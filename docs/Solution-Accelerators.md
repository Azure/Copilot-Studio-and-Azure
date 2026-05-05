#  Solution Accelerators
## Objectives
Copilot Studio is a native tool that can be extended with various Azure AI capabilities. Thanks to Microsoft’s accelerators, we can enhance its functionality and significantly improve performance. In this document, we’ll explore how each accelerator can support and complement Copilot Studio to achieve this goal.
## Content Flow

Copilot Studio provides native capabilities for generating answers and connecting basic queries to Azure AI Search. However, in many scenarios, this isn't sufficient. To deliver more accurate and context-rich responses, we need to implement Retrieval-Augmented Generation (RAG). This approach is especially valuable when customers need to index a large volume of documents and require high accuracy in the generative responses. By leveraging the [Content Flow](https://github.com/Azure/contentflow) alongside Copilot Studio, we can significantly accelerate the adoption of this advanced technology.
 [Content Flow](https://github.com/Azure/contentflow)   acceleration can significally helps in the data Ingestion service automates the processing of diverse document types—such as PDFs, images, spreadsheets, transcripts, and SharePoint files—preparing them for indexing in Azure AI Search. It uses intelligent chunking strategies tailored to each format, generates text and image embeddings, and enables rich, multimodal retrieval experies for agent-based RAG applications.

 [Content Flow](https://github.com/Azure/contentflow)  is a comprehensive, enterprise-ready document processing solution built on Azure that enables organizations to rapidly deploy and scale document processing workflows. This accelerator combines the power of Azure AI services, cloud-native architecture, and modern development practices to provide a complete platform for document ingestion, processing, and analysis.


## AI Search Custom connector Flow

  This [AISearch Flow](/accelerators/aisearch/) enables users to interact with Azure AI Search through a manual button trigger, supporting three main operations: creating an index, uploading documents, and performing semantic search queries.

  Extending Copilot Studio with this flow allows users to manage Azure AI Search functionalities directly within the Copilot Studio environment, enhancing the overall user experience and streamlining search operations.

  ## Main Components 
  - **Manual Trigger**: Starts the flow and collects user inputs for search parameters and action selection.
  - **Variable Initialization**: Sets up variables for search configuration (select, search, filter, facets, top, api-version). 
  - **Conditional Logic**: Updates variables only if user input is provided, ensuring dynamic and flexible operation. 
  - **Switch Action**: Directs the flow to the correct operation based on user selection: 
  - **CreateIndex**: Creates a new search index. 
  - **UploadDocuments**: Uploads documents to a specified index. 
  - **Search**: Executes a semantic search with advanced options. ## Summary AI_Search_HTTP_Flow_Demo streamlines Azure AI Search management, allowing users to create indexes, upload data, and run complex searches—all controlled by user input at runtime.

## Video RAG Accelerator

The [Video RAG Accelerator](/accelerators/Video-RAG/) enables intelligent question-and-answer over training videos by automatically extracting video content, transforming it into structured knowledge, and grounding responses in Azure AI Search for use in Copilot Studio.
Training videos uploaded to storage are automatically processed end-to-end using event-driven Azure services. Video content is analyzed using Azure AI Content Understanding (Video Analyzer) to extract transcripts, summaries, and contextual markdown. The extracted information is normalized and indexed in Azure AI Search, enabling fast, accurate, and scalable retrieval.
Users can then ask natural-language questions in Copilot Studio, receiving answers grounded directly in the video content.

**Why this accelerator?** Information locked inside training videos, recorded all-hands, and product walkthroughs is effectively invisible to text search — the knowledge exists in the corpus but nobody can cite it or retrieve it on demand. Building the pipeline from scratch (event-driven video processing, Content Understanding for transcripts and summaries, chunking, embedding, AI Search indexing) is a significant engineering effort that most teams don't budget for. This accelerator provides a working end-to-end pipeline — drop a video into blob storage and within minutes it becomes searchable Copilot Studio knowledge, with citations that point back to the source video. Teams move from "our training library is a black box" to "employees ask questions, get grounded answers" without an ML project.

## SharePoint Connector Accelerator

The [SharePoint Connector Accelerator](/accelerators/sharepoint-connector/) lets employees ask a Copilot Studio agent questions about their company's SharePoint content and get grounded, cited answers — without ever seeing documents they don't already have permission to read. It works equally well on text-heavy content (policies, memos, contracts) and image-heavy content (slide decks, product diagrams, scanned forms, whiteboard photos), so a question like "what did we decide about Q3 pricing?" surfaces the right paragraph *and* the chart that visualises it. Answers stay current as SharePoint changes: new and edited files flow into the agent's knowledge within the hour, and files deleted in SharePoint disappear from the agent's answers on the next run. The accelerator can be scoped to a single site or folder, so one team's agent doesn't touch another team's content.

**Why this accelerator?** The out-of-the-box SharePoint knowledge sources available to Copilot Studio and Azure AI Search have real operational limits — no private-endpoint support, no Conditional Access compatibility, no production SLA, and critically no per-user security trimming at retrieval time. Building a compliant custom replacement from scratch is typically a multi-month effort that hits the same three hard problems every team: (1) making sure an LLM never grounds on a document the caller doesn't have permission to read, (2) making image-rich content (charts, slide decks, scanned forms) as findable as plain text, and (3) keeping the index in sync with SharePoint as files are added, edited, and deleted — without pounding rate-limits or losing state on failure. This accelerator provides a worked, production-oriented solution to all three, so a team can go from "empty SharePoint site" to "secure, grounded, multimodal Copilot Studio agent" in days rather than months, and focus their engineering on the business-specific parts (which content, which agents, which prompts) instead of the pipeline plumbing.

Key capabilities:

- **Per-user security trimming.** A Copilot Studio `OnKnowledgeRequested` topic calls the connector's `/api/search` endpoint with the signed-in user's delegated Entra token; the endpoint validates the JWT, resolves transitive group memberships through Graph with the Function's managed identity, and applies a `permission_ids` filter so the LLM only ever sees chunks the caller is authorised for.
- **Deletion propagation.** Graph `/delta` query drives incremental ingestion; deletions at source are mirrored into the index on the next indexer run, backed by periodic full reconciliation.
- **Scoped monitoring.** Point one connector instance at a single site — or at specific folders within a library — via `SHAREPOINT_SITE_URL` + `SHAREPOINT_LIBRARIES` + `SHAREPOINT_ROOT_PATHS`, without broad tenant permissions.
- **Least-privilege Graph access.** Ships a `grant-site-permission.ps1` helper that grants the managed identity `Sites.Selected` on just the target site — no tenant-wide `Sites.Read.All`.
- **Backup + DR.** Nightly timer function exports index schema, document metadata, and state tables to a `backup` blob container with configurable retention.
- **Throughput + rate-limit safety.** Per-file chunk vectorisation runs on a bounded thread pool; the Vision client holds a global semaphore + shared 429 cool-off so all workers throttle together.

The same pattern can be used as a starting point for your own connector. The Customization Guide in the accelerator README covers adding new file formats, swapping the embedding model, adjusting concurrency, and modifying the search index schema.

## Content Understanding Flow Accelerator

The [Content Understanding Flow Accelerator](/accelerators/contentunderstanding/) gives low-code teams a Power Automate path into Azure AI Content Understanding, so an analyst — not a developer — can pull structured data out of multimodal content. Drop an invoice into a folder and a flow extracts the line items, vendor, and totals; drop a meeting recording in and a flow returns the transcript, summary, and action items; drop a scanned form in and a flow returns the field values as Dataverse rows. The accelerator ships as a Power Platform solution (.zip) containing a cloud flow, a custom connector to Content Understanding, and the connection references — import it, wire up your Content Understanding endpoint, and start consuming the service from any Power Automate or Power Apps solution in the environment.

**Why this accelerator?** Azure AI Content Understanding is a powerful multimodal service, but its native surface is a REST API — that's great for pro-code teams but a non-starter for business users, citizen developers, and line-of-business analysts who live in Power Platform. Left un-accelerated, every team that wants to extract structured data from forms, invoices, images, or meeting recordings ends up commissioning a custom dev project just to get started. This accelerator removes that bottleneck: the custom connector turns Content Understanding into a first-class Power Automate action, so an analyst can build "watch this folder → extract invoice data → write rows to Dataverse → trigger approvals" in an afternoon. It also keeps ALM clean — everything ships inside a Power Platform solution with proper environment, Dataverse, and connection-reference governance.

## Azure Copilot Pricing Accelerator

The [Azure Copilot Pricing Accelerator](/accelerators/azure-copilot-pricing/) installs as a GitHub Copilot Chat skill that answers Azure pricing and Copilot Studio credit-consumption questions directly inside VS Code. Ask *"how much is a Standard D4s v5 in West Europe per month?"* or *"estimate the monthly credit spend for an agent doing 10k Copilot Studio sessions with RAG and two tool calls per turn"* — the skill queries the live public Azure Retail Prices API and applies the documented Copilot Studio credit-consumption formulae, returning an indicative cost estimate without leaving the editor.

**Why this accelerator?** Pricing work during an architecture review or design session today means tab-switching between the Azure pricing calculator, VM SKU documentation, and Copilot Studio licensing pages — interrupting flow and risking stale numbers inside design documents. This accelerator collapses that lookup into a conversation with GitHub Copilot Chat, using always-current public pricing data (no Azure subscription or auth needed) and a repeatable estimator for Copilot Studio credit consumption. For any team scoping Azure + Copilot Studio architectures it pays off on every design review: faster estimates, fewer errors, less context switching — and because it's just a file-copy install, there's no infrastructure to provision or maintain.

> **Note on accuracy.** The pricing skill returns indicative estimates only. Real consumption depends on actual traffic patterns; use the numbers for scoping, not as a commitment.

## Voice Channel Accelerator

The [Voice Channel Accelerator](/accelerators/voice-channel/) makes a Copilot Studio agent voice-capable across **three surfaces from one shared agent** — a custom Voice Live web UI, Microsoft Teams, and Microsoft 365 Copilot Chat. The same Foundry Agent Service "IT Assistant" holds the instructions and tools on every channel, and it's grounded via a Copilot Studio "Microsoft Learn Assistant" agent on the Microsoft Learn MCP server — so answers are cited, current, and consistent whether the user is speaking to the custom web widget, pressing the mic in Teams, or typing into M365 Copilot Chat. Deployment is one-click (ARM + Azure Container Apps, with an optional Power Platform service-principal step that also provisions the Copilot Studio agent).

**Why this accelerator?** Real-time voice experiences on a Copilot Studio agent normally require the Omnichannel Engagement Hub / Contact Center licence. This accelerator demonstrates an alternative supported **Foundry Agent Service** path that pairs **Voice Live** for low-latency speech-to-speech with **Azure Bot Service** for Teams and M365 Copilot publishing — one agent, three surfaces, a fraction of the licensing cost. Adapted from Azure-Samples' call-center-voice-agent with three deliberate additions: (1) three-channel publishing on a single shared agent, (2) Voice Live in "agent mode" so Foundry instructions and tools apply automatically on every voice session, and (3) a Copilot Studio + Microsoft Learn MCP backend so voice answers are grounded. Teams move from "how do we pilot voice on Copilot Studio?" to "voice agent live in three channels" quicker.
