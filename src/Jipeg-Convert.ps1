<#
  Jipeg — convertit des images en JPEG avec l'encodeur jpegli.
  Lance par le menu contextuel de l'Explorateur. Aucune fenetre de reglages :
  une simple boite de progression aux couleurs de Windows, puis le resultat.
#>
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Paths)

$ErrorActionPreference = 'Stop'
[void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')
[void][System.Reflection.Assembly]::LoadWithPartialName('System.Drawing')
[System.Windows.Forms.Application]::EnableVisualStyles()

$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$Cjpegli = Join-Path $Root 'bin\cjpegli.exe'
$Quality = 90          # equivalent libjpeg ; 90 = haute qualite, bon defaut
$Suffixe = '_jipeg'

$NativeExt = @('.png', '.apng', '.jpg', '.jpeg', '.jpe', '.gif', '.jxl',
               '.ppm', '.pnm', '.pgm', '.pam', '.pfm', '.pgx')
$GdiExt    = @('.bmp', '.tif', '.tiff', '.ico', '.emf', '.wmf')
$AllExt    = $NativeExt + $GdiExt

# ------------------------------------------------------------------ entrees
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

# ----------------------------------------------------- selection multiple
# L'Explorateur lance une instance par fichier selectionne. La premiere garde un
# verrou pendant toute sa vie ; les suivantes deposent leurs chemins dans une file
# et rendent la main, l'instance vivante les recupere et les ajoute au lot.
$QueueFile = Join-Path $env:TEMP 'jipeg.queue'
$LockFile  = Join-Path $env:TEMP 'jipeg.lock'
$Mutex     = New-Object System.Threading.Mutex($false, 'Local\JipegQueue')
$script:LockFs = $null
$Files = New-Object System.Collections.Generic.List[string]

function Open-Lock {
    try { return [System.IO.File]::Open($LockFile, 'CreateNew', 'Write', 'None') } catch { }
    try { return [System.IO.File]::Open($LockFile, 'Open', 'Write', 'None') } catch { }   # verrou orphelin
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

if (-not $script:LockFs) { exit }          # une conversion tourne deja, elle prendra le relais
Start-Sleep -Milliseconds 700              # laisse arriver le reste de la selection
foreach ($f in @(Read-Queue)) { if ($Files -notcontains $f) { $Files.Add($f) } }

if ($Files.Count -eq 0) {
    if ($script:LockFs) { $script:LockFs.Close(); Remove-Item -LiteralPath $LockFile -Force -ErrorAction SilentlyContinue }
    exit
}
if (-not (Test-Path -LiteralPath $Cjpegli)) {
    [void][System.Windows.Forms.MessageBox]::Show(
        "cjpegli.exe est introuvable :`n$Cjpegli`n`nRelance l'installation de Jipeg.",
        'Jipeg', 'OK', 'Error')
    exit 1
}

# ------------------------------------------------------------------ theme
function Test-DarkMode {
    try {
        $v = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' `
              -Name AppsUseLightTheme -ErrorAction Stop).AppsUseLightTheme
        return ($v -eq 0)
    } catch { return $false }
}
Add-Type -MemberDefinition @'
[DllImport("dwmapi.dll")] public static extern int  DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int cmd);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
[DllImport("uxtheme.dll", CharSet=CharSet.Unicode)] public static extern int SetWindowTheme(IntPtr hwnd, string sub, string id);
'@ -Name 'Dwm' -Namespace 'Jipeg' | Out-Null

