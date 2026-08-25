<#
  Jipeg — converts images to JPEG using Google's jpegli encoder.
  Started from the Explorer context menu. No settings here: just a progress
  window that follows the Windows theme, then the result.
#>
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Paths)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $Root 'Jipeg-Common.ps1')
[System.Windows.Forms.Application]::EnableVisualStyles()

$Cjpegli  = Join-Path $Root 'bin\cjpegli.exe'
$Settings = Get-JipegSettings
$L        = Import-JipegLang $Settings.language
$Theme    = Get-JipegTheme $Settings.theme
$Suffix   = '_jipeg'

$NativeExt = @('.png', '.jpg', '.jpeg', '.jpe', '.jxl',
               '.ppm', '.pnm', '.pgm', '.pam', '.pfm', '.pgx')
# GIF and APNG are in this list, not the one above, even though cjpegli claims
# to read them: it does read them, then fails at the encode step. Measured on a
# plain 100x100 static GIF and on a two-frame APNG, both answered "jpegli
# encoding failed" with exit code 1 - every GIF Jipeg was offered had been
# failing silently. Handed over as PNG, both convert.
$GdiExt    = @('.bmp', '.tif', '.tiff', '.ico', '.emf', '.wmf', '.gif', '.apng')
# WebP comes with its own decoder, because nothing already on the machine reads
# it: cjpegli refuses it, GDI+ has never known it, and Windows only decodes it
# if someone installed the Store extension - measured on a clean Windows 11,
# WIC answers "no imaging component suitable".
$WebpExt   = @('.webp')
# These are handed to Windows itself. It decodes them when the matching codec is
# present - HEIF Image Extensions for HEIC, AV1 Video Extension for AVIF - and
# says so plainly when it is not, rather than failing without a reason.
$WicExt    = @('.heic', '.heif', '.avif', '.jxr', '.wdp', '.hdp')
$AllExt    = $NativeExt + $GdiExt + $WebpExt + $WicExt
$Dwebp     = Join-Path $Root 'bin\dwebp.exe'
$Webpmux   = Join-Path $Root 'bin\webpmux.exe'
$Oxipng    = Join-Path $Root 'bin\oxipng.exe'

# ------------------------------------------------------------------- inputs
function Expand-Inputs([string[]]$in) {
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($p in @($in)) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $p = $p.Trim('"')
        try {
            if (Test-Path -LiteralPath $p -PathType Container) {
                Get-ChildItem -LiteralPath $p -File |
                    Where-Object { $AllExt -contains $_.Extension.ToLower() } |
                    ForEach-Object { $out.Add($_.FullName) }
            } elseif (Test-Path -LiteralPath $p -PathType Leaf) {
                if ($AllExt -contains ([System.IO.Path]::GetExtension($p).ToLower())) {
                    $out.Add((Resolve-Path -LiteralPath $p).Path)
                }
            }
        } catch { }
    }
    return $out
}

# -------------------------------------------------------- multiple selection
# Explorer starts one process per selected file. The first one keeps a lock for
# its whole life; the others drop their paths into a shared queue and quit. The
# live instance picks them up, even after the batch has finished.
$QueueFile = Join-Path $env:TEMP 'jipeg.queue'
$LockFile  = Join-Path $env:TEMP 'jipeg.lock'
$Mutex     = New-Object System.Threading.Mutex($false, 'Local\JipegQueue')
$script:LockFs = $null
$Files = New-Object System.Collections.Generic.List[string]

function Open-Lock {
    try { return [System.IO.File]::Open($LockFile, 'CreateNew', 'Write', 'None') } catch { }
    try { return [System.IO.File]::Open($LockFile, 'Open', 'Write', 'None') } catch { }   # stale lock
    return $null
}
function Read-Queue {
    $res = New-Object System.Collections.Generic.List[string]
    [void]$Mutex.WaitOne()
    try {
        if (Test-Path -LiteralPath $QueueFile) {
            $limit = [DateTime]::UtcNow.AddSeconds(-20).Ticks
            foreach ($line in @(Get-Content -LiteralPath $QueueFile -ErrorAction SilentlyContinue)) {
                $i = $line.IndexOf('|')
                if ($i -lt 1) { continue }
                if ([int64]$line.Substring(0, $i) -lt $limit) { continue }
                $res.Add($line.Substring($i + 1))
            }
            Remove-Item -LiteralPath $QueueFile -Force -ErrorAction SilentlyContinue
        }
    } finally { $Mutex.ReleaseMutex() }
    return $res
}

