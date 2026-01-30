# Video RAG Accelerator

## Objectives

Copilot Studio is a native tool that can be extended with various Azure AI capabilities. Thanks to Microsoft's accelerators, we can enhance its functionality and significantly improve performance.

This accelerator enables **automated video content processing** for Retrieval-Augmented Generation (RAG). When training videos are uploaded to Azure Blob Storage, the system automatically:

- **Extracts** transcripts and AI-generated summaries using Azure Content Understanding
- **Generates** vector embeddings for semantic search
- **Indexes** content in Azure AI Search for retrieval by Copilot Studio

This enables your Copilot to answer questions based on video content, not just text documents.

### Use Cases
- Training video libraries
- Corporate knowledge management
- Educational content repositories
- Media asset management with natural language search

### Design

![Video RAG Architecture](images-samples/arch.png)

---

# 1) Prerequisites & What You'll Need

### Azure Subscription Requirements
- Active Azure subscription with sufficient credits
- Contributor or Owner role on the subscription/resource group
- Ability to create and manage Azure resources

### Required Azure Services

| Service | Purpose |
|---------|---------|
| Azure Storage Account | Store uploaded videos |
| Microsoft Foundry | Content Understanding (video analysis) 
| Azure OpenAI | Generate vector embeddings | 
| Azure AI Search | Index and search content |
| Logic App | Workflow orchestration |
| Event Grid | Event-based triggers |

### Model Deployments Required

**In Azure OpenAI:**
- `text-embedding-3-large` - For generating vector embeddings (3072 dimensions)

**In Microsoft Foundry (Content Understanding):**
- `gpt-4.1` - For video understanding
- `gpt-4.1-mini` - For summarization
- `text-embedding-3-large` - For content vectorization

### Files Included in This Accelerator

| File | Description |
|------|-------------|
| `VideoRAG_LogicApp.zip` | Exportable Logic App workflow |
| `ai-search-index-schema.json` | AI Search index definition sample|
| `readme.md` | This documentation |
| `images-samples/` | Screenshot references |

> **Why Logic Apps?** Logic Apps provide a low-code way to orchestrate complex workflows with built-in connectors for Azure services, retry policies, and monitoring capabilities.

---

# 2) Create Azure Resources

## 2.1 Create a Resource Group

