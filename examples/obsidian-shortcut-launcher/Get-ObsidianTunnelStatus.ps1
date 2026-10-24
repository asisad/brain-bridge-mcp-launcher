$ErrorActionPreference = 'Stop'
$base = $PSScriptRoot
. (Join-Path $base 'Launcher-Config.ps1')
$status = $null
for ($attempt = 0; $attempt -lt 3; $attempt++) {
    try { $status = Get-Content -LiteralPath (Join-Path $base 'state\status.json') -Raw | ConvertFrom-Json; break }
    catch { Start-Sleep -Milliseconds 100 }
}
if (-not $status) { @{ state = 'status_unavailable'; supervisor_running = $false } | ConvertTo-Json; exit 1 }
$parent = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$status.supervisor_pid)
$alive = ($null -ne $parent -and $parent.Name -eq 'powershell.exe' -and
    $parent.CommandLine -match [regex]::Escape((Join-Path $base 'Start-ObsidianTunnel.ps1')) -and
    [Math]::Abs((([DateTime]$parent.CreationDate).ToUniversalTime() - ([DateTime]$status.supervisor_started_at).ToUniversalTime()).TotalSeconds) -lt 15)
$childAlive = $false
if ($alive -and $status.tunnel_pid) {
    $child = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$status.tunnel_pid)
    $config = Read-LauncherConfig $base
    $childAlive = ($null -ne $child -and $child.ParentProcessId -eq $parent.ProcessId -and $child.ExecutablePath -eq $config.tunnel_exe)
}
$age = [Math]::Round(([DateTime]::UtcNow - ([DateTime]$status.updated_at).ToUniversalTime()).TotalSeconds, 1)
$status | Add-Member -NotePropertyName supervisor_running -NotePropertyValue ([bool]$alive)
$status | Add-Member -NotePropertyName tunnel_running -NotePropertyValue ([bool]$childAlive)
$status | Add-Member -NotePropertyName heartbeat_age_seconds -NotePropertyValue $age
if ($status.state -notlike 'stopped*' -and (-not $alive -or $age -gt 30)) { $status.state = 'supervisor_stopped_or_stale'; $status.local_mcp_ready = $false; $status.tunnel_health_ready = $false }
elseif ($status.state -eq 'ready' -and -not $childAlive) { $status.state = 'tunnel_not_running'; $status.tunnel_health_ready = $false }
$status | ConvertTo-Json
