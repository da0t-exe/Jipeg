' Runs the quiet update check with no console window at all.
Option Explicit
Dim fso, sh, base, script
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")
base   = fso.GetParentFolderName(WScript.ScriptFullName)
script = base & "\Jipeg-Update.ps1"
sh.Run "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & script & """", 0, False
