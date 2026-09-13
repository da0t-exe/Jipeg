# Imaging helpers: no window creation, queue or installation side effects.
# Pixel analysis and WebP detection use helpers from Jipeg-Common.ps1.
# WebP decoding expects $Dwebp and $Webpmux to point to the bundled tools.

function Get-JipegTraits([string]$path) {
    $img = $null; $bmp = $null
    try {
        $img = [System.Drawing.Image]::FromFile($path)
        $bmp = New-Object System.Drawing.Bitmap($img)
        $edges = [Jipeg.Pixels]::ChromaEdges($bmp, 4, 40)
        $hard  = [double]$edges[0]
        $total = [double]$edges[1]
        $ratio = $(if ($total -gt 0) { $hard / $total } else { 0.0 })
        # Measured across the test set: photographs scored exactly zero hard
        # chroma transitions, a photograph with a line of coloured text over it
        # 0.10%, a diagram 0.56%, a 64-pixel icon 2.98% and a screenshot 3.48%.
        # 0.05% sits in the gap with room on both sides. An absolute count was
        # tried alongside it and dropped: it fired on a perfectly ordinary
        # photograph and cost 10% of the file for nothing. The bias is still
        # deliberate - guessing 4:4:4 for a photograph costs about 18% of the
        # file, guessing 4:2:0 for text costs fringing that cannot be undone.
        return @{
            Pixels     = ([double]$bmp.Width * [double]$bmp.Height)
            Grey       = [Jipeg.Pixels]::IsGrey($bmp, 4, 2)
            HardChroma = ($ratio -gt 0.0005)
        }
    } catch {
        return @{ Pixels = 0.0; Grey = $false; HardChroma = $true }
    } finally {
        if ($bmp) { $bmp.Dispose() }
        if ($img) { $img.Dispose() }
    }
}

