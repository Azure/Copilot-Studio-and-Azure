# Azure Pricing Skill for GitHub Copilot

This skill enables GitHub Copilot to fetch real-time Azure retail pricing and estimate Copilot Studio agent credit consumption — directly inside your editor.

## What It Does

- **Azure Pricing Lookups**: Queries the public [Azure Retail Prices API](https://prices.azure.com) to return live pricing for any Azure service, SKU, and region.
- **Cost Estimation**: Calculates monthly and annual cost estimates for common Azure workloads (VMs, Functions, Storage, Cosmos DB, AKS, Azure OpenAI, and more).
- **Copilot Studio Estimation**: Estimates Copilot Studio agent credit consumption and USD costs based on your expected usage patterns.

## Prerequisites

| Requirement | Details |
|---|---|
| **GitHub Copilot** | An active [GitHub Copilot](https://github.com/features/copilot) subscription (Individual, Business, or Enterprise) |
| **VS Code** | Version 1.99 or later with the [GitHub Copilot Chat](https://marketplace.visualstudio.com/items?itemName=GitHub.copilot-chat) extension installed |
| **Internet Access** | The skill calls `prices.azure.com` and `learn.microsoft.com` at runtime — no authentication required |

> **Note:** No Azure subscription is needed. The Azure Retail Prices API is public and unauthenticated.

## Setup

### Option 1 — Repository-Level Skill (recommended for teams)

Use this approach when you want everyone who clones the repo to have the skill available automatically.

1. **Copy the skill folder** into your repository:

   ```
   your-repo/
   └── .github/
       └── skills/
           └── azure-pricing/
               ├── SKILL.md            # Skill definition (required)
               └── references/
                   ├── COPILOT-STUDIO-RATES.md
                   ├── COST-ESTIMATOR.md
                   ├── REGIONS.md
                   └── SERVICE-NAMES.md
   ```

   The folder structure must be exactly `.github/skills/azure-pricing/`. GitHub Copilot discovers skills by convention from the `.github/skills/` directory.

2. **Commit and push** the folder to your default branch.

3. **Verify**: Open VS Code, start a Copilot Chat session, and ask something like:

   ```
   How much does a Standard_D4s_v5 VM cost in East US?
   ```

   Copilot should invoke the skill and return live pricing data.

### Option 2 — User-Level Skill (personal setup)

Use this approach when you want the skill available across all your repositories without committing it to each one.

1. **Create the skill directory** in your VS Code user settings location:

   - **Windows**: `%APPDATA%\Code\User\skills\azure-pricing\`
   - **macOS**: `~/Library/Application Support/Code/User/skills/azure-pricing/`
   - **Linux**: `~/.config/Code/User/skills/azure-pricing/`

2. **Copy all files** (`SKILL.md` and the `references/` folder) into that directory.

3. **Restart VS Code** and test with a pricing question in Copilot Chat.

### Option 3 — Install from GitHub

If you want to pull the skill directly from the source repository:

```bash
# Clone the repo (or use sparse checkout for just the skill folder)
git clone https://github.com/github/awesome-copilot.git

# Copy the skill into your project
cp -r awesome-copilot/skills/azure-pricing .github/skills/azure-pricing
```

Then commit the `.github/skills/azure-pricing/` folder to your repository.

## Folder Structure

```
azure-pricing/
├── SKILL.md                            # Main skill definition — triggers, API usage, and instructions
└── references/
    ├── COPILOT-STUDIO-RATES.md         # Copilot Studio billing rates, estimation formulas, and examples
    ├── COST-ESTIMATOR.md               # Azure cost estimation formulas by service type
    ├── REGIONS.md                      # Azure region name → armRegionName mapping table
    └── SERVICE-NAMES.md                # Case-sensitive Azure service names for API filters
```

| File | Purpose |
|---|---|
| `SKILL.md` | Core skill. Defines when/how Copilot should fetch pricing and estimate costs. |
| `references/COPILOT-STUDIO-RATES.md` | Cached Copilot Studio credit rates and estimation formulas (fallback when live fetch is unavailable). |
| `references/COST-ESTIMATOR.md` | Formulas for converting Azure unit prices into monthly/annual estimates for VMs, Functions, Storage, Cosmos DB, AKS, OpenAI, and more. |
| `references/REGIONS.md` | Maps display names (e.g., "East US") to API values (e.g., `eastus`) and common user aliases. |
| `references/SERVICE-NAMES.md` | Lists correct case-sensitive `serviceName` values for the Azure Retail Prices API. |

## Example Prompts

Once the skill is set up, try these in Copilot Chat:

| Prompt | What It Does |
|---|---|
| *"How much does a D4s v5 VM cost per month in West Europe?"* | Fetches VM pricing and calculates monthly cost |
| *"Compare Azure Functions consumption pricing across East US and West US 2"* | Retrieves and compares regional pricing |
| *"What's the cost of Azure Cosmos DB serverless at 10M RU/s per month?"* | Fetches Cosmos DB pricing and applies serverless formula |
| *"Estimate Copilot Studio costs for 500 users with 20 interactions/month"* | Calculates credit consumption and USD cost |
| *"How much does GPT-4o cost on Azure OpenAI in East US?"* | Queries Foundry Models pricing for OpenAI models |
| *"Show me 1-year reserved instance pricing for Standard_E8s_v5"* | Retrieves reservation pricing with savings plan data |

## How It Works

1. **Trigger**: Copilot detects a pricing-related question based on the skill's description in `SKILL.md`.
2. **Filter**: The skill builds an OData filter string from your question (service, region, SKU, price type).
3. **Fetch**: Copilot calls `https://prices.azure.com/api/retail/prices` with the constructed filter.
4. **Calculate**: Unit prices are converted to monthly/annual estimates using the formulas in `references/COST-ESTIMATOR.md`.
5. **Respond**: Results are presented in a summary table with service, SKU, region, unit price, and estimated costs.

For Copilot Studio questions, the skill also fetches live billing rates from [Microsoft Learn](https://learn.microsoft.com/en-us/microsoft-copilot-studio/requirements-messages-management) and applies the estimation formulas from `references/COPILOT-STUDIO-RATES.md`.

## Troubleshooting

| Issue | Solution |
|---|---|
| Skill not triggering | Ensure the folder is at `.github/skills/azure-pricing/` and `SKILL.md` exists at the root of that folder |
| Empty pricing results | The API is case-sensitive — check `references/SERVICE-NAMES.md` for correct service names |
| Missing savings plan data | The skill uses `api-version=2023-01-01-preview` by default, which includes savings plan data |
| Incorrect region | Check `references/REGIONS.md` for the correct `armRegionName` mapping |
| Copilot Studio rates seem outdated | The skill fetches live rates from Microsoft Learn; `references/COPILOT-STUDIO-RATES.md` is a fallback cache |

## Contributing

To update the cached reference data:

1. **Service names**: Check the [Azure Retail Prices API](https://prices.azure.com/api/retail/prices) for new or renamed services.
2. **Regions**: Review the [Azure regions](https://azure.microsoft.com/en-us/explore/global-infrastructure/geographies/) page for new regions.
3. **Copilot Studio rates**: Update from the [billing rates documentation](https://learn.microsoft.com/en-us/microsoft-copilot-studio/requirements-messages-management).
4. **Cost formulas**: Verify formulas against the [Azure pricing calculator](https://azure.microsoft.com/en-us/pricing/calculator/).

## License

This skill is part of the [awesome-copilot](https://github.com/github/awesome-copilot) repository and follows its license terms.
