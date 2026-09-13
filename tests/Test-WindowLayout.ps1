# Construct the real settings UI without starting its message loop or network check.
# Measures geometry; this is not a visual or physical mixed-DPI validation.
param([double]$Scale = 1.0)
$ErrorActionPreference = 'Stop'
$env:JIPEG_SCALE = $Scale.ToString([Globalization.CultureInfo]::InvariantCulture)
$repo = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repo 'src\Jipeg-Settings.ps1'
$source = Get-Content -LiteralPath $sourcePath -Raw
$source = $source.Replace('$Root = Split-Path -Parent $MyInvocation.MyCommand.Path',
    ('$Root = ''' + (Join-Path $repo 'src').Replace("'", "''") + ''''))
$stop = $source.LastIndexOf('[System.Windows.Forms.Application]::Run($form)')
if ($stop -lt 0) { throw 'Could not locate the UI message loop.' }
. ([scriptblock]::Create($source.Substring(0, $stop)))
try {
    $overflow = New-Object Collections.Generic.List[string]
    function Check-Children($control) {
        foreach ($child in $control.Controls) {
            if ($child.Left -lt 0 -or $child.Top -lt 0 -or
                $child.Right -gt ($control.ClientSize.Width + 2) -or
                $child.Bottom -gt ($control.ClientSize.Height + 2)) {
                $overflow.Add(('{0}: {1}' -f $child.GetType().Name, $child.Text))
            }
            Check-Children $child
        }
    }
    Check-Children $form
    $result = foreach ($screen in [Windows.Forms.Screen]::AllScreens) {
        [pscustomobject]@{
            RequestedScale = $Scale
            EffectiveScale = $JipegScale
            Screen = $screen.DeviceName
            Primary = $screen.Primary
            WorkWidth = $screen.WorkingArea.Width
            WorkHeight = $screen.WorkingArea.Height
            WindowWidth = $form.Width
            WindowHeight = $form.Height
            FitsScreen = ($form.Width -le $screen.WorkingArea.Width -and $form.Height -le $screen.WorkingArea.Height)
            Overflow = @($overflow.ToArray())
        }
    }
    $results = Join-Path $PSScriptRoot 'device-results'
    [void][IO.Directory]::CreateDirectory($results)
    $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $results ('layout-' + $env:JIPEG_SCALE + '.json')) -Encoding UTF8
    $result | Format-Table RequestedScale,EffectiveScale,Screen,WindowWidth,WindowHeight,FitsScreen
    if ($overflow.Count -or @($result | Where-Object { -not $_.FitsScreen }).Count) {
        $overflow | Write-Output
        exit 1
    }
} finally { $form.Dispose() }
