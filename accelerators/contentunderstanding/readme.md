#  Content Understanding Flow Accelerator
## Objectives
Copilot Studio is a native tool that can be extended with various Azure AI capabilities. Thanks to this accelerators, we can enhance its functionality and significantly improve performance. The accelerator enables Copilot Studio to use Azure AI Content Understanding for multimodal extraction (documents, images, audio, and video), automatically transforming unstructured enterprise content into structured and grounded outputs.

On this case importing the [Content Understanding Flow] we were able to connect Copilot Studio with Content Understanding in a more efficient way, enabling advanced search capabilities and improving the overall user experience.

***

# 1) Prerequisites & What you’ll import

*   **Power Platform environments** (Dev → Test/Prod) with **Dataverse**.
*   A **solution (.zip)** that contains:
    *   Your **cloud flow** (solution‑aware).
    *   Your **custom connector** (solution‑aware).
    *   **Connection references** used by the flow/connector.
*   Permissions to **import solutions** and activate flows/connectors. [\[learn.microsoft.com\]](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/import-update-export-solutions)
*   A **Content Understanding resource** with API key and endpoint. [\[learn.microsoft.com\]](https://learn.microsoft.com/en-us/azure/ai-services/content-understanding/how-to/create-multi-service-resource)
*   **API key authentication must be enabled** on your Content Understanding / AI Services resource. If local authentication is disabled by policy, the custom connector will not be able to authenticate. Check this in the Azure Portal under your resource → Keys and Endpoint.
*   An **Azure AI Foundry project** associated with your Content Understanding resource, with the following **models deployed**:
    *   `GPT-4.1` or `GPT-4.1-mini` — required for document analysis and extraction.
    *   `text-embedding-3-large` — required for search-based analyzers (e.g., image search, audio search, video search).
    *   Different prebuilt analyzers require different models. Ensure the models needed for your chosen operation are deployed.

> **Why solutions?** Solutions package apps, flows, connectors, env‑vars and make **ALM** (export/import, managed vs unmanaged) consistent across environments. [\[learn.microsoft.com\]](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/import-update-export-solutions)

***

# 2) Import the solution into your target environment

1.  Go to **Power Apps** → **Solutions** → **Import solution**.
![Copilot Studio Home](images/01.png)
![Solutions Import](images/02.png)
2.  Upload the **solution file** and select **Next**.
3.  In **Advanced settings**, keep the option to enable **plugin steps and flows**.
4.  Proceed with **Import**, then **Publish all customizations** once done. [\[learn.microsoft.com\]](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/import-update-export-solutions)

***

# 2.5) Set up Content Understanding defaults

Before the flow can call the Content Understanding API, you must configure the defaults on your Content Understanding resource. This tells the service which Foundry models to use for processing.

1.  Go to the **Content Understanding settings page** in the [Azure AI Foundry portal](https://ai.azure.com).
2.  Select the **+ Add resource** button in the upper left.
3.  Select the **Foundry resource** that you want to use and select **Next** → **Save**.
4.  Make sure that the **Enable autodeployment for required models if no defaults are available** checkbox is selected. This ensures your resource is fully set up with the required `GPT-4.1`, `GPT-4.1-mini`, and `text-embedding-3-large` models.

By taking these steps, you set up a connection between Content Understanding and Foundry models in your Foundry resource. [\[learn.microsoft.com\]](https://learn.microsoft.com/en-us/azure/ai-services/content-understanding/overview)

> **Important:** If you skip this step, the flow will fail with the error: `"Defaults have not yet been set. Call 'PATCH /contentunderstanding/defaults' first."`

***

# 3) Configure connection references & authenticate

After import:

1.  Open the **solution** → review **Content Understanding connector** click on it to edit the connections to your Content Understanding service.
2.  On the connector page, click **Edit** to modify its connections and Content Understanding endpoint.
![Add Connection](images/06.png)
3.  On General change host name to yor Content Understanding endpoint. Such us <your_content_understanding_name>.services.ai.azure.com. Do not type https://
![Edit Connector General](images/07.png)
4.  Skip the connector wizard steps 2 (Security), 3 (Definition), and 4 (Code) as they are — no changes needed.
5.  On Test tab, create a new connection using your **api-key** from Content Understanding.
![Create connection](images/08.png)
![Api-key](images/09.png)
6.  Save the connector clicking in **update connector**. Now your connector is ready to be used in the flow.
***

# 4) Finish Review at copilot Studio

Go to [Copilot Studio](https://copilotstudio.microsoft.com/). Check you are in the right environment. In tools section you will be hable to see, the connector and the flow.

Then click on the flow to open it and test it.
![Flow in Copilot Studio](images/10.png)

Now you can check the flows steps and familiarize yourself with its logic.

Flow Overview
1. Trigger
The flow starts manually using a button.
The user provides the following inputs:

BaseUrl
Body
Subscription Key
Operation
api-version


2. Initialize Variables
The flow initializes the following variables:

| Variable | Default Value |
|---|---|
| finish | Completed |
| id | (empty) |
| operation-type | prebuilt-invoice |
| api-version | 2025-11-01 |

3. API Version Condition

If an api-version is provided by the user, the flow updates the variable.
Otherwise, the default value is retained.


4. Set Operation
The operation-type variable is updated based on the user input.

5. Call API
The flow calls the Content Understanding API using:

The provided request body
The selected operation
The specified parameters


6. Store Status and ID
The flow extracts and stores the following values from the API response:

status
id


7. Do Until Loop
The flow enters a loop that repeats up to 20 times or until:
finish == "Succeeded"

Each iteration performs the following steps:

Waits 15 seconds
Calls the API again to retrieve the result using the stored id
Updates the finish variable with the latest status

***

# 5) How to use it

1.  In the design view of copilot studio. Cliclk on **Test** button on the top right corner.
![Test Flow](images/11.png)
2.  A panel will open on the right side where you can set the parameters for the flow.
*       Select Manually to insert the parameters.
*       Select Automatically if you want to use a previous parameters configuration. (This option will be only available after you have run the flow at least once)
*       Click test.
![Test Panel](images/12.png)

3.  Paste the **Body** of the request. The body must contain a `url` property pointing to the document you want to analyse. For example:

    ```json
    {"inputs":[{"url":"https://github.com/Azure-Samples/azure-ai-content-understanding-python/raw/refs/heads/main/data/invoice.pdf"}]}
    ```

    You can find more examples in the [Content Understanding REST API quickstart](https://learn.microsoft.com/en-us/azure/ai-services/content-understanding/quickstart/use-rest-api?tabs=rest-api%2Cimage&pivots=programming-language-rest).

    > **Note:** The body must use the `inputs` array format with a `url` field. Do not paste the API response JSON as the body — that is the output format, not the input.

4.  Choose the **Operation** based on the file you want to analyze:

    | Operation | Description | Required Models |
    |---|---|---|
    | `prebuilt-invoice` | Extract fields from invoices | GPT-4.1 or GPT-4.1-mini |
    | `prebuilt-imageSearch` | Analyse and search images | GPT-4.1 or GPT-4.1-mini + text-embedding-3-large |
    | `prebuilt-audioSearch` | Analyse and search audio | GPT-4.1 or GPT-4.1-mini + text-embedding-3-large |
    | `prebuilt-videoSearch` | Analyse and search video | GPT-4.1 or GPT-4.1-mini + text-embedding-3-large |
    | `customanalysis` | Custom analyzer defined in Content Understanding playground | Depends on configuration |

    You can create custom analyzers in the Content Understanding playground. [\[learn.microsoft.com\]](https://learn.microsoft.com/en-us/azure/ai-services/content-understanding/tutorial/create-custom-analyzer?tabs=portal%2Cdocument&pivots=programming-language-rest)

5.  Fill the **api-version** default value 2025-11-01.

6.  Click on **Run flow** to execute it.

Note: If you are using the http flow instead of the custom connector, you will need to fill the **BaseUrl** with your Content Understanding endpoint `https://<your service>.services.ai.azure.com/` and the **Ocp-Apim-Subscription-Key** with your API key from Content Understanding.

***

## Appendix — Useful references

*   **Use connectors in Copilot Studio agents** (overview, prebuilt & custom). [\[learn.microsoft.com\]](https://learn.microsoft.com/en-us/microsoft-copilot-studio/advanced-connectors)
*   **Call an agent flow from an agent / topic** (tools vs topic invocation patterns). [\[learn.microsoft.com\]](https://learn.microsoft.com/en-us/microsoft-copilot-studio/advanced-use-flow)
*   **Import solutions** (managed vs unmanaged, publishing, troubleshooting). [\[learn.microsoft.com\]](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/import-update-export-solutions)
*   **Use environment variables in solution custom connectors** (syntax, Key Vault support). [\[learn.microsoft.com\]](https://learn.microsoft.com/en-us/connectors/custom-connectors/environment-variables)
*   **Content Understanding custom analysis**. [\[learn.microsoft.com\]](https://learn.microsoft.com/en-us/azure/ai-services/content-understanding/tutorial/create-custom-analyzer?tabs=portal%2Cdocument&pivots=programming-language-rest)
*   **Content Understanding Foundry tools**. [\[learn.microsoft.com\]](https://learn.microsoft.com/en-us/azure/ai-services/content-understanding/overview)

***
