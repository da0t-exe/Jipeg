<#  Removes Jipeg: context menu, shortcut, files and the uninstall entry.  #>
param([switch]$Silent)

$ErrorActionPreference = 'SilentlyContinue'
[void][System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms')

. (Join-Path $PSScriptRoot 'Jipeg-Common.ps1')

$Dest      = Join-Path $env:LOCALAPPDATA 'Jipeg'
$L = Import-JipegLang (Get-JipegSettings).language
$UninstKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Jipeg'
$Shortcut  = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Jipeg Settings.lnk'

if (-not $Silent) {
    $r = [System.Windows.Forms.MessageBox]::Show(
        $L.unAsk + [Environment]::NewLine + [Environment]::NewLine +
        ($L.unWhat -f $Dest) + [Environment]::NewLine + $L.unKeep,
        $L.unTitle, 'YesNo', 'Question')
    if ($r -ne 'Yes') { exit }
}

# Every association that actually carries our key, rather than a copy of the
# installer's list: the two lists were already drifting apart, and an extension
# added to one and not the other would have been left behind here for good.
$assoc = 'HKCU:\Software\Classes\SystemFileAssociations'
if (Test-Path -LiteralPath $assoc) {
    Get-ChildItem -LiteralPath $assoc -ErrorAction SilentlyContinue | ForEach-Object {
        $key = Join-Path $_.PSPath 'shell\JipegConvert'
        if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force }
    }
}
Remove-Item -Path 'HKCU:\Software\Classes\Directory\shell\JipegConvert' -Recurse -Force
Remove-Item -LiteralPath $Shortcut -Force

# The Windows 11 classic menu tweak is only undone if we were the ones who set it.
if ((Get-ItemProperty -Path $UninstKey -Name 'ClassicMenuSet' -ErrorAction SilentlyContinue).ClassicMenuSet -eq 1) {
    Remove-Item -Path 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}' -Recurse -Force
    Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Milliseconds 800
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
}

Remove-Item -Path $UninstKey -Recurse -Force

# Cleanup runs outside the install folder and waits for conversions to finish.
# Use literal PowerShell paths throughout, including names with shell characters.
if (Test-Path -LiteralPath $Dest) {
    $expected = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Jipeg'))
    if ([IO.Path]::GetFullPath($Dest) -ne $expected) { throw 'Invalid uninstall target.' }
    $worker = Join-Path $env:TEMP ('jipeg-remove-{0}.ps1' -f [guid]::NewGuid().ToString('N'))
    $cleanup = @'
$ErrorActionPreference = 'Stop'
$target = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'Jipeg'))
$parent = [IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\')
if ([IO.Path]::GetDirectoryName($target) -ne $parent -or [IO.Path]::GetFileName($target) -ne 'Jipeg') {
    throw 'Refusing cleanup outside the Jipeg install folder.'
}
$lock = Join-Path $env:TEMP 'jipeg.lock'
try {
    # Hold the same queue mutex as the converter while checking/deleting, so a
    # new batch cannot acquire its file lock between our check and the cleanup.
    $mutex = New-Object Threading.Mutex($false, 'Local\JipegQueue')
    $deadline = [DateTime]::UtcNow.AddMinutes(2)
    do {
        $owned = $false
        try {
            try { $owned = $mutex.WaitOne(1000) }
            catch [Threading.AbandonedMutexException] { $owned = $true }
            if (-not $owned) { continue }
            $busy = $false
            if (Test-Path -LiteralPath $lock) {
                try { $stream = [IO.File]::Open($lock, 'Open', 'Write', 'None'); $stream.Dispose() }
                catch { $busy = $true }
            }
            if (-not $busy) {
                # A junction/reparse point must not redirect recursive cleanup.
                if (Test-Path -LiteralPath $target) {
                    $root = Get-Item -LiteralPath $target -Force
                    if ($root.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing reparse-point install folder.' }
                    $links = @(Get-ChildItem -LiteralPath $target -Recurse -Force | Where-Object {
                        $_.Attributes -band [IO.FileAttributes]::ReparsePoint
                    })
                    if ($links.Count) { throw 'Refusing cleanup containing reparse points.' }
                    Remove-Item -LiteralPath $target -Recurse -Force
                }
                break
            }
        } finally { if ($owned) { $mutex.ReleaseMutex() } }
        Start-Sleep -Milliseconds 500
    } while ([DateTime]::UtcNow -lt $deadline)
    # A timeout deliberately leaves files intact rather than breaking a batch.
} finally {
    if ($mutex) { $mutex.Dispose() }
    Remove-Item -LiteralPath $PSCommandPath -Force
}
'@
    Set-Content -LiteralPath $worker -Value $cleanup -Encoding UTF8
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $worker))
}

if (-not $Silent) {
    [void][System.Windows.Forms.MessageBox]::Show($L.unDone, 'Jipeg', 'OK', 'Information')
}
