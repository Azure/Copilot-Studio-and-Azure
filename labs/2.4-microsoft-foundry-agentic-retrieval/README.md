# 2.4 Microsoft Foundry Agentic Retrieval with Foundry IQ
## Copilot Studio + Foundry IQ Multi-Source Knowledge Agents



> ⚠️ **EDUCATIONAL USE ONLY**: This workshop is designed for hands-on learning and experimentation. It is **not intended or recommended for production use**. For production deployments, additional security, error handling, monitoring, and enterprise features would be required.

> 🚨 **CRITICAL: SAME TENANT REQUIREMENT**: Copilot Studio and Microsoft Foundry (Azure AI Foundry) **must be in the same Microsoft Entra ID (Azure AD) tenant** for the agents to communicate. This solution will NOT work if they are in different tenants. Ensure your Copilot Studio environment and Azure AI Foundry project are both associated with the same tenant before proceeding.

---

## Objectives

This lab showcases the convergence of Microsoft's most advanced AI technologies—**Microsoft Foundry**, **Foundry IQ**, and **Copilot Studio**—working in harmony to create intelligent, knowledge-grounded agents that transform how enterprises work.

## Prerequisites

It's required to have completed **[Lab 0.0 - Create an agent](../0.0-create-an-agent/0.0-create-an-agent.md)** and **[Lab 1.4 AI Search](../1.4-ai-search/1.4-ai-search.md)** to follow this part.

## Contents

### 🏭 Microsoft Foundry (Azure AI Foundry)

**Microsoft Foundry** is the unified platform for building, deploying, and managing enterprise AI applications. It brings together:

- **Model Catalog**: Access to the latest foundation models (GPT-4o, Claude, Llama, and more)
- **Agent Framework**: Build sophisticated AI agents with tools, memory, and reasoning
- **Enterprise Security**: Built-in governance, compliance, and data protection
- **Unified Experience**: One platform for the entire AI development lifecycle

> *"Microsoft Foundry is where AI innovation meets enterprise reality."*

### 🧠 Foundry IQ: The Knowledge Revolution