1. Navigate to the [Azure Portal](https://portal.azure.com)
2. Click **"Create a resource"** → Search for **"Resource group"**
3. Configure:
   - **Subscription:** Select your subscription
   - **Resource group name:** `VideoRAG-Project-RG`
   - **Region:** Select a region that supports all services (e.g., Sweden Central, East US 2)
4. Click **"Review + create"** → **"Create"**


## 2.2 Create Storage Account

1. Click **"Create a resource"** → Search for **"Storage account"**
2. Configure:
   - **Resource group:** `VideoRAG-Project-RG`
   - **Storage account name:** `videoragstorage` (must be globally unique)
   - **Region:** Same as resource group


3. After creation, go to **Containers** → **"+ Container"**
4. Create container named: `uploadedvideocontent`


## 2.3 Create Microsoft Foundry for Content Understanding

1. Click **"Create a resource"** → Search for **"Microsoft Foundry"**
2. Configure:
   - **Resource group:** `VideoRAG-Project-RG`
   - **Region:** Same region (must support Content Understanding)
   - **Name:** `videorag-foundry`
   - **Default project name:** `videorag-foundry-proj-default`

> **Region Support:** Not all regions support Content Understanding. Check the [Language and region support documentation](https://learn.microsoft.com/en-us/azure/ai-services/content-understanding/language-region-support) before selecting your region.

## 2.4 Create Azure OpenAI Service

> **⚠️ Important:** You must create an Azure OpenAI resource directly in the Azure portal. Azure OpenAI resources (with access to embedding models) that were created in the Microsoft Foundry portal aren't supported for integrated vectorization with AI Search.
>
> Reference: [Integrated vectorization documentation](https://learn.microsoft.com/en-us/azure/search/search-how-to-integrated-vectorization?tabs=prepare-data-storage%2Cprepare-model-aoai)

1. Click **"Create a resource"** → Search for **"Azure OpenAI"**
2. Configure:
   - **Resource group:** `VideoRAG-Project-RG`
   - **Name:** `videorag-openai`


3. After creation, go to **Azure OpenAI portal** → **Deployments**
4. Click **"+ Create new deployment"**:
   - **Model:** `text-embedding-3-large`
   - **Deployment name:** `text-embedding-3-large`


## 2.5 Create Azure AI Search

1. Click **"Create a resource"** → Search for **"Azure AI Search"**
2. Configure:
   - **Resource group:** `VideoRAG-Project-RG`
   - **Service name:** `videorag-search`

3. After creation, go to **Keys** and copy the **Primary admin key**

---

# 3) Create AI Search Index

## 3.1 Create Index Schema

1. Navigate to your AI Search resource
2. Go to **"Indexes"** → **"+ Add index"**
3. Set **Index name:** `video-training-index`

## 3.2 Configure Fields

Add the following fields as an example:



![Index Fields](images-samples/index.png)

## 3.3 Configure Vector Search

1. Scroll to **"Vector profiles"** → **"+ Add vector profile"**
2. Configure:
   - **Profile name:** `vector-profile`
   - **Algorithm:** HNSW

3. Configure `contentVector` field:
   - **Dimensions:** `3072` (for text-embedding-3-large)
   - **Vector search profile:** `vector-profile`

![Vector Configuration](images-samples/vector-profile.jpg)
![Vectorizer](images-samples/vectorizer.jpg)

4. Click **"Create"**

---

# 4) Create the Logic App

## 4.1 Create Logic App Resource

1. Click **"Create a resource"** → Search for **"Logic App"**
2. Configure:
   - **Resource group:** `VideoRAG-Project-RG`
   - **Logic App name:** `videorag-automation`
   - **Region:** Same as other resources

## 4.2 Enable Managed Identity

1. Navigate to your Logic App
2. Go to **"Identity"** → **"System assigned"**
3. Set Status to **"On"** → Click **"Save"**

![Enable Managed Identity](images-samples/sys-identity.jpg)

4. Note the **Object ID** for RBAC assignments

---

# 5) Configure Permissions (RBAC)

The Logic App's Managed Identity needs access to Azure services.

## 5.1 Grant Storage Access

1. Navigate to Storage Account → **"Access Control (IAM)"**
2. Click **"+ Add"** → **"Add role assignment"**
3. Configure:
   - **Role:** `Storage Blob Data Reader`
   - **Assign to:** System identity
   - **Select:** Your Logic App

## 5.2 Grant Foundry Access

1. Navigate to Foundry → **"Access Control (IAM)"**
2. Add role assignment:
   - **Role:** `Cognitive Services User`
   - **Select:** Your Logic App


## 5.3 Grant OpenAI Access

1. Navigate to Azure OpenAI → **"Access Control (IAM)"**
2. Add role assignment:
   - **Role:** `Cognitive Services OpenAI User`
   - **Select:** Your Logic App

### Permission Summary

| Resource | Role |
|----------|------|
| Storage Account | Storage Blob Data Reader |
| Microsoft Foundry | Cognitive Services User |
| Azure OpenAI | Cognitive Services OpenAI User |

> **Note:** Role assignments can take up to 10 minutes to propagate.

---

# 6) Build the Logic App Workflow

## 6.1 Workflow Overview

The Logic App performs these steps:

```
┌─────────────────┐     ┌─────────────────┐     ┌──────────────────────┐
│  Blob Storage   │────▶│  Event Grid     │────▶│    Logic App         │
│  (Video Upload) │     │  Trigger        │     │                      │
└─────────────────┘     └─────────────────┘     │  1. Parse Event      │
                                                │  2. Call Content     │
                                                │     Understanding    │
                                                │  3. Poll for Status  │
                                                │  4. Extract Content  │
                                                │  5. Generate Vector  │
                                                │  6. Push to Search   │
                                                └──────────────────────┘
```

## 6.2 Add Event Grid Trigger

1. Open Logic App Designer
2. Search for **"Event Grid"** → Select **"When a resource event occurs"**
3. Configure:
   - **Resource Type:** `Microsoft.Storage.StorageAccounts`
   - **Resource Name:** Your storage account
   - **Event Type:** `Microsoft.Storage.BlobCreated`
4. Add **Prefix Filter:** `/blobServices/default/containers/uploadedvideocontent`


5. Click **Settings** (⋯) → Enable **Concurrency Control** → Set to `50`

## 6.3 Add Parse JSON (Parse Trigger)

1. Click **"+ New step"** → Search **"Parse JSON"**
2. Configure:
   - **Content:** Expression: `first(triggerBody())`
   - **Schema:** example:

```json
{
  "type": "object",
  "properties": {
    "topic": {
      "type": "string"
    },
    "subject": {
      "type": "string"
    },
    "eventType": {
      "type": "string"
    },
    "id": {
      "type": "string"
    },
    "data": {
      "type": "object",
      "properties": {
        "api": {
          "type": "string"
        },
        "clientRequestId": {
          "type": "string"
        },
        "requestId": {
          "type": "string"
        },
        "eTag": {
          "type": "string"
        },
        "contentType": {
          "type": "string"
        },
        "contentLength": {
          "type": "integer"
        },
        "blobType": {
          "type": "string"
        },
        "accessTier": {
          "type": "string"
        },
        "url": {
          "type": "string"
        },
        "sequencer": {
          "type": "string"
        },
        "storageDiagnostics": {
          "type": "object",
          "properties": {
            "batchId": {
              "type": "string"
            }
          }
        }
      }
    },
    "dataVersion": {
      "type": "string"
    },
    "metadataVersion": {
      "type": "string"
    },
    "eventTime": {
      "type": "string"
    }
  }
}
```

3. Rename to `Parse_trigger_body`

## 6.4 Initialize Variables

Add **Initialize variable** actions for:

| Variable Name | Type | Value (Expression) |
|---------------|------|-------------------|
| `vBlobUrl` | String | `body('Parse_trigger_body')?['data']?['url']` |
| `vBlobName` | String | `last(split(body('Parse_trigger_body')?['data']?['url'],'/'))` |
| `vContainer` | String | `split(body('Parse_trigger_body')?['data']?['url'],'/')[3]}` |

![Initialize Variables](images-samples/blob-info.jpg)

> **Important:** The `vDocumentId` uses Base64 encoding to create a valid AI Search document key. This handles ALL special characters automatically (spaces, slashes, dots, etc.).

## 6.5 Add HTTP Action (Set Defaults)

1. Add **HTTP** action
2. Configure:
   - **Method:** `PATCH`
   - **URI:** `https://<your-ai-services>.services.ai.azure.com/contentunderstanding/defaults?api-version=2025-11-01`
   - **Headers:** `Content-Type: application/json`
   - **Body:**
```json
{
    "modelDeployments": {
        "gpt-4.1": "gpt-4.1",
        "gpt-4.1-mini": "gpt-4.1-mini",
        "text-embedding-3-large": "text-embedding-3-large"
    },
    "storage": {
        "type": "AzureBlob",
        "containerUri": "https://<your-storage>.blob.core.windows.net/uploadedvideocontent"
    }
}
```
   - **Authentication:** System-assigned managed Identity
   - **Audience:** `https://cognitiveservices.azure.com`

![Set Defaults]![Set Defaults](images-samples/set-defaults.jpg)

3. Rename to `Set_defaults`

## 6.6 Add HTTP Action (Call Content Understanding)

1. Add **HTTP** action
2. Configure:
   - **Method:** `POST`
   - **URI:** `https://<your-ai-services>.cognitiveservices.azure.com/contentunderstanding/analyzers/prebuilt-videoSearch:analyze?api-version=2025-11-01`
   - **Headers:** `Content-Type: application/json`
   - **Body:**
```json
{
    "inputs": [
        {
            "url": "@{variables('vBlobUrl')}"
        }
    ]
}
```
   - **Authentication:** System-assigned Managed Identity
   - **Audience:** `https://cognitiveservices.azure.com`

![Call Content Understanding](images-samples/call-content-understanding.jpg)

1. Rename to `Call_Content_Understanding`

## 6.7 Parse CU Body

1. Click **"+ New step"** → Search **"Parse JSON"**
2. Configure:
   - **Content:** Expression: `body('Call_Content_Understanding')`
   - **Schema:** example:

```json
{
  "type": "object",
  "properties": {
    "id": {
      "type": "string"
    },
    "status": {
      "type": "string"
    },
    "result": {
      "type": "object",
      "properties": {
        "analyzerId": {
          "type": "string"
        },
        "apiVersion": {
          "type": "string"
        },
        "createdAt": {
          "type": "string"
        },
        "warnings": {
          "type": "array"
        },
        "contents": {
          "type": "array"
        }
      }
    }
  }
}
```

## 6.8 Capture Operation Location

1. Add **Set variable** action
2. Configure:
   - **Name:** `vOperationLocation`
   - **Value:** Expression: `outputs('Call_Content_Understanding')?['headers']?['Operation-Location']`


## 6.9 Capture Analyzer Status

1. Add **Set variable** action
2. Configure:
   - **Name:** `vAnalyzerStatus`
   - **Type:** String
   - **Value:** notStarted


## 6.10 Add Polling Loop (Until)

1. Add **Until** action
2. Set condition (Advanced mode):
```
@or(equals(variables('vAnalyzerStatus'), 'succeeded'), equals(variables('vAnalyzerStatus'), 'failed'))
```

3. Set limits:
   - **Count:** `120`
   - **Timeout:** `PT1H`

![Until Loop](images-samples/until-loop.jpg)

### Inside the Until loop, add:

**a) Delay Action**
- **Count:** `15`
- **Unit:** `Second`

**b) HTTP Action (Check_Status)**
- **Method:** `GET`
- **URI:** `@variables('vOperationLocation')`
- **Authentication:** System-assigned managed Identity, Audience: `https://cognitiveservices.azure.com`

**c) Parse JSON**
- **Content:** `@body('Check_Status')`

