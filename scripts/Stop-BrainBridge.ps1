#Requires -Version 5.1
[CmdletBinding()]
param([string]$InstallRoot=(Join-Path $env:LOCALAPPDATA 'BrainBridge'))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'BrainBridge.Core.ps1')
$InstallRoot=Assert-BrainBridgeRoot $InstallRoot
$runner=Get-BrainBridgeRunner $InstallRoot
if (-not $runner) { Write-Output 'No verified runner is active.'; return }
$known=@($runner)
$pending=New-Object 'Collections.Generic.Queue[int]'
$pending.Enqueue($runner.Id)
while ($pending.Count) {
  $parentId=$pending.Dequeue()
  foreach ($row in @(Get-CimInstance Win32_Process -Filter ('ParentProcessId='+$parentId))) {
    $child=Get-Process -Id $row.ProcessId -ErrorAction SilentlyContinue
    if ($child -and $child.StartTime -ge $runner.StartTime -and $child.Id -notin $known.Id) { $known+=$child; $pending.Enqueue($child.Id) }
  }
}
# A short-lived preflight child may exit while taskkill walks the tree.
# Suppress native stderr and judge completion by process identity, not stderr alone.
$previousPreference=$ErrorActionPreference
try {
  $ErrorActionPreference='Continue'
  & "$env:WINDIR\System32\taskkill.exe" /PID $runner.Id /T /F 2>&1 | Out-Null
} finally { $ErrorActionPreference=$previousPreference }
foreach ($process in $known) {
  if (-not $process.WaitForExit(5000)) { throw 'Unable to stop the complete verified runner tree.' }
}
Remove-Item -LiteralPath (Join-Path $InstallRoot 'runner.json'),(Join-Path $InstallRoot 'health.url') -Force -ErrorAction SilentlyContinue
Set-Content -LiteralPath (Join-Path $InstallRoot 'state.txt') -Value 'Stopped by user' -Encoding UTF8
Write-Output 'Brain Bridge stopped.'
