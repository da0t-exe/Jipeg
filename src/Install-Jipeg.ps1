<#
  Installs Jipeg for the current user:
    - copies cjpegli.exe and the scripts to %LOCALAPPDATA%\Jipeg
    - adds "Convert to JPEG (Jipeg)" to the image context menu
    - adds a Start menu shortcut for the settings window
  No administrator rights. Nothing is written outside the user profile.
#>
param([switch]$Silent, [switch]$ClassicMenu)

$ErrorActionPreference = 'Stop'
$Here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$Project = Split-Path -Parent $Here
. (Join-Path $Here 'Jipeg-Common.ps1')
[System.Windows.Forms.Application]::EnableVisualStyles()

$Dest   = Join-Path $env:LOCALAPPDATA 'Jipeg'
$ZipUrl = 'https://github.com/libjxl/libjxl/releases/download/v0.11.1/jxl-x64-windows-static.zip'
$ZipSha = '8F53EBCE91820C30C9FC9294F06380213C1E2E66B361718880580246B2BE008E'
$Verb   = 'Convert to JPEG (Jipeg)'

$Exts = @('.png', '.apng', '.jpg', '.jpeg', '.jpe', '.gif', '.bmp', '.tif', '.tiff',
          '.jxl', '.ppm', '.pnm', '.pgm', '.pam', '.pfm')

# --------------------------------------------------------------------- icon
function New-JipegIcon([string]$outPath) {
    $sizes = @(16, 24, 32, 48, 64, 128, 256)
    $plate = [System.Drawing.Color]::FromArgb(255, 74, 123, 232)
    $ink   = [System.Drawing.Color]::White
    $frames = @()

    # The JPEG mark: a square with its bottom-right corner taken out, and the
    # piece that was removed set down beside it. The notch is painted back over
    # the square and allowed to overrun the right and bottom edges, so only its
    # inner corner is rounded - the detail that makes the cut look deliberate.
    function Add-RoundRect($graphics, $brush, [single]$x, [single]$y, [single]$w, [single]$h, [single]$radius) {
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $d = [math]::Min([double]$radius, [double][math]::Min($w, $h) / 2.0) * 2.0
        if ($d -le 0.4) {
            $path.AddRectangle((New-Object System.Drawing.RectangleF($x, $y, $w, $h)))
        } else {
            $path.AddArc($x, $y, $d, $d, 180, 90)
            $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
            $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
            $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
            $path.CloseFigure()
        }
        $graphics.FillPath($brush, $path)
        $path.Dispose()
    }

    foreach ($s in $sizes) {
        $bmp = New-Object System.Drawing.Bitmap($s, $s)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = 'AntiAlias'

        $pb = New-Object System.Drawing.SolidBrush($plate)
        $ib = New-Object System.Drawing.SolidBrush($ink)

        Add-RoundRect $g $pb 0 0 $s $s ($s * 0.20)                     # the plate

        $side = $s * 0.410
        $r    = $side * 0.10
        Add-RoundRect $g $ib ($s * 0.215) ($s * 0.295) $side $side $r  # the square

        $nx = $s * 0.455
        $ny = $s * 0.535
        $over = $s * 0.07
        Add-RoundRect $g $pb $nx $ny (($s * 0.625) - $nx + $over) (($s * 0.705) - $ny + $over) $r

        $piece = $s * 0.145
        Add-RoundRect $g $ib ($s * 0.645) ($s * 0.550) $piece $piece ($piece * 0.10)

        $pb.Dispose(); $ib.Dispose(); $g.Dispose()
        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        $frames += , $ms.ToArray()
    }

    $out = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($out)
    $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$frames.Count)
    $offset = 6 + 16 * $frames.Count
    for ($i = 0; $i -lt $frames.Count; $i++) {
        $dim = $sizes[$i]; if ($dim -ge 256) { $dim = 0 }
        $bw.Write([byte]$dim); $bw.Write([byte]$dim); $bw.Write([byte]0); $bw.Write([byte]0)
        $bw.Write([uint16]1); $bw.Write([uint16]32)
        $bw.Write([uint32]$frames[$i].Length); $bw.Write([uint32]$offset)
        $offset += $frames[$i].Length
    }
    foreach ($f in $frames) { $bw.Write($f) }
    $bw.Flush()
    [System.IO.File]::WriteAllBytes($outPath, $out.ToArray())
    $bw.Dispose(); $out.Dispose()
}

