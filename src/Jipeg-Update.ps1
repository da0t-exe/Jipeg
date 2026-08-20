<#
  Quiet update. Started detached and hidden after a conversion, at most once a
  day. Shows nothing, ever - the only trace is a line in the settings window
  saying what it did.

  What it will and will not do:
    - only the release feed of one fixed repository, over HTTPS
    - only a strictly higher version than the one installed
    - the archive is rejected unless it matches the SHA-256 GitHub publishes
    - nothing runs while a conversion is in flight
    - the only thing executed is that release's own installer, silently
  Turn it off in the settings window and this script never runs.
#>
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $Root 'Jipeg-Common.ps1')

$Work = Join-Path $env:TEMP ('jipeg-update-{0}' -f [guid]::NewGuid().ToString('N').Substring(0, 8))

function Save-Trace([string]$text) {
    try {
        $s = Get-JipegSettings
        $s.lastCheck = [DateTime]::UtcNow.Ticks
        if ($text) { $s.lastUpdate = $text }
        Save-JipegSettings $s
    } catch { }
}

try {
    $settings = Get-JipegSettings
    if (-not $settings.autoUpdate) { exit }

    # never while the converter is working: cjpegli.exe would be locked and the
    # copy would fail halfway through
    if (Test-Path -LiteralPath (Join-Path $env:TEMP 'jipeg.lock')) { exit }

    $rel = Get-JipegLatestRelease
    if (-not $rel) { exit }                       # offline; try again tomorrow

    if ((Compare-JipegVersion $rel.Tag $JipegVersion) -le 0) {
        Save-Trace ''                             # already current
        exit
    }
    if (-not $rel.AssetUrl -or -not $rel.Digest) {
        Save-Trace "Skipped $($rel.Tag): no checksummed archive published."
        exit
    }

    New-Item -ItemType Directory -Path $Work -Force | Out-Null
    $zip = Join-Path $Work 'jipeg.zip'
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add('User-Agent', 'Jipeg-Updater')
    $wc.DownloadFile($rel.AssetUrl, $zip)
    $wc.Dispose()

    $actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    if ($actual -ne $rel.Digest) {
        Save-Trace "Refused $($rel.Tag): checksum did not match."
        exit
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $Work)
    $setup = Get-ChildItem -Path $Work -Recurse -Filter 'Install-Jipeg.ps1' | Select-Object -First 1
    if (-not $setup) {
        Save-Trace "Skipped $($rel.Tag): the archive had no installer."
        exit
    }

    # -Silent only. No -ClassicMenu, so nothing touches Explorer behind the
    # user's back; whatever they chose at install time stays as it is.
    $proc = Start-Process -FilePath 'powershell.exe' -PassThru -Wait -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $setup.FullName, '-Silent')

    if ($proc.ExitCode -eq 0) {
        Save-Trace ("Updated to {0} on {1}." -f $rel.Tag, (Get-Date).ToString('d MMM yyyy'))
    } else {
        Save-Trace "Update to $($rel.Tag) failed (exit $($proc.ExitCode))."
    }
} catch {
    try { Save-Trace ("Update check failed: " + $_.Exception.Message) } catch { }
} finally {
    if (Test-Path -LiteralPath $Work) {
        Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
