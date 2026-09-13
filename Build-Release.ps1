# Assembles the archive that gets attached to a release.
#
# It exists because the previous one was put together by hand, and by the time
# the tenth language file appeared there was a folder in the tree that an
# installer needs and that nobody would think to tick. Leaving src\lang out does
# not fail loudly - every string comes back empty, so the settings window opens
# with no text in it and the right-click entry has no name.
#
# What goes in is decided by git, not by a list kept here: anything tracked and
# not development-only. A file added to the repository ships without anyone
# having to remember it.
param([string]$Out = $PSScriptRoot)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Repo = $PSScriptRoot

$hit = Select-String -LiteralPath (Join-Path $Repo 'src\Jipeg-Common.ps1') `
                     -Pattern "JipegVersion\s*=\s*'([^']+)'" | Select-Object -First 1
if (-not $hit) { throw 'Could not read $JipegVersion out of src\Jipeg-Common.ps1.' }
$Version = $hit.Matches[0].Groups[1].Value
$Name = 'Jipeg-{0}' -f $Version

# Development-only. The tests are not shipped - they need Python and Pillow, and
# nobody installing Jipeg has any use for them.
$Skip = @('tests/', '.github/', '.gitattributes', '.gitignore', 'Build-Release.ps1')

Push-Location $Repo
try { $tracked = @(& git ls-files) } finally { Pop-Location }
if (-not $tracked) { throw 'git ls-files returned nothing. Is this a working copy?' }

$files = $tracked | Where-Object {
    $f = $_
    -not ($Skip | Where-Object { $f -eq $_ -or $f.StartsWith($_) })
}

$stage = Join-Path $env:TEMP ('jipeg-release-{0}' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
$root  = Join-Path $stage $Name
New-Item -ItemType Directory -Path $root -Force | Out-Null
foreach ($f in $files) {
    $src = Join-Path $Repo ($f -replace '/', '\')
    $dst = Join-Path $root ($f -replace '/', '\')
    $dir = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item -LiteralPath $src -Destination $dst -Force
}

# Read out of the installer rather than trusted to a list here: these are the
# paths it reaches for, and an archive missing one of them installs something
# broken without saying so.
$must = @(
    'src\Install-Jipeg.ps1', 'src\Jipeg-Common.ps1', 'src\Jipeg-Imaging.ps1', 'src\Jipeg-Convert.ps1',
    'src\Jipeg-Settings.ps1', 'src\Jipeg-Update.ps1', 'src\Uninstall-Jipeg.ps1',
    'src\launch.vbs', 'src\settings.vbs', 'src\update.vbs',
    'src\lang\en.psd1',
    'bin\cjpegli.exe', 'bin\dwebp.exe', 'bin\webpmux.exe', 'bin\oxipng.exe',
    'install.ps1', 'uninstall.ps1', 'README.md', 'LICENSE'
)
$missing = @($must | Where-Object { -not (Test-Path -LiteralPath (Join-Path $root $_)) })
if ($missing) {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    throw ("The archive would have shipped without: {0}" -f ($missing -join ', '))
}

$langs = @(Get-ChildItem -LiteralPath (Join-Path $root 'src\lang') -Filter '*.psd1')
if ($langs.Count -lt 10) {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    throw ("Only {0} language files reached the archive; ten were expected." -f $langs.Count)
}

$zip = Join-Path $Out ($Name + '.zip')
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip)
Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue

$sha = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
'  {0}' -f $zip
'  {0:N0} bytes, {1} files, {2} languages' -f (Get-Item $zip).Length, $files.Count, $langs.Count
'  SHA-256 {0}' -f $sha
''
'  Now check it installs, before it goes anywhere:'
'    powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Release.ps1 -Zip "{0}"' -f $zip
