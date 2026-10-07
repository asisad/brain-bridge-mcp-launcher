#Requires -Version 5.1
[CmdletBinding()]
param([string]$InstallRoot=(Join-Path $env:LOCALAPPDATA 'BrainBridge'))
$pidPath=Join-Path $InstallRoot 'runner.pid'
if (-not (Test-Path -LiteralPath $pidPath)) { Write-Host 'No runner PID recorded.'; return }
$runnerId=[int](Get-Content -LiteralPath $pidPath -Raw)
$proc=Get-CimInstance Win32_Process -Filter "ProcessId=$runnerId" -ErrorAction SilentlyContinue
if (-not $proc -or $proc.CommandLine -notlike '*Start-BrainBridge.ps1*') { throw 'Stale or unrelated PID; refusing to stop.' }
& taskkill.exe /PID $runnerId /T /F | Out-Null
Write-Host 'Brain Bridge stopped.'
