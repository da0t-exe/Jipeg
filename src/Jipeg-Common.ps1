<#
  Shared helpers for Jipeg: settings storage, theming and a few Win32 calls.
  Dot-sourced by Jipeg-Convert.ps1 and Jipeg-Settings.ps1.
#>

$JipegVersion = '2.2'
$JipegRepo    = 'da0t-exe/Jipeg'

[void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
[void][System.Reflection.Assembly]::LoadWithPartialName('System.Drawing')

Add-Type -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)] public struct MARGINS { public int Left, Right, Top, Bottom; }
[DllImport("dwmapi.dll")] public static extern int  DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);
[DllImport("dwmapi.dll")] public static extern int  DwmExtendFrameIntoClientArea(IntPtr hwnd, ref MARGINS m);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int cmd);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
[DllImport("uxtheme.dll", CharSet=CharSet.Unicode)] public static extern int SetWindowTheme(IntPtr hwnd, string sub, string id);
[DllImport("shell32.dll", CharSet=CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string name);
[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hwnd, int msg, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
'@ -Name 'Win' -Namespace 'Jipeg' | Out-Null

# ------------------------------------------------------------------ settings
# Every window here is hosted by powershell.exe, so without an identity of its
# own Windows files them under PowerShell in the taskbar and shows its icon.
# Must be set before the process creates any window.
$JipegAppId = 'Jipeg.ImageConverter'
try { [void][Jipeg.Win]::SetCurrentProcessExplicitAppUserModelID($JipegAppId) } catch { }

function Set-JipegIcon($form, [string]$root) {
    $path = Join-Path $root 'jipeg.ico'
    if (-not (Test-Path -LiteralPath $path)) { return }
    try { $form.Icon = New-Object System.Drawing.Icon($path) } catch { }
}

# Declared before any window exists, which is why it sits above everything else
# in the file every script loads first. Left undeclared, the process is
# DPI-unaware and Windows takes the whole window, rendered at 96 DPI, and
# stretches it: on a laptop at 150% every one of those byte-identical corners
# goes through a bitmap resize. Asking for per-monitor awareness means the
# window is drawn at the screen's real resolution instead.
try {
    if (-not [Jipeg.Win]::SetProcessDpiAwarenessContext([IntPtr](-4))) {   # PER_MONITOR_AWARE_V2
        [void][Jipeg.Win]::SetProcessDPIAware()                            # older builds
    }
} catch { }

# One factor decides everything: the size of the fonts, the position of every
# control and the radius of every corner. It is settled here, before a single
# font or window exists, because deciding it later was a bug - the fonts ended
# up built at one scale and the layout shrunk to another, and at 150% the text
# overflowed its box and the drop-down below wrote over the line above it.
#
# It starts as what Windows asks for, then is capped by what the screen can hold:
# the settings window is 760 points tall, which is 1140 at 150%, more than a
# 1080p laptop has room for, and OK and Cancel fell off the bottom. Slightly
# smaller than Windows asked and entirely visible beats exactly right and cut off.
$JipegDesignHeight = 760
$JipegRealDpi = 1.0
try {
    $g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
    $JipegRealDpi = [double]$g.DpiX / 96.0
    $g.Dispose()
} catch { }

# JIPEG_SCALE pretends the screen has that scaling, so the layout can be checked
# at 125, 150 and 200% on an ordinary display. There is no other way to test it.
$JipegAsked = $JipegRealDpi
if ($env:JIPEG_SCALE) {
    $forced = 0.0
    if ([double]::TryParse($env:JIPEG_SCALE, [ref]$forced) -and $forced -ge 0.5 -and $forced -le 4.0) {
        $JipegAsked = $forced
    }
}
$JipegScale = $JipegAsked
try {
    $room = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height - 48
    $wanted = $JipegDesignHeight * $JipegAsked
    if ($wanted -gt $room -and $room -gt 200) { $JipegScale = $JipegAsked * ($room / $wanted) }
} catch { }

# A font size is in points, so on a real high-DPI screen it already comes out
# larger on its own - that is what points are for. What is left to apply is the
# difference between what the screen gives and what was settled above.
$JipegFontMul = $(if ($JipegRealDpi -gt 0) { $JipegScale / $JipegRealDpi } else { 1.0 })

function Get-JipegScaled([double]$px) { return [int][math]::Round($px * $JipegScale) }

# Applied once, after a window is built and before it is shown. WinForms is told
# not to scale anything itself, so the numbers written in the layout stay design
# units until they pass through here. Scale does not touch fonts - those were
# built at the right size already - so bounds and text land on the same factor.
function Set-JipegScaleForm($form) {
    if ([math]::Abs($JipegScale - 1.0) -lt 0.001) { return }
    try {
        $f = [single]$JipegScale
        $form.Scale((New-Object System.Drawing.SizeF($f, $f)))
    } catch { }
}

$JipegSettingsPath = Join-Path (Join-Path $env:LOCALAPPDATA 'Jipeg') 'settings.json' 

# Bumped when the meaning of a stored value changes, so an older file can be
# brought forward instead of being thrown away or misread.
$JipegSchema = 2

function Get-JipegDefaults {
    return [pscustomobject]@{
        schema        = $JipegSchema
        writtenBy     = $JipegVersion
        theme         = 'auto'      # auto | light | dark
        quality       = 90          # libjpeg scale, 1..100
        chroma        = 'auto'      # auto | always | never, see Test-JipegSourceFullChroma
        closeWhenDone = $false      # dismiss the progress window automatically
        mica          = $true       # the Windows 11 backdrop behind the windows
        autoUpdate    = $true       # fetch and install newer releases quietly
        lastCheck     = 0           # ticks of the last update check
        lastUpdate    = ''          # what the last quiet update did
    }
}

# Settings survive an upgrade: unknown keys from a newer build are ignored,
# missing ones take today's default, and anything whose meaning changed is
# rewritten here rather than silently misread.
function Update-JipegSchema($s, $raw) {
    # The version to migrate FROM is the one in the file, never the one already
    # sitting in $s: that came from the defaults and is always current, so a file
    # written before the field existed would look up to date and be left alone.
    $s.schema = 0
    if ($raw -and $null -ne $raw.schema) { $s.schema = [int]$raw.schema }
    if ([int]$s.schema -lt 2 -and $raw) {
        # 1 -> 2: chroma stopped being a yes/no. Ticked was a deliberate act, so
        # it is kept as 'always'. Unticked was merely the old default - nobody
        # chose it - so it becomes the new default rather than pinning those
        # users to 4:2:0 forever.
        if ($null -ne $raw.chroma444) {
            if ([bool]$raw.chroma444) { $s.chroma = 'always' } else { $s.chroma = 'auto' }
        }
        # mica changed meaning rather than value: in schema 1 it meant "accept
        # colours that come out lighter than they were picked", which is why it
        # was off. The palette is compensated now, so the old answer was to a
        # different question and the new default applies.
        $s.mica = (Get-JipegDefaults).mica
    }
    $s.schema = $JipegSchema
    return $s
}

function Get-JipegSettings {
    $s = Get-JipegDefaults
    $raw = $null
    try {
        if (Test-Path -LiteralPath $JipegSettingsPath) {
            $raw = Get-Content -LiteralPath $JipegSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $s.PSObject.Properties.Name) {
                if ($null -ne $raw.$p) { $s.$p = $raw.$p }
            }
        }
    } catch { }   # a corrupt file must never stop a conversion
    $s = Update-JipegSchema $s $raw
    if ($s.quality -lt 1 -or $s.quality -gt 100) { $s.quality = 90 }
    if ('auto', 'light', 'dark' -notcontains $s.theme) { $s.theme = 'auto' }
    if ('auto', 'always', 'never' -notcontains $s.chroma) { $s.chroma = 'auto' }
    return $s
}

# A pixel scan in PowerShell is hundreds of times slower than the same loop in
# compiled code, so this one is compiled. It walks a subsample and gives up on
# the first pixel that is not grey - a colour photograph is rejected in about
# two milliseconds.
Add-Type -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
namespace Jipeg {
  public static class Pixels {
    // La proportion de couples de pixels voisins dont la chrominance saute
    // brutalement - exactement ce que le sous-echantillonnage 4:2:0 detruit.
    // Mesure : du texte ou un aplat colore depassent 0,5 %, une photographie
    // reste a 0,00 %, ses variations de couleur etant douces.
    public static long[] ChromaEdges(Bitmap b, int step, int thr) {
      if (b.Width < 2 || b.Height < 1) return new long[] { 0, 0 };
      Rectangle r = new Rectangle(0, 0, b.Width, b.Height);
      BitmapData d = b.LockBits(r, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
      try {
        byte[] row = new byte[d.Stride];
        long hard = 0, total = 0;
        for (int y = 0; y < b.Height; y += step) {
          Marshal.Copy(IntPtr.Add(d.Scan0, y * d.Stride), row, 0, d.Stride);
          for (int x = 1; x < b.Width; x++) {
            int i = x * 3, j = (x - 1) * 3;
            double cb1 = -0.169 * row[i+2] - 0.331 * row[i+1] + 0.500 * row[i];
            double cr1 =  0.500 * row[i+2] - 0.419 * row[i+1] - 0.081 * row[i];
            double cb0 = -0.169 * row[j+2] - 0.331 * row[j+1] + 0.500 * row[j];
            double cr0 =  0.500 * row[j+2] - 0.419 * row[j+1] - 0.081 * row[j];
            total++;
            if (Math.Abs(cb1 - cb0) + Math.Abs(cr1 - cr0) > thr) hard++;
          }
        }
        return new long[] { hard, total };
      } finally { b.UnlockBits(d); }
    }

    public static bool IsGrey(Bitmap b, int step, int tol) {
      if (b.Width < 1 || b.Height < 1) return false;
      Rectangle r = new Rectangle(0, 0, b.Width, b.Height);
      BitmapData d = b.LockBits(r, ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
      try {
        int stride = d.Stride;
        byte[] row = new byte[stride];
        for (int y = 0; y < b.Height; y += step) {
          Marshal.Copy(IntPtr.Add(d.Scan0, y * stride), row, 0, stride);
          for (int x = 0; x < b.Width; x += step) {
            int i = x * 3;
            int bl = row[i], g = row[i + 1], rd = row[i + 2];
            if (Math.Abs(rd - g) > tol || Math.Abs(g - bl) > tol || Math.Abs(rd - bl) > tol)
              return false;
          }
        }
        return true;
      } finally { b.UnlockBits(d); }
    }
  }
}
'@ -ReferencedAssemblies System.Drawing

# What a WebP actually holds, read from its RIFF header: VP8 is lossy and always
# 4:2:0 inside, VP8L is lossless, and VP8X with an ANIM chunk is an animation -
# which dwebp cannot decode on its own.
function Get-JipegWebpKind([string]$path) {
    try {
        $fs = [System.IO.File]::OpenRead($path)
        try {
            $head = New-Object byte[] 64
            $n = $fs.Read($head, 0, 64)
            if ($n -lt 16) { return 'unknown' }
            $ascii = [System.Text.Encoding]::ASCII
            if ($ascii.GetString($head, 0, 4) -ne 'RIFF') { return 'unknown' }
            if ($ascii.GetString($head, 8, 4) -ne 'WEBP') { return 'unknown' }
            $kind = $ascii.GetString($head, 12, 4)
            if ($kind -eq 'VP8 ')  { return 'lossy' }
            if ($kind -eq 'VP8L')  { return 'lossless' }
            if ($kind -eq 'VP8X') {
                $rest = $ascii.GetString($head, 0, $n)
                if ($rest.Contains('ANIM')) { return 'animated' }
                if ($rest.Contains('VP8L')) { return 'lossless' }
                return 'lossy'
            }
        } finally { $fs.Dispose() }
    } catch { }
    return 'unknown'
}

# The orientation a JPEG asks to be displayed at, from its Exif block. 1 means
# upright, and so does a file that has no Exif at all or one we cannot make
# sense of - the safe answer, since acting on a wrong guess would rotate a
# picture that was already the right way up.
function Get-JipegOrientation([string]$path) {
    $ext = [System.IO.Path]::GetExtension($path).ToLower()
    if ('.jpg', '.jpeg', '.jpe', '.jfif' -notcontains $ext) { return 1 }
    $fs = $null
    try {
        $fs = [System.IO.File]::OpenRead($path)
        $br = New-Object System.IO.BinaryReader($fs)
        if ([int]$br.ReadByte() -ne 0xFF -or [int]$br.ReadByte() -ne 0xD8) { return 1 }
        while ($true) {
            if ([int]$br.ReadByte() -ne 0xFF) { continue }
            $m = [int]$br.ReadByte()
            while ($m -eq 0xFF) { $m = [int]$br.ReadByte() }
            if ($m -eq 0x01 -or ($m -ge 0xD0 -and $m -le 0xD8)) { continue }
            if ($m -eq 0xD9 -or $m -eq 0xDA) { return 1 }        # pixel data: no Exif
            $len = ([int]$br.ReadByte() -shl 8) -bor [int]$br.ReadByte()
            if ($len -lt 2) { return 1 }
            if ($m -ne 0xE1) { [void]$br.ReadBytes($len - 2); continue }

            $block = $br.ReadBytes($len - 2)
            if ($block.Length -lt 14) { return 1 }
            if ([System.Text.Encoding]::ASCII.GetString($block, 0, 4) -ne 'Exif') { continue }
            $t = 6                                                # past the Exif marker
            $little = ([char]$block[$t] -eq 'I')
            function Get16($a, $o, $le) {
                if ($le) { return ([int]$a[$o + 1] -shl 8) -bor [int]$a[$o] }
                return ([int]$a[$o] -shl 8) -bor [int]$a[$o + 1]
            }
            function Get32($a, $o, $le) {
                if ($le) {
                    return ([int]$a[$o + 3] -shl 24) -bor ([int]$a[$o + 2] -shl 16) -bor
                           ([int]$a[$o + 1] -shl 8)  -bor  [int]$a[$o]
                }
                return ([int]$a[$o] -shl 24) -bor ([int]$a[$o + 1] -shl 16) -bor
                       ([int]$a[$o + 2] -shl 8)  -bor  [int]$a[$o + 3]
            }
            $ifd = $t + (Get32 $block ($t + 4) $little)
            if ($ifd -lt 0 -or ($ifd + 2) -gt $block.Length) { return 1 }
            $count = Get16 $block $ifd $little
            for ($i = 0; $i -lt $count; $i++) {
                $e = $ifd + 2 + ($i * 12)
                if (($e + 12) -gt $block.Length) { break }
                if ((Get16 $block $e $little) -eq 0x0112) {
                    $v = Get16 $block ($e + 8) $little
                    if ($v -ge 1 -and $v -le 8) { return $v }
                    return 1
                }
            }
            return 1
        }
    } catch { } finally { if ($fs) { $fs.Dispose() } }
    return 1
}

# Whether the source still holds full colour detail, so "follow the source" can
# be an answer rather than a guess from the file extension: a JPEG states its
# sampling factors in the start-of-frame header, and anything lossless has all
# of its colour by definition. Every ReadByte is cast before shifting - shifting
# a [byte] in PowerShell masks the shift count and quietly returns the wrong
# number.
function Test-JipegSourceFullChroma([string]$path) {
    $frame = Get-JipegJpegFrame $path
    if ($null -eq $frame) { return $true }
    return $frame.FullChroma
}

# How many colour components a JPEG carries, and whether it kept its chroma at
# full resolution. Four components means CMYK or YCCK, which cjpegli refuses
# outright - "Failed to decode input image" - so those have to go the long way
# round through Windows, which reads them.
function Get-JipegJpegFrame([string]$path) {
    $ext = [System.IO.Path]::GetExtension($path).ToLower()
    if ('.jpg', '.jpeg', '.jpe', '.jfif' -notcontains $ext) { return $null }
    $fs = $null
    try {
        $fs = [System.IO.File]::OpenRead($path)
        $br = New-Object System.IO.BinaryReader($fs)
        if ([int]$br.ReadByte() -ne 0xFF -or [int]$br.ReadByte() -ne 0xD8) { return $null }
        while ($true) {
            if ([int]$br.ReadByte() -ne 0xFF) { continue }   # resync on the next marker
            $m = [int]$br.ReadByte()
            while ($m -eq 0xFF) { $m = [int]$br.ReadByte() } # fill bytes before a marker
            if ($m -eq 0x01 -or ($m -ge 0xD0 -and $m -le 0xD8)) { continue }   # no payload
            if ($m -eq 0xD9 -or $m -eq 0xDA) { break }       # image data: no frame header
            $len = ([int]$br.ReadByte() -shl 8) -bor [int]$br.ReadByte()
            if ($len -lt 2) { break }
            $isFrame = ($m -ge 0xC0 -and $m -le 0xCF -and $m -ne 0xC4 -and $m -ne 0xC8 -and $m -ne 0xCC)
            if (-not $isFrame) { [void]$br.ReadBytes($len - 2); continue }
            [void]$br.ReadByte()                             # sample precision
            [void]$br.ReadBytes(4)                           # height, width
            $n = [int]$br.ReadByte()
            if ($n -lt 3) { return @{ Components = $n; FullChroma = $true } }  # grey
            [void]$br.ReadByte()                             # component id
            $hv = [int]$br.ReadByte()
            return @{
                Components = $n
                FullChroma = ((($hv -shr 4) -eq 1) -and (($hv -band 0x0F) -eq 1))
            }
        }
    } catch { } finally { if ($fs) { $fs.Dispose() } }
    return $null       # unreadable header
}

function Save-JipegSettings($s) {
    $s.schema = $JipegSchema
    $s.writtenBy = $JipegVersion
    $dir = Split-Path -Parent $JipegSettingsPath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    ($s | ConvertTo-Json) | Set-Content -LiteralPath $JipegSettingsPath -Encoding UTF8
}

# -------------------------------------------------------------------- theme
function Test-SystemDark {
    try {
        return ((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' `
                 -Name AppsUseLightTheme -ErrorAction Stop).AppsUseLightTheme -eq 0)
    } catch { return $false }
}

# Windows keeps eight shades of the user's accent colour, light to dark. The
# light ones read well on a dark background and vice versa, which is exactly
# what Windows itself picks from.
function Get-JipegAccent([bool]$dark) {
    $fallback = [System.Drawing.Color]::FromArgb(255, 76, 148, 255)
    try {
        $pal = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' `
                -Name AccentPalette -ErrorAction Stop).AccentPalette
        if ($pal.Length -lt 32) { return $fallback }
        $i = 4      # a deeper shade, for light backgrounds
        if ($dark) { $i = 2 }
        $o = $i * 4
        return [System.Drawing.Color]::FromArgb(255, $pal[$o], $pal[$o + 1], $pal[$o + 2])
    } catch { return $fallback }
}

function Get-JipegTheme([string]$preference) {
    $dark = switch ($preference) {
        'dark'  { $true }
        'light' { $false }
        default { Test-SystemDark }
    }
    if ($dark) {
        return @{
            Dark    = $true
            Back    = [System.Drawing.Color]::FromArgb(32, 32, 32)
            Panel   = [System.Drawing.Color]::FromArgb(43, 43, 43)
            Text    = [System.Drawing.Color]::FromArgb(255, 255, 255)
            Muted   = [System.Drawing.Color]::FromArgb(192, 192, 192)   # 7.8:1 sur les cartes
            Button  = [System.Drawing.Color]::FromArgb(45, 45, 45)
            Edge    = [System.Drawing.Color]::FromArgb(70, 70, 70)
            Track   = [System.Drawing.Color]::FromArgb(58, 58, 58)
            Field   = [System.Drawing.Color]::FromArgb(56, 56, 56)   # doit trancher sur la carte
            CardEdge = [System.Drawing.Color]::FromArgb(58, 58, 58)
            CheckEdge = [System.Drawing.Color]::FromArgb(122, 122, 122)
            Accent  = Get-JipegAccent $true
        }
    }
    return @{
        Dark    = $false
        Back    = [System.Drawing.Color]::FromArgb(243, 243, 243)
        Panel   = [System.Drawing.Color]::FromArgb(251, 251, 251)
        Text    = [System.Drawing.Color]::FromArgb(26, 26, 26)
        Muted   = [System.Drawing.Color]::FromArgb(80, 80, 80)          # 7.9:1 sur les cartes
        Button  = [System.Drawing.Color]::FromArgb(253, 253, 253)
        Edge    = [System.Drawing.Color]::FromArgb(205, 205, 205)
        Track   = [System.Drawing.Color]::FromArgb(222, 222, 222)
        Field   = [System.Drawing.Color]::FromArgb(255, 255, 255)
        CardEdge = [System.Drawing.Color]::FromArgb(226, 226, 226)
        CheckEdge = [System.Drawing.Color]::FromArgb(140, 140, 140)
        Accent  = Get-JipegAccent $false
    }
}

# Three sizes rather than one. With a single size the section headings, the
# control labels and the explanations all shout at the same volume and nothing
# leads the eye. The family stays the user's own dialog font, so this still
# follows their typeface and DPI.
$JipegFamily = [System.Drawing.SystemFonts]::MessageBoxFont.FontFamily

function New-JipegSemibold([single]$size) {
    # Semibold reads better than Bold at heading sizes, when the family has it.
    try {
        $f = New-Object System.Drawing.Font(($JipegFamily.Name + ' Semibold'), $size)
        if ($f.Name -like '*Semibold*') { return $f }
        $f.Dispose()
    } catch { }
    return New-Object System.Drawing.Font($JipegFamily, $size, [System.Drawing.FontStyle]::Bold)
}

$JipegFont        = New-Object System.Drawing.Font($JipegFamily, (10.0  * $JipegFontMul))  # labels, body
$JipegFontHint    = New-Object System.Drawing.Font($JipegFamily, (8.75  * $JipegFontMul))  # explanations
$JipegFontSection = New-JipegSemibold (11.25 * $JipegFontMul)            # section headings
$JipegFontBold    = New-JipegSemibold (10.0  * $JipegFontMul)            # emphasis in body
$JipegFontBig     = New-JipegSemibold (15.0  * $JipegFontMul)            # the one number that matters

# Windows 11 rounds top-level windows on its own; this only syncs the title bar
# with the theme the user picked, which may differ from the system one.
function Set-JipegChrome($form, $theme) {
    $on = 0
    if ($theme.Dark) { $on = 1 }
    if ([Jipeg.Win]::DwmSetWindowAttribute($form.Handle, 20, [ref]$on, 4) -ne 0) {
        [void][Jipeg.Win]::DwmSetWindowAttribute($form.Handle, 19, [ref]$on, 4)
    }
}

# A parent process launched with a hidden window (wscript, or "-WindowStyle
# Hidden") passes that SW_HIDE on to the first window this process creates.
# Without this the window exists but never appears.
function Show-JipegWindow($form) {
    [void][Jipeg.Win]::ShowWindow($form.Handle, 1)      # SW_SHOWNORMAL
    [void][Jipeg.Win]::SetForegroundWindow($form.Handle)
}

# A combo box drops its list in a separate system window of class ComboLBox.
# Windows 11 will round it for us, but only if asked once the window exists -
# hence the short delay after DropDown fires.
function Set-JipegPopupChrome($theme) {
    try {
        $lb = [Jipeg.Win]::FindWindow('ComboLBox', $null)
        if ($lb -eq [IntPtr]::Zero) { return }
        $round = 2                                   # DWMWA_WINDOW_CORNER_PREFERENCE
        [void][Jipeg.Win]::DwmSetWindowAttribute($lb, 33, [ref]$round, 4)
        $dark = 0
        if ($theme.Dark) { $dark = 1 }
        [void][Jipeg.Win]::DwmSetWindowAttribute($lb, 20, [ref]$dark, 4)
        # A border, or the list melts into whatever is behind it. The casts are
        # load-bearing: shifting a [byte] in PowerShell masks the shift count to
        # three bits, so 58 -shl 16 gives back 58 and the colour arrived as
        # 0x0000003A - pure red - instead of 0x003A3A3A.
        $edge = ([int]$theme.CardEdge.B -shl 16) -bor ([int]$theme.CardEdge.G -shl 8) -bor [int]$theme.CardEdge.R
        [void][Jipeg.Win]::DwmSetWindowAttribute($lb, 34, [ref]$edge, 4)
    } catch { }
}

function Set-JipegLabel($lbl, $theme, [bool]$mica) {
    if ($mica) { $lbl.BackColor = [System.Drawing.Color]::Transparent }
}

# GDI+ rasterises the right and bottom edges of a path differently from the left
# and top. Measured on a button, the four corner ramps differed by 14 levels out
# of 255, and no geometry fixes it: rebuilding the shape from a mirrored point
# set instead of four arcs gives the same 14, at every point count tried.
#
# So the shape is drawn once into a buffer and its top-left quarter is mirrored
# over the other three. A rounded rectangle is symmetric by definition and its
# straight edges are uniform, so this changes nothing about the intended shape -
# it only makes the four corners identical byte for byte instead of merely
# close. Only the shape goes through here; text and glyphs are drawn afterwards,
# straight onto the control, so they keep subpixel rendering and stay put.
function Copy-JipegCorners($bmp) {
    $w = $bmp.Width; $h = $bmp.Height
    if ($w -lt 2 -or $h -lt 2) { return }
    $hw = [int][math]::Ceiling($w / 2.0)
    $hh = [int][math]::Ceiling($h / 2.0)
    $tl = $bmp.Clone((New-Object System.Drawing.Rectangle(0, 0, $hw, $hh)), $bmp.PixelFormat)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CompositingMode = 'SourceCopy'
    foreach ($spec in @(@('RotateNoneFlipX', ($w - $hw), 0),
                        @('RotateNoneFlipY', 0, ($h - $hh)),
                        @('RotateNoneFlipXY', ($w - $hw), ($h - $hh)))) {
        $c = $tl.Clone()
        $c.RotateFlip($spec[0])
        $g.DrawImageUnscaled($c, [int]$spec[1], [int]$spec[2])
        $c.Dispose()
    }
    $g.Dispose(); $tl.Dispose()
}


# Lighter or darker by a fraction, for the hover and pressed states. Windows
# lifts a dark button on hover and presses both themes down.
function New-JipegShade($c, [double]$amount) {
    if ($amount -ge 0) {
        return [System.Drawing.Color]::FromArgb(255,
            [int]([double]$c.R + (255.0 - $c.R) * $amount),
            [int]([double]$c.G + (255.0 - $c.G) * $amount),
            [int]([double]$c.B + (255.0 - $c.B) * $amount))
    }
    $k = 1.0 + $amount
    return [System.Drawing.Color]::FromArgb(255,
        [int]([double]$c.R * $k), [int]([double]$c.G * $k), [int]([double]$c.B * $k))
}

# Windows keeps focus rectangles hidden until someone navigates with the
# keyboard, and every native control obeys it; WM_QUERYUISTATE reports the flag
# for a window. Asking it means clicking a check box no longer paints a ring
# nobody asked for, while Tab still shows one.
function Test-JipegFocusCue($ctrl) {
    if (-not $ctrl.IsHandleCreated) { return $false }
    try {
        $state = [Jipeg.Win]::SendMessage($ctrl.Handle, 0x0129, [IntPtr]::Zero, [IntPtr]::Zero)
        return ((([int]$state) -band 0x1) -eq 0)      # UISF_HIDEFOCUS clear = show it
    } catch { return $false }
}

# Buttons are painted for the same reason the fields are. Set-JipegRounded put a
# Region on them, and a region is all-or-nothing per pixel: measured, the four
# corners of a button differed by 45 levels out of 255 and the diagonal through
# a corner held only two distinct values - a staircase, not a curve. Painting
# gives an antialiased edge and the same radius on all four corners.
#
# $backdrop is whatever lies behind the button, because the corners outside the
# rounded shape have to be that and nothing else. On a Mica window it is black,
# which is what the material is keyed on, so the glass carries on through them.
function Set-JipegButton($b, $theme, $backdrop = $null) {
    if ($null -eq $backdrop) { $backdrop = $theme.Back }
    $b.Font = $JipegFont
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.ForeColor = $theme.Text
    $b.BackColor = $backdrop
    $b.UseVisualStyleBackColor = $false
    $b.FlatAppearance.MouseOverBackColor = $backdrop
    $b.FlatAppearance.MouseDownBackColor = $backdrop
    Set-JipegDoubleBuffer $b
    $b.Tag = [pscustomobject]@{ Theme = $theme; Hot = $false; Down = $false }
    $b.Add_MouseEnter({ $this.Tag.Hot = $true;  $this.Invalidate() })
    $b.Add_MouseLeave({ $this.Tag.Hot = $false; $this.Tag.Down = $false; $this.Invalidate() })
    $b.Add_MouseDown({  $this.Tag.Down = $true;  $this.Invalidate() })
    $b.Add_MouseUp({    $this.Tag.Down = $false; $this.Invalidate() })
    $b.Add_GotFocus({   $this.Invalidate() })
    $b.Add_LostFocus({  $this.Invalidate() })
    $b.Add_EnabledChanged({ $this.Invalidate() })
    $b.Add_Paint({
        $g  = $_.Graphics
        $st = $this.Tag
        $t  = $st.Theme

        $face = $t.Button
        if (-not $this.Enabled) {
            $face = $(if ($t.Dark) { New-JipegShade $t.Button -0.25 } else { New-JipegShade $t.Button -0.03 })
        } elseif ($st.Down) {
            $face = New-JipegShade $t.Button $(if ($t.Dark) { -0.18 } else { -0.09 })
        } elseif ($st.Hot) {
            $face = New-JipegShade $t.Button $(if ($t.Dark) { 0.09 } else { -0.035 })
        }

        # the shape is built in a buffer so its corners can be made identical
        # before it reaches the screen
        $buf = New-Object System.Drawing.Bitmap($this.Width, $this.Height)
        $bg = [System.Drawing.Graphics]::FromImage($buf)
        # cleared before smoothing goes on, or the outermost column is left
        # half covered and a Mica backdrop shows through the gap
        $bg.Clear($this.BackColor)
        $bg.SmoothingMode = 'AntiAlias'

        $p = New-JipegRoundPath 0 0 ($this.Width - 1) ($this.Height - 1) (Get-JipegScaled 5)
        $fill = New-Object System.Drawing.SolidBrush($face)
        $bg.FillPath($fill, $p); $fill.Dispose()
        $pen = New-Object System.Drawing.Pen($t.Edge, 1)
        $pen.Alignment = 'Inset'
        $bg.DrawPath($pen, $p); $pen.Dispose()

        if ($this.Focused -and (Test-JipegFocusCue $this)) {
            $ring = New-JipegRoundPath 1.0 1.0 ($this.Width - 3.0) ($this.Height - 3.0) (Get-JipegScaled 4)
            $rp = New-Object System.Drawing.Pen($t.Accent, 1.4)
            $rp.Alignment = 'Inset'
            $bg.DrawPath($rp, $ring); $rp.Dispose(); $ring.Dispose()
        }
        $p.Dispose(); $bg.Dispose()
        Copy-JipegCorners $buf
        $g.DrawImageUnscaled($buf, 0, 0)
        $buf.Dispose()
        $g.TextRenderingHint = 'ClearTypeGridFit'

        $ink = $(if ($this.Enabled) { $t.Text } else { $t.Muted })
        [System.Windows.Forms.TextRenderer]::DrawText($g, $this.Text, $this.Font,
            $this.ClientRectangle, $ink,
            ([System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor
             [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor
             [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor
             [System.Windows.Forms.TextFormatFlags]::NoPrefix))
    })
}

# Clips a control to a rounded rectangle. Used on the progress bar and its
# track so they read as pills, the way Windows 11 draws them.
# WinForms check boxes keep a white glyph in dark mode whatever BackColor says,
# and SetWindowTheme breaks them outright. FlatStyle draws the box from the
# control's own colours instead, which is the only combination that stays dark.
# Neither built-in style is presentable: Standard draws a white box when
# unticked, Flat an unreadable light one when ticked, and SetWindowTheme breaks
# the control outright. So the glyph is painted here. The control itself is
# still a real CheckBox, which keeps focus, Space, and accessibility.
function Set-JipegCheck($chk, $theme, $back = $null) {
    $chk.FlatStyle = 'Flat'
    $chk.FlatAppearance.BorderSize = 0
    # Opaque on purpose, taken from whatever it sits on. It has to erase what the
    # control drew for itself first: left transparent, the native caption shows
    # through underneath the one painted here and the text renders twice.
    if ($null -eq $back) { $back = $theme.Panel }
    $chk.BackColor = $back
    $chk.ForeColor = $theme.Text
    $chk.AutoSize  = $false
    $chk.Tag = $theme
    Set-JipegDoubleBuffer $chk

    # The font is pinned before measuring: an unparented control still reports the
    # default 9 pt, so measuring against it clipped the text once the control
    # inherited the form's 10 pt. Width hugs the text so the opaque strip does
    # not cut a band across the Mica background.
    $chk.Font = $JipegFont
    $measured = [System.Windows.Forms.TextRenderer]::MeasureText($chk.Text, $JipegFont)
    $chk.Width = (Get-JipegScaled 26) + $measured.Width + (Get-JipegScaled 8)

    $chk.Add_Paint({
        $t = $this.Tag
        $g = $_.Graphics
        # Cleared before smoothing is switched on: an antialiased FillRectangle
        # leaves its outermost row only partly covered, and over Mica the
        # backdrop shows through the gap as a faint line.
        if ($this.BackColor.A -ne 0) { $g.Clear($this.BackColor) }
        $g.SmoothingMode = 'AntiAlias'
        $g.TextRenderingHint = 'ClearTypeGridFit'

        # The box goes through a buffer of its own size so its four corners come
        # out identical; the tick is drawn afterwards, on the control, because a
        # check mark is not symmetric and mirroring would fold it in half.
        $side = Get-JipegScaled 18
        $top  = [int][math]::Floor(($this.Height - $side) / 2.0)
        $buf = New-Object System.Drawing.Bitmap($side, $side)
        $bg = [System.Drawing.Graphics]::FromImage($buf)
        $bg.Clear($this.BackColor)
        $bg.SmoothingMode = 'AntiAlias'
        $box = New-JipegRoundPath 0 0 ($side - 1.0) ($side - 1.0) (Get-JipegScaled 4)
        if ($this.Checked) {
            $fill = New-Object System.Drawing.SolidBrush($t.Accent)
            $bg.FillPath($fill, $box); $fill.Dispose()
        } else {
            $fill = New-Object System.Drawing.SolidBrush($t.Field)
            $bg.FillPath($fill, $box); $fill.Dispose()
            $pen = New-Object System.Drawing.Pen($t.CheckEdge, 1)
            $pen.Alignment = 'Inset'
            $bg.DrawPath($pen, $box); $pen.Dispose()
        }
        $box.Dispose(); $bg.Dispose()
        Copy-JipegCorners $buf
        $g.DrawImageUnscaled($buf, 0, $top)
        $buf.Dispose()

        if ($this.Checked) {
            $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 1.9)
            $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
            $tick = @(
                (New-Object System.Drawing.PointF(4.8, ($top + 9.2))),
                (New-Object System.Drawing.PointF(7.8, ($top + 12.4))),
                (New-Object System.Drawing.PointF(13.4, ($top + 5.6)))
            )
            $g.DrawLines($pen, $tick); $pen.Dispose()
        }

        $off = Get-JipegScaled 26
        $r = New-Object System.Drawing.Rectangle($off, 0, ($this.Width - $off), $this.Height)
        [System.Windows.Forms.TextRenderer]::DrawText($g, $this.Text, $this.Font, $r, $this.ForeColor,
            ([System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor
             [System.Windows.Forms.TextFormatFlags]::NoPrefix))
        # ControlPaint's focus rectangle is a hard black dotted box whatever the
        # theme, which on a dark surface reads as a scattering of black pixels.
        # A thin rounded outline in the accent colour says the same thing and
        # belongs to the design - but only when Windows is showing focus cues at
        # all. Drawn on plain focus, it appeared the moment the box was clicked:
        # a blue outline 236 pixels wide that no native control would have drawn.
        if ($this.Focused -and (Test-JipegFocusCue $this)) {
            $ring = New-JipegRoundPath 0 ($top - 3.0) ($this.Width - 1.0) ($side + 6.0) (Get-JipegScaled 5)
            $pen = New-Object System.Drawing.Pen($t.Accent, 1)
            $pen.Alignment = 'Inset'
            $g.DrawPath($pen, $ring)
            $pen.Dispose(); $ring.Dispose()
        }
    })
    $chk.Add_CheckedChanged({ $this.Invalidate() })
    $chk.Add_GotFocus({ $this.Invalidate() })
    $chk.Add_LostFocus({ $this.Invalidate() })
    $chk.Add_MouseEnter({ $this.Invalidate() })
    $chk.Add_MouseLeave({ $this.Invalidate() })
}

function New-JipegRoundPath([single]$x, [single]$y, [single]$w, [single]$h, [single]$radius) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = [math]::Min([double]$radius, [double][math]::Min($w, $h) / 2.0) * 2.0
    if ($d -le 0) {
        $path.AddRectangle((New-Object System.Drawing.RectangleF($x, $y, $w, $h)))
        return $path
    }
    $path.AddArc($x, $y, $d, $d, 180, 90)
    $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

function Set-JipegDoubleBuffer($ctrl) {
    $p = $ctrl.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance,NonPublic')
    if ($p) { $p.SetValue($ctrl, $true, $null) }
}

# Mica draws the desktop through the window. Its tint comes from the *system*
# light/dark setting, not ours, so it is only used when the two agree -
# otherwise a dark backdrop would sit behind light controls. Needs Windows 11
# 22H2 for the backdrop attribute, and a black client area as the glass key.
# Mica needs no colour compensation. What DWM lifts is the window background,
# which is erased by WinForms with no alpha and is meant to be glass: painted
# black, it comes back as #202020, and that is the material showing through.
# Every surface on top of it - cards, fields, check boxes - is filled with a GDI+
# brush, which writes opaque pixels: a card drawn #2B2B2B measures #2B2B2B with
# the backdrop on. An earlier build compensated for a lift that those surfaces
# never had, and only made them darker than they were picked.
function Test-JipegMica($theme) {
    if ([Environment]::OSVersion.Version.Build -lt 22621) { return $false }
    return ($theme.Dark -eq (Test-SystemDark))
}

# DWM keys the glass on black pixels, so the form background must be black and
# labels transparent. Nothing else in the UI is pure black, so nothing else
# disappears.
#
# The cost, measured rather than assumed: what GDI draws over the extended frame
# is composited additively onto the backdrop, so every colour lands lighter than
# it was specified. A card set to #2B2B2B measured #4B4B4B, a field set to
# #383838 measured #585858 - a flat +0x20 taken from whatever Mica had blurred
# behind the window. With the backdrop off, the same points measure #2B2B2B and
# #383838 exactly. So the translucency is real but the palette is no longer
# yours, and it drifts with the wallpaper. It is off unless asked for.
function Set-JipegMica($form, $theme) {
    if (-not (Test-JipegMica $theme)) { return $false }
    $type = 2                                    # DWMSBT_MAINWINDOW (Mica)
    if ([Jipeg.Win]::DwmSetWindowAttribute($form.Handle, 38, [ref]$type, 4) -ne 0) { return $false }
    $m = New-Object Jipeg.Win+MARGINS
    $m.Left = -1; $m.Right = -1; $m.Top = -1; $m.Bottom = -1
    if ([Jipeg.Win]::DwmExtendFrameIntoClientArea($form.Handle, [ref]$m) -ne 0) { return $false }
    return $true
}

function Format-JipegSize([double]$b) {
    if ($b -lt 1024)    { return ('{0} B' -f [int]$b) }
    if ($b -lt 1048576) { return ('{0:N0} KB' -f ($b / 1024)) }
    return ('{0:N1} MB' -f ($b / 1048576))
}

# ------------------------------------------------------------------ updates
# Only ever reports; downloading and running an installer unattended is not
# something this tool should do behind the user's back.
# Started without blocking the window; the caller polls IsCompleted from a timer.
function Start-JipegUpdateCheck {
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        $req = [System.Net.HttpWebRequest]::Create("https://api.github.com/repos/$JipegRepo/releases/latest")
        $req.UserAgent = 'Jipeg'
        $req.Timeout   = 8000
        return [pscustomobject]@{ Request = $req; Async = $req.BeginGetResponse($null, $null) }
    } catch { return $null }
}

function Complete-JipegUpdateCheck($state) {
    try {
        $resp = $state.Request.EndGetResponse($state.Async)
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $json = $reader.ReadToEnd()
        $reader.Close(); $resp.Close()
        $rel = $json | ConvertFrom-Json
        return (ConvertTo-JipegRelease $rel)
    } catch { return $null }
}

# Everything the quiet updater needs, including the checksum GitHub publishes
# for the asset, so a download can be rejected before anything is run.
function ConvertTo-JipegRelease($rel) {
    $asset = $rel.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
    $digest = ''
    if ($asset -and $asset.digest -and $asset.digest -match '^sha256:(?<h>[0-9a-fA-F]{64})$') {
        $digest = $Matches['h'].ToUpper()
    }
    $url = ''
    if ($asset) { $url = $asset.browser_download_url }
    return [pscustomobject]@{
        Tag      = ($rel.tag_name -replace '^v', '')
        Url      = $rel.html_url
        AssetUrl = $url
        Digest   = $digest
    }
}

function Get-JipegLatestRelease {
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        $req = [System.Net.HttpWebRequest]::Create("https://api.github.com/repos/$JipegRepo/releases/latest")
        $req.UserAgent = 'Jipeg'
        $req.Timeout   = 6000          # never leave the window frozen for long
        $resp = $req.GetResponse()
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $json = $reader.ReadToEnd()
        $reader.Close(); $resp.Close()
        $rel = $json | ConvertFrom-Json
        return (ConvertTo-JipegRelease $rel)
    } catch { return $null }
}

function Compare-JipegVersion([string]$a, [string]$b) {
    try {
        $va = [version]($a -replace '[^0-9.]', '')
        $vb = [version]($b -replace '[^0-9.]', '')
        return $va.CompareTo($vb)
    } catch { return 0 }
}
