<#  Removes Jipeg: context menu, shortcut, files and the uninstall entry.  #>
param([switch]$Silent)

$ErrorActionPreference = 'SilentlyContinue'
[void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')

$Dest      = Join-Path $env:LOCALAPPDATA 'Jipeg'
$UninstKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Jipeg'
$Shortcut  = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Jipeg Settings.lnk'
$Exts = @('.png', '.apng', '.jpg', '.jpeg', '.jpe', '.gif', '.bmp', '.tif', '.tiff',
          '.jxl', '.ppm', '.pnm', '.pgm', '.pam', '.pfm')

if (-not $Silent) {
    $r = [System.Windows.Forms.MessageBox]::Show(
        'Remove Jipeg?' + [Environment]::NewLine + [Environment]::NewLine +
        "The context menu entry and the folder $Dest will be deleted." + [Environment]::NewLine +
        'Images you already converted are left alone.',
        'Uninstall Jipeg', 'YesNo', 'Question')
    if ($r -ne 'Yes') { exit }
}

foreach ($e in $Exts) {
    Remove-Item -Path "HKCU:\Software\Classes\SystemFileAssociations\$e\shell\JipegConvert" -Recurse -Force
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
if (Test-Path -LiteralPath $Dest) {
    Start-Process -FilePath 'cmd.exe' -WindowStyle Hidden -ArgumentList @(
        '/c', 'ping', '127.0.0.1', '-n', '3', '>nul', '&', 'rd', '/s', '/q', ('"{0}"' -f $Dest))
}

if (-not $Silent) {
    [void][System.Windows.Forms.MessageBox]::Show('Jipeg has been removed.', 'Jipeg', 'OK', 'Information')
}
