<#
.SYNOPSIS
  Loads KEY=VALUE pairs from a .env file into the current PowerShell session
  (as variables and as process environment variables).

.EXAMPLE
  . ./scripts/load-env.ps1            # loads ./.env
  . ./scripts/load-env.ps1 -Path .env.dev
#>
[CmdletBinding()]
param(
  [string] $Path = (Join-Path (Split-Path -Parent $PSScriptRoot) '.env')
)

if (-not (Test-Path $Path)) {
  throw ".env file not found at '$Path'. Copy .env.example to .env and fill in the values."
}

Get-Content $Path | ForEach-Object {
  $line = $_.Trim()
  if (-not $line -or $line.StartsWith('#')) { return }
  $kv = $line -split '=', 2
  if ($kv.Count -ne 2) { return }
  $name  = $kv[0].Trim()
  $value = $kv[1].Trim().Trim('"').Trim("'")
  Set-Item -Path "Env:$name" -Value $value
  Set-Variable -Name $name -Value $value -Scope Script
}
