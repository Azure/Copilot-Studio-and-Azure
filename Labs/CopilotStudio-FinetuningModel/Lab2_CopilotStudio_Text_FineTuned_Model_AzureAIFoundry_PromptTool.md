# Lab 2 — Copilot Studio × Azure AI Foundry: Fine‑tuned Text Model + Prompt Tool

## Summary
In this lab you will **fine‑tune a text model** in **Azure AI Foundry**, deploy it to a managed endpoint, and consume it from **Copilot Studio**. You will implement two complementary integration patterns:
- **HTTP Action Tool** — to invoke **your fine‑tuned endpoint** directly.
- **Prompt Tool** — a **Prompt‑mode Tool** in Copilot Studio to template instructions, validate outputs, and add guardrails around your Action.

---

## Learning objectives
1. Prepare domain data and run **baseline evaluation** with Azure AI Evaluation tools.  
2. Execute a **fine‑tuning job** in Azure AI Foundry and deploy the resulting model.  
3. Integrate the endpoint via an **HTTP Action** in Copilot Studio.  
4. Create a **Prompt Tool** (Prompt builder) with input schema and output template.  
5. Combine generative triggers with Tool orchestration, and compare **baseline vs fine‑tuned** performance.

---

## Prerequisites
- Azure subscription with access to **Azure AI Foundry** (project & model deployment permissions).  
- Copilot Studio environment with **publish** rights and message capacity.  
- Curated text dataset for the target domain (no PII; license‑compliant).

> References:  
> - Azure AI Foundry model catalog & deployment: Microsoft Learn.  
> - Copilot Studio Prompt builder model options & settings (default **GPT‑4.1 mini** and others may be available).  
> - Azure AI Evaluation & Monitoring guidance (metrics, safety, groundedness).  
> - Copilot Studio extensibility (actions/plugins) and access/licensing.

---

## Architecture

```text
[User (Teams/Web)]
   ↕
[Copilot Studio Agent — Generative or Classic]
   ├─ Tool A: HTTP Action → [Azure AI Foundry Endpoint — Fine‑tuned Text Model]
   └─ Tool B: Prompt Tool (built‑in model) → [Post‑process / validation / templating]
```

