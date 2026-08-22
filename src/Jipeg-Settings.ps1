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
# What gets painted in the corners outside every rounded shape. Never black,
# even on a Mica window: DWM composites a child control opaquely, so black there
# stays black and each button and card wore four #000000 notches against a
# backdrop measuring #1D2025. The theme's own background is within a few levels
# of what the material renders, so the corners disappear into it.
$Backdrop = $Theme.Back

# Everything sits on a 4-pixel grid: 20 outside the window, 16 inside a card.
$W        = 540
$Margin   = 20
$CardW    = $W - 2 * $Margin
$Pad      = 16
$InnerW   = $CardW - 2 * $Pad
$FieldW   = 280
$FieldX   = $CardW - $Pad - $FieldW

# One label per value, spelled out. Two entries reading "light, for the web"
# told the reader nothing about the difference between them.
$QualityText = @{
    100 = 'maximum, files get very large'
     96 = 'visually lossless'
     92 = 'very high quality'
     90 = 'high quality (default)'
     85 = 'balanced'
     80 = 'small files, still crisp'
     75 = 'light, made for the web'
     70 = 'strong compression'
     60 = 'very strong, artefacts show'
}
function Quality-Label([int]$q) {
    if ($QualityText.ContainsKey($q)) { return "$q - $($QualityText[$q])" }
    return "$q - custom"
}

# ------------------------------------------------------------------- window
$form = New-Object System.Windows.Forms.Form
$form.Text            = 'Jipeg Settings'
$form.FormBorderStyle = 'FixedDialog'
$form.StartPosition   = 'CenterScreen'
$form.ClientSize      = New-Object System.Drawing.Size($W, 760)
# Everything below is written in the units the window was designed in; WinForms
# multiplies them by the screen's scaling for us, so long as the process is
# DPI-aware, which Jipeg-Common arranges before any window exists.
# WinForms is told to keep its hands off: everything below is in design units
# and Set-JipegScaleForm applies the one factor just before the window is shown.
$form.AutoScaleMode   = 'None'
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
        # The corners outside the rounded shape are the window's own backdrop.
        # This used to be a Region clip instead, which is all-or-nothing per
        # pixel: the four corners of a card measured 44 levels apart out of 255
        # and the curve was a staircase. Painting them costs nothing and leaves
        # the Mica glass showing through, which a clipped region also did.
        # Drawn in a buffer so Copy-JipegCorners can make the four corners
        # identical before any of it reaches the screen.
        $buf = New-Object System.Drawing.Bitmap($this.Width, $this.Height)
        $bg = [System.Drawing.Graphics]::FromImage($buf)
        $bg.Clear($Backdrop)
        $bg.SmoothingMode = 'AntiAlias'
        $p = New-JipegRoundPath 0 0 ($this.Width - 1) ($this.Height - 1) (Get-JipegScaled 8)
        # Filled here rather than left to BackColor: over Mica, the background
        # WinForms paints comes out with no alpha and the backdrop shows through,
        # so the card was translucent - measured at #494B50 instead of #2B2B2B.
        # A GDI+ brush writes opaque pixels.
        $fill = New-Object System.Drawing.SolidBrush($Theme.Panel)
        $bg.FillPath($fill, $p); $fill.Dispose()
        $pen = New-Object System.Drawing.Pen($Theme.CardEdge, 1)
        $pen.Alignment = 'Inset'
        $bg.DrawPath($pen, $p)
        $pen.Dispose(); $p.Dispose(); $bg.Dispose()
        Copy-JipegCorners $buf
        $g.DrawImageUnscaled($buf, 0, 0)
        $buf.Dispose()
    })
    $form.Controls.Add($c)
    return $c
}

function New-Label([string]$text, [int]$x, [int]$y, [int]$w, $parent) {
    $l = New-Object System.Windows.Forms.Label
    $l.SetBounds($x, $y, $w, 22)
    $l.ForeColor = $Theme.Text
    # Transparent so the card's own painted fill shows through. Left opaque, the
    # label's background is drawn by WinForms with no alpha and the Mica backdrop
    # bleeds into it, leaving a lighter rectangle around every line of text.
    $l.BackColor = [System.Drawing.Color]::Transparent
    $l.Text = $text
    $parent.Controls.Add($l)
    return $l
}

