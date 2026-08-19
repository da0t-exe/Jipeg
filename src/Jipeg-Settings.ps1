<#
  Jipeg settings — the only window with any options in it.
  Opened from the Start menu; the converter just reads what is saved here.
#>
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $Root 'Jipeg-Common.ps1')
[System.Windows.Forms.Application]::EnableVisualStyles()

$Settings = Get-JipegSettings
$Theme    = Get-JipegTheme $Settings.theme
$Bold     = New-Object System.Drawing.Font($JipegFont, [System.Drawing.FontStyle]::Bold)
$Mica     = ($Settings.mica -and (Test-JipegMica $Theme))

function Quality-Label([int]$q) {
    if ($q -ge 99) { return "$q - maximum, very large files" }
    if ($q -ge 95) { return "$q - visually lossless" }
    if ($q -ge 92) { return "$q - very high quality" }
    if ($q -eq 90) { return "$q - high quality (default)" }
    if ($q -ge 84) { return "$q - balanced" }
    if ($q -ge 78) { return "$q - light, for the web" }
    if ($q -ge 70) { return "$q - strong compression" }
    return "$q - very strong compression"
}

# ------------------------------------------------------------------- window
$form = New-Object System.Windows.Forms.Form
$form.Text            = 'Jipeg Settings'
$form.FormBorderStyle = 'FixedDialog'
$form.StartPosition   = 'CenterScreen'
$form.ClientSize      = New-Object System.Drawing.Size(480, 500)
$form.MaximizeBox     = $false
$form.MinimizeBox     = $false
$form.ForeColor       = $Theme.Text
$form.Font            = $JipegFont
if ($Mica) { $form.BackColor = [System.Drawing.Color]::Black } else { $form.BackColor = $Theme.Back }
$form.Add_HandleCreated({
    Set-JipegChrome $form $Theme
    if ($Mica) { [void](Set-JipegMica $form $Theme) }
})
$icoPath = Join-Path $Root 'jipeg.ico'
if (Test-Path -LiteralPath $icoPath) { try { $form.Icon = New-Object System.Drawing.Icon($icoPath) } catch { } }

function New-Section([string]$text, [int]$y) {
    $l = New-Object System.Windows.Forms.Label
    $l.SetBounds(16, $y, 400, 18)
    $l.Font = $Bold
    $l.ForeColor = $Theme.Text
    $l.Text = $text
    Set-JipegLabel $l $Theme $Mica
    $form.Controls.Add($l)
}
function New-Card([int]$y, [int]$h) {
    $c = New-Object System.Windows.Forms.Panel
    $c.SetBounds(16, $y, 448, $h)
    $c.BackColor = $Theme.Panel
    $form.Controls.Add($c)
    Set-JipegRounded $c 8
    return $c
}
function New-Hint([string]$text, [int]$x, [int]$y, [int]$w, $parent) {
    $l = New-Object System.Windows.Forms.Label
    $l.SetBounds($x, $y, $w, 18)
    $l.ForeColor = $Theme.Muted
    $l.Text = $text
    $parent.Controls.Add($l)
    return $l
}

# --------------------------------------------------------------- conversion
New-Section 'Conversion' 14
$card1 = New-Card 36 120

$lblQ = New-Object System.Windows.Forms.Label
$lblQ.SetBounds(16, 16, 160, 20)
$lblQ.ForeColor = $Theme.Text
$lblQ.Text = 'JPEG quality'
$card1.Controls.Add($lblQ)

# A drop-down list, not a spin box: NumericUpDown ignores BackColor and stays
# white in dark mode, which is exactly the bright patch we are avoiding.
$QualityValues = @(100, 96, 92, 90, 85, 80, 78, 70, 60)
$cmbQ = New-Object System.Windows.Forms.ComboBox
$cmbQ.SetBounds(196, 13, 236, 24)
$cmbQ.DropDownStyle = 'DropDownList'
$cmbQ.FlatStyle = 'Flat'
$cmbQ.BackColor = $Theme.Field
$cmbQ.ForeColor = $Theme.Text
foreach ($v in $QualityValues) { [void]$cmbQ.Items.Add((Quality-Label $v)) }
$saved = [int]$Settings.quality
if ($QualityValues -notcontains $saved) {
    [void]$cmbQ.Items.Add((Quality-Label $saved))
    $QualityValues += $saved
}
$cmbQ.SelectedIndex = [array]::IndexOf($QualityValues, $saved)
$card1.Controls.Add($cmbQ)

[void](New-Hint 'Higher keeps more detail and makes bigger files.' 16 42 416 $card1)

$chk444 = New-Object System.Windows.Forms.CheckBox
$chk444.SetBounds(16, 68, 416, 20)
$chk444.Text = 'Keep full colour detail (4:4:4)'
$chk444.Checked = [bool]$Settings.chroma444
Set-JipegCheck $chk444 $Theme
$card1.Controls.Add($chk444)
[void](New-Hint 'Better for screenshots, text and sharp colour edges. Larger files.' 34 90 398 $card1)

# --------------------------------------------------------------- appearance
New-Section 'Appearance' 170
$card2 = New-Card 192 104