**d) Set Variable**
- **Name:** `vAnalyzerStatus`
- **Value:** `@body('Parse_JSON')?['status']`

## 6.11 Add Failure Check Condition

1. After Until loop, add **Condition**
2. Set condition (Advanced mode):
```
@equals(variables('vAnalyzerStatus'), 'failed')
```

3. In **True** branch, add **Terminate**:
   - **Status:** Failed
   - **Message:** `Content Understanding analysis failed for @{variables('vBlobName')}`

## 6.12 Parse Final Result

1. Add **Parse JSON** action
2. Configure:
   - **Content:** `@body('Check_Status')`
   - **Schema:** Use comprehensive schema including `contents`, `transcriptPhrases`, `fields`

3. Rename to `Parse_Call_Result_JSON`

## 6.13 Capture Transcript Text

1. Add **Set variable** action
2. Configure:
   - **Name:** `vTranscriptText`
   - **Type:** String
   - **Value:** empty

## 6.14 Capture Summary Text

1. Add **Set variable** action
2. Configure:
   - **Name:** `vSummaryText`
   - **Type:** String
   - **Value:** empty

## 6.15 Add For Each Loop (Extract Content)

1. Add **For each** action
2. Set **From:** `@body('Parse_Call_Result_JSON')?['result']?['contents']`

