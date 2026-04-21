using './main.bicep'

// Base name — must be 3-18 chars, lowercase, globally-ish unique because it
// seeds the Foundry custom subdomain and the App Service hostname.
param baseName = 'voicech-01'

// Any Voice Live region. swedencentral is recommended because HD voices are
// supported there (other options: eastus2, westus2, centralindia, southeastasia).
param location = 'swedencentral'

// Voice Live model. gpt-realtime-mini gives low latency native audio at the
// "basic" pricing tier. Switch to gpt-realtime for pro quality or gpt-5-nano
// for "lite" pricing.
param voiceLiveModel = 'gpt-realtime-mini'

// TTS voice. Use an Azure HD voice for the most natural output. HD voices are
// only available in the regions listed in the voice-live-how-to doc.
param voiceName = 'en-US-Ava:DragonHDLatestNeural'

// B1 is fine for a dozen concurrent voice sessions. Bump to P1v3 in prod.
param appServicePlanSku = 'B1'

// Must match the display name of the Copilot Studio agent created in Step 3.
param mcsAgentName = 'Microsoft Learn Assistant'
