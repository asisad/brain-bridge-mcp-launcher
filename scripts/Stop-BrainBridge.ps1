#Requires -Version 5.1
[CmdletBinding()]
param([string]$InstallRoot=(Join-Path $env:LOCALAPPDATA 'BrainBridge'))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'BrainBridge.Core.ps1')
$InstallRoot=Assert-BrainBridgeRoot $InstallRoot
$runner=Get-BrainBridgeRunner $InstallRoot
if (-not $runner) { Write-Output 'No verified runner is active.'; return }
& "$env:WINDIR\System32\taskkill.exe" /PID $runner.Id /T /F 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Unable to stop verified runner.' }
Remove-Item -LiteralPath (Join-Path $InstallRoot 'runner.json'),(Join-Path $InstallRoot 'health.url') -Force -ErrorAction SilentlyContinue
Set-Content -LiteralPath (Join-Path $InstallRoot 'state.txt') -Value 'Stopped by user' -Encoding UTF8
Write-Output 'Brain Bridge stopped.'
