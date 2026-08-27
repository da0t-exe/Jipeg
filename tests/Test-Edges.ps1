param(
    [string]$Dossier = (Join-Path $env:TEMP 'jipeg-edges'),
    [int]$Timeout = 120
)

# Les branches que PLAN.md portait comme jamais essayees, essayees pour de bon.
# Chaque cas est un fichier reel converti par la copie installee : rien n'est
# simule, et le compte-rendu dit ce qui est sorti, pas ce qui aurait du sortir.

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$root = Join-Path $env:LOCALAPPDATA 'Jipeg'
if (-not (Test-Path $root)) { throw "Jipeg n'est pas installe" }

. (Join-Path $root 'Jipeg-Common.ps1')
$reglages = Get-JipegSettings
$avant = $reglages.closeWhenDone
$reglages.closeWhenDone = $true
Save-JipegSettings $reglages

$resultats = @()

function Sorties([string]$chemin) {
    # Split-Path -LiteralPath -Parent n'existe pas en 5.1 : les deux parametres
    # appartiennent a des jeux differents. La methode .NET est litterale de toute
    # facon, ce qui est justement ce qu'il faut ici.
    $d = [IO.Path]::GetDirectoryName($chemin)
    $b = [IO.Path]::GetFileNameWithoutExtension($chemin)
    # StartsWith et pas -like : le premier essai comparait avec -like, et le cas
    # "crochets [1] et #diese" - dont l'objet est precisement que PowerShell lit
    # les crochets comme des jokers - a fait lire [1] comme une classe de
    # caracteres. Jipeg avait bien produit sa sortie ; c'est le banc qui ne la
    # voyait pas. Le test des jokers casse par un joker.
    Get-ChildItem -LiteralPath $d -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name.StartsWith($b + '_jipeg.', [StringComparison]::Ordinal) }
}

function Convertir {
    param([string[]]$Fichiers, [int]$Attente = 60)
    $args = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-STA',
              '-File', ('"' + (Join-Path $root 'Jipeg-Convert.ps1') + '"'))
    foreach ($f in $Fichiers) { $args += ('"' + $f + '"') }
    $p = Start-Process powershell.exe -PassThru -WindowStyle Hidden -ArgumentList $args
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while (-not $p.HasExited -and $sw.Elapsed.TotalSeconds -lt $Attente) { Start-Sleep -Milliseconds 300 }
    $tue = $false
    if (-not $p.HasExited) { [void]$p.CloseMainWindow(); Start-Sleep -Seconds 2 }
    if (-not $p.HasExited) { $p.Kill(); $tue = $true }
    [pscustomobject]@{ Secondes = [math]::Round($sw.Elapsed.TotalSeconds, 1); Tue = $tue }
}

function Cas {
    param([string]$Nom, [string]$Source, [int]$Attente = 60, [string]$Attendu = 'une sortie')
    if (-not (Test-Path -LiteralPath $Source)) {
        $script:resultats += [pscustomobject]@{ Cas = $Nom; Etat = 'ABSENT'; Detail = 'fichier introuvable' }
        return
    }
    foreach ($v in (Sorties $Source)) { Remove-Item -LiteralPath $v.FullName -Force }
    $r = Convertir -Fichiers @($Source) -Attente $Attente
    $out = @(Sorties $Source)
    $avantO = (Get-Item -LiteralPath $Source -Force).Length
    # Un refus peut etre la bonne reponse : une entree malformee doit echouer,
    # et compter cela comme un defaut donnerait un compte-rendu faux.
    if ($out.Count -eq 0) {
        $etat = if ($Attendu -eq 'refus') { 'refuse' } else { 'RIEN' }
        $detail = "aucune sortie apres $($r.Secondes)s" + $(if ($r.Tue) { ', fenetre tuee' } else { '' })
    } else {
        $etat = if ($Attendu -eq 'refus') { 'ACCEPTE' } else { 'ok' }
        $gain = [math]::Round(100 - ($out[0].Length * 100.0 / $avantO))
        $detail = "$($out[0].Name), $avantO -> $($out[0].Length) o (-$gain%), $($r.Secondes)s"
    }
    $script:resultats += [pscustomobject]@{ Cas = $Nom; Etat = $etat; Detail = $detail }
    "  {0,-22} {1,-7} {2}" -f $Nom, $etat, $detail
}