if (-not $Paths -or $Paths.Count -eq 0) { exit }

[void]$Mutex.WaitOne()
try {
    $stamp = [DateTime]::UtcNow.Ticks
    $lines = Expand-Inputs $Paths | ForEach-Object { "$stamp|$_" }
    if ($lines) { Add-Content -LiteralPath $QueueFile -Value $lines -Encoding UTF8 }
    $script:LockFs = Open-Lock
} finally { $Mutex.ReleaseMutex() }

if (-not $script:LockFs) { exit }          # a conversion is already running, it will take over

# No waiting before the window appears. Whatever is in the queue right now goes
# in; the rest of the selection is picked up by the watcher while the window is
# already on screen, and the engine holds off for a moment so the count settles.
foreach ($f in @(Read-Queue)) { if ($Files -notcontains $f) { $Files.Add($f) } }

if (-not (Test-Path -LiteralPath $Cjpegli)) {
    [void][System.Windows.Forms.MessageBox]::Show(
        ('{0}{1}{2}{1}{1}{3}' -f $L.cvNoEncoder, [Environment]::NewLine, $Cjpegli, $L.cvReinstall),
        'Jipeg', 'OK', 'Error')
    exit 1
}

# -------------------------------------------------------------------- tools
function Get-FreePath([string]$dir, [string]$base, [string]$ext) {
    $p = Join-Path $dir ($base + $ext)
    $i = 1
    while (Test-Path -LiteralPath $p) { $p = Join-Path $dir ('{0} ({1}){2}' -f $base, $i, $ext); $i++ }
    return $p
}

# ------------------------------------------------------------------- window
$Mica = ($Settings.mica -and (Test-JipegMica $Theme))
# never black: DWM composites a child control opaquely, so black in the corners
# outside a rounded shape stays black instead of turning to glass
$Backdrop = $Theme.Back

$form = New-Object System.Windows.Forms.Form
$form.Text            = 'Jipeg'
$form.FormBorderStyle = 'FixedDialog'
$form.StartPosition   = 'CenterScreen'
$form.ClientSize      = New-Object System.Drawing.Size(430, 150)
# WinForms is told to keep its hands off: everything below is in design units
# and Set-JipegScaleForm applies the one factor just before the window is shown.
$form.AutoScaleMode   = 'None'
$form.MaximizeBox     = $false
$form.MinimizeBox     = $false
$form.ShowInTaskbar   = $true
$form.ForeColor       = $Theme.Text
$form.Font            = $JipegFont
if ($Mica) { $form.BackColor = [System.Drawing.Color]::Black } else { $form.BackColor = $Theme.Back }
Set-JipegDoubleBuffer $form
Set-JipegIcon $form $Root
$form.Add_HandleCreated({
    Set-JipegChrome $form $Theme
    if ($Mica) { [void](Set-JipegMica $form $Theme) }
})

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.SetBounds(16, 16, 398, 24)
$lblTitle.Font = $JipegFontSection
$lblTitle.ForeColor = $Theme.Text
$lblTitle.Text = $L.cvReady
Set-JipegLabel $lblTitle $Theme $Mica
$form.Controls.Add($lblTitle)

$lblFile = New-Object System.Windows.Forms.Label
$lblFile.SetBounds(16, 44, 398, 18)
$lblFile.Font = $JipegFontHint
$lblFile.ForeColor = $Theme.Muted
$lblFile.AutoEllipsis = $true
Set-JipegLabel $lblFile $Theme $Mica
$form.Controls.Add($lblFile)

