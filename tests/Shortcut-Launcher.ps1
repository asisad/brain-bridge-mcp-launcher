#Requires -Version 5.1
[CmdletBinding()]
param([switch]$SkipSlowRecovery)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1')
$repo = Split-Path -Parent $PSScriptRoot
$example = Join-Path $repo 'examples\obsidian-shortcut-launcher'
. (Join-Path $example 'Launcher-Config.ps1')
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('brainbridge-shortcut-' + [Guid]::NewGuid().ToString('N'))
$install = Join-Path $sandbox 'install with spaces'
$null = New-Item -ItemType Directory -Path $install -Force
$script:checks = 0
$server = $null
$runner = $null
function Assert($Value, [string]$Message) { if (-not $Value) { throw $Message }; $script:checks++ }
function Read-State {
    try { Get-Content -LiteralPath (Join-Path $install 'state\status.json') -Raw | ConvertFrom-Json } catch { return $null }
}
function Wait-State([string]$Name, [int]$Timeout, [int]$DifferentChild = 0) {
    $until = [DateTime]::UtcNow.AddSeconds($Timeout)
    do {
        $snapshot = Read-State
        if ($snapshot -and $snapshot.state -eq $Name -and (-not $DifferentChild -or ($snapshot.tunnel_pid -and $snapshot.tunnel_pid -ne $DifferentChild))) { return $snapshot }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $until)
    throw ('Timed out waiting for fixture state: ' + $Name)
}
function Get-OwnedChild($Snapshot) {
    $p = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$Snapshot.tunnel_pid)
    if (-not $p -or $p.ParentProcessId -ne $Snapshot.supervisor_pid -or $p.ExecutablePath -ne (Join-Path $sandbox 'tunnel-client.exe')) { throw 'Fixture child identity mismatch.' }
    return Get-Process -Id $p.ProcessId
}
function Save-Config($Value) { $Value | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $install 'launcher-config.json') -Encoding UTF8 }
try {
    Copy-Item -LiteralPath (Join-Path $example 'Start-ObsidianTunnel.ps1'),(Join-Path $example 'Get-ObsidianTunnelStatus.ps1'),(Join-Path $example 'Launcher-Config.ps1'),(Join-Path $example 'Open-Obsidian.vbs'),(Join-Path $example 'Run-Hidden.vbs') -Destination $install
    Add-Type -TypeDefinition @'
using System;
using System.Threading;
public class MockObsidian { public static void Main() { Thread.Sleep(300000); } }
'@ -OutputAssembly (Join-Path $sandbox 'Obsidian.exe') -OutputType WindowsApplication
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
public class MockShortcutTunnel {
 public static void Main() {
  if (Environment.GetEnvironmentVariable("CONTROL_PLANE_API_KEY") != "synthetic-shortcut-runtime") Environment.Exit(7);
  if (Environment.GetEnvironmentVariable("OBSIDIAN_MCP_AUTH") != "Bearer synthetic-shortcut-token") Environment.Exit(8);
  if (Environment.GetEnvironmentVariable("TUNNEL_CLIENT_PROFILE") != null) Environment.Exit(9);
  Console.WriteLine("synthetic-shortcut-runtime synthetic-shortcut-token");
  Console.Error.WriteLine("synthetic-shortcut-runtime synthetic-shortcut-token");
  TcpListener listener = new TcpListener(IPAddress.Loopback, 0); listener.Start();
  File.WriteAllText(Environment.GetEnvironmentVariable("HEALTH_URL_FILE"), "http://127.0.0.1:" + ((IPEndPoint)listener.LocalEndpoint).Port);
  while (true) {
   using (TcpClient client = listener.AcceptTcpClient()) {
    client.ReceiveTimeout = 3000; client.SendTimeout = 3000;
    using (NetworkStream stream = client.GetStream()) {
     StreamReader reader = new StreamReader(stream); string line;
     do { line = reader.ReadLine(); } while (line != null && line.Length != 0);
     string body = "{\"live\":true,\"ready\":true,\"components\":{\"control-plane\":{\"status\":\"ok\",\"observed_at\":\"" + DateTime.UtcNow.ToString("o") + "\"}}}";
     byte[] payload = Encoding.UTF8.GetBytes(body);
     byte[] header = Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: " + payload.Length + "\r\n\r\n");
     stream.Write(header,0,header.Length); stream.Write(payload,0,payload.Length);
    }
   }
  }
 }
}
'@ -OutputAssembly (Join-Path $sandbox 'tunnel-client.exe') -OutputType ConsoleApplication
    $portFile = Join-Path $sandbox 'port.txt'
    $modeFile = Join-Path $sandbox 'mode.txt'
    $server = Start-Process -FilePath (Get-Command python.exe).Source -ArgumentList ('"' + (Join-Path $PSScriptRoot 'shortcut_mcp.py') + '" "' + $portFile + '" "' + $modeFile + '"') -WindowStyle Hidden -PassThru
    for ($i = 0; $i -lt 100 -and -not (Test-Path -LiteralPath $portFile); $i++) { Start-Sleep -Milliseconds 100 }
    Assert (Test-Path -LiteralPath $portFile) 'Fixture MCP did not start.'
    $config = [pscustomobject]@{ schema_version = 1; obsidian_exe = (Join-Path $sandbox 'Obsidian.exe'); tunnel_exe = (Join-Path $sandbox 'tunnel-client.exe'); tunnel_sha256 = (Get-FileHash -LiteralPath (Join-Path $sandbox 'tunnel-client.exe')).Hash; tunnel_id = 'tunnel_' + ('a' * 32); mcp_url = 'http://127.0.0.1:' + (Get-Content -LiteralPath $portFile) + '/mcp' }
    Save-Config $config
    Assert ([bool](Read-LauncherConfig $install)) 'Valid fixture config rejected.'
    Assert ((Get-LauncherMutexName $install) -ne (Get-LauncherMutexName (Join-Path $sandbox 'other'))) 'Different installations share a mutex.'
    $goodUrl = $config.mcp_url
    foreach ($badUrl in @('https://example.com/mcp', 'http://127.0.0.1/mcp?token=fixture', 'http://user:fixture@127.0.0.1/mcp', 'http://127.0.0.1/mcp#fixture', 'http://127.0.0.1/broker/mcp')) {
        $config.mcp_url = $badUrl; Save-Config $config
        $rejected = $false; try { Read-LauncherConfig $install | Out-Null } catch { $rejected = $true }
        Assert $rejected 'Unsafe MCP target accepted.'
    }
    $config.mcp_url = $goodUrl; Save-Config $config
    $badHash = $config.PSObject.Copy(); $badHash.tunnel_sha256 = 'b' * 64
    $rejected = $false; try { Assert-LauncherClientHash $badHash } catch { $rejected = $true }
    Assert $rejected 'Changed client hash accepted.'
    ConvertTo-SecureString 'synthetic-shortcut-runtime' -AsPlainText -Force | ConvertFrom-SecureString | Set-Content -LiteralPath (Join-Path $install 'runtime-key.dpapi')
    ConvertTo-SecureString 'synthetic-shortcut-token' -AsPlainText -Force | ConvertFrom-SecureString | Set-Content -LiteralPath (Join-Path $install 'obsidian-token.dpapi')
    $beforeKeys = @((Get-FileHash -LiteralPath (Join-Path $install 'runtime-key.dpapi')).Hash, (Get-FileHash -LiteralPath (Join-Path $install 'obsidian-token.dpapi')).Hash)
    $previousProfile = [Environment]::GetEnvironmentVariable('TUNNEL_CLIENT_PROFILE', 'Process')
    try {
        $env:TUNNEL_CLIENT_PROFILE = 'must-not-reach-fixture-child'
        $runner = Start-Process -FilePath "$env:SystemRoot\System32\wscript.exe" -ArgumentList ('//B //Nologo "' + (Join-Path $install 'Open-Obsidian.vbs') + '"') -WindowStyle Hidden -PassThru
    } finally { [Environment]::SetEnvironmentVariable('TUNNEL_CLIENT_PROFILE', $previousProfile, 'Process') }
    $first = Wait-State 'ready' 35
    Assert $first.local_mcp_ready 'Authenticated fixture MCP probe failed.'
    Assert $first.tunnel_health_ready 'Fixture tunnel health failed.'
    $child = Get-OwnedChild $first; $child.Dispose()
    $status = & (Join-Path $install 'Get-ObsidianTunnelStatus.ps1') | ConvertFrom-Json
    Assert ($status.supervisor_running -and $status.tunnel_running) 'Status did not verify owned processes.'
    1..3 | ForEach-Object { Start-Process -FilePath "$env:SystemRoot\System32\wscript.exe" -ArgumentList ('//B //Nologo "' + (Join-Path $install 'Run-Hidden.vbs') + '"') -WindowStyle Hidden }
    Start-Sleep -Seconds 3
    $duplicates = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -match [regex]::Escape((Join-Path $install 'Start-ObsidianTunnel.ps1')) })
    Assert ($duplicates.Count -eq 1) 'Duplicate supervisors started.'
    Assert ((Read-State).tunnel_pid -eq $first.tunnel_pid) 'Duplicate launch replaced the tunnel.'
    $child = Get-OwnedChild $first; $child.Kill(); $child.Dispose()
    $recovered = Wait-State 'ready' 35 $first.tunnel_pid
    Assert ($recovered.supervisor_pid -eq $first.supervisor_pid -and $recovered.restart_count -ge 1) 'Child crash did not recover under the same supervisor.'
    [IO.File]::WriteAllText($modeFile, 'unauthorized')
    $waiting = Wait-State 'waiting_for_mcp' 15
    $until = [DateTime]::UtcNow.AddSeconds(25)
    do { Start-Sleep -Seconds 1; $waiting = Read-State } while ($waiting.tunnel_pid -and [DateTime]::UtcNow -lt $until)
    Assert (-not $waiting.tunnel_pid) 'Tunnel continued after sustained authenticated MCP failure.'
    [IO.File]::WriteAllText($modeFile, 'ok')
    $recovered = Wait-State 'ready' 20
    Assert $recovered.local_mcp_ready 'Local MCP recovery failed.'
    if (-not $SkipSlowRecovery) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ShortcutFixtureFreeze {
 [DllImport("ntdll.dll")] public static extern int NtSuspendProcess(IntPtr p);
 [DllImport("ntdll.dll")] public static extern int NtResumeProcess(IntPtr p);
}
'@
        $child = Get-OwnedChild $recovered
        try {
            Assert ([ShortcutFixtureFreeze]::NtSuspendProcess($child.Handle) -eq 0) 'Fixture suspend failed.'
            $next = Wait-State 'ready' 125 $recovered.tunnel_pid
            Assert ($next.supervisor_pid -eq $recovered.supervisor_pid) 'Unresponsive child recovery lost the supervisor.'
        } finally { if (-not $child.HasExited) { [ShortcutFixtureFreeze]::NtResumeProcess($child.Handle) | Out-Null }; $child.Dispose() }
    }
    foreach ($p in @(Get-Process Obsidian -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $config.obsidian_exe })) { $p.Kill() }
    $closed = Wait-State 'stopped_obsidian_closed' 25
    Start-Sleep -Seconds 1
    Assert (-not (Get-Process -Id $closed.supervisor_pid -ErrorAction SilentlyContinue)) 'Supervisor survived fixture app exit.'
    Assert (-not $closed.tunnel_pid) 'Tunnel survived fixture app exit.'
    foreach ($name in @('runtime-key.dpapi', 'obsidian-token.dpapi')) {
        $index = if ($name -eq 'runtime-key.dpapi') { 0 } else { 1 }
        Assert ((Get-FileHash -LiteralPath (Join-Path $install $name)).Hash -eq $beforeKeys[$index]) 'Fixture key file changed.'
    }
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $install 'state') -File)) {
        Assert (-not ((Get-Content -LiteralPath $file.FullName -Raw) -match 'synthetic-shortcut-runtime|synthetic-shortcut-token')) 'A synthetic secret reached diagnostics.'
    }
    Write-Output ('PASS: ' + $script:checks + ' shortcut launcher integration checks; slow recovery skipped: ' + $SkipSlowRecovery.IsPresent)
} finally {
    # All stop targets are private fixtures verified by their exact executable/script paths.
    foreach ($p in @(Get-CimInstance Win32_Process | Where-Object {
        ($_.Name -eq 'powershell.exe' -and $_.CommandLine -match [regex]::Escape((Join-Path $install 'Start-ObsidianTunnel.ps1'))) -or
        $_.ExecutablePath -in @((Join-Path $sandbox 'Obsidian.exe'), (Join-Path $sandbox 'tunnel-client.exe'))
    })) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
    if ($server -and -not $server.HasExited) { $server.Kill(); $server.WaitForExit(5000) | Out-Null }
    $resolved = [IO.Path]::GetFullPath($sandbox)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'brainbridge-shortcut-*') { throw 'Unsafe fixture cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
