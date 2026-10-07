#Requires -Version 5.1
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'scripts\BrainBridge.Core.ps1')
$sandbox=Join-Path ([IO.Path]::GetTempPath()) ('brainbridge-test-'+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $sandbox
$root=Join-Path $sandbox 'BrainBridge'
$startup=Join-Path $sandbox 'Startup'
$null=New-Item -ItemType Directory -Path $startup
$client=Join-Path $sandbox 'tunnel-client.exe'
$script:checks=0
function Assert($Value,$Message) { if (-not $Value) { throw $Message }; $script:checks++ }
function Reject([scriptblock]$Code) { $failed=$false; try { & $Code | Out-Null } catch { $failed=$true }; Assert $failed 'Expected rejection.' }
$server=$null
$runner=$null
try {
  Add-Type -TypeDefinition @'
using System;
using System.Threading;
public class MockTunnel {
 public static int Main(string[] args) {
  if (Environment.GetEnvironmentVariable("CONTROL_PLANE_API_KEY") != "synthetic-runtime") return 7;
  if (Environment.GetEnvironmentVariable("OBSIDIAN_MCP_AUTH") != "Bearer synthetic-token") return 8;
  Console.WriteLine("synthetic-runtime synthetic-token");
  Console.Error.WriteLine("synthetic-runtime synthetic-token");
  if (args[0] == "doctor" || args[0] == "admin") return Environment.GetEnvironmentVariable("BB_TEST_DENY") == "1" ? 1 : 0;
  Thread.Sleep(120000); return 0;
 }
}
'@ -OutputAssembly $client -OutputType ConsoleApplication
  $tunnel='tunnel_'+('a'*32)
  $runtime=ConvertTo-SecureString 'synthetic-runtime' -AsPlainText -Force
  $token=ConvertTo-SecureString 'synthetic-token' -AsPlainText -Force
  $portFile=Join-Path $sandbox 'port.txt'
  $mode=Join-Path $sandbox 'mode.txt'
  $python=(Get-Command python.exe).Source
  $server=Start-Process -FilePath $python -ArgumentList ('"'+(Join-Path $PSScriptRoot 'mock_mcp.py')+'" "'+$portFile+'" "'+$mode+'"') -WindowStyle Hidden -PassThru
  for ($i=0;$i -lt 50 -and -not (Test-Path $portFile);$i++) { Start-Sleep -Milliseconds 100 }
  $url='http://127.0.0.1:'+(Get-Content $portFile)+'/mcp'
  $c=@{tunnel_client_exe=$client;tunnel_id=$tunnel;mcp_url=$url}
  Assert ([bool](Assert-BrainBridgeConfig $client $tunnel $url)) 'Valid loopback rejected.'
  Assert ([bool](Assert-BrainBridgeConfig $client ('tunnel_ab12_'+('z'*32)) 'http://[::1]:27200/mcp')) 'Namespaced ID or IPv6 rejected.'
  foreach ($bad in @('https://example.com/mcp','http://127.0.0.1/mcp?token=x','http://u:p@127.0.0.1/mcp','http://127.0.0.1/mcp#x','file:///mcp','http://127.0.0.1/broker/mcp')) {
    Reject { Assert-BrainBridgeConfig $client $tunnel $bad }
  }
  Reject { Assert-BrainBridgeRoot $sandbox }
  [IO.File]::SetAttributes($sandbox,([IO.File]::GetAttributes($sandbox) -bor [IO.FileAttributes]::Hidden))
  Assert ((Assert-BrainBridgeRoot $root) -eq $root) 'Hidden parent directory rejected.'
  Assert ((Test-BrainBridgeConnection $c $runtime $token) -like '*passed*') 'Connection fixture failed.'
  foreach ($bad in @('unauthorized','forbidden','redirect','invalid')) {
    [IO.File]::WriteAllText($mode,$bad)
    Reject { Test-BrainBridgeConnection $c $runtime $token }
  }
  [IO.File]::WriteAllText($mode,'ok')
  $env:BB_TEST_DENY='1'
  Reject { Test-BrainBridgeConnection $c $runtime $token }
  Remove-Item Env:\BB_TEST_DENY
  & (Join-Path $repo 'scripts\Install-BrainBridge.ps1') -TunnelClientPath $client -TunnelId $tunnel -McpUrl $url -RuntimeKey $runtime -ObsidianToken $token -InstallRoot $root -StartupDirectory $startup -EnableAutoStart
  $cipher=Get-Content -LiteralPath (Join-Path $root 'runtime-key.dpapi') -Raw
  . (Join-Path $root 'BrainBridge.Help.ps1')
  Assert ((Open-BrainBridgeResource 'guide' -ResolveOnly) -eq (Join-Path $root 'help\index.fa.html')) 'Installed help does not resolve locally.'
  Reject { Open-BrainBridgeResource 'https://example.com/untrusted' -ResolveOnly }
  Assert (-not $cipher.Contains('synthetic-runtime')) 'Plaintext secret saved.'
  $decoded=$cipher.Trim() | ConvertTo-SecureString
  Assert ((Get-BrainBridgePlain $decoded) -eq 'synthetic-runtime') 'DPAPI roundtrip failed.'
  Assert ((Get-Acl -LiteralPath $root).AreAccessRulesProtected) 'ACL inheritance not disabled.'
  $link=(New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $startup 'Brain Bridge.lnk'))
  Assert ($link.Arguments -eq ('"'+(Join-Path $root 'Run-Hidden.vbs')+'"')) 'Startup target mismatch.'
  Assert ((Get-Content -LiteralPath (Join-Path $root 'Run-Hidden.vbs') -Raw) -match '0, False') 'Launcher not hidden.'
  $ps=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $fixtureError=Join-Path $sandbox 'fixture-error.txt'
  $runner=Start-Process -FilePath $ps -ArgumentList ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $root 'Start-BrainBridge.ps1')+'"') -WindowStyle Hidden -PassThru -RedirectStandardError $fixtureError
  for ($i=0;$i -lt 100;$i++) {
    if ((Test-Path (Join-Path $root 'state.txt')) -and (Get-Content (Join-Path $root 'state.txt') -Raw) -like '*Runner active*') { break }
    Start-Sleep -Milliseconds 100
  }
  if (-not (Get-BrainBridgeRunner $root)) {
    if (Test-Path (Join-Path $root 'state.txt')) { Get-Content (Join-Path $root 'state.txt') }
    if (Test-Path (Join-Path $root 'runner.json')) { Get-Content (Join-Path $root 'runner.json') }
    Write-Output ('Fixture runner exited: '+$runner.HasExited)
    Get-Content -LiteralPath $fixtureError
  }
  Assert ([bool](Get-BrainBridgeRunner $root)) 'Runner identity check failed.'
  Assert ((& (Join-Path $repo 'scripts\Status-BrainBridge.ps1') -InstallRoot $root | Out-String) -like '*Verified runner active: True*') 'Status failed.'
  [IO.File]::WriteAllText((Join-Path $root 'health.url'),($url -replace '/mcp$',''))
  Assert ((& (Join-Path $repo 'scripts\Status-BrainBridge.ps1') -InstallRoot $root | Out-String) -like '*endpoint: ready*') 'Scoped readiness failed.'
  Reject { & (Join-Path $repo 'scripts\Install-BrainBridge.ps1') -TunnelClientPath $client -TunnelId $tunnel -McpUrl $url -RuntimeKey $runtime -ObsidianToken $token -InstallRoot $root -StartupDirectory $startup }
  & (Join-Path $repo 'scripts\Stop-BrainBridge.ps1') -InstallRoot $root
  Assert (-not (Get-BrainBridgeRunner $root)) 'Runner remained active.'
  # An unrelated live PID must never be accepted, even if a state file is forged.
  @{pid=$PID;started=(Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks.ToString()} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'runner.json')
  Assert (-not (Get-BrainBridgeRunner $root)) 'Unrelated process accepted.'
  Remove-Item -LiteralPath (Join-Path $root 'runner.json')
  foreach ($f in (Get-ChildItem -LiteralPath $root -Recurse -File)) {
    Assert (-not ((Get-Content -LiteralPath $f.FullName -Raw) -match 'synthetic-runtime|synthetic-token')) 'Secret leaked into installation.'
  }
  $installed=Get-Content -LiteralPath (Join-Path $root 'config.json') -Raw | ConvertFrom-Json
  $installed.client_sha256='incorrect'
  Reject { New-BrainBridgeProcess $installed $runtime $token 'doctor' }
  # Exercise the actual hidden VBS entry point, not just its text.
  $launcher=Start-Process -FilePath (Join-Path $env:WINDIR 'System32\wscript.exe') -ArgumentList ('"'+(Join-Path $root 'Run-Hidden.vbs')+'"') -WindowStyle Hidden -PassThru
  for ($i=0;$i -lt 100;$i++) {
    $runner=Get-BrainBridgeRunner $root
    if ($runner) { break }; Start-Sleep -Milliseconds 100
  }
  Assert ([bool]$runner) 'Hidden VBS launch failed.'
  $marker=Join-Path $root '.brainbridge-install'
  [IO.File]::WriteAllText($marker,'unrelated')
  Reject { & (Join-Path $repo 'scripts\Remove-BrainBridge.ps1') -InstallRoot $root -StartupDirectory $startup -RemoveLocalConfig -Confirm:$false }
  Assert ([bool](Get-BrainBridgeRunner $root)) 'Invalid removal stopped a process.'
  [IO.File]::WriteAllText($marker,'BrainBridge')
  & (Join-Path $repo 'scripts\Remove-BrainBridge.ps1') -InstallRoot $root -StartupDirectory $startup -RemoveLocalConfig -WhatIf
  Assert (Test-Path $root) 'WhatIf removed installation.'
  & (Join-Path $repo 'scripts\Remove-BrainBridge.ps1') -InstallRoot $root -StartupDirectory $startup -RemoveLocalConfig -Confirm:$false
  Assert (-not (Test-Path $root)) 'Removal failed.'
  Assert (-not (Test-Path (Join-Path $startup 'Brain Bridge.lnk'))) 'Startup remained.'
  'PASS: '+$checks+' integration assertions; synthetic credentials and loopback fixture only.'
} finally {
  if ($server -and -not $server.HasExited) { $server.Kill(); $server.WaitForExit() }
  if ($runner -and -not $runner.HasExited) { & "$env:WINDIR\System32\taskkill.exe" /PID $runner.Id /T /F 2>&1 | Out-Null }
  Remove-Item Env:\BB_TEST_DENY -ErrorAction SilentlyContinue
  # Only this test's GUID-named, direct temporary child is eligible for cleanup.
  $full=[IO.Path]::GetFullPath($sandbox)
  if ((Split-Path -Parent $full) -eq [IO.Path]::GetTempPath().TrimEnd('\') -and (Split-Path -Leaf $full) -match '^brainbridge-test-[a-f0-9]{32}$') { Remove-Item -LiteralPath $full -Recurse -Force }
}
