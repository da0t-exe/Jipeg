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

  -Force runs it on demand from the Update button, which is the one case where
  the daily rhythm and the autoUpdate setting do not apply. Every other guard
  still does. Exit codes: 0 updated, 2 nothing to do, 3 could not.
#>
param([switch]$Force)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $Root 'Jipeg-Common.ps1')

$Work = Join-Path $env:TEMP ('jipeg-update-{0}' -f [guid]::NewGuid().ToString('N').Substring(0, 8))

# The sentence the settings window shows is in the user's language; the one
# written to the log stays in English. The log exists to be read by whoever is
# working out why an update has been failing for a week, and that reader should
# not have to guess which of ten languages the machine was set to.
$UiLang = Import-JipegLang (Get-JipegSettings).language
$EnLang = Import-JipegLang 'en'

function Save-Trace([string]$key, [object[]]$parts) {
    $shown = ''
    try {
        $s = Get-JipegSettings
        $s.lastCheck = [DateTime]::UtcNow.Ticks
        if ($key) { $shown = $UiLang[$key] -f $parts; $s.lastUpdate = $shown }
        Save-JipegSettings $s
    } catch { }
    # the settings file keeps the last word only; the log keeps all of them
    if ($key) { try { Write-JipegLog ('update   ' + ($EnLang[$key] -f $parts)) } catch { } }
}

try {
    $settings = Get-JipegSettings
    if (-not $Force -and -not $settings.autoUpdate) { exit 2 }

    # Never while the converter is working: cjpegli.exe would be locked and the
    # copy would fail halfway through. Presence alone is not the test - a
    # converter that was killed rather than closed leaves the file behind, and
    # testing for the file would then have switched quiet updates off for good.
    # What counts is whether anything still holds it open.
    $lock = Join-Path $env:TEMP 'jipeg.lock'
    if (Test-Path -LiteralPath $lock) {
        try {
            $fs = [System.IO.File]::Open($lock, 'Open', 'Write', 'None')
            $fs.Close()          # opened exclusively, so nobody else has it: stale
        } catch {
            exit 2               # still held, a conversion is running
        }
    }

    $rel = Get-JipegLatestRelease
    if (-not $rel) { exit 3 }                     # offline; try again tomorrow

    if ((Compare-JipegVersion $rel.Tag $JipegVersion) -le 0) {
        Save-Trace '' @()                         # already current
        exit 2
    }
    if (-not $rel.AssetUrl -or -not $rel.Digest) {
        Save-Trace 'trSkipped' @($rel.Tag)
        exit 3
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
        Save-Trace 'trRefused' @($rel.Tag)
        exit 3
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $Work)
    $setup = Get-ChildItem -Path $Work -Recurse -Filter 'Install-Jipeg.ps1' | Select-Object -First 1
    if (-not $setup) {
        Save-Trace 'trNoInstaller' @($rel.Tag)
        exit 3
    }

    # -Silent only. No -ClassicMenu, so nothing touches Explorer behind the
    # user's back; whatever they chose at install time stays as it is.
    $proc = Start-Process -FilePath 'powershell.exe' -PassThru -Wait -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $setup.FullName, '-Silent')

    if ($proc.ExitCode -eq 0) {
        Save-Trace 'trUpdated' @($rel.Tag, (Get-Date).ToString('d MMM yyyy'))
        $script:Code = 0
    } else {
        Save-Trace 'trFailed' @($rel.Tag, $proc.ExitCode)
        $script:Code = 3
    }
} catch {
    try { Save-Trace 'trCheckFail' @($_.Exception.Message) } catch { }
    $script:Code = 3
} finally {
    if (Test-Path -LiteralPath $Work) {
        Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
exit $(if ($null -ne $script:Code) { $script:Code } else { 3 })
