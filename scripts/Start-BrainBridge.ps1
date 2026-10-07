#Requires -Version 5.1
[CmdletBinding()]
param([string]$InstallRoot)
$ErrorActionPreference='Stop'
if (-not $InstallRoot) { $InstallRoot=$PSScriptRoot }
. (Join-Path $PSScriptRoot 'BrainBridge.Core.ps1')
$InstallRoot=Assert-BrainBridgeRoot $InstallRoot
$config=Get-Content -LiteralPath (Join-Path $InstallRoot 'config.json') -Raw | ConvertFrom-Json
$null=Assert-BrainBridgeConfig $config.tunnel_client_exe $config.tunnel_id $config.mcp_url
$created=$false
$sha=[Security.Cryptography.SHA256]::Create()
try { $instance=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($InstallRoot.ToLowerInvariant()))).Replace('-','') }
finally { $sha.Dispose() }
$mutex=New-Object Threading.Mutex($true,('Local\BrainBridge-'+$instance),[ref]$created)
if (-not $created) { $mutex.Dispose(); return }
$child=$null
$record=Join-Path $InstallRoot 'runner.json'
$state=Join-Path $InstallRoot 'state.txt'
$health=Join-Path $InstallRoot 'health.url'
try {
  @{pid=$PID;started=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks.ToString()} | ConvertTo-Json | Set-Content -LiteralPath $record -Encoding UTF8
  Set-Content -LiteralPath $state -Value 'Checking connection' -Encoding UTF8
  $runtime=(Get-Content -LiteralPath (Join-Path $InstallRoot 'runtime-key.dpapi') -Raw).Trim() | ConvertTo-SecureString
  $token=(Get-Content -LiteralPath (Join-Path $InstallRoot 'obsidian-token.dpapi') -Raw).Trim() | ConvertTo-SecureString
  $passed=$false
  for ($attempt=0; $attempt -lt 6; $attempt++) {
    try { $null=Test-BrainBridgeConnection $config $runtime $token; $passed=$true; break }
    catch { Set-Content -LiteralPath $state -Value 'Connection check failed; retrying (maximum 6 attempts)' -Encoding UTF8; Start-Sleep -Seconds 10 }
  }
  if (-not $passed) { throw 'Preflight failed.' }
  Remove-Item -LiteralPath $health -Force -ErrorAction SilentlyContinue
  $child=New-BrainBridgeProcess $config $runtime $token ('run --health.listen-addr 127.0.0.1:0 --health.url-file "'+$health+'"')
  Set-Content -LiteralPath $state -Value 'Runner active; use Refresh status to check readiness' -Encoding UTF8
  $child.WaitForExit()
  Set-Content -LiteralPath $state -Value 'Tunnel exited; inspect settings and restart' -Encoding UTF8
} catch {
  Set-Content -LiteralPath $state -Value 'Stopped: connection, configuration or credential check failed' -Encoding UTF8
} finally {
  if ($child) { if (-not $child.HasExited) { $child.Kill() }; $child.Dispose() }
  if ($runtime) { $runtime.Dispose() }; if ($token) { $token.Dispose() }
  Remove-Item -LiteralPath $record,$health -Force -ErrorAction SilentlyContinue
  $mutex.ReleaseMutex(); $mutex.Dispose()
}