# -------------------------------------------------------------------- steps
function Get-Cjpegli([scriptblock]$report) {
    $local = Join-Path $Project 'bin\cjpegli.exe'
    if (Test-Path -LiteralPath $local) {
        & $report 'Copying cjpegli.exe'
        Copy-Item -LiteralPath $local -Destination (Join-Path $Dest 'bin\cjpegli.exe') -Force
        return
    }
    & $report 'Downloading libjxl 0.11.1 (~50 MB)'
    $zip = Join-Path $env:TEMP 'jxl-jpegli.zip'
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($ZipUrl, $zip)
    $wc.Dispose()
    & $report 'Verifying SHA-256'
    if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $ZipSha) {
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        throw 'The downloaded archive does not match the expected checksum.'
    }
    & $report 'Extracting cjpegli.exe'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $arch = [System.IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $entry = $arch.Entries | Where-Object { $_.Name -eq 'cjpegli.exe' } | Select-Object -First 1
        if (-not $entry) { throw 'cjpegli.exe is missing from the archive.' }
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $Dest 'bin\cjpegli.exe'), $true)
        foreach ($lic in ($arch.Entries | Where-Object { $_.Name -like 'LICENSE*' })) {
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($lic, (Join-Path $Dest "bin\$($lic.Name)"), $true)
        }
    } finally { $arch.Dispose() }
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
}

function Set-ContextMenu([string]$icon) {
    $cmd = 'wscript.exe "{0}" "%1"' -f (Join-Path $Dest 'launch.vbs')
    foreach ($e in $Exts) {
        $key = "HKCU:\Software\Classes\SystemFileAssociations\$e\shell\JipegConvert"
        New-Item -Path $key -Force | Out-Null
        New-Item -Path "$key\command" -Force | Out-Null
        Set-ItemProperty -Path $key -Name 'MUIVerb'          -Value $Verb
        Set-ItemProperty -Path $key -Name 'Icon'             -Value $icon
        Set-ItemProperty -Path $key -Name 'MultiSelectModel' -Value 'Player'
        Set-ItemProperty -Path "$key\command" -Name '(default)' -Value $cmd
    }
    $key = 'HKCU:\Software\Classes\Directory\shell\JipegConvert'
    New-Item -Path $key -Force | Out-Null
    New-Item -Path "$key\command" -Force | Out-Null
    Set-ItemProperty -Path $key -Name 'MUIVerb' -Value 'Convert images to JPEG (Jipeg)'
    Set-ItemProperty -Path $key -Name 'Icon'    -Value $icon
    Set-ItemProperty -Path "$key\command" -Name '(default)' -Value (
        'wscript.exe "{0}" "%V"' -f (Join-Path $Dest 'launch.vbs'))
}

function Set-StartMenuShortcut([string]$icon) {
    $lnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Jipeg Settings.lnk'
    $sh = New-Object -ComObject WScript.Shell
    $s = $sh.CreateShortcut($lnk)
    $s.TargetPath       = 'wscript.exe'
    $s.Arguments        = '"{0}"' -f (Join-Path $Dest 'settings.vbs')
    $s.WorkingDirectory = $Dest
    $s.IconLocation     = $icon
    $s.Description      = 'Jipeg settings'
    $s.Save()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($sh) | Out-Null
}