$Dark = Test-DarkMode
if ($Dark) {
    $ColBack   = [System.Drawing.Color]::FromArgb(32, 32, 32)
    $ColText   = [System.Drawing.Color]::FromArgb(255, 255, 255)
    $ColMuted  = [System.Drawing.Color]::FromArgb(160, 160, 160)
    $ColBtn    = [System.Drawing.Color]::FromArgb(45, 45, 45)
    $ColBtnHi  = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $ColBorder = [System.Drawing.Color]::FromArgb(70, 70, 70)
    $ColPiste  = [System.Drawing.Color]::FromArgb(58, 58, 58)
} else {
    $ColBack   = [System.Drawing.SystemColors]::Control
    $ColText   = [System.Drawing.SystemColors]::ControlText
    $ColMuted  = [System.Drawing.SystemColors]::GrayText
    $ColBtn    = [System.Drawing.SystemColors]::Control
    $ColBtnHi  = [System.Drawing.SystemColors]::ControlLight
    $ColBorder = [System.Drawing.SystemColors]::ControlDark
    $ColPiste  = [System.Drawing.SystemColors]::Control
}
$UiFont = [System.Drawing.SystemFonts]::MessageBoxFont

# ------------------------------------------------------------------ outils
function Format-Size([double]$b) {
    if ($b -lt 1024)    { return ('{0} o' -f [int]$b) }
    if ($b -lt 1048576) { return ('{0:N0} Ko' -f ($b / 1024)) }
    return ('{0:N1} Mo' -f ($b / 1048576))
}
function Get-FreePath([string]$dir, [string]$base, [string]$ext) {
    $p = Join-Path $dir ($base + $ext)
    $i = 1
    while (Test-Path -LiteralPath $p) { $p = Join-Path $dir ('{0} ({1}){2}' -f $base, $i, $ext); $i++ }
    return $p
}

# ----------------------------------------------------------------- fenetre
$form = New-Object System.Windows.Forms.Form
$form.Text            = 'Jipeg'
$form.FormBorderStyle = 'FixedDialog'
$form.StartPosition   = 'CenterScreen'
$form.ClientSize      = New-Object System.Drawing.Size(430, 158)
$form.MaximizeBox     = $false
$form.MinimizeBox     = $false
$form.ShowInTaskbar   = $true
$form.BackColor       = $ColBack
$form.ForeColor       = $ColText
$form.Font            = $UiFont
$form.Add_HandleCreated({
    if ($Dark) {
        $on = 1
        # 20 = DWMWA_USE_IMMERSIVE_DARK_MODE (Windows 11 / 10 20H1+), 19 sur les builds anterieurs
        if ([Jipeg.Dwm]::DwmSetWindowAttribute($form.Handle, 20, [ref]$on, 4) -ne 0) {
            [void][Jipeg.Dwm]::DwmSetWindowAttribute($form.Handle, 19, [ref]$on, 4)
        }
    }
})

$lblTitre = New-Object System.Windows.Forms.Label
$lblTitre.SetBounds(16, 16, 398, 20)
$lblTitre.ForeColor = $ColText
$lblTitre.Text = 'Préparation…'
$form.Controls.Add($lblTitre)

$lblFichier = New-Object System.Windows.Forms.Label
$lblFichier.SetBounds(16, 38, 398, 18)
$lblFichier.ForeColor = $ColMuted
$lblFichier.AutoEllipsis = $true
$form.Controls.Add($lblFichier)

# En sombre, la cuvette native de la ProgressBar est blanche. Le theme
# DarkMode_Explorer la rend transparente : on pose donc le controle sur un
# panneau qui fournit la piste, et l'on garde le vrai controle Windows.
$piste = New-Object System.Windows.Forms.Panel
$piste.SetBounds(16, 64, 398, 12)
$piste.BackColor = $ColPiste
$form.Controls.Add($piste)

$bar = New-Object System.Windows.Forms.ProgressBar
$bar.SetBounds(0, 0, 398, 12)
$bar.Style = 'Continuous'
$bar.Minimum = 0
$bar.Maximum = [math]::Max(1, $Files.Count)
$piste.Controls.Add($bar)

$lblBilan = New-Object System.Windows.Forms.Label
$lblBilan.SetBounds(16, 86, 398, 18)
$lblBilan.ForeColor = $ColMuted
$form.Controls.Add($lblBilan)

