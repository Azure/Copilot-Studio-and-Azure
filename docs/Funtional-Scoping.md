# Functional Scoping Template
### Copilot Studio Project Specification

This template captures the minimum set of information required to define a new Copilot Studio project. It includes guided AI prompts in each section to accelerate documentation and ensure consistency across scoping calls.

---

## 1. Project Overview

| Field | Value |
|---|---|
| **Project Name** | [To be defined] |
| **Business Area / Department** | [e.g., HR, Finance, Sales, Operations] |
| **Project Owner** | [Name / Role] |

**Primary Goal**
Describe in 2–3 sentences what the Copilot agent is expected to achieve.

#### Suggested Prompt

```text
You are an expert in Microsoft Copilot Studio and enterprise solution design.
Your task is to write the "Primary Goal" section of a Functional Project Document.

I will provide:
- The project name
- The business area or department
- What the Copilot agent should roughly do (bullet points)

Using that input, generate a concise 2–3 sentence description that:
- Clearly states the main objective of the Copilot agent
- Focuses on measurable business value
- Uses enterprise wording
- Avoids technical detail (save that for other sections)
- Reflects the purpose of the agent from a business-outcome perspective

Format the output as:
Primary Goal: <2–3 sentence description>
```

---

## 2. Business Problem & Use Case

**Problem Statement**
Clearly describe the current challenge or inefficiency.

**Target Users**
- Internal employees
- Customer support agents
- Customers / Partners

**Key Use Cases**
- Use Case #1
- Use Case #2

#### Suggested Prompt

```text
You are a senior solution architect specialized in Microsoft Copilot Studio.
Your task is to write the full "Business Problem & Use Case" section of a Functional Project Document.

I will provide:
- The problem or current inefficiency (bullet points)
- The target users (e.g., internal employees, customer support agents, customers, partners)
- The key use cases (bullet points)

Using that input, generate:

1. Problem Statement:
   - Expand my bullets into a clear, concise description of the business challenge.
   - Explain the impact on users, processes, or efficiency.
   - Write in 2–4 sentences, business-focused, non-technical.

2. Target Users:
   - Rewrite and group the user types I provide.
   - Use enterprise wording (e.g., "Frontline employees", "HR specialists", etc.).

3. Key Use Cases:
   - Convert each bullet point into a short 1–2 sentence use case.
   - Describe what the user wants to achieve and how the Copilot agent helps.
   - Do NOT introduce new functionality not provided by me.

Format the output as:

Business Problem & Use Case

Problem Statement: <expanded description>

Target Users:
- <user group 1>
- <user group 2>

Key Use Cases:
1. <Expanded Use Case #1>
2. <Expanded Use Case #2>

Wait for my input.
```

---

## 3. Expected Outcomes & KPIs

**Success Criteria**
- Reduce handling time
- Automate requests

**KPIs**
- Resolution rate
- Escalation rate
- Time saved

#### Suggested Prompt

```text
You are a senior solution architect specialized in Microsoft Copilot Studio.
Your task is to write the full "Expected Outcomes & KPIs" section of a Functional Project Document.

I will provide:
- The high-level success criteria (bullet points)
- The KPIs for measurement (bullet points)

Your job is to:

1. Success Criteria:
   - Expand each bullet point into 1–2 clear outcome statements.
   - Describe the improvement the Copilot agent should deliver.
   - Keep it business-oriented and measurable, not technical.

2. KPIs:
   - Convert each KPI I provide into a short, clear definition.
   - Explain what the KPI measures and how it proves value.
   - Do NOT introduce new KPIs beyond what I provide.

Format the output exactly like this:

Expected Outcomes & KPIs

Success Criteria:
- <Expanded success criterion 1>
- <Expanded success criterion 2>

KPIs:
- <KPI name>: <short definition>
- <KPI name>: <short definition>
```

---

## 4. User Experience & Channels

**Primary Channels**
- Microsoft Teams
- Microsoft 365 Copilot
- Web chat

**Conversation Style:** Guided or conversational

#### Suggested Prompt

```text
You are a senior solution architect specialized in Microsoft Copilot Studio.
Your task is to write the full "User Experience & Channels" section of a Functional Project Document.

I will provide:
- The primary channels where the Copilot agent will be available
- The preferred conversation style (guided, conversational, hybrid, etc.)

Your job is to:

1. Primary Channels:
   - Expand each channel into a 1–2 sentence description.
   - Describe how the user will interact with the agent in each channel.
   - Use enterprise-level wording, aligned with Copilot Studio capabilities.
   - Do NOT add new channels beyond the ones I provide.

2. Conversation Style:
   - Expand the provided style into a short explanation (2–3 sentences).
   - Describe how the tone, flow, and guidance level will shape the user experience.
   - Keep it functional (no technical details).

Format the output exactly like this:

User Experience & Channels

Primary Channels:
- <Channel 1>: <expanded description>
- <Channel 2>: <expanded description>

Conversation Style: <2–3 sentence explanation based on the input>
```

---

## 5. Functional Requirements

**Core Capabilities**
- Answer questions
- Perform actions
- Collect structured input

**Exception Handling**
- Escalation to humans
- Logging

#### Suggested Prompt