function New-Hint([string]$text, [int]$x, [int]$y, [int]$w, $parent) {
    $l = New-Object System.Windows.Forms.Label
    $l.SetBounds($x, $y, $w, 18)
    $l.Font = $JipegFontHint
    $l.ForeColor = $Theme.Muted
    $l.BackColor = [System.Drawing.Color]::Transparent
    $l.Text = $text
    $parent.Controls.Add($l)
    return $l
}

# The list items are drawn so they follow the theme instead of the system's
# default dropdown.
$script:PopupTimer = New-Object System.Windows.Forms.Timer
$script:PopupTimer.Interval = 40
$script:PopupTimer.Add_Tick({
    $script:PopupTimer.Stop()
    Set-JipegPopupChrome $Theme
})

# The visible field is painted here, not clipped. A Region clip is binary, so
# rounded corners came out as a hard staircase; painting gives the same radius
# on all four corners, antialiased. The ComboBox itself stays underneath purely
# to provide the system drop-down list, and a Button is used as the face so it
# keeps focus and answers to Space and Enter.
#
# A ComboBox ignores the height it is given - it is always ItemHeight + 6, here
# 32 against the 26 the field is drawn at. The face used to be 26 too, so the
# last six rows of the real control showed underneath it: a #F0F0F0 strip with a
# white line under it, the pale bar that kept appearing below every drop-down.
# The face now covers the control completely, and the control is lifted by the
# difference so its bottom edge - where Windows hangs the list - lands exactly on
# the bottom of the painted field.
$FieldH = 26
$script:ComboRows = New-Object System.Collections.Generic.List[object]

# Re-run once the window has been scaled. The field is drawn $FieldH tall and
# the real control is taller; the control is lifted so its bottom edge - where
# Windows hangs the list - lands on the bottom of the painted field, and the
# face is stretched to cover whatever is left showing.
function Update-JipegComboRows {
    $fieldH = Get-JipegScaled $FieldH
    foreach ($row in $script:ComboRows) {
        if (-not $row.Face) { continue }
        $bottom = [int][math]::Round($row.Y * $JipegScale) + $fieldH
        $top = $bottom - $row.Combo.Height
        $row.Combo.Top = $top
        $row.Face.SetBounds($row.Face.Left, $top, $row.Face.Width, ($bottom - $top))
    }
}

