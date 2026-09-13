$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$dir = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\lang'
$codes = 'en','fr','es','de','pt','it','pl','ru','ja','zh'
$en = Import-PowerShellDataFile (Join-Path $dir 'en.psd1')
$bad = 0
foreach ($c in $codes) {
    $p = Join-Path $dir ($c + '.psd1')
    if (-not (Test-Path $p)) { "$c : FICHIER ABSENT"; $bad++; continue }
    $t = Import-PowerShellDataFile $p
    $miss = @($en.Keys | Where-Object { -not $t.ContainsKey($_) })
    $extra = @($t.Keys | Where-Object { -not $en.ContainsKey($_) })
    # every {0}/{1} in the English line has to survive the translation, or the
    # formatted message comes out with a hole in it
    $ph = @()
    foreach ($k in $en.Keys) {
        if (-not $t.ContainsKey($k)) { continue }
        $a = [regex]::Matches($en[$k], '\{\d\}') | ForEach-Object { $_.Value } | Sort-Object -Unique
        $b = [regex]::Matches($t[$k],  '\{\d\}') | ForEach-Object { $_.Value } | Sort-Object -Unique
        if (($a -join ',') -ne ($b -join ',')) { $ph += $k }
    }
    $flag = 'ok'
    if ($miss.Count -or $extra.Count -or $ph.Count) { $flag = 'PROBLEME'; $bad++ }
    '{0,-3} {1,3} cles  manquantes {2}  en trop {3}  placeholders {4}  {5}' -f
        $c, $t.Count, $miss.Count, $extra.Count, $ph.Count, $flag
    if ($ph.Count) { '     -> ' + ($ph -join ', ') }
    if ($miss.Count) { '     -> manquantes: ' + ($miss -join ', ') }
}
''
if ($bad) { "$bad fichier(s) a corriger" } else { "10/10 fichiers de langue conformes" }
exit $(if ($bad) { 1 } else { 0 })
