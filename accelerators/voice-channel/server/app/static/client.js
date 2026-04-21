// Browser client for the Voice Channel server.
// Streams mic audio as base64 PCM16 over the /api/voice WebSocket; plays
// response audio deltas back scheduled to the Web Audio clock.

const SAMPLE_RATE = 24000;

const toggle      = document.getElementById("toggle");
const statusEl    = document.getElementById("status");
const hintEl      = document.getElementById("hint");
const turnsEl     = document.getElementById("turns");
const modeTagEl   = document.getElementById("mode-tag");
const subtitleEl  = document.getElementById("subtitle");
const meterMic    = document.getElementById("meter-mic").getContext("2d");
const meterAgent  = document.getElementById("meter-agent").getContext("2d");

let ws = null;
let audioCtx = null;
let micStream = null;
let workletNode = null;
let analyserMic = null;
let playCursor = 0;
let currentAgentTurn = null;   // DOM node being streamed into
let currentUserTurn = null;
let cfg = {};

// ─── Startup ───────────────────────────────────────────────────────────

fetch("/api/config").then(r => r.json()).then(c => {
    cfg = c;
    subtitleEl.textContent = `Answers come from "${c.mcsAgentName}" via the Microsoft Learn MCP server.`;
    modeTagEl.textContent = c.mode === "agent"
        ? "mode: agent (Foundry IT Assistant)"
        : `mode: model (${c.model})`;
}).catch(() => {
    modeTagEl.textContent = "mode: ?";
});

// ─── UI helpers ────────────────────────────────────────────────────────

function setStatus(label, kind = "") {
    statusEl.textContent = label;
    statusEl.className = "status-pill" + (kind ? ` ${kind}` : "");
}

function setHint(text) { hintEl.textContent = text; }

function startTurn(role) {
    const div = document.createElement("div");
    div.className = `turn ${role} pending`;
    const who = document.createElement("div");
    who.className = "who";
    who.textContent = role === "user" ? "You" : "IT Assistant";
    const body = document.createElement("div");
    body.className = "body";
    div.appendChild(who);
    div.appendChild(body);
    turnsEl.appendChild(div);
    turnsEl.scrollTop = turnsEl.scrollHeight;
    return div;
}

function appendToTurn(turnDiv, text) {
    if (!turnDiv) return;
    const body = turnDiv.querySelector(".body");
    body.textContent += text;
    turnsEl.scrollTop = turnsEl.scrollHeight;
}

function finalizeTurn(turnDiv, text) {
    if (!turnDiv) return;
    turnDiv.classList.remove("pending");
    if (text !== undefined && text !== null) {
        turnDiv.querySelector(".body").textContent = text;
    }
    turnsEl.scrollTop = turnsEl.scrollHeight;
}

// ─── Audio conversion helpers ──────────────────────────────────────────

function base64ToArrayBuffer(b64) {
    const raw = atob(b64);
    const len = raw.length;
    const buf = new Uint8Array(len);
    for (let i = 0; i < len; i++) buf[i] = raw.charCodeAt(i);
    return buf.buffer;
}
function arrayBufferToBase64(buf) {
    let s = "";
    const bytes = new Uint8Array(buf);
    for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
    return btoa(s);
}
function float32ToPCM16(f32) {
    const buf = new ArrayBuffer(f32.length * 2);
    const view = new DataView(buf);
    for (let i = 0; i < f32.length; i++) {
        let s = Math.max(-1, Math.min(1, f32[i]));
        view.setInt16(i * 2, s < 0 ? s * 0x8000 : s * 0x7fff, true);
    }
    return buf;
}
function pcm16ToFloat32(buf) {
    const view = new DataView(buf);
    const out = new Float32Array(buf.byteLength / 2);
    for (let i = 0; i < out.length; i++) out[i] = view.getInt16(i * 2, true) / 0x8000;
    return out;
}

// ─── Playback: schedule deltas back-to-back on the Web Audio clock ─────

