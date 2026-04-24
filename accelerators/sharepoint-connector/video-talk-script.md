# SharePoint Connector — Video Walkthrough Script

> **Estimated duration:** 18–22 minutes
> **Audience:** Azure developers, architects, Copilot Studio practitioners
> **Format:** Screen recording with narration

---

## PART 1 — Design Walkthrough (6–8 minutes)

### Opening (30 s)

> Hi everyone. In this video, I'll walk you through the SharePoint → Azure AI Search connector accelerator. It's a push connector that keeps an Azure AI Search index in sync with one SharePoint site — or even a specific folder inside it — and wires that index into a Copilot Studio agent with **true per-user security trimming**, so the agent only ever cites documents the signed-in user actually has access to.
>
> Along the way it handles multimodal content (text and images in the same retrieval), deletions at source, large files, rate limits, and nightly backups. By the end you'll understand the architecture, know how to deploy it, and see it working end-to-end.

### Why this exists (1 min)

> Azure AI Search has a preview SharePoint connector, but it has real limitations: no private endpoint support, no Conditional Access compatibility, no SLA, limited control over extraction, and no per-user trimming.
>
> If you're building a Copilot Studio agent that needs to ground on SharePoint content *safely*, you want a pipeline you control. That's what this accelerator gives you — and importantly, it plugs into Copilot Studio using the **built-in generative-orchestration lifecycle triggers**, not a bespoke connector.

### Architecture overview (2–3 min)

*[Show the architecture diagram — images/sharepoint-connector-architecture.png]*

> Let me walk you through it. Two flows: the **ingestion pipeline** at the top, and the **retrieval flow** at the bottom.
>
> **On the left** is SharePoint Online. We point the connector at one site, one library, or even one folder inside a library — via `SHAREPOINT_SITE_URL` plus `SHAREPOINT_LIBRARIES` and `SHAREPOINT_ROOT_PATHS`. Least-privilege access is enforced using Graph's `Sites.Selected` permission — we grant the Function App's managed identity read on this one site, and nothing else in the tenant.
>
> **The ingestion pipeline is queue-fed.** Every hour a timer-triggered **dispatcher** asks Graph's `/delta` endpoint what's changed — including deletions — since the last run. For each new or modified file it enqueues one message on `sp-indexer-q`. For each *deleted* file it removes the corresponding chunks from the search index immediately. The per-drive delta token gets persisted so the next run picks up where this one left off.
>
> **Queue-triggered workers** scale out independently — up to 40 instances. Each worker takes one message, streams the file to a tempfile (so we stay memory-bounded on 500-MB PDFs), routes it through extraction, chunks the content, and embeds every chunk.
>
> **Extraction has two routes.** If Azure AI Document Intelligence is configured, PDFs and Office files go through its `prebuilt-layout` model — that gives us reading-order paragraphs, tables, and **figures with cropped image bytes and bounding polygons**. Standalone image files and plain-text formats use simpler paths.
>
> **Embedding is the unified multimodal part.** Every chunk — text or image — goes through Azure AI Vision multimodal embeddings, the Florence model. It produces 1024-dimensional vectors that live in **the same vector space** for both modalities. That means a text query like "our Q3 revenue chart" can match the slide containing the chart, not just text that mentions Q3.
>
> **The index itself** has one vector field: `content_embedding`. Each chunk carries `content_text`, `has_image`, `location_metadata` (page number + bounding polygon), and `permission_ids` — the Entra object IDs that have SharePoint access to the source file. We also store image crops in a dedicated blob container so Copilot Studio can render them as citation thumbnails.
>
> **At the bottom, the retrieval flow.** A Copilot Studio agent running in generative-orchestration mode hosts an `OnKnowledgeRequested` topic. When the agent decides to query knowledge, this topic fires an HTTP action against our `/api/search` endpoint, flowing the signed-in user's delegated Entra token. Our endpoint validates the token, resolves the user's transitive group memberships via Graph using the Function's managed identity, applies a `permission_ids` OData filter, runs the hybrid + semantic query, and returns ranked citations. The LLM only ever sees chunks the caller is authorised for — there is no post-filter leak.

### Key design decisions (1–2 min)