**[Foundry IQ](https://techcommunity.microsoft.com/blog/azure-ai-foundry-blog/foundry-iq-unlocking-ubiquitous-knowledge-for-agents/4470812)** is Microsoft's breakthrough unified knowledge layer that transforms how AI agents access and reason over enterprise data. It's not just RAG—it's **intelligent, multi-source knowledge retrieval** that understands context and intent.

**What makes Foundry IQ revolutionary:**

| Feature | Traditional RAG | Foundry IQ |
|---------|----------------|------------|
| **Source Selection** | Manual, single index | 🤖 AI automatically selects relevant sources |
| **Query Planning** | Simple similarity search | 🧠 Agentic retrieval with reasoning |
| **Response Quality** | Often fragmented | ✨ **36% better relevance** ([source](https://techcommunity.microsoft.com/blog/azure-ai-foundry-blog/foundry-iq-boost-response-relevance-by-36-with-agentic-retrieval/4470720)) |
| **Multi-Source** | Complex integration | 🔗 Native multi-index querying |
| **Grounding** | Basic citations | 📚 Rich citations with source attribution |

**Key Capabilities:**
- **🎯 Agentic Retrieval**: The AI *plans* its search strategy, queries multiple sources, and synthesizes coherent responses
- **📊 Multi-Source Knowledge Bases**: Combine fraud patterns, regulations, and procedures in one queryable layer
- **🔐 Enterprise Security**: Document-level permissions, audit trails, and compliance
- **⚡ Real-Time Updates**: Knowledge stays current as documents change

> 📖 **Learn More**: [Foundry IQ Knowledge Retrieval Documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/how-to/tools/knowledge-retrieval?view=foundry&tabs=foundry%2Cpython)

### 💬 Copilot Studio: The Conversation Layer

**Copilot Studio** is Microsoft's low-code platform for building conversational AI experiences. It excels at:

- **Natural Dialogue**: Intuitive conversation flows that feel human
- **Rapid Development**: Build agents in minutes, not months
- **Enterprise Integration**: Connect to Microsoft 365, Dynamics 365, and custom APIs
- **Multi-Channel**: Deploy to Teams, web, mobile, and custom apps

### 🤝 The Magic: When They Work Together

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│   💬 COPILOT STUDIO          🔗 CONNECTED AGENTS        🧠 FOUNDRY IQ       │
│   ────────────────           ─────────────────          ───────────         │
│                                                                             │
│   • Natural conversation     • Seamless routing         • Deep knowledge    │
│   • Quick lookups            • Context passing          • Multi-source      │
│   • User experience          • Orchestration            • Agentic retrieval │
│   • Low-code speed           • Best of both worlds      • 36% better results│
│                                                                             │
│   "Hi, I need help"    →    Routes to right agent   →   Expert analysis     │
│   "CTR threshold?"     →    Answers directly        →   (not needed)        │
│   "ATO red flags?"     →    Calls Foundry agent     →   Detailed patterns   │
│   Complex scenario     →    Combines both           →   Comprehensive guide │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**This architecture delivers:**

| Benefit | How It's Achieved |
|---------|-------------------|
| **⚡ Speed** | Copilot handles quick lookups instantly |
| **🎯 Accuracy** | Foundry IQ provides grounded, cited responses |
| **🧠 Intelligence** | Agentic retrieval selects the right knowledge sources |
| **💼 Enterprise-Ready** | Same-tenant security, audit trails, compliance |
| **📈 Scalability** | Low-code for conversation, code-first for depth |

> *"The future of enterprise AI isn't choosing between low-code and code-first—it's connecting them intelligently."*

---

## 💼 Business Use Case: AI-Powered Fraud Investigation System

### The Challenge

Financial institutions face significant challenges in fraud investigation:

**Traditional Pain Points:**
- ⏱️ **Slow Investigation Times**: Average fraud cases take 5-10 days due to manual research across multiple systems
- 📚 **Siloed Information**: Investigators must search across multiple databases, regulations, and procedure manuals
- 💰 **High Compliance Costs**: Manual SAR filing and regulatory research requires specialized expertise
- 🔍 **Inconsistent Detection**: Different analysts may miss fraud patterns or misinterpret regulations
- ❌ **Knowledge Gaps**: New investigators take months to learn fraud patterns and compliance requirements

### The AI-Powered Solution

This lab demonstrates **Foundry IQ** - Microsoft's unified knowledge layer that enables AI agents to intelligently query multiple unstructured knowledge sources through a single endpoint.

**How This Helps Your Business:**

#### 1. **Unified Knowledge Access** 🧠
- Single AI agent queries across 3 specialized knowledge bases simultaneously
- Automatic source routing - the right knowledge source is selected based on the question
- No more switching between systems or searching multiple databases
- **Business Impact**: 80% reduction in research time per case

#### 2. **Fraud Pattern Intelligence** 🚨
- Instant access to comprehensive fraud pattern library:
  - Synthetic identity fraud detection
  - Account takeover indicators
  - Money mule network characteristics
  - Business email compromise patterns
  - Elder financial exploitation warning signs
- **Business Impact**: 60% improvement in fraud detection accuracy

#### 3. **Regulatory Compliance Guidance** 📋
- Real-time access to BSA/AML requirements
- SAR filing guidelines and narrative standards
- KYC/CDD procedures and enhanced due diligence requirements
- OFAC sanctions compliance
- **Business Impact**: 90% reduction in compliance errors, faster SAR filing

#### 4. **Investigation Procedure Support** 🔐
- Step-by-step case handling protocols
- Evidence collection and chain of custody guidelines
- Escalation workflows and approval processes
- Case closure standards and documentation requirements
- **Business Impact**: Consistent investigation quality across all analysts

#### 5. **Hybrid Human-AI Workflow** 🤝
- Copilot Studio handles initial triage and case intake
- Foundry Agent provides deep knowledge retrieval
- Humans make final decisions with AI-powered recommendations
- Complete audit trail for regulatory compliance
- **Business Impact**: Handle 3x more cases with same staff

---

## 🏗️ Architecture: The Power of Two Systems

This workshop demonstrates the **Connected Agents Pattern** - combining Copilot Studio's conversational AI and quick reference knowledge with Foundry's deep multi-source knowledge retrieval:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         USER / FRAUD ANALYST                                 │
│                  "Is this transaction suspicious?"                           │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    COPILOT STUDIO (Orchestrator + Quick Reference)          │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │  • Greets users and collects case information                       │    │
│  │  • 📋 QUICK LOOKUPS from uploaded knowledge:                        │    │
│  │      - CTR/SAR thresholds & deadlines                               │    │
│  │      - Fraud type codes (ATO, BEC, MM, etc.)                        │    │
│  │      - Wire recall windows, freeze approvals                        │    │
│  │  • Routes complex questions to Foundry Agent                        │    │
│  │  • 🌟 HYBRID: Combines quick refs + Foundry for rich responses      │    │
│  └────────────────────────────────────────────────────────────────────┘    │
│                              │                                              │
│    Quick Lookups             │        Deep Knowledge Questions              │
│    (Uploaded Knowledge)      │        (Call Foundry Agent)                  │
│    ┌─────────────┐           │                                              │
│    │ Thresholds  │           │                                              │
│    │ Deadlines   │           │                                              │
│    │ Fraud Codes │           │                                              │
│    └─────────────┘           ▼                                              │
└──────────────────────────────┼──────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    FOUNDRY IQ AGENT (Deep Knowledge Expert)                 │
│  ┌────────────────────────────────────────────────────────────────────┐    │
│  │              Intelligent Multi-Source Knowledge Base                │    │
│  │                                                                     │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                │    │
│  │  │ Fraud       │  │ Regulatory  │  │Investigation│                │    │
│  │  │ Patterns    │  │ Compliance  │  │ Procedures  │                │    │
│  │  │ (8 docs)    │  │ (8 docs)    │  │ (8 docs)    │                │    │
│  │  └─────────────┘  └─────────────┘  └─────────────┘                │    │
│  │         │                │                │                        │    │
│  │         └────────────────┴────────────────┘                        │    │
│  │                          │                                         │    │
│  │                          ▼                                         │    │
│  │              ┌─────────────────────┐                              │    │
│  │              │ Agentic Retrieval   │                              │    │
│  │              │ (AI selects sources)│                              │    │
│  │              └─────────────────────┘                              │    │
│  └────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 🔀 Four Response Paths

| Path | When Used | Example |
|------|-----------|---------|
| **Copilot Only** | Greetings, simple intake | "Hi, I need help" |
| **Copilot Knowledge** | Quick lookups | "What's the CTR threshold?" → $10,000 |
| **Foundry Only** | Deep expertise needed | "What are ATO red flags?" → Detailed patterns |
| **🌟 Hybrid (Both)** | Complex scenarios | Money mule case → Quick refs + Deep analysis |

### Why Two Systems Work Better Together

| Capability | Copilot Studio | Foundry Agent | Together |
|------------|----------------|---------------|----------|
| **Conversation** | ⭐ Excellent | Basic | Natural dialogue with deep knowledge |
| **Quick Lookups** | ⭐ Uploaded Knowledge | Overkill | Instant answers for common questions |
| **Deep Knowledge** | ❌ Limited | ⭐ 24 Documents | Comprehensive expertise on demand |
| **Multi-Source Search** | ❌ No | ⭐ Yes | Unified knowledge access |
| **Build Time** | Minutes | Hours | Faster overall with clear roles |
| **Customization** | Drag-and-drop | Full code | Right tool for each job |

### 🎯 The Value Proposition

**Without this architecture:**
- Analysts must search multiple systems manually
- Simple questions require the same effort as complex ones
- No instant context for time-critical situations

**With Copilot Studio + Foundry IQ:**
- **Quick lookups in milliseconds** (Copilot knowledge) - CTR is $10K, SAR in 30 days
- **Deep expertise on demand** (Foundry) - Detailed patterns, regulations, procedures
- **Hybrid responses** (Both) - Instant context + comprehensive guidance together

---

## 📋 What You'll Build

In this hands-on workshop, you'll create:

1. **Foundry IQ Knowledge Base** with 3 knowledge sources:
   - 🚨 Fraud Pattern Intelligence (8 documents)
   - 📋 Regulatory Compliance Guidelines (8 documents)
   - 🔐 Investigation Procedures (8 documents)

2. **Foundry Fraud Analyst Agent** that:
   - Uses Agentic Retrieval to query multiple sources
   - Provides grounded answers with citations
   - Supports complex fraud investigation queries

3. **Copilot Studio Orchestrator** that:
   - Handles conversational intake and triage
   - **Answers quick lookups from uploaded knowledge** (thresholds, deadlines, codes)
   - Routes complex questions to Foundry Agent
   - **Combines both sources for hybrid scenarios**

---

## ⚡ Quick Overview

| What | Description |
|------|-------------|
| **Duration** | ~60 minutes |
| **Skill Level** | Beginner to Intermediate |
| **Main Tools** | Python Notebook, Azure AI Foundry, Copilot Studio |
| **Authentication** | Azure CLI (device code flow) |

---

## 🎯 Before You Start (Prerequisites)

### ✅ Step 1: Azure Login

```bash
az login --use-device-code
```

### ✅ Step 2: Azure AI Foundry Project

You need an Azure subscription with an **AI Foundry project** already created.

**How to verify:**
1. Go to [https://ai.azure.com](https://ai.azure.com)
2. Sign in with your Microsoft account
3. You should see your AI Foundry project listed

### ✅ Step 3: Required Models Deployed

| Model | Purpose |
|-------|---------|
| `gpt-4o` | Chat completions for the agent |
| `text-embedding-3-large` | Vector embeddings for knowledge search |

### ✅ Step 4: Azure AI Search Connection

Your AI Foundry project must have an **Azure AI Search** connection configured. ( We create one conection in lab 1.4).

### ✅ Step 5: Required RBAC Roles

On your **Azure AI Search** service:

| Role | Assigned To | Purpose |
|------|-------------|---------|
| Search Index Data Contributor | Your User | Create indexes, upload documents |
| Search Index Data Reader | Your User + Project Managed Identity | Query indexes |
| Search Service Contributor | Your User | Create knowledge bases |

---

## 🚀 Workshop Steps

### Step 0: Set Up Python Environment (2 min)

```bash
# Create virtual environment
python -m venv .venv

# Activate virtual environment
.venv\Scripts\activate  # Windows
# source .venv/bin/activate  # Linux/Mac

# Install dependencies
pip install -r requirements.txt
```

### Step 1: Configure Environment (5 min)

1. Copy `.env.example` to `.env`
2. Fill in your Azure resource details:

```ini
AI_FOUNDRY_PROJECT_ENDPOINT=https://your-resource.services.ai.azure.com/api/projects/your-project
AZURE_AI_SEARCH_ENDPOINT=https://your-search.search.windows.net
AZURE_OPENAI_ENDPOINT=https://your-openai.openai.azure.com
PROJECT_RESOURCE_ID=/subscriptions/.../projects/your-project
```

### Step 2: Run the Foundry IQ Notebook (30 min)

Open and run [notebooks/foundry-IQ-agents.ipynb](notebooks/foundry-IQ-agents.ipynb):

| Step | What It Does |
|------|--------------|
| Steps 1-2 | Install packages and connect to Azure |
| Step 3 | Generate 24 fraud investigation documents |
| Steps 4-5 | Create 3 vector search indexes with embeddings |
| Steps 6-7 | Create knowledge sources and knowledge base |
| Step 8 | Create Fraud Analyst Agent with MCP tool |
| Step 9 | Test the agent with sample questions |

### Step 3: Set Up Copilot Studio (25 min)

Follow [docs/COPILOT_STUDIO_SETUP.md](docs/COPILOT_STUDIO_SETUP.md) to:
1. Create a new Copilot agent
2. Connect to your Foundry Agent
3. Configure conversation flows
4. Test hybrid scenarios

---

## 🧪 Sample Questions to Test

### Category 1: Copilot Only (Greetings)

| Question | Why Copilot Handles It |
|----------|------------------------|
| "Hi, I need help with a fraud case" | Greeting and intake |
| "Who should I escalate this to?" | Business routing logic |
| "Can you connect me to a human?" | Handoff management |

### Category 2: Quick Lookups (Copilot Knowledge)

These are answered from Copilot's uploaded knowledge file - no Foundry call needed:

| Question | What Copilot Returns |
|----------|---------------------|
| "What's the CTR threshold?" | $10,000 in cash |
| "How long do I have to file a SAR?" | 30 days (60 if no suspect) |
| "What does ATO stand for?" | Account Takeover + all fraud codes |
| "What's the wire recall window?" | 24-48 hours for best success |

### Category 3: Deep Knowledge (Foundry Only)

These require Foundry's knowledge base with 24 detailed documents:

| Question | Knowledge Source Used |
|----------|----------------------|
| "What are the red flags for synthetic identity fraud?" | Fraud Patterns |
| "What are the detailed SAR narrative writing standards?" | Regulatory Compliance |
| "How do I properly freeze an account when fraud is suspected?" | Investigation Procedures |

### 🌟 Hybrid Questions (Both Systems Working Together)

These questions demonstrate the power of the connected architecture - the response combines information from **both Copilot's uploaded knowledge and Foundry's deep expertise**:

#### Hybrid Example 1: Money Mule / Structuring Detection
**User:** "I have a new account opened 3 weeks ago by a 19-year-old college student. The account has received multiple cash deposits of $9,500 each day for the past 5 days, followed immediately by wire transfers overseas. What should I do?"

**Expected Response Includes:**
- CTR threshold: $10,000 - these deposits are structured just below!
- SAR deadline: 30 days from detection
- Fraud codes: MM (Money Mule) + STR (Structuring)
- Priority: 🔴 CRITICAL
- Money mule recruitment patterns targeting young people
- 31 USC 5324 structuring laws and aggregation rules
- Account freeze procedures and customer interview techniques

#### Hybrid Example 2: Account Takeover with Wire Fraud
**User:** "A customer is calling frantically saying there's been a $45,000 unauthorized wire transfer. I can see their email and phone number were changed 2 days ago, and there were login attempts from a new IP address. What's our procedure?"

**Expected Response Includes:**
- ⏰ Wire recall window: 24-48 hours - TIME CRITICAL!
- SAR deadline: 30 days from detection
- Fraud codes: ATO (Account Takeover) + WF (Wire Fraud)
- Priority: 🔴 CRITICAL
- ATO attack pattern analysis and credential compromise indicators
- Regulation E considerations for business accounts
- Wire recall procedures and evidence preservation steps

#### Hybrid Example 3: Business Email Compromise (Prevented)
**User:** "Our commercial client's controller just requested an urgent $125,000 wire to a new vendor in Hong Kong. The email appears to be from the CEO, but when I called the CEO directly, he said he never sent that email. The domain is companny.com vs company.com."

**Expected Response Includes:**
- Fraud code: BEC (Business Email Compromise)
- SAR required: YES - even for prevented fraud attempts!
- SAR deadline: 30 days from detection
- Priority: 🟠 HIGH
- BEC attack pattern analysis - domain spoofing, CEO impersonation
- FinCEN BEC advisories and SAR requirements for attempts
- Evidence preservation and IC3 reporting procedures

#### Hybrid Example 4: SAR Narrative Writing
**User:** "I need to write a SAR narrative for a business email compromise case involving cryptocurrency. What should I include?"

**Expected Response Includes:**
- SAR narrative structure: 5 W's + H (Who, What, When, Where, Why, How)
- Filing deadline: 30 days
- Retention: 5 years
- BEC-specific narrative elements to include
- Cryptocurrency documentation requirements - wallet addresses, exchanges, blockchain hashes
- SAR writing standards and quality review checklist

---

## 📊 Complete Test Matrix

This table shows all 11 test scenarios and which agent handles each:

| # | Scenario | Type | Copilot | Foundry | What It Demonstrates |
|---|----------|------|---------|---------|---------------------|
| 1 | "Hi, I need help" | Greeting | ✅ | ❌ | Copilot handles conversational intake |
| 2 | "What's the CTR threshold?" | Quick Lookup | ✅ | ❌ | Copilot uses uploaded knowledge |
| 3 | "How long for SAR?" | Quick Lookup | ✅ | ❌ | Copilot uses uploaded knowledge |
| 4 | "What does ATO stand for?" | Quick Lookup | ✅ | ❌ | Copilot uses uploaded knowledge |
| 5 | "Red flags for ATO fraud?" | Deep Pattern | ❌ | ✅ | Foundry Fraud Patterns index |
| 6 | "SAR filing requirements?" | Deep Regulatory | ❌ | ✅ | Foundry Regulatory Compliance index |
| 7 | "How to freeze an account?" | Deep Procedure | ❌ | ✅ | Foundry Investigation Procedures index |
| 8 | Money Mule + Structuring | **🌟 HYBRID** | ✅ | ✅ | **Both: Quick refs + deep analysis** |
| 9 | ATO + Wire Fraud | **🌟 HYBRID** | ✅ | ✅ | **Both: Time-critical + procedures** |
| 10 | BEC (Prevented) | **🌟 HYBRID** | ✅ | ✅ | **Both: SAR requirement + patterns** |
| 11 | SAR + Crypto Narrative | **🌟 HYBRID** | ✅ | ✅ | **Both: Framework + specifics** |

**Key Takeaway:** Scenarios 8-11 demonstrate the value of the connected architecture - getting comprehensive responses that combine uploaded knowledge with deep expertise from Foundry.

---

## 📁 Project Structure

```
foundry-copilotstudio/
│
├── 📄 README.md                      ← You are here
├── 📄 requirements.txt               ← Python dependencies
├── 📄 .env.example                   ← Environment template
├── 📄 .env                           ← Your configuration
│
├── 📁 notebooks/
│   └── foundry-IQ-agents.ipynb       ← 🌟 Main workshop notebook (creates Foundry Agent)
│
├── 📁 data/
│   └── copilot_knowledge/
│       └── quick_reference_guide.md  ← 📋 Upload to Copilot Studio as Knowledge
│
└── 📁 docs/
    └── COPILOT_STUDIO_SETUP.md       ← Copilot Studio setup guide + 11 test scenarios
```

---

## 🎓 Key Concepts

### What is Foundry IQ?

**Foundry IQ** is Microsoft's unified knowledge layer for AI agents that:
- Creates **reusable knowledge bases** that can ground multiple agents
- Provides **automatic source routing** - queries go to the right knowledge source(s)
- Uses **agentic retrieval** - AI plans, searches, and synthesizes across sources
- Maintains **enterprise-grade security** with document-level access control
- Delivers **36% better response relevance** compared to traditional RAG approaches

### Connected Agents Pattern

The **Connected Agents Pattern** combines:
- **Copilot Studio** (low-code): Fast to build, excellent for conversation flows
- **Foundry Agents** (code-first): Powerful knowledge retrieval and custom logic

This pattern gives you the best of both worlds - natural conversation with deep domain knowledge.

---

## 📚 Resources

### Foundry IQ & Agentic Retrieval
- [📖 Knowledge Retrieval Documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/how-to/tools/knowledge-retrieval?view=foundry&tabs=foundry%2Cpython) - Official how-to guide
- [🚀 Foundry IQ: Unlocking ubiquitous knowledge for agents](https://techcommunity.microsoft.com/blog/azure-ai-foundry-blog/foundry-iq-unlocking-ubiquitous-knowledge-for-agents/4470812) - Introduction and vision
- [📊 Foundry IQ: 36% better relevance with agentic retrieval](https://techcommunity.microsoft.com/blog/azure-ai-foundry-blog/foundry-iq-boost-response-relevance-by-36-with-agentic-retrieval/4470720) - Performance benchmarks

### Microsoft Foundry (Azure AI Foundry)
- [Azure AI Foundry Documentation](https://learn.microsoft.com/azure/ai-studio/)
- [Azure AI Foundry Agents](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/)

### Copilot Studio
- [Copilot Studio Documentation](https://learn.microsoft.com/microsoft-copilot-studio/)
- [Connected Agents in Copilot Studio](https://learn.microsoft.com/en-us/microsoft-copilot-studio/copilot-ai-plugins)

---

## ❓ Troubleshooting

### "DefaultAzureCredential failed"
```bash
az login --use-device-code
```

### "Search Index Data Reader role required"
Assign the role to your user AND the project managed identity on Azure AI Search.

### "Knowledge source creation failed"
Ensure your Azure AI Search connection is configured in AI Foundry project settings.

---

**Happy Building! 🚀**
