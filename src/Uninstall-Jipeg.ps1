<#  Retire Jipeg : menu contextuel, fichiers, entrée de désinstallation.  #>
param([switch]$Silent)

$ErrorActionPreference = 'SilentlyContinue'
[void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')

$Dest      = Join-Path $env:LOCALAPPDATA 'Jipeg'
$UninstKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Jipeg'
$Exts = @('.png', '.apng', '.jpg', '.jpeg', '.jpe', '.gif', '.bmp', '.tif', '.tiff',
          '.jxl', '.ppm', '.pnm', '.pgm', '.pam', '.pfm')

if (-not $Silent) {
    $r = [System.Windows.Forms.MessageBox]::Show(
        "Retirer Jipeg ?" + [Environment]::NewLine + [Environment]::NewLine +
        "L'entrée du clic droit et le dossier $Dest seront supprimés." + [Environment]::NewLine +
        "Les images déjà converties ne sont pas touchées.",
        'Désinstaller Jipeg', 'YesNo', 'Question')
    if ($r -ne 'Yes') { exit }
}

foreach ($e in $Exts) {
    Remove-Item -Path "HKCU:\Software\Classes\SystemFileAssociations\$e\shell\JipegConvert" -Recurse -Force
}
Remove-Item -Path 'HKCU:\Software\Classes\Directory\shell\JipegConvert' -Recurse -Force

# menu classique de Windows 11 : seulement si c'est nous qui l'avions activé
if ((Get-ItemProperty -Path $UninstKey -Name 'ClassicMenuSet' -ErrorAction SilentlyContinue).ClassicMenuSet -eq 1) {
    Remove-Item -Path 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}' -Recurse -Force
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 800
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
}

Remove-Item -Path $UninstKey -Recurse -Force

# ce script vit dans le dossier à supprimer : on délègue à cmd
if (Test-Path -LiteralPath $Dest) {
    Start-Process -FilePath 'cmd.exe' -WindowStyle Hidden -ArgumentList @(
        '/c', 'ping', '127.0.0.1', '-n', '3', '>nul', '&', 'rd', '/s', '/q', ('"{0}"' -f $Dest))
}

if (-not $Silent) {
    [void][System.Windows.Forms.MessageBox]::Show('Jipeg a été retiré.', 'Jipeg', 'OK', 'Information')
}
