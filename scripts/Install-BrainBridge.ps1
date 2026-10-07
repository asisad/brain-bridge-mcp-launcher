#Requires -Version 5.1
[CmdletBinding()]
param(
  [string]$TunnelClientPath,
  [string]$TunnelId,
  [string]$McpUrl,
  [switch]$EnableAutoStart,
  [Security.SecureString]$RuntimeKey,
  [Security.SecureString]$ObsidianToken,
  [switch]$SkipConnectionTest,
  [string]$StartupDirectory = ([Environment]::GetFolderPath('Startup')),
  [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'BrainBridge')
)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Brain Bridge supports Windows only.' }
if (-not $TunnelClientPath) { $TunnelClientPath = Read-Host 'Full path to official tunnel-client.exe' }
$TunnelClientPath = [Environment]::ExpandEnvironmentVariables($TunnelClientPath.Trim('"'))
if (-not (Test-Path -LiteralPath $TunnelClientPath -PathType Leaf)) {
  throw 'tunnel-client.exe not found. Obtain it from official openai/tunnel-client releases.'
}
if ([IO.Path]::GetFileName($TunnelClientPath) -ne 'tunnel-client.exe') {
  throw 'Select the executable named tunnel-client.exe.'
}
if (-not $TunnelId) { $TunnelId = Read-Host 'OpenAI Tunnel ID (tunnel_...)' }
if ($TunnelId -cnotmatch '^tunnel_(?:[a-z0-9]{4}_)?[a-z0-9]{32}$') { throw 'Invalid Tunnel ID format.' }
if (-not $McpUrl) { $McpUrl = Read-Host 'Direct local Obsidian MCP URL (e.g. http://127.0.0.1:27200/mcp)' }
 . (Join-Path $PSScriptRoot 'BrainBridge.Core.ps1')
