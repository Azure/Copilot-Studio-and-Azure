# Azure AI Search Lab - Terraform Deployment Guide

This guide provides step-by-step instructions to deploy Azure AI Search infrastructure using Terraform, including AI Foundry and Azure AI Search.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Installation & Setup](#installation--setup)
- [Configuration](#configuration)
- [Deployment Steps](#deployment-steps)
- [Post-Deployment](#post-deployment)
- [Cleanup](#cleanup)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools

1. **Azure CLI**
**Azure CLI**
    - Download: [https://aka.ms/installazurecliwindows](https://aka.ms/installazurecliwindows)
    - Version required: 2.50.0 or later
    
    **Windows Installation:**
    - Use MSI installer (recommended):
      ```terminal
      # Download and run the MSI installer from the link above
      # Or use winget:
      winget install Microsoft.AzureCLI
      ```
    - Or use Chocolatey:
      ```terminal
      choco install azure-cli
      ```
    
    **macOS Installation:**
    - Use Homebrew (recommended):
      ```terminal
      brew update && brew install azure-cli
      ```
    - Or use the installer package:
      ```terminal
      curl -L https://aka.ms/InstallAzureCli | bash
      ```
    
    **Ubuntu/Debian Installation:**
    - Use apt package manager:
      ```terminal
      curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
      ```
    - Or install manually:
      ```terminal
      # Update package index
      sudo apt-get update
      
      # Install required packages
      sudo apt-get install ca-certificates curl apt-transport-https lsb-release gnupg
      
      # Add Microsoft signing key
      curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null
      
      # Add Azure CLI repository
      AZ_REPO=$(lsb_release -cs)
      echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | sudo tee /etc/apt/sources.list.d/azure-cli.list
      
      # Update and install
      sudo apt-get update
      sudo apt-get install azure-cli
      ```
    
    **Verify installation (all platforms):**
    ```terminal
    az --version
    ```

2. **Terraform**
    - Download: [https://www.terraform.io/downloads](https://www.terraform.io/downloads)
    - Version required: 1.5.0 or later
    
    **Windows Installation:**
    - Use Chocolatey:
      ```terminal
      choco install terraform
      ```
    - Or download manually and add to PATH
    
    **macOS Installation:**
    - Use Homebrew (recommended):
      ```terminal
      brew install terraform
      ```
    - Or use tfenv for version management:
      ```terminal
      brew install tfenv
      tfenv install 1.5.0
      tfenv use 1.5.0
      ```
    
    **Ubuntu/Debian Installation:**
    - Add HashiCorp GPG key and repository:
      ```terminal
      wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
      echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
      sudo apt update && sudo apt install terraform
      ```
    - Or download binary manually:
      ```terminal
      wget https://releases.hashicorp.com/terraform/1.5.7/terraform_1.5.7_linux_amd64.zip
      unzip terraform_1.5.7_linux_amd64.zip
      sudo mv terraform /usr/local/bin/
      ```
    
    **Verify installation (all platforms):**
    ```terminal
    terraform version
    ```

### Azure Requirements

1. **Azure Subscription**
   - An active Azure subscription with appropriate permissions
   - Required roles: `Contributor` or `Owner` on the subscription or resource group
   - Get your subscription ID:
     ```terminal
     az account show --query id -o tsv
     ```

2. **Azure Service Provider Registrations**
    - Ensure the following resource providers are registered:
      ```terminal
      az provider register --namespace Microsoft.CognitiveServices
      az provider register --namespace Microsoft.Network
      az provider register --namespace Microsoft.ManagedIdentity
      az provider register --namespace Microsoft.KeyVault
      az provider register --namespace Microsoft.Storage
      ```

3. **Quota Requirements**
   - Azure Open AI services quota in your region.


---

## Installation & Setup

### 1. Authenticate with Azure

```terminal
# Login to Azure
az login

# Set the subscription (replace with your subscription ID)
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# Verify the current subscription
az account show
```

### 2. Initialize Terraform

```terminal
# Initialize Terraform (downloads required providers)
terraform init
```

---

## Configuration

### Required Variables to Customize

Edit the `variables.tf` file or create a `terraform.tfvars` file with your custom values:

#### **Option 1: Edit variables.tf directly**

Open `variables.tf` and modify the following variables:

```terraform
variable "subscription_id" {
  default = "YOUR_SUBSCRIPTION_ID"  # Replace with your Azure subscription ID
}
```

#### **Option 2: Create terraform.tfvars file (Recommended)**

Create a new file named `terraform.tfvars` in the same directory:

```terraform
# terraform.tfvars

# REQUIRED: Your Azure Subscription ID
subscription_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# OPTIONAL: Customize resource names and settings
resource_group_name = "aisearch-lab-rg"
location            = "eastus2"          # Primary region for most resources
```


---

## Deployment Steps

### Step 1: Review the Deployment Plan

```terminal
# Preview what Terraform will create
terraform plan
```

**Review the output carefully**:
- Check resource names
- Verify regions
- Confirm resource types
- Review estimated costs

### Step 2: Deploy the Infrastructure

```terminal
# Apply the Terraform configuration
terraform apply

# When prompted, type 'yes' to confirm
```

**Expected deployment time**: 10-15 minutes

### Step 3: Monitor the Deployment

The deployment will create resources in this order:
1. Resource Group
2. Virtual Network
3. Managed Identity
4. Role Assignments
5. Storage Account & Key Vault
6. AI Foundry Hub
7. AI Foundry Project
8. Azure OpenAI Model deployment
9. Azure AI Search

### Step 4: Verify Deployment

```terminal
# Check the deployed resources
az resource list --resource-group <your-resource-group-name> --output table
```

---

## Post-Deployment

### 1. Retrieve Deployment Outputs

```terminal
# View all outputs
terraform output

# View specific output
terraform output resource_group_name
terraform output ai_search_endpoint
```

### 2. Access Azure Portal

1. Navigate to [Azure Portal](https://portal.azure.com)
2. Find your resource group (use the name from `terraform output`)
3. Verify all resources are running

### 3. Access AI Foundry Portal

1. Go to [Azure AI Foundry](https://ai.azure.com)
2. Sign in with your Azure credentials
3. Select your project
4. Verify the deployments

---

## Cleanup

### Remove All Resources

```terminal
# Destroy all Terraform-managed resources
terraform destroy

# When prompted, type 'yes' to confirm
```

**Warning**: This will permanently delete all resources created by this deployment.

### Verify Cleanup

```terminal
# Check if resource group still exists
az group show --name <your-resource-group-name>

# If it exists, delete manually
az group delete --name <your-resource-group-name> --yes --no-wait
```

---

## Troubleshooting

### Common Issues

#### 1. **Authentication Errors**

```
Error: Error building AzureRM Client: obtain subscription...
```

**Solution**:
```terminal
az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"
```

#### 2. **Resource Name Conflicts**

```
Error: A resource with the ID already exists
```

**Solution**:
- Set `use_random_suffix = true` in `terraform.tfvars`
- Or choose different resource names

#### 3. **Quota Exceeded**

```
Error: Quota exceeded for resource type
```

**Solution**:
- Request quota increase in Azure Portal
- Or choose a different region

#### 4. **Provider Not Registered**

```
Error: The subscription is not registered to use namespace 'Microsoft.XXX'
```

**Solution**:
```terminal
az provider register --namespace Microsoft.CognitiveServices
az provider register --namespace Microsoft.Search
```

#### 5. **Terraform State Lock**

```
Error: Error acquiring the state lock
```

**Solution**:
```terminal
# If you're sure no other process is running
terraform force-unlock <LOCK_ID>
```

### Debug Mode

Enable detailed logging:

```terminal
# Windows terminal
$env:TF_LOG = "DEBUG"
terraform apply

# Reset logging
$env:TF_LOG = ""
```

### Get Help

- **Terraform Documentation**: [https://www.terraform.io/docs](https://www.terraform.io/docs)
- **Azure Provider Docs**: [https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- **Azure Support**: [https://azure.microsoft.com/support](https://azure.microsoft.com/support)

---
## Security Best Practices

1. **Never commit sensitive data** to version control
   - Add `terraform.tfvars` to `.gitignore`
   - Use Azure Key Vault for secrets

2. **Use Managed Identity** for authentication between services
   - Already configured in this deployment

3. **Enable network restrictions**
   - Configure `allowed_ips` in `terraform.tfvars`
   - Use Virtual Network integration

4. **Regular security audits**
   ```terminal
   az security assessment list --query "[?status.code=='Unhealthy']"
   ```

5. **Enable diagnostic logging**
   - Monitor Azure resources through Azure Monitor
   - Set up alerts for critical events

---

## Support

For issues related to:
- **This deployment**: Create an issue in the repository
- **Azure services**: Contact Azure Support
- **Terraform**: Visit [Terraform Community](https://discuss.hashicorp.com/c/terraform-core)

---

