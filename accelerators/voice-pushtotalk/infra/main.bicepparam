using './main.bicep'

// Base name — lowercase, 3-18 chars. Seeds the Foundry custom subdomain.
param baseName = 'voicech-01'

// Any region where Microsoft Foundry is available. swedencentral gives broad
// model + HD-voice coverage if you ever swap back to a voice UX.
param location = 'swedencentral'