$lblT = New-Object System.Windows.Forms.Label
$lblT.SetBounds(16, 16, 200, 20)
$lblT.ForeColor = $Theme.Text
$lblT.Text = 'Theme'
$card2.Controls.Add($lblT)

$cmbT = New-Object System.Windows.Forms.ComboBox
$cmbT.SetBounds(272, 13, 160, 24)
$cmbT.DropDownStyle = 'DropDownList'
$cmbT.FlatStyle = 'Flat'
$cmbT.BackColor = $Theme.Field
$cmbT.ForeColor = $Theme.Text
[void]$cmbT.Items.AddRange(@('Follow Windows', 'Light', 'Dark'))
$cmbT.SelectedIndex = switch ($Settings.theme) { 'light' { 1 } 'dark' { 2 } default { 0 } }
$card2.Controls.Add($cmbT)

[void](New-Hint 'Changing this takes effect the next time a window opens.' 16 44 416 $card2)

$chkMica = New-Object System.Windows.Forms.CheckBox
$chkMica.SetBounds(16, 70, 416, 20)
$chkMica.Text = 'Translucent window background (Mica)'
$chkMica.Checked = [bool]$Settings.mica
Set-JipegCheck $chkMica $Theme
$card2.Controls.Add($chkMica)

# ------------------------------------------------------------------ finish
New-Section 'When a conversion finishes' 310
$card3 = New-Card 332 66

$chkClose = New-Object System.Windows.Forms.CheckBox
$chkClose.SetBounds(16, 12, 416, 20)
$chkClose.Text = 'Close the window automatically'
$chkClose.Checked = [bool]$Settings.closeWhenDone
Set-JipegCheck $chkClose $Theme
$card3.Controls.Add($chkClose)
[void](New-Hint 'Otherwise the result stays on screen until you click OK.' 34 34 398 $card3)

# ----------------------------------------------------------------- version
$lblVer = New-Object System.Windows.Forms.Label
$lblVer.SetBounds(16, 414, 240, 18)
$lblVer.ForeColor = $Theme.Text
$lblVer.Text = "Jipeg $JipegVersion"
Set-JipegLabel $lblVer $Theme $Mica
$form.Controls.Add($lblVer)

$lblUpd = New-Object System.Windows.Forms.Label
$lblUpd.SetBounds(16, 434, 290, 18)
$lblUpd.ForeColor = $Theme.Muted
$lblUpd.Text = ''
Set-JipegLabel $lblUpd $Theme $Mica
$form.Controls.Add($lblUpd)

$btnUpd = New-Object System.Windows.Forms.Button
$btnUpd.SetBounds(314, 410, 150, 28)
$btnUpd.Text = 'Check for updates'
Set-JipegButton $btnUpd $Theme
$form.Controls.Add($btnUpd)
Set-JipegRounded $btnUpd 5

$script:NewUrl = $null
$btnUpd.Add_Click({
    if ($script:NewUrl) { Start-Process $script:NewUrl; return }
    $btnUpd.Enabled = $false
    $lblUpd.Text = 'Checking...'
    $lblUpd.ForeColor = $Theme.Muted
    $form.Refresh()
    $rel = Get-JipegLatestRelease
    if (-not $rel) {
        $lblUpd.Text = 'Could not reach GitHub.'
    } elseif ((Compare-JipegVersion $rel.Tag $JipegVersion) -gt 0) {
        $lblUpd.Text = "Version $($rel.Tag) is available."
        $lblUpd.ForeColor = $Theme.Text
        $script:NewUrl = $rel.Url
        $btnUpd.Text = 'Open download page'
    } else {
        $lblUpd.Text = 'You have the latest version.'
    }
    $btnUpd.Enabled = $true
})

# --------------------------------------------------------------- OK/Cancel
$btnOK = New-Object System.Windows.Forms.Button
$btnOK.SetBounds(276, 454, 90, 30)
$btnOK.Text = 'OK'
Set-JipegButton $btnOK $Theme
$form.Controls.Add($btnOK)
Set-JipegRounded $btnOK 5

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.SetBounds(374, 454, 90, 30)
$btnCancel.Text = 'Cancel'
Set-JipegButton $btnCancel $Theme
$btnCancel.Add_Click({ $form.Close() })
$form.Controls.Add($btnCancel)
Set-JipegRounded $btnCancel 5
$form.AcceptButton = $btnOK
$form.CancelButton = $btnCancel

$btnOK.Add_Click({
    $Settings.quality       = [int]$QualityValues[$cmbQ.SelectedIndex]
    $Settings.chroma444     = [bool]$chk444.Checked
    $Settings.closeWhenDone = [bool]$chkClose.Checked
    $Settings.mica          = [bool]$chkMica.Checked
    $Settings.theme         = switch ($cmbT.SelectedIndex) { 1 { 'light' } 2 { 'dark' } default { 'auto' } }
    try {
        Save-JipegSettings $Settings
    } catch {
        [void][System.Windows.Forms.MessageBox]::Show(
            "Settings could not be saved.`n`n" + $_.Exception.Message, 'Jipeg', 'OK', 'Error')
        return
    }
    $form.Close()
})

$form.Add_Shown({
    Show-JipegWindow $form
    $form.ActiveControl = $btnOK   # no control opens pre-highlighted
})
[System.Windows.Forms.Application]::Run($form)