$btn = New-Object System.Windows.Forms.Button
$btn.SetBounds(430 - 16 - 96, 114, 96, 30)
$btn.Text = 'Annuler'
$btn.Font = $UiFont
if ($Dark) {
    $btn.FlatStyle = 'Flat'
    $btn.BackColor = $ColBtn
    $btn.ForeColor = $ColText
    $btn.FlatAppearance.BorderColor = $ColBorder
    $btn.FlatAppearance.MouseOverBackColor = $ColBtnHi
}
$form.Controls.Add($btn)
$form.CancelButton = $btn

# ----------------------------------------------------------------- moteur
$script:Index    = 0
$script:Ok       = 0
$script:Echecs   = 0
$script:TotalIn  = 0
$script:TotalOut = 0
$script:Annule   = $false
$script:Fini     = $false
$script:Proc     = $null
$script:TmpIn    = $null
$script:TmpOut   = $null
$script:Courant  = $null

function Set-Etat {
    $n = $Files.Count
    $lblTitre.Text = if ($n -eq 1) { 'Conversion en JPEG…' } else { "Conversion en JPEG… ($($script:Index) sur $n)" }
    $bar.Value = [math]::Min($bar.Maximum, $script:Index)
}

function Start-Suivant {
    if ($script:Annule -or $script:Index -ge $Files.Count) { Complete-Batch; return }
    $src = $Files[$script:Index]
    $script:Courant = $src
    $lblFichier.Text = [System.IO.Path]::GetFileName($src)
    Set-Etat
    try {
        $ext = [System.IO.Path]::GetExtension($src).ToLower()
        $entree = $src
        $script:TmpIn = $null
        if ($GdiExt -contains $ext) {
            # format que cjpegli ne lit pas : passage intermediaire en PNG
            $tmpPng = Join-Path $env:TEMP ('jipeg-in-{0}.png' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
            $fs = [System.IO.File]::OpenRead($src)
            try {
                $img = [System.Drawing.Image]::FromStream($fs, $true, $false)
                try { $img.Save($tmpPng, [System.Drawing.Imaging.ImageFormat]::Png) } finally { $img.Dispose() }
            } finally { $fs.Close() }
            $entree = $tmpPng; $script:TmpIn = $tmpPng
        }
        $dir = Split-Path -Parent $src
        $script:TmpOut = Join-Path $dir ('.jipeg-{0}.tmp' -f [guid]::NewGuid().ToString('N').Substring(0, 8))

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName               = $Cjpegli
        $psi.Arguments              = '"{0}" "{1}" -q {2}' -f $entree, $script:TmpOut, $Quality
        $psi.UseShellExecute        = $false
        $psi.CreateNoWindow         = $true
        $psi.RedirectStandardError  = $true
        $psi.RedirectStandardOutput = $true
        $script:Proc = [System.Diagnostics.Process]::Start($psi)
    } catch {
        $script:Echecs++
        $script:Index++
        $script:Proc = $null
        Start-Suivant
    }
}

function Complete-Courant {
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
            $dir  = Split-Path -Parent $script:Courant
            $base = [System.IO.Path]::GetFileNameWithoutExtension($script:Courant)
            $cible = Get-FreePath $dir ($base + $Suffixe) '.jpg'
            Move-Item -LiteralPath $script:TmpOut -Destination $cible -Force
            $script:TotalIn  += (Get-Item -LiteralPath $script:Courant).Length
            $script:TotalOut += (Get-Item -LiteralPath $cible).Length
            $script:Ok++
        } catch { $script:Echecs++ }
    } else {
        Remove-Item -LiteralPath $script:TmpOut -Force -ErrorAction SilentlyContinue
        $script:Echecs++
    }
    $script:TmpOut = $null
    $script:Index++
}

function Resume-Batch {
    # des fichiers sont arrives apres la fin du lot : on repart
    $script:Fini = $false
    $sortie.Stop()
    $btn.Text = 'Annuler'
    $lblBilan.Text = ''
    $bar.Maximum = [math]::Max(1, $Files.Count)
    Set-Etat
    $chrono.Start()
}

