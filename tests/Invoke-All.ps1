# Runs the whole suite in one pass, in an order that does not have the tests
# fighting each other: the static checks first, then the ones that uninstall and
# reinstall, then everything that converts, and the interrupted-batch scenarios
# last so the lock is nobody else's business.
#
# Nothing stops on the first failure. A run that halts halfway tells you about
# one thing; a run that finishes tells you about all of them.
param([int]$Seeds = 2, [switch]$Quick)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Repo = Split-Path -Parent $PSScriptRoot
$T = $PSScriptRoot
$resultats = New-Object System.Collections.Generic.List[object]

function Etape([string]$nom, [scriptblock]$quoi) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host ('  {0,-40} ' -f $nom) -NoNewline
    $sortie = ''
    $ok = $true
    try {
        $sortie = (& $quoi 2>&1 | Out-String)
        $ok = ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE)
    } catch {
        $ok = $false
        $sortie = $_.Exception.Message
    }
    $sw.Stop()
    Write-Host $(if ($ok) { 'ok' } else { 'RATE' }) -NoNewline
    Write-Host ('   {0,6:N0}s' -f $sw.Elapsed.TotalSeconds)
    $resultats.Add([pscustomobject]@{ Nom = $nom; Ok = $ok; Secondes = $sw.Elapsed.TotalSeconds; Sortie = $sortie })
}

function Ps1([string]$script, [string[]]$arguments = @()) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $T $script) @arguments
}

''
'Ce qui ne demande que de lire les fichiers'
Etape 'encodages, fins de ligne, octets nuls' { & python (Join-Path $T 'check-encoding.py') }
Etape 'la page et ses dix traductions'        { & python (Join-Path $T 'check-site.py') }
Etape 'fonctions et variables mortes'         { & python (Join-Path $T 'check-dead-code.py') }
Etape 'contrastes, echelle, rythme'           { & python (Join-Path $T 'check-design.py') }
Etape 'dechiffrement, image par image'        { & node (Join-Path $T 'banc-dechiffrement.js') }
Etape 'tout le PowerShell parse' {
    $mauvais = 0
    foreach ($f in (Get-ChildItem (Join-Path $Repo 'src') -Filter '*.ps1') +
                   (Get-ChildItem $T -Filter '*.ps1') +
                   (Get-Item (Join-Path $Repo 'install.ps1')) +
                   (Get-Item (Join-Path $Repo 'uninstall.ps1')) +
                   (Get-Item (Join-Path $Repo 'Build-Release.ps1'))) {
        $e = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$e)
        if ($e.Count) { $mauvais++; "$($f.Name) : $($e[0].Message)" }
    }
    $global:LASTEXITCODE = $mauvais
}
Etape 'les cles de langue et leurs {0}'       { Ps1 'Test-Languages.ps1' }
Etape 'chaque chaine dans sa boite'           { Ps1 'Test-Widths.ps1' }

''
'Ce qui installe et desinstalle'
Etape 'l archive se fabrique' {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Repo 'Build-Release.ps1') -Out $env:TEMP
}
$zip = Join-Path $env:TEMP ('Jipeg-{0}.zip' -f (
    (Select-String -LiteralPath (Join-Path $Repo 'src\Jipeg-Common.ps1') `
        -Pattern "JipegVersion\s*=\s*'([^']+)'" | Select-Object -First 1).Matches[0].Groups[1].Value))
Etape 'l archive s installe et convertit'     { Ps1 'Test-Release.ps1' @('-Zip', $zip) }
Etape 'cycles installation/desinstallation'   { Ps1 'Test-InstallCycle.ps1' @('-Tours', $(if ($Quick) { '3' } else { '8' })) }

''
'Ce qui convertit'
Etape 'la grille des reglages'                { Ps1 'Test-Settings.ps1' $(if ($Quick) { @('-Quick') } else { @() }) }
Etape 'le lot de 48, resultat ecrit d avance' {
    & python (Join-Path $T 'corpus-build.py') | Out-Null
    Ps1 'Invoke-Corpus.ps1' @('-Folder', 'corpus', '-Timeout', '900') | Out-Null
    & python (Join-Path $T 'corpus-check.py')
}
for ($i = 0; $i -lt $Seeds; $i++) {
    $graine = @(4242, 7, 1337, 90210)[$i % 4]
    Etape ("le lot aleatoire, graine $graine") {
        & python (Join-Path $T 'fuzz-build.py') $graine | Out-Null
        Ps1 'Invoke-Corpus.ps1' @('-Folder', 'random', '-Timeout', '900') | Out-Null
        & python (Join-Path $T 'fuzz-check.py')
    }
}

''
'Ce qui derange la conversion pendant qu elle tourne'
Etape 'annuler, la croix, deux a la fois, une source qui disparait' {
    Ps1 'Test-DuringRun.ps1' @('-Files', $(if ($Quick) { '12' } else { '24' }))
}

''
'Ce que l antivirus de la machine en dit'
Etape 'Windows Defender'                      { Ps1 'Test-Defender.ps1' @('-Zip', $zip) }

Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue

# ------------------------------------------------------------------ bilan
''
'=================================================================='
$rates = @($resultats | Where-Object { -not $_.Ok })
'{0} etapes, {1:N0} secondes en tout' -f $resultats.Count, ($resultats | Measure-Object Secondes -Sum).Sum
if ($rates.Count -eq 0) {
    'tout passe'
} else {
    '{0} etape(s) en echec :' -f $rates.Count
    foreach ($r in $rates) {
        ''
        '--- {0} ---' -f $r.Nom
        ($r.Sortie -split "`n" | Where-Object { $_.Trim() } | Select-Object -Last 12) |
            ForEach-Object { '    ' + $_.TrimEnd() }
    }
}
exit $rates.Count