function Set-UninstallEntry([string]$icon) {
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Jipeg'
    New-Item -Path $key -Force | Out-Null
    Set-ItemProperty -Path $key -Name 'DisplayName'     -Value 'Jipeg'
    Set-ItemProperty -Path $key -Name 'DisplayVersion'  -Value $JipegVersion
    Set-ItemProperty -Path $key -Name 'Publisher'       -Value 'Jipeg'
    Set-ItemProperty -Path $key -Name 'DisplayIcon'     -Value $icon
    Set-ItemProperty -Path $key -Name 'InstallLocation' -Value $Dest
    Set-ItemProperty -Path $key -Name 'NoModify'        -Value 1 -Type DWord
    Set-ItemProperty -Path $key -Name 'NoRepair'        -Value 1 -Type DWord
    Set-ItemProperty -Path $key -Name 'UninstallString' -Value (
        'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $Dest 'Uninstall-Jipeg.ps1'))
}

function Invoke-Install([scriptblock]$report, [bool]$classicMenu) {
    & $report 'Creating the install folder'
    New-Item -ItemType Directory -Path (Join-Path $Dest 'bin') -Force | Out-Null
    Get-Cjpegli $report
    & $report 'Installing Jipeg'
    foreach ($f in @('Jipeg-Common.ps1', 'Jipeg-Convert.ps1', 'Jipeg-Settings.ps1',
                     'Uninstall-Jipeg.ps1', 'launch.vbs', 'settings.vbs')) {
        Copy-Item -LiteralPath (Join-Path $Here $f) -Destination $Dest -Force
    }
    $licSrc = Join-Path $Project 'bin'
    if (Test-Path $licSrc) {
        Get-ChildItem -LiteralPath $licSrc -Filter 'LICENSE*' -ErrorAction SilentlyContinue |
            ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Dest 'bin') -Force }
    }
    & $report 'Drawing the icon'
    $icon = Join-Path $Dest 'jipeg.ico'
    New-JipegIcon $icon
    & $report 'Adding the context menu entry'
    Set-ContextMenu $icon
    Set-StartMenuShortcut $icon
    Set-UninstallEntry $icon
    if ($classicMenu) {
        $k = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
        $already = $false
        try {
            if (Test-Path -LiteralPath $k) {
                $current = (Get-ItemProperty -LiteralPath $k -Name '(default)' -ErrorAction SilentlyContinue).'(default)'
                $already = ($null -ne $current -and $current -eq '')
            }
        } catch { }

        if ($already) {
            # Nothing to change, so nothing to restart. Reinstalling used to cost
            # a few seconds of blank taskbar rewriting the same value. The
            # uninstall marker stays unset on purpose: the setting was not ours,
            # so removing Jipeg must not take it away.
            & $report 'Classic context menu already on, leaving Explorer alone'
        } else {
            & $report 'Restoring the classic context menu'
            New-Item -Path $k -Force | Out-Null
            Set-ItemProperty -Path $k -Name '(default)' -Value ''
            Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Jipeg' `
                             -Name 'ClassicMenuSet' -Value 1 -Type DWord
            & $report 'Restarting Explorer'
            Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 800
            if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
        }
    }
    & $report 'Done'
}

if ($Silent) {
    Invoke-Install { param($m) Write-Host "  $m" } ([bool]$ClassicMenu)
    exit 0
}

# ------------------------------------------------------------------- window
$Theme = Get-JipegTheme 'auto'
$Mica  = Test-JipegMica $Theme

