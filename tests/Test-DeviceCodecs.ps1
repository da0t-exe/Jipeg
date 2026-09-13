# Test actual Windows WIC decoding of independently generated valid fixtures.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'src\Jipeg-Imaging.ps1')
$fixture = Join-Path $PSScriptRoot 'device-fixtures'
$results = Join-Path $PSScriptRoot 'device-results'
[void][IO.Directory]::CreateDirectory($results)
$report = foreach ($extension in '.heic', '.avif') {
    $source = Join-Path $fixture ('sample' + $extension)
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing fixture: $source. Run build-device-fixtures.py first." }
    $output = Join-Path $results ('decoded-' + $extension.Substring(1) + '.png')
    try {
        ConvertTo-JipegPng-Wic $source $output $extension
        [pscustomobject]@{ Format = $extension; Decoded = $true; Detail = 'Windows WIC decoded the fixture' }
    } catch {
        [pscustomobject]@{ Format = $extension; Decoded = $false; Detail = $_.Exception.Message }
    }
}
$report | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $results 'wic.json') -Encoding UTF8
$report | Format-Table -AutoSize
if (@($report | Where-Object { -not $_.Decoded }).Count) { exit 2 }