# The native ProgressBar animates its own fill, cannot be recoloured reliably
# and has a white trough in dark mode, so the bar is drawn here: one flat accent
# colour, rounded ends, and it glides to each new value instead of jumping.
$script:BarShown  = 0.0
$script:BarMuted  = $false
$script:BarTarget = 0.0
$bar = New-Object System.Windows.Forms.Panel
$bar.SetBounds(16, 76, 398, 10)
$bar.BackColor = $form.BackColor
Set-JipegDoubleBuffer $bar
$bar.Add_Paint({
    $g = $_.Graphics
    $w = $this.Width; $h = $this.Height
    # Track and fill are mirrored separately. Passing the whole bar through
    # Copy-JipegCorners would fold the fill back onto the right-hand side, since
    # a half-filled bar is not symmetric - but each rounded end on its own is.
    $buf = New-Object System.Drawing.Bitmap($w, $h)
    $bg = [System.Drawing.Graphics]::FromImage($buf)
    $bg.Clear($this.BackColor)
    $bg.SmoothingMode = 'AntiAlias'
    $track = New-JipegRoundPath 0 0 ($w - 1) ($h - 1) ($h / 2)
    $tb = New-Object System.Drawing.SolidBrush($Theme.Track)
    $bg.FillPath($tb, $track); $tb.Dispose(); $track.Dispose(); $bg.Dispose()
    Copy-JipegCorners $buf
    $g.DrawImageUnscaled($buf, 0, 0)
    $buf.Dispose()

    $fw = [int][math]::Round([double]$w * $script:BarShown)
    if ($fw -ge 2) {
        # grey rather than the accent colour when the batch ended without a
        # single conversion: a full bar in the accent reads as success, and it
        # sat directly under the words "0 images converted, 1 failure"
        $ink = $(if ($script:BarMuted) { $Theme.Muted } else { $Theme.Accent })
        $fbuf = New-Object System.Drawing.Bitmap($fw, $h)
        $fg = [System.Drawing.Graphics]::FromImage($fbuf)
        $fg.Clear($Theme.Track)
        $fg.SmoothingMode = 'AntiAlias'
        $fill = New-JipegRoundPath 0 0 ($fw - 1) ($h - 1) ($h / 2)
        $fb = New-Object System.Drawing.SolidBrush($ink)
        $fg.FillPath($fb, $fill); $fb.Dispose(); $fill.Dispose(); $fg.Dispose()
        Copy-JipegCorners $fbuf
        $g.DrawImageUnscaled($fbuf, 0, 0)
        $fbuf.Dispose()
    }
})
$form.Controls.Add($bar)

# The saving is the point of the window, so it gets the largest type on screen.
$lblPercent = New-Object System.Windows.Forms.Label
$lblPercent.SetBounds(16, 104, 92, 28)
$lblPercent.Font = $JipegFontBig
$lblPercent.ForeColor = $Theme.Accent
Set-JipegLabel $lblPercent $Theme $Mica
$form.Controls.Add($lblPercent)

$lblSizes = New-Object System.Windows.Forms.Label
$lblSizes.SetBounds(112, 109, 190, 18)
$lblSizes.Font = $JipegFontHint
$lblSizes.ForeColor = $Theme.Muted
Set-JipegLabel $lblSizes $Theme $Mica
$form.Controls.Add($lblSizes)

$btn = New-Object System.Windows.Forms.Button
$btn.SetBounds(430 - 16 - 100, 102, 100, 32)
$btn.Text = $L.btnCancel
Set-JipegButton $btn $Theme $Backdrop
$form.Controls.Add($btn)
$form.CancelButton = $btn

# ------------------------------------------------------------------- engine
$script:Index     = 0
$script:Done      = 0
$script:Failed    = 0
$script:Reason    = ''
$script:Reasons   = New-Object System.Collections.Generic.List[string]
$script:ProcStarted = Get-Date

# Every distinct reason is kept, not just the first: a batch can fail for two
# different causes at once - one file with no HEIC codec, one corrupt - and
# showing only the earlier of them sent the other into thin air. All of them go
# to the log; the window shows the first and counts the rest.
# The English table, fetched once and only if something actually goes wrong.
function Get-JipegEnglish {
    if (-not $script:EnLang) { $script:EnLang = Import-JipegLang 'en' }
    return $script:EnLang
}

# The window speaks the user's language; the log stays in English. It is there
# to be read by whoever is working out what went wrong, and that reader should
# not have to work out which of ten languages the machine was set to first - a
# German "der Encoder hat es abgelehnt" turned up in a log during testing and
# made the point.
function Add-JipegReason([string]$why, [string]$logged) {
    if (-not $why) { return }
    if (-not $script:Reasons.Contains($why)) { $script:Reasons.Add($why) }
    if (-not $script:Reason) { $script:Reason = $why }
    if (-not $logged) { $logged = $why }
    Write-JipegLog ('failed   ' + $logged)
}
$script:Grey      = $false
$script:Kept      = 0
$script:Mode      = 'jpeg'   # jpeg | png
$script:ForcePng  = $false
$script:TotalIn   = 0
$script:TotalOut  = 0
$script:Cancelled = $false
$script:Finished  = $false
$script:Started   = $false
$script:Proc      = $null
$script:TmpIn     = $null
$script:TmpOut    = $null
$script:Current   = $null

function Set-Bar([double]$fraction) {
    if ($fraction -lt 0) { $fraction = 0.0 }
    if ($fraction -gt 1) { $fraction = 1.0 }
    $script:BarTarget = $fraction
    $glide.Start()
}

