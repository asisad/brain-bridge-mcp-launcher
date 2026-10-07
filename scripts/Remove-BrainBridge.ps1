#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param([string]$InstallRoot=(Join-Path $env:LOCALAPPDATA 'BrainBridge'),[switch]$RemoveLocalConfig,[string]$StartupDirectory=([Environment]::GetFolderPath('Startup')))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'BrainBridge.Core.ps1')
$InstallRoot=Assert-BrainBridgeRoot $InstallRoot
if ($RemoveLocalConfig -and (Test-Path -LiteralPath $InstallRoot)) {
  $marker=Join-Path $InstallRoot '.brainbridge-install'
  if (-not (Test-Path -LiteralPath $marker) -or (Get-Content -LiteralPath $marker -Raw).Trim() -ne 'BrainBridge') { throw 'Installation ownership marker missing. Refusing recursive removal.' }
  if (Get-ChildItem -LiteralPath $InstallRoot -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) { throw 'Links found in installation. Refusing removal.' }
}
if ($PSCmdlet.ShouldProcess('BrainBridge installation','Stop runner and remove startup')) {
  & (Join-Path $PSScriptRoot 'Stop-BrainBridge.ps1') -InstallRoot $InstallRoot
  $shortcut=Join-Path $StartupDirectory 'Brain Bridge.lnk'
  if (Test-Path -LiteralPath $shortcut) {
    $shell=New-Object -ComObject WScript.Shell
    $link=$shell.CreateShortcut($shortcut)
    if ($link.Arguments -eq ('"'+(Join-Path $InstallRoot 'Run-Hidden.vbs')+'"')) { Remove-Item -LiteralPath $shortcut -Force }
    else { throw 'Startup shortcut belongs to another installation.' }
  }
  if ($RemoveLocalConfig -and (Test-Path -LiteralPath $InstallRoot)) { Remove-Item -LiteralPath $InstallRoot -Recurse -Force }
  'Removal completed. Third-party software and vault data were not removed.'
}
