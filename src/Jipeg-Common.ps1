<#
  Shared helpers for Jipeg: settings storage, theming and a few Win32 calls.
  Dot-sourced by Jipeg-Convert.ps1 and Jipeg-Settings.ps1.
#>

$JipegVersion = '1.7.0'
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

$JipegSettingsPath = Join-Path (Join-Path $env:LOCALAPPDATA 'Jipeg') 'settings.json' 

# Bumped when the meaning of a stored value changes, so an older file can be
# brought forward instead of being thrown away or misread.
$JipegSchema = 1

function Get-JipegDefaults {
    return [pscustomobject]@{
        schema        = $JipegSchema
        writtenBy     = $JipegVersion
        theme         = 'auto'      # auto | light | dark
        quality       = 90          # libjpeg scale, 1..100
        chroma444     = $false      # keep full colour detail (bigger files)
        closeWhenDone = $false      # dismiss the progress window automatically
        mica          = $true       # translucent Mica window background
        autoUpdate    = $true       # fetch and install newer releases quietly
        lastCheck     = 0           # ticks of the last update check
        lastUpdate    = ''          # what the last quiet update did
    }
}

# Settings survive an upgrade: unknown keys from a newer build are ignored,
# missing ones take today's default, and anything whose meaning changed is
# rewritten here rather than silently misread.
function Update-JipegSchema($s) {
    if ($null -eq $s.schema) { $s.schema = 0 }
    # (no migrations yet - schema 1 is the first stamped format)
    $s.schema = $JipegSchema
    return $s
}

function Get-JipegSettings {
    $s = Get-JipegDefaults
    try {
        if (Test-Path -LiteralPath $JipegSettingsPath) {
            $raw = Get-Content -LiteralPath $JipegSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $s.PSObject.Properties.Name) {
                if ($null -ne $raw.$p) { $s.$p = $raw.$p }
            }
        }
    } catch { }   # a corrupt file must never stop a conversion
    $s = Update-JipegSchema $s
    if ($s.quality -lt 1 -or $s.quality -gt 100) { $s.quality = 90 }
    if ('auto', 'light', 'dark' -notcontains $s.theme) { $s.theme = 'auto' }
    return $s
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
        Button  = [System.Drawing.SystemColors]::Control
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

$JipegFont        = New-Object System.Drawing.Font($JipegFamily, 10.0)   # labels, body
$JipegFontHint    = New-Object System.Drawing.Font($JipegFamily, 8.75)   # explanations
$JipegFontSection = New-JipegSemibold 11.25                              # section headings
$JipegFontBold    = New-JipegSemibold 10.0                               # emphasis in body
$JipegFontBig     = New-JipegSemibold 15.0                               # the one number that matters

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
        # a border, or the list melts into whatever is behind it
        $edge = ($theme.CardEdge.B -shl 16) -bor ($theme.CardEdge.G -shl 8) -bor $theme.CardEdge.R
        [void][Jipeg.Win]::DwmSetWindowAttribute($lb, 34, [ref]$edge, 4)
    } catch { }
}

function Set-JipegLabel($lbl, $theme, [bool]$mica) {
    if ($mica) { $lbl.BackColor = [System.Drawing.Color]::Transparent }
}

function Set-JipegButton($b, $theme) {
    $b.Font = $JipegFont
    if ($theme.Dark) {
        $b.FlatStyle = 'Flat'
        $b.BackColor = $theme.Button
        $b.ForeColor = $theme.Text
        $b.FlatAppearance.BorderColor = $theme.Edge
    }
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
    $chk.Width = 26 + $measured.Width + 8

    $chk.Add_Paint({
        $t = $this.Tag
        $g = $_.Graphics
        $g.SmoothingMode = 'AntiAlias'
        $g.TextRenderingHint = 'ClearTypeGridFit'
        if ($this.BackColor.A -ne 0) {
            $b = New-Object System.Drawing.SolidBrush($this.BackColor)
            $g.FillRectangle($b, $this.ClientRectangle); $b.Dispose()
        }

        $side = 18.0
        $top  = [math]::Floor(($this.Height - $side) / 2.0)
        $box  = New-JipegRoundPath 0.5 ($top + 0.5) ($side - 1.0) ($side - 1.0) 4
        if ($this.Checked) {
            $fill = New-Object System.Drawing.SolidBrush($t.Accent)
            $g.FillPath($fill, $box); $fill.Dispose()
            $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 1.9)
            $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
            $tick = @(
                (New-Object System.Drawing.PointF(4.8, ($top + 9.2))),
                (New-Object System.Drawing.PointF(7.8, ($top + 12.4))),
                (New-Object System.Drawing.PointF(13.4, ($top + 5.6)))
            )
            $g.DrawLines($pen, $tick); $pen.Dispose()
        } else {
            $fill = New-Object System.Drawing.SolidBrush($t.Field)
            $g.FillPath($fill, $box); $fill.Dispose()
            $pen = New-Object System.Drawing.Pen($t.CheckEdge, 1)
            $g.DrawPath($pen, $box); $pen.Dispose()
        }
        $box.Dispose()

        $r = New-Object System.Drawing.Rectangle(26, 0, ($this.Width - 26), $this.Height)
        [System.Windows.Forms.TextRenderer]::DrawText($g, $this.Text, $this.Font, $r, $this.ForeColor,
            ([System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor
             [System.Windows.Forms.TextFormatFlags]::NoPrefix))
        if ($this.Focused) {
            $ring = New-Object System.Drawing.Rectangle(0, ($top - 2), ($this.Width - 1), ($side + 4))
            [System.Windows.Forms.ControlPaint]::DrawFocusRectangle($g, $ring)
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
function Test-JipegMica($theme) {
    if ([Environment]::OSVersion.Version.Build -lt 22621) { return $false }
    return ($theme.Dark -eq (Test-SystemDark))
}

# DWM keys the glass on black pixels, so the form background must be black and
# labels transparent. Nothing else in the UI is pure black, so nothing else
# disappears.
function Set-JipegMica($form, $theme) {
    if (-not (Test-JipegMica $theme)) { return $false }
    $type = 2                                    # DWMSBT_MAINWINDOW (Mica)
    if ([Jipeg.Win]::DwmSetWindowAttribute($form.Handle, 38, [ref]$type, 4) -ne 0) { return $false }
    $m = New-Object Jipeg.Win+MARGINS
    $m.Left = -1; $m.Right = -1; $m.Top = -1; $m.Bottom = -1
    if ([Jipeg.Win]::DwmExtendFrameIntoClientArea($form.Handle, [ref]$m) -ne 0) { return $false }
    return $true
}

function Set-JipegRounded($ctrl, [single]$radius) {
    $w = $ctrl.Width; $h = $ctrl.Height
    if ($w -le 0 -or $h -le 0) { return }
    $path = New-JipegRoundPath 0 0 $w $h $radius
    $ctrl.Region = New-Object System.Drawing.Region($path)
    $path.Dispose()
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
