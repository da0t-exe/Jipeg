<#  Removes Jipeg: context menu, shortcut, files and the uninstall entry.  #>
param([switch]$Silent)

$ErrorActionPreference = 'SilentlyContinue'
[void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')

$Dest      = Join-Path $env:LOCALAPPDATA 'Jipeg'
$L = Import-JipegLang (Get-JipegSettings).language
$UninstKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Jipeg'
$Shortcut  = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Jipeg Settings.lnk'

if (-not $Silent) {
    $r = [System.Windows.Forms.MessageBox]::Show(
        $L.unAsk + [Environment]::NewLine + [Environment]::NewLine +
        ($L.unWhat -f $Dest) + [Environment]::NewLine + $L.unKeep,
        $L.unTitle, 'YesNo', 'Question')
    if ($r -ne 'Yes') { exit }
}

# Every association that actually carries our key, rather than a copy of the
# installer's list: the two lists were already drifting apart, and an extension
# added to one and not the other would have been left behind here for good.
$assoc = 'HKCU:\Software\Classes\SystemFileAssociations'
if (Test-Path -LiteralPath $assoc) {
    Get-ChildItem -LiteralPath $assoc -ErrorAction SilentlyContinue | ForEach-Object {
        $key = Join-Path $_.PSPath 'shell\JipegConvert'
        if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force }
    }
}
Remove-Item -Path 'HKCU:\Software\Classes\Directory\shell\JipegConvert' -Recurse -Force
Remove-Item -LiteralPath $Shortcut -Force

# The Windows 11 classic menu tweak is only undone if we were the ones who set it.
if ((Get-ItemProperty -Path $UninstKey -Name 'ClassicMenuSet' -ErrorAction SilentlyContinue).ClassicMenuSet -eq 1) {
    Remove-Item -Path 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}' -Recurse -Force
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 800
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
}

Remove-Item -Path $UninstKey -Recurse -Force

# This script lives inside the folder being deleted, so hand that part to cmd.
#
# Two earlier shapes were wrong in opposite directions. One try, two seconds
# later: a conversion running at the time holds the scripts and cjpegli open, rd
# fails without a word, and 36 files stay behind for good - the menu gone, the
# megabytes not. Retrying hard instead was worse: it deleted the scripts out
# from under a running batch, which lost all five of its files.
#
# So it waits for the conversion rather than fighting it. The converter holds
# TEMP\jipeg.lock open with no sharing for as long as it runs - the same signal
# the quiet update already uses to keep out of the way. cmd can test it by
# trying to open it for append: that fails while anything holds it.
if (Test-Path -LiteralPath $Dest) {
    $lock = Join-Path $env:TEMP 'jipeg.lock'
    $bat  = Join-Path $env:TEMP ('jipeg-remove-{0}.cmd' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
    $lignes = @(
        '@echo off',
        'setlocal',
        ('set "VERROU=' + $lock + '"'),
        ('set "DOSSIER=' + $Dest + '"'),
        'rem on attend que la conversion rende le verrou, deux minutes au plus',
        'for /l %%a in (1,1,60) do (',
        '  if not exist "%VERROU%" goto libre',
        '  2>nul ( >>"%VERROU%" call ) && goto libre',
        '  ping 127.0.0.1 -n 3 >nul',
        ')',
        ':libre',
        'rem puis on efface, en reessayant : un fichier peut rester une seconde',
        'for /l %%b in (1,1,10) do (',
        '  rd /s /q "%DOSSIER%" 2>nul',
        '  if not exist "%DOSSIER%" goto fini',
        '  ping 127.0.0.1 -n 2 >nul',
        ')',
        ':fini',
        'del /f /q "%~f0" 2>nul'
    )
    Set-Content -LiteralPath $bat -Value $lignes -Encoding OEM
    Start-Process -FilePath 'cmd.exe' -WindowStyle Hidden -ArgumentList @('/c', ('"{0}"' -f $bat))
}

if (-not $Silent) {
    [void][System.Windows.Forms.MessageBox]::Show($L.unDone, 'Jipeg', 'OK', 'Information')
}
