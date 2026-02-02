# Fraud Investigation Quick Reference Guide
## For Copilot Studio Knowledge Upload

This document contains quick reference information for fraud analysts. Upload this to Copilot Studio as a Knowledge source.

---

## 📊 Reporting Thresholds

### Currency Transaction Report (CTR)
| Item | Value |
|------|-------|
| **Threshold** | $10,000 in cash |
| **Aggregation** | Multiple transactions totaling $10,000+ in one business day |
| **Filing Deadline** | 15 calendar days from transaction date |
| **Form Number** | FinCEN Form 112 |
| **Exemptions** | Banks, government agencies, listed companies (with proper documentation) |

### Suspicious Activity Report (SAR)
| Item | Value |
|------|-------|
| **Bank Threshold** | $5,000 (or $0 if insider abuse) |
| **MSB Threshold** | $2,000 |
| **Filing Deadline** | 30 calendar days from detection |
| **Extended Deadline** | 60 days if no suspect identified |
| **Retention Period** | 5 years |
| **Form Number** | FinCEN Form 111 |
| **Confidentiality** | Never disclose SAR existence to subject |

### Wire Transfer Recordkeeping
| Item | Value |
|------|-------|
| **Threshold** | $3,000 |
| **Travel Rule** | Required for transfers $3,000+ |
| **Recall Window** | Best within 24-48 hours |
| **Retention** | 5 years |

---

## ⏰ Key Deadlines

| Report/Action | Deadline |
|---------------|----------|
| CTR Filing | 15 days from transaction |
| SAR Filing (with suspect) | 30 days from detection |
| SAR Filing (no suspect) | 60 days from detection |
| SAR Supporting Documentation | Retain 5 years |
| CTR Supporting Documentation | Retain 5 years |
| Wire Recall Request | Within 24-48 hours (best results) |
| Account Freeze Review | Within 48 hours |
| Customer Notification (account freeze) | As required by policy, unless law enforcement hold |

---

## 💰 Common Thresholds Quick List

- **$2,000** - SAR threshold for Money Service Businesses (MSBs)
- **$3,000** - Wire transfer recordkeeping / Travel Rule threshold
- **$5,000** - SAR threshold for banks
- **$10,000** - CTR filing threshold (cash)
- **$100,000** - Enhanced approval required for account freeze (typical)

---

## 📋 SAR Narrative Elements (5 W's + H)

When writing a SAR narrative, include:

1. **WHO** - Subject(s), victim(s), account holder(s)
2. **WHAT** - Type of suspicious activity, transactions involved
3. **WHEN** - Dates and timeline of activity
4. **WHERE** - Locations, jurisdictions, IP addresses
5. **WHY** - Red flags that triggered the report
6. **HOW** - Method used to conduct the suspicious activity

---

## 🚨 Priority Levels

| Priority | Description | Examples |
|----------|-------------|----------|
| 🔴 **CRITICAL** | Active fraud in progress | Unauthorized wire pending, ATO with live session |
| 🟠 **HIGH** | Imminent risk or significant loss | Elder exploitation detected, large BEC attempt |
| 🟡 **MEDIUM** | Requires investigation | Unusual patterns, compliance questions |
| 🟢 **LOW** | General inquiries | Training questions, documentation help |

---

## 📞 Internal Contacts

| Department | Contact | Use For |
|------------|---------|---------|
| BSA/AML Compliance | compliance@bank.com | SAR questions, regulatory guidance |
| Fraud Operations | fraud-ops@bank.com | Active fraud cases, account freezes |
| Legal Department | legal@bank.com | Subpoenas, law enforcement requests |
| Information Security | infosec@bank.com | Data breaches, cyber incidents |
| Customer Service Escalation | cs-escalation@bank.com | Customer complaints related to fraud |

---

## 🔐 Account Action Types

### Freeze Types
| Type | Description | Use When |
|------|-------------|----------|
| **Full Freeze** | No debits or credits | Confirmed fraud, law enforcement hold |
| **Debit Block** | No outgoing transactions | Suspected unauthorized access |
| **Wire Block** | Block wire transfers only | Suspected BEC or ATO |
| **Partial Hold** | Hold specific amount | Disputed transaction |

### Approval Requirements
- Balance < $10,000: Analyst approval
- Balance $10,000 - $100,000: Supervisor approval
- Balance > $100,000: Manager + Compliance approval

---

## 📝 Common Fraud Type Codes

| Code | Fraud Type |
|------|------------|
| ATO | Account Takeover |
| BEC | Business Email Compromise |
| SIF | Synthetic Identity Fraud |
| MM | Money Mule |
| STR | Structuring |
| ACH | ACH/Check Fraud |
| WF | Wire Fraud |
| EFE | Elder Financial Exploitation |
| ROM | Romance Scam |
| ID | Identity Theft |

---

## ⚖️ Key Regulations Reference

| Regulation | Description |
|------------|-------------|
| **BSA** | Bank Secrecy Act - Foundation for AML compliance |
| **AML** | Anti-Money Laundering requirements |
| **31 USC 5324** | Structuring statute - illegal to structure transactions |
| **Regulation E** | Electronic fund transfer consumer protections |
| **OFAC** | Office of Foreign Assets Control - sanctions screening |
| **KYC** | Know Your Customer requirements |
| **CDD** | Customer Due Diligence rule |
| **EDD** | Enhanced Due Diligence for high-risk customers |

---

## 🔍 Red Flag Categories

### Account Opening Red Flags
- Multiple applications with similar information
- Inconsistent or unverifiable information
- Unusual urgency to open account
- Reluctance to provide required documentation

### Transaction Red Flags
- Transactions just under reporting thresholds
- Rapid movement of funds (in and out quickly)
- Round-dollar transactions
- Transactions inconsistent with customer profile

### Behavior Red Flags
- Customer appears coached or nervous
- Third party directing the customer
- Reluctance to explain transaction purpose
- Frequent address or contact changes

---

## 📊 Wire Recall Success Rates (Industry Estimates)

| Timeframe | Success Rate |
|-----------|--------------|
| Within 24 hours | 50-70% |
| 24-48 hours | 30-50% |
| 48-72 hours | 10-30% |
| Beyond 72 hours | <10% |

**Note:** International wires and cryptocurrency conversions significantly reduce recall success.

---

## ✅ Quick Checklist: New Fraud Case

- [ ] Document initial report (date, time, reporter)
- [ ] Assess priority level
- [ ] Secure the account (freeze/block as needed)
- [ ] Preserve evidence
- [ ] Notify required parties (supervisor, compliance)
- [ ] Begin investigation documentation
- [ ] Set SAR filing reminder (30-day deadline)

---

*Last Updated: January 2026*
*For detailed guidance, consult the Foundry Knowledge Agent*
