# Solution Accelerators

Ready-to-deploy components that extend Copilot Studio with Azure AI capabilities. Each accelerator targets a specific integration pattern and can be deployed independently.

| Accelerator | What It Does | Stack | Deployment |
|---|---|---|---|
| [SharePoint Connector](#sharepoint-connector) | Indexes SharePoint documents into AI Search | Python, Azure Functions, Graph API | Bicep |
| [Video RAG](#video-rag) | Processes video content for question-answering | Logic Apps, Content Understanding, Event Grid | ARM Template |
| [AI Search Flow](#ai-search-flow) | Search, index creation, and document upload from Power Platform | Power Automate, Custom Connector | Solution ZIP |
| [Content Understanding Flow](#content-understanding-flow) | Document, image, audio, and video analysis from Power Platform | Power Automate, Custom Connector | Solution ZIP |
| [Azure Copilot Pricing](#azure-copilot-pricing) | Real-time Azure pricing queries inside VS Code | GitHub Copilot Chat, REST API | File copy |
| [Voice Channel](voice-channel/) | Real-time voice for Copilot Studio without Omnichannel/Contact Center licensing — Foundry Voice Live agent in Teams/M365 that forwards to a Copilot Studio agent grounded via Microsoft Learn MCP | Azure AI Foundry (Voice Live), Python/FastAPI, App Service, Copilot Studio, pac CLI | Bicep + pac |
