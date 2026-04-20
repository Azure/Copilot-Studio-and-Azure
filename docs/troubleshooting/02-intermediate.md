# 02 — Intermediate troubleshooting (Copilot Studio portal)

You've moved past the basics: your agent saves, publishes, and routes correctly. Now you're integrating it with **identity, connectors, flows, custom entities, environments, and telemetry**. This page covers the issues you typically hit there.

> [!TIP]
> Before opening Azure / Power Automate, **always reproduce in the [Test pane](./00-diagnostic-toolbox.md#1-test-pane) first** and capture the conversation id with `/debug conversationId` — it's how you'll find the matching telemetry in [Application Insights](./00-diagnostic-toolbox.md#3-application-insights).

## How to diagnose this area

1. **Reproduce in the Test pane** and copy the conversation id.
2. **Open the [Activity map](./00-diagnostic-toolbox.md#2-activity-map)** to find which action / connector / flow node failed.
3. **Inspect inputs and outputs** of that node — especially anything coming from a variable, a connection, or an OAuth token.
4. **Cross-reference with [Application Insights](./00-diagnostic-toolbox.md#3-application-insights)** if the failure is intermittent or only happens for some users.
5. **Check environment-level constraints** in the [Power Platform Admin Center](./00-diagnostic-toolbox.md#power-platform-admin-center-ppac) — DLP, capacity, region — when an action works for you but not for someone else.

<!--
Source: optional screenshot showing a failed action node expanded next to its App Insights record.
Filename: images/02-intermediate-diagnostic-flow.png
-->

## Common issues at a glance

| # | Symptom | Likely cause | Jump to |
|---|---------|--------------|---------|
| I1 | User is asked to sign in repeatedly / auth loop | Misconfigured Entra app, redirect URIs, scopes | [I1](#i1--authentication-loop-or-repeated-sign-in) |
| I2 | OAuth connection works for the maker, fails for end users | Connection sharing, consent, conditional access | [I2](#i2--oauth-works-for-maker-fails-for-users) |
| I3 | Connector action returns 401 / 403 | Token expired, missing scope, RBAC | [I3](#i3--connector-returns-401--403) |
| I4 | Power Automate flow called from agent fails or times out | Flow permissions, plan limits, payload shape | [I4](#i4--power-automate-flow-fails-or-times-out) |
| I5 | Variable is empty when used downstream | Scope mismatch, slot not filled, type mismatch | [I5](#i5--variable-is-empty-downstream) |
| I6 | Custom entity not extracted / extracted wrong | Synonyms, regex, entity scope | [I6](#i6--custom-entity-not-extracted) |
| I7 | Solution import fails between environments | Missing dependencies, connection references | [I7](#i7--solution-import-fails-between-environments) |
| I8 | App Insights shows no data for the agent | Instrumentation key wrong, telemetry not enabled | [I8](#i8--application-insights-shows-no-data) |
| I9 | Uploaded files (attachments) are ignored by tools / actions | Engine doesn't pass the attachment to the action input | [I9](#i9--uploaded-files-are-ignored-by-tools--actions) |
| I10 | Knowledge source shows an error after solution import | Federated knowledge sources don't survive export / import | [I10](#i10--knowledge-source-shows-an-error-after-solution-import) |
| I11 | Analytics → "Download sessions" returns *Couldn't load data* | Transcript storage limitation or missing security role | [I11](#i11--analytics--download-sessions-returns-couldnt-load-data) |

---

## I1 — Authentication loop or repeated sign-in

<!--
Source brief — please provide:
- Symptom: user is asked to sign in twice, or sign-in card keeps reappearing.
- Reproduce in Test pane: yes (Test pane uses a separate auth than channels — note that explicitly).
- Likely causes:
  - Authentication setting is "Authenticate manually" but Entra app is misconfigured.
  - Redirect URI does not include the channel.
  - Required scopes missing.
- Step-by-step fix (numbered) with screenshots of:
  - Copilot Studio "Security > Authentication" page.
  - Entra app "Authentication" + "API permissions" pages.
- Verify: Test pane shows a single sign-in prompt and proceeds.
- Screenshots:
  - images/02-intermediate-i1-auth-config.png
  - images/02-intermediate-i1-entra-redirect.png
- Related links:
  - Lab 0.0 (create an agent): ../../labs/0.0-create-an-agent/0.0-create-an-agent.md
-->

## I2 — OAuth works for maker, fails for users

<!--
Source brief — please provide:
- Symptom: maker can call the action; end-users get an error.
- Likely causes: connection not shared with users, admin consent missing, conditional access blocking the app.
- Step-by-step fix (numbered).
- Verify: a non-maker test user can complete the flow.
- Screenshots:
  - images/02-intermediate-i2-connection-sharing.png
- Related links:
  - PPAC reference in toolbox §5.
-->

## I3 — Connector returns 401 / 403

<!--
Source brief — please provide:
- Symptom: action fails with 401 or 403 in Activity map / App Insights.
- Likely causes: expired token, missing scope, RBAC role missing on target resource.
- Step-by-step fix:
  1. Inspect failing node → copy correlation id.
  2. Look up the request in the connector's diagnostics (or the target service's logs).
  3. For Azure-targeted calls, verify the managed identity / app registration has the correct RBAC role.
- Verify: action returns 200/2xx.
- Screenshots:
  - images/02-intermediate-i3-failed-action.png
- Related links:
  - Lab 1.7 monitoring: ../../labs/1.7-monitoring/1.7.1-monitor-agent-with-application-insights.md
-->

## I4 — Power Automate flow fails or times out

<!--
Source brief — please provide:
- Symptom: agent calls a flow → no response, error message, or 120s timeout.
- Likely causes:
  - Flow run failed (check the flow's run history).
  - Payload schema mismatch between agent and flow.
  - Flow plan limits / throttling.
- Step-by-step fix:
  1. From Copilot Studio, open the flow definition (link icon).
  2. Open Power Automate run history → inspect failed run.
  3. Compare expected vs. actual input/output schema.
- Verify: re-run from Test pane succeeds end-to-end.
- Screenshots:
  - images/02-intermediate-i4-flow-run-history.png
  - images/02-intermediate-i4-schema-mismatch.png
- Related links: none yet.
-->

## I5 — Variable is empty downstream

<!--
Source brief — please provide:
- Symptom: a variable set in topic A is empty when read in topic B (or in a flow).
- Likely causes:
  - Variable scope is "Topic" instead of "Global".
  - Slot filling didn't capture the value.
  - Type mismatch (string vs. record).
- Step-by-step fix.
- Verify: Test pane variable inspector shows expected value at the failing turn.
- Screenshots:
  - images/02-intermediate-i5-variable-scope.png
- Related links:
  - Lab 1.1 Topics: ../../labs/1.1-create-topics/1.1-create-topics.md
-->

## I6 — Custom entity not extracted

<!--
Source brief — please provide:
- Symptom: user message contains the value but the entity slot stays empty.
- Likely causes: missing synonyms, no regex pattern, wrong entity attached to the slot.
- Step-by-step fix.
- Verify: Test pane shows the entity captured in the variable inspector.
- Screenshots:
  - images/02-intermediate-i6-custom-entity.png
- Related links: Lab 1.1.
-->

## I7 — Solution import fails between environments

<!--
Source brief — please provide:
- Symptom: solution export from DEV fails to import in TEST/PROD.
- Likely causes: missing dependency (connector / flow / Entra app), connection references not mapped, environment variables not set.
- Step-by-step fix.
- Verify: import completes and the agent works in the target env.
- Screenshots:
  - images/02-intermediate-i7-solution-import-error.png
- Related links:
  - Lab 1.6.1: ../../labs/1.6-application-lifecycle-management/1.6.1-manual-import-export.md
  - Lab 1.6.2: ../../labs/1.6-application-lifecycle-management/1.6.2-personal-power-platform-pipelines.md
-->

## I8 — Application Insights shows no data

<!--
Source brief — please provide:
- Symptom: App Insights workspace is empty (or only shows old data) after enabling telemetry.
- Likely causes: instrumentation key not pasted, agent not republished after enabling, wrong workspace, sampling.
- Step-by-step fix:
  1. Re-check the connection string in Settings > Monitoring.
  2. Republish the agent.
  3. Send a test message and wait ~2-5 min for ingestion.
- Verify: a basic KQL query returns at least one record for your conversation id.
- Screenshots:
  - images/02-intermediate-i8-monitoring-settings.png
  - images/02-intermediate-i8-kql-validation.png
- Related links:
  - Lab 1.7: ../../labs/1.7-monitoring/1.7.1-monitor-agent-with-application-insights.md
-->

## I9 — Uploaded files are ignored by tools / actions

**Symptom.** A user uploads a file in the conversation. The agent acknowledges the message but the file content is **not passed to the tool or action** that was supposed to process it (e.g. an action expecting a document blob runs with an empty / null input).

**Reproduce in Test pane.** Yes — attach the same file in the Test pane and inspect the action's inputs in the [Activity map](./00-diagnostic-toolbox.md#2-activity-map).

**Likely causes.**

- The agent does not have an explicit topic / handler that captures the attachment and forwards it as a typed input to the tool.
- The orchestrator chose a tool whose input schema doesn't include a file/binary parameter, so the attachment is silently dropped.

**Step-by-step fix.**

1. Add (or open) a **topic** that triggers when the user sends an attachment.
2. In that topic, **explicitly capture the attachment** into a variable (file / record type).
3. **Pass that variable** as the input parameter to the tool / action you want to run.
4. Make sure the tool's input schema declares a parameter of the right type (file URL, base64, or binary, depending on the connector).
5. Republish and re-test in the Test pane.

**Verify.** In the Activity map, the action node now shows the attachment in its **Inputs** panel and the action returns the expected output.

**Related links.**

- [Lab 1.1 — Create topics](../../labs/1.1-create-topics/1.1-create-topics.md)
- [Lab 1.2 — Tools](../../labs/1.2-tools/1.2-tools.md)

<!--
Screenshot suggestions:
- images/02-intermediate-i9-attachment-topic.png
- images/02-intermediate-i9-action-input-binding.png
-->

## I10 — Knowledge source shows an error after solution import

**Symptom.** You exported a solution containing your agent from one environment and imported it into another (DEV → TEST or TEST → PROD). After import, one or more **knowledge sources** appear in an **error state** in the agent.

**Reproduce in Test pane.** Yes in the target environment — ask a question that should hit the failing source and observe an empty / error result.

**Likely causes.**

- **Federated knowledge sources** (e.g. external/web sources, some enterprise sources, Foundry IQ knowledge bases) **are not fully transported** by solution export/import. The reference is preserved but the underlying connection / index / permissions must be re-established in the target environment.
- The connection / Entra app used by the source exists only in the source environment.

**Step-by-step fix.**

1. Open the agent in the **target** environment → **Knowledge**.
2. For each source in error: **remove and re-add** it, signing in / re-authorizing in the target environment.
3. If the source depends on a **connection reference** or **environment variable**, set those values in the target solution before activating the agent.
4. Republish.

**Verify.** The knowledge sources show as **healthy**; a Test-pane question returns a grounded answer with the expected citation.

**Related links.**

- [Lab 1.6.1 — Manual import / export](../../labs/1.6-application-lifecycle-management/1.6.1-manual-import-export.md)
- [Lab 1.6.2 — Power Platform Pipelines](../../labs/1.6-application-lifecycle-management/1.6.2-personal-power-platform-pipelines.md)
- [I7 — Solution import fails between environments](#i7--solution-import-fails-between-environments)

<!--
Screenshot suggestions:
- images/02-intermediate-i10-knowledge-error-state.png
- images/02-intermediate-i10-reauth-source.png
-->

## I11 — Analytics → "Download sessions" returns *Couldn't load data*

**Symptom.** In **Analytics → Sessions**, clicking **Download sessions** returns an error such as *"Couldn't load data"* and no transcript file is produced.

**Reproduce in Test pane.** N/A — this is a portal analytics action.

**Likely causes.**

- **Transcript data is not written** for certain environment / agent types, including:
  - **Dataverse for Teams** environments.
  - **Dataverse developer** environments.
  - **Microsoft 365 Copilot agents** (declarative agents).
- The signed-in user is **missing the security role** required to read the **Conversation Transcript** table in Dataverse.

**Step-by-step fix.**

1. Confirm the **environment type** in the [Power Platform Admin Center](./00-diagnostic-toolbox.md#power-platform-admin-center-ppac). If it's Dataverse for Teams, a developer environment, or you're working with a declarative Microsoft 365 Copilot agent, transcript download is **expected to be unavailable** — you can't "fix" it; use [Application Insights](./00-diagnostic-toolbox.md#3-application-insights) for telemetry instead.
2. Otherwise, in PPAC → the target environment → **Settings → Users + permissions → Security roles**, ensure the user has **read access on the Conversation Transcript table**. The agent's owning team should already be shared with the agent; the read access on the table is what's typically missing.
3. Reload the Analytics page and re-try **Download sessions**.

**Verify.** A `.csv` of sessions is downloaded successfully.

**Related links.**

- [Diagnostic toolbox — Application Insights](./00-diagnostic-toolbox.md#3-application-insights)
- [Lab 1.7 — Monitor agent with Azure Application Insights](../../labs/1.7-monitoring/1.7.1-monitor-agent-with-application-insights.md)

<!--
Screenshot suggestions:
- images/02-intermediate-i11-download-sessions-error.png
- images/02-intermediate-i11-security-role.png
-->

---

## Where to next

- MCP tools, custom models, AI Search, Foundry IQ → [03 — Advanced](./03-advanced.md)
- Back to the [Diagnostic toolbox](./00-diagnostic-toolbox.md) or [troubleshooting index](./README.md)
