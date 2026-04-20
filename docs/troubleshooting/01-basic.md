# 01 — Basic troubleshooting (Copilot Studio portal)

The **day-1 issues** every maker hits while authoring an agent in the Copilot Studio portal. If you're new here, start at the top and work down.

> [!TIP]
> **Reproduce in the [Test pane](./00-diagnostic-toolbox.md#1-test-pane) first.** If the issue does not reproduce there, jump straight to [Channels troubleshooting](./README.md#how-this-guide-is-organized).

## How to diagnose this area

A short, repeatable diagnostic flow for basic issues — applied with tools from the [Diagnostic toolbox](./00-diagnostic-toolbox.md).

1. **Reproduce in the Test pane.** Open a fresh conversation (refresh icon) and try the exact user input that fails.
2. **Open the [Activity map](./00-diagnostic-toolbox.md#2-activity-map)** for that conversation. Confirm whether the expected topic / knowledge call was triggered at all.
3. **Inspect variables** at the failing turn. Most basic issues are an empty / wrong variable, not a logic bug.
4. **Check the agent's publish state.** Many "it doesn't work" reports are simply unpublished changes.
5. **Check licensing / environment** in the [Power Platform Admin Center](./00-diagnostic-toolbox.md#power-platform-admin-center-ppac) only if steps 1–4 don't explain the symptom.

<!--
Source: optional screenshot showing the diagnostic flow inside the portal
(Test pane open, Activity map open side-by-side).
Filename: images/01-basic-diagnostic-flow.png
-->

## Common issues at a glance

| # | Symptom | Likely cause | Jump to |
|---|---------|--------------|---------|
| B1 | Can't sign in to Copilot Studio / no environments listed | Licensing / wrong tenant / wrong environment | [B1](#b1--cant-sign-in-or-no-environments-listed) |
| B2 | "Save" or "Publish" fails | Validation errors, missing required fields, environment capacity | [B2](#b2--save-or-publish-fails) |
| B3 | Topic does not trigger on expected user input | Trigger phrases, generative orchestration choosing another path | [B3](#b3--topic-does-not-trigger) |
| B4 | Generative answers return empty / "I don't know" | No / wrong knowledge sources, scoping, indexing | [B4](#b4--generative-answers-return-empty) |
| B5 | Knowledge source returns wrong / stale results | Indexing, source freshness, scoping | [B5](#b5--knowledge-source-returns-wrong-results) |
| B6 | Test pane shows an error message at runtime | Variable not set, action failed, missing connection | [B6](#b6--test-pane-shows-a-runtime-error) |
| B7 | "Publish not allowed" after editing Teams / M365 Copilot channel settings | Channel/auth state out of sync after recent change | [B7](#b7--publish-not-allowed-after-teams--m365-copilot-channel-changes) |

---

## B1 — Can't sign in or no environments listed

<!--
Source brief — please provide:
- Symptom: exact text users see (e.g. "You don't have access to Copilot Studio").
- Reproduce in Test pane: N/A (pre-portal issue) — describe how to confirm in Microsoft 365 admin center / PPAC instead.
- Likely causes: missing license, signed in with wrong tenant, environment is in another region, conditional access.
- Step-by-step fix:
  1. Verify the signed-in account in the top-right of copilotstudio.microsoft.com.
  2. Switch environment using the environment picker (top bar).
  3. Confirm a Copilot Studio license is assigned (link to Lab 0.1).
- Verify: user lands on the agents list page.
- Screenshots:
  - images/01-basic-b1-account-picker.png
  - images/01-basic-b1-environment-picker.png
- Related links:
  - Lab 0.1 (licensing / PAYG): ../../labs/0.1-enable-payg/0.1-enable-payg.md
-->

## B2 — Save or Publish fails

<!--
Source brief — please provide:
- Symptom: error banner text(s) on Save / Publish.
- Reproduce in Test pane: N/A — this is an authoring action.
- Likely causes:
  - Validation errors highlighted on a topic node.
  - Missing required field on a tool / connector.
  - Environment over capacity / DLP block.
- Step-by-step fix (numbered).
- Verify: green "Published" status appears on the agent header.
- Screenshots:
  - images/01-basic-b2-publish-error-banner.png
  - images/01-basic-b2-validation-errors.png
- Related links:
  - Lab 1.6 ALM: ../../labs/1.6-application-lifecycle-management/1.6.1-manual-import-export.md
-->

## B3 — Topic does not trigger

<!--
Source brief — please provide:
- Symptom: user sends a message that should match a topic, but the agent answers from generative answers (or fallback).
- Reproduce in Test pane: yes — capture the exact phrase used.
- Likely causes:
  - Trigger phrases too narrow / overlap with another topic.
  - Generative orchestration is on and routes to a tool / generative answer instead.
  - Topic is disabled or unpublished.
- Step-by-step fix:
  1. Open the Activity map (link to toolbox §2) and confirm which node was triggered.
  2. If orchestration is on, open the Activity map and click **Show rationale** on the failing step (toolbox §2).
  3. Add or rephrase trigger phrases; consider giving the topic a clear "description" used by the orchestrator.
- Verify: re-run the same phrase in the Test pane → expected topic node lights up in the Activity map.
- Screenshots:
  - images/01-basic-b3-trigger-phrases.png
  - images/01-basic-b3-activity-map-misroute.png
- Related links:
  - Lab 1.1 Topics: ../../labs/1.1-create-topics/1.1-create-topics.md
-->

## B4 — Generative answers return empty

<!--
Source brief — please provide:
- Symptom: agent says "I don't know" or returns an empty generative answer for a question that should be covered by knowledge.
- Reproduce in Test pane: yes.
- Likely causes:
  - No knowledge source attached.
  - Knowledge source is attached but not indexed yet.
  - Question is outside the configured scope / instructions.
  - Authentication to the knowledge source failed silently.
- Step-by-step fix (numbered).
- Verify: same question in Test pane returns a grounded answer with citation(s).
- Screenshots:
  - images/01-basic-b4-knowledge-list.png
  - images/01-basic-b4-empty-answer-test-pane.png
- Related links:
  - Lab 1.4 AI Search: ../../labs/1.4-ai-search/1.4-ai-search.md
-->

## B5 — Knowledge source returns wrong results

<!--
Source brief — please provide:
- Symptom: cited snippet is unrelated, outdated, or from the wrong document.
- Reproduce in Test pane: yes — capture the citation.
- Likely causes: stale index, wrong scoping, document permissions, chunking.
- Step-by-step fix (numbered).
- Verify: re-run, confirm citation matches expectation.
- Screenshots:
  - images/01-basic-b5-citation-detail.png
- Related links:
  - Lab 2.1 Advanced AI Search: ../../labs/2.1-ai-search-advanced/2.1-ai-search-advanced.md
  - Lab 2.3 SharePoint indexer: ../../labs/2.3-ai-search-sharepoint-indexer/
-->

## B6 — Test pane shows a runtime error

<!--
Source brief — please provide:
- Symptom: red error banner / "Something went wrong" inside the Test pane.
- Reproduce in Test pane: yes — capture the conversation id.
- Likely causes:
  - Action node failed (connector / flow).
  - Variable used before being set.
  - Missing required entity in slot filling.
- Step-by-step fix:
  1. Click the failing node in the Activity map to expand error detail.
  2. Inspect input / output of that node.
  3. If a connector / flow, jump to the Intermediate page (link to 02 §C-flows).
- Verify: same input completes successfully.
- Screenshots:
  - images/01-basic-b6-runtime-error.png
  - images/01-basic-b6-failing-node-detail.png
- Related links:
  - 02 — Intermediate (connectors / flows): ./02-intermediate.md
-->

## B7 — "Publish not allowed" after Teams / M365 Copilot channel changes

**Symptom.** After enabling, disabling, or changing settings on the **Microsoft Teams** or **Microsoft 365 Copilot** channel (often together with an authentication change), clicking **Publish** fails with a message similar to *"Publish not allowed"* or the publish never completes.

**Reproduce in Test pane.** N/A — this is an authoring action. The Test pane itself usually keeps working.

**Likely causes.**

- The channel state is out of sync with the agent's authentication settings after a recent toggle.
- The Teams or Microsoft 365 Copilot channel was added before authentication was configured the way it now is.

**Step-by-step fix.**

1. In the Copilot Studio portal, open your agent → **Settings** → **Channels**.
2. **Remove** the affected channel (Teams or Microsoft 365 Copilot).
3. Open **Settings → Security → Authentication** and confirm the authentication option matches what the channel requires (manual auth vs. Microsoft Entra vs. inherited).
4. **Re-add** the channel. Walk through the configuration end-to-end without skipping steps.
5. **Save** and try **Publish** again.

**Verify.** Publish completes successfully; the agent header shows a fresh **Published** timestamp; opening the agent in Teams / Microsoft 365 Copilot loads the latest version.

**Related links.**

- [B2 — Save or Publish fails](#b2--save-or-publish-fails) (covers other publish failure modes).
- [02 — Intermediate § I1 Authentication loop](./02-intermediate.md#i1--authentication-loop-or-repeated-sign-in).

<!--
Screenshot suggestions:
- images/01-basic-b7-publish-not-allowed-banner.png
- images/01-basic-b7-channels-page.png
-->

---

## Where to next

- Authentication, connectors, flows, environments → [02 — Intermediate](./02-intermediate.md)
- MCP, custom models, AI Search, Foundry IQ → [03 — Advanced](./03-advanced.md)
- Back to the [Diagnostic toolbox](./00-diagnostic-toolbox.md) or [troubleshooting index](./README.md)