function Set-Status {
    $n = $Files.Count
    if ($n -eq 1) { $lblTitle.Text = $L.cvOne }
    else          { $lblTitle.Text = $L.cvMany -f $script:Index, $n }
    if ($n -gt 0) { Set-Bar ($script:Index / [double]$n) } else { Set-Bar 0 }
}

# --------------------------------------------------------------- decoding
# Squeezes a PNG without touching a single pixel: the deflate stream is
# rebuilt, the filters are picked per row, the colour type and bit depth are
# reduced where the image allows it, and the chunks that carry nothing anyone
# looks at are dropped. Measured on the test set: -14% on a photograph, -29% on
# a screenshot, -44% on an icon, -57% on a diagram, -78% on a palette image,
# and the pixels and the alpha channel come back byte for byte identical.
#
# -o 4 rather than max: on a screenshot both reach -29.4%, but max takes 0.59 s
# against 0.38 s, and on a transparent image it buys 0.3% for another 0.36 s.
# --strip safe drops metadata but keeps the chunks that decide how the colours
# are read, which is the whole point of not losing anything.
# Whether the picture is grey even though it is stored in colour - a scanned
# page, a diagram, a black and white photograph exported as RGB. Encoding those
# as one channel instead of three takes about 8% off the result, measured, and
# costs nothing in quality because the colour was never there.
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

# JPEG has no transparency, so something has to be put behind it. cjpegli uses
# black, which turned a logo on a transparent background into a logo on a black
# square; every other tool in the world uses white. Anything carrying alpha is
# flattened onto white here first. The image is drawn into a rectangle its own
# size rather than with DrawImageUnscaled, which would rescale it whenever the
# file carries a DPI different from the screen's.
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

