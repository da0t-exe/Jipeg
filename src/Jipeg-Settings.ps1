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
$Mica     = ($Settings.mica -and (Test-JipegMica $Theme))

# Everything sits on a 4-pixel grid: 20 outside the window, 16 inside a card.
$W        = 540
$Margin   = 20
$CardW    = $W - 2 * $Margin
$Pad      = 16
$InnerW   = $CardW - 2 * $Pad
$FieldW   = 280
$FieldX   = $CardW - $Pad - $FieldW

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
$form.ClientSize      = New-Object System.Drawing.Size($W, 608)
$form.MaximizeBox     = $false
$form.MinimizeBox     = $false
$form.ForeColor       = $Theme.Text
$form.Font            = $JipegFont
if ($Mica) { $form.BackColor = [System.Drawing.Color]::Black } else { $form.BackColor = $Theme.Back }
Set-JipegDoubleBuffer $form
Set-JipegIcon $form $Root
$form.Add_HandleCreated({
    Set-JipegChrome $form $Theme
    if ($Mica) { [void](Set-JipegMica $form $Theme) }
})

function New-Section([string]$text, [int]$y) {
    $l = New-Object System.Windows.Forms.Label
    $l.SetBounds($Margin, $y, 400, 22)
    $l.Font = $JipegFontSection
    $l.ForeColor = $Theme.Text
    $l.Text = $text
    Set-JipegLabel $l $Theme $Mica
    $form.Controls.Add($l)
}

# A card is a surface, so it gets an edge. Without one it reads as a smudge on
# the translucent background rather than something laid on top of it.
function New-Card([int]$y, [int]$h) {
    $c = New-Object System.Windows.Forms.Panel
    $c.SetBounds($Margin, $y, $CardW, $h)
    $c.BackColor = $Theme.Panel
    Set-JipegDoubleBuffer $c
    $c.Add_Paint({
        $g = $_.Graphics
        $g.SmoothingMode = 'AntiAlias'
        $p = New-JipegRoundPath 0.5 0.5 ($this.Width - 1) ($this.Height - 1) 8
        $pen = New-Object System.Drawing.Pen($Theme.CardEdge, 1)
        $g.DrawPath($pen, $p)
        $pen.Dispose(); $p.Dispose()
    })
    $form.Controls.Add($c)
    Set-JipegRounded $c 8
    return $c
}

function New-Label([string]$text, [int]$x, [int]$y, [int]$w, $parent) {
    $l = New-Object System.Windows.Forms.Label
    $l.SetBounds($x, $y, $w, 22)
    $l.ForeColor = $Theme.Text
    $l.Text = $text
    $parent.Controls.Add($l)
    return $l
}

function New-Hint([string]$text, [int]$x, [int]$y, [int]$w, $parent) {
    $l = New-Object System.Windows.Forms.Label
    $l.SetBounds($x, $y, $w, 18)
    $l.Font = $JipegFontHint
    $l.ForeColor = $Theme.Muted
    $l.Text = $text
    $parent.Controls.Add($l)
    return $l
}

