# SharePoint Connector — Video Walkthrough Script

> **Estimated duration:** 24–30 minutes
> **Audience:** Azure developers, architects, Copilot Studio practitioners
> **Format:** Screen recording with narration

---

## PART 1 — Design Walkthrough (6–8 minutes)

### Opening (30 s)

> Hi everyone. In this video, I'll walk you through the SharePoint → Azure AI Search connector accelerator which can be used to overcome limitations on Copilot Studio SharePoint connector and Sharepoint Connector of Azure AI Search in preview.

> It's a push connector that keeps an Azure AI Search index in sync with selected SharePoint site or a specific folder and wires that index into a Copilot Studio agent.

> The accelerator also handles multimodal content (text and images in the same retrieval), file status changes at source, large files, rate limits, and nightly backups. By the end you'll understand the architecture, know how to deploy it, and see it working end-to-end.

### Architecture overview (2–3 min)

*[Show the architecture diagram — images/sharepoint-connector-architecture.png]*

> Let me walk you through the architecture.

> There are two main flows: the **ingestion pipeline** at the top, and the **retrieval flow** at the bottom.
>
> **On the left** is SharePoint Online. We point the connector at one site, one library, or even one folder inside a library. Least-privilege access is enforced using Graph's `Sites.Selected` permission in which we grant the Function App's managed identity read on this selected site.
>
> **The ingestion pipeline is queue-fed.** Every hour a timer-triggered **dispatcher** asks Graph's `/delta` endpoint what's changed — including deletions — since the last run. For each new or modified file it enqueues one message on queue. For each *deleted* file it removes the corresponding chunks from the search index immediately. The per-drive delta token gets persisted so the next run picks up where this one left off.
>
> **Queue-triggered workers** scale out independently — up to 40 instances. Each worker takes one message, streams the file to a tempfile (so we stay memory-bounded on 500-MB PDFs), routes it through extraction, chunks the content, and embeds every chunk.
>
> **Extraction has two routes.** If Azure AI Document Intelligence is configured, PDFs and Office files go through its `prebuilt-layout` model — that gives us reading-order paragraphs, tables, and **figures with cropped image bytes and bounding polygons**. Standalone image files and plain-text formats use simpler paths.
>
> **Embedding is the unified multimodal part.** Every chunk — text or image — goes through Azure AI Vision multimodal embeddings, the Florence model. It produces 1024-dimensional vectors that live in **the same vector space** for both modalities. That means a text query like "our Q3 revenue chart" can match the slide containing the chart, not just text that mentions Q3.
>
> **The index itself** has one vector field: `content_embedding`. Each chunk carries `content_text`, `has_image`, and `location_metadata` (page number + bounding polygon). We also store image crops in a dedicated blob container so Copilot Studio can render them as citation thumbnails.
>
> **At the bottom, the retrieval flow.** A Copilot Studio agent running in generative-orchestration mode connects directly to the AI Search index using its **built-in Azure AI Search Knowledge Source** connector — no custom topic, no HTTP action, no Entra app, no Power Platform connection. Copilot Studio runs hybrid (vector + keyword) queries with the semantic ranker against `sharepoint-index`, and the LLM grounds its answers on the returned chunks with citations back to the SharePoint source files.

### Key design decisions (1–2 min)

> Four things worth calling out.
>
> **First — unified multimodal embeddings.** One vector field, one hybrid query, cross-modal retrieval works natively. No dual-vector complexity.
>
> **Second — queue-based scale-out.** The dispatcher does the discovery, workers do the heavy lifting in parallel. Poison-queue handling is automatic, per-file failure counters live in a table so we don't retry the same doomed file forever.
>
> **Third — zero secrets.** Every Azure service call is managed identity. If you need a client-secret fallback for Graph, the Bicep optionally provisions a Key Vault and the app setting becomes a `@Microsoft.KeyVault(SecretUri=…)` reference — never a plain-text secret.
>
> **Fourth — built-in AI Search integration in Copilot Studio.** The agent talks directly to the index through the native Azure AI Search Knowledge Source connector — no custom HTTP action, no topic YAML, no Entra app registration, no Power Platform connection. The integration surface is one `Add knowledge → Azure AI Search` click in the Copilot Studio designer.

