<#
  Shared helpers for Jipeg: settings storage, theming and a few Win32 calls.
  Dot-sourced by Jipeg-Convert.ps1 and Jipeg-Settings.ps1.
#>

$JipegVersion = '1.2.1'
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
'@ -Name 'Win' -Namespace 'Jipeg' | Out-Null

# ------------------------------------------------------------------ settings
$JipegSettingsPath = Join-Path (Join-Path $env:LOCALAPPDATA 'Jipeg') 'settings.json'

function Get-JipegDefaults {
    return [pscustomobject]@{
        theme         = 'auto'      # auto | light | dark
        quality       = 90          # libjpeg scale, 1..100
        chroma444     = $false      # keep full colour detail (bigger files)
        closeWhenDone = $false      # dismiss the progress window automatically
        mica          = $true       # translucent Mica window background
    }
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
    if ($s.quality -lt 1 -or $s.quality -gt 100) { $s.quality = 90 }
    if ('auto', 'light', 'dark' -notcontains $s.theme) { $s.theme = 'auto' }
    return $s
}

function Save-JipegSettings($s) {
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
            Muted   = [System.Drawing.Color]::FromArgb(160, 160, 160)
            Button  = [System.Drawing.Color]::FromArgb(45, 45, 45)
            Edge    = [System.Drawing.Color]::FromArgb(70, 70, 70)
            Track   = [System.Drawing.Color]::FromArgb(58, 58, 58)
            Field   = [System.Drawing.Color]::FromArgb(45, 45, 45)
            Accent  = Get-JipegAccent $true
        }
    }
    return @{
        Dark    = $false
        Back    = [System.Drawing.Color]::FromArgb(243, 243, 243)
        Panel   = [System.Drawing.Color]::FromArgb(251, 251, 251)
        Text    = [System.Drawing.Color]::FromArgb(26, 26, 26)
        Muted   = [System.Drawing.Color]::FromArgb(93, 93, 93)
        Button  = [System.Drawing.SystemColors]::Control
        Edge    = [System.Drawing.Color]::FromArgb(205, 205, 205)
        Track   = [System.Drawing.Color]::FromArgb(222, 222, 222)
        Field   = [System.Drawing.Color]::FromArgb(255, 255, 255)
        Accent  = Get-JipegAccent $false
    }
}

$JipegFont = [System.Drawing.SystemFonts]::MessageBoxFont

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
function Set-JipegCheck($chk, $theme, $back = $null) {
    $chk.ForeColor = $theme.Text
    if (-not $theme.Dark) { return }
    $chk.FlatStyle = 'Flat'
    # never transparent: the flat renderer fills the glyph from BackColor, and a
    # transparent one comes out as a solid white square
    if ($null -eq $back) { $back = $theme.Panel }
    $chk.BackColor = $back
    # FlatAppearance.CheckedBackColor has no effect on the glyph, so a ticked box
    # stays light with a dark tick. Unticked is the common state and this is the
    # only style that keeps it dark.
    $chk.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(140, 140, 140)
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
        return [pscustomobject]@{
            Tag     = ($rel.tag_name -replace '^v', '')
            Url     = $rel.html_url
            Name    = $rel.name
        }
    } catch { return $null }
}

function Compare-JipegVersion([string]$a, [string]$b) {
    try {
        $va = [version]($a -replace '[^0-9.]', '')
        $vb = [version]($b -replace '[^0-9.]', '')
        return $va.CompareTo($vb)
    } catch { return 0 }
}
