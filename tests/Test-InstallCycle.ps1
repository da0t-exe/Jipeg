param([int]$Tours = 20)
# Installe et desinstalle en boucle, en relevant l'etat complet a chaque tour.
# Ce qu'on cherche : une trace qui reste, une cle qui differe d'un tour a
# l'autre, un raccourci qui survit - les choses qui ne se voient qu'en repetant.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$src  = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
$dest = Join-Path $env:LOCALAPPDATA 'Jipeg'
$prog = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Jipeg Settings.lnk'
$uninst = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Jipeg'

function Etat-Installe {
    $assoc = 'HKCU:\Software\Classes\SystemFileAssociations'
    $exts = @()
    if (Test-Path $assoc) {
        foreach ($e in (Get-ChildItem $assoc -ErrorAction SilentlyContinue)) {
            if (Test-Path (Join-Path $e.PSPath 'shell\JipegConvert')) { $exts += $e.PSChildName }
        }
    }
    [pscustomobject]@{
        Extensions = ($exts | Sort-Object) -join ','
        Dossier    = (Test-Path $dest)
        Binaires   = @(Get-ChildItem (Join-Path $dest 'bin') -Filter '*.exe' -ErrorAction SilentlyContinue).Count
        Langues    = @(Get-ChildItem (Join-Path $dest 'lang') -Filter '*.psd1' -ErrorAction SilentlyContinue).Count
        Dossiers   = (Test-Path 'HKCU:\Software\Classes\Directory\shell\JipegConvert')
        Programmes = (Test-Path $uninst)
        Raccourci  = (Test-Path $prog)
        Clsid      = (Test-Path 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}')
    }
}

$refInstalle = $null
$fautes = 0
for ($i = 1; $i -le $Tours; $i++) {
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $src 'Install-Jipeg.ps1') -Silent | Out-Null
    if ($LASTEXITCODE -ne 0) { "  tour $i : l'installation a rendu $LASTEXITCODE"; $fautes++ }
    $apres = Etat-Installe
    if ($null -eq $refInstalle) {
        $refInstalle = $apres
        '  reference : {0} extensions, {1} binaires, {2} langues, dossiers {3}, programmes {4}, raccourci {5}' -f
            ($apres.Extensions -split ',').Count, $apres.Binaires, $apres.Langues,
            $apres.Dossiers, $apres.Programmes, $apres.Raccourci
    } else {
        foreach ($p in 'Extensions','Dossier','Binaires','Langues','Dossiers','Programmes','Raccourci','Clsid') {
            if ($refInstalle.$p -ne $apres.$p) {
                "  tour $i : apres installation, $p vaut '$($apres.$p)' au lieu de '$($refInstalle.$p)'"
                $fautes++
            }
        }
    }

    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $dest 'Uninstall-Jipeg.ps1') -Silent | Out-Null
    Start-Sleep -Seconds 4              # cmd attend un ping -n 3, soit ~2 s, avant le rd /s
    $vide = Etat-Installe
    if ($vide.Extensions -ne '')   { "  tour $i : extensions restantes -> $($vide.Extensions)"; $fautes++ }
    if ($vide.Dossiers)            { "  tour $i : l'entree Dossier survit"; $fautes++ }
    if ($vide.Programmes)          { "  tour $i : l'entree Programmes survit"; $fautes++ }
    if ($vide.Raccourci)           { "  tour $i : le raccourci survit"; $fautes++ }
    # le CLSID n'est retire que si Jipeg l'avait pose lui-meme, ce qui est
    # voulu : on ne reprend pas un reglage qu'on n'a pas fait
    if ($vide.Dossier)             { "  tour $i : le dossier $dest survit"; $fautes++ }
    Write-Host ('.') -NoNewline
}
Write-Host ''
# on laisse la machine installee
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $src 'Install-Jipeg.ps1') -Silent | Out-Null
''
if ($fautes) { "  $Tours tours, $fautes ecart(s)" } else { "  $Tours tours, aucun ecart : chaque installation pose exactement la meme chose, chaque desinstallation ne laisse rien" }
exit $(if ($fautes) { 1 } else { 0 })
