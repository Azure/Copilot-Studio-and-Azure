# 03 — Advanced troubleshooting (Copilot Studio portal)

You're integrating Copilot Studio with the broader Azure AI stack: **MCP tools, custom / fine-tuned models, Azure AI Search, Foundry IQ agentic retrieval, generative orchestration, and prompt / instruction tuning**. Issues here usually span multiple services, so the diagnostic loop is more involved.

> [!IMPORTANT]
> Advanced issues almost always require **correlated telemetry** across Copilot Studio, Power Automate, and the underlying Azure resources. Before you dig in, make sure [Application Insights](./00-diagnostic-toolbox.md#3-application-insights) is wired up and you can search by conversation id.

## How to diagnose this area

1. **Reproduce in the [Test pane](./00-diagnostic-toolbox.md#1-test-pane)** and capture the conversation id.
2. **Open the [Activity map](./00-diagnostic-toolbox.md#2-activity-map)** for the failing turn and click **Show rationale** on the suspect step — this is where most "the agent picked the wrong tool / model / source" issues are visible.
3. **Open [Application Insights](./00-diagnostic-toolbox.md#3-application-insights)** and pivot from the conversation id to the dependency calls (AI Search, Foundry, MCP server, custom model endpoint).
4. **Inspect the dependency** at its source (AI Search query, Foundry agent run, MCP server logs, fine-tuned deployment metrics).
5. **Iterate on instructions / prompts** *only after* the data flow above is verified — otherwise you'll be tuning prompts to compensate for a broken integration.

<!--
Source: optional screenshot showing orchestrator trace + App Insights dependency chart side by side.
Filename: images/03-advanced-diagnostic-flow.png
-->

## Deep-dive: parsing a snapshot with Copilot Studio Trace Viewer

The [Test pane snapshot](./00-diagnostic-toolbox.md#download-a-test-pane-snapshot) you downloaded is a `botContent.zip` containing two files:

| File | What it is |
|---|---|
| `dialog.json` | The full orchestrator trace for the conversation: every activity, plan, tool call, knowledge lookup, AI thought, and response. |
| `botContent.yml` | The agent's definition: topics, tools, instructions, variables, connectors, GPT settings. |

Reading `dialog.json` by hand is doable for a single turn but quickly becomes painful. The community-built **[Copilot Studio Trace Viewer](https://github.com/rquattros/CopilotStudioTraceViewer)** parses the snapshot and gives you, in a single offline page (no install, no server, no dependency):

- **Activity timeline** colour-coded by type (user/bot message, plan, thought, tool call, search, error) with the agent's full plan tree.
- **Friendly topic / tool names** resolved from `botContent.yml` (instead of raw schema GUIDs).
- **Performance waterfall** to spot the slow step (often a tool call or AI Search).
- **Knowledge Sources panel** \u2014 search results, query rewrites, citation mapping, token counts, model name, for any `GenerativeAnswersSupportData` activity.
- **Variable Tracker** \u2014 inputs/outputs of every step with AUTO/MANUAL binding badges.
- **Topic Flow** diagram of orchestrator plans, topic invocations, and connected-agent / Foundry handoffs.
- **Error banner** that surfaces every error/exception in the trace and jumps you to the failing step.

**Typical workflow:**

1. Reproduce the failing turn in the Test pane and **Save snapshot** (see the [toolbox steps](./00-diagnostic-toolbox.md#download-a-test-pane-snapshot)).
2. Open the Trace Viewer (clone the repo and open `index.html`, or use a hosted copy you trust).
3. Drag the `botContent.zip` (or just `dialog.json`) onto the page.
4. Start with the **Error banner** \u2192 jump to the failing step \u2192 inspect the **Knowledge Sources** / **Variable Tracker** / **Topic Flow** for that turn.
5. Pair what you see with the conversation id from `/debug conversationId` and your [App Insights](./00-diagnostic-toolbox.md#3-application-insights) query for the same turn.

> [!IMPORTANT]
> The Trace Viewer is a **community project**, not a Microsoft product. The snapshot you upload is parsed entirely **in your browser** \u2014 nothing is sent to a server \u2014 but the underlying file still contains user messages, variable values, and tool outputs. Treat it as sensitive (see the [toolbox sensitivity note](./00-diagnostic-toolbox.md#00--diagnostic-toolbox)) and never paste it into untrusted hosted instances.

The same tool can also load **channel transcripts directly from Dataverse** (Teams, Web Chat, DirectLine, etc.) via an Entra app registration \u2014 useful when the issue only reproduces in a real channel and not in the Test pane. See the project README for the one-time Azure / Dataverse setup.

## Reading a HAR / network trace

Once you can capture a HAR (see [Diagnostic toolbox §4](./00-diagnostic-toolbox.md#4-browser-network-trace-har)), the value is in **what you do with it**. Use this section when:

- You've reproduced an issue, captured a HAR, and need to know **what to look for**.
- A support / engineering contact has asked you to share a HAR + correlation ids.
- The portal returns a generic error and you need to identify the **first failing request** in a chain.

### Signals to scan for first

| Signal | What it usually means | Where to check |
|---|---|---|
| **HTTP 401 / 403** on a Copilot Studio API call | Auth or RBAC problem (token expired, missing role on environment, conditional access). | Cross-check with [02 — Intermediate § I3 Connector returns 401 / 403](./02-intermediate.md#i3--connector-returns-401--403). |
| **HTTP 404** on an environment-scoped URL | Wrong environment selected, or the resource was deleted / moved. | Look for the environment id (GUID) in the request URL. |
| **HTTP 429** | Throttling. | Slow the action down; check capacity in [PPAC](./00-diagnostic-toolbox.md#power-platform-admin-center-ppac). |
| **HTTP 5xx** | Service-side issue. | Capture the `x-ms-correlation-id` / `x-ms-request-id` response header — it's what support will ask for. |
| **CORS errors** in the Console tab | Tenant policy, browser extension, or a third-party domain blocked. | Retry in InPrivate with extensions disabled. |
| **Request never sent** (no row appears) | Browser extension, content-blocker, or network policy intercepted the click. | Retry in InPrivate, then on a clean network. |

### Triage workflow

1. **Filter** the request list to `XHR` / `Fetch` and sort by **status code** descending — failed requests bubble to the top.
2. Find the **first** failing request in time order. Later failures are often cascading effects of the first one.
3. Open that request and capture:
   - **Request URL** (note the environment id GUID and any resource id).
   - **Status code** + **status text**.
   - Response headers `x-ms-correlation-id`, `x-ms-request-id`, `request-id` — these are the ids support uses to find the same request in service logs.
   - **Response body** preview if present.
4. If the failing request is an **auth / token** call (`/oauth2/`, `/.default`, `login.microsoftonline.com`), the root cause is identity, not Copilot Studio — escalate accordingly.
5. If multiple environments are involved, confirm **all GUIDs in the URLs match** the environment you think you're in.

### Correlate with conversation telemetry

If the failing action is a **conversation turn** (not a portal click):

1. Grab the conversation id with `/debug conversationId` in the [Test pane](./00-diagnostic-toolbox.md#1-test-pane) **before** triggering the failure.
2. Capture the HAR for the next turn.
3. In [Application Insights](./00-diagnostic-toolbox.md#3-application-insights), filter by that conversation id and align the `x-ms-correlation-id` from the HAR to the matching dependency call. You now have the **same failure visible from both client and server side**.

> [!IMPORTANT]
> A HAR contains tokens and cookies. Always **redact or sanitize** before sharing — open the file in a text editor and remove `Authorization`, `Cookie`, and any obvious user identifiers before attaching it to a ticket or pasting it anywhere.

<!--
Screenshot suggestions:
- images/03-advanced-har-failed-request.png (failed request expanded with correlation id and response body annotated)
- images/03-advanced-har-correlation-appinsights.png (HAR correlation id matched in App Insights query result)
-->

## Common issues at a glance

| # | Symptom | Likely cause | Jump to |
|---|---------|--------------|---------|
| A1 | Generative orchestrator picks the wrong tool / topic | Tool / topic descriptions, instructions, ordering | [A1](#a1--orchestrator-picks-the-wrong-tool) |
| A2 | MCP tool call fails or returns nothing | MCP server registration, auth, schema | [A2](#a2--mcp-tool-call-fails) |
| A3 | Azure AI Search returns no / poor results | Index design, query type, semantic config, scoring | [A3](#a3--azure-ai-search-returns-poor-results) |
| A4 | Foundry IQ agentic retrieval returns empty / wrong sources | Knowledge base scoping, permissions, source routing | [A4](#a4--foundry-iq-agentic-retrieval-issues) |
| A5 | Custom / fine-tuned model returns errors or off-style answers | Deployment, capacity, prompt drift, dataset quality | [A5](#a5--custom-or-fine-tuned-model-issues) |
| A6 | Citations are missing or wrong | Grounding off, source not citation-capable, post-processing | [A6](#a6--citations-missing-or-wrong) |
| A7 | High latency / timeouts on generative answers | Model region, payload size, dependency latency | [A7](#a7--high-latency-or-timeouts) |
| A8 | Inconsistent answers across runs | Temperature, non-deterministic tools, retrieval variance | [A8](#a8--inconsistent-answers-across-runs) |
| A9 | Long Teams conversations stop responding / loop | Conversation history exceeds the model's context window | [A9](#a9--long-teams-conversations-stop-responding--loop-token-limit) |

---

## A1 — Orchestrator picks the wrong tool

<!--
Source brief — please provide:
- Symptom: user asks X → agent calls tool Y instead of expected tool / topic.
- Reproduce in Test pane: yes — capture the trace.
- Likely causes:
  - Tool / topic description is vague or overlapping.
  - Agent instructions don't disambiguate.
  - Two tools have similar names; orchestrator picks the first match.
- Step-by-step fix:
  1. Open the Activity map and click **Show rationale** on the failing step (toolbox §2).
  2. Read "candidate tools" + "selected tool + reason".
  3. Tighten the description and / or add disambiguating instructions.
  4. Re-test.
- Verify: trace shows the expected tool selected with a clear reason.
- Screenshots:
  - images/03-advanced-a1-trace-wrong-tool.png
  - images/03-advanced-a1-tool-description-edit.png
- Related links: Lab 1.2 Tools, Lab 1.3 MCP.
-->

## A2 — MCP tool call fails

<!--
Source brief — please provide:
- Symptom: MCP-backed tool returns an error, empty result, or "tool not available".
- Likely causes:
  - MCP server not reachable from the agent's network path.
  - Auth (API key / OAuth) misconfigured.
  - Tool schema (input/output) mismatch.
  - MCP server version/feature mismatch.
- Step-by-step fix.
- Verify: round-trip succeeds in Test pane and App Insights shows a successful dependency call.
- Screenshots:
  - images/03-advanced-a2-mcp-tool-error.png
  - images/03-advanced-a2-mcp-server-logs.png
- Related links:
  - Lab 1.3 MCP: ../../labs/1.3-MCP/1.3-MCP.md
-->

## A3 — Azure AI Search returns poor results

<!--
Source brief — please provide:
- Symptom: agent answer is generic, unrelated, or grounded on the wrong document.
- Likely causes:
  - Index design (chunk size, fields, vector vs. keyword).
  - Query type (simple vs. semantic vs. hybrid).
  - Missing semantic configuration.
  - Scoring profile / freshness boost missing.
- Step-by-step fix:
  1. Reproduce the same query directly in the AI Search Explorer in Azure portal.
  2. Compare results to what the agent received.
  3. Adjust query type / semantic config / chunking; re-index if needed.
- Verify: same question in Test pane returns a relevant, well-grounded answer with the right citation.
- Screenshots:
  - images/03-advanced-a3-search-explorer.png
  - images/03-advanced-a3-semantic-config.png
- Related links:
  - Lab 1.4: ../../labs/1.4-ai-search/1.4-ai-search.md
  - Lab 2.1: ../../labs/2.1-ai-search-advanced/2.1-ai-search-advanced.md
  - Lab 2.3: ../../labs/2.3-ai-search-sharepoint-indexer/
-->

## A4 — Foundry IQ agentic retrieval issues

<!--
Source brief — please provide:
- Symptom: agentic retrieval returns empty, wrong source, or only one of the configured KBs.
- Likely causes:
  - Knowledge base not scoped / permissioned for the calling identity.
  - Source routing rules too narrow.
  - Foundry agent / project misconfiguration.
- Step-by-step fix:
  1. Run the same query directly against the Foundry agent (outside Copilot Studio).
  2. Inspect the planning + retrieval trace in the Foundry project.
  3. Adjust scoping / permissions / routing.
- Verify: the same question in Test pane returns the expected source(s) with citations.
- Screenshots:
  - images/03-advanced-a4-foundry-trace.png
  - images/03-advanced-a4-knowledge-base-config.png
- Related links:
  - Lab 2.4: ../../labs/2.4-microsoft-foundry-agentic-retrieval/README.md
-->

## A5 — Custom or fine-tuned model issues

<!--
Source brief — please provide:
- Symptom: deployment errors, throttling, or the model's tone / format drifted from training data.
- Likely causes:
  - Deployment region / capacity (PTU / TPM limits).
  - Wrong deployment name selected in Copilot Studio.
  - Training data drift / overfitting.
- Step-by-step fix.
- Verify: model returns expected style and stays under latency budget.
- Screenshots:
  - images/03-advanced-a5-model-deployment.png
- Related links:
  - Lab 1.5: ../../labs/1.5-custom-models/1.5-custom-models.md
  - Lab 2.2: ../../labs/2.2-Fine-Tunned-Model/Lab2_CopilotStudio_Text_FineTuned_Model_AzureAIFoundry_PromptTool.md
-->

## A6 — Citations missing or wrong

<!--
Source brief — please provide:
- Symptom: answer is correct but cites the wrong source, or cites nothing.
- Likely causes: grounding turned off, source not configured to return citations, post-processing strips them.
- Step-by-step fix.
- Verify: every grounded answer in Test pane has the correct citation.
- Screenshots:
  - images/03-advanced-a6-citation-toggle.png
-->

## A7 — High latency or timeouts

<!--
Source brief — please provide:
- Symptom: turns take > 8s or hit a timeout.
- Likely causes:
  - Model region far from data region.
  - Large payloads (full documents instead of chunks).
  - Slow downstream dependency (AI Search, MCP server, flow).
- Step-by-step fix:
  1. In App Insights, break down dependency latency for the failing turn.
  2. Identify the slowest dependency and tune it (region, payload, indexing).
- Verify: median turn latency back under target.
- Screenshots:
  - images/03-advanced-a7-latency-breakdown.png
- Related links:
  - Lab 1.7: ../../labs/1.7-monitoring/1.7.1-monitor-agent-with-application-insights.md
-->

## A8 — Inconsistent answers across runs

<!--
Source brief — please provide:
- Symptom: same question, different answers across attempts.
- Likely causes: temperature too high, retrieval order changes, tools with non-deterministic outputs.
- Step-by-step fix:
  1. Lower temperature / pin model version in instructions.
  2. Confirm retrieval is deterministic for the same query (top-k stable).
  3. Add evaluation set to detect regressions.
- Verify: 5 consecutive runs return the same grounded answer.
- Screenshots:
  - images/03-advanced-a8-instructions-tuning.png
-->

## A9 — Long Teams conversations stop responding / loop (token limit)

**Symptom.** A long-running conversation in **Microsoft Teams** suddenly stops producing useful answers. The agent may keep "thinking" forever, return errors, or appear to loop. The same agent works fine for **short** conversations (and in the Test pane).

**Reproduce in Test pane.** Often **not** reproducible — the Test pane is usually a short, fresh conversation, while the failing Teams session has a long history. Try to reproduce by simulating a long history (paste prior turns) before deciding it's channel-only.

**Likely causes.**

- The **accumulated conversation history exceeds the model's context window (token limit)**. Once the prompt + history + tools metadata + grounded content overflows, the model fails or behaves erratically.
- This is more likely on agents using **older / smaller-context models** or with very verbose tool / knowledge outputs.

**Step-by-step fix.**

1. **Confirm it's history-driven**: ask the user to start a **new chat** in Teams. If the issue disappears, it's a context-window problem.
2. **Reduce per-turn payload size**:
   - Trim long system instructions; move static content to knowledge sources instead of instructions.
   - For tools, return the smallest useful payload (project the fields you need, not the whole record).
   - For knowledge, prefer **chunked retrieval with citations** over passing whole documents.
3. **Use a model with a larger context window** for that agent if available.
4. **Plan for history compaction**: newer Copilot Studio runtime versions can compact older turns automatically for newer models. Keep the agent on the latest model and runtime to benefit from this.
5. As a workaround for affected users, advise them to **start a new Teams chat** for unrelated topics rather than continuing one long thread.

**Verify.** A long simulated conversation no longer fails; per-turn token counts (visible in [Application Insights](./00-diagnostic-toolbox.md#3-application-insights)) stay comfortably below the model limit.

**Related links.**

- [A7 — High latency or timeouts](#a7--high-latency-or-timeouts) (often correlated with large payloads).
- [Lab 1.5 — Custom models](../../labs/1.5-custom-models/1.5-custom-models.md).

<!--
Screenshot suggestions:
- images/03-advanced-a9-teams-long-conversation-error.png
- images/03-advanced-a9-token-usage-appinsights.png
-->

---

## Where to next

- Refresher on the diagnostic tools → [00 — Diagnostic toolbox](./00-diagnostic-toolbox.md)
- Back to the [troubleshooting index](./README.md)
