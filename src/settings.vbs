' Opens the Jipeg settings window without flashing a console window.
Option Explicit
Dim fso, sh, base, script
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")
base   = fso.GetParentFolderName(WScript.ScriptFullName)
script = base & "\Jipeg-Settings.ps1"
sh.Run "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -STA -File """ & script & """", 0, False
