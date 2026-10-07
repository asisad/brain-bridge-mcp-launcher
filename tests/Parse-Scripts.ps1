#Requires -Version 5.1
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$count=0
foreach ($file in (Get-ChildItem (Join-Path $repo 'scripts'),$PSScriptRoot -Filter *.ps1)) {
  $tokens=$null; $errors=$null
  $null=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
  if ($errors.Count) { throw ('PowerShell syntax error in '+$file.Name) }
  $count++
}
'PASS: '+$count+' PowerShell files parsed.'
