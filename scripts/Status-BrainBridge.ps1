#Requires -Version 5.1
[CmdletBinding()]
param([string]$InstallRoot=(Join-Path $env:LOCALAPPDATA 'BrainBridge'),[switch]$CheckOpenAI)
$ErrorActionPreference='Stop'
$configPath=Join-Path $InstallRoot 'config.json'
if (-not (Test-Path -LiteralPath $configPath)) { Write-Host 'NOT INSTALLED'; exit 1 }
$c=Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
Write-Host 'Brain Bridge v0.1'
Write-Host ('Tunnel ID: '+$c.tunnel_id)
Write-Host ('Local MCP URL: '+$c.mcp_url)
Write-Host ('Client executable found: '+(Test-Path -LiteralPath $c.tunnel_client_exe -PathType Leaf))
Write-Host ('Runtime DPAPI exists: '+(Test-Path -LiteralPath (Join-Path $InstallRoot 'runtime-key.dpapi')))
Write-Host ('Obsidian DPAPI exists: '+(Test-Path -LiteralPath (Join-Path $InstallRoot 'obsidian-token.dpapi')))
$pidPath=Join-Path $InstallRoot 'runner.pid'
$running=$false
if (Test-Path -LiteralPath $pidPath) {
  $runnerId=[int](Get-Content -LiteralPath $pidPath -Raw)
  $proc=Get-Process -Id $runnerId -ErrorAction SilentlyContinue
  if ($proc) {
    try {
      $row=Get-CimInstance Win32_Process -Filter "ProcessId=$runnerId"
      $running=[bool]($row.CommandLine -like '*Start-BrainBridge.ps1*')
    } catch { $running=$false }
  }
}
Write-Host ('Runner active: '+$running)
try {
  $resp=Invoke-WebRequest -Uri 'http://127.0.0.1:8080/readyz' -UseBasicParsing -TimeoutSec 3
  Write-Host ('Tunnel health HTTP: '+$resp.StatusCode)
  $clean=($resp.Content -replace '\r|\n',' ')
  if ($clean.Length -gt 220) { $clean=$clean.Substring(0,220)+'...' }
  Write-Host ('Tunnel health: '+$clean)
} catch { Write-Host 'Tunnel health: offline or unavailable.' }
if ($CheckOpenAI) {
  $secure=(Get-Content -LiteralPath (Join-Path $InstallRoot 'runtime-key.dpapi') -Raw).Trim() | ConvertTo-SecureString
  $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { $env:CONTROL_PLANE_API_KEY=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
  try {
    & $c.tunnel_client_exe admin tunnels get $c.tunnel_id | Out-Null
    Write-Host ('OpenAI key accepted: '+($LASTEXITCODE -eq 0))
  } finally { Remove-Item Env:\CONTROL_PLANE_API_KEY -ErrorAction SilentlyContinue }
}