'--- 1.4 les noms, 1.1 les profils, 1.2 la taille ---'

Cas 'nom-crochets'   (Join-Path $Dossier 'crochets [1] et #diese.png')
Cas 'icc-adobergb-png' (Join-Path $Dossier 'icc-adobergb.png')
Cas 'icc-adobergb-jpg' (Join-Path $Dossier 'icc-adobergb.jpg')
# Ces deux-la portent un profil que le format n'admet pas - Lab et CMYK dans un
# PNG. Ce ne sont donc pas des tests de profil non sRGB mais de PNG malforme,
# et c'est a ce titre qu'on les garde : le logiciel doit refuser proprement.
Cas 'png-profil-illegal-lab'  (Join-Path $Dossier 'icc-lab.png')  30 'refus'
Cas 'png-profil-illegal-cmyk' (Join-Path $Dossier 'icc-swop.png') 30 'refus'
Cas 'grande-4200px'  (Join-Path $Dossier 'grande-4200px.png') 120

# --- chemin de 258 caracteres -------------------------------------------
# On exclut les sorties : trier par longueur decroissante avait choisi le
# _jipeg.png du passage precedent, long de 264 caracteres, et mesurait donc la
# relecture d'un chemin trop long au lieu de la conversion de la source.
$long = Get-ChildItem -LiteralPath $Dossier -Recurse -Filter 'l*.png' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '_jipeg' } |
        Sort-Object { $_.FullName.Length } -Descending | Select-Object -First 1
if ($long) { Cas 'chemin-258-car' $long.FullName } else {
    "  chemin-258-car         ABSENT  non fabrique"
}

# --- cache et systeme ----------------------------------------------------
foreach ($paire in @(@('cache.png', 'Hidden', 'fichier-cache'),
                     @('systeme.png', 'System', 'fichier-systeme'))) {
    $f = Join-Path $Dossier $paire[0]
    if (Test-Path -LiteralPath $f) {
        (Get-Item -LiteralPath $f -Force).Attributes = $paire[1]
        Cas $paire[2] $f
    }
}

'--- 1.3 le fichier lui-meme, 2.2 comment on le lance ---'

# --- clic droit sur un DOSSIER : le verbe Directory passe %V, un dossier ---
$lot = Join-Path $Dossier 'lot'
if (Test-Path -LiteralPath $lot) {
    Get-ChildItem -LiteralPath $lot -Force | Where-Object { $_.Name -match '_jipeg' } | Remove-Item -Force
    $n = @(Get-ChildItem -LiteralPath $lot -File).Count
    $r = Convertir -Fichiers @($lot) -Attente 600
    $faits = @(Get-ChildItem -LiteralPath $lot -File | Where-Object { $_.Name -match '_jipeg' }).Count
    $etat = if ($faits -eq $n) { 'ok' } elseif ($faits -eq 0) { 'RIEN' } else { 'PARTIEL' }
    $resultats += [pscustomobject]@{ Cas = 'clic-droit-dossier'; Etat = $etat
                                     Detail = "$faits sorties pour $n entrees, $($r.Secondes)s" }
    "  {0,-22} {1,-7} {2}" -f 'clic-droit-dossier', $etat, "$faits/$n en $($r.Secondes)s"
}

# --- source tenue ouverte par un autre processus -------------------------
$ouvert = Join-Path $Dossier 'ouverte-ailleurs.png'
if (Test-Path -LiteralPath $ouvert) {
    foreach ($v in (Sorties $ouvert)) { Remove-Item -LiteralPath $v.FullName -Force }
    # verrou exclusif : personne d'autre ne peut ni lire ni ecrire
    $fs = [IO.File]::Open($ouvert, 'Open', 'Read', 'None')
    try {
        $r = Convertir -Fichiers @($ouvert) -Attente 40
        $out = @(Sorties $ouvert)
    } finally { $fs.Close() }
    $etat = if ($out.Count -gt 0) { 'ok' } else { 'refuse' }
    $resultats += [pscustomobject]@{ Cas = 'source-verrouillee'; Etat = $etat
                                     Detail = "verrou exclusif pendant la conversion, $($r.Secondes)s" }
    "  {0,-22} {1,-7} {2}" -f 'source-verrouillee', $etat, "verrou exclusif, $($r.Secondes)s"
}