### Inside the loop, add:

**a) Append Summary**
- **Variable:** `vSummaryText`
- **Value:** `@{if(equals(items('For_each_content')?['fields']?['Summary']?['valueString'], null), '', concat(items('For_each_content')?['fields']?['Summary']?['valueString'], ' '))}`

**b) Select Phrases**
- **From:** `@if(equals(items('For_each_content')?['transcriptPhrases'], null), json('[]'), items('For_each_content')?['transcriptPhrases'])`
- **Select:** `@item()?['text']`

**c) Append Transcript**
- **Variable:** `vTranscriptText`
- **Value:** `@{join(body('Select_Phrases'), ' ')} `

![For Each Content](images-samples/for-each-content.png)

## 6.16 Add Content Check and Final Actions

1. Add **Condition** to check content exists:
```
@greater(length(trim(variables('vTranscriptText'))), 0)
```

### In True branch:

**a) Compose Search Content**
```
@take(concat(trim(variables('vSummaryText')), ' ', trim(variables('vTranscriptText'))), 8000)
```

**b) Generate Embedding (HTTP)**
- **Method:** `POST`
- **URI:** `https://<your-openai>.openai.azure.com/openai/deployments/text-embedding-3-large/embeddings?api-version=2024-06-01`
- **Body:**
```json
{
    "input": "@{outputs('Compose_Search_Content')}"
}
```
- **Authentication:** System-assigned managed Identity, Audience: `https://cognitiveservices.azure.com`
- **Retry Policy:** Exponential, Count: 3


