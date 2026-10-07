Option Explicit
Dim shell, files, root, script, powershell
Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
root = files.GetParentFolderName(WScript.ScriptFullName)
script = files.BuildPath(root, "scripts\BrainBridge.Gui.ps1")
powershell = shell.ExpandEnvironmentStrings("%WINDIR%\System32\WindowsPowerShell\v1.0\powershell.exe")
If Not files.FileExists(script) Then
  MsgBox "Extract the complete Brain Bridge package before opening Setup.", 16, "Brain Bridge"
  WScript.Quit 1
End If
shell.Run """" & powershell & """ -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & script & """", 0, False
