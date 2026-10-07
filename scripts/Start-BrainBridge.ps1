#Requires -Version 5.1
[CmdletBinding()]
param([string]$InstallRoot = $PSScriptRoot)
$ErrorActionPreference='Stop'
$configPath=Join-Path $InstallRoot 'config.json'
if (-not (Test-Path -LiteralPath $configPath)) { throw 'Install Brain Bridge first.' }
$config=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
if (-not (Test-Path -LiteralPath $config.tunnel_client_exe -PathType Leaf)) { throw 'tunnel-client executable missing.' }
$createdNew=$false
$mutex=New-Object System.Threading.Mutex($true,'Local\BrainBridge-TunnelRunner',[ref]$createdNew)
if (-not $createdNew) { $mutex.Dispose(); return }
$logDir=Join-Path $InstallRoot 'logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$log=Join-Path $logDir 'runner.log'
$pidPath=Join-Path $InstallRoot 'runner.pid'
Set-Content -LiteralPath $pidPath -Value $PID -Encoding ASCII
function Write-Log([string]$message) {
  Add-Content -LiteralPath $log -Encoding UTF8 -Value ((Get-Date).ToString('s')+' '+$message)
}
function Get-DpapiSecret([string]$file) {
  $secure=(Get-Content -LiteralPath (Join-Path $InstallRoot $file) -Raw).Trim() | ConvertTo-SecureString
  $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}
function Test-ObsidianMcp([Uri]$uri,[string]$authorization) {
  $body='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"brain-bridge","version":"0.1.0"}}}'
  $headers=@{Authorization=$authorization;Accept='application/json, text/event-stream'}
  try {
    $resp=Invoke-WebRequest -Uri $uri.AbsoluteUri -Method POST -Headers $headers -ContentType 'application/json' -Body $body -UseBasicParsing -TimeoutSec 4
    return ($resp.StatusCode -eq 200)
  } catch [System.Net.WebException] {
    if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 401) {
      throw 'Local Obsidian MCP unauthorized: check vault token and URL.'
    }
    return $false
  }
}
try {
  $env:CONTROL_PLANE_API_KEY=Get-DpapiSecret 'runtime-key.dpapi'
  $rawToken=Get-DpapiSecret 'obsidian-token.dpapi'
  if (-not $env:CONTROL_PLANE_API_KEY -or -not $rawToken) { throw 'Stored credential is empty.' }
  $env:CONTROL_PLANE_TUNNEL_ID=[string]$config.tunnel_id
  $env:MCP_SERVER_URL=[string]$config.mcp_url
  $env:OBSIDIAN_MCP_AUTH='Bearer '+$rawToken
  $env:MCP_EXTRA_HEADERS='Authorization: env:OBSIDIAN_MCP_AUTH'
  $env:MCP_DISCOVERY_EXTRA_HEADERS='Authorization: env:OBSIDIAN_MCP_AUTH'
  Remove-Variable rawToken -ErrorAction SilentlyContinue
  $preflight=& $config.tunnel_client_exe admin tunnels get $config.tunnel_id 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { throw 'OpenAI rejected the Runtime key or Tunnel permission.' }
  Write-Log 'Runtime key validated by control plane.'
  $uri=[Uri]$config.mcp_url
  while($true) {
    if (-not (Test-ObsidianMcp $uri $env:OBSIDIAN_MCP_AUTH)) {
      Write-Log 'Waiting for Obsidian MCP endpoint.'
      Start-Sleep -Seconds 10
      continue
    }
    Write-Log 'Starting tunnel-client.'
    & $config.tunnel_client_exe run 2>&1 | Out-File -LiteralPath $log -Append -Encoding UTF8
    $recheck=& $config.tunnel_client_exe admin tunnels get $config.tunnel_id 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw 'OpenAI credentials no longer authorized; stopped.' }
    Start-Sleep -Seconds 10
  }
} catch {
  Write-Log ('STOPPED: '+$_.Exception.Message)
} finally {
  Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
  Remove-Item Env:\CONTROL_PLANE_API_KEY -ErrorAction SilentlyContinue
  Remove-Item Env:\OBSIDIAN_MCP_AUTH -ErrorAction SilentlyContinue
  if ($createdNew) { $mutex.ReleaseMutex() }
  $mutex.Dispose()
}