# --- dossier ou l'on ne peut pas ecrire ----------------------------------
$verrou = Join-Path $Dossier 'dossier-verrouille'
$dedans = Join-Path $verrou 'dedans.png'
if (Test-Path -LiteralPath $dedans) {
    foreach ($v in (Sorties $dedans)) { Remove-Item -LiteralPath $v.FullName -Force }
    $moi = "$env:USERDOMAIN\$env:USERNAME"
    & icacls $verrou /deny "${moi}:(WD,AD)" | Out-Null
    try {
        $r = Convertir -Fichiers @($dedans) -Attente 40
        $out = @(Sorties $dedans)
    } finally { & icacls $verrou /remove:d $moi | Out-Null }
    $etat = if ($out.Count -gt 0) { 'ACCEPTE' } else { 'refuse' }
    $resultats += [pscustomobject]@{ Cas = 'dossier-non-inscriptible'; Etat = $etat
                                     Detail = "ecriture refusee par ACL, $($r.Secondes)s" }
    "  {0,-22} {1,-7} {2}" -f 'dossier-non-inscriptible', $etat, "ecriture refusee, $($r.Secondes)s"
}

# --- ExecutionPolicy AllSigned, par le vrai point d'entree ---------------
# Le premier essai lancait le .ps1 directement avec -ExecutionPolicy AllSigned
# et concluait "bloque". C'etait vrai et sans interet : personne ne lance Jipeg
# ainsi. launch.vbs passe -ExecutionPolicy Bypass sur la ligne de commande, et
# la question est donc de savoir si ce Bypass tient face a une politique posee
# sur l'utilisateur. On la pose pour de vrai, et on la remet.
$temoin = Join-Path $Dossier 'systeme.png'
if (Test-Path -LiteralPath $temoin) {
    foreach ($v in (Sorties $temoin)) { Remove-Item -LiteralPath $v.FullName -Force }
    # Ce shell tourne lui-meme avec une portee Process a Bypass, plus prioritaire
    # que CurrentUser : Set-ExecutionPolicy y leve une exception. On passe donc
    # par un processus enfant, qui n'en herite pas.
    function PoserPolitique([string]$valeur) {
        $a = @('-NoProfile', '-NonInteractive', '-Command',
               ("Set-ExecutionPolicy $valeur -Scope CurrentUser -Force"))
        $q = Start-Process powershell.exe -PassThru -WindowStyle Hidden -ArgumentList $a
        $q.WaitForExit()
        (& powershell.exe -NoProfile -NonInteractive -Command 'Get-ExecutionPolicy -Scope CurrentUser').Trim()
    }
    $politiqueAvant = PoserPolitique 'Undefined'
    try {
        $pose = PoserPolitique 'AllSigned'
        $vbs = Join-Path $root 'launch.vbs'
        $p = Start-Process wscript.exe -PassThru -ArgumentList @(('"' + $vbs + '"'), ('"' + $temoin + '"'))
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ($sw.Elapsed.TotalSeconds -lt 30 -and (Sorties $temoin).Count -eq 0) { Start-Sleep -Milliseconds 400 }
        $out = @(Sorties $temoin)
    } finally {
        $rendue = PoserPolitique 'Undefined'
    }
    $etat = if ($out.Count -gt 0) { 'ok' } else { 'BLOQUE' }
    $resultats += [pscustomobject]@{ Cas = 'allsigned-par-launch-vbs'; Etat = $etat
        Detail = "politique posee a $pose puis rendue a $rendue" }
    "  {0,-24} {1,-7} {2}" -f 'allsigned-par-launch-vbs', $etat, "posee a $pose, rendue a $rendue"
}


'--- 1.2 la memoire, 1.4 les noms interdits, 2.3 pendant la course ---'

# --- 100 megapixels : la memoire, pas la taille du fichier ---------------
Cas 'panorama-100mp' (Join-Path $Dossier 'panorama-100mp.png') 300

