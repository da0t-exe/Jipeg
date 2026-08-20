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
        "cjpegli.exe was not found at:`n$Cjpegli`n`nRun the Jipeg installer again.",
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
$lblTitle.Text = 'Getting ready...'
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
$btn.Text = 'Cancel'
Set-JipegButton $btn $Theme $Backdrop
$form.Controls.Add($btn)
$form.CancelButton = $btn

# ------------------------------------------------------------------- engine
$script:Index     = 0
$script:Done      = 0
$script:Failed    = 0
$script:Reason    = ''
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
    if ($n -eq 1) { $lblTitle.Text = 'Converting to JPEG...' }
    else          { $lblTitle.Text = "Converting to JPEG... ($($script:Index) of $n)" }
    if ($n -gt 0) { Set-Bar ($script:Index / [double]$n) } else { Set-Bar 0 }
}

# --------------------------------------------------------------- decoding
# JPEG has no transparency, so something has to be put behind it. cjpegli uses
# black, which turned a logo on a transparent background into a logo on a black
# square; every other tool in the world uses white. Anything carrying alpha is
# flattened onto white here first. The image is drawn into a rectangle its own
# size rather than with DrawImageUnscaled, which would rescale it whenever the
# file carries a DPI different from the screen's.
function ConvertTo-JipegPng-Gdi([string]$src, [string]$dst) {
    $fs = [System.IO.File]::OpenRead($src)
    try {
        $img = [System.Drawing.Image]::FromStream($fs, $true, $false)
        try {
            $bmp = New-Object System.Drawing.Bitmap($img.Width, $img.Height,
                       [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
            try {
                $g = [System.Drawing.Graphics]::FromImage($bmp)
                $g.Clear([System.Drawing.Color]::White)
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
function Test-JipegPngNeedsDecode([string]$path) {
    $fs = $null
    try {
        $fs = [System.IO.File]::OpenRead($path)
        $head = New-Object byte[] 26
        if ($fs.Read($head, 0, 26) -lt 26) { return $false }
        $type = [int]$head[25]
        $alpha = ($type -eq 4 -or $type -eq 6)
        # 8 signature bytes, then IHDR: 4 length + 4 name + 13 data + 4 CRC.
        # Reading 26 bytes to reach the colour type leaves the cursor inside
        # IHDR's data, so the chunk walk has to be put back on the boundary.
        $fs.Position = 33
        $br = New-Object System.IO.BinaryReader($fs)
        while ($fs.Position -lt $fs.Length) {
            $len = ([int]$br.ReadByte() -shl 24) -bor ([int]$br.ReadByte() -shl 16) -bor
                   ([int]$br.ReadByte() -shl 8)  -bor  [int]$br.ReadByte()
            $name = [System.Text.Encoding]::ASCII.GetString($br.ReadBytes(4))
            if ($name -eq 'acTL') { return $true }              # animated
            if ($name -eq 'tRNS') { $alpha = $true }
            if ($name -eq 'IDAT') { return $alpha }             # header is over
            [void]$br.ReadBytes($len + 4)                       # data plus its CRC
        }
        return $alpha
    } catch { } finally { if ($fs) { $fs.Dispose() } }
    return $false
}

function ConvertTo-JipegPng-Webp([string]$src, [string]$dst) {
    if (-not (Test-Path -LiteralPath $Dwebp)) {
        throw "WebP needs bin\dwebp.exe. Run the Jipeg installer again."
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $Dwebp
    $psi.Arguments              = '"{0}" -o "{1}"' -f $src, $dst
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $psi.RedirectStandardError  = $true
    $psi.RedirectStandardOutput = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $err = $p.StandardError.ReadToEnd()
    [void]$p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    $code = $p.ExitCode
    $p.Dispose()
    if ($code -ne 0 -or -not (Test-Path -LiteralPath $dst)) {
        throw ("WebP could not be read: " + $err.Trim())
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
        # a PNG only needs the detour if it is transparent or animated
        $awkward = ($ext -eq '.png' -and (Test-JipegPngNeedsDecode $src))
        if ($GdiExt -contains $ext -or $WebpExt -contains $ext -or
            $WicExt -contains $ext -or $awkward) {
            # cjpegli reads none of these: decode to PNG first, by whichever
            # route knows the format, and hand it that instead
            $tmpPng = Join-Path $env:TEMP ('jipeg-in-{0}.png' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
            if ($WebpExt -contains $ext -or $WicExt -contains $ext) {
                $raw = Join-Path $env:TEMP ('jipeg-raw-{0}.png' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
                if ($WebpExt -contains $ext) { ConvertTo-JipegPng-Webp $src $raw }
                else                         { ConvertTo-JipegPng-Wic  $src $raw $ext }
                # these decoders keep the alpha channel, so the same flattening
                # applies to them
                if (Test-JipegPngNeedsDecode $raw) { ConvertTo-JipegPng-Gdi $raw $tmpPng }
                else { Move-Item -LiteralPath $raw -Destination $tmpPng -Force }
                Remove-Item -LiteralPath $raw -Force -ErrorAction SilentlyContinue
            } else {
                ConvertTo-JipegPng-Gdi $src $tmpPng
            }
            $source = $tmpPng; $script:TmpIn = $tmpPng
        }
        $dir = Split-Path -Parent $src
        $script:TmpOut = Join-Path $dir ('.jipeg-{0}.tmp' -f [guid]::NewGuid().ToString('N').Substring(0, 8))

        $cmdArgs = '"{0}" "{1}" -q {2}' -f $source, $script:TmpOut, $Settings.quality
        # 'auto' asks the original - not $source, which may be a temporary PNG and
        # would always answer yes.
        $full = switch ([string]$Settings.chroma) {
            'always' { $true }
            'never'  { $false }
            default  { Test-JipegSourceFullChroma $src }
        }
        # Both branches say it out loud. cjpegli defaults to 4:4:4, so the old
        # code - which passed the flag only to ask for 4:4:4 - produced the same
        # image either way, and the setting did nothing in either position.
        if ($full) { $cmdArgs = $cmdArgs + ' --chroma_subsampling=444' }
        else       { $cmdArgs = $cmdArgs + ' --chroma_subsampling=420' }

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName               = $Cjpegli
        $psi.Arguments              = $cmdArgs
        $psi.UseShellExecute        = $false
        $psi.CreateNoWindow         = $true
        $psi.RedirectStandardError  = $true
        $psi.RedirectStandardOutput = $true
        $script:Proc = [System.Diagnostics.Process]::Start($psi)
    } catch {
        if (-not $script:Reason) { $script:Reason = $_.Exception.Message }
        $script:Failed++
        $script:Index++
        $script:Proc = $null
        Start-Next
    }
}

function Complete-Current {
    $code = 999
    try { $code = $script:Proc.ExitCode } catch { }
    try { [void]$script:Proc.StandardError.ReadToEnd(); [void]$script:Proc.StandardOutput.ReadToEnd() } catch { }
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
            $target = Get-FreePath $dir ($base + $Suffix) '.jpg'
            Move-Item -LiteralPath $script:TmpOut -Destination $target -Force
            $script:TotalIn  += (Get-Item -LiteralPath $script:Current).Length
            $script:TotalOut += (Get-Item -LiteralPath $target).Length
            $script:Done++
        } catch { $script:Failed++ }
    } else {
        Remove-Item -LiteralPath $script:TmpOut -Force -ErrorAction SilentlyContinue
        $script:Failed++
    }
    $script:TmpOut = $null
    $script:Index++
}

function Resume-Batch {
    # files arrived after the batch was done: pick the work back up
    $script:Finished = $false
    $autoClose.Stop()
    $btn.Text = 'Cancel'
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
    $script:BarMuted = ($script:Done -eq 0 -and $script:Failed -gt 0)
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
    $word = 'images'
    if ($script:Done -eq 1) { $word = 'image' }
    if ($script:Cancelled) {
        $lblTitle.Text = "Cancelled - $($script:Done) $word converted"
    } elseif ($script:Failed -gt 0) {
        $f = 'failures'; if ($script:Failed -eq 1) { $f = 'failure' }
        $lblTitle.Text = "$($script:Done) $word converted, $($script:Failed) $f"
    } else {
        $lblTitle.Text = "$($script:Done) $word converted"
    }
    $lblFile.Text = ''
    if ($script:Failed -gt 0 -and $script:Reason) { $lblFile.Text = $script:Reason }
    $btn.Text = 'OK'
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

$engine = New-Object System.Windows.Forms.Timer
$engine.Interval = 50
$engine.Add_Tick({
    if ($script:Proc -and -not $script:Proc.HasExited) { return }
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
    $lblTitle.Text = 'Cancelling...'
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

[System.Windows.Forms.Application]::Run($form)
