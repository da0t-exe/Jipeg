# Runs the antivirus that is actually on this machine against the things that
# get published: the archive, the installed folder, and the scripts themselves.
#
# This is worth more than a VirusTotal verdict on the four .exe files, which are
# unmodified releases from libjxl, libwebp and oxipng and are already known
# everywhere. The part nobody has scanned is the PowerShell: an installer that
# writes to the registry and fetches a zip from the internet is the exact shape
# heuristics are tuned to notice.
param([string]$Zip)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Repo = Split-Path -Parent $PSScriptRoot
$mp = 'C:\Program Files\Windows Defender\MpCmdRun.exe'
if (-not (Test-Path -LiteralPath $mp)) { '  MpCmdRun.exe is not on this machine.'; exit 2 }

try {
    $st = Get-MpComputerStatus
    '  engine on: {0}   signatures dated {1}' -f $st.RealTimeProtectionEnabled,
        $st.AntivirusSignatureLastUpdated.ToString('d MMM yyyy')
} catch { '  Get-MpComputerStatus said: ' + $_.Exception.Message }
''

$cibles = @(
    @{ n = 'the scripts as written'; p = (Join-Path $Repo 'src') },
    @{ n = 'the console installer';  p = (Join-Path $Repo 'install.ps1') },
    @{ n = 'the installed folder';   p = (Join-Path $env:LOCALAPPDATA 'Jipeg') }
)
if ($Zip) { $cibles += @{ n = 'the published archive'; p = $Zip } }

$fautes = 0
foreach ($c in $cibles) {
    if (-not (Test-Path -LiteralPath $c.p)) {
        '  {0,-24} not here' -f $c.n
        continue
    }
    # MpCmdRun wants a Windows path. Handed one with forward slashes it answers
    # the same 0x80508023 as an excluded folder, which reads as a verdict and
    # is not one.
    $c.p = (Resolve-Path -LiteralPath $c.p).ProviderPath
    # -DisableRemediation: it reports and does not quarantine. Being told a file
    # was deleted while looking at it is not the experiment.
    $sortie = & $mp -Scan -ScanType 3 -File $c.p -DisableRemediation 2>&1 | Out-String
    # 0x80508023 comes back for anything under an excluded path, and this
    # machine excludes %LOCALAPPDATA% - the same archive copied to Documents
    # scans clean in a second. That is a path that cannot be scanned, not a
    # verdict, and counting it as a failure would be a lie in the other
    # direction. The exclusion list needs an administrator to read.
    if ($sortie -match '0x80508023') {
        '  {0,-24} not scannable from here - the path looks excluded' -f $c.n
        continue
    }
    $propre = ($sortie -match 'found no threats')
    if (-not $propre) { $fautes++ }
    $ligne = ($sortie -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 1)
    '  {0,-24} {1}' -f $c.n, $(if ($propre) { 'clean' } else { $ligne.Trim() })
}
''
if ($fautes) { "  $fautes of them were not reported clean" }
else { '  Defender reports nothing on any of them' }
'  (one engine, on one machine, today. It says nothing about the twenty others.)'
exit $(if ($fautes) { 1 } else { 0 })
