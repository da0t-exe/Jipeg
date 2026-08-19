' Starts the Jipeg converter without flashing a console window.
Option Explicit
Dim fso, sh, base, script, cmd, i
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")
base   = fso.GetParentFolderName(WScript.ScriptFullName)
script = base & "\Jipeg-Convert.ps1"
cmd    = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -STA -File """ & script & """"
For i = 0 To WScript.Arguments.Count - 1
    cmd = cmd & " """ & WScript.Arguments(i) & """"
Next
sh.Run cmd, 0, False
