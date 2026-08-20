<#
    Jipeg installer for the console.

        irm https://raw.githubusercontent.com/da0t-exe/Jipeg/main/install.ps1 | iex

    Downloads the latest release, checks it against the SHA-256 GitHub reports
    for that asset, and installs it right here. Nothing needs administrator
    rights and nothing is written outside your user profile.

    Switches, when the file is run directly rather than piped:
        -ClassicMenu / -NoClassicMenu   answer the Windows 11 menu question up front
        -Gui                            open the setup window instead
#>
[CmdletBinding()]
param(
    [switch]$Gui,
    [switch]$ClassicMenu,
    [switch]$NoClassicMenu
)

$ErrorActionPreference = 'Stop'
$Repo = 'da0t-exe/Jipeg'
$Dest = Join-Path $env:LOCALAPPDATA 'Jipeg'
$Work = Join-Path $env:TEMP ('jipeg-setup-{0}' -f [guid]::NewGuid().ToString('N').Substring(0, 8))

function Say([string]$text, [string]$colour = 'Gray') { Write-Host "  $text" -ForegroundColor $colour }

# A question that answers itself when nobody is at the keyboard, so the same
# command works in a terminal and inside a script.
function Read-YesNoTimed([string]$question, [int]$seconds, [bool]$default) {
    $hint = 'Y/n'
    if (-not $default) { $hint = 'y/N' }
    Write-Host ''
    Write-Host "  $question " -NoNewline -ForegroundColor White
    Write-Host "[$hint] " -NoNewline -ForegroundColor DarkGray
    try {
        if ([Console]::IsInputRedirected) { throw 'redirected' }
        $deadline = (Get-Date).AddSeconds($seconds)
        while ((Get-Date) -lt $deadline) {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq 'Y') { Write-Host 'yes' -ForegroundColor White; return $true }
                if ($key.Key -eq 'N') { Write-Host 'no'  -ForegroundColor White; return $false }
                if ($key.Key -eq 'Enter') {
                    if ($default) { Write-Host 'yes' -ForegroundColor White }
                    else          { Write-Host 'no'  -ForegroundColor White }
                    return $default
                }
            }
            Start-Sleep -Milliseconds 120
        }
        Write-Host "no answer after $seconds s, keeping the default" -ForegroundColor DarkGray
    } catch {
        Write-Host 'nothing to read from, keeping the default' -ForegroundColor DarkGray
    }
    return $default
}

Write-Host ''
Write-Host '  Jipeg' -ForegroundColor White
Write-Host '  Right-click an image, get a smaller JPEG.' -ForegroundColor DarkGray
Write-Host ''

try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    $installed = $null
    $marker = Join-Path $Dest 'Jipeg-Common.ps1'
    if (Test-Path -LiteralPath $marker) {
        $hit = Select-String -LiteralPath $marker -Pattern "JipegVersion\s*=\s*'([^']+)'" | Select-Object -First 1
        if ($hit) { $installed = $hit.Matches[0].Groups[1].Value }
    }

    Say 'Looking up the latest release...'
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" `
                                 -Headers @{ 'User-Agent' = 'Jipeg-Installer' }
    $asset = $release.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1
    if (-not $asset) { throw "The $($release.tag_name) release has no .zip asset." }

    $found = "Found $($release.tag_name)  -  $([math]::Round($asset.size / 1MB, 1)) MB"
    if ($installed) { $found += "   (installed: $installed)" }
    Say $found 'White'

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
            throw 'The download does not match the checksum GitHub published for it.'
        }
    }

    Say 'Unpacking...'
    Expand-Archive -LiteralPath $zip -DestinationPath $Work -Force
    $setup = Get-ChildItem -Path $Work -Recurse -Filter 'Install-Jipeg.ps1' | Select-Object -First 1
    if (-not $setup) { throw 'Install-Jipeg.ps1 is missing from the archive.' }

    # Run in its own process with Bypass: the files were just downloaded, so
    # they are unsigned and carry the mark of the web, which a machine set to
    # RemoteSigned - the Windows default - would refuse to run.
    $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', $setup.FullName)

    if ($Gui) {
        Say 'Opening the setup window...'
        Write-Host ''
    } else {
        # The one thing worth asking about, because it restarts Explorer.
        $classic = $false
        if ($ClassicMenu)       { $classic = $true }
        elseif ($NoClassicMenu) { $classic = $false }
        elseif ([Environment]::OSVersion.Version.Build -ge 22000) {
            Write-Host ''
            Say 'Windows 11 hides new right-click entries under "Show more options".' 'DarkGray'
            Say 'Jipeg can restore the classic menu so it appears directly.' 'DarkGray'
            Say 'Explorer restarts for about a second; your open windows stay open.' 'DarkGray'
            $classic = Read-YesNoTimed 'Show Jipeg directly in the right-click menu?' 15 $true
        }
        $psArgs += '-Silent'
        if ($classic) { $psArgs += '-ClassicMenu' }
        Write-Host ''
        Say 'Installing...'
    }

    $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $psArgs -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) { throw "The installer exited with code $($proc.ExitCode)." }

    Write-Host ''
    Say "Installed in $Dest" 'Green'
    Say 'Right-click an image  ->  Convert to JPEG (Jipeg)' 'Green'
    Say 'Settings are in the Start menu, under "Jipeg Settings".' 'DarkGray'
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
