# Solution Accelerators

Ready-to-deploy components that extend Copilot Studio with Azure AI capabilities. Each accelerator targets a specific integration pattern and can be deployed independently.

| Accelerator | What It Does | Stack | Deployment |
|---|---|---|---|
| [SharePoint Connector](#sharepoint-connector) | Indexes SharePoint documents into AI Search | Python, Azure Functions, Graph API | Bicep |
| [Video RAG](#video-rag) | Processes video content for question-answering | Logic Apps, Content Understanding, Event Grid | ARM Template |
| [AI Search Flow](#ai-search-flow) | Search, index creation, and document upload from Power Platform | Power Automate, Custom Connector | Solution ZIP |
| [Content Understanding Flow](#content-understanding-flow) | Document, image, audio, and video analysis from Power Platform | Power Automate, Custom Connector | Solution ZIP |
| [Azure Copilot Pricing](#azure-copilot-pricing) | Real-time Azure pricing queries inside VS Code | GitHub Copilot Chat, REST API | File copy |
| [Voice Channel](voice-channel/) | Voice-enabled Copilot Studio agent without Omnichannel/Contact Center licensing. One Foundry "IT Assistant" agent serves three surfaces: custom Voice Live web UI, Microsoft Teams, and M365 Copilot Chat. Backend grounded via a Copilot Studio agent on the Microsoft Learn MCP server. | Azure AI Foundry (Voice Live, Agent Service), Container Apps, ACR, Copilot Studio, pac CLI | azd + pac |
