# SharePoint Connector — Video Walkthrough Script

> **Estimated duration:** 15–20 minutes  
> **Audience:** Azure developers, architects, Copilot Studio practitioners  
> **Format:** Screen recording with narration

---

## PART 1: Design Walkthrough (5–7 minutes)

### Opening (30 seconds)

> Hi everyone. In this video, I'm going to walk you through the SharePoint to Azure AI Search connector accelerator. This is a fully custom push connector that indexes SharePoint Online documents into Azure AI Search — extracting text, generating vector embeddings, and preserving security permissions — all running as a serverless Azure Function.
>
> By the end of this video, you'll understand the architecture, know how to deploy it to your own environment, and see it working end to end.

### The Problem (1 minute)

> Let's start with **why** this exists.
>
> Azure AI Search has a built-in SharePoint connector, but it's still in preview. It doesn't support private endpoints, it doesn't work with Conditional Access policies, there's no SLA, and you have limited control over how documents are processed.
>
> If you're building a Copilot Studio agent that needs to search your organization's SharePoint documents, you need something more reliable. That's what this accelerator gives you — a production-ready connector you fully control.

### Architecture Overview (2–3 minutes)

*[Show the architecture diagram]*

> Let me walk you through the solution architecture. There are two flows here: the **ingestion pipeline** at the top, and the **retrieval flow** at the bottom.
>
> **Starting from the left** — we have SharePoint Online with your document libraries. The connector supports over 25 file formats: Word, PDF, Excel, PowerPoint, plain text, HTML, email files, and more.
>
> **In the center** is the Azure Function App. This is the heart of the solution. It runs on Flex Consumption, which means it scales to zero when idle — you only pay when it's actually processing documents. It uses a timer trigger, configured to run every hour by default.
>
> When the timer fires, here's what happens inside the function:
>
> 1. **File discovery** — it calls the Microsoft Graph API to list files across your SharePoint document libraries. In incremental mode, it only looks at files modified in the last 65 minutes.
> 2. **Download** — for each file that needs processing, it downloads the content via Graph API.
> 3. **Text extraction** — a built-in document processor handles 25+ formats, extracting clean text from each file.
> 4. **Chunking** — the text is split into overlapping chunks with intelligent boundary detection at paragraph and sentence breaks.
> 5. **Embedding generation** — chunks are sent to Azure OpenAI to generate vector embeddings using text-embedding-3-large at 1536 dimensions.
> 6. **Push to index** — finally, the chunks, their vectors, metadata, and SharePoint permission IDs are pushed directly into Azure AI Search.
>
> On the **right side**, you see the supporting services. Azure Storage handles the Function App runtime. Application Insights gives you logging and monitoring. And the RBAC panel shows the role assignments — the function's managed identity gets specific roles on each service. No API keys anywhere.
>
> On the **bottom**, the retrieval flow shows how Copilot Studio connects to the AI Search index as a knowledge base. End users ask questions in natural language, and Copilot Studio performs hybrid search — combining vector similarity with keyword matching — and returns grounded answers from your SharePoint documents.

### Key Design Decisions (1–2 minutes)

> Let me highlight a few important design decisions:
>
> **First, this is a push connector, not a pull connector.** We don't rely on Azure's built-in indexer infrastructure. The function downloads files, processes them in memory, and pushes results directly to the index. This gives you complete control over the pipeline.
>
> **Second, there's no blob storage intermediary.** Files go straight from SharePoint into memory, get processed, and go into the search index. No intermediate storage to manage or pay for.
>
> **Third, zero secrets.** All Azure service authentication uses managed identity with RBAC role assignments. The only thing that requires special handling is the Microsoft Graph API permissions, which need a one-time admin consent step.
>
> **Fourth, incremental sync.** In production, the connector doesn't reprocess everything every hour. It uses the Graph API's `lastModifiedDateTime` filter to only pick up changed files. There's also a freshness check against the index — if a file's modification timestamp matches what's already indexed, it's skipped entirely.
>
> **And finally, security trimming.** The connector stores SharePoint permission IDs with each chunk. This means you can filter search results at query time based on the current user's identity and group memberships — so users only see documents they actually have access to.

---

## PART 2: Deployment (5–7 minutes)

### Prerequisites (30 seconds)

> Now let's deploy this. You'll need a few things ready:
>
> - An Azure subscription
> - Azure CLI installed
> - Azure Functions Core Tools v4
> - Python 3.11 or later
> - An Azure AI Search service — Basic tier or higher, because the free tier doesn't support vector search
> - An Azure OpenAI or Foundry resource with a text-embedding-3-large deployment
> - A SharePoint Online site with some documents

### Option A: One-Click Deploy (1 minute)

*[Show the README, scroll to the Deploy to Azure button]*

> The fastest way to get the infrastructure up is the **Deploy to Azure** button in the README.
>
> Click it, and you'll be taken to the Azure Portal's custom deployment page. Fill in the parameters:
>
> - **baseName** — a short name like `sp-indexer`, used as a prefix for all resources
> - **tenantId** — your Entra ID tenant ID
> - **sharePointSiteUrl** — the full URL to your SharePoint site
> - **searchEndpoint** and **searchResourceId** — your AI Search service endpoint and its full resource ID
> - **foundryEndpoint** and **foundryResourceId** — same for Azure OpenAI
>
> Click **Review + create**, and the deployment will take about 2–3 minutes. It creates the Function App on Flex Consumption, a Storage Account, Application Insights with Log Analytics, and assigns all the RBAC roles automatically.
>
> Note that this only deploys the **infrastructure**. We still need to deploy the function code separately.