# --- noms finissant par une espace ou un point --------------------------
# Win32 les refuse par les chemins ordinaires. Ils existent sur le disque, mais
# tout ce qui passe par l'API classique les tronque : la question est de savoir
# ce que fait Jipeg quand l'Explorateur lui en tend un.
$prefixe = [char]92 + [char]92 + '?' + [char]92
# Ces deux-la sont crees par CreateFileW : Python les avait fabriques via open(),
# qui passe par la CRT et retire le caractere final, si bien que les deux
# premieres executions testaient des fichiers parfaitement ordinaires.
foreach ($paire in @(@('brut-espace.png ', 'nom-finit-espace'),
                     @('brut-point.png.', 'nom-finit-point'))) {
    $brut = Join-Path $Dossier $paire[0]
    $existe = [IO.File]::Exists($prefixe + $brut)
    if (-not $existe) {
        $resultats += [pscustomobject]@{ Cas = $paire[1]; Etat = 'ABSENT'; Detail = 'non fabrique' }
        continue
    }
    $r = Convertir -Fichiers @($brut) -Attente 30
    # la sortie, si elle existe, s'appellerait <base>_jipeg.png sans le suffixe
    $attendu = Join-Path $Dossier (($paire[0] -replace '\.png.$', '') + '_jipeg.png')
    $tout = [IO.Directory]::GetFiles($prefixe + $Dossier)
    $sortie = [IO.File]::Exists($attendu) -or (@(Sorties $brut).Count -gt 0) -or
              (@($tout | Where-Object { $_ -match '_jipeg' -and $_ -match 'brut-' }).Count -gt 0)
    $etat = if ($sortie) { 'ok' } else { 'refuse' }
    $resultats += [pscustomobject]@{ Cas = $paire[1]; Etat = $etat
        Detail = "nom cree via \?\, passe tel quel, $($r.Secondes)s" }
    "  {0,-24} {1,-7} {2}" -f $paire[1], $etat, "$($r.Secondes)s"
}

# --- la source renommee pendant la conversion ---------------------------
# Test-DuringRun couvrait la suppression ; le renommage est l'autre moitie.
$course = Join-Path $Dossier 'course'
if (Test-Path -LiteralPath $course) { Remove-Item -LiteralPath $course -Recurse -Force }
New-Item -ItemType Directory -Path $course | Out-Null
$gros = Join-Path $Dossier 'panorama-100mp.png'
$src = @()
foreach ($k in 1..6) {
    $c = Join-Path $course ("c$k.png")
    Copy-Item -LiteralPath $gros -Destination $c
    $src += $c
}
$args2 = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-STA',
           '-File', ('"' + (Join-Path $root 'Jipeg-Convert.ps1') + '"'))
foreach ($f in $src) { $args2 += ('"' + $f + '"') }
$pp = Start-Process powershell.exe -PassThru -WindowStyle Hidden -ArgumentList $args2
Start-Sleep -Milliseconds 2500
$renomme = $false
foreach ($f in $src[3..5]) {
    try { Rename-Item -LiteralPath $f -NewName ([IO.Path]::GetFileName($f) + '.renomme'); $renomme = $true } catch { }
}
$sw = [Diagnostics.Stopwatch]::StartNew()
while (-not $pp.HasExited -and $sw.Elapsed.TotalSeconds -lt 300) { Start-Sleep -Milliseconds 400 }
if (-not $pp.HasExited) { [void]$pp.CloseMainWindow(); Start-Sleep -Seconds 2 }
if (-not $pp.HasExited) { $pp.Kill() }
$restants = @(Get-ChildItem -LiteralPath $course -File -Force)
$sorties = @($restants | Where-Object { $_.Name -match '_jipeg' })
$perdus = @($src | Where-Object { -not [IO.File]::Exists($_) -and -not [IO.File]::Exists($_ + '.renomme') })
$etat = if ($perdus.Count -eq 0) { 'ok' } else { 'PERTE' }
$resultats += [pscustomobject]@{ Cas = 'source-renommee-pendant'; Etat = $etat
    Detail = "$($sorties.Count) sorties, $($perdus.Count) originaux perdus, renommage $renomme, $([math]::Round($sw.Elapsed.TotalSeconds,1))s" }
"  {0,-24} {1,-7} {2}" -f 'source-renommee-pendant', $etat, "$($sorties.Count) sorties, $($perdus.Count) perdus"

'  ---'
$reglages = Get-JipegSettings
$reglages.closeWhenDone = $avant
Save-JipegSettings $reglages

$resultats | Format-Table -AutoSize | Out-String -Width 120
$mauvais = @($resultats | Where-Object { $_.Etat -ne 'ok' -and $_.Etat -ne 'refuse' })
"  {0} cas, {1} conformes, {2} a regarder" -f $resultats.Count, ($resultats.Count - $mauvais.Count), $mauvais.Count