$InstallRoot = Assert-BrainBridgeRoot $InstallRoot
if (Test-Path -LiteralPath $InstallRoot) {
  if (Get-ChildItem -LiteralPath $InstallRoot -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) { throw 'Installation contains links; refusing to overwrite.' }
}
$uri = Assert-BrainBridgeConfig $TunnelClientPath $TunnelId $McpUrl
if (Get-BrainBridgeRunner $InstallRoot) { throw 'Stop the installed runner before changing configuration.' }
$legacyPid=Join-Path $InstallRoot 'runner.pid'
if (Test-Path -LiteralPath $legacyPid) {
  try { $legacy=Get-Process -Id ([int](Get-Content -LiteralPath $legacyPid -Raw)) -ErrorAction SilentlyContinue } catch { $legacy=$null }
  if ($legacy) { throw 'A legacy runner may be active. Stop the old installation before upgrading.' }
}
$runtime = $RuntimeKey
$obsidian = $ObsidianToken
if (-not $runtime) { $runtime = Read-Host 'OpenAI Restricted Runtime key' -AsSecureString }
if (-not $obsidian) { $obsidian = Read-Host 'Obsidian MCP token (raw, without Bearer)' -AsSecureString }
if ($runtime.Length -eq 0 -or $obsidian.Length -eq 0) { throw 'Keys may not be empty.' }
$packageNames = @('BrainBridge.Core.ps1','Start-BrainBridge.ps1','Status-BrainBridge.ps1','Stop-BrainBridge.ps1','Remove-BrainBridge.ps1','BrainBridge.Gui.ps1','Install-BrainBridge.ps1')
foreach ($name in $packageNames) {
  if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $name))) { throw 'Package incomplete.' }
}
$probe = @{ tunnel_client_exe=$TunnelClientPath; tunnel_id=$TunnelId; mcp_url=$uri.AbsoluteUri }
$shortcut=Join-Path $StartupDirectory 'Brain Bridge.lnk'
if (Test-Path -LiteralPath $shortcut) {
  $oldLink=(New-Object -ComObject WScript.Shell).CreateShortcut($shortcut)
  if ($oldLink.Arguments -ne ('"'+(Join-Path $InstallRoot 'Run-Hidden.vbs')+'"')) { throw 'Startup shortcut belongs to another installation.' }
}
if (-not $SkipConnectionTest) { $null = Test-BrainBridgeConnection $probe $runtime $obsidian }
New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
Protect-BrainBridgeDirectory $InstallRoot
Set-Content -LiteralPath (Join-Path $InstallRoot '.brainbridge-install') -Value 'BrainBridge' -Encoding ASCII
$names = @('config.json','runtime-key.dpapi','obsidian-token.dpapi')
if (@($names | Where-Object { Test-Path -LiteralPath (Join-Path $InstallRoot $_) }).Count -gt 0) {
  $backup = Join-Path $InstallRoot ('backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
  New-Item -ItemType Directory -Path $backup -Force | Out-Null
  foreach($name in $names) {
    $f=Join-Path $InstallRoot $name
    if (Test-Path -LiteralPath $f) { Copy-Item -LiteralPath $f -Destination (Join-Path $backup $name) -Force }
  }
}
$runtime | ConvertFrom-SecureString | Set-Content -LiteralPath (Join-Path $InstallRoot 'runtime-key.dpapi') -Encoding ASCII
$obsidian | ConvertFrom-SecureString | Set-Content -LiteralPath (Join-Path $InstallRoot 'obsidian-token.dpapi') -Encoding ASCII
$config=[ordered]@{
  version='0.2.0-prototype'
  client_sha256=(Get-FileHash -LiteralPath $TunnelClientPath -Algorithm SHA256).Hash
  tunnel_client_exe=(Resolve-Path -LiteralPath $TunnelClientPath).Path
  tunnel_id=$TunnelId
  mcp_url=$uri.AbsoluteUri
  updated_at=(Get-Date).ToString('o')
}
$config | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $InstallRoot 'config.json') -Encoding UTF8
foreach($name in $packageNames) {
  $src=Join-Path $PSScriptRoot $name
  if (-not (Test-Path -LiteralPath $src)) { throw "Missing package file: $name" }
  if ([IO.Path]::GetFullPath($src) -ne (Join-Path $InstallRoot $name)) { Copy-Item -LiteralPath $src -Destination (Join-Path $InstallRoot $name) -Force }
}
$scriptPath=(Join-Path $InstallRoot 'Start-BrainBridge.ps1').Replace('"','""')
$systemPowerShell=(Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe').Replace('"','""')
$vbs='CreateObject("WScript.Shell").Run """'+$systemPowerShell+'"" -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File ""' + $scriptPath + '""", 0, False'
$vbsPath=Join-Path $InstallRoot 'Run-Hidden.vbs'
Set-Content -LiteralPath $vbsPath -Value $vbs -Encoding Unicode
if ($EnableAutoStart) {
  $startup=$StartupDirectory
  $shell=New-Object -ComObject WScript.Shell
  $link=$shell.CreateShortcut((Join-Path $startup 'Brain Bridge.lnk'))
  $link.TargetPath=Join-Path $env:WINDIR 'System32\wscript.exe'
  $link.Arguments='"' + $vbsPath + '"'
  $link.WorkingDirectory=$InstallRoot
  $link.Save()
}
if (-not $EnableAutoStart) {
  $shortcut=Join-Path $StartupDirectory 'Brain Bridge.lnk'
  if (Test-Path -LiteralPath $shortcut) {
    $existingLink=(New-Object -ComObject WScript.Shell).CreateShortcut($shortcut)
    if ($existingLink.Arguments -eq ('"'+$vbsPath+'"')) { Remove-Item -LiteralPath $shortcut -Force }
    else { throw 'Startup shortcut belongs to another installation.' }
  }
}
Write-Host 'Brain Bridge configured; check status before starting.' -ForegroundColor Green
Write-Host ('Status: ' + (Join-Path $InstallRoot 'Status-BrainBridge.ps1'))
Write-Host ('Launcher: ' + $vbsPath)
