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

### Use Template Structure
Azure AI Foundry fine-tuning primarily uses JSONL (JSON Lines) format, where each line contains a separate JSON object representing one training example.
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

### 📊 Data Quality Standards

### ✅ What Makes Good Training Data

**High-Quality Examples:**
- **Comprehensive responses** with detailed explanations
- **Consistent tone and style** throughout each domain
- **Real-world scenarios** that users actually encounter
- **Step-by-step guidance** when appropriate
- **Professional but friendly** communication style

**Proper Format:**
- Valid JSON structure on each line
- Required `messages` array with `role` and `content`
- Appropriate token length (100-2000 tokens per example)
- UTF-8 encoding

### ❌ What to Avoid

- Generic or template-like responses
- Inconsistent formatting or style
- Overly short or minimal answers
- Technical errors or inaccuracies
- Duplicate or near-duplicate examples

### 🔧 Using the Validation Script

The included validation script helps ensure your data meets Azure AI Foundry requirements:

```bash
# Basic validation
python validate_training_data.py your-file.jsonl

# Example output:
============================================================
VALIDATION REPORT: customer-support-training-data.jsonl
============================================================
Status: ✅ VALID
Total lines: 10
Valid examples: 10

Token Statistics:
  Min tokens per example: 156
  Max tokens per example: 445
  Average tokens per example: 289.2
  Total tokens: 2892

📋 RECOMMENDATIONS:
  ✅ File format is valid and ready for fine-tuning!
```

### 🛠 Customization Guidelines

### Adapting for Your Use Case

1. **Modify the System Prompt:**
   ```json
   {"role": "system", "content": "You are a specialist in [YOUR DOMAIN]. [SPECIFIC INSTRUCTIONS]"}
   ```

2. **Add Domain-Specific Examples:**
   - Use your actual user questions
   - Include your preferred response style
   - Add industry-specific terminology

3. **Maintain Consistency:**
   - Keep the same tone throughout
   - Use consistent formatting
   - Follow the same response structure

### Scaling Your Dataset

**Starting Small (10-50 examples):**
- Test your approach
- Validate model behavior
- Iterate on prompt engineering

**Production Scale (100-1000+ examples):**
- Cover edge cases and variations
- Include error scenarios
- Add diverse conversation patterns

### 📈 Fine-Tuning Best Practices

#### Pre-Training Checklist
- [ ] Validate data format with the included script
- [ ] Review examples for accuracy and consistency
- [ ] Ensure diverse coverage of use cases
- [ ] Test with a small batch first
- [ ] Set aside validation data (~20% of total)

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

## Part 3 — Create a Prompt Tool (Prompt‑mode Tool) in Copilot Studio

> Purpose: The **Prompt Tool** uses the models available inside Copilot Studio’s Prompt builder (e.g., **GPT‑4.1 mini** by default). It’s ideal for templating instructions, **validating/normalizing** outputs from your fine‑tuned model, or adding safety checks—without calling your external endpoint.

### 3.1 Define the Prompt Tool
1. In the agent, **Tools → Add Tool → New Tool → Prompt**.  

  <ol><img src="../images/add-prompt-tool-copilot-studio.png" alt="Screenshot of adding a prompt tool to the copilot studio agent" width="600"/></ol> 
2. From the top right **Model** section, chose  Azure AI Foundry models

   <ol><img src="../images/aifoundry-import-copilot-studio.png" alt="Screenshot of importing fine tuned model from Foundry" width="600"/></ol>

3. Fill all the required information, using the deployment information of the fine-tuned model, then **Connect**

   <ol><img src="../images/ft-model-details-copilot-studio.png" alt="Screenshot of importing fine tuned model from Foundry" width="600"/></ol>
4. When you see this confirmation box, then the connection is succeded.

   <ol><img src="../images/ft-model-connected-copilot-studio.png" alt="Screenshot of importing fine tuned model from Foundry" width="600"/></ol>
5. Then, configure the instruction for the prompt tool.  
   
   **System Prompt** (example):
   ```
   You are a compliance verifier. Review the model's response for: 
   (1) professional tone, (2) no PII leakage, (3) completeness vs. the user's request. 
   If issues exist, return a concise revised response.
   ```
   
   <ol><img src="../images/agents-ft-pompt-copilot-studio.png" alt="Screenshot of importing fine tuned model from Foundry" width="600"/></ol> 
6. Next step, rename the prompt tool, previously created. To do that, click on the created tool and edit the **Name** : `FT_PostProcessor`.

   <ol><img src="../images/rename-prompt-tool-copilot-studio.png" alt="Screenshot of importing fine tuned model from Foundry" width="600"/></ol>
7. Once configured, your agent "Tool" section, should look as below:

<ol><img src="../images/tool-confirmation-copilot-studio.png" alt="Screenshot of importing fine tuned model from Foundry" width="600"/></ol>

### 3.2 Orchestrate both Tools in Generative mode
- In **Instructions**, tell the agent to:
  - First call **`inferText`** (the fine‑tuned endpoint) with the user’s task.  
  - Then call **`FT_PostProcessor`** with `{model_response: completion, user_request: <original request>}`.  
  - Return `final_response` to the user; if `valid = false`, include `observations`.


<ol><img src="../images/edit-agent-instruction-copilot-studio.png" alt="Screenshot of importing fine tuned model from Foundry" width="600"/></ol>

**Example instruction snippet**:
```
When a user asks a domain question:
1) Use the "inferText" tool to get a domain answer from the fine-tuned model.
2) Pass that answer to the "FT_PostProcessor" Prompt Tool for compliance and polishing.
3) Return only "final_response" to the user; if invalid, add a short note.
```

---

## Part 4 — Classic topic variant (deterministic path)
- Create **Topic**: `Domain Answer (Classic)`.  
- **Trigger phrases**: 6–10 representative intents (short, semantically diverse).  
- **Nodes**:
  1. Ask for any missing slots (e.g., claim number).  
  2. **Call an action** → `inferText`.  
  3. **Call an action** → `FT_PostProcessor`.  
  4. Respond with `final_response`.  
- Use **Topic overlap detection** to reduce ambiguity across classic topics.

---

## Part 5 — A/B testing & evaluation
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