function schedulePlayback(f32) {
    const buf = audioCtx.createBuffer(1, f32.length, SAMPLE_RATE);
    buf.copyToChannel(f32, 0);
    const src = audioCtx.createBufferSource();
    src.buffer = buf;
    src.connect(audioCtx.destination);
    const startAt = Math.max(audioCtx.currentTime, playCursor);
    src.start(startAt);
    playCursor = startAt + buf.duration;
    // feed the agent meter
    feedAgentMeter(f32);
}

function cancelPlayback() { if (audioCtx) playCursor = audioCtx.currentTime; }

// ─── Meters ────────────────────────────────────────────────────────────

function drawMeter(ctx, level) {
    const w = ctx.canvas.width, h = ctx.canvas.height;
    ctx.clearRect(0, 0, w, h);
    ctx.fillStyle = "#0078d4";
    const bars = 30;
    const gap = 2;
    const barW = (w - (bars - 1) * gap) / bars;
    for (let i = 0; i < bars; i++) {
        const active = i < Math.round(level * bars);
        const barH = active ? (0.3 + (i / bars) * 0.7) * h : 3;
        ctx.fillStyle = active ? (i < bars * 0.7 ? "#0078d4" : "#d13438") : "#edebe9";
        ctx.fillRect(i * (barW + gap), (h - barH) / 2, barW, barH);
    }
}

let agentLevel = 0;
function feedAgentMeter(f32) {
    let sum = 0;
    for (let i = 0; i < f32.length; i++) sum += f32[i] * f32[i];
    agentLevel = Math.min(1, Math.sqrt(sum / f32.length) * 3);
    drawMeter(meterAgent, agentLevel);
}

function tickMicMeter() {
    if (!analyserMic) return;
    const data = new Uint8Array(analyserMic.fftSize);
    analyserMic.getByteTimeDomainData(data);
    let sum = 0;
    for (let i = 0; i < data.length; i++) {
        const v = (data[i] - 128) / 128;
        sum += v * v;
    }
    drawMeter(meterMic, Math.min(1, Math.sqrt(sum / data.length) * 3));
    requestAnimationFrame(tickMicMeter);
}

// ─── AudioWorklet: tap mic at 24 kHz mono, post PCM blocks to main thread