# The list items are drawn so they follow the theme instead of the system's
# default dropdown. The control is still a real ComboBox: it simply sits in a
# frame narrower than itself, so the grey system arrow button falls outside and
# is clipped away, and a chevron is drawn in its place.
function New-Combo([int]$y, $parent) {
    $frame = New-Object System.Windows.Forms.Panel
    $frame.SetBounds($FieldX, $y, $FieldW, 26)
    $frame.BackColor = $Theme.Field
    $parent.Controls.Add($frame)
    Set-JipegRounded $frame 4

    # A ComboBox ignores the height you give it: it is always ItemHeight + 6. So
    # ItemHeight is chosen to make the control taller than the frame, and the
    # control is offset on every side, which puts its pale system border outside
    # the frame where the clip removes it. The frame's fill is the only edge left.
    $c = New-Object System.Windows.Forms.ComboBox
    $c.SetBounds(-2, -3, ($FieldW + 30), 32)
    $c.DropDownStyle = 'DropDownList'
    $c.FlatStyle = 'Flat'
    $c.BackColor = $Theme.Field
    $c.ForeColor = $Theme.Text
    $c.Font = $JipegFont
    $c.DrawMode = 'OwnerDrawFixed'
    $c.ItemHeight = 26
    $c.DropDownWidth = $FieldW
    $c.Add_DrawItem({
        $e = $_
        $g = $e.Graphics
        $isClosed = (($e.State -band [System.Windows.Forms.DrawItemState]::ComboBoxEdit) -ne 0)
        $back = $Theme.Field
        if (-not $isClosed -and (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0)) {
            $back = $Theme.Accent
        }
        $b = New-Object System.Drawing.SolidBrush($back)
        $g.FillRectangle($b, $e.Bounds)
        $b.Dispose()
        if ($e.Index -ge 0) {
            $right = 10
            if ($isClosed) { $right = 34 }
            $r = New-Object System.Drawing.Rectangle(
                ($e.Bounds.X + 8), $e.Bounds.Y, ($e.Bounds.Width - $right), $e.Bounds.Height)
            [System.Windows.Forms.TextRenderer]::DrawText(
                $g, $this.Items[$e.Index].ToString(), $JipegFont, $r, $Theme.Text,
                ([System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor
                 [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor
                 [System.Windows.Forms.TextFormatFlags]::NoPrefix))
        }
        if ($isClosed) {
            $g.SmoothingMode = 'AntiAlias'
            $pen = New-Object System.Drawing.Pen($Theme.Muted, 1.6)
            $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
            $cx = $FieldW - 14.0
            $cy = $e.Bounds.Y + $e.Bounds.Height / 2.0
            $pts = @(
                (New-Object System.Drawing.PointF(($cx - 4.0), ($cy - 2.0))),
                (New-Object System.Drawing.PointF($cx, ($cy + 2.5))),
                (New-Object System.Drawing.PointF(($cx + 4.0), ($cy - 2.0)))
            )
            $g.DrawLines($pen, $pts)
            $pen.Dispose()
        }
    })
    $frame.Controls.Add($c)
    return $c
}

# --------------------------------------------------------------- conversion
New-Section 'Conversion' 20
$card1 = New-Card 50 132

[void](New-Label 'JPEG quality' $Pad 16 160 $card1)
$QualityValues = @(100, 96, 92, 90, 85, 80, 78, 70, 60)
$cmbQ = New-Combo 14 $card1
foreach ($v in $QualityValues) { [void]$cmbQ.Items.Add((Quality-Label $v)) }
$saved = [int]$Settings.quality
if ($QualityValues -notcontains $saved) {
    [void]$cmbQ.Items.Add((Quality-Label $saved))
    $QualityValues += $saved
}
$cmbQ.SelectedIndex = [array]::IndexOf($QualityValues, $saved)

[void](New-Hint 'Higher keeps more detail and makes bigger files.' $Pad 46 $InnerW $card1)

$chk444 = New-Object System.Windows.Forms.CheckBox
$chk444.SetBounds($Pad, 74, $InnerW, 22)
$chk444.Text = 'Keep full colour detail (4:4:4)'
$chk444.Checked = [bool]$Settings.chroma444
Set-JipegCheck $chk444 $Theme
$card1.Controls.Add($chk444)
[void](New-Hint 'Better for screenshots, text and sharp colour edges. Larger files.' ($Pad + 20) 98 ($InnerW - 20) $card1)

# --------------------------------------------------------------- appearance
New-Section 'Appearance' 202
$card2 = New-Card 232 112

[void](New-Label 'Theme' $Pad 16 160 $card2)
$cmbT = New-Combo 14 $card2
[void]$cmbT.Items.AddRange(@('Follow Windows', 'Light', 'Dark'))
$cmbT.SelectedIndex = switch ($Settings.theme) { 'light' { 1 } 'dark' { 2 } default { 0 } }

[void](New-Hint 'Takes effect the next time a window opens.' $Pad 46 $InnerW $card2)

$chkMica = New-Object System.Windows.Forms.CheckBox
$chkMica.SetBounds($Pad, 74, $InnerW, 22)
$chkMica.Text = 'Translucent window background (Mica)'
$chkMica.Checked = [bool]$Settings.mica
Set-JipegCheck $chkMica $Theme
$card2.Controls.Add($chkMica)

# ------------------------------------------------------------------ finish
New-Section 'When a conversion finishes' 364
$card3 = New-Card 394 76

$chkClose = New-Object System.Windows.Forms.CheckBox
$chkClose.SetBounds($Pad, 16, $InnerW, 22)
$chkClose.Text = 'Close the window automatically'
$chkClose.Checked = [bool]$Settings.closeWhenDone
Set-JipegCheck $chkClose $Theme
$card3.Controls.Add($chkClose)
[void](New-Hint 'Otherwise the result stays on screen until you click OK.' ($Pad + 20) 42 ($InnerW - 20) $card3)

# ----------------------------------------------------------------- version
$lblVer = New-Object System.Windows.Forms.Label
$lblVer.SetBounds($Margin, 494, 260, 22)
$lblVer.ForeColor = $Theme.Text
$lblVer.Text = "Jipeg $JipegVersion"
Set-JipegLabel $lblVer $Theme $Mica
$form.Controls.Add($lblVer)

$lblUpd = New-Object System.Windows.Forms.Label
$lblUpd.SetBounds($Margin, 518, 320, 18)
$lblUpd.Font = $JipegFontHint
$lblUpd.ForeColor = $Theme.Muted
Set-JipegLabel $lblUpd $Theme $Mica
$form.Controls.Add($lblUpd)

$btnUpd = New-Object System.Windows.Forms.Button
$btnUpd.SetBounds(($W - $Margin - 160), 496, 160, 32)
$btnUpd.Text = 'Check for updates'
Set-JipegButton $btnUpd $Theme
$form.Controls.Add($btnUpd)
Set-JipegRounded $btnUpd 5

$script:NewUrl = $null
$script:Check  = $null

function Show-UpdateResult($rel) {
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
}

function Start-Check {
    $script:NewUrl = $null
    $btnUpd.Enabled = $false
    $btnUpd.Text = 'Check for updates'
    $lblUpd.ForeColor = $Theme.Muted
    $lblUpd.Text = 'Checking for updates...'
    $script:Check = Start-JipegUpdateCheck
    if (-not $script:Check) { Show-UpdateResult $null; return }
    $poll.Start()
}

# The check runs on its own; polling here keeps the window responsive rather
# than freezing it for however long GitHub takes to answer.
$poll = New-Object System.Windows.Forms.Timer
$poll.Interval = 200
$poll.Add_Tick({
    if (-not $script:Check) { $poll.Stop(); return }
    if (-not $script:Check.Async.IsCompleted) { return }
    $poll.Stop()
    $rel = Complete-JipegUpdateCheck $script:Check
    $script:Check = $null
    Show-UpdateResult $rel
})

$btnUpd.Add_Click({
    if ($script:NewUrl) { Start-Process $script:NewUrl; return }
    Start-Check
})

# --------------------------------------------------------------- OK/Cancel
$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.SetBounds(($W - $Margin - 100), 556, 100, 32)
$btnCancel.Text = 'Cancel'
Set-JipegButton $btnCancel $Theme
$btnCancel.Add_Click({ $form.Close() })
$form.Controls.Add($btnCancel)
Set-JipegRounded $btnCancel 5

$btnOK = New-Object System.Windows.Forms.Button
$btnOK.SetBounds(($W - $Margin - 208), 556, 100, 32)
$btnOK.Text = 'OK'
Set-JipegButton $btnOK $Theme
$form.Controls.Add($btnOK)
Set-JipegRounded $btnOK 5

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
    Start-Check                    # look for a newer release straight away
})
[System.Windows.Forms.Application]::Run($form)