# GDI+ writes an indexed PNG as a palette image, which cjpegli would expand back
# to three channels, so the single-channel PNG is written through Windows own
# imaging instead - that one produces a real greyscale PNG.
function ConvertTo-JipegGreyPng([string]$src, [string]$dst) {
    Add-Type -AssemblyName PresentationCore
    $uri = New-Object System.Uri($src)
    $dec = [System.Windows.Media.Imaging.BitmapDecoder]::Create($uri,
        [System.Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,
        [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
    $grey = New-Object System.Windows.Media.Imaging.FormatConvertedBitmap(
        $dec.Frames[0], [System.Windows.Media.PixelFormats]::Gray8, $null, 0.0)
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($grey))
    $out = [System.IO.File]::Create($dst)
    try { $enc.Save($out) } finally { $out.Close() }
}

# Exif orientation, turned into the rotation GDI+ understands. The tag is not
# copied to the result - it is applied to the pixels and then forgotten, which
# leaves the picture upright everywhere and adds not one byte.
function Get-JipegRotateFlip([int]$orientation) {
    switch ($orientation) {
        2 { return 'RotateNoneFlipX' }
        3 { return 'Rotate180FlipNone' }
        4 { return 'RotateNoneFlipY' }
        5 { return 'Rotate90FlipX' }
        6 { return 'Rotate90FlipNone' }
        7 { return 'Rotate270FlipX' }
        8 { return 'Rotate270FlipNone' }
        default { return $null }
    }
}

# Decode to PNG while preserving transparency and applying orientation.
# Draw at the original pixel dimensions, independently of the stored DPI.
function ConvertTo-JipegPng-Gdi([string]$src, [string]$dst, [int]$orientation = 1) {
    $fs = [System.IO.File]::OpenRead($src)
    try {
        $img = [System.Drawing.Image]::FromStream($fs, $true, $false)
        try {
            $flip = Get-JipegRotateFlip $orientation
            if ($flip) { $img.RotateFlip($flip) }
            # Transparency is carried through instead of being painted over.
            # This cleared to white whatever came in, which is how a see-through
            # WebP, GIF or TIFF reached the encoder already stuck on a white
            # square. What to do about the transparency is decided further on -
            # the decoder's one job here is not to destroy it.
            #
            # An indexed image needs its palette read: GDI reports
            # Format8bppIndexed for a transparent GIF and answers False to both
            # IsAlphaPixelFormat and the HasAlpha flag, so the transparent
            # entry only shows up in the palette itself.
            $keep = [System.Drawing.Image]::IsAlphaPixelFormat($img.PixelFormat)
            if (-not $keep -and $img.Palette -and $img.Palette.Entries.Count -gt 0) {
                foreach ($entry in $img.Palette.Entries) {
                    if ($entry.A -lt 255) { $keep = $true; break }
                }
            }
            $format = [System.Drawing.Imaging.PixelFormat]::Format24bppRgb
            if ($keep) { $format = [System.Drawing.Imaging.PixelFormat]::Format32bppArgb }
            $bmp = New-Object System.Drawing.Bitmap($img.Width, $img.Height, $format)
            try {
                $g = [System.Drawing.Graphics]::FromImage($bmp)
                if ($keep) { $g.Clear([System.Drawing.Color]::Transparent) }
                else       { $g.Clear([System.Drawing.Color]::White) }
                $g.PixelOffsetMode   = 'Half'
                $g.InterpolationMode = 'NearestNeighbor'
                $g.DrawImage($img, (New-Object System.Drawing.Rectangle(0, 0, $img.Width, $img.Height)))
                $g.Dispose()
                $bmp.Save($dst, [System.Drawing.Imaging.ImageFormat]::Png)
            } finally { $bmp.Dispose() }
        } finally { $img.Dispose() }
    } finally { $fs.Close() }
}

# Read from the PNG header rather than by decoding the file: whether it carries
# transparency, and whether it is animated. Colour types 4 and 6 hold an alpha
# channel; a palette image (3) is transparent only if a tRNS chunk appears
# before the pixel data; an APNG is one with an acTL chunk, and it usually calls
# itself .png, so the extension says nothing. Both send the file the long way
# round - cjpegli lays transparency on black, and fails outright on animation.
# The eight bytes every PNG starts with. Nothing else in here may trust the
# extension: a JPEG saved as .png reads as a PNG to every check that looks at
# byte 25 and up, and the one that mattered handed it to oxipng, which refused
# it and reported the encoder as the culprit.
function Test-JipegIsPng([string]$path) {
    $fs = $null
    try {
        $fs = [System.IO.File]::OpenRead($path)
        $sig = New-Object byte[] 8
        if ($fs.Read($sig, 0, 8) -lt 8) { return $false }
        $want = [byte[]](137, 80, 78, 71, 13, 10, 26, 10)
        for ($i = 0; $i -lt 8; $i++) { if ($sig[$i] -ne $want[$i]) { return $false } }
        return $true
    } catch { return $false } finally { if ($fs) { $fs.Dispose() } }
}

# Transparency alone, which is a different question from whether the file needs
# decoding: an animated PNG needs the long way round but has nothing to do with
# alpha, and sending one down the PNG-shrinking path would be answering the
# wrong question.
# Both facts come out of the same handful of bytes, so they are read together.
# They used to be two nearly identical functions, which meant opening the file
# and walking it twice to learn things that sit next to each other.
function Get-JipegPngFacts([string]$path) {
    $facts = @{ Alpha = $false; Animated = $false }
    if (-not (Test-JipegIsPng $path)) { return $facts }
    $fs = $null
    try {
        $fs = [System.IO.File]::OpenRead($path)
        $head = New-Object byte[] 26
        if ($fs.Read($head, 0, 26) -lt 26) { $facts.Alpha = $true; return $facts }
        $facts.Alpha = ([int]$head[25] -eq 4 -or [int]$head[25] -eq 6)
        # 8 signature bytes, then IHDR: 4 length + 4 name + 13 data + 4 CRC.
        # Reading 26 bytes to reach the colour type leaves the cursor inside
        # IHDR's data, so the chunk walk has to be put back on the boundary.
        $fs.Position = 33
        $br = New-Object System.IO.BinaryReader($fs)
        while ($fs.Position -lt $fs.Length) {
            $len = ([int]$br.ReadByte() -shl 24) -bor ([int]$br.ReadByte() -shl 16) -bor
                   ([int]$br.ReadByte() -shl 8)  -bor  [int]$br.ReadByte()
            $name = [System.Text.Encoding]::ASCII.GetString($br.ReadBytes(4))
            if ($name -eq 'acTL') { $facts.Animated = $true }   # animated
            if ($name -eq 'tRNS') { $facts.Alpha = $true }      # palette transparency
            if ($name -eq 'IDAT') { return $facts }             # the header is over
            [void]$br.ReadBytes($len + 4)                       # data plus its CRC
        }
    } catch { } finally { if ($fs) { $fs.Dispose() } }
    # Only IDAT settles this for certain. Anything else - a truncated file, a
    # length field pointing past the end, a read that throws - leaves the
    # question open, and the two ways of being wrong do not cost the same:
    # guessing "opaque" sends a transparent image down the JPEG path and
    # flattens it for good, while guessing "transparent" costs a few kilobytes.
    $facts.Alpha = $true
    return $facts
}

# These run on the window's own thread, so an external tool that never returns
# would freeze the whole window - no repainting, no Cancel button, nothing. The
# wait is bounded and the process killed if it overruns. The wait comes before
# the reads on purpose: reading a pipe to the end blocks just as hard, and if
# the child ever filled its output buffer the two would deadlock. Thirty seconds
# is far beyond what these need - decoding was measured at 25 milliseconds.
function Invoke-JipegTool([string]$exe, [string]$arguments, [int]$timeoutMs = 30000) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $exe
    $psi.Arguments              = $arguments
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.RedirectStandardError  = $true
    $psi.RedirectStandardOutput = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $timedOut = $false
    if (-not $p.WaitForExit($timeoutMs)) {
        $timedOut = $true
        try { $p.Kill() } catch { }
        try { [void]$p.WaitForExit(2000) } catch { }
    }
    $err = ''
    try { $err = $p.StandardError.ReadToEnd(); [void]$p.StandardOutput.ReadToEnd() } catch { }
    $code = 1
    try { $code = $p.ExitCode } catch { }
    $p.Dispose()
    if ($timedOut) {
        return @{ Code = 1; Error = ('gave up after {0} seconds' -f ($timeoutMs / 1000)) }
    }
    return @{ Code = $code; Error = $err.Trim() }
}

function ConvertTo-JipegPng-Webp([string]$src, [string]$dst) {
    if (-not (Test-Path -LiteralPath $Dwebp)) {
        throw "WebP needs bin\dwebp.exe. Run the Jipeg installer again."
    }
    # dwebp decodes a still WebP and nothing else: handed an animation it fails
    # outright, which is why every animated WebP used to come back as a failure
    # with no explanation. webpmux lifts the first frame out as a still one.
    $still = $null
    if ((Get-JipegWebpKind $src) -eq 'animated') {
        if (-not (Test-Path -LiteralPath $Webpmux)) {
            throw "Animated WebP needs bin\webpmux.exe. Run the Jipeg installer again."
        }
        $still = Join-Path $env:TEMP ('jipeg-f1-{0}.webp' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
        $r = Invoke-JipegTool $Webpmux ('-get frame 1 "{0}" -o "{1}"' -f $src, $still)
        if ($r.Code -ne 0 -or -not (Test-Path -LiteralPath $still)) {
            Remove-Item -LiteralPath $still -Force -ErrorAction SilentlyContinue
            throw ("The animated WebP could not be read: " + $r.Error)
        }
        $src = $still
    }
    $r = Invoke-JipegTool $Dwebp ('"{0}" -o "{1}"' -f $src, $dst)
    if ($still) { Remove-Item -LiteralPath $still -Force -ErrorAction SilentlyContinue }
    if ($r.Code -ne 0 -or -not (Test-Path -LiteralPath $dst)) {
        throw ("WebP could not be read: " + $r.Error)
    }
}

# Windows' own imaging layer. It reads HEIC, AVIF and JPEG XR only when the
# matching codec is installed, so the failure is named rather than left as a
# bare count: the fix is a free download and the user should hear which one.
function ConvertTo-JipegPng-Wic([string]$src, [string]$dst, [string]$ext) {
    # loaded here, not at startup: it is a heavy assembly and most conversions
    # never come near it
    Add-Type -AssemblyName PresentationCore
    try {
        $uri = New-Object System.Uri($src)
        $dec = [System.Windows.Media.Imaging.BitmapDecoder]::Create($uri,
            [System.Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,
            [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
    } catch {
        $need = switch ($ext) {
            '.heic' { 'HEIF Image Extensions' }
            '.heif' { 'HEIF Image Extensions' }
            '.avif' { 'AV1 Video Extension' }
            default { 'the matching extension' }
        }
        # kept short on purpose: it is shown in a 398 px label, and the longer
        # wording measured 478 px and was cut off mid-sentence
        throw ("No {0} codec on this PC. Install {1} from the Store." -f $ext, $need)
    }
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($dec.Frames[0]))
    $out = [System.IO.File]::Create($dst)
    try { $enc.Save($out) } finally { $out.Close() }
}

