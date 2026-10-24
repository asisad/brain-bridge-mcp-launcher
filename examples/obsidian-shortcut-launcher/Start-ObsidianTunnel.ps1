#Requires -Version 5.1
[CmdletBinding()]
param([switch]$OpenObsidian)
# No secrets are accepted as command-line arguments.
$ErrorActionPreference = 'Stop'
$base = $PSScriptRoot
. (Join-Path $base 'Launcher-Config.ps1')
$config = Read-LauncherConfig $base
$stateDir = Join-Path $base 'state'
[IO.Directory]::CreateDirectory($stateDir) | Out-Null
$statusPath = Join-Path $stateDir 'status.json'
$logPath = Join-Path $stateDir 'events.jsonl'
$healthFile = Join-Path $stateDir 'health-url.txt'
$mutex = New-Object Threading.Mutex($false, (Get-LauncherMutexName $base))
$locked = $false
$child = $null
$job = [IntPtr]::Zero
$lastState = ''
$restartCount = 0
$token = $null
$started = [DateTime]::UtcNow
$session = (Get-Process -Id $PID).SessionId

function Write-Event([string]$code) {
    # Only fixed event codes; never exception messages or raw client output.
    try {
        if ((Test-Path -LiteralPath $logPath) -and (Get-Item -LiteralPath $logPath).Length -gt 262144) {
            Move-Item -LiteralPath $logPath -Destination ($logPath + '.1') -Force
        }
        $row = @{ at = [DateTime]::UtcNow.ToString('o'); event = $code; supervisor_pid = $PID }
        [IO.File]::AppendAllText($logPath, (($row | ConvertTo-Json -Compress) + [Environment]::NewLine))
    } catch { }
}
function Write-State([string]$state, [bool]$localOk = $false, [bool]$tunnelOk = $false) {
    if ($state -ne $script:lastState) { Write-Event $state; $script:lastState = $state }
    $childId = $null
    if ($script:child -and -not $script:child.HasExited) { $childId = $script:child.Id }
    $row = [ordered]@{
        schema_version = 1; updated_at = [DateTime]::UtcNow.ToString('o'); state = $state
        supervisor_pid = $PID; supervisor_started_at = $started.ToString('o')
        tunnel_pid = $childId; local_mcp_ready = $localOk; tunnel_health_ready = $tunnelOk
        restart_count = $script:restartCount; launch_mode = 'shortcut-wrapper'
        remote_e2e = 'not_checked_by_supervisor'
    }
    try {
        $tmp = $statusPath + '.' + $PID + '.tmp'
        [IO.File]::WriteAllText($tmp, ($row | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tmp -Destination $statusPath -Force
    } catch { Write-Event 'status_write_failed' }
}
function Get-Secret([string]$name) {
    $secure = (Get-Content -LiteralPath (Join-Path $base $name) -Raw).Trim() | ConvertTo-SecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr); $secure.Dispose() }
}
function Test-Obsidian {
    return @((Get-Process -Name Obsidian -ErrorAction SilentlyContinue) | Where-Object {
        $_.SessionId -eq $session -and $_.Path -eq $config.obsidian_exe
    }).Count -gt 0
}
function Test-LocalMcp {
    $response = $null
    try {
        $request = [Net.HttpWebRequest]::Create($config.mcp_url)
        $request.Proxy = $null
        $request.AllowAutoRedirect = $false
        $request.Method = 'POST'
        $request.Timeout = 3000
        $request.ReadWriteTimeout = 3000
        $request.ContentType = 'application/json'
        $request.Accept = 'application/json, text/event-stream'
        $request.Headers['Authorization'] = 'Bearer ' + $script:token
        $data = [Text.Encoding]::UTF8.GetBytes('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"obsidian-tunnel-supervisor","version":"1.0"}}}')
        $request.ContentLength = $data.Length
        $stream = $request.GetRequestStream()
        try { $stream.Write($data, 0, $data.Length) } finally { $stream.Dispose() }
        $response = $request.GetResponse()
        $reader = New-Object IO.StreamReader($response.GetResponseStream())
        try {
            # Read one bounded JSON response or first SSE data event, not an infinite SSE stream.
            $body = ''
            if ($response.ContentType -like '*text/event-stream*') {
                for ($i = 0; $i -lt 20; $i++) {
                    $line = $reader.ReadLine()
                    if ($null -eq $line) { break }
                    if ($line.StartsWith('data:')) { $body = $line.Substring(5).Trim(); break }
                }
            } else { $body = $reader.ReadToEnd() }
            $message = $body | ConvertFrom-Json
            return ($null -ne $message.result.protocolVersion -and $null -eq $message.error)
        } finally { $reader.Dispose() }
    } catch { return $false }
    finally { if ($response) { $response.Dispose() } }
}
function Test-TunnelHealth {
    try {
        if (-not (Test-Path -LiteralPath $healthFile)) { return $false }
        $url = [IO.File]::ReadAllText($healthFile).Trim()
        $uri = [Uri]$url
        if ($uri.Scheme -ne 'http' -or $uri.Host -ne '127.0.0.1' -or $uri.UserInfo -or $uri.Query) { return $false }
        $req = [Net.HttpWebRequest]::Create($url.TrimEnd('/') + '/health?details=true')
        $req.Proxy = $null; $req.Timeout = 3000; $req.ReadWriteTimeout = 3000; $req.AllowAutoRedirect = $false
        $resp = $req.GetResponse()
        try {
            $r = New-Object IO.StreamReader($resp.GetResponseStream())
            try { $h = $r.ReadToEnd() | ConvertFrom-Json } finally { $r.Dispose() }
        } finally { $resp.Dispose() }
        $cp = $h.components.'control-plane'
        $fresh = $false
        if ($cp.observed_at) { $fresh = ([DateTime]::UtcNow - ([DateTime]$cp.observed_at).ToUniversalTime()).TotalSeconds -lt 120 }
        return ($h.live -eq $true -and $h.ready -eq $true -and $cp.status -eq 'ok' -and $fresh)
    } catch { return $false }
}
function Stop-OwnedTunnel {
    if ($script:child) {
        try {
            if (-not $script:child.HasExited) { $script:child.Kill(); $script:child.WaitForExit(5000) | Out-Null }
        } catch { Write-Event 'child_stop_failed' }
        $script:child.Dispose(); $script:child = $null
    }
}
function Start-OwnedTunnel {
    Assert-LauncherClientHash $config
    if (Test-Path -LiteralPath $healthFile) { Remove-Item -LiteralPath $healthFile -Force }
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $config.tunnel_exe
    $psi.Arguments = 'run'
    $psi.WorkingDirectory = $base
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    # A different installed bridge must not supply competing routing, headers,
    # proxy configuration or diagnostic payload capture to this child.
    foreach ($name in @($psi.EnvironmentVariables.Keys)) {
        if ($name -match '^(CONTROL_PLANE_|MCP_|OPENAI_|OBSIDIAN_|TUNNEL_|HEALTH_|CLOUDFLARED_|HARPOON_|LOG_|ADMIN_UI_|ALLOW_REMOTE_UI$|OPEN_WEB_UI$|HTTP_PROXY$|HTTPS_PROXY$|ALL_PROXY$|NO_PROXY$)') { $psi.EnvironmentVariables.Remove($name) }
    }
    $psi.EnvironmentVariables['CONTROL_PLANE_API_KEY'] = Get-Secret 'runtime-key.dpapi'
    $psi.EnvironmentVariables['CONTROL_PLANE_TUNNEL_ID'] = $config.tunnel_id
    $psi.EnvironmentVariables['OBSIDIAN_MCP_AUTH'] = 'Bearer ' + $script:token
    $psi.EnvironmentVariables['MCP_SERVER_URL'] = $config.mcp_url
    $psi.EnvironmentVariables['MCP_EXTRA_HEADERS'] = 'Authorization: env:OBSIDIAN_MCP_AUTH'
    $psi.EnvironmentVariables['MCP_DISCOVERY_EXTRA_HEADERS'] = 'Authorization: env:OBSIDIAN_MCP_AUTH'
    $psi.EnvironmentVariables['HEALTH_LISTEN_ADDR'] = '127.0.0.1:0'
    $psi.EnvironmentVariables['HEALTH_URL_FILE'] = $healthFile
    $psi.EnvironmentVariables['LOG_LEVEL'] = 'warn'
    $psi.EnvironmentVariables['LOG_FILE'] = 'stdout'
    $psi.EnvironmentVariables['LOG_HTTP_RAW_UNSAFE'] = 'false'
    $psi.EnvironmentVariables['HARPOON_CAPTURE_PAYLOADS'] = 'false'
    $psi.EnvironmentVariables['OPEN_WEB_UI'] = 'false'
    $psi.EnvironmentVariables['ALLOW_REMOTE_UI'] = 'false'
    $p = New-Object Diagnostics.Process
    $p.StartInfo = $psi
    try {
        $p.Start() | Out-Null
        $script:child = $p
        if (-not [ObsidianTunnelJob]::AssignProcessToJobObject($script:job, $p.Handle)) { throw 'job_assignment_failed' }
        # Asynchronous readers discard raw output; nothing sensitive is written to a terminal or file.
        $p.BeginOutputReadLine(); $p.BeginErrorReadLine()
        Write-Event 'tunnel_started'
    } finally {
        $psi.EnvironmentVariables.Clear()
    }
}
try {
    # Reopening the shortcut still brings Obsidian forward when the mutex is held.
    if ($OpenObsidian) {
        $appInfo = New-Object Diagnostics.ProcessStartInfo
        $appInfo.FileName = $config.obsidian_exe
        $appInfo.UseShellExecute = $true
        $appInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Normal
        $app = [Diagnostics.Process]::Start($appInfo)
        if ($app) { $app.Dispose() }
    }
    try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
    if (-not $locked) { exit 0 }
    Write-State 'starting'
    # A launcher inherited from PowerShell 7 can carry a PSModulePath without the
    # Windows PowerShell Security module. Load the built-in module explicitly.
    Import-Module -Name (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1') -ErrorAction Stop
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ObsidianTunnelJob {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr CreateJobObject(IntPtr a, string n);
    [DllImport("kernel32.dll")] public static extern bool SetInformationJobObject(IntPtr j, int c, IntPtr p, uint l);
    [DllImport("kernel32.dll")] public static extern bool AssignProcessToJobObject(IntPtr j, IntPtr p);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
    [StructLayout(LayoutKind.Sequential)] public struct Basic { public long p, j; public uint flags; public UIntPtr min, max; public uint active; public UIntPtr affinity; public uint priority, scheduling; }
    [StructLayout(LayoutKind.Sequential)] public struct IO { public ulong a,b,c,d,e,f; }
    [StructLayout(LayoutKind.Sequential)] public struct Extended { public Basic basic; public IO io; public UIntPtr a,b,c,d; }
    public static IntPtr Create() {
        IntPtr job = CreateJobObject(IntPtr.Zero, null);
        if (job == IntPtr.Zero) throw new Exception("job_create_failed");
        Extended info = new Extended(); info.basic.flags = 0x2000;
        int size = Marshal.SizeOf(info); IntPtr ptr = Marshal.AllocHGlobal(size);
        try { Marshal.StructureToPtr(info, ptr, false); if(!SetInformationJobObject(job,9,ptr,(uint)size)) { CloseHandle(job); throw new Exception("job_config_failed"); } }
        finally { Marshal.FreeHGlobal(ptr); }
        return job;
    }
}
'@
    $job = [ObsidianTunnelJob]::Create()
    $token = Get-Secret 'obsidian-token.dpapi'
    $deadline = [DateTime]::UtcNow.AddSeconds(45)
    while (-not (Test-Obsidian)) {
        Write-State 'waiting_for_obsidian'
        if ([DateTime]::UtcNow -gt $deadline) { Write-State 'stopped_no_obsidian'; exit 0 }
        Start-Sleep -Seconds 2
    }
    $missingSince = $null; $unhealthySince = $null; $localDownSince = $null
    $nextStart = [DateTime]::UtcNow; $backoff = 5
    while ($true) {
        $now = [DateTime]::UtcNow
        if (-not (Test-Obsidian)) {
            if (-not $missingSince) { $missingSince = $now }
            Write-State 'obsidian_closing'
            if (($now - $missingSince).TotalSeconds -ge 8) { break }
            Start-Sleep -Seconds 2; continue
        }
        $missingSince = $null
        $localOk = Test-LocalMcp
        if (-not $localOk) {
            if (-not $localDownSince) { $localDownSince = $now }
            if (($now - $localDownSince).TotalSeconds -ge 15) { Stop-OwnedTunnel }
            Write-State 'waiting_for_mcp'
            Start-Sleep -Seconds 5; continue
        }
        $localDownSince = $null
        if ($child -and $child.HasExited) {
            Write-Event 'tunnel_exited'
            Stop-OwnedTunnel
            $restartCount++; $nextStart = $now.AddSeconds($backoff)
            $backoff = [Math]::Min(60, $backoff * 2)
        }
        if (-not $child) {
            if ($now -lt $nextStart) { Write-State 'retry_wait' $true; Start-Sleep -Seconds 2; continue }
            try {
                Start-OwnedTunnel
                $unhealthySince = $now
            } catch {
                Stop-OwnedTunnel; Write-State 'launch_failed' $true
                $restartCount++; $nextStart = $now.AddSeconds($backoff)
                $backoff = [Math]::Min(60, $backoff * 2)
                Start-Sleep -Seconds 2; continue
            }
        }
        $healthy = Test-TunnelHealth
        if ($healthy) {
            $unhealthySince = $null; $backoff = 5
            Write-State 'ready' $true $true
        } else {
            if (-not $unhealthySince) { $unhealthySince = $now }
            Write-State 'reconnecting' $true $false
            if (($now - $unhealthySince).TotalSeconds -ge 90) {
                Write-Event 'health_timeout_restart'; Stop-OwnedTunnel
                $restartCount++; $nextStart = $now.AddSeconds($backoff)
                $backoff = [Math]::Min(60, $backoff * 2)
            }
        }
        Start-Sleep -Seconds 5
    }
    Stop-OwnedTunnel
    Write-State 'stopped_obsidian_closed'
} catch {
    if ($_.Exception -is [System.Management.Automation.CommandNotFoundException] -and $_.Exception.CommandName -match '^[A-Za-z][A-Za-z0-9-]{0,60}$') { Write-Event ('missing_command_' + $_.Exception.CommandName) }
    if ($locked) { Write-Event ('supervisor_error_type_' + $_.Exception.GetType().Name + '_line_' + $_.InvocationInfo.ScriptLineNumber); Stop-OwnedTunnel; Write-State 'supervisor_error' }
    exit 1
} finally {
    if ($locked) {
        Stop-OwnedTunnel
        if ($job -ne [IntPtr]::Zero) { [ObsidianTunnelJob]::CloseHandle($job) | Out-Null }
        $token = $null
        $mutex.ReleaseMutex()
    }
    $mutex.Dispose()
}
