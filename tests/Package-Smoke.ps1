#Requires -Version 5.1
# Static checks only: no secrets, network calls, or vault access.
$root = Split-Path -Parent $PSScriptRoot
$required = @(
 'README.md','LICENSE','SECURITY.md','CHANGELOG.md',
 'scripts/Install-BrainBridge.ps1','scripts/Start-BrainBridge.ps1',
 'scripts/Status-BrainBridge.ps1','scripts/Stop-BrainBridge.ps1',
 'scripts/Remove-BrainBridge.ps1','docs/README.fa.md',
 'docs/ARCHITECTURE.md','docs/ROADMAP.md'
)
$missing = $required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $root $_)) }
if ($missing) { throw ('Missing files: ' + ($missing -join ', ')) }
$pattern = '(?i)sk-(?:proj-)?[a-z0-9_-]{20,}|tunnel_[a-f0-9]{32}'
$files = Get-ChildItem -LiteralPath $root -Recurse -File |
    Where-Object { $_.Extension -in @('.ps1','.md','.json','.vbs','.txt') }
$violations = @()
foreach ($file in $files) {
    if ((Get-Content -LiteralPath $file.FullName -Raw) -match $pattern) {
        $violations += $file.FullName
    }
}
if ($violations) { throw ('Possible literal credentials in: ' + ($violations -join ', ')) }
Write-Host 'PASS: package inventory and basic credential scan'
