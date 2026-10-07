#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param([string]$InstallRoot=(Join-Path $env:LOCALAPPDATA 'BrainBridge'),[switch]$RemoveLocalConfig)
$shortcut=Join-Path ([Environment]::GetFolderPath('Startup')) 'Brain Bridge.lnk'
if ((Test-Path -LiteralPath $shortcut) -and $PSCmdlet.ShouldProcess($shortcut,'Remove startup shortcut')) {
  Remove-Item -LiteralPath $shortcut -Force
}
Write-Host 'Auto-start removed; stop the runner separately.'
if ($RemoveLocalConfig -and (Test-Path -LiteralPath $InstallRoot)) {
  if ($PSCmdlet.ShouldProcess($InstallRoot,'Remove local encrypted credentials and config')) {
    Remove-Item -LiteralPath $InstallRoot -Recurse -Force
    Write-Host 'Local configuration removed.'
  }
}