### Option B: Script Deploy (1 minute)

> Alternatively, you can use the PowerShell deployment script, which handles both infrastructure and code in one command.
>
> Clone the repo, navigate to the `sharepoint-connector` directory, edit `infra/main.bicepparam` with your values, and then run:
>
> ```
> .\infra\deploy.ps1 -ResourceGroup my-rg
> ```
>
> This runs the Bicep deployment, generates the requirements.txt, and publishes the function code.

### Deploy Function Code (1 minute)

*[Show terminal]*

> If you used the one-click button, you need to deploy the code now. From the `sharepoint-connector` directory:
>
> ```
> uv sync
> uv export --no-hashes --extra func --no-dev > requirements.txt
> func azure functionapp publish sp-indexer-func --python
> ```
>
> This packages up the Python code and pushes it to your Function App. Should take about a minute.

### Grant Graph API Permissions (2 minutes)

*[Show terminal]*

> This is the one manual step that can't be automated — granting the function's managed identity permission to read SharePoint via Microsoft Graph.
>
> The deployment output gives you the managed identity's object ID. We need to grant it two application permissions: `Sites.Read.All` and `Files.Read.All`.
>
> I'll use the Azure CLI approach. First, get the Graph API service principal ID, then get the role IDs for each permission, and finally create the app role assignments.
>
> ```
> GRAPH_SP_ID=$(az ad sp list --filter "appId eq '00000003-0000-0000-c000-000000000000'" --query "[0].id" -o tsv)
> ```
>
> Then for each permission:
>
> ```
> az rest --method POST --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$MSI_OBJECT_ID/appRoleAssignments" --body "{...}"
> ```
>
> This requires Global Admin or Privileged Role Administrator. In most organizations, you'll need to coordinate with your identity team for this step.
>
> After granting permissions, wait 2–10 minutes for RBAC propagation before testing.

---

## PART 3: Testing the Connector (3–5 minutes)

### Trigger a Full Reindex (1–2 minutes)

*[Show terminal]*

> Let's test the connector. First, we'll set it to full reindex mode so it processes all files:
>
> ```
> az functionapp config appsettings set --name sp-indexer-func --resource-group my-rg --settings INCREMENTAL_MINUTES=0
> ```
>
> Now trigger the function manually:
>
> ```
> $masterKey = (az functionapp keys list --name sp-indexer-func --resource-group my-rg --query "masterKey" -o tsv)
> Invoke-WebRequest -Uri "https://sp-indexer-func.azurewebsites.net/admin/functions/sharepoint_indexer" -Method POST -Headers @{"x-functions-key"=$masterKey; "Content-Type"="application/json"} -Body '{}'
> ```
>
> While it's running, let's stream the logs:
>
> ```
> func azure functionapp logstream sp-indexer-func
> ```
>
> *[Show logs streaming — point out the key messages]*
>
> You can see the function discovering files, downloading each one, extracting text, generating embeddings, and pushing chunks to the index. At the end, it logs a summary: how many files were discovered, processed, skipped, and any errors.

### Verify the Search Index (1 minute)

*[Show terminal or Azure Portal]*

> Let's verify the data landed in the search index. We can query the document count:
>
> ```
> $token = (az account get-access-token --resource "https://search.azure.com" | ConvertFrom-Json).accessToken
> Invoke-RestMethod -Uri "https://my-search.search.windows.net/indexes/sharepoint-index/docs?api-version=2024-07-01&search=*&`$count=true&`$top=0" -Headers @{"Authorization"="Bearer $token"}
> ```
>
> We can see there are now documents in the index. Let's also do a semantic search to make sure the vectors are working:
>
> *[Run a search query with a natural language question relevant to the SharePoint content]*
>
> Great — we're getting relevant results back, with the correct metadata, chunk text, and permission IDs.

### Connect to Copilot Studio (1–2 minutes)

*[Show Copilot Studio]*

> The final step is connecting this index to Copilot Studio as a knowledge base.
>
> In Copilot Studio, go to your agent's **Knowledge** section, click **Add knowledge**, select **Azure AI Search**, and enter your search endpoint and index name.
>
> Now let's test it. I'll ask the agent a question about one of the documents in SharePoint...
>
> *[Ask a question, show the response with citations]*
>
> And there it is — the agent found the relevant document chunks from the search index and generated a grounded response with citations pointing back to the source SharePoint documents.

### Restore Incremental Mode (15 seconds)

> Before we wrap up, let's switch back to incremental mode for production:
>
> ```
> az functionapp config appsettings set --name sp-indexer-func --resource-group my-rg --settings INCREMENTAL_MINUTES=65
> ```
>
> Now the connector will run every hour and only process files that changed in the last 65 minutes.

---

## Closing (30 seconds)

> That's the SharePoint to Azure AI Search connector. To recap:
>
> - It's a fully custom **push connector** running as a serverless Azure Function
> - It supports **25+ file formats** with text extraction, chunking, and vector embeddings
> - It uses **managed identity** everywhere — no API keys or secrets
> - It does **incremental sync** so it's efficient in production
> - And it preserves **security permissions** for query-time trimming
>
> The full source code, Bicep templates, and one-click deployment are all in the GitHub repo. Check the README for the complete documentation.
>
> Thanks for watching, and happy building.
