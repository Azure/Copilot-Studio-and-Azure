# Copilot Studio + Azure AI Foundry
## Readiness & Prerequisites Checklist

### Purpose

This document defines the **technical, security, governance, and operational prerequisites** that must be completed **before** a team starts designing and delivering **Copilot Studio agents integrated with Azure AI Foundry** in a customer tenant.

It is intended as a **checklist-style readiness guide** that can be shared with:
- Customers
- Executive sponsors
- IT & security teams
- Platform and governance teams

All items must be reviewed and validated prior to delivery.

---

## 1. Commercial & Contractual Prerequisites

### 1.1 Required Licenses

The customer must have the following licenses in place:

- **Power Platform**
  - Pay-As-You-Go environment enabled
  - Microsoft Copilot Studio license  
  - Copilot credits **or** Microsoft Agent Pre‑Purchase Plan (P3)  
  - *Microsoft 365 Copilot (USL) is also valid, with limitations*
- **Power Platform environment** enabled

If the project also involves **Azure AI Foundry**:

- Azure subscription linked to the tenant
- Azure AI Foundry access (via Azure resource)

✅ **Action**: Confirm SKU, license counts, and assigned users

---

## 2. Identity, Security & Access

### 2.1 Entra ID (Azure AD) Requirements

- Active Entra ID tenant
- Users provisioned for:
  - Copilot Studio makers
  - Azure AI engineers
  - Administrators

**Recommended roles**:
- Copilot Studio: *Environment Maker* / *Environment Admin*
- Azure: *Contributor* or custom RBAC role

✅ **Action**: Role assignments validated

---

### 2.2 Conditional Access & Security Policies

Verify that Conditional Access policies **do not block**:

- Copilot Studio
- Azure AI endpoints
- Power Platform service‑to‑service calls: [Power Platform URLs and IP address ranges](https://learn.microsoft.com/en-us/power-platform/admin/online-requirements)

Review:
- MFA enforcement
- IP restrictions
- Device compliance policies

✅ **Action**: Security sign‑off completed

---

## 3. Power Platform Readiness

### 3.1 Environments

At project start, provision **at least one dedicated environment**:

- **Dev / Test** (mandatory)
- **Prod** (recommended)

**Environment settings**:
- Region aligned with Azure resources
- Dataverse enabled
- Managed Environments enabled (recommended): [Enable Managed Environments](https://learn.microsoft.com/en-us/power-platform/admin/managed-environment-enable)

✅ **Action**: Environment created and accessible

---

### 3.2 DLP (Data Loss Prevention) Policies

Review [DLP](https://learn.microsoft.com/en-us/power-platform/admin/wp-data-loss-prevention) policies to allow:

- Copilot Studio actions
- Required connectors, such as:
  - Dataverse
  - HTTP
  - SharePoint
  - Microsoft Graph
  - Other required services

✅ **Action**: DLP policy exceptions approved

---

## 4. Azure AI Foundry & Azure Setup

### 4.1 Azure Subscription

- Active Azure subscription in the same tenant
- Budget and spending limits defined
- Appropriate region selected (data residency)

✅ **Action**: Subscription confirmed

---

### 4.2 Azure AI Foundry Resources

Required Azure resources:

- Azure AI Foundry project
- Model deployment (e.g. GPT‑4.x or approved model)
- *Optional (for RAG scenarios)*:
  - Azure AI Search
  - Azure Blob Storage
  - Azure Key Vault

✅ **Action**: Foundry project created

---

### 4.3 Networking & Private Access (If Required)

Decision required on:
- Public endpoints  
- Private endpoints (VNET)

If **Private Endpoints** are used:

- VNET created
- DNS configured
- Copilot Studio connectivity validated

✅ **Action**: Network architecture approved

---

## 5. Data Sources & Knowledge Readiness

### 5.1 Knowledge Sources Identified

The customer must identify:

- SharePoint sites
- Files (PDF, DOCX, PPTX)
- Databases
- APIs / line‑of‑business systems
- Connectors
- Sample datasets for document upload or analysis scenarios

> ⚠️ On‑premise integrations are **out of scope**

✅ **Action**: Data inventory completed

---

### 5.2 Data Governance & Ownership

- Content owners assigned
- Data classification confirmed:
  - PII
  - Confidential
  - Public
- Approval for AI ingestion granted

✅ **Action**: Governance approval obtained

---

## 6. Copilot Studio Configuration Readiness

### 6.1 Agent Scope Definition

Before build starts, define:

- Business scenario(s)
- Target users (internal / external)
- Supported channels:
  - Microsoft Teams
  - Microsoft Copilot
  - Web
  - SharePoint
  - Custom application
  - Other channels

✅ **Action**: Scope document approved

---

### 6.2 Authentication Strategy

If accessing secured data, define the authentication model:

- **Microsoft authentication (Entra ID)**  
  - Teams  
  - SharePoint  
  - Power Apps  
  - Microsoft 365 Copilot
- **No authentication**
- **Manual authentication**
  - Channel‑specific configuration

✅ **Action**: Authentication model validated

---

## 8. Delivery & Operating Model

### 8.1 Project Governance

- Project sponsor identified
- Technical owner assigned
- Single Named Point of Contact (SPOC)
- Change management process defined

✅ **Action**: Governance model confirmed

---

## 9. Final Go / No‑Go Checklist

Before consultants start building, all items must be **GREEN**:

- ✅ Licenses active  
- ✅ Hands‑on access granted  
- ✅ Environments and DLP ready  
- ✅ Azure AI Foundry deployed  
- ✅ Required connectors approved  

🚦 **Delivery can only start once all prerequisites are completed**

---
