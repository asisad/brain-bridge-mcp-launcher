#Requires -Version 5.1
# Fixed destinations only. Never append configuration, IDs or credentials to a URL.
function Get-BrainBridgeResource([string]$Key) {
  switch ($Key) {
    'download' { return 'https://github.com/openai/tunnel-client/releases/latest' }
    'tunnels' { return 'https://platform.openai.com/settings/organization/tunnels' }
    'keys' { return 'https://platform.openai.com/settings/organization/api-keys' }
    'guide' { return (Join-Path $PSScriptRoot 'help\index.fa.html') }
    default { throw 'Unknown help destination.' }
  }
}
function Open-BrainBridgeResource([string]$Key,[switch]$ResolveOnly) {
  $destination=Get-BrainBridgeResource $Key
  if ($Key -eq 'guide' -and -not (Test-Path -LiteralPath $destination -PathType Leaf)) { throw 'Help files missing. Extract the complete package again.' }
  if (-not $ResolveOnly) {
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$destination
    $info.UseShellExecute=$true
    $null=[Diagnostics.Process]::Start($info)
  }
  return $destination
}