> Four things worth calling out.
>
> **First — unified multimodal embeddings.** One vector field, one hybrid query, cross-modal retrieval works natively. No dual-vector complexity.
>
> **Second — queue-based scale-out.** The dispatcher does the discovery, workers do the heavy lifting in parallel. Poison-queue handling is automatic, per-file failure counters live in a table so we don't retry the same doomed file forever.
>
> **Third — zero secrets.** Every Azure service call is managed identity. If you need a client-secret fallback for Graph, the Bicep optionally provisions a Key Vault and the app setting becomes a `@Microsoft.KeyVault(SecretUri=…)` reference — never a plain-text secret.
>
> **Fourth — pre-retrieval security trimming, not post-filtering.** We deliberately chose Copilot Studio's `OnKnowledgeRequested` lifecycle trigger instead of `AI Response Generated`. Post-filtering citations leaves a data leak — the LLM has already seen restricted content and could paraphrase it. Pre-retrieval trimming means the LLM never sees what the user isn't authorised for.

---

## PART 2 — Deployment (6–8 min)

### Prerequisites (30 s)

> You'll need:
>
> - An Azure subscription — Owner or User Access Administrator on the target RG (needed to assign RBAC).
> - Python 3.11+, the Azure CLI (`az`), and Azure Functions Core Tools v4.
> - `uv` for Python dependency management.
> - An Azure AI Search service — Basic tier or higher (free tier doesn't support vector search).
> - A Microsoft Foundry / Azure AI Services multi-service resource — hosts the Vision multimodal embedder, and optionally Document Intelligence.
> - A SharePoint Online site with some documents.

### Option A — Deploy to Azure button (1–2 min)

*[Show the README, scroll to "Automated Deployment"]*

> The fastest path is the **Deploy to Azure** button in the README. Fill in:
>
> - `baseName` — short prefix like `sp-indexer`.
> - `tenantId`, `sharePointSiteUrl`.
> - `searchEndpoint` + `searchResourceId` for your AI Search service.
> - `foundryEndpoint` + `foundryResourceId` for the Foundry resource.
> - Optional: `sharePointRootPaths` to scope to specific folders.
>
> Review + create, deployment takes about 3 minutes. It creates the Function App on Flex Consumption, Storage with queue / table / state / images / backup containers, App Insights, optional Key Vault (if you're using the client-secret path), and every RBAC role.

### Option B — Scripted deploy (1 min)

> Or clone the repo, edit `infra/main.bicepparam` with your values, and run:
>
> ```powershell
> .\infra\deploy.ps1 -ResourceGroup my-rg
> ```
>
> Pass `-ProvisionDocIntel` to create a new Document Intelligence account; pass `-ClientSecret (Read-Host -AsSecureString)` if you want the Graph client-secret fallback via Key Vault.

### Deploy the function code (1 min)

*[Show terminal]*

> Regardless of how you did the infra, push the code:
>
> ```powershell
> uv sync
> func azure functionapp publish <function-app-name> --python
> ```

### Grant Sites.Selected — least privilege (2 min)

*[Show terminal]*

> This is the one manual step that can't be automated. We need to grant the Function's managed identity read on *just* our target site. The accelerator ships a helper:
>
> ```powershell
> .\infra\grant-site-permission.ps1 `
>     -SiteUrl "https://contoso.sharepoint.com/sites/YourSite" `
>     -FunctionAppName "<function-app-name>"
> ```
>
> That's it — no tenant-wide `Sites.Read.All`, no `Files.Read.All`. The MI can read this one site and nothing else.
>
> We also need one Graph app permission for the `/api/search` endpoint to resolve user group memberships: `GroupMember.Read.All` (Application). Grant admin consent to that on the MI.
>
> Wait 2–10 minutes for RBAC propagation before you test.

---

## PART 3 — Testing (4–5 min)

### Upload sample data (optional, 30 s)

> If you don't already have SharePoint content to test with, the README's Testing section points at Microsoft's public [azure-search-sample-data](https://github.com/Azure-Samples/azure-search-sample-data) repo. The `health-plan/`, `hotel-reviews-images/`, and `nasa-e-book/` folders exercise different parts of the pipeline in a few minutes.

### Trigger a one-off run (1–2 min)

*[Show terminal]*

> Let's trigger the dispatcher manually instead of waiting for the timer:
>
> ```powershell
> $masterKey = (az functionapp keys list --name <fn> --resource-group <rg> --query "masterKey" -o tsv)
> Invoke-WebRequest -Uri "https://<fn>.azurewebsites.net/admin/functions/sp_indexer_timer" `
>     -Method POST -Headers @{"x-functions-key"=$masterKey; "Content-Type"="application/json"} -Body '{}'
> ```
>
> And stream logs:
>
> ```bash
> func azure functionapp logstream <fn>
> ```
>
> *[Show logs]*
>
> You'll see the dispatcher call Graph `/delta`, log how many items came back modified vs deleted, enqueue one message per modified file, and advance the delta token. Queue workers pick up messages in parallel — each one logs the download, the DocIntel call, the vectorization (8 chunks at a time by default), and the push to Search.

### Confirm documents landed (1 min)

```powershell
$token = (az account get-access-token --resource "https://search.azure.com" | ConvertFrom-Json).accessToken
Invoke-RestMethod -Uri "https://<search>.search.windows.net/indexes/sharepoint-index/docs?api-version=2024-07-01&search=*&`$count=true&`$top=0" -Headers @{"Authorization"="Bearer $token"}
```

> Expect `@odata.count > 0`.

### Wire up Copilot Studio (1–2 min)

*[Show Copilot Studio]*

> Now the Copilot Studio side. In your generative-orchestration agent, import the topic YAML that ships with the accelerator: `copilot-studio-topics/OnKnowledgeRequested.yaml`. The topic has to be named **exactly** `OnKnowledgeRequested` — that's how Copilot Studio resolves the lifecycle trigger.
>
> Two placeholders to fill in: your Function App hostname, and the name of the OAuth2 connection reference you set up against the API app registration. Publish the agent.
>
> Now let's test it. I'll ask the agent a question about one of the SharePoint documents...
>
> *[Ask a question as User A — shows citation]*
>
> Perfect — grounded response with citations pointing back to the SharePoint file URL. Note the citation link is the SharePoint URL, not an Azure AI Search URL — click it and SharePoint opens the file with its own permission check. Defence in depth.

### Verify per-user trimming (30 s)

> Now I sign in as **User B**, who doesn't have SharePoint access to that file, and ask the same question.
>
> *[Ask same question as User B]*
>
> No citation for that file. Even though the file is in the index, our `/api/search` endpoint saw that User B's Entra object ID wasn't in the chunk's `permission_ids` and filtered it out before the LLM ever saw it.

### Verify deletion propagation (30 s)

> I'll delete a file in SharePoint, trigger the dispatcher again, and re-run the query. The citation is gone — Graph `/delta` reported the deletion, and the dispatcher removed the chunks.

### Trigger a backup on demand (15 s)

> The nightly backup function can also run on demand:
>
> ```powershell
> $fk = (az functionapp keys list --name <fn> --resource-group <rg> --query "functionKeys.default" -o tsv)
> Invoke-WebRequest -Uri "https://<fn>.azurewebsites.net/api/backup?code=$fk" -Method POST
> ```
>
> Check the `backup` blob container — a `YYYY-MM-DD/` folder with `index-schema.json`, `documents.jsonl`, `watermarks.jsonl`, and `failed-files.jsonl`. Seven days of retention by default.

---

## Closing (30 s)

> That's the SharePoint connector. Recap:
>
> - **Queue-fed push connector** on Flex Consumption — scales past 50+ files per run.
> - **Unified multimodal retrieval** via Azure AI Vision multimodal embeddings — one vector field, cross-modal works natively.
> - **Document Intelligence Layout** (optional) for reading-order paragraphs, tables, and figures from PDF / Office files.
> - **Per-user security trimming** via Copilot Studio's `OnKnowledgeRequested` topic and `/api/search` — LLM never sees restricted content.
> - **Least-privilege Graph access** via `Sites.Selected` + a site-scoped PowerShell grant.
> - **Delta-query deletion propagation** — mirrors SharePoint deletions into the index in near real time.
> - **Nightly backup** with configurable retention.
> - **Rate-limit safe** — bounded concurrency + shared 429 cool-off across workers.
>
> Source code, Bicep templates, the Copilot Studio topic YAML, and one-click deployment are all in the GitHub repo. The README has a **Customization Guide** covering new file formats, swapping the embedding model, tuning concurrency, and schema changes — plus concrete playbooks for the high / medium items still open in the Well-Architected assessment.
>
> Thanks for watching, and happy building.
