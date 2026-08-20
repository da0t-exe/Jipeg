<#
    Jipeg one-line installer.

        irm https://raw.githubusercontent.com/da0t-exe/Jipeg/main/install.ps1 | iex

    Downloads the latest release, checks it against the SHA-256 GitHub reports
    for that asset, and runs the normal installer. Nothing needs administrator
    rights and nothing is written outside your user profile.

    Run the file directly with -Silent to install without the setup window.
#>
[CmdletBinding()]
param([switch]$Silent)

$ErrorActionPreference = 'Stop'
$Repo = 'da0t-exe/Jipeg'
$Work = Join-Path $env:TEMP ('jipeg-setup-{0}' -f [guid]::NewGuid().ToString('N').Substring(0, 8))

function Say([string]$text, [string]$colour = 'Gray') { Write-Host "  $text" -ForegroundColor $colour }

Write-Host ''
Write-Host '  Jipeg' -ForegroundColor White
Write-Host '  Right-click an image, get a smaller JPEG.' -ForegroundColor DarkGray
Write-Host ''

try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    Say 'Looking up the latest release...'
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" `
                                 -Headers @{ 'User-Agent' = 'Jipeg-Installer' }
    $asset = $release.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
    if (-not $asset) { throw "The $($release.tag_name) release has no .zip asset." }
    Say "Found $($release.tag_name) - $($asset.name) ($([math]::Round($asset.size / 1MB, 1)) MB)" 'White'

    New-Item -ItemType Directory -Path $Work -Force | Out-Null
    $zip = Join-Path $Work $asset.name

    Say 'Downloading...'
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add('User-Agent', 'Jipeg-Installer')
    $wc.DownloadFile($asset.browser_download_url, $zip)
    $wc.Dispose()

    # GitHub reports a digest for the asset; both it and the file come over
    # HTTPS, so this catches a corrupted transfer rather than a hostile GitHub.
    if ($asset.digest -and $asset.digest -match '^sha256:(?<hash>[0-9a-fA-F]{64})$') {
        Say 'Checking SHA-256...'
        $actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
        if ($actual -ne $Matches['hash'].ToUpper()) {
            throw "The download does not match the checksum GitHub published for it."
        }
    }

    Say 'Unpacking...'
    Expand-Archive -LiteralPath $zip -DestinationPath $Work -Force
    $setup = Get-ChildItem -Path $Work -Recurse -Filter 'Install-Jipeg.ps1' | Select-Object -First 1
    if (-not $setup) { throw 'Install-Jipeg.ps1 is missing from the archive.' }

    Say 'Starting the installer...'
    Write-Host ''
    # Launched in its own process with Bypass: the freshly downloaded script is
    # unsigned and carries the mark of the web, which a machine set to
    # RemoteSigned or AllSigned would otherwise refuse to run.
    $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', $setup.FullName)
    if ($Silent) { $psArgs += '-Silent' }
    $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $psArgs -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) { throw "The installer exited with code $($proc.ExitCode)." }
    Write-Host ''
    Say 'Done. Right-click an image to convert it.' 'Green'
} catch {
    Write-Host ''
    Say "Installation failed: $($_.Exception.Message)" 'Red'
    Write-Host ''
    exit 1
} finally {
    if (Test-Path -LiteralPath $Work) {
        Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Write-Host ''
