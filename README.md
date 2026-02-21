# Copilot Studio Empowered by Azure

This solution empowers organisations to rapidly build and deploy intelligent copilots using a low-code platform integrated with Azure AI. Enabling Fusion Teams, IT Leaders, and Solution Architects with Copilot Studio and Azure building secure, scalable, and task specific AI workflows for enterprise innovation. This repository provides a clear and practical guide to implementing Copilot Studio with Azure, featuring real-world examples and actionable insights on when and how this combination delivers value.

The repository also showcases the convergence of Microsoft's most advanced AI technologies **Microsoft Foundry**, **Foundry IQ**, and **Copilot Studio** working in harmony to create intelligent, knowledge-grounded agents that transform how enterprises work.

# What

Copilot Studio is a graphical, low-code tool for building agents and agent flows, whose capabilities can be further enhanced by leveraging the full potential of Azure AI.

**Foundry IQ** is Microsoft's breakthrough unified knowledge layer that transforms how AI agents access and reason over enterprise data. It's not just RAG, it's intelligent, multi-source knowledge retrieval that understands context and intent. Key capabilities include:
- **Agentic Retrieval**: The AI plans its search strategy, queries multiple sources, and synthesizes coherent responses
- **Multi-Source Knowledge Bases**: Combine multiple data sources in one queryable layer
- **Enterprise Security**: Document-level permissions, audit trails, and compliance
- **36% better response relevance** compared to traditional RAG approaches

# Why

We typically use Copilot Studio with Azure AI when we need to go a step further:

- Optimizing and customizing our RAG implementation. 
- It allows us to introduce information that was previously underrepresented and enrich the foundation of our LLM-based model.
- Rapid Prototyping + Deep customization
- Integrates natively with Microsoft 365 Platform
- Tailored Solutions, Use fine tunning Models for specific use cases, providing more relevant and context-aware outcomes
- Unified Knowledge Access: Single AI agent queries across multiple specialized knowledge bases simultaneously with automatic source routing
- Hybrid Human-AI Workflow: Copilot Studio handles initial triage, Foundry Agent provides deep knowledge retrieval, humans make final decisions with AI-powered recommendations

Use cases:

- Enhancing answer accuracy by leveraging advanced search capabilities. (AI Search)
- Steering the LLM outputs in a specific style or tone. (Fine Tunning)
- Intelligent multi-source knowledge retrieval with agentic reasoning. (Foundry IQ)
  
# When

Copilot Studio empowered by Azure is recommended in scenarios when:

- The out-of-the-box capabilities of Copilot Studio aren't enough.
- You require highly accurate AI responses to meet specific client requirements.
- Involving complex databases that demand customization. 
- You have a clear understanding of what needs to be emphasized in the search process. 
- You have access to thousands of high-quality examples and verified data.
- You need to query multiple knowledge sources simultaneously with intelligent routing.
- Deep expertise is required on demand with grounded, cited responses.
- Complex scenarios require both quick lookups and comprehensive analysis (hybrid responses).

# Architecture

<img width="785" height="545" alt="image" src="https://github.com/user-attachments/assets/350944c5-65cc-4aa4-a3f4-4713b30dc74f" />

# Solutions Accelerators

By leveraging the [Solution Accelerators](docs/Solution-Accelerators.md), we can expand core functionality. In this document, we outline how each accelerator integrates with and enhances Copilot Studio to support these goals:

- Pairing Copilot Studio with [Content Flow](https://github.com/Azure/contentflow) enables high‑accuracy RAG by automating large‑scale document ingestion, intelligent chunking, and multimodal retrieval for enterprise scenarios.
- [AISearch Flow](/accelerators/aisearch/) enables users to interact with Azure AI Search through a manual button trigger, supporting three main operations: creating an index, uploading documents, and performing semantic search queries.
- The [Video RAG Accelerator](/accelerators/Video-RAG/) enables intelligent question-and-answer over training videos by automatically extracting video content, transforming it into structured knowledge, and grounding responses in Azure AI Search for use in Copilot Studio.


# Learning Path
**Lab 0: Prerequisites**
- [Lab 0.0](labs/0.0-create-an-agent/0.0-create-an-agent.md): Create an agent for testing and monitoring.
- [Lab 0.1](labs/0.1-enable-payg/0.1-enable-payg.md): Understanding Copilot Studio licensing (Pay-as-you-go, P1, P3 Agent Factory) and enabling Pay-as-you-go billing

**Lab1: Copilot Studio AI Native features**
- [Lab 1.1](labs/1.1-create-topics/1.1-create-topics.md): Create Topics.
- [Lab 1.2](labs/1.2-tools/1.2-tools.md): Tools.
- [Lab 1.3](labs/1.3-MCP/1.3-MCP.md): Integrate Model Context Protocol (MCP) in Copilot Studio.
- [Lab 1.4](labs/1.4-ai-search/1.4-ai-search.md): Use Azure AI Search in Copilot Studio.
- [Lab 1.5](labs/1.5-custom-models/1.5-custom-models.md): Use custom models in Copilot Studio.
- [Lab 1.6](labs/1.6-application-lifecycle-management): ALM with Copilot Studio.

**Lab 2: Copilot Studio integration with Azure AI**
- [Lab 2.1](labs/2.1-ai-search-advanced/2.1-ai-search-advanced.md): Use advance Azure AI Search.
- [Lab 2.2](labs/2.2-Fine-Tunned-Model/Lab2_CopilotStudio_Text_FineTuned_Model_AzureAIFoundry_PromptTool.md): Use fine tunning in Copilot Studio.
- [Lab 2.3](labs/2.3-ai-search-sharepoint-indexer/2.3-ai-search-sharepoint-indexer.md): AI search Sharepoint Indexer.
- [Lab 2.4](labs/2.4-microsoft-foundry-agentic-retrieval/README.md): Microsoft Foundry Agentic Retrieval with Foundry IQ.

**Best Practices**
- [Best Practices](docs/Best-Practices_decision-tree_for_building_copilot_studio_agent.md): Decision tree and best practices to build an agent. 

  
# Usage scenarios

- Healthcare: Doctors use Copilot Studio with Azure AI Search to instantly find clinical guidelines and patient records, improving diagnosis and care. Fine-tuning adapts the assistant to medical terminology and hospital protocols.
- Financial Services: Compliance teams leverage Copilot Studio to search regulatory documents and audit trails, ensuring fast, accurate responses to legal queries. Fine-tuning customizes the bot for specific regulations and internal policies.
- Retail & E-commerce: Customer service agents use Copilot Studio and Azure AI Search to answer product questions and check inventory, improving response speed and accuracy. AI search refines results based on context and user intent.
- Energy & Utilities: Technicians access Copilot Studio with Azure AI Search to retrieve maintenance records and safety procedures, boosting field efficiency. Intelligent search filters ensure compliance and operational safety.
- Fraud Investigation: Financial analysts use Copilot Studio with Foundry IQ to investigate suspicious transactions by querying fraud patterns, regulatory compliance guidelines, and investigation procedures simultaneously. Foundry IQ's agentic retrieval intelligently selects relevant sources, providing grounded answers with citations—achieving 80% reduction in research time and 60% improvement in fraud detection accuracy.


## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit [Contributor License Agreements](https://cla.opensource.microsoft.com).

When you submit a pull request, a CLA bot will automatically determine whether you need to provide a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).

For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft trademarks or logos is subject to and must follow [Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/legal/intellectualproperty/trademarks/usage/general).

Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.

Any use of third-party trademarks or logos are subject to those third-party's policies.
