# Exercises the actual imaging functions without opening windows or installing.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'src\Jipeg-Imaging.ps1')
Add-Type -AssemblyName System.Drawing

function Assert($condition, [string]$message) {
    if (-not $condition) { throw $message }
    Write-Output "PASS: $message"
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ('jipeg-headless-' + [guid]::NewGuid().ToString('N'))
[void][System.IO.Directory]::CreateDirectory($work)
try {
    $source = Join-Path $work 'alpha.png'
    $bmp = New-Object System.Drawing.Bitmap(3, 2)
    $bmp.SetPixel(0, 0, [System.Drawing.Color]::Red)
    $bmp.SetPixel(2, 1, [System.Drawing.Color]::Blue)
    $bmp.Save($source, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Assert (Test-JipegIsPng $source) 'PNG signature recognized'
    Assert (Get-JipegPngFacts $source).Alpha 'Alpha channel recognized'
    $renamed = Join-Path $work 'wrong.jpg'
    [System.IO.File]::Copy($source, $renamed)
    Assert (Test-JipegIsPng $renamed) 'File content wins over extension'
    $broken = Join-Path $work 'broken.png'
    [System.IO.File]::WriteAllBytes($broken, [byte[]](137, 80))
    Assert (-not (Test-JipegIsPng $broken)) 'Truncated signature rejected'

    # Expected location of the original top-left red pixel for all EXIF values.
    $corners = @(@(0,0), @(2,0), @(2,1), @(0,1), @(0,0), @(1,0), @(1,2), @(0,2))
    foreach ($orientation in 1..8) {
        $output = Join-Path $work ("rotation-$orientation.png")
        ConvertTo-JipegPng-Gdi $source $output $orientation
        $result = [System.Drawing.Bitmap]::FromFile($output)
        try {
            $width = $(if ($orientation -le 4) { 3 } else { 2 })
            $height = $(if ($orientation -le 4) { 2 } else { 3 })
            Assert ($result.Width -eq $width -and $result.Height -eq $height) "Orientation $orientation dimensions"
            $corner = $corners[$orientation - 1]
            Assert ($result.GetPixel($corner[0], $corner[1]).ToArgb() -eq [System.Drawing.Color]::Red.ToArgb()) "Orientation $orientation pixel position"
            $clear = 0
            for ($y = 0; $y -lt $height; $y++) {
                for ($x = 0; $x -lt $width; $x++) {
                    if ($result.GetPixel($x, $y).A -eq 0) { $clear++ }
                }
            }
            Assert ($clear -eq 4) "Orientation $orientation transparency"
        } finally { $result.Dispose() }
    }

    # Exercise the shipped codecs, not only header parsing and decoding.
    $photo = Join-Path $work 'photo.bmp'
    $jpeg = Join-Path $work 'photo.jpg'
    $bmp = New-Object System.Drawing.Bitmap(128, 96)
    for ($y = 0; $y -lt 96; $y++) {
        for ($x = 0; $x -lt 128; $x++) {
            $bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($x * 2, $y * 2, 128))
        }
    }
    $bmp.Save($photo, [System.Drawing.Imaging.ImageFormat]::Bmp)
    $bmp.Dispose()
    $originalHash = (Get-FileHash -LiteralPath $photo).Hash
    # Use the same intermediate PNG as the app for BMP input.
    $decoded = Join-Path $work 'photo.png'
    ConvertTo-JipegPng-Gdi $photo $decoded
    $encoded = Invoke-JipegTool (Join-Path $repo 'bin\cjpegli.exe') ('"{0}" "{1}" -q 90' -f $decoded, $jpeg)
    Assert ($encoded.Code -eq 0) 'Bundled jpegli encodes a decoded image'
    Assert ((Get-Item $jpeg).Length -lt (Get-Item $photo).Length) 'Encoded fixture is smaller'
    Assert ((Get-FileHash -LiteralPath $photo).Hash -eq $originalHash) 'Original image is unchanged'
    $image = [System.Drawing.Image]::FromFile($jpeg)
    try { Assert ($image.Width -eq 128 -and $image.Height -eq 96) 'JPEG output can be decoded at original dimensions' }
    finally { $image.Dispose() }

    $optimized = Join-Path $work 'optimized.png'
    [System.IO.File]::Copy($source, $optimized)
    $encoded = Invoke-JipegTool (Join-Path $repo 'bin\oxipng.exe') ('-o 4 --strip safe -q "{0}"' -f $optimized)
    Assert ($encoded.Code -eq 0) 'Bundled oxipng optimizes transparent PNG'
    $before = [System.Drawing.Bitmap]::FromFile($source)
    $after = [System.Drawing.Bitmap]::FromFile($optimized)
    try {
        $identical = $before.Width -eq $after.Width -and $before.Height -eq $after.Height
        for ($y = 0; $y -lt $before.Height; $y++) {
            for ($x = 0; $x -lt $before.Width; $x++) {
                if ($before.GetPixel($x, $y).ToArgb() -ne $after.GetPixel($x, $y).ToArgb()) { $identical = $false }
            }
        }
        Assert $identical 'PNG optimization preserves all RGBA pixels'
    } finally { $before.Dispose(); $after.Dispose() }

    # Run the real installer verification block in isolation: no network/setup.
    $installer = Get-Content -LiteralPath (Join-Path $repo 'install.ps1') -Raw
    $start = $installer.IndexOf('    # Refuse assets without a valid digest')
    $end = $installer.IndexOf("    Say 'Unpacking...'", $start)
    Assert ($start -ge 0 -and $end -gt $start) 'Installer verification block located'
    $verify = [scriptblock]::Create($installer.Substring($start, $end - $start))
    function Say { param($text) }
    $zip = $source
    $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    foreach ($digest in @($null, '', 'md5:123', ('sha256:' + ('0' * 64)), ('sha256:' + $hash.ToLower()))) {
        $asset = [pscustomobject]@{ digest = $digest }
        $accepted = $true
        try { & $verify } catch { $accepted = $false }
        $expected = ($digest -eq ('sha256:' + $hash))
        Assert ($accepted -eq $expected) "Digest validation: '$digest'"
    }
} finally {
    # Only delete the uniquely created directory under the system temp folder.
    $resolved = [System.IO.Path]::GetFullPath($work)
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        [System.IO.Path]::GetFileName($resolved) -notlike 'jipeg-headless-*') {
        throw 'Refusing cleanup outside the test temporary directory.'
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
