// Browser client for the Voice Live bridge.
//
// Pipeline:
//   mic --(AudioWorklet, 24 kHz PCM16)--> ws --> bridge --> Voice Live
//   Voice Live --(audio deltas, base64 PCM16 24 kHz)--> bridge --> ws --> speaker

const SAMPLE_RATE = 24000;

const toggle = document.getElementById("toggle");
const statusEl = document.getElementById("status");
const transcript = document.getElementById("transcript");

let ws = null;
let audioCtx = null;
let micStream = null;
let workletNode = null;
let playCursor = 0;

function setStatus(text) {
    statusEl.textContent = text;
}

function appendTurn(who, text) {
    const div = document.createElement("div");
    div.className = `turn ${who}`;
    const label = document.createElement("div");
    label.className = "who";
    label.textContent = who === "user" ? "You" : "IT Assistant";
    const body = document.createElement("div");
    body.textContent = text;
    div.appendChild(label);
    div.appendChild(body);
    transcript.appendChild(div);
    transcript.scrollTop = transcript.scrollHeight;
}

// ----- PCM conversion helpers -----

function base64ToArrayBuffer(b64) {
    const raw = atob(b64);
    const len = raw.length;
    const buf = new Uint8Array(len);
    for (let i = 0; i < len; i++) buf[i] = raw.charCodeAt(i);
    return buf.buffer;
}

function arrayBufferToBase64(buf) {
    let binary = "";
    const bytes = new Uint8Array(buf);
    for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
    return btoa(binary);
}

function float32ToPCM16(float32Array) {
    const buf = new ArrayBuffer(float32Array.length * 2);
    const view = new DataView(buf);
    for (let i = 0; i < float32Array.length; i++) {
        let s = Math.max(-1, Math.min(1, float32Array[i]));
        view.setInt16(i * 2, s < 0 ? s * 0x8000 : s * 0x7fff, true);
    }
    return buf;
}

function pcm16ToFloat32(buf) {
    const view = new DataView(buf);
    const out = new Float32Array(buf.byteLength / 2);
    for (let i = 0; i < out.length; i++) {
        out[i] = view.getInt16(i * 2, true) / 0x8000;
    }
    return out;
}

// ----- Audio playback (schedule deltas back-to-back) -----

function schedulePlayback(float32Array) {
    const buffer = audioCtx.createBuffer(1, float32Array.length, SAMPLE_RATE);
    buffer.copyToChannel(float32Array, 0);
    const src = audioCtx.createBufferSource();
    src.buffer = buffer;
    src.connect(audioCtx.destination);
    const startAt = Math.max(audioCtx.currentTime, playCursor);
    src.start(startAt);
    playCursor = startAt + buffer.duration;
}

function cancelPlayback() {
    // Smash the cursor to "now" so scheduled buffers still play but nothing new queues behind.
    playCursor = audioCtx.currentTime;
}

// ----- Mic capture via AudioWorklet (writes every 40 ms) -----

const WORKLET_SRC = `
class PcmWriter extends AudioWorkletProcessor {
    constructor() {
        super();
        this._buf = [];
        this._frames = 0;
    }
    process(inputs) {
        const input = inputs[0];
        if (!input || !input[0]) return true;
        const ch = input[0];
        this._buf.push(new Float32Array(ch));
        this._frames += ch.length;
        // Flush every ~40 ms (at 24 kHz that's 960 frames)
        if (this._frames >= 960) {
            const merged = new Float32Array(this._frames);
            let o = 0;
            for (const b of this._buf) { merged.set(b, o); o += b.length; }
            this._buf = [];
            this._frames = 0;
            this.port.postMessage(merged, [merged.buffer]);
        }
        return true;
    }
}
registerProcessor("pcm-writer", PcmWriter);
`;

async function registerWorklet(ctx) {
    const blob = new Blob([WORKLET_SRC], { type: "application/javascript" });
    const url = URL.createObjectURL(blob);
    await ctx.audioWorklet.addModule(url);
    URL.revokeObjectURL(url);
}

// ----- Event loop -----

async function start() {
    toggle.disabled = true;
    setStatus("Requesting microphone…");

    try {
        micStream = await navigator.mediaDevices.getUserMedia({
            audio: {
                channelCount: 1,
                sampleRate: SAMPLE_RATE,
                echoCancellation: true,
                noiseSuppression: true,
            },
        });
    } catch (e) {
        setStatus("Microphone access denied.");
        toggle.disabled = false;
        return;
    }

    audioCtx = new AudioContext({ sampleRate: SAMPLE_RATE });
    await registerWorklet(audioCtx);
    playCursor = audioCtx.currentTime;

    const src = audioCtx.createMediaStreamSource(micStream);
    workletNode = new AudioWorkletNode(audioCtx, "pcm-writer");
    src.connect(workletNode);
    // don't route worklet output to speakers; only use it as a tap

    setStatus("Connecting…");
    const wsUrl = (location.protocol === "https:" ? "wss://" : "ws://") + location.host + "/ws/voice";
    ws = new WebSocket(wsUrl);

    ws.onopen = () => {
        setStatus("Connected. Start talking.");
        toggle.textContent = "Stop";
        toggle.setAttribute("data-state", "live");
        toggle.disabled = false;

        workletNode.port.onmessage = (evt) => {
            if (!ws || ws.readyState !== WebSocket.OPEN) return;
            const pcm16 = float32ToPCM16(evt.data);
            ws.send(JSON.stringify({
                type: "input_audio_buffer.append",
                audio: arrayBufferToBase64(pcm16),
            }));
        };
    };

    ws.onmessage = (evt) => {
        let msg;
        try { msg = JSON.parse(evt.data); } catch { return; }
        switch (msg.type) {
            case "session.updated":
                setStatus("Session ready.");
                break;
            case "response.audio.delta":
                if (msg.delta) {
                    const pcm = pcm16ToFloat32(base64ToArrayBuffer(msg.delta));
                    schedulePlayback(pcm);
                }
                break;
            case "response.audio_transcript.delta":
                // Incremental assistant transcript — could be streamed to the UI.
                break;
            case "response.audio_transcript.done":
                if (msg.transcript) appendTurn("assistant", msg.transcript);
                break;
            case "conversation.item.input_audio_transcription.completed":
                if (msg.transcript) appendTurn("user", msg.transcript);
                break;
            case "input_audio_buffer.speech_started":
                cancelPlayback(); // user barged in
                break;
            case "error":
                console.error("voice-live error", msg);
                setStatus("Error: " + (msg.error?.message || "unknown"));
                break;
        }
    };

    ws.onclose = () => {
        setStatus("Disconnected.");
        cleanup();
    };

    ws.onerror = () => setStatus("Connection error.");
}

function cleanup() {
    if (ws) { try { ws.close(); } catch {} ws = null; }
    if (workletNode) { try { workletNode.disconnect(); } catch {} workletNode = null; }
    if (micStream) { micStream.getTracks().forEach((t) => t.stop()); micStream = null; }
    if (audioCtx) { try { audioCtx.close(); } catch {} audioCtx = null; }
    toggle.textContent = "Start talking";
    toggle.setAttribute("data-state", "idle");
    toggle.disabled = false;
}

toggle.addEventListener("click", () => {
    if (toggle.getAttribute("data-state") === "live") {
        cleanup();
        setStatus("Stopped.");
    } else {
        start();
    }
});
