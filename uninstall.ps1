<#
    Jipeg uninstaller for the console.

        irm https://raw.githubusercontent.com/da0t-exe/Jipeg/main/uninstall.ps1 | iex

    Removes the right-click entry, the Start menu shortcut and the install
    folder. Converted images are never touched. Nothing needs administrator
    rights.

    Add -Yes to skip the question, for a script:
        & ([scriptblock]::Create((irm https://raw.githubusercontent.com/da0t-exe/Jipeg/main/uninstall.ps1))) -Yes
#>
[CmdletBinding()]
param([switch]$Yes)

$ErrorActionPreference = 'Stop'
$Dest = Join-Path $env:LOCALAPPDATA 'Jipeg'

function Say([string]$text, [string]$colour = 'Gray') { Write-Host "  $text" -ForegroundColor $colour }

# Same shape as the question the installer asks: the answer is typed and
# confirmed with Enter, because a bare key press is far too easy to hit by
# accident, and it answers itself when nobody is at the keyboard so the command
# still works from a script.
function Read-Confirm([string]$question, [int]$seconds) {
    Write-Host ''
    Write-Host "  $question " -NoNewline -ForegroundColor White
    Write-Host '[y/n] ' -NoNewline -ForegroundColor DarkGray
    $anchor = $null
    try {
        if (-not [Console]::IsOutputRedirected -and ([Console]::CursorLeft + 40) -lt [Console]::BufferWidth) {
            $anchor = @{ Left = [Console]::CursorLeft; Top = [Console]::CursorTop }
        }
    } catch { $anchor = $null }

    try {
        if ([Console]::IsInputRedirected) { throw 'redirected' }
        $typed = ''
        $deadline = (Get-Date).AddSeconds($seconds)
        $shown = -1
        while ($true) {
            $left = [int][math]::Ceiling(($deadline - (Get-Date)).TotalSeconds)
            if ($left -le 0) { break }
            if ($left -ne $shown -and $anchor) {
                try {
                    [Console]::SetCursorPosition($anchor.Left, $anchor.Top)
                    $tail = "(Enter = yes, ${left}s) "
                    Write-Host $tail -NoNewline -ForegroundColor DarkGray
                    Write-Host $typed -NoNewline -ForegroundColor White
                    $used = $anchor.Left + $tail.Length + $typed.Length
                    $pad = [Console]::BufferWidth - $used - 1
                    if ($pad -gt 0) { Write-Host (' ' * $pad) -NoNewline }
                    [Console]::SetCursorPosition($used, $anchor.Top)
                } catch { }
                $shown = $left
            }
            if (-not [Console]::KeyAvailable) { Start-Sleep -Milliseconds 60; continue }
            $key = [Console]::ReadKey($true)
            $deadline = (Get-Date).AddSeconds($seconds)
            $shown = -1
            if ($key.Key -eq 'Enter') {
                Write-Host ''
                $a = $typed.Trim().ToLower()
                if ($a -eq '') { return $true }
                if ($a.StartsWith('y')) { return $true }
                if ($a.StartsWith('n')) { return $false }
                Say 'Type y or n, then Enter.' 'DarkGray'
                Write-Host "  $question " -NoNewline -ForegroundColor White
                Write-Host '[y/n] ' -NoNewline -ForegroundColor DarkGray
                try { if ($anchor) { $anchor = @{ Left = [Console]::CursorLeft; Top = [Console]::CursorTop } } } catch { }
                $typed = ''
                continue
            }
            if ($key.Key -eq 'Backspace') {
                if ($typed.Length -gt 0) { $typed = $typed.Substring(0, $typed.Length - 1) }
                continue
            }
            if ($key.KeyChar -and -not [char]::IsControl($key.KeyChar)) { $typed += $key.KeyChar }
        }
    } catch { }
    Write-Host ''
    return $true
}

Write-Host ''
Write-Host '  Jipeg' -ForegroundColor White
Write-Host ''

$script = Join-Path $Dest 'Uninstall-Jipeg.ps1'
if (-not (Test-Path -LiteralPath $script)) {
    Say 'Jipeg is not installed for this user.' 'Yellow'
    Say "Nothing was found in $Dest" 'DarkGray'
    Write-Host ''
    return
}

if (-not $Yes) {
    Say 'This removes the right-click entry, the Start menu shortcut and'
    Say "the folder $Dest"
    Say 'Images you have already converted are left alone.' 'DarkGray'
    if (-not (Read-Confirm 'Remove Jipeg?' 10)) {
        Write-Host ''
        Say 'Nothing was removed.' 'DarkGray'
        Write-Host ''
        return
    }
}

Write-Host ''
Say 'Removing...' 'White'

# Run in its own process with the policy relaxed: the copy on disk is unsigned,
# and a machine set to RemoteSigned would otherwise refuse to run it.
$p = Start-Process -FilePath 'powershell.exe' -PassThru -Wait -WindowStyle Hidden -ArgumentList @(
    '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $script, '-Silent')

if ($p.ExitCode -ne 0) {
    Write-Host ''
    Say "The uninstaller stopped with code $($p.ExitCode)." 'Red'
    Say "You can remove $Dest by hand if anything is left." 'DarkGray'
    Write-Host ''
    exit 1
}

# The folder goes last and it goes on a short delay: the uninstaller lives
# inside it, so it hands that step to cmd rather than trying to delete the
# ground it is standing on. Waiting for it here means this never reports a
# problem that is only a race - which it did, the first time it was tried.
$waited = 0
while ((Test-Path -LiteralPath $Dest) -and $waited -lt 8000) {
    Start-Sleep -Milliseconds 250
    $waited += 250
}

Write-Host ''
if (Test-Path -LiteralPath $Dest) {
    Say 'Removed, but some files are still in place:' 'Yellow'
    Say $Dest 'DarkGray'
    Say 'Close any open Jipeg window and delete the folder by hand.' 'DarkGray'
} else {
    Say 'Jipeg has been removed.' 'Green'
}
Write-Host ''