const WORKLET_SRC = `
class PcmWriter extends AudioWorkletProcessor {
    constructor() { super(); this._buf = []; this._n = 0; }
    process(inputs) {
        const input = inputs[0];
        if (!input || !input[0]) return true;
        const ch = input[0];
        this._buf.push(new Float32Array(ch));
        this._n += ch.length;
        if (this._n >= 960) { // ~40 ms at 24 kHz
            const merged = new Float32Array(this._n);
            let o = 0;
            for (const b of this._buf) { merged.set(b, o); o += b.length; }
            this._buf = []; this._n = 0;
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

// ─── Session ───────────────────────────────────────────────────────────

async function start() {
    toggle.disabled = true;
    toggle.setAttribute("data-state", "connecting");
    setStatus("Connecting", "connecting");
    setHint("Waiting for microphone permission…");

    try {
        micStream = await navigator.mediaDevices.getUserMedia({
            audio: { channelCount: 1, sampleRate: SAMPLE_RATE, echoCancellation: true, noiseSuppression: true },
        });
    } catch (_) {
        setStatus("Mic blocked", "error");
        setHint("Allow microphone access and try again.");
        toggle.setAttribute("data-state", "idle");
        toggle.disabled = false;
        return;
    }

    audioCtx = new AudioContext({ sampleRate: SAMPLE_RATE });
    await registerWorklet(audioCtx);
    playCursor = audioCtx.currentTime;

    const src = audioCtx.createMediaStreamSource(micStream);
    analyserMic = audioCtx.createAnalyser();
    analyserMic.fftSize = 512;
    src.connect(analyserMic);
    workletNode = new AudioWorkletNode(audioCtx, "pcm-writer");
    src.connect(workletNode);
    requestAnimationFrame(tickMicMeter);

    const wsUrl = (location.protocol === "https:" ? "wss://" : "ws://") + location.host + "/api/voice";
    ws = new WebSocket(wsUrl);

    ws.onopen = () => {
        setStatus("Live", "live");
        setHint("Speak naturally. The agent will interrupt you politely if it has something to add.");
        toggle.textContent = "";
        toggle.insertAdjacentHTML("afterbegin",
            '<span class="talk-icon"></span><span class="talk-label">Stop</span>');
        toggle.setAttribute("data-state", "live");
        toggle.disabled = false;

        workletNode.port.onmessage = (evt) => {
            if (!ws || ws.readyState !== WebSocket.OPEN) return;
            const pcm = float32ToPCM16(evt.data);
            ws.send(JSON.stringify({
                type: "input_audio_buffer.append",
                audio: arrayBufferToBase64(pcm),
            }));
        };
    };

    ws.onmessage = (evt) => {
        let msg;
        try { msg = JSON.parse(evt.data); } catch { return; }
        handleEvent(msg);
    };

    ws.onerror = () => setStatus("Error", "error");
    ws.onclose = () => {
        setStatus("Idle");
        cleanup();
    };
}

function handleEvent(msg) {
    switch (msg.type) {
        case "session.updated":
            setHint("Ready — say hello.");
            break;

        case "input_audio_buffer.speech_started":
            cancelPlayback();
            if (currentAgentTurn) finalizeTurn(currentAgentTurn);
            currentAgentTurn = null;
            if (!currentUserTurn) currentUserTurn = startTurn("user");
            break;

        case "conversation.item.input_audio_transcription.completed":
            if (msg.transcript) {
                if (!currentUserTurn) currentUserTurn = startTurn("user");
                finalizeTurn(currentUserTurn, msg.transcript);
            }
            currentUserTurn = null;
            break;

        case "response.audio.delta":
            if (msg.delta) schedulePlayback(pcm16ToFloat32(base64ToArrayBuffer(msg.delta)));
            if (!currentAgentTurn) currentAgentTurn = startTurn("agent");
            break;

        case "response.audio_transcript.delta":
            if (!currentAgentTurn) currentAgentTurn = startTurn("agent");
            appendToTurn(currentAgentTurn, msg.delta || "");
            break;

        case "response.audio_transcript.done":
            finalizeTurn(currentAgentTurn, msg.transcript);
            currentAgentTurn = null;
            break;

        case "response.done":
            if (currentAgentTurn) { finalizeTurn(currentAgentTurn); currentAgentTurn = null; }
            break;

        case "error":
            setStatus("Error", "error");
            setHint(msg.error?.message || "Unknown Voice Live error");
            break;
    }
}

function cleanup() {
    if (ws)         { try { ws.close(); } catch {} ws = null; }
    if (workletNode){ try { workletNode.disconnect(); } catch {} workletNode = null; }
    if (micStream)  { micStream.getTracks().forEach(t => t.stop()); micStream = null; }
    if (audioCtx)   { try { audioCtx.close(); } catch {} audioCtx = null; }
    analyserMic = null;
    drawMeter(meterMic, 0);
    drawMeter(meterAgent, 0);
    toggle.innerHTML = '<span class="talk-icon"></span><span class="talk-label">Start talking</span>';
    toggle.setAttribute("data-state", "idle");
    toggle.disabled = false;
    if (currentAgentTurn) { finalizeTurn(currentAgentTurn); currentAgentTurn = null; }
    if (currentUserTurn)  { finalizeTurn(currentUserTurn);  currentUserTurn  = null; }
}

toggle.addEventListener("click", () => {
    if (toggle.getAttribute("data-state") === "live") {
        cleanup();
        setStatus("Idle");
        setHint("Click the button to start another conversation.");
    } else if (toggle.getAttribute("data-state") === "idle") {
        start();
    }
});

// Draw an empty meter at load
drawMeter(meterMic, 0);
drawMeter(meterAgent, 0);