---
## Part 1 — Data preparation & baseline evaluation
For illustration purposes, the training and validation datasets have been made ready for you. Each dataset contains only 10 samples, and each sample consists of a single-turn Q&A pair. [sample dataset](https://github.com/Azure/LLM-Fine-Tuning-Azure/tree/main/labs/fine_tuning_notebooks/gpt_fine_tuning)
### 1.1 Curate datasets
- Prepare **train**, **validation**, and **test** splits.
- Format in **JSONL** compatible with the target base model (prompt‑completion or chat turns).
- Remove or mask **PII**; ensure licensing and consent for all data.


**Example `train.jsonl` (chat format):**
```jsonl
{"messages": 
    [{"role": "system", "content": "Clippy is a factual chatbot that is also sarcastic."}, 
     {"role": "user", "content": "Who discovered Antarctica?"}, 
     {"role": "assistant", "content": "Some chaps named Fabian Gottlieb von Bellingshausen and Mikhail Lazarev, as if they don't teach that in every school!"}]}

{"messages": 
    [{"role": "system", "content": "Clippy is a factual chatbot that is also sarcastic."},
     {"role": "user", "content": "What is the biggest ocean?"}, 
     {"role": "assistant", "content": "The Pacific Ocean. It's not like it's a small pond or anything."}]}
```

### 1.2 Establish a baseline
- In Azure AI Foundry, evaluate your **candidate base model** with a representative **prompt set** (held‑out test).  
- Use **Azure AI Evaluation SDK** and choose metrics relevant to your domain (accuracy, coherence, safety signals, groundedness where applicable).  
- Document baseline results to compare post fine‑tune.

---

## Part 2 — Fine‑tuning in Azure AI Foundry
In this section, we’ll walk through a step-by-step guide on how to fine-tune the GPT-4.1-mini model using the AI Foundry Dashboard.

### Step 1: Create a Project in Azure AI Foundry

1. Navigate to https://ai.azure.com/ and sign in with your Azure credentials.
2. On the landing page, click the **+ Create new** button in the top-right corner to create a new project.
<ol><img src="../images/screenshot-create-project.png" alt="Screenshot of creating a new project in Azure AI Foundry" width="600"/></ol>

3. Provide a name for your project, configure other settings such as region, resource group etc., and then select **Create**.  
<ol><img src="../images/screenshot-create-project-config.png" alt="Screenshot of configuring the project settings" width="600"/></ol>

---

### Step 2: Launch the *Fine-tune with your own data* Wizard

1. Inside your project, go to the **Fine-tuning** pane.
2. Click **Fine-tune model** to open the wizard.
<ol><img src="../images/screenshot-launch-finetune-wizard.png" alt="Screenshot of launching the fine-tune wizard" width="600"/></ol>

---

### Step 3: Select the *Base model*

1. In the **Base models** pane, choose **gpt-4.1-mini** from the dropdown.
2. Click **Next** to proceed.

> 🧠 *gpt-4.1-mini is optimized for low-latency inference and supports supervised fine-tuning.*

<ol><img src="../images/screenshot-select-base-model.png" alt="Screenshot of selecting the base model" width="600"/></ol>

---

### Step 4: Upload your *Training data*

1. Choose your fine-tuning method: **Supervised** or **Direct Preference Optimization** or **Reinforcement**.
2. Upload your training data using one of the following options:
   - **Upload files** from your local machine.
   - **Azure blob or other shared web locations**.
   - **Existing files on this resource** (already registered in Azure AI Foundry).

> 📌 *Ensure your data is in JSONL format with UTF-8 encoding and that you have the necessary permissions (e.g., Azure Blob Storage Contributor).*

<ol><img src="../images/screenshot-upload-training-data.png" alt="Screenshot of uploading training data" width="600"/></ol>

Assume we want to **Upload files** from our local machine.
<ol><img src="../images/screenshot-upload-training-data-display.png" alt="Screenshot of displaying uploaded training data" width="600"/></ol>

---

### Step 5 (Optional): Add *Validation data*

Validation data is optional but recommended. Upload it using the same method as training data.
<ol><img src="../images/screenshot-upload-validation-data.png" alt="Screenshot of uploading validation data" width="600"/></ol>

---

### Step 6 (Optional): Configure *Advanced options*

You can customize hyperparameters such as:
- Epochs
- Batch size
- Learning rate
- Warmup steps

Or leave them at default values.
<ol><img src="../images/screenshot-advanced-options.png" alt="Screenshot of advanced configuration options" width="600"/></ol>

> 🔧 For tuning the hyperparameters, one can refer to the MS Learn document [here](https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/fine-tuning?tabs=turbo%2Cpython&pivots=programming-language-studio#configure-advanced-options) for a detailed explanation.

---

### Step 7: Review and *Submit*

1. Review your configuration.
2. Click **Submit** to start the fine-tuning job.
3. Monitor progress in the **Status** column of the **Fine-tuning** pane.
<ol><img src="../images/screenshot-review-status.png" alt="Screenshot of reviewing the status of the fine-tuning job" width="600"/></ol>

> ⏱️ *Training duration depends on dataset size and selected parameters.*

When the fine-tuning process finishes, you will see the **Status** showing **Completed**.
<ol><img src="../images/screenshot-review-status-completed.png" alt="Screenshot of completed status of the fine-tuning job" width="600"/></ol>

You can also review the various **Metrics** of your fine-tuned model.
<ol><img src="../images/screenshot-review-metrics.png" alt="Screenshot of reviewing metrics of the fine-tuning job" width="600"/></ol>

---

### Step 8: *Deploy* your fine-tuned model

1. Once training completes, select your model in the **Fine-tuning** pane.
2. Click **Use this model**.
<ol><img src="../images/screenshot-deploy-model.png" alt="Screenshot of deploying the fine-tuned model" width="600"/></ol>

4. In the **Deploy model** dialog, enter a deployment name and click **Deploy**.
<ol><img src="../images/screenshot-deploy-model-config.png" alt="Screenshot of configuring the deployment of the fine-tuned model" width="600"/></ol>

---

### Step 9: *Test and use* your deployed model

- Use the **Playgrounds** in Azure AI Foundry to test your model interactively.
<ol><img src="../images/screenshot-deploy-model-completed.png" alt="Screenshot of completed deployment of the fine-tuned model" width="600"/></ol>

<ol><img src="../images/screenshot-test-model.png" alt="Screenshot of testing the deployed model" width="600"/></ol>

- Or integrate it via the Completion API.

---
## Part 3 — Integrate the endpoint via an HTTP Action (Tool)

### 3.1 Create the Action
**Option A — Custom Connector**  
- Name: `FTTextModelConnector`.  
- Security: API key or AAD.  
- Operation `inferText` (POST to `{FOUNDry_ENDPOINT}/inference`).  
- Request (example):
  ```json
  {
    "input": {
      "messages": [
        {"role":"system","content":"<stable domain instructions>"},
        {"role":"user","content":"<user_input>"}
      ],
      "temperature": 0.3,
      "max_tokens": 512
    }
  }
  ```
- Response (example):
  ```json
  {
    "result": {
      "completion": "string",
      "meta": {"latency_ms": 0}
    }
  }
  ```
- **Test** and **Publish**.

**Option B — Power Automate flow (HTTP)**  
- Configure *HTTP* POST with the same URL/body.  
- Return `completion` as the flow’s output.

### 3.2 Add & map the Tool in the agent
- **Add Tool** → select the connector operation (or flow).  
- Inputs: `user_input`, `temperature` (optional), `context` (optional).  
- Outputs: `completion`, `meta`.

---

## Part 4 — Create a Prompt Tool (Prompt‑mode Tool) in Copilot Studio

> Purpose: The **Prompt Tool** uses the models available inside Copilot Studio’s Prompt builder (e.g., **GPT‑4.1 mini** by default). It’s ideal for templating instructions, **validating/normalizing** outputs from your fine‑tuned model, or adding safety checks—without calling your external endpoint.

### 4.1 Define the Prompt Tool
1. In the agent, **Add Tool → Prompt**.  
2. **Name**: `FT_PostProcessor`.  
3. **System Prompt** (example):
   ```
   You are a compliance verifier. Review the model's response for: 
   (1) professional tone, (2) no PII leakage, (3) completeness vs. the user's request. 
   If issues exist, return a concise revised response.
   ```
4. **Inputs**:
   - `model_response` (string, required)  
   - `user_request` (string, required)  
   - `policy_notes` (string, optional)
5. **Output schema** (template):
   - `valid` (boolean)  
   - `observations` (string)  
   - `final_response` (string)
6. **Model selection**: Keep default or choose a higher tier if available in your tenant’s Prompt builder.
7. **Test** with a representative `model_response`.

### 4.2 Orchestrate both Tools in Generative mode
- In **Instructions**, tell the agent to:
  - First call **`inferText`** (the fine‑tuned endpoint) with the user’s task.  
  - Then call **`FT_PostProcessor`** with `{model_response: completion, user_request: <original request>}`.  
  - Return `final_response` to the user; if `valid = false`, include `observations`.

**Example instruction snippet**:
```
When a user asks a domain question:
1) Use the "inferText" tool to get a domain answer from the fine-tuned model.
2) Pass that answer to the "FT_PostProcessor" Prompt Tool for compliance and polishing.
3) Return only "final_response" to the user; if invalid, add a short note.
```

---

## Part 5 — Classic topic variant (deterministic path)
- Create **Topic**: `Domain Answer (Classic)`.  
- **Trigger phrases**: 6–10 representative intents (short, semantically diverse).  
- **Nodes**:
  1. Ask for any missing slots (e.g., claim number).  
  2. **Call an action** → `inferText`.  
  3. **Call an action** → `FT_PostProcessor`.  
  4. Respond with `final_response`.  
- Use **Topic overlap detection** to reduce ambiguity across classic topics.

---

## Part 6 — A/B testing & evaluation
- Prepare a fixed **prompt set** from real scenarios (sanitized).  
- Compare **baseline vs fine‑tuned** using Azure AI Evaluation (quality, safety, groundedness where applicable).  
- Track **latency** and **token/throughput** signals (if available from your endpoint).  
- Capture **human feedback** (thumbs up/down, comments) from agent sessions.

---

## Troubleshooting
- **Generic responses**: Lower `temperature`; enrich `system` message; verify domain terminology in training data.  
- **Hallucinations**: Add retrieval of authoritative snippets (optional), or tighten prompts; add stronger checks in the Prompt Tool.  
- **Auth failures**: Verify API key / AAD scope and connector policy.  
- **Prompt Tool not invoked**: Emphasize the orchestration order in Instructions; ensure the Tool is enabled.

---

## Governance & security
- Respect **data minimization** and exclude PII from training data.  
- Document **risk assessment** and post‑tune evaluation results.  
- In Copilot Studio, manage **sharing**, **publishing**, and **message capacity**.  
- Consider **Managed Identity** and **private networking** for production endpoints.

---

## Cleanup
- Unpublish/disable the agent used for testing.  
- Delete the **fine‑tuned deployment/endpoint** in Azure AI Foundry to avoid costs.  
- Archive experiment artifacts and evaluation reports.

---

## References
1. **Azure AI Foundry — Models & deployment**: https://learn.microsoft.com/azure/ai-foundry/foundry-models/concepts/models  
2. **Azure AI Evaluation & monitoring** (quality, safety, groundedness): https://learn.microsoft.com/azure/ai-foundry/model-evaluation/overview  
3. **Copilot Studio — Prompt builder model settings** (default model options): https://learn.microsoft.com/microsoft-copilot-studio/authoring/prompts-change-model  
4. **Copilot Studio — Create extensions (Actions/Plugins)**: https://learn.microsoft.com/microsoft-copilot-studio/copilot-extensions-create  
5. **Get access to Copilot Studio & capacity**: https://learn.microsoft.com/microsoft-copilot-studio/access  
6. **Copilot Studio — Overview & modes**: https://learn.microsoft.com/microsoft-copilot-studio/overview  
7. **What’s new in Copilot Studio** (agent features, connectors): https://learn.microsoft.com/microsoft-copilot-studio/whats-new
