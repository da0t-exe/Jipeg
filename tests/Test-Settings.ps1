# Walks the settings that have never been exercised. Everything measured so far
# was measured at quality 90, chroma auto, dark theme, Mica on - which is one
# point out of a grid of several dozen.
#
# Puts the settings back where it found them, whatever happens.
param([switch]$Quick)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Root = Join-Path $env:LOCALAPPDATA 'Jipeg'
. (Join-Path $Root 'Jipeg-Common.ps1')
Add-Type -AssemblyName System.Drawing

$work = Join-Path $env:TEMP ('jipeg-settings-{0}' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $work -Force | Out-Null
$fautes = 0
function Note($ok, $quoi, $detail) {
    if (-not $ok) { $script:fautes++ }
    '  {0}  {1,-34} {2}' -f $(if ($ok) { 'ok  ' } else { 'RATE' }), $quoi, $detail
}

# A photograph, because that is what the quality scale is for, plus a picture of
# flat colour and text, because that is what the chroma setting is for.
function New-Photo($path, $w, $h) {
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $rnd = New-Object Random 11
    for ($y = 0; $y -lt $h; $y++) {
        for ($x = 0; $x -lt $w; $x++) {
            $n = $rnd.Next(-18, 18)
            $bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(
                [math]::Max(0, [math]::Min(255, 120 + [int]($x * 90 / $w) + $n)),
                [math]::Max(0, [math]::Min(255, 100 + [int]($y * 90 / $h) + $n)),
                [math]::Max(0, [math]::Min(255, 160 - [int]($x * 60 / $w) + $n))))
        }
    }
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
}
function New-Flat($path, $w, $h) {
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::White)
    for ($i = 0; $i -lt 6; $i++) {
        $b = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(
            (40 + $i * 35) % 256, (200 - $i * 25) % 256, (90 + $i * 20) % 256))
        $g.FillRectangle($b, 8, 8 + $i * [int]($h / 7), $w - 16, [int]($h / 9)); $b.Dispose()
    }
    $f = New-Object System.Drawing.Font('Segoe UI', 13)
    $g.DrawString('Jipeg Jipeg Jipeg', $f, [System.Drawing.Brushes]::Black, 10, $h - 34)
    $f.Dispose(); $g.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
}

function Convert-One($src) {
    Get-ChildItem -LiteralPath (Split-Path $src -Parent) -Filter '*_jipeg.*' |
        Remove-Item -Force -ErrorAction SilentlyContinue
    $p = Start-Process powershell.exe -PassThru -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-STA', '-File',
        ('"' + (Join-Path $Root 'Jipeg-Convert.ps1') + '"'), ('"' + $src + '"'))
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $p.HasExited -and $sw.Elapsed.TotalSeconds -lt 90) { Start-Sleep -Milliseconds 200 }
    if (-not $p.HasExited) { [void]$p.CloseMainWindow(); Start-Sleep -Seconds 2 }
    if (-not $p.HasExited) { $p.Kill() }
    return (Get-ChildItem -LiteralPath (Split-Path $src -Parent) -Filter '*_jipeg.*' |
            Select-Object -First 1)
}

$avant = Get-JipegSettings
try {
    $s = Get-JipegSettings
    $s.closeWhenDone = $true
    Save-JipegSettings $s

    $photo = Join-Path $work 'photo.png'
    New-Photo $photo 420 300
    $flat = Join-Path $work 'aplats.png'
    New-Flat $flat 420 300

    # ---------------------------------------------------------- 1. quality
    'Les neuf valeurs de qualite, sur la meme photo'
    $valeurs = @(100, 96, 92, 90, 85, 80, 75, 70, 60)
    if ($Quick) { $valeurs = @(100, 90, 60) }
    $tailles = @{}
    foreach ($q in $valeurs) {
        $s = Get-JipegSettings; $s.quality = $q; Save-JipegSettings $s
        $out = Convert-One $photo
        if (-not $out) { Note $false ("qualite $q") 'aucune sortie'; continue }
        $tailles[$q] = $out.Length
        Note $true ("qualite $q") ('{0:N0} octets, {1}' -f $out.Length, $out.Extension)
    }
    # Une echelle de qualite qui ne se traduit pas par des tailles croissantes
    # ne veut rien dire : c'est la seule chose qu'on puisse verifier sans oeil.
    $ordonnees = $true
    $tries = $valeurs | Where-Object { $tailles.ContainsKey($_) } | Sort-Object
    for ($i = 1; $i -lt $tries.Count; $i++) {
        if ($tailles[$tries[$i]] -lt $tailles[$tries[$i - 1]]) { $ordonnees = $false }
    }
    Note $ordonnees 'la taille suit la qualite' (
        ($tries | ForEach-Object { '{0}:{1:N0}' -f $_, $tailles[$_] }) -join '  ')

    # ---------------------------------------------------------- 2. chroma
    ''
    'Les trois modes de couleur, sur des aplats et sur une photo'
    $s = Get-JipegSettings; $s.quality = 90; Save-JipegSettings $s
    $chroma = @{}
    foreach ($mode in 'auto', 'always', 'never') {
        $s = Get-JipegSettings; $s.chroma = $mode; Save-JipegSettings $s
        $a = Convert-One $flat
        $b = Convert-One $photo
        $chroma[$mode] = @{ Flat = $(if ($a) { $a.Length } else { 0 }); Photo = $(if ($b) { $b.Length } else { 0 }) }
        Note ($null -ne $b) "chroma $mode" (
            'aplats {0:N0}  photo {1:N0}' -f $chroma[$mode].Flat, $chroma[$mode].Photo)
    }
    # 4:4:4 coute de la place : force partout, la photo doit grossir par rapport
    # a 4:2:0. Si les deux sont identiques, le reglage n'a servi a rien.
    Note ($chroma['always'].Photo -gt $chroma['never'].Photo) 'always coute plus cher que never' (
        '{0:N0} contre {1:N0}' -f $chroma['always'].Photo, $chroma['never'].Photo)

    # ---------------------------------------------------------- 3. l'apparence
    ''
    'Le theme clair et Mica, dans les deux fenetres'
    $s = Get-JipegSettings; $s.chroma = 'auto'; Save-JipegSettings $s
    foreach ($theme in 'light', 'dark') {
        foreach ($mica in $true, $false) {
            $s = Get-JipegSettings; $s.theme = $theme; $s.mica = $mica; Save-JipegSettings $s
            $out = Convert-One $photo
            Note ($null -ne $out) ("theme $theme, mica $mica") $(
                if ($out) { '{0:N0} octets' -f $out.Length } else { 'aucune sortie' })
        }
    }
} finally {
    Save-JipegSettings $avant
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    ''
    '  (les reglages ont ete remis comme ils etaient)'
}
''
if ($fautes) { "  $fautes ecart(s)" } else { '  tous les reglages se comportent' }
exit $(if ($fautes) { 1 } else { 0 })
