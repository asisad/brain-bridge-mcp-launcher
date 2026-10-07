#Requires -Version 5.1
[CmdletBinding()]
param(
  [string]$TunnelClientPath,
  [string]$TunnelId,
  [string]$McpUrl,
  [switch]$EnableAutoStart,
  [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA 'BrainBridge')
)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Brain Bridge v0.1 supports Windows only.' }
if (-not $TunnelClientPath) { $TunnelClientPath = Read-Host 'Full path to official tunnel-client.exe' }
$TunnelClientPath = [Environment]::ExpandEnvironmentVariables($TunnelClientPath.Trim('"'))
if (-not (Test-Path -LiteralPath $TunnelClientPath -PathType Leaf)) {
  throw 'tunnel-client.exe not found. Obtain it from official openai/tunnel-client releases.'
}
if ([IO.Path]::GetFileName($TunnelClientPath) -ne 'tunnel-client.exe') {
  throw 'Select the executable named tunnel-client.exe.'
}
if (-not $TunnelId) { $TunnelId = Read-Host 'OpenAI Tunnel ID (tunnel_...)' }
if ($TunnelId -cnotmatch '^tunnel_[a-f0-9]{32}$') { throw 'Invalid Tunnel ID format.' }
if (-not $McpUrl) { $McpUrl = Read-Host 'Direct local Obsidian MCP URL (e.g. http://127.0.0.1:27200/mcp)' }
try { $uri = [Uri]$McpUrl } catch { throw 'Invalid MCP URL.' }
if (-not $uri.IsAbsoluteUri -or $uri.Scheme -notin @('http','https') -or $uri.Host -notin @('localhost','127.0.0.1','::1') -or $uri.AbsolutePath -notmatch '/mcp/?$') {
  throw 'MCP URL must be a local loopback URL ending in /mcp.'
}
$runtime = Read-Host 'OpenAI Restricted Runtime key' -AsSecureString
$obsidian = Read-Host 'Obsidian MCP token (raw, without Bearer)' -AsSecureString
if ($runtime.Length -eq 0 -or $obsidian.Length -eq 0) { throw 'Keys may not be empty.' }
New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
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
  version='0.1.0'
  tunnel_client_exe=(Resolve-Path -LiteralPath $TunnelClientPath).Path
  tunnel_id=$TunnelId
  mcp_url=$uri.AbsoluteUri
  updated_at=(Get-Date).ToString('o')
}
$config | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $InstallRoot 'config.json') -Encoding UTF8
foreach($name in @('Start-BrainBridge.ps1','Status-BrainBridge.ps1','Stop-BrainBridge.ps1','Remove-BrainBridge.ps1')) {
  $src=Join-Path $PSScriptRoot $name
  if (-not (Test-Path -LiteralPath $src)) { throw "Missing package file: $name" }
  Copy-Item -LiteralPath $src -Destination (Join-Path $InstallRoot $name) -Force
}
$scriptPath=(Join-Path $InstallRoot 'Start-BrainBridge.ps1').Replace('"','""')
$vbs='CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File ""' + $scriptPath + '""", 0, False'
$vbsPath=Join-Path $InstallRoot 'Run-Hidden.vbs'
Set-Content -LiteralPath $vbsPath -Value $vbs -Encoding ASCII
if ($EnableAutoStart) {
  $startup=[Environment]::GetFolderPath('Startup')
  $shell=New-Object -ComObject WScript.Shell
  $link=$shell.CreateShortcut((Join-Path $startup 'Brain Bridge.lnk'))
  $link.TargetPath=Join-Path $env:WINDIR 'System32\wscript.exe'
  $link.Arguments='"' + $vbsPath + '"'
  $link.WorkingDirectory=$InstallRoot
  $link.Save()
}
Write-Host 'Brain Bridge configured; check status before starting.' -ForegroundColor Green
Write-Host ('Status: ' + (Join-Path $InstallRoot 'Status-BrainBridge.ps1'))
Write-Host ('Launcher: ' + $vbsPath)
