#Requires -Version 5.1
# Shared validation. Never include supplied values or exception messages in UI/logs.
function Assert-BrainBridgeConfig($Client, $Tunnel, $Url) {
  if ($Tunnel -cnotmatch '^tunnel_(?:[a-z0-9]{4}_)?[a-z0-9]{32}$') { throw 'Invalid Tunnel ID.' }
  $uri = $null
  if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri) -or
      $uri.Scheme -notin @('http','https') -or
      $uri.DnsSafeHost.Trim('[',']') -notin @('localhost','127.0.0.1','::1','0000:0000:0000:0000:0000:0000:0000:0001') -or
      $uri.AbsolutePath -ne '/mcp' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) {
    throw 'Use a direct loopback HTTP(S) URL with path /mcp, without credentials, query or fragment.'
  }
  if (-not [IO.Path]::IsPathRooted($Client) -or $Client.StartsWith('\\') -or
      [IO.Path]::GetFileName($Client) -ne 'tunnel-client.exe' -or
      -not (Test-Path -LiteralPath $Client -PathType Leaf)) { throw 'Select a local tunnel-client.exe using its full path.' }
  $item = Get-Item -LiteralPath $Client
  if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Executable links are not supported.' }
  return $uri
}
function Assert-BrainBridgeRoot([string]$Root) {
  $full = [IO.Path]::GetFullPath($Root).TrimEnd('\')
  if ($full.StartsWith('\\') -or [IO.Path]::GetFileName($full) -ne 'BrainBridge' -or
      $full -eq [IO.Path]::GetPathRoot($full).TrimEnd('\')) { throw 'Installation directory must be a local folder named BrainBridge.' }
  $walk = $full
  while ($walk) {
    if (Test-Path -LiteralPath $walk) {
      if ((Get-Item -LiteralPath $walk).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Installation directory cannot contain links or junctions.' }
    }
    $walk = Split-Path -Parent $walk
  }
  return $full
}
function Protect-BrainBridgeDirectory([string]$Root) {
  $acl = New-Object Security.AccessControl.DirectorySecurity
  $acl.SetAccessRuleProtection($true, $false)
  foreach ($sid in @([Security.Principal.WindowsIdentity]::GetCurrent().User, (New-Object Security.Principal.SecurityIdentifier('S-1-5-18')))) {
    $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
    $acl.AddAccessRule($rule)
  }
  Set-Acl -LiteralPath $Root -AclObject $acl
}
function Get-BrainBridgePlain([Security.SecureString]$Secret) {
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}
function New-BrainBridgeProcess($Config, [Security.SecureString]$Runtime, [Security.SecureString]$Token, [string]$Arguments) {
  $null = Assert-BrainBridgeConfig $Config.tunnel_client_exe $Config.tunnel_id $Config.mcp_url
  if ($Config.client_sha256 -and (Get-FileHash -LiteralPath $Config.tunnel_client_exe -Algorithm SHA256).Hash -ne $Config.client_sha256) { throw 'Client changed. Review the executable and reinstall.' }
  $info = New-Object Diagnostics.ProcessStartInfo
  $info.FileName = $Config.tunnel_client_exe
  $info.Arguments = $Arguments
  $info.WorkingDirectory = Split-Path -Parent $Config.tunnel_client_exe
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  # Do not inherit competing tunnel configuration, profiles, admin keys or proxies.
  foreach ($name in @($info.EnvironmentVariables.Keys)) {
    if ($name -match '^(CONTROL_PLANE_|MCP_|OPENAI_|OBSIDIAN_|TUNNEL_|HEALTH_|HTTP_PROXY$|HTTPS_PROXY$|ALL_PROXY$)') { $info.EnvironmentVariables.Remove($name) }
  }
  $info.EnvironmentVariables['CONTROL_PLANE_API_KEY'] = Get-BrainBridgePlain $Runtime
  $info.EnvironmentVariables['CONTROL_PLANE_TUNNEL_ID'] = $Config.tunnel_id
  $info.EnvironmentVariables['MCP_SERVER_URL'] = $Config.mcp_url
  $info.EnvironmentVariables['OBSIDIAN_MCP_AUTH'] = 'Bearer ' + (Get-BrainBridgePlain $Token)
  $info.EnvironmentVariables['MCP_EXTRA_HEADERS'] = 'Authorization: env:OBSIDIAN_MCP_AUTH'
  $info.EnvironmentVariables['MCP_DISCOVERY_EXTRA_HEADERS'] = 'Authorization: env:OBSIDIAN_MCP_AUTH'
  $process = New-Object Diagnostics.Process
  $process.StartInfo = $info
  try { $null = $process.Start() }
  finally { $info.EnvironmentVariables.Clear() }
  # Drain output without recording it or retaining unbounded buffers.
  $process.BeginOutputReadLine()
  $process.BeginErrorReadLine()
  return $process
}
function Test-BrainBridgeConnection($Config, [Security.SecureString]$Runtime, [Security.SecureString]$Token) {
  $uri = Assert-BrainBridgeConfig $Config.tunnel_client_exe $Config.tunnel_id $Config.mcp_url
  if (-not $Runtime.Length -or -not $Token.Length) { throw 'Both credentials are required.' }
  $authorization = 'Bearer ' + (Get-BrainBridgePlain $Token)
  try {
    $body = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"brain-bridge","version":"0.2.0"}}}'
    $response = Invoke-WebRequest -UseBasicParsing -Uri $uri -Method POST -Headers @{Authorization=$authorization; Accept='application/json, text/event-stream'} -ContentType 'application/json' -Body $body -MaximumRedirection 0 -TimeoutSec 8 -ErrorAction Stop
    $content = $response.Content
    if ($response.Headers['Content-Type'] -like 'text/event-stream*') {
      $content = (($content -split "`n" | Where-Object { $_ -match '^data:\s*\{' } | Select-Object -First 1) -replace '^data:\s*','')
    }
    $reply = $content | ConvertFrom-Json
    if ($response.StatusCode -ne 200 -or $reply.jsonrpc -ne '2.0' -or $reply.id -ne 1 -or $reply.error -or -not $reply.result.protocolVersion -or -not $reply.result.serverInfo) { throw 'Invalid handshake.' }
  } catch { throw 'MCP initialization failed. Check local server, token, URL and access policy.' }
  finally { $authorization = $null }
  foreach ($command in @(('admin tunnels get '+$Config.tunnel_id), 'doctor --health.listen-addr 127.0.0.1:0')) {
    $process = New-BrainBridgeProcess $Config $Runtime $Token $command
    try {
      if (-not $process.WaitForExit(30000)) { $process.Kill(); throw 'Runtime check timed out.' }
      if ($process.ExitCode -ne 0) { throw 'Runtime check failed. Check Read + Use permissions, client compatibility and network.' }
    } finally { $process.Dispose() }
  }
  'MCP initialize, Runtime tunnel lookup and client doctor passed. Use permission and remote connectivity still require a running tunnel.'
}
function Get-BrainBridgeRunner([string]$Root) {
  $file = Join-Path $Root 'runner.json'
  if (-not (Test-Path -LiteralPath $file)) { return $null }
  try {
    $record = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
    $p = Get-Process -Id $record.pid -ErrorAction Stop
    $row = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$record.pid)
    $expected = Join-Path $Root 'Start-BrainBridge.ps1'
    if ($p.StartTime.ToUniversalTime().Ticks.ToString() -ne $record.started -or
        $p.ProcessName -ne 'powershell' -or -not $row.CommandLine.Contains('"' + $expected + '"')) { return $null }
    return $p
  } catch { return $null }
}
