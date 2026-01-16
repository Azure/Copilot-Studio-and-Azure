#  Solution Accelerators
## Objectives
Copilot Studio is a native tool that can be extended with various Azure AI capabilities. Thanks to Microsoft’s accelerators, we can enhance its functionality and significantly improve performance. In this document, we’ll explore how each accelerator can support and complement Copilot Studio to achieve this goal.
## Document Procesing

Copilot Studio provides native capabilities for generating answers and connecting basic queries to Azure AI Search. However, in many scenarios, this isn't sufficient. To deliver more accurate and context-rich responses, we need to implement Retrieval-Augmented Generation (RAG). This approach is especially valuable when customers need to index a large volume of documents and require high accuracy in the generative responses. By leveraging the [Document procesing](https://github.com/Azure/doc-proc-solution-accelerator) alongside Copilot Studio, we can significantly accelerate the adoption of this advanced technology.
[Document procesing](https://github.com/Azure/doc-proc-solution-accelerator)  acceleration can significally helps in the data Ingestion service automates the processing of diverse document types—such as PDFs, images, spreadsheets, transcripts, and SharePoint files—preparing them for indexing in Azure AI Search. It uses intelligent chunking strategies tailored to each format, generates text and image embeddings, and enables rich, multimodal retrieval experies for agent-based RAG applications.

[Document procesing](https://github.com/Azure/doc-proc-solution-accelerator) is a comprehensive, enterprise-ready document processing solution built on Azure that enables organizations to rapidly deploy and scale document processing workflows. This accelerator combines the power of Azure AI services, cloud-native architecture, and modern development practices to provide a complete platform for document ingestion, processing, and analysis.

## Prerequisites

Before starting this lab, ensure you have completed the following prerequisites:

- **[Lab 0.0 - Create an agent](../0.0-create-an-agent/0.0-create-an-agent.md)**

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

## Prerequisites

No prerequisites are needed to deploy this flow.