function Start-Next {
    if ($script:Cancelled -or $script:Index -ge $Files.Count) { Complete-Batch; return }
    $src = $Files[$script:Index]
    $script:Current = $src
    $lblFile.Text = [System.IO.Path]::GetFileName($src)
    Set-Status
    try {
        $ext = [System.IO.Path]::GetExtension($src).ToLower()
        $source = $src
        $script:TmpIn = $null

        # A PNG that has transparent pixels never becomes a JPEG. JPEG has no
        # alpha channel at all, so the only way to make one is to paint
        # something behind the picture - which is a loss the file never asked
        # for, and a logo meant to sit on any background comes back stuck on a
        # white square. It is shrunk as a PNG instead, losslessly, and stays
        # readable on everything that reads PNG, which is everything.
        $png = Get-JipegPngFacts $src
        $script:Mode = 'jpeg'
        if (($script:ForcePng -or $png.Alpha) -and (Test-JipegIsPng $src)) {
            $script:Mode = 'png'
        }
        if ($script:Mode -eq 'png') {
            $script:TmpOut = Join-Path (Split-Path -Parent $src) ('.jipeg-{0}.png' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
            Copy-Item -LiteralPath $src -Destination $script:TmpOut -Force
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName               = $Oxipng
            $psi.Arguments              = '-o 4 --strip safe -q "{0}"' -f $script:TmpOut
            $psi.UseShellExecute        = $false
            $psi.CreateNoWindow         = $true
            $psi.RedirectStandardError  = $true
            $psi.RedirectStandardOutput = $true
            $script:Proc = [System.Diagnostics.Process]::Start($psi)
            $script:ProcStarted = Get-Date
            return
        }
        # a PNG only needs the detour if it is transparent or animated; a JPEG
        # needs it if it asks to be shown rotated
        $awkward = ($ext -eq '.png' -and ($png.Alpha -or $png.Animated))
        $orient  = Get-JipegOrientation $src
        # A four-component JPEG is CMYK or YCCK. cjpegli will not touch one, so
        # Windows decodes it instead - both GDI+ and WIC read them without
        # complaint, and until now every one of them came back as a bare
        # failure with "Failed to decode input image" behind it.
        $frame = Get-JipegJpegFrame $src
        $cmyk  = ($null -ne $frame -and [int]$frame.Components -ge 4)
        if ($GdiExt -contains $ext -or $WebpExt -contains $ext -or
            $WicExt -contains $ext -or $awkward -or $orient -ne 1 -or $cmyk) {
            # cjpegli reads none of these: decode to PNG first, by whichever
            # route knows the format, and hand it that instead
            $tmpPng = Join-Path $env:TEMP ('jipeg-in-{0}.png' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
            if ($WebpExt -contains $ext -or $WicExt -contains $ext) {
                $raw = Join-Path $env:TEMP ('jipeg-raw-{0}.png' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
                if ($WebpExt -contains $ext) { ConvertTo-JipegPng-Webp $src $raw }
                else                         { ConvertTo-JipegPng-Wic  $src $raw $ext }
                # Only an animated file still needs GDI, to pick the first
                # frame out of it. Transparency alone does not, and sending it
                # through here is what used to flatten it.
                if ((Get-JipegPngFacts $raw).Animated) { ConvertTo-JipegPng-Gdi $raw $tmpPng }
                else { Move-Item -LiteralPath $raw -Destination $tmpPng -Force }
                Remove-Item -LiteralPath $raw -Force -ErrorAction SilentlyContinue
            } else {
                ConvertTo-JipegPng-Gdi $src $tmpPng $orient
            }
            $source = $tmpPng; $script:TmpIn = $tmpPng
        }

        # The rule above - transparency is never flattened - was written for
        # PNG sources and only ever checked those. Every other format that can
        # carry an alpha channel walked straight past it: measured on a 900x700
        # lossless WebP, 351,403 transparent pixels went in and none came out,
        # the picture arriving on a white square. The question is asked again
        # here, of whatever the decoders produced, so the answer no longer
        # depends on which door the file came in through.
        if ($script:TmpIn -and (Test-JipegTransparentPixels $source)) {
            $script:Mode = 'png'
            $script:TmpOut = Join-Path (Split-Path -Parent $src) ('.jipeg-{0}.png' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
            Copy-Item -LiteralPath $source -Destination $script:TmpOut -Force
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName               = $Oxipng
            $psi.Arguments              = '-o 4 --strip safe -q "{0}"' -f $script:TmpOut
            $psi.UseShellExecute        = $false
            $psi.CreateNoWindow         = $true
            $psi.RedirectStandardError  = $true
            $psi.RedirectStandardOutput = $true
            $script:Proc = [System.Diagnostics.Process]::Start($psi)
            $script:ProcStarted = Get-Date
            return
        }

        # One decode answers both questions: is the picture grey, and does it
        # hold the kind of hard colour edges that 4:2:0 would smear. Judged on
        # whatever is about to be encoded, so a rotated or flattened image is
        # measured on what it became rather than on what it was.
        $traits = Get-JipegTraits $source
        $script:Grey = $false
        if ($traits.Grey) {
            $greyPng = Join-Path $env:TEMP ('jipeg-g-{0}.png' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
            try {
                ConvertTo-JipegGreyPng $source $greyPng
                if ($script:TmpIn) { Remove-Item -LiteralPath $script:TmpIn -Force -ErrorAction SilentlyContinue }
                $source = $greyPng
                $script:TmpIn = $greyPng
                $script:Grey = $true
            } catch {
                Remove-Item -LiteralPath $greyPng -Force -ErrorAction SilentlyContinue
            }
        }
        $dir = Split-Path -Parent $src
        $script:TmpOut = Join-Path $dir ('.jipeg-{0}.tmp' -f [guid]::NewGuid().ToString('N').Substring(0, 8))

        # The quality goes onto a command line, so it is written as a plain
        # integer rather than through the machine's number format: a decimal
        # separator picked up from a French or German Windows would reach
        # cjpegli as "90,5" and be refused.
        $cmdArgs = '"{0}" "{1}" -q {2}' -f $source, $script:TmpOut, ([int]$Settings.quality)
        # 'auto' used to answer "yes, full colour" for anything that was not a
        # JPEG, which meant every PNG, every screenshot and every WebP was
        # encoded 4:4:4 - the most expensive setting there is, measured at 14 to
        # 23% more than 4:2:0 on the same picture, and pure waste on a
        # photograph. It now asks two questions instead. Does the content need
        # it: only pictures with hard colour edges, text and flat colour, do.
        # And can the source even have it: a JPEG says so in its frame header,
        # and a lossy WebP is 4:2:0 inside whatever it looks like.
        $full = switch ([string]$Settings.chroma) {
            'always' { $true }
            'never'  { $false }
            default  {
                $sourceHasIt = $true
                if ($WebpExt -contains $ext) {
                    $sourceHasIt = ((Get-JipegWebpKind $src) -ne 'lossy')
                } elseif ('.jpg', '.jpeg', '.jpe', '.jfif' -contains $ext) {
                    $sourceHasIt = Test-JipegSourceFullChroma $src
                }
                ($traits.HardChroma -and $sourceHasIt)
            }
        }
        # Both branches say it out loud. cjpegli defaults to 4:4:4, so the old
        # code - which passed the flag only to ask for 4:4:4 - produced the same
        # image either way, and the setting did nothing in either position.
        # How the scan data is laid out in the file. It changes nothing about the
        # picture - decoded, -p 0, -p 1 and -p 2 give bit-identical pixels, and
        # ssimulacra2 returns the same score to eight decimal places - but it
        # changes the size, and the default of 2 was never the smallest of the
        # three on anything measured. 1 wins on ordinary pictures by 1 to 2%;
        # below roughly 20 000 pixels 0 takes over, by 7% on a 64-pixel icon.
        # The crossover sat between 120 and 200 pixels wide on both a photograph
        # and a screenshot, so it is not a property of the content.
        $prog = $(if ($traits.Pixels -gt 0 -and $traits.Pixels -lt 20000) { 0 } else { 1 })
        $cmdArgs = $cmdArgs + (' -p {0}' -f $prog)

        # a single-channel image has no chroma to sample
        if (-not $script:Grey) {
            if ($full) { $cmdArgs = $cmdArgs + ' --chroma_subsampling=444' }
            else       { $cmdArgs = $cmdArgs + ' --chroma_subsampling=420' }
        }

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName               = $Cjpegli
        $psi.Arguments              = $cmdArgs
        $psi.UseShellExecute        = $false
        $psi.CreateNoWindow         = $true
        $psi.RedirectStandardError  = $true
        $psi.RedirectStandardOutput = $true
        $script:Proc = [System.Diagnostics.Process]::Start($psi)
        $script:ProcStarted = Get-Date
    } catch {
        Add-JipegReason ('{0}: {1}' -f [System.IO.Path]::GetFileName($src), $_.Exception.Message)
        $script:Failed++
        $script:Index++
        $script:Proc = $null
        Start-Next
    }
}

function Complete-Current {
    $code = 999
    $err = ''
    try { $code = $script:Proc.ExitCode } catch { }
    # kept rather than discarded: when the encoder refuses a file it says why,
    # and that sentence was being thrown away - a batch could report two
    # failures and offer one explanation between them
    try { $err = $script:Proc.StandardError.ReadToEnd(); [void]$script:Proc.StandardOutput.ReadToEnd() } catch { }
    try { $script:Proc.Dispose() } catch { }
    $script:Proc = $null
    if ($script:TmpIn) {
        Remove-Item -LiteralPath $script:TmpIn -Force -ErrorAction SilentlyContinue
        $script:TmpIn = $null
    }
    if ($code -eq 0 -and (Test-Path -LiteralPath $script:TmpOut)) {
        try {
            $dir    = Split-Path -Parent $script:Current
            $base   = [System.IO.Path]::GetFileNameWithoutExtension($script:Current)
            $srcExt = [System.IO.Path]::GetExtension($script:Current).ToLower()
            $inLen  = (Get-Item -LiteralPath $script:Current).Length
            $outLen = (Get-Item -LiteralPath $script:TmpOut).Length

            # A result heavier than the file it came from is of no use to
            # anyone, whatever the source was. JPEG is simply worse than PNG at
            # flat colour and text: measured, a screenshot grew 88%, a diagram
            # 325%, a 64-pixel icon 448%, and a lossy WebP 162%. Those files are
            # not written at all now - the lighter of the two was already there,
            # and the point of the exercise was to save space.
            $pointless = ($outLen -ge $inLen)

            # A PNG that would have grown as a JPEG is not a lost cause: shrunk
            # as a PNG instead it usually loses a fifth to three quarters of its
            # weight, without a pixel changing. The same file comes back round
            # once, in png mode, rather than being written off.
            if ($pointless -and $script:Mode -eq 'jpeg' -and -not $script:ForcePng -and
                (Test-JipegIsPng $script:Current)) {
                Remove-Item -LiteralPath $script:TmpOut -Force -ErrorAction SilentlyContinue
                $script:TmpOut = $null
                $script:ForcePng = $true
                return                      # same file, second pass
            }

            if ($pointless) {
                Remove-Item -LiteralPath $script:TmpOut -Force -ErrorAction SilentlyContinue
                $script:Kept++
            } else {
                $ending = $(if ($script:Mode -eq 'png') { '.png' } else { '.jpg' })
                $target = Get-FreePath $dir ($base + $Suffix) $ending
                Move-Item -LiteralPath $script:TmpOut -Destination $target -Force
                # the result stands in for the original, so it carries the same
                # date: a converted holiday folder still sorts by when the
                # pictures were taken rather than by when they were converted
                try {
                    $stamp = Get-Item -LiteralPath $script:Current
                    $made  = Get-Item -LiteralPath $target
                    $made.CreationTime   = $stamp.CreationTime
                    $made.LastWriteTime  = $stamp.LastWriteTime
                } catch { }
                $script:TotalIn  += $inLen
                $script:TotalOut += $outLen
                $script:Done++
            }
        } catch {
            Add-JipegReason ('{0}: {1}' -f [System.IO.Path]::GetFileName($script:Current), $_.Exception.Message)
            $script:Failed++
        }
    } else {
        Remove-Item -LiteralPath $script:TmpOut -Force -ErrorAction SilentlyContinue
        $why = ($err -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
        $whyLog = $why
        if (-not $why) {
            $why    = $L.cvRefused -f $code
            $whyLog = (Get-JipegEnglish).cvRefused -f $code
        }
        $name = [System.IO.Path]::GetFileName($script:Current)
        Add-JipegReason ('{0}: {1}' -f $name, $why.Trim()) ('{0}: {1}' -f $name, $whyLog.Trim())
        $script:Failed++
    }
    $script:TmpOut = $null
    $script:ForcePng = $false
    $script:Index++
}

function Resume-Batch {
    # files arrived after the batch was done: pick the work back up
    $script:Finished = $false
    $autoClose.Stop()
    $btn.Text = $L.btnCancel
    $form.AcceptButton = $null
    $lblPercent.Text = ''
    $lblSizes.Text = ''
    Set-Status
    $engine.Start()
}

function Complete-Batch {
    if ($script:Finished) { return }
    $script:Finished = $true
    $engine.Stop()
    $script:BarMuted = ($script:Done -eq 0 -and ($script:Failed -gt 0 -or $script:Kept -gt 0))
    Set-Bar 1

    if ($script:Done -gt 0) {
        $pc = 0
        if ($script:TotalIn -gt 0) { $pc = [math]::Round(100 - ($script:TotalOut * 100 / $script:TotalIn)) }
        $sign = [char]0x2212
        if ($pc -lt 0) { $sign = '+'; $pc = [math]::Abs($pc) }
        $lblPercent.Text = '{0}{1}%' -f $sign, $pc
        $lblPercent.ForeColor = $Theme.Accent
        if ($pc -lt 0) { $lblPercent.ForeColor = $Theme.Text }
        $lblSizes.Text = '{0} {1} {2}' -f (Format-JipegSize $script:TotalIn), ([char]0x2192),
                                          (Format-JipegSize $script:TotalOut)
    }
    # One key for one, another for several, and a language that needs three
    # forms can phrase both around the number instead - which is what the
    # Russian and Polish files do.
    $done = $L.cvDoneMany -f $script:Done
    if ($script:Done -eq 1) { $done = $L.cvDoneOne }
    $tail = ''
    if ($script:Failed -eq 1)    { $tail = $L.cvFailOne }
    elseif ($script:Failed -gt 1) { $tail = $L.cvFailMany -f $script:Failed }
    if ($script:Kept -gt 0) { $tail = $tail + ($L.cvKept -f $script:Kept) }
    $lblTitle.Text = $done + $tail
    if ($script:Cancelled) { $lblTitle.Text = $L.cvCancelled -f ($done + $tail) }
    Write-JipegLog ('batch    {0} converted, {1} failed, {2} left alone, {3} -> {4}' -f
        $script:Done, $script:Failed, $script:Kept,
        (Format-JipegSize $script:TotalIn), (Format-JipegSize $script:TotalOut))
    $lblFile.Text = ''
    if ($script:Kept -gt 0 -and $script:Failed -eq 0) {
        $lblFile.Text = $L.cvKeptNote
    }
    if ($script:Failed -gt 0 -and $script:Reason) {
        $lblFile.Text = $script:Reason
        if ($script:Reasons.Count -gt 1) {
            $lblFile.Text = $L.cvMore -f $script:Reason, ($script:Reasons.Count - 1)
        }
    }
    $btn.Text = $L.btnOK
    $btn.Enabled = $true
    $form.AcceptButton = $btn
    $btn.Focus()

    if ($Settings.closeWhenDone -and -not $script:Cancelled -and $script:Failed -eq 0) {
        $autoClose.Start()
    }
}

# Eases the drawn value toward the real one so the bar glides between steps
# instead of snapping. It never invents progress - only real values are targets.
$glide = New-Object System.Windows.Forms.Timer
$glide.Interval = 16
$glide.Add_Tick({
    $delta = $script:BarTarget - $script:BarShown
    if ([math]::Abs($delta) -lt 0.002) {
        $script:BarShown = $script:BarTarget
        $glide.Stop()
    } else {
        $script:BarShown += $delta * 0.22
    }
    $bar.Invalidate()
})

Write-JipegContext @{ files = $Files.Count }

$engine = New-Object System.Windows.Forms.Timer
$engine.Interval = 50
$engine.Add_Tick({
    if ($script:Proc -and -not $script:Proc.HasExited) {
        # An encoder that never returns used to leave the bar frozen for good,
        # with nothing on screen to say why. Two minutes is far past anything
        # real - a 1400x950 photograph takes about a third of a second.
        if (((Get-Date) - $script:ProcStarted).TotalSeconds -lt 120) { return }
        $late = [System.IO.Path]::GetFileName($script:Current)
        Add-JipegReason ($L.cvTimeout -f $late) ((Get-JipegEnglish).cvTimeout -f $late)
        try { $script:Proc.Kill() } catch { }
        try { [void]$script:Proc.WaitForExit(2000) } catch { }
    }
    if ($script:Proc) { Complete-Current }
    Start-Next
})

# picks up files dropped by instances started after this one
$watcher = New-Object System.Windows.Forms.Timer
$watcher.Interval = 400
$watcher.Add_Tick({
    try {
        $incoming = @(Read-Queue)
        $added = 0
        foreach ($f in $incoming) {
            if ($Files -notcontains $f) { $Files.Add($f); $added++ }
        }
        if ($added -eq 0) { return }
        if ($script:Finished) { Resume-Batch }
        elseif ($script:Started) { Set-Status }
    } catch { }
})

# Gives the rest of an Explorer selection a moment to land before the first file
# starts, so the count does not visibly climb while converting.
$grace = New-Object System.Windows.Forms.Timer
$grace.Interval = 350
$grace.Add_Tick({
    $grace.Stop()
    if ($Files.Count -eq 0) { $form.Close(); return }
    $script:Started = $true
    $engine.Start()
})

$autoClose = New-Object System.Windows.Forms.Timer
$autoClose.Interval = 1300
$autoClose.Add_Tick({ $autoClose.Stop(); $form.Close() })

$btn.Add_Click({
    if ($script:Finished) { $form.Close(); return }
    $script:Cancelled = $true
    $btn.Enabled = $false
    $lblTitle.Text = $L.cvCancelling
})

$form.Add_Shown({
    Show-JipegWindow $form
    $watcher.Start()
    $grace.Start()
})
$form.Add_FormClosed({
    $engine.Stop(); $watcher.Stop(); $autoClose.Stop(); $glide.Stop(); $grace.Stop()
    try {
        $late = @(Read-Queue) | Where-Object { $Files -notcontains $_ }
        if ($late.Count -gt 0) {
            # something landed as we were closing: hand it to a fresh instance
            $vbs = Join-Path $Root 'launch.vbs'
            if (Test-Path -LiteralPath $vbs) {
                $argv = @('"' + $vbs + '"') + ($late | ForEach-Object { '"' + $_ + '"' })
                Start-Process wscript.exe -ArgumentList $argv
            }
        }
    } catch { }
    if ($script:Proc) { try { $script:Proc.Kill() } catch { } }
    if ($script:TmpOut) { Remove-Item -LiteralPath $script:TmpOut -Force -ErrorAction SilentlyContinue }
    if ($script:TmpIn)  { Remove-Item -LiteralPath $script:TmpIn  -Force -ErrorAction SilentlyContinue }
    if ($script:LockFs) {
        [void]$Mutex.WaitOne()
        try {
            $script:LockFs.Close()
            Remove-Item -LiteralPath $LockFile -Force -ErrorAction SilentlyContinue
        } finally { $Mutex.ReleaseMutex() }
    }
    # Quiet update, once a day at most, and only after the lock is gone so it
    # can never collide with a conversion. Nothing is shown either way.
    try {
        if ($Settings.autoUpdate) {
            $age = [DateTime]::UtcNow.Ticks - [int64]$Settings.lastCheck
            if ($age -gt ([TimeSpan]::FromHours(24)).Ticks) {
                $vbs = Join-Path $Root 'update.vbs'
                if (Test-Path -LiteralPath $vbs) {
                    Start-Process wscript.exe -ArgumentList ('"' + $vbs + '"')
                }
            }
        }
    } catch { }
})

Set-JipegScaleForm $form
[System.Windows.Forms.Application]::Run($form)
