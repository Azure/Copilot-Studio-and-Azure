// Parameter file for azd deployments. azd normally reads env vars from the
// `.azure/<env>/.env` file it writes after `azd init`, but this file lets you
// deploy via `az deployment group create` without azd.
//
// Under azd, `environmentName`, `location`, and `principalId` are set
// automatically from your `azd init` answers and `az account show`.

using './main.bicep'

param environmentName = readEnvironmentVariable('AZURE_ENV_NAME', 'voice-channel')
param location        = readEnvironmentVariable('AZURE_LOCATION', 'swedencentral')
param principalId     = readEnvironmentVariable('AZURE_PRINCIPAL_ID', '')

// Voice Live model the IT Assistant agent uses. gpt-realtime-mini is the
// low-cost native-audio option; gpt-realtime is the premium choice.
param voiceLiveModel = 'gpt-realtime-mini'

// TTS voice the web UI hears. HD voices live in: swedencentral, eastus,
// eastus2, westus2, centralindia, southeastasia, westeurope.
param voiceName = 'en-US-Ava:DragonHDLatestNeural'

// Display name of the Copilot Studio backend agent.
param mcsAgentName = 'Microsoft Learn Assistant'