function New-Combo([int]$y, $parent) {
    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.SetBounds($FieldX, $y, $FieldW, $FieldH)
    $combo.DropDownStyle = 'DropDownList'
    $combo.FlatStyle = 'Flat'
    $combo.Font = $JipegFont
    $combo.BackColor = $Theme.Field
    $combo.ForeColor = $Theme.Text
    $combo.DropDownWidth = $FieldW
    $combo.DrawMode = 'OwnerDrawFixed'
    $combo.ItemHeight = Get-JipegScaled 26
    $combo.Add_DrawItem({
        $e = $_
        $back = $Theme.Field
        if (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0) { $back = $Theme.Accent }
        $b = New-Object System.Drawing.SolidBrush($back)
        $e.Graphics.FillRectangle($b, $e.Bounds)
        $b.Dispose()
        if ($e.Index -ge 0) {
            $r = New-Object System.Drawing.Rectangle(
                ($e.Bounds.X + (Get-JipegScaled 10)), $e.Bounds.Y,
                ($e.Bounds.Width - (Get-JipegScaled 14)), $e.Bounds.Height)
            [System.Windows.Forms.TextRenderer]::DrawText(
                $e.Graphics, $this.Items[$e.Index].ToString(), $JipegFont, $r, $Theme.Text,
                ([System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor
                 [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor
                 [System.Windows.Forms.TextFormatFlags]::NoPrefix))
        }
    })
    $combo.Add_DropDown({ $script:PopupTimer.Start() })
    $parent.Controls.Add($combo)

    # measured after the control exists, never assumed - and measured again once
    # the window has been scaled, because the control's height does not grow by
    # the same factor as the layout: its font grows too, so at 150% it stood 21
    # pixels above the field instead of 6 and its face wrote over the line above
    $over = [math]::Max(0, $combo.Height - $FieldH)
    $combo.Top = $y - $over
    $script:ComboRows.Add([pscustomobject]@{ Combo = $combo; Face = $null; Y = $y })

    $face = New-Object System.Windows.Forms.Button
    $face.SetBounds($FieldX, ($y - $over), $FieldW, ($FieldH + $over))
    $face.FlatStyle = 'Flat'
    $face.FlatAppearance.BorderSize = 0
    $face.FlatAppearance.MouseOverBackColor = $Theme.Panel
    $face.FlatAppearance.MouseDownBackColor = $Theme.Panel
    $face.BackColor = $Theme.Panel
    $face.Font = $JipegFont
    $face.Tag = $combo
    Set-JipegDoubleBuffer $face
    $face.Add_Paint({
        $g = $_.Graphics
        # Clear, not FillRectangle: with antialiasing already on, the fill left
        # its outermost column only partly covered, and the Mica backdrop came
        # through it as a faint blue line down the left edge of every field
        # (#383B40 where the surface should have been flat #2B2B2B). Clear
        # ignores smoothing and writes the whole surface opaque.
        $g.Clear($this.BackColor)
        $g.TextRenderingHint = 'ClearTypeGridFit'

        # the field is the bottom $FieldH rows; anything above is the lifted
        # control, left in the card colour. The shape is drawn on its own, in a
        # buffer its exact size, so its four corners can be made identical before
        # it is placed - mirroring the face itself would move the shape, which
        # does not sit in the middle of it.
        $w = $this.Width
        $h = Get-JipegScaled $FieldH
        $top = [int]($this.Height - $h)
        $buf = New-Object System.Drawing.Bitmap($w, $h)
        $bg = [System.Drawing.Graphics]::FromImage($buf)
        $bg.Clear($this.BackColor)
        $bg.SmoothingMode = 'AntiAlias'
        $shape = New-JipegRoundPath 0 0 ($w - 1.0) ($h - 1.0) (Get-JipegScaled 5)
        $fill = New-Object System.Drawing.SolidBrush($Theme.Field)
        $bg.FillPath($fill, $shape); $fill.Dispose()
        $edge = $Theme.CardEdge
        $width = 1.0
        if ($this.Focused -and (Test-JipegFocusCue $this)) { $edge = $Theme.Accent; $width = 1.4 }
        $pen = New-Object System.Drawing.Pen($edge, $width)
        $pen.Alignment = 'Inset'
        $bg.DrawPath($pen, $shape); $pen.Dispose(); $shape.Dispose(); $bg.Dispose()
        Copy-JipegCorners $buf
        $g.DrawImageUnscaled($buf, 0, $top)
        $buf.Dispose()
        $g.SmoothingMode = 'AntiAlias'

        $text = ''
        if ($this.Tag) { $text = [string]$this.Tag.Text }
        $tr = New-Object System.Drawing.Rectangle((Get-JipegScaled 10), [int]$top,
                                                  ($w - (Get-JipegScaled 40)), $h)
        [System.Windows.Forms.TextRenderer]::DrawText($g, $text, $JipegFont, $tr, $Theme.Text,
            ([System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor
             [System.Windows.Forms.TextFormatFlags]::EndEllipsis -bor
             [System.Windows.Forms.TextFormatFlags]::NoPrefix))

        $pen = New-Object System.Drawing.Pen($Theme.Muted, ([single](1.6 * $JipegScale)))
        $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
        $cx = $w - (16.0 * $JipegScale)
        $cy = $top + $h / 2.0
        $a  = 4.0 * $JipegScale
        $b  = 2.0 * $JipegScale
        $c  = 2.5 * $JipegScale
        $g.DrawLines($pen, @(
            (New-Object System.Drawing.PointF(($cx - $a), ($cy - $b))),
            (New-Object System.Drawing.PointF($cx, ($cy + $c))),
            (New-Object System.Drawing.PointF(($cx + $a), ($cy - $b)))
        ))
        $pen.Dispose()
    })
    $face.Add_Click({ $this.Tag.DroppedDown = $true })
    $face.Add_GotFocus({ $this.Invalidate() })
    $face.Add_LostFocus({ $this.Invalidate() })
    $parent.Controls.Add($face)
    $face.BringToFront()

    $combo.Tag = $face
    $combo.Add_SelectedIndexChanged({ if ($this.Tag) { $this.Tag.Invalidate() } })
    $script:ComboRows[$script:ComboRows.Count - 1].Face = $face
    return $combo
}

# --------------------------------------------------------------- conversion
New-Section 'Conversion' 20
$card1 = New-Card 50 138

[void](New-Label 'JPEG quality' $Pad 16 160 $card1)
$QualityValues = @(100, 96, 92, 90, 85, 80, 75, 70, 60)
$cmbQ = New-Combo 14 $card1
foreach ($v in $QualityValues) { [void]$cmbQ.Items.Add((Quality-Label $v)) }
$saved = [int]$Settings.quality
if ($QualityValues -notcontains $saved) {
    [void]$cmbQ.Items.Add((Quality-Label $saved))
    $QualityValues += $saved
}
$cmbQ.SelectedIndex = [array]::IndexOf($QualityValues, $saved)

[void](New-Hint 'Higher keeps more detail and makes bigger files.' $Pad 46 $InnerW $card1)

[void](New-Label 'Colour detail' $Pad 74 160 $card1)
$ChromaValues = @('auto', 'always', 'never')
$cmbC = New-Combo 72 $card1
[void]$cmbC.Items.AddRange(@('Follow the source', 'Always full (4:4:4)', 'Smaller files (4:2:0)'))
$cmbC.SelectedIndex = [array]::IndexOf($ChromaValues, [string]$Settings.chroma)
if ($cmbC.SelectedIndex -lt 0) { $cmbC.SelectedIndex = 0 }

[void](New-Hint 'Full colour keeps text and sharp edges clean, and costs some size.' $Pad 104 $InnerW $card1)

# --------------------------------------------------------------- appearance
New-Section 'Appearance' 208
$card2 = New-Card 238 132

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
[void](New-Hint 'The Windows 11 material: the background picks up what is behind it.' ($Pad + 26) 98 ($InnerW - 26) $card2)

New-Section 'Updates' 390
$card4 = New-Card 420 76
$chkAuto = New-Object System.Windows.Forms.CheckBox
$chkAuto.SetBounds($Pad, 16, $InnerW, 22)
$chkAuto.Text = 'Install new versions quietly'
$chkAuto.Checked = [bool]$Settings.autoUpdate
Set-JipegCheck $chkAuto $Theme
$card4.Controls.Add($chkAuto)
$autoHint = 'Checked once a day after a conversion, never during one.'
if ($Settings.lastUpdate) { $autoHint = [string]$Settings.lastUpdate }
[void](New-Hint $autoHint ($Pad + 26) 42 ($InnerW - 26) $card4)

# ------------------------------------------------------------------ finish
New-Section 'When a conversion finishes' 516
$card3 = New-Card 546 76

$chkClose = New-Object System.Windows.Forms.CheckBox
$chkClose.SetBounds($Pad, 16, $InnerW, 22)
$chkClose.Text = 'Close the window automatically'
$chkClose.Checked = [bool]$Settings.closeWhenDone
Set-JipegCheck $chkClose $Theme
$card3.Controls.Add($chkClose)
[void](New-Hint 'Otherwise the result stays on screen until you click OK.' ($Pad + 26) 42 ($InnerW - 26) $card3)

# ----------------------------------------------------------------- version
$lblVer = New-Object System.Windows.Forms.Label
$lblVer.SetBounds($Margin, 642, 260, 22)
$lblVer.ForeColor = $Theme.Text
$lblVer.Text = "Jipeg $JipegVersion"
Set-JipegLabel $lblVer $Theme $Mica
$form.Controls.Add($lblVer)

$lblUpd = New-Object System.Windows.Forms.Label
$lblUpd.SetBounds($Margin, 664, 320, 18)
$lblUpd.Font = $JipegFontHint
$lblUpd.ForeColor = $Theme.Muted
Set-JipegLabel $lblUpd $Theme $Mica
$form.Controls.Add($lblUpd)

$btnUpd = New-Object System.Windows.Forms.Button
$btnUpd.SetBounds(($W - $Margin - 160), 646, 160, 32)
$btnUpd.Text = 'Check for updates'
Set-JipegButton $btnUpd $Theme $Backdrop
$form.Controls.Add($btnUpd)

$script:NewTag = $null
$script:Check  = $null
$script:Job    = $null

function Show-UpdateResult($rel) {
    if (-not $rel) {
        $lblUpd.Text = 'Could not reach GitHub.'
    } elseif ((Compare-JipegVersion $rel.Tag $JipegVersion) -gt 0) {
        $lblUpd.Text = "Version $($rel.Tag) is available."
        $lblUpd.ForeColor = $Theme.Text
        $script:NewTag = $rel.Tag
        $btnUpd.Text = 'Update'
    } else {
        $lblUpd.Text = 'You have the latest version.'
    }
    $btnUpd.Enabled = $true
}

function Start-Check {
    $script:NewTag = $null
    $btnUpd.Enabled = $false
    $btnUpd.Text = 'Check for updates'
    $lblUpd.ForeColor = $Theme.Muted
    $lblUpd.Text = 'Checking for updates...'
    $script:Check = Start-JipegUpdateCheck
    if (-not $script:Check) { Show-UpdateResult $null; return }
    $poll.Start()
}

# The Update button installs it here rather than opening a browser. It runs the
# same updater the quiet daily check uses - same repository, same strictly
# higher version, same SHA-256 - only with -Force, so it does not wait for
# tomorrow. It runs in its own hidden process so this window stays alive: it is
# about to have its own files replaced underneath it, which is safe because
# PowerShell has already read them.
function Start-Update {
    $btnUpd.Enabled = $false
    $lblUpd.ForeColor = $Theme.Muted
    $lblUpd.Text = "Downloading Jipeg $script:NewTag..."
    try {
        $script:Job = Start-Process -FilePath 'powershell.exe' -PassThru -WindowStyle Hidden -ArgumentList @(
            '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
            '-File', (Join-Path $Root 'Jipeg-Update.ps1'), '-Force')
    } catch {
        $lblUpd.Text = 'Could not start the update.'
        $btnUpd.Enabled = $true
        return
    }
    $watch.Start()
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

$watch = New-Object System.Windows.Forms.Timer
$watch.Interval = 400
$watch.Add_Tick({
    if (-not $script:Job -or -not $script:Job.HasExited) { return }
    $watch.Stop()
    $code = $script:Job.ExitCode
    $script:Job = $null
    if ($code -eq 0) {
        $lblVer.Text = "Jipeg $JipegVersion -> $script:NewTag"
        $lblUpd.ForeColor = $Theme.Text
        $lblUpd.Text = "Installed. It takes effect the next time you convert."
        $btnUpd.Text = 'Up to date'
        # the updater wrote lastCheck and lastUpdate; keep them, or clicking OK
        # here would save this window's older copy back over them
        try {
            $fresh = Get-JipegSettings
            $Settings.lastCheck  = $fresh.lastCheck
            $Settings.lastUpdate = $fresh.lastUpdate
        } catch { }
    } elseif ($code -eq 2) {
        $lblUpd.Text = 'Nothing to install right now.'
        $btnUpd.Text = 'Check for updates'
        $btnUpd.Enabled = $true
    } else {
        $lblUpd.Text = 'The update did not go through. Try again later.'
        $btnUpd.Text = 'Update'
        $btnUpd.Enabled = $true
    }
})

$btnUpd.Add_Click({
    if ($script:NewTag) { Start-Update; return }
    Start-Check
})

# --------------------------------------------------------------- OK/Cancel
$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.SetBounds(($W - $Margin - 100), 708, 100, 32)
$btnCancel.Text = 'Cancel'
Set-JipegButton $btnCancel $Theme $Backdrop
$btnCancel.Add_Click({ $form.Close() })
$form.Controls.Add($btnCancel)

$btnOK = New-Object System.Windows.Forms.Button
$btnOK.SetBounds(($W - $Margin - 208), 708, 100, 32)
$btnOK.Text = 'OK'
Set-JipegButton $btnOK $Theme $Backdrop
$form.Controls.Add($btnOK)

$form.AcceptButton = $btnOK
$form.CancelButton = $btnCancel

$btnOK.Add_Click({
    $Settings.quality       = [int]$QualityValues[$cmbQ.SelectedIndex]
    $Settings.chroma        = [string]$ChromaValues[$cmbC.SelectedIndex]
    $Settings.closeWhenDone = [bool]$chkClose.Checked
    $Settings.mica          = [bool]$chkMica.Checked
    $Settings.autoUpdate    = [bool]$chkAuto.Checked
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
Set-JipegScaleForm $form
Update-JipegComboRows
[System.Windows.Forms.Application]::Run($form)