```text
You are a senior solution architect specialized in Microsoft Copilot Studio.
Your task is to write the full "Functional Requirements" section of a Functional Project Document.

I will provide:
- The core capabilities the Copilot agent must support (bullet points)
- The exception-handling requirements (bullet points)

Your job is to:

1. Core Capabilities:
   - Expand each bullet point into a clear functional requirement.
   - Each requirement should describe what the agent must do and how users benefit.
   - Keep the wording functional, not technical (avoid implementation details).
   - Do NOT introduce new capabilities beyond what I provide.

2. Exception Handling:
   - Convert each bullet point into a concise requirement describing how the agent should
     behave in error, failure, or edge-case scenarios.
   - Include expectations around escalation, logging, fallback responses, or
     channel-appropriate behavior.
   - Keep the tone enterprise-level and focused on reliability.

Format the output exactly like this:

Functional Requirements

Core Capabilities:
- <Expanded requirement 1>
- <Expanded requirement 2>

Exception Handling:
- <Expanded exception handling requirement 1>
- <Expanded exception handling requirement 2>
```

---

## 6. Automation & Integration

**Automation**
- Power Automate
- RPA (if required)

**Integrations**
- Microsoft 365
- Dataverse
- SaaS applications
- APIs

#### Suggested Prompt

```text
You are a senior solution architect specialized in Microsoft Copilot Studio.
Your task is to write the full "Automation & Integration" section of a Functional Project Document.

I will provide:
- The automation components needed (e.g., Power Automate, RPA)
- The integration targets (Microsoft 365, Dataverse, SaaS apps, APIs)

Your job is to:

1. Automation:
   - Expand each automation mechanism into 2–3 sentence functional descriptions.
   - Describe WHEN the agent uses automation and WHAT business outcome it produces.
   - Keep it functional, not technical (no trigger/connector details unless provided by me).

2. Integration:
   - Expand each integration target into a clear functional requirement.
   - Explain how the agent will interact with Microsoft 365, Dataverse, SaaS systems, or APIs.
   - Highlight the purpose of each integration (e.g., retrieve data, update records, trigger workflows).
   - Do NOT add integrations beyond the ones I provide.

Format the output exactly like this:

Automation & Integration

Automation:
- <Expanded description of Power Automate>
- <Expanded description of RPA (if required)>

Integrations:
- Microsoft 365: <expanded functional description>
- Dataverse: <expanded functional description>
- SaaS: <expanded functional description>
- APIs: <expanded functional description>
```

---

## 7. AI & Knowledge Sources

**Knowledge Sources**
- SharePoint
- OneDrive
- Websites
- Dataverse

**Advanced AI**
- Azure AI Search
- Azure OpenAI

---

## 8. Governance, Security & Compliance

| Area | Details |
|---|---|
| **Data Sensitivity** | Define applicable sensitivity levels |
| **Security** | Authentication via Microsoft Entra ID and RBAC |
| **Compliance** | GDPR and applicable regulatory requirements |

---

## 9. ALM & Lifecycle

| Area | Details |
|---|---|
| **Environments** | Dev / Test / Production |
| **Deployment** | Via pipelines |
| **Versioning** | Versioning and rollback strategy |

---

## 10. Risks & Constraints

**Risks**
- Data quality
- External dependencies

#### Suggested Prompt

```text
You are a senior solution architect specialized in Microsoft Copilot Studio.
Your task is to write the full "Risks & Constraints" section of a Functional Project Document.

I will provide:
- Key risks (bullet points)
- Key constraints (bullet points, if any)

Your job is to:

1. Risks:
   - Expand each risk into 2–3 sentences.
   - Describe the nature of the risk, why it matters, and the potential impact on the Copilot solution.
   - Keep the risk business-relevant (not technical unless specified).
   - Do NOT introduce new risks beyond the ones I provide.

2. Constraints:
   - Expand each constraint into a clear limiting factor for the project.
   - Explain how the constraint affects design, implementation, timing, or integrations.
   - Keep it objective and aligned with enterprise delivery.

Format the output exactly like this:

Risks & Constraints

Risks:
- <Expanded risk 1>
- <Expanded risk 2>

Constraints:
- <Expanded constraint 1>
- <Expanded constraint 2>
```

---

## 11. Recommended Architecture

Choose the pattern that best fits the project scope:

| Option | When to use |
|---|---|
| **Copilot Studio** | Standard use cases fully covered by native capabilities |
| **Copilot Studio + Azure AI Foundry** | When advanced RAG, custom models, or Azure AI Search are needed |
| **Azure AI Foundry** | Fully custom agent with deep Azure AI integration |

---

## 12. Next Steps

- [ ] Validate scope
- [ ] Confirm integrations
- [ ] Build MVP
- [ ] Deploy to production

---

## AI Scoping Agent

> Use the **Copilot Studio Scoping Agent** to technically validate your project before completing this template. The agent is connected to Microsoft Copilot Studio documentation and helps confirm what is natively supported, what requires Azure AI services, and where potential blockers may exist.

**Access the agent:** [huggingface.co/spaces/saadmsft/copilot-studio-scoping-agent](https://huggingface.co/spaces/saadmsft/copilot-studio-scoping-agent)

### How to use it

**Step 1 — Describe your project**
Share the use case, business challenge, and target users in plain language. No technical detail required at this stage.
*Example: "We want an agent for HR that answers policy questions from employees via Microsoft Teams."*

**Step 2 — Ask technical questions**
Query specific capabilities you plan to use:
- *"Can Copilot Studio connect to SharePoint as a knowledge source?"*
- *"Does it support voice channel with Azure Communication Services?"*
- *"Can I fine-tune the underlying model for my domain?"*
- *"What authentication options are available for external users?"*

**Step 3 — Validate feasibility**
Get grounded, documentation-backed answers on what Copilot Studio handles natively versus what requires Azure AI Search, Azure OpenAI, or custom connectors. Use these answers to make architecture decisions before committing to a direction.

**Step 4 — Document the outcomes**
Transfer the validated findings into the relevant sections above — Functional Requirements, AI & Knowledge Sources, Recommended Architecture — to build a well-scoped, technically accurate project specification.