**c) Push to AI Search (HTTP)**
- **Method:** `POST`
- **URI:** `https://<your-search>.search.windows.net/indexes/video-training-index/docs/index?api-version=2024-07-01`
- **Headers:** 
  - `Content-Type: application/json`
  - `api-key: <your-search-admin-key>`
- **Body:**
```json
{
    "value": [
        {
            "@search.action": "mergeOrUpload",
            "id": "@{variables('vDocumentId')}",
            "title": "@{variables('vBlobName')}",
            "sourceUrl": "@{variables('vBlobUrl')}",
            "type": "training-video",
            "summary": "@{trim(variables('vSummaryText'))}",
            "content": "@{trim(variables('vTranscriptText'))}",
            "createdAt": "@{utcNow()}",
            "contentVector": "@body('Generate_Embedding')?['data'][0]['embedding']"
        }
    ]
}
```


### In False branch:

Add **Terminate** with Failed status: `No transcript content extracted`

## 6.17 Save the Logic App

Click **"Save"** in the toolbar.


---

# 7) Testing the Solution

## 7.1 Upload Test Video

1. Navigate to Storage Account → **Containers** → `uploadedvideocontent`
2. Click **"Upload"** → Select a test video (MP4 recommended)
3. Start with a short video (1-2 minutes) for faster testing


## 7.2 Monitor Logic App Run

1. Navigate to Logic App → **"Overview"**
2. Check **"Runs history"** for new run

3. Click on run to see details
4. Verify all actions show green checkmarks


## 7.3 Verify AI Search Results

1. Navigate to AI Search → **"Search explorer"**
2. Run query: `*`
3. Verify document appears with:
   - Title (filename)
   - Summary text
   - Transcript content
   - Content vector array


---

# 8) Connect to Copilot Studio

## 8.1 Create Custom Connector 

To query the indexed videos from Copilot Studio, you can:

1. Use the built-in **Azure AI Search** connector

![Connect to AI Search](images-samples/ai-search-connector.jpg)

2. Create an Agent & attach the knowledge base (the AI Search)

![Copilot Agent](images-samples/copilot-agent.jpg)

## 8.2 Query Videos by Content

Once indexed, videos can be searched using:

- **Keyword search:** Find videos mentioning specific terms
- **Semantic search:** Find videos by meaning/concept
- **Hybrid search:** Combine both approaches

Example search query for Copilot:
```
"What are the best ways to use Microsoft Copilot according to training videos?"
```

The AI Search index returns matching videos with their source URLs, enabling playback or linking.

---

![Agent Search Results](images-samples/agent-test.jpg)

## Appendix — Useful References

- [Azure Content Understanding Documentation](https://learn.microsoft.com/azure/ai-services/content-understanding/)
- [Azure AI Search Vector Search](https://learn.microsoft.com/azure/search/vector-search-overview)
- [Logic Apps Managed Identity](https://learn.microsoft.com/azure/logic-apps/create-managed-service-identity)
- [Azure OpenAI Embeddings](https://learn.microsoft.com/azure/ai-services/openai/concepts/understand-embeddings)
- [Copilot Studio Connectors](https://learn.microsoft.com/microsoft-copilot-studio/advanced-connectors)
- [Microsoft Foundry Overview](https://learn.microsoft.com/en-us/azure/ai-foundry/what-is-foundry)
---

## Additional Links
