# Installs the archive that is about to be published, and looks at what it left
# behind. Reading a file list tells you a folder is present; only installing
# tells you the thing works.
#
# This overwrites the installed copy with what is in the archive. That is the
# point - it is the same path anyone downloading it takes, and the same one the
# quiet update takes.
param(
    [Parameter(Mandatory = $true)][string]$Zip,
    [switch]$KeepInstalled
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Repo = Split-Path -Parent $PSScriptRoot
$Dest = Join-Path $env:LOCALAPPDATA 'Jipeg'
$fautes = 0
function Note($ok, $quoi, $detail) {
    if (-not $ok) { $script:fautes++ }
    '  {0}  {1,-42} {2}' -f $(if ($ok) { 'ok  ' } else { 'RATE' }), $quoi, $detail
}

if (-not (Test-Path -LiteralPath $Zip)) { throw "No archive at $Zip" }
$work = Join-Path $env:TEMP ('jipeg-check-{0}' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($Zip, $work)

# Cleared out first, or leftovers answer for the archive. Tried without this
# and it showed: an archive with no src\lang still reported ten language files,
# because the installer copies over what is there rather than replacing it, and
# the ten from the previous install were still sitting in the folder.
if (Test-Path -LiteralPath (Join-Path $Dest 'Uninstall-Jipeg.ps1')) {
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
        -File (Join-Path $Dest 'Uninstall-Jipeg.ps1') -Silent | Out-Null
    Start-Sleep -Seconds 4          # the folder itself is handed to cmd on a delay
}
if (Test-Path -LiteralPath $Dest) { Remove-Item -LiteralPath $Dest -Recurse -Force -ErrorAction SilentlyContinue }
Note (-not (Test-Path -LiteralPath $Dest)) 'nothing was left from before' $Dest

$setup = Get-ChildItem -LiteralPath $work -Recurse -Filter 'Install-Jipeg.ps1' | Select-Object -First 1
Note ($null -ne $setup) 'the archive carries an installer' $(if ($setup) { $setup.FullName.Substring($work.Length + 1) } else { 'absent' })
if (-not $setup) { Remove-Item -LiteralPath $work -Recurse -Force; exit 1 }

$proc = Start-Process powershell.exe -PassThru -Wait -WindowStyle Hidden -ArgumentList @(
    '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $setup.FullName, '-Silent')
Note ($proc.ExitCode -eq 0) 'it installs without complaining' ('exit {0}' -f $proc.ExitCode)

# --- what the installer was supposed to leave behind ----------------------
$hit = Select-String -LiteralPath (Join-Path $Dest 'Jipeg-Common.ps1') `
                     -Pattern "JipegVersion\s*=\s*'([^']+)'" -ErrorAction SilentlyContinue | Select-Object -First 1
$installed = $(if ($hit) { $hit.Matches[0].Groups[1].Value } else { '(unreadable)' })
Note ($null -ne $hit) 'a version can be read back' $installed

$langs = @(Get-ChildItem -LiteralPath (Join-Path $Dest 'lang') -Filter '*.psd1' -ErrorAction SilentlyContinue)
Note ($langs.Count -eq 10) 'ten language files arrived' ('{0} found' -f $langs.Count)

$bins = @(Get-ChildItem -LiteralPath (Join-Path $Dest 'bin') -Filter '*.exe' -ErrorAction SilentlyContinue)
Note ($bins.Count -eq 4) 'four tools arrived' (($bins | ForEach-Object { $_.Name }) -join ' ')

# The failure this whole script exists for: with src\lang left out, nothing
# throws - every string is simply empty, and the menu entry has no name.
$assoc = 'HKCU:\Software\Classes\SystemFileAssociations'
$exts = @()
if (Test-Path $assoc) {
    foreach ($e in (Get-ChildItem $assoc -ErrorAction SilentlyContinue)) {
        if (Test-Path (Join-Path $e.PSPath 'shell\JipegConvert')) { $exts += $e.PSChildName }
    }
}
Note ($exts.Count -ge 20) 'the extensions are registered' ('{0} of them' -f $exts.Count)

$verb = $null
if ($exts -contains '.png') {
    $verb = (Get-ItemProperty "$assoc\.png\shell\JipegConvert" -Name MUIVerb -ErrorAction SilentlyContinue).MUIVerb
}
Note (-not [string]::IsNullOrWhiteSpace($verb)) 'the menu entry has a name' $(if ($verb) { """$verb""" } else { 'EMPTY - src\lang did not ship' })

# --- and that it converts something --------------------------------------
$sample = Join-Path $work 'essai.png'
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap(240, 180)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$rnd = New-Object Random 7
for ($y = 0; $y -lt 180; $y += 2) {
    for ($x = 0; $x -lt 240; $x += 2) {
        $b = New-Object System.Drawing.SolidBrush(
            [System.Drawing.Color]::FromArgb(($x + $rnd.Next(30)) % 256, ($y * 2) % 256, 140))
        $g.FillRectangle($b, $x, $y, 2, 2); $b.Dispose()
    }
}
$g.Dispose(); $bmp.Save($sample, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()

$p = Start-Process powershell.exe -PassThru -WindowStyle Hidden -ArgumentList @(
    '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-STA', '-File',
    ('"' + (Join-Path $Dest 'Jipeg-Convert.ps1') + '"'), ('"' + $sample + '"'))
$sw = [System.Diagnostics.Stopwatch]::StartNew()
while (-not $p.HasExited -and $sw.Elapsed.TotalSeconds -lt 60) { Start-Sleep -Milliseconds 300 }
if (-not $p.HasExited) { [void]$p.CloseMainWindow(); Start-Sleep -Seconds 2 }
if (-not $p.HasExited) { $p.Kill() }
$made = Get-ChildItem -LiteralPath $work -Filter 'essai_jipeg.*' -ErrorAction SilentlyContinue | Select-Object -First 1
Note ($null -ne $made) 'it converts an image' $(if ($made) { '{0}, {1:N0} -> {2:N0} bytes' -f $made.Name, (Get-Item $sample).Length, $made.Length } else { 'nothing came out' })

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
if (-not $KeepInstalled) {
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
        -File (Join-Path $Repo 'src\Install-Jipeg.ps1') -Silent | Out-Null
    '  (the working copy has been put back over it)'
}
''
if ($fautes) { "  $fautes thing(s) wrong - this archive must not be published" }
else { '  the archive installs, registers and converts' }
exit $(if ($fautes) { 1 } else { 0 })