---

## PART 2 — Deployment (6–8 min)

### Prerequisites (30 s)

> For the **default deployment**:
>
> - An Azure subscription where you hold **Owner** (or *Contributor + User Access Administrator*) on the target resource group — the template assigns RBAC across seven resources.
> - The **Azure CLI** (`az`) and **PowerShell 7+** on your workstation.
> - A **SharePoint Online site** with documents in it, and a **SharePoint Administrator** (or Global Administrator) account to grant the Function App's managed identity per-site read access after deployment.
> - A **Copilot Studio** environment with the *environment maker* role to add the AI Search index as a Knowledge Source on your agent.
>
> No local Python, `uv`, or `func` install is required — the function-app code is pulled from a CI-built GitHub Release at deploy time. The Bicep template provisions every Azure resource itself (AI Search, Foundry, Document Intelligence, Storage, Key Vault, Function App, App Insights, all RBAC).

###  Deploy to Azure button (1–2 min)

*[Show the README, scroll to "Automated Deployment"]*

> The fastest path is the **Deploy to Azure** button in the README. The template asks for **just two values**:
>
> - `baseName` — short prefix like `sp-indexer`. A 6-char uniqueness hash is appended where Azure requires globally-unique names.
> - `sharePointSiteUrl` — full URL of the SharePoint site, e.g. `https://contoso.sharepoint.com/sites/YourSite`.
>
> Everything else is defaulted or computed. Review + create, deployment takes about 5 minutes. Behind the scenes it creates the Function App on Flex Consumption, Storage account with all queue / table / blob containers, Log Analytics + App Insights, Azure AI Search (Basic), Microsoft Foundry / Azure AI Services multi-service for the Vision multimodal embedder, Document Intelligence for Layout extraction, Key Vault, every RBAC role assignment on the Function App's managed identity — and **provisions the AI Search index schema** via an inline ARM `deploymentScript`. It also pulls the latest CI-built function-app package from GitHub Releases and pushes it through Flex's `/api/publish` endpoint, so the code is registered and running by the time the deployment finishes.


### Grant Sites.Selected — least privilege (2 min)

*[Show terminal]*

> One mandatory manual step that can't sit in the template — granting the Function's managed identity read on *just* our target site. This requires SharePoint Administrator or Global Administrator and uses the Microsoft Graph PowerShell SDK (the per-site grant endpoint requires `Sites.FullControl.All`, which the Azure CLI's first-party token doesn't carry).
>
> Open a `pwsh` window — Windows PowerShell 5.x won't work — and run:
>
> ```powershell
> .\infra\grant-site-permission.ps1 `
>     -SiteUrl "https://contoso.sharepoint.com/sites/YourSite" `
>     -FunctionAppName "<function-app-name>"
> ```
>
> The script auto-installs the two Graph sub-modules it needs in CurrentUser scope (~30 s, ~25 MB), prompts you to consent in the browser, and grants read access. **No tenant-wide `Sites.Read.All`, no `Files.Read.All` — the MI can read this one site and nothing else.**
>
> Wait 2–10 minutes for AAD propagation. Then we're ready to wire up Copilot Studio.

### Add AI Search as a Knowledge Source (1 min)

*[Show Copilot Studio]*