$form = New-Object System.Windows.Forms.Form
$form.Text            = 'Install Jipeg'
$form.FormBorderStyle = 'FixedDialog'
$form.StartPosition   = 'CenterScreen'
$form.ClientSize      = New-Object System.Drawing.Size(520, 282)
$form.MaximizeBox     = $false
$form.MinimizeBox     = $false
$form.ForeColor       = $Theme.Text
$form.Font            = $JipegFont
if ($Mica) { $form.BackColor = [System.Drawing.Color]::Black } else { $form.BackColor = $Theme.Back }
# On a first install the icon does not exist yet, so draw one for this window.
$tempIcon = Join-Path $env:TEMP ('jipeg-setup-{0}.ico' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
try { New-JipegIcon $tempIcon; $form.Icon = New-Object System.Drawing.Icon($tempIcon) } catch { }

$form.Add_HandleCreated({
    Set-JipegChrome $form $Theme
    if ($Mica) { [void](Set-JipegMica $form $Theme) }
})

$lbl1 = New-Object System.Windows.Forms.Label
$lbl1.SetBounds(20, 20, 480, 44)
$lbl1.ForeColor = $Theme.Text
$lbl1.Font = $JipegFont
$Quote1 = [char]0x201C
$Quote2 = [char]0x201D
$lbl1.Text = 'Jipeg adds {0}{1}{2} to the right-click menu on images and converts them with Google''s jpegli encoder.' -f $Quote1, $Verb, $Quote2
Set-JipegLabel $lbl1 $Theme $Mica
$form.Controls.Add($lbl1)

$lbl2 = New-Object System.Windows.Forms.Label
$lbl2.SetBounds(20, 72, 480, 40)
$lbl2.Font = $JipegFontHint
$lbl2.ForeColor = $Theme.Muted
$lbl2.Text = "Installs to: $Dest" + [Environment]::NewLine + 'No administrator rights required.'
Set-JipegLabel $lbl2 $Theme $Mica
$form.Controls.Add($lbl2)

$IsWin11 = ([Environment]::OSVersion.Version.Build -ge 22000)
$chk = New-Object System.Windows.Forms.CheckBox
$chk.SetBounds(20, 124, 480, 22)
$chk.AutoSize = $true   # la bande opaque epouse le texte au lieu de barrer le Mica
$chk.Checked = $IsWin11
$chk.Enabled = $IsWin11
$chk.Text = 'Show the entry directly in the right-click menu'
Set-JipegCheck $chk $Theme $Theme.Back
if (-not $IsWin11) { $chk.Text = 'Classic context menu - not needed on this Windows'; $chk.ForeColor = $Theme.Muted }
$form.Controls.Add($chk)

$lblChk = New-Object System.Windows.Forms.Label
$lblChk.SetBounds(44, 150, 456, 56)
$lblChk.Font = $JipegFontHint
$lblChk.ForeColor = $Theme.Muted
$lblChk.Text = ('Otherwise Windows 11 hides it under {0}Show more options{1}.' -f $Quote1, $Quote2) +
               [Environment]::NewLine + 'Explorer restarts: the taskbar and any open folders' +
               [Environment]::NewLine + 'close, and come back after a few seconds.'
if (-not $IsWin11) { $lblChk.Text = 'Your Windows already shows the full menu.' }
Set-JipegLabel $lblChk $Theme $Mica
$form.Controls.Add($lblChk)

$lblState = New-Object System.Windows.Forms.Label
$lblState.SetBounds(20, 234, 260, 22)
$lblState.Font = $JipegFontHint
$lblState.ForeColor = $Theme.Muted
Set-JipegLabel $lblState $Theme $Mica
$form.Controls.Add($lblState)

$btnGo = New-Object System.Windows.Forms.Button
$btnGo.SetBounds(520 - 20 - 100 - 8 - 100, 230, 100, 32)
$btnGo.Text = 'Install'
Set-JipegButton $btnGo $Theme
$form.Controls.Add($btnGo)
Set-JipegRounded $btnGo 5

$btnNo = New-Object System.Windows.Forms.Button
$btnNo.SetBounds(520 - 20 - 100, 230, 100, 32)
$btnNo.Text = 'Cancel'
Set-JipegButton $btnNo $Theme
$btnNo.Add_Click({ $form.Close() })
$form.Controls.Add($btnNo)
Set-JipegRounded $btnNo 5
$form.CancelButton = $btnNo
$form.AcceptButton = $btnGo

$btnGo.Add_Click({
    $btnGo.Enabled = $false; $btnNo.Enabled = $false; $chk.Enabled = $false
    $form.Cursor = 'WaitCursor'
    try {
        Invoke-Install {
            param($m)
            $lblState.Text = $m
            $lblState.Refresh()
        } ([bool]$chk.Checked)
        $form.Cursor = 'Default'
        [void][System.Windows.Forms.MessageBox]::Show(
            'Jipeg is installed.' + [Environment]::NewLine + [Environment]::NewLine +
            "Right-click an image   →   $Verb",
            'Jipeg', 'OK', 'Information')
        $form.Close()
    } catch {
        $form.Cursor = 'Default'
        $lblState.Text = ''
        [void][System.Windows.Forms.MessageBox]::Show(
            'The installation failed.' + [Environment]::NewLine + [Environment]::NewLine + $_.Exception.Message,
            'Jipeg', 'OK', 'Error')
        $btnGo.Enabled = $true; $btnNo.Enabled = $true; $chk.Enabled = $IsWin11
    }
})

$form.Add_Shown({ Show-JipegWindow $form })
[System.Windows.Forms.Application]::Run($form)