function Complete-Batch {
    if ($script:Fini) { return }
    $script:Fini = $true
    $chrono.Stop()
    $bar.Value = $bar.Maximum

    if ($script:Ok -gt 0) {
        $pc = 0
        if ($script:TotalIn -gt 0) { $pc = [math]::Round(100 - ($script:TotalOut * 100 / $script:TotalIn)) }
        $signe = [char]0x2212
        if ($pc -lt 0) { $signe = '+'; $pc = [math]::Abs($pc) }
        $lblBilan.Text = '{0} {1} {2}   ({3}{4} %)' -f (Format-Size $script:TotalIn), ([char]0x2192),
                                                       (Format-Size $script:TotalOut), $signe, $pc
    }
    $mot = 'images converties'
    if ($script:Ok -eq 1) { $mot = 'image convertie' }
    if ($script:Annule) {
        $lblTitre.Text = "Annulé — $($script:Ok) $mot"
    } elseif ($script:Echecs -gt 0) {
        $ech = 'échecs'; if ($script:Echecs -eq 1) { $ech = 'échec' }
        $lblTitre.Text = "$($script:Ok) $mot, $($script:Echecs) $ech"
    } else {
        $lblTitre.Text = "$($script:Ok) $mot"
    }
    $lblFichier.Text = ''
    $btn.Text = 'Fermer'

    # on ferme tout seul quand tout s'est bien passe ; sinon on laisse lire
    if (-not $script:Annule -and $script:Echecs -eq 0) {
        $sortie.Start()
    }
}

$chrono = New-Object System.Windows.Forms.Timer
$chrono.Interval = 50
$chrono.Add_Tick({
    if ($script:Proc -and -not $script:Proc.HasExited) { return }
    if ($script:Proc) { Complete-Courant }
    Start-Suivant
})

# recupere les fichiers deposes par les instances lancees apres nous
$veille = New-Object System.Windows.Forms.Timer
$veille.Interval = 600
$veille.Add_Tick({
    try {
        $neufs = @(Read-Queue)
        $ajoutes = 0
        foreach ($f in $neufs) {
            if ($Files -notcontains $f) { $Files.Add($f); $ajoutes++ }
        }
        if ($ajoutes -eq 0) { return }
        if ($script:Fini) { Resume-Batch } else { $bar.Maximum = [math]::Max(1, $Files.Count); Set-Etat }
    } catch { }
})

$sortie = New-Object System.Windows.Forms.Timer
$sortie.Interval = 1300
$sortie.Add_Tick({ $sortie.Stop(); $form.Close() })

$btn.Add_Click({
    if ($script:Fini) { $form.Close(); return }
    $script:Annule = $true
    $btn.Enabled = $false
    $lblTitre.Text = 'Annulation…'
})

$form.Add_Shown({
    # wscript lance PowerShell fenetre cachee ; Windows transmet ce SW_HIDE a la
    # premiere fenetre du processus. On impose donc l'affichage nous-memes.
    [void][Jipeg.Dwm]::ShowWindow($form.Handle, 1)          # SW_SHOWNORMAL
    [void][Jipeg.Dwm]::SetForegroundWindow($form.Handle)
    if ($Dark) { [void][Jipeg.Dwm]::SetWindowTheme($bar.Handle, 'DarkMode_Explorer', $null) }
    $chrono.Start()
    $veille.Start()
})
$form.Add_FormClosed({
    $chrono.Stop(); $veille.Stop(); $sortie.Stop()
    try {
        $tardifs = @(Read-Queue) | Where-Object { $Files -notcontains $_ }
        if ($tardifs.Count -gt 0) {
            $vbs = Join-Path $Root 'launch.vbs'
            if (Test-Path -LiteralPath $vbs) {
                $argv = @('"' + $vbs + '"') + ($tardifs | ForEach-Object { '"' + $_ + '"' })
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
})

[System.Windows.Forms.Application]::Run($form)