> In the Copilot Studio agent we want to ground:
>
> - **Knowledge → + Add knowledge → Azure AI Search**.
> - Pick the search service the deployment created (`<baseName>-search-<hash>`), index name `sharepoint-index`.
> - Authentication: **Managed identity** if your Copilot Studio environment supports it (grant the environment's identity `Search Index Data Reader` on the search service); otherwise **API key** with a query key from the search service's Keys blade.
> - Semantic configuration: `sp-semantic-config`. Vector field: `content_embedding`. Title field: `title`. URL field: `source_url`. Content field: `content_text`.
> - **Add** and **Publish** the agent.
>
> That's it. The agent now retrieves grounded chunks from the index using vector + keyword + semantic ranker through Copilot Studio's built-in connector — no custom code on the retrieval path. Every authenticated user of the agent sees every chunk in the index; when the user clicks a citation, SharePoint enforces its own permission check on the source file at click-through time.

---

## PART 3 — Testing the happy path (3–4 min)

### Upload sample data (optional, 30 s)

> If you don't already have SharePoint content to test with, the README's Testing section points at Microsoft's public [azure-search-sample-data](https://github.com/Azure-Samples/azure-search-sample-data) repo. The `health-plan/`, `hotel-reviews-images/`, and `nasa-e-book/` folders exercise different parts of the pipeline in a few minutes. Drop a few PDFs into your SharePoint site's *Documents* library.

### Trigger a one-off run (1 min)

*[Show terminal]*

> Rather than wait for the hourly timer, fire the dispatcher manually:
>
> ```powershell
> $rg  = "<resource-group>"
> $fn  = "<function-app-name>"   # printed by deploy.ps1
> $key = az functionapp keys list --name $fn --resource-group $rg --query masterKey -o tsv
>
> Invoke-WebRequest -Method POST `
>     -Uri "https://$fn.azurewebsites.net/admin/functions/sp_indexer_timer?code=$key" `
>     -ContentType 'application/json' -Body '{}'
> ```
>
> The dispatcher calls Graph's `/delta` endpoint, finds the new files, and enqueues one message per file onto `sp-indexer-q`. Workers scale out and process them in parallel — stream download, Document Intelligence Layout extraction, multimodal embedding, push to AI Search.

### Confirm documents landed (1 min)

*[Show terminal, then Search Explorer in the portal]*

> Two ways to verify. From the CLI:
>
> ```powershell
> $searchSvc = "<search-service-name>"
> $skey = az search admin-key show --service-name $searchSvc --resource-group $rg --query primaryKey -o tsv
> Invoke-RestMethod -Method Get `
>     -Uri "https://$searchSvc.search.windows.net/indexes/sharepoint-index/docs/`$count?api-version=2024-07-01" `
>     -Headers @{ "api-key" = $skey }
> ```
>
> Expect a non-zero count — typically several documents per file because chunking splits each PDF into ~10–20 retrievable chunks.
>
> Or in the portal: **Search service → Search explorer**, run `*` against `sharepoint-index`. You'll see `chunk_id`, `parent_id`, `title`, `source_url`, the `content_text`, and the 1024-d `content_embedding` vector — exactly what Copilot Studio's built-in connector queries against.

### Test the agent (1 min)

*[Show Copilot Studio chat]*

> Open the Copilot Studio agent we wired up in Part 2. Ask it a question whose answer is in one of the indexed PDFs — say, "what's the company's PTO policy?".
>
> *[Ask the question, agent responds with grounded answer + citation]*
>
> Grounded response with a citation pointing back to the SharePoint file URL. Click the citation — SharePoint opens the file with its own permission check, so the source-file gate stays in place at click-through time.

### Verify deletion propagation (30 s)

> Delete one of those PDFs in SharePoint, trigger the dispatcher again, ask the same question.
>
> *[Show: dispatcher run, citation now absent]*
>
> Citation gone — Graph `/delta` reported the deletion, the dispatcher removed the chunks from the index. End-to-end deletion propagation in near real time.

---

## PART 4 — Monitoring & Operations (6–8 min)

> The pipeline is up. Now let's spend some quality time in the portal showing you exactly where to look when something needs attention — because production data ingestion is never "deploy and forget". I'll cover three views: the **Function App** for execution telemetry, the **Storage Account** for queue + state inspection, and **Application Insights** for KQL-driven deep dives. Everything I'll show maps directly to the troubleshooting matrix in the README.

### 4.1 Function App walkthrough (2–3 min)

*[Portal → Resource group → click the Function App `<baseName>-func-<hash>`]*

> Land on the **Overview** blade. Note the plan type — **Flex Consumption**. Status: Running. Memory: 4096 MB per instance. Default domain ends in `.azurewebsites.net` — that's where `/api/backup` and the `/admin/functions/sp_indexer_timer` trigger endpoint are served.
>
> **Functions blade.** Click **Functions → Functions**. You should see five entries:
>
> - `sp_indexer_timer` — timer trigger, runs hourly (CRON `0 0 * * * *`). The dispatcher.
> - `sp_worker` — queue trigger on `sp-indexer-q`. Processes one file per invocation.
> - `sp_poison_handler` — queue trigger on `sp-indexer-q-poison`. Records terminal failures.
> - `sp_backup_timer` — timer trigger, daily at 03:00 UTC.
> - `sp_backup_manual` — HTTP trigger at `POST /api/backup` for on-demand backups.
>
> *If this list is empty after a fresh deploy*, that's the canonical Flex Consumption "0 functions" symptom — the runtime didn't pick up the package. The README's troubleshooting **S1** has the one-line `func azure functionapp publish` fix.
>
> **Click `sp_indexer_timer`.** The function detail blade has three tabs that matter:
>
> - **Code + Test** — see the function source. Click **Test/Run → Run** to trigger the dispatcher right here, no CLI needed. The HTTP output panel returns 202 (queued).
> - **Monitor** — *every invocation* is listed with timestamp, duration, status, and a link to the full trace in App Insights. Click any row to see the full execution log: which Graph endpoints it called, how many files it found, the run ID it assigned, the watermark advance.
> - **Function Keys** — these are the auth keys for HTTP-triggered functions and admin endpoints.
>
> **Log stream.** Back to the Function App level → **Monitoring → Log stream**. This is your real-time tail. Refresh once for a fresh WebSocket connection, then trigger a dispatcher run from another tab. You'll see, in order:
>
> ```text
> Executing 'Functions.sp_indexer_timer' (Reason='This function was programmatically called')
> SharePoint dispatcher triggered (queue mode)
> SharePoint client: using DefaultAzureCredential (managed identity)
> Acquired new Graph API access token
> HTTP Request: GET https://graph.microsoft.com/v1.0/sites/...:/sites/... "HTTP/1.1 200 OK"
> Listing /delta on drive ...
> Dispatched run <id>: enqueued 3/3 files
> ```
>
> Then within a few seconds, three concurrent worker invocations:
>
> ```text
> Executing 'Functions.sp_worker' (Reason='New queue message detected on 'sp-indexer-q'.')
> Streaming download → /tmp/sp-...
> Document Intelligence: prebuilt-layout on file=employee_handbook.pdf
> Vectorising 14 chunks
> Push chunks + vectors → AI Search
> Executed 'Functions.sp_worker' (Succeeded, Duration=11476ms)
> ```
>
> *Log stream is the single most useful view on Flex Consumption* — App Insights ingestion lags 1–3 minutes; Log stream is live. Anytime something seems stuck, this is where to look first.
>
> **Diagnose and solve problems.** Built-in diagnostic blade — surfaces common configuration issues (failed deploys, scale failures, MI auth problems) without you needing to write KQL. A good first stop for "something's off but I'm not sure what".
>
> **Configuration → Environment variables.** All ~40 app settings the connector reads — `SHAREPOINT_SITE_URL`, `SEARCH_ENDPOINT`, `MULTIMODAL_ENDPOINT`, `INDEXER_SCHEDULE`, the `AzureWebJobsStorage__*` MI settings, etc. Change one here and it takes effect on the next worker recreate (~30 s). The README's "Post-deployment tuning" table calls out the ones you'll commonly touch — `SHAREPOINT_LIBRARIES`, `PROCESSING_MODE`, `VECTORISE_CONCURRENCY`, `BACKUP_RETENTION_DAYS`.

### 4.2 Storage Account walkthrough (2–3 min)

*[Portal → Resource group → click the Storage Account `<baseName>st<hash>`]*

> The storage account holds **all the connector's runtime state** — queues, tables, blobs. Open it.
>
> **Storage browser.** This is the unified UI — Blob containers, File shares, Queues, Tables — all in one tree.
>
> **Queues — `sp-indexer-q`.** Click into it. **Switch authentication to "Microsoft Entra user account"** at the top (you'll need `Storage Queue Data Reader` on yourself for read-only browsing — the README's diagnostic toolkit shows the one-liner to grant it).
>
> The queue lists every pending file message. Each message has:
>
> - **Insertion time** — when the dispatcher enqueued it.
> - **Expiration time** — 7 days by default; messages auto-disappear after that.
> - **Dequeue count** — how many times a worker has tried this message. **0 means workers haven't picked it up yet.** Above 0 means workers are pulling but failing — at `maxDequeueCount=5` (set in `host.json`) the message moves to poison.
> - **Message text** — the JSON body: `run_id`, `drive_id`, `item_id`, `name`, `size`, `web_url`, `last_modified`.
>
> **`sp-indexer-q-poison`.** Same UI — but anything here failed five times. Click any message to see the body and figure out which file it was. The companion `failedFiles` table (we'll see in a sec) has the `last_error` text.
>
> *If `sp-indexer-q` accumulates messages with `dequeueCount=0` and never drains*, the scale controller isn't waking workers. Most likely cause is the Flex/MI service-URI gap covered in README **S2** — fix is in the Bicep but documented for any drifted deployments.
>
> **Tables.** Three tables track operational state:
>
> - **`runState`** — one row per dispatcher run. Columns: `RowKey` (run UUID), `started_at`, `expected` (files enqueued), `completed` (workers that succeeded), `failed`, `completed_at` (timestamp when the run wrapped — empty while in flight). This is your *was the last run successful and how many files did it touch* answer.
> - **`failedFiles`** — files that exhausted retry attempts. Columns: `RowKey` (item ID), `failure_count`, `last_error` (text), `last_seen_iso`. Open a row, copy the `last_error` — that's the actual exception text the worker hit. Common values: `Streaming download failed after 5 retries: <id>` (Graph 403 — Sites.Selected gap), `Upload failed for <name>: Operation returned an invalid status 'Forbidden'` (AI Search RBAC gap, README **S4**).
> - **`watermark`** — single-row table with the timestamp of the last successful run. Used as the floor for "since-last-run" mode if delta tokens get reset.
>
> **Blob containers.** Six relevant ones:
>
> - **`app-package`** — the Function App's deployment zip. The runtime mounts whatever's here as the function code. Updated by the Bicep `publishCode` deploymentScript via Flex's `/api/publish` endpoint, or by `func azure functionapp publish` for manual redeploys.
> - **`images`** — image crops extracted by Document Intelligence Layout, named `<docHash>/<page>-<index>.png`. Copilot Studio renders these as citation thumbnails.
> - **`backup`** — nightly index dumps. Each daily folder (`YYYY-MM-DD/`) contains `index-schema.json`, `documents.jsonl`, `watermarks.jsonl`, `failed-files.jsonl`. Retention defaults to 7 days, governed by `BACKUP_RETENTION_DAYS`.
> - **`state`** — currently reserved for future large-state dumps. Empty by design.
> - **`azure-webjobs-hosts`** — Azure-managed: host metadata, sync-trigger payloads, distributed locks. Don't touch.
> - **`azure-webjobs-secrets`** — Azure-managed: function-app keys at rest. Don't touch.
>
> *On-demand backup demo:*
>
> ```powershell
> $fk = az functionapp keys list --name $fn --resource-group $rg --query "functionKeys.default" -o tsv
> Invoke-WebRequest -Method POST -Uri "https://$fn.azurewebsites.net/api/backup?code=$fk"
> ```
>
> Refresh the `backup` container, you'll see a fresh `YYYY-MM-DD/` folder appear within ~30 seconds.

### 4.3 Application Insights — KQL deep dives (2 min)

*[Portal → Resource group → App Insights resource → Logs blade]*

> When portal blades aren't enough — say, you want to correlate dispatcher runs with worker failures across the last 24 hours — App Insights and KQL is the answer. The README's troubleshooting section has the canonical queries; let me run the three I use most often.
>
> **Pipeline activity (last hour):** dispatcher → worker → search push, end-to-end:
>
> ```kusto
> union traces, exceptions
> | where timestamp > ago(1h)
> | where message has_any (
>     "Dispatched run", "sp_worker", "Streaming download", "Upload",
>     "Push chunks", "Freshness check", "Vectorize"
>   ) or itemType == "exception"
> | project timestamp, itemType, severityLevel,
>           msg = substring(coalesce(message, outerMessage), 0, 400)
> | order by timestamp desc
> ```
>
> Run it — you see every meaningful step from the latest dispatcher invocation, in order. If a stage is missing, that tells you where the pipeline broke.
>
> **Worker exceptions only** (most actionable signal — strips out info traces):
>
> ```kusto
> exceptions
> | where timestamp > ago(6h)
> | project timestamp, type, outerMessage, innermostMessage, problemId, operation_Name
> | order by timestamp desc
> ```
>
> **Per-run completion ratio** — useful for capacity planning:
>
> ```kusto
> traces
> | where timestamp > ago(24h)
> | where message startswith "Dispatched run"
> | extend run_id = extract("Dispatched run ([0-9a-f-]+):", 1, message)
> | project timestamp, run_id, msg = message
> ```
>
> Cross-reference with the `runState` table in storage and you've got a full picture: what was enqueued vs what completed.
>
> **CLI shortcut.** All of these run from the terminal too:
>
> ```powershell
> az monitor app-insights query --app <ai-name> --resource-group $rg `
>     --analytics-query "exceptions | where timestamp > ago(6h) | take 20" -o table
> ```
>
> Useful when you're already in a terminal triaging an incident.

### 4.4 When something's wrong (30 s)

> The README's **Troubleshooting → Symptom matrix** has 10 entries (S1–S10) covering every issue we hit while productionising this connector — Functions blade empty, queue messages stuck at dequeueCount=0, "Message decoding has failed", AI Search 403, vectorizer auth failure, Sites.Selected stale grant, role-assignment update conflict on redeploy, dispatcher enqueuing 0 files, `createSearchIndex` script failure, and `ModuleNotFoundError`. Each one has a copy-paste manual remediation alongside the permanent Bicep fix that ships with the template.
>
> Bookmark that section. It's saved me hours.

---

## Closing (45 s)

> That's the SharePoint connector. Recap:
>
> - **Two-required-parameter deploy** — `Deploy to Azure` button → working pipeline in ~5 minutes including code, RBAC, and AI Search index schema. Sites.Selected grant is the only mandatory follow-up.
> - **Queue-fed push connector** on Flex Consumption — scales past 50+ files per run via parallel workers.
> - **Unified multimodal retrieval** via Azure AI Vision multimodal embeddings — one vector field, cross-modal works natively.
> - **Document Intelligence Layout** for reading-order paragraphs, tables, and figures from PDF / Office files.
> - **Built-in Azure AI Search integration** in Copilot Studio — direct Knowledge Source connector, no Entra app, no Power Platform connection, no custom topic YAML.
> - **Least-privilege Graph access** via `Sites.Selected` + a site-scoped PowerShell grant.
> - **Delta-query deletion propagation** — mirrors SharePoint deletions into the index in near real time.
> - **Nightly backup** with configurable retention.
> - **Rate-limit safe** — bounded concurrency + shared 429 cool-off across workers.
>
> Source code, Bicep templates, the Copilot Studio topic YAML, and one-click deployment are all in the GitHub repo. The README has a **Customization Guide** covering new file formats, swapping the embedding model, tuning concurrency, and schema changes — plus concrete playbooks for the high / medium items still open in the Well-Architected assessment.
>
> Thanks for watching, and happy building.
