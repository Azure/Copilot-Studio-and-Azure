# Solution Accelerators

Ready-to-deploy components that extend Copilot Studio with Azure AI capabilities. Each accelerator targets a specific integration pattern and can be deployed independently.

| Accelerator | What It Does | Stack | Deployment |
|---|---|---|---|
| [SharePoint Connector](#sharepoint-connector) | Indexes SharePoint documents into AI Search | Python, Azure Functions, Graph API | Bicep |
| [Video RAG](#video-rag) | Processes video content for question-answering | Logic Apps, Content Understanding, Event Grid | ARM Template |
| [AI Search Flow](#ai-search-flow) | Search, index creation, and document upload from Power Platform | Power Automate, Custom Connector | Solution ZIP |
| [Content Understanding Flow](#content-understanding-flow) | Document, image, audio, and video analysis from Power Platform | Power Automate, Custom Connector | Solution ZIP |
| [Azure Copilot Pricing](#azure-copilot-pricing) | Real-time Azure pricing queries inside VS Code | GitHub Copilot Chat, REST API | File copy |
| [Voice (Push-to-Talk)](voice-pushtotalk/) | Voice-capable Teams / M365 Copilot agent without Omnichannel/Contact Center licensing or custom hosting — Foundry Agent Service "IT Assistant" published natively to Teams/M365, calls Copilot Studio "Microsoft Learn Assistant" over Direct Line via an OpenAPI tool | Azure AI Foundry (Agent Service), Copilot Studio, Azure Bot Service (auto), pac CLI | Bicep + pac |
