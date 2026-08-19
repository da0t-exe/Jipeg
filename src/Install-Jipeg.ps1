<#
  Installe Jipeg pour l'utilisateur courant :
    - copie cjpegli.exe et le convertisseur dans %LOCALAPPDATA%\Jipeg
    - ajoute « Convertir en JPEG (Jipeg) » au menu contextuel des images
  Aucun droit administrateur. Rien n'est ecrit hors du profil utilisateur.
#>
param([switch]$Silent)

$ErrorActionPreference = 'Stop'
[void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
[void][System.Reflection.Assembly]::LoadWithPartialName('System.Drawing')
[System.Windows.Forms.Application]::EnableVisualStyles()

$Here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$Project = Split-Path -Parent $Here
$Dest    = Join-Path $env:LOCALAPPDATA 'Jipeg'
$ZipUrl  = 'https://github.com/libjxl/libjxl/releases/download/v0.11.1/jxl-x64-windows-static.zip'
$ZipSha  = '8F53EBCE91820C30C9FC9294F06380213C1E2E66B361718880580246B2BE008E'
$Verbe   = 'Convertir en JPEG (Jipeg)'

$Exts = @('.png', '.apng', '.jpg', '.jpeg', '.jpe', '.gif', '.bmp', '.tif', '.tiff',
          '.jxl', '.ppm', '.pnm', '.pgm', '.pam', '.pfm')

# ---------------------------------------------------------------- icone
function New-JipegIcon([string]$outPath) {
    $sizes = @(16, 24, 32, 48, 64, 128, 256)
    $bleu  = [System.Drawing.Color]::FromArgb(255, 74, 123, 232)
    $frames = @()
    foreach ($s in $sizes) {
        $bmp = New-Object System.Drawing.Bitmap($s, $s)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
        $r = [math]::Max(2, $s * 0.23)
        $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
        $d = $r * 2
        $gp.AddArc(0, 0, $d, $d, 180, 90)
        $gp.AddArc($s - $d, 0, $d, $d, 270, 90)
        $gp.AddArc($s - $d, $s - $d, $d, $d, 0, 90)
        $gp.AddArc(0, $s - $d, $d, $d, 90, 90)
        $gp.CloseFigure()
        $br = New-Object System.Drawing.SolidBrush($bleu)
        $g.FillPath($br, $gp); $br.Dispose(); $gp.Dispose()
        $font = New-Object System.Drawing.Font('Segoe UI', ($s * 0.6), [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
        $wb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $g.DrawString('J', $font, $wb, (New-Object System.Drawing.RectangleF(0, ($s * -0.04), $s, $s)), $sf)
        $wb.Dispose(); $font.Dispose(); $sf.Dispose(); $g.Dispose()
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

# ---------------------------------------------------------------- etapes
function Get-Cjpegli([scriptblock]$report) {
    $local = Join-Path $Project 'bin\cjpegli.exe'
    if (Test-Path -LiteralPath $local) {
        & $report 'Copie de cjpegli.exe'
        Copy-Item -LiteralPath $local -Destination (Join-Path $Dest 'bin\cjpegli.exe') -Force
        return
    }
    & $report 'Téléchargement de libjxl 0.11.1 (~50 Mo)'
    $zip = Join-Path $env:TEMP 'jxl-jpegli.zip'
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($ZipUrl, $zip)
    $wc.Dispose()
    & $report 'Vérification de l''empreinte SHA-256'
    if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $ZipSha) {
        Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
        throw "L'archive téléchargée ne correspond pas à l'empreinte attendue."
    }
    & $report 'Extraction de cjpegli.exe'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $arch = [System.IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $entry = $arch.Entries | Where-Object { $_.Name -eq 'cjpegli.exe' } | Select-Object -First 1
        if (-not $entry) { throw 'cjpegli.exe est absent de l''archive.' }
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
        Set-ItemProperty -Path $key -Name 'MUIVerb'          -Value $Verbe
        Set-ItemProperty -Path $key -Name 'Icon'             -Value $icon
        Set-ItemProperty -Path $key -Name 'MultiSelectModel' -Value 'Player'
        Set-ItemProperty -Path "$key\command" -Name '(default)' -Value $cmd
    }
    $key = 'HKCU:\Software\Classes\Directory\shell\JipegConvert'
    New-Item -Path $key -Force | Out-Null
    New-Item -Path "$key\command" -Force | Out-Null
    Set-ItemProperty -Path $key -Name 'MUIVerb' -Value 'Convertir les images en JPEG (Jipeg)'
    Set-ItemProperty -Path $key -Name 'Icon'    -Value $icon
    Set-ItemProperty -Path "$key\command" -Name '(default)' -Value (
        'wscript.exe "{0}" "%V"' -f (Join-Path $Dest 'launch.vbs'))
}

function Set-UninstallEntry([string]$icon) {
    $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Jipeg'
    New-Item -Path $key -Force | Out-Null
    Set-ItemProperty -Path $key -Name 'DisplayName'     -Value 'Jipeg'
    Set-ItemProperty -Path $key -Name 'DisplayVersion'  -Value '1.0'
    Set-ItemProperty -Path $key -Name 'Publisher'       -Value 'Jipeg'
    Set-ItemProperty -Path $key -Name 'DisplayIcon'     -Value $icon
    Set-ItemProperty -Path $key -Name 'InstallLocation' -Value $Dest
    Set-ItemProperty -Path $key -Name 'NoModify'        -Value 1 -Type DWord
    Set-ItemProperty -Path $key -Name 'NoRepair'        -Value 1 -Type DWord
    Set-ItemProperty -Path $key -Name 'UninstallString' -Value (
        'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $Dest 'Uninstall-Jipeg.ps1'))
}

function Invoke-Install([scriptblock]$report, [bool]$menuClassique) {
    & $report 'Création du dossier'
    New-Item -ItemType Directory -Path (Join-Path $Dest 'bin') -Force | Out-Null
    Get-Cjpegli $report
    & $report 'Installation du convertisseur'
    Copy-Item -LiteralPath (Join-Path $Here 'Jipeg-Convert.ps1')   -Destination $Dest -Force
    Copy-Item -LiteralPath (Join-Path $Here 'launch.vbs')          -Destination $Dest -Force
    Copy-Item -LiteralPath (Join-Path $Here 'Uninstall-Jipeg.ps1') -Destination $Dest -Force
    $licSrc = Join-Path $Project 'bin'
    if (Test-Path $licSrc) {
        Get-ChildItem -LiteralPath $licSrc -Filter 'LICENSE*' -ErrorAction SilentlyContinue |
            ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Dest 'bin') -Force }
    }
    & $report 'Génération de l''icône'
    $icon = Join-Path $Dest 'jipeg.ico'
    New-JipegIcon $icon
    & $report 'Ajout au menu contextuel'
    Set-ContextMenu $icon
    Set-UninstallEntry $icon
    if ($menuClassique) {
        & $report 'Menu contextuel classique'
        $k = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
        New-Item -Path $k -Force | Out-Null
        Set-ItemProperty -Path $k -Name '(default)' -Value ''
        Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Jipeg' `
                         -Name 'ClassicMenuSet' -Value 1 -Type DWord
        & $report 'Redémarrage de l''Explorateur'
        Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 800
        if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
    }
    & $report 'Terminé'
}

if ($Silent) {
    Invoke-Install { param($m) Write-Host "  $m" } $false
    Write-Host "`nJipeg installé dans $Dest" -ForegroundColor Green
    exit 0
}

# =================================================================== fenetre
function Test-DarkMode {
    try {
        return ((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' `
                 -Name AppsUseLightTheme -ErrorAction Stop).AppsUseLightTheme -eq 0)
    } catch { return $false }
}
Add-Type -MemberDefinition @'
[DllImport("dwmapi.dll")] public static extern int  DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int cmd);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
'@ -Name 'Dwm' -Namespace 'JipegSetup' | Out-Null

$Dark = Test-DarkMode
if ($Dark) {
    $ColBack  = [System.Drawing.Color]::FromArgb(32, 32, 32)
    $ColText  = [System.Drawing.Color]::FromArgb(255, 255, 255)
    $ColMuted = [System.Drawing.Color]::FromArgb(160, 160, 160)
    $ColBtn   = [System.Drawing.Color]::FromArgb(45, 45, 45)
    $ColEdge  = [System.Drawing.Color]::FromArgb(70, 70, 70)
} else {
    $ColBack  = [System.Drawing.SystemColors]::Control
    $ColText  = [System.Drawing.SystemColors]::ControlText
    $ColMuted = [System.Drawing.SystemColors]::GrayText
    $ColBtn   = [System.Drawing.SystemColors]::Control
    $ColEdge  = [System.Drawing.SystemColors]::ControlDark
}
$UiFont = [System.Drawing.SystemFonts]::MessageBoxFont

$form = New-Object System.Windows.Forms.Form
$form.Text            = 'Installation de Jipeg'
$form.FormBorderStyle = 'FixedDialog'
$form.StartPosition   = 'CenterScreen'
$form.ClientSize      = New-Object System.Drawing.Size(470, 250)
$form.MaximizeBox     = $false
$form.MinimizeBox     = $false
$form.BackColor       = $ColBack
$form.ForeColor       = $ColText
$form.Font            = $UiFont
$form.Add_HandleCreated({
    if ($Dark) {
        $on = 1
        if ([JipegSetup.Dwm]::DwmSetWindowAttribute($form.Handle, 20, [ref]$on, 4) -ne 0) {
            [void][JipegSetup.Dwm]::DwmSetWindowAttribute($form.Handle, 19, [ref]$on, 4)
        }
    }
})

$lbl1 = New-Object System.Windows.Forms.Label
$lbl1.SetBounds(16, 16, 438, 40)
$lbl1.ForeColor = $ColText
$lbl1.Text = "Jipeg ajoute « $Verbe » au menu du clic droit sur les images, et convertit avec l'encodeur jpegli de Google."
$form.Controls.Add($lbl1)

$lbl2 = New-Object System.Windows.Forms.Label
$lbl2.SetBounds(16, 62, 438, 36)
$lbl2.ForeColor = $ColMuted
$lbl2.Text = "Destination : $Dest" + [Environment]::NewLine + "Aucun droit administrateur requis."
$form.Controls.Add($lbl2)

$IsWin11 = ([Environment]::OSVersion.Version.Build -ge 22000)
$chk = New-Object System.Windows.Forms.CheckBox
$chk.SetBounds(16, 106, 438, 22)
$chk.ForeColor = $ColText
$chk.Checked = $IsWin11
$chk.Enabled = $IsWin11
$chk.Text = "Afficher l'entrée directement dans le menu du clic droit"
if (-not $IsWin11) { $chk.Text = "Menu contextuel classique — inutile sur ce Windows"; $chk.ForeColor = $ColMuted }
$form.Controls.Add($chk)

$lblChk = New-Object System.Windows.Forms.Label
$lblChk.SetBounds(35, 128, 419, 34)
$lblChk.ForeColor = $ColMuted
$lblChk.Text = "Sinon, Windows 11 la range sous « Afficher plus d'options »." + [Environment]::NewLine +
               "L'Explorateur redémarre brièvement."
if (-not $IsWin11) { $lblChk.Text = "Ton Windows affiche déjà le menu complet." }
$form.Controls.Add($lblChk)

$lblEtat = New-Object System.Windows.Forms.Label
$lblEtat.SetBounds(16, 206, 210, 20)
$lblEtat.ForeColor = $ColMuted
$form.Controls.Add($lblEtat)

function Style-Button($b) {
    $b.Font = $UiFont
    if ($Dark) {
        $b.FlatStyle = 'Flat'
        $b.BackColor = $ColBtn
        $b.ForeColor = $ColText
        $b.FlatAppearance.BorderColor = $ColEdge
    }
}
$btnGo = New-Object System.Windows.Forms.Button
$btnGo.SetBounds(470 - 16 - 96 - 8 - 110, 200, 110, 30)
$btnGo.Text = 'Installer'
Style-Button $btnGo
$form.Controls.Add($btnGo)

$btnNo = New-Object System.Windows.Forms.Button
$btnNo.SetBounds(470 - 16 - 96, 200, 96, 30)
$btnNo.Text = 'Annuler'
Style-Button $btnNo
$btnNo.Add_Click({ $form.Close() })
$form.Controls.Add($btnNo)
$form.CancelButton = $btnNo
$form.AcceptButton = $btnGo

$btnGo.Add_Click({
    $btnGo.Enabled = $false; $btnNo.Enabled = $false; $chk.Enabled = $false
    $form.Cursor = 'WaitCursor'
    try {
        Invoke-Install {
            param($m)
            $lblEtat.Text = $m
            $lblEtat.Refresh()
        } ([bool]$chk.Checked)
        $form.Cursor = 'Default'
        [void][System.Windows.Forms.MessageBox]::Show(
            "Jipeg est installé." + [Environment]::NewLine + [Environment]::NewLine +
            "Clic droit sur une image  →  $Verbe",
            'Jipeg', 'OK', 'Information')
        $form.Close()
    } catch {
        $form.Cursor = 'Default'
        $lblEtat.Text = ''
        [void][System.Windows.Forms.MessageBox]::Show(
            "L'installation a échoué." + [Environment]::NewLine + [Environment]::NewLine + $_.Exception.Message,
            'Jipeg', 'OK', 'Error')
        $btnGo.Enabled = $true; $btnNo.Enabled = $true; $chk.Enabled = $IsWin11
    }
})

$form.Add_Shown({
    # meme precaution : le .bat lance PowerShell fenetre cachee
    [void][JipegSetup.Dwm]::ShowWindow($form.Handle, 1)
    [void][JipegSetup.Dwm]::SetForegroundWindow($form.Handle)
})
[System.Windows.Forms.Application]::Run($form)
