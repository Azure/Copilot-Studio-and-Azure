# Video walkthrough — script / transcript

A speaker-ready script for a ~6–8 minute walkthrough video of this
accelerator. Section headings double as on-screen chapter markers.

---

## 0:00 — Cold open / hook (≈20 s)

> "Power Platform can't natively reach an Azure AI service that's locked
> behind a Private Endpoint — Azure AI Services doesn't trust Power Platform
> the way it trusts, say, Azure Machine Learning. In the next few minutes
> I'll show you how to bridge that gap with VNet injection, and we'll deploy
> the whole thing with a single ARM button."

[On screen: title card — "Azure Content Understanding behind a Private
Endpoint, called from Power Platform"]

---

## 0:20 — The problem (≈40 s)

> "Here's the situation. You set `publicNetworkAccess=Disabled` on your AI
> Services account so it's only reachable through a Private Endpoint inside
> your VNet. Great for security — but now your Power Automate flows and
> Power Apps that used to call the public endpoint just get a `403 Public
> access is disabled`.
>
> The usual escape hatch — `bypass=AzureServices` — doesn't help here. Power
> Platform isn't on the trusted-Microsoft-services list for Cognitive
> Services, so its calls still get blocked.
>
> The supported fix is **Power Platform VNet integration**: a delegated
> subnet in your VNet, plus an Enterprise Policy resource that links your
> Power Platform environment to that subnet. After it's wired up, Power
> Platform injects network interfaces into your subnet and reaches the
> Private Endpoint over Microsoft's backbone."

---

## 1:00 — Architecture walkthrough (≈90 s)

[Switch to the architecture diagram in `docs/ppvnet-acu-solution-architecture.png`]

> "Let's look at what we're building.
>
> **Left side — Power Platform.** Power Apps and Power Automate sit inside
> a Managed Environment. They talk to a custom connector — a thin OpenAPI
> wrapper around the Content Understanding REST API.
>
> **Right side — Azure**, split into two regions because the `unitedstates`
> Power Platform geo requires delegated subnets in two paired Azure
> regions. We'll use `westus` as primary and `eastus` as secondary.
>
> In the **primary region** we have a spoke VNet with two subnets:
>
> * `snet-pe` — hosts the Private Endpoint NIC for the AI Services account.
> * `snet-powerplatform` — empty subnet that's *delegated* to
>   `Microsoft.PowerPlatform/enterprisePolicies`. Power Platform will inject
>   its own NICs here at runtime.
>
> The **AI Services account** itself is `kind: AIServices`, with public
> network access disabled, a custom subdomain enabled (mandatory for
> Private Endpoints on Cognitive Services), and a system-assigned identity.
>
> Three **Private DNS zones** —
> `privatelink.cognitiveservices.azure.com`, `privatelink.openai.azure.com`,
> and `privatelink.services.ai.azure.com` — are linked to the VNet so the
> account's FQDN resolves to the Private Endpoint's private IP from inside
> the network.
>
> In the **secondary region** we have a paired spoke VNet with just the
> delegated `snet-powerplatform` subnet. No PE here — Private Endpoints can
> live in either VNet but we keep ours in primary for simplicity.
>
> Tying it all together is the **Enterprise Policy** — a resource of type
> `Microsoft.PowerPlatform/enterprisePolicies`, kind `vnet`. Its `location`
> is the Power Platform geo name (`unitedstates`), *not* an Azure region —
> that catches a lot of people. It references both delegated subnets, and
> when we link it to our PP environment, Power Platform starts routing
> outbound calls through those subnets."

---

## 2:30 — What we'll deploy (≈30 s)

> "So the deployment will produce: two VNets, one AI Services account, one
> Private Endpoint, three Private DNS zones with VNet links, one Enterprise
> Policy, and finally one Power Platform custom connector. Plus a small
> connectivity test that proves the lockdown works *and* that the VNet path
> works.
>
> Let's deploy it."

---

## 3:00 — Prerequisites (≈30 s)

[Switch to README "Prerequisites" table on screen]

> "Quickly — you'll need:
>
> * An Azure subscription where you're Owner or Contributor.
> * The target Power Platform environment must be a **Managed Environment**
>   — Sandbox environments cannot be linked to an Enterprise Policy.
> * You need to be a **Power Platform** or **Global Administrator** to
>   enable Managed Environment and to perform the link.
> * For the scripted path: PowerShell 7, Azure CLI 2.50+, and the `pac` CLI
>   signed in. The Enterprise Policies PowerShell module installs itself."

---

## 3:30 — Option A: One-click ARM deploy (≈90 s)

[Click the **Deploy to Azure** button in the README]

> "The fastest way is the Deploy to Azure button. It opens a Custom
> deployment blade with the parameters we need.
>
> * **Resource group** — pick or create a new one.
> * **Base name** — a 3-to-11-character lowercase string used to derive
>   resource names. I'll use `prvendcu`.
> * **Location** — primary Azure region. I'll pick `westus` because that's
>   where Content Understanding is supported in my geo.
> * **Secondary location** — `eastus`, the paired region.
> * **Power platform geo** — `unitedstates`. This is the value you'd pass
>   to `Get-AdminPowerAppEnvironment` as a region — it's *not* an Azure
>   region.
> * **Power platform environment ID** — the GUID of the target environment.
>   You can grab it from the Power Platform Admin Center under
>   *Environments → \<your env\> → Environment ID*. It's not the org URL.
> * The four CIDR fields default to `10.50.0.0/16` and `10.51.0.0/16` for
>   the two VNets. Override them if those overlap with anything you
>   already have.
>
> Notice we don't ask for tenant ID or subscription ID — those come from
> the portal session.
>
> Hit **Review + create**, then **Create**, and the template provisions
> everything. It takes about three to four minutes."

[Time-lapse the deployment]

---

## 5:00 — Final step: link the Enterprise Policy (≈60 s)

> "ARM can do everything *except* link the policy to the Power Platform
> environment — that call goes through a Power Platform admin API that
> requires interactive admin auth. So we run one local script.
>
> First, copy `.env.example` to `.env` and fill in `PP_ENVIRONMENT_ID` and
> `PP_TENANT_ID`. The other Azure values can stay at their defaults — they
> aren't used by the link script."

[Show terminal]

```powershell
Copy-Item .env.example .env
code .env   # fill in the two PP values
./scripts/link-enterprise-policy.ps1 -UseDeviceCode
```

> "The `-UseDeviceCode` switch is the safe choice — Az PowerShell's WAM
> popup is unreliable on some hosts. The script installs the
> `Microsoft.PowerPlatform.EnterprisePolicies` module if needed, signs you
> in to Azure, then calls `Enable-SubnetInjection` against your
> environment. When it finishes, the policy's `linkStatus` is `Linked`."

---

## 6:00 — Push the connector + test (≈75 s)

> "Now the connector. The `create-and-test-connector.ps1` script reads the
> AI Services hostname from the deployment outputs, stamps it into the
> swagger, pushes the connector to your environment with `pac connector
> create`, and then runs a connectivity test."

```powershell
./scripts/create-and-test-connector.ps1
```

> "The first call goes from your laptop, over the public internet, to
> `https://<account>.cognitiveservices.azure.com/contentunderstanding/analyzers`.
> We expect a **403 — Public access is disabled**. That confirms the
> lockdown is real.
>
> Now the real proof: open your Power Platform environment, build a quick
> instant-trigger flow, add the **List Analyzers** action from the new
> custom connector, create a connection with your AI Services key, and run
> the flow. You should see a **200 OK** with the list of analyzers.
>
> If you ran the same test from inside the connector designer, you'd
> actually see a 403 — that's not a bug. The designer's *Test operation*
> button routes through the connector authoring host, which is *outside*
> the VNet. Only real flow runs go through subnet injection."

---

## 7:15 — Verify the link via the BAP API (≈30 s)

> "If you ever want to confirm the policy is still linked without opening
> a UI:"

```powershell
. ./scripts/load-env.ps1
$tok = az account get-access-token --resource 'https://service.powerapps.com/' --query accessToken -o tsv
$uri = "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments/$env:PP_ENVIRONMENT_ID" + '?api-version=2019-10-01&$expand=properties.enterprisePolicies'
Invoke-RestMethod -Uri $uri -Headers @{ Authorization = "Bearer $tok" } |
  Select-Object -ExpandProperty properties |
  Select-Object -ExpandProperty enterprisePolicies
```

> "Look for `linkStatus: Linked` in the output."

---

## 7:45 — Common gotchas (≈30 s)

> "Three quick gotchas worth memorising:
>
> 1. The Enterprise Policy resource's `location` must match your PP geo,
>    not an Azure region. Setting `westus` will fail to link.
> 2. To change the policy's subnets later, you have to *unlink* first —
>    the resource is immutable while linked.
> 3. The connector's *Test* button doesn't go through VNet injection.
>    Always validate from a real flow run."

---

## 8:15 — Cleanup + outro (≈15 s)

```powershell
./scripts/link-enterprise-policy.ps1 -Unlink
az group delete -n $env:AZURE_RESOURCE_GROUP --yes --no-wait
```

> "Unlink first, then delete the resource group. That's it — Power
> Platform calling Azure AI Content Understanding through a Private
> Endpoint, end to end. Repo link is in the description. Thanks for
> watching."

[End card with repo URL]

---

## Suggested chapter markers (for YouTube description)

```
0:00  The problem
1:00  Architecture
2:30  What we'll deploy
3:00  Prerequisites
3:30  One-click ARM deploy
5:00  Link the Enterprise Policy
6:00  Push the connector and test
7:15  Verify the link
7:45  Common gotchas
8:15  Cleanup
```
