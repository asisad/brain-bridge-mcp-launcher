#Requires -Version 5.1
# Pure configuration helpers. No secrets, process launch or installation side effects.
function Read-LauncherConfig([string]$BasePath) {
    $config = Get-Content -LiteralPath (Join-Path $BasePath 'launcher-config.json') -Raw | ConvertFrom-Json
    if ($config.schema_version -ne 1) { throw 'Unsupported launcher configuration.' }
    foreach ($name in @('obsidian_exe', 'tunnel_exe')) {
        $path = [Environment]::ExpandEnvironmentVariables([string]$config.$name)
        if (-not [IO.Path]::IsPathRooted($path) -or $path.StartsWith('\\') -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Select existing local executable paths.' }
        $config.$name = [IO.Path]::GetFullPath($path)
        $walk = $config.$name
        while ($walk) {
            if ((Get-Item -LiteralPath $walk -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Executable paths cannot contain links or junctions.' }
            $walk = Split-Path -Parent $walk
        }
    }
    if ([IO.Path]::GetFileName($config.obsidian_exe) -ine 'Obsidian.exe' -or [IO.Path]::GetFileName($config.tunnel_exe) -ine 'tunnel-client.exe') { throw 'Select Obsidian.exe and tunnel-client.exe.' }
    if ($config.tunnel_id -cnotmatch '^tunnel_(?:[a-z0-9]{4}_)?[a-z0-9]{32}$') { throw 'Enter an existing Tunnel ID.' }
    if ($config.tunnel_sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Configure the SHA-256 of the verified official tunnel client.' }
    $uri = $null
    if (-not [Uri]::TryCreate($config.mcp_url, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -notin @('http', 'https') -or
        $uri.DnsSafeHost.Trim('[', ']') -notin @('localhost', '127.0.0.1', '::1', '0000:0000:0000:0000:0000:0000:0000:0001') -or
        $uri.AbsolutePath -ne '/mcp' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) { throw 'Use a direct loopback HTTP(S) /mcp URL without credentials, query or fragment.' }
    return $config
}
function Assert-LauncherClientHash($Config) {
    if ((Get-FileHash -LiteralPath $Config.tunnel_exe -Algorithm SHA256).Hash -ne $Config.tunnel_sha256) { throw 'Tunnel executable changed; verify the official download before updating its saved hash.' }
}
function Get-LauncherMutexName([string]$BasePath) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value + '|' + [IO.Path]::GetFullPath($BasePath).TrimEnd('\').ToLowerInvariant()
    $hash = [Security.Cryptography.SHA256]::Create()
    try { $digest = [BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity))).Replace('-', '') }
    finally { $hash.Dispose() }
    return 'Local\ObsidianTunnelSupervisor-' + $digest.Substring(0, 24)
}
