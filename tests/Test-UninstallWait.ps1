# Real uninstall regression: never remove files while a conversion lock is held.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $env:LOCALAPPDATA 'Jipeg'
$lock = Join-Path $env:TEMP 'jipeg.lock'
$existed = Test-Path -LiteralPath $lock
$stream = $null
try {
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $repo 'src\Install-Jipeg.ps1') -Silent
    if ($LASTEXITCODE) { throw 'Installation failed.' }
    # This will fail safely if a real conversion is already holding the lock.
    $stream = [IO.File]::Open($lock, 'OpenOrCreate', 'Write', 'None')
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $dest 'Uninstall-Jipeg.ps1') -Silent
    if ($LASTEXITCODE) { throw 'Uninstaller failed.' }
    Start-Sleep -Seconds 3
    if (-not (Test-Path -LiteralPath (Join-Path $dest 'Jipeg-Convert.ps1'))) { throw 'Files removed while conversion lock held.' }
    if (Test-Path 'HKCU:\Software\Classes\Directory\shell\JipegConvert') { throw 'Menu entry remains after uninstall.' }
    'PASS: menu removed while files remain protected by the conversion lock'
    $stream.Dispose(); $stream = $null
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while ((Test-Path -LiteralPath $dest) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 300 }
    if (Test-Path -LiteralPath $dest) { throw 'Install folder remains after conversion lock released.' }
    'PASS: install folder removed after conversion lock released'
} finally {
    if ($stream) { $stream.Dispose() }
    if (-not $existed) { Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue }
    # Do not race a still-running cleanup worker with a reinstall after failure.
}
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $repo 'src\Install-Jipeg.ps1') -Silent
if ($LASTEXITCODE) { throw 'Could not reinstall the working copy.' }
