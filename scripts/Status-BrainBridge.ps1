#Requires -Version 5.1
[CmdletBinding()]
param([string]$InstallRoot=(Join-Path $env:LOCALAPPDATA 'BrainBridge'),[switch]$CheckOpenAI)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'BrainBridge.Core.ps1')
$InstallRoot=Assert-BrainBridgeRoot $InstallRoot
if (-not (Test-Path -LiteralPath (Join-Path $InstallRoot 'config.json'))) { 'Not installed'; return }
$runner=Get-BrainBridgeRunner $InstallRoot
'Installed: yes'
'Verified runner active: '+[bool]$runner
'Tunnel readiness: not confirmed'
$state=Join-Path $InstallRoot 'state.txt'
if (Test-Path -LiteralPath $state) { Get-Content -LiteralPath $state }
$health=Join-Path $InstallRoot 'health.url'
if ($runner -and (Test-Path -LiteralPath $health)) {
  try {
    $uri=[Uri](Get-Content -LiteralPath $health -Raw).Trim()
    if ($uri.Scheme -ne 'http' -or $uri.Host -ne '127.0.0.1' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) { throw 'Invalid health URL.' }
    $resp=Invoke-WebRequest -UseBasicParsing -Uri ($uri.GetLeftPart([UriPartial]::Authority)+'/readyz') -MaximumRedirection 0 -TimeoutSec 3
    if ($resp.StatusCode -eq 200) { 'Local tunnel readiness endpoint: ready (not a remote ChatGPT test)' }
  } catch { 'Local tunnel readiness endpoint: unavailable' }
}
if ($CheckOpenAI) {
  $c=Get-Content -LiteralPath (Join-Path $InstallRoot 'config.json') -Raw | ConvertFrom-Json
  $runtime=(Get-Content -LiteralPath (Join-Path $InstallRoot 'runtime-key.dpapi') -Raw).Trim() | ConvertTo-SecureString
  $token=(Get-Content -LiteralPath (Join-Path $InstallRoot 'obsidian-token.dpapi') -Raw).Trim() | ConvertTo-SecureString
  try { Test-BrainBridgeConnection $c $runtime $token }
  finally { $runtime.Dispose(); $token.Dispose() }
}
