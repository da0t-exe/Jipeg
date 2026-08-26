# Everything that happens while a batch is running. Until now the converter was
# only ever watched from start to finish with nothing interrupting it, which
# leaves the queue, the watcher, the lock and the teardown untested - the four
# parts most likely to be wrong in a program that runs other processes.
#
# Four things are asked of every scenario, whatever it does to the window:
#   the process exits, nothing is left in the folder, nothing is left in %TEMP%,
#   and every file that did come out opens as an image.
param([int]$Files = 14)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Root = Join-Path $env:LOCALAPPDATA 'Jipeg'
Add-Type -AssemblyName System.Drawing
Add-Type -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumProc p, IntPtr l);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern IntPtr SendMessageW(IntPtr h, int m, IntPtr w, IntPtr l);
[DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, int m, IntPtr w, IntPtr l);
public delegate bool EnumProc(IntPtr h, IntPtr l);
'@ -Name 'W' -Namespace 'Dr' | Out-Null

$fautes = 0
function Note($ok, $quoi, $detail) {
    if (-not $ok) { $script:fautes++ }
    '    {0}  {1,-36} {2}' -f $(if ($ok) { 'ok  ' } else { 'RATE' }), $quoi, $detail
}

function New-Lot([string]$dir, [int]$n) {
    if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $rnd = New-Object Random 3
    for ($i = 0; $i -lt $n; $i++) {
        $bmp = New-Object System.Drawing.Bitmap(560, 420)
        for ($y = 0; $y -lt 420; $y += 1) {
            for ($x = 0; $x -lt 560; $x += 1) {
                $bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(
                    ($x + $rnd.Next(24)) % 256, ($y * 2 + $i) % 256, (160 - $x / 6) % 256))
            }
        }
        $bmp.Save((Join-Path $dir ('p{0:D2}.png' -f $i)), [System.Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
    }
}

function Start-Batch([string]$dir) {
    $files = Get-ChildItem -LiteralPath $dir -File |
             Where-Object { $_.Name -notlike '*_jipeg*' } | ForEach-Object { $_.FullName }
    return Start-Process powershell.exe -PassThru -WindowStyle Hidden -ArgumentList (
        @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-STA', '-File',
          ('"' + (Join-Path $Root 'Jipeg-Convert.ps1') + '"')) +
        ($files | ForEach-Object { '"' + $_ + '"' }))
}

function Get-Fenetre {
    for ($i = 0; $i -lt 60; $i++) {
        $p = Get-Process | Where-Object { $_.MainWindowTitle -eq 'Jipeg' } | Select-Object -First 1
        if ($p -and $p.MainWindowHandle -ne 0) { return $p.MainWindowHandle }
        Start-Sleep -Milliseconds 250
    }
    return [IntPtr]::Zero
}

function Get-Bouton([IntPtr]$fenetre) {
    $script:trouve = [IntPtr]::Zero
    $cb = [Dr.W+EnumProc] {
        param($h, $l)
        $cn = New-Object System.Text.StringBuilder 128
        [void][Dr.W]::GetClassNameW($h, $cn, 128)
        if ($cn.ToString() -match 'BUTTON') { $script:trouve = $h; return $false }
        return $true
    }
    [void][Dr.W]::EnumChildWindows($fenetre, $cb, [IntPtr]::Zero)
    return $script:trouve
}

function Test-Proprete([string]$dir, [string]$quoi) {
    $restes = @(Get-ChildItem -LiteralPath $dir -Filter '.jipeg-*' -Force -ErrorAction SilentlyContinue)
    Note ($restes.Count -eq 0) "$quoi : rien laisse dans le dossier" ('{0} reste(s)' -f $restes.Count)
    $tmp = @(Get-ChildItem -LiteralPath $env:TEMP -Filter 'jipeg-in-*' -ErrorAction SilentlyContinue) +
           @(Get-ChildItem -LiteralPath $env:TEMP -Filter 'jipeg-raw-*' -ErrorAction SilentlyContinue) +
           @(Get-ChildItem -LiteralPath $env:TEMP -Filter 'jipeg-g-*' -ErrorAction SilentlyContinue)
    Note ($tmp.Count -eq 0) "$quoi : rien laisse dans TEMP" ('{0} reste(s)' -f $tmp.Count)
    Note (-not (Test-Path -LiteralPath (Join-Path $env:TEMP 'jipeg.lock'))) "$quoi : le verrou est rendu" ''
    $casse = 0; $sortis = 0
    foreach ($f in (Get-ChildItem -LiteralPath $dir -Filter '*_jipeg.*' -ErrorAction SilentlyContinue)) {
        $sortis++
        try { $im = [System.Drawing.Image]::FromFile($f.FullName); $im.Dispose() } catch { $casse++ }
    }
    Note ($casse -eq 0) "$quoi : les sorties s ouvrent" ('{0} produite(s), {1} cassee(s)' -f $sortis, $casse)
}

function Wait-Fin($p, [int]$secondes) {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $p.HasExited -and $sw.Elapsed.TotalSeconds -lt $secondes) { Start-Sleep -Milliseconds 200 }
    return $p.HasExited
}

# Sans cela, une fenetre qui a termine reste ouverte a attendre un OK - et
# garde le verrou avec elle. Le premier passage a compte ca comme un blocage et
# comme un verrou non rendu, alors que c'est le reglage par defaut qui parlait.
. (Join-Path $Root 'Jipeg-Common.ps1')
$reglages = Get-JipegSettings
$avantClose = $reglages.closeWhenDone
$reglages.closeWhenDone = $true
Save-JipegSettings $reglages

$base = Join-Path $env:TEMP ('jipeg-during-{0}' -f [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $base -Force | Out-Null
Get-ChildItem -LiteralPath $env:TEMP -Filter 'jipeg-*' -ErrorAction SilentlyContinue |
    Remove-Item -Force -Recurse -ErrorAction SilentlyContinue

try {
    # ------------------------------------------------------- 1. Annuler
    'On appuie sur Annuler au milieu du lot'
    $d1 = Join-Path $base 'annuler'
    New-Lot $d1 $Files
    $p = Start-Batch $d1
    $h = Get-Fenetre
    Note ($h -ne [IntPtr]::Zero) 'annuler : la fenetre est la' ''
    $b = Get-Bouton $h
    Note ($b -ne [IntPtr]::Zero) 'annuler : le bouton est trouve' ''
    Start-Sleep -Milliseconds 900          # assez pour etre dedans, pas pour finir
    [void][Dr.W]::SendMessageW($b, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)   # BM_CLICK
    Start-Sleep -Seconds 4
    # La preuve qu'une annulation a mordu n'est pas dans le titre : c'est qu'il
    # manque des sorties. Le premier passage cliquait apres la fin du lot et
    # trouvait douze sur douze, sans rien annuler du tout.
    $faits = @(Get-ChildItem -LiteralPath $d1 -Filter '*_jipeg.*').Count
    Note ($faits -lt $Files) 'annuler : le lot s est arrete avant la fin' (
        '{0} sortie(s) sur {1}' -f $faits, $Files)
    # Une conversion annulee garde sa fenetre expres, pour qu'on lise le compte,
    # meme avec la fermeture automatique demandee.
    Note (-not $p.HasExited) 'annuler : la fenetre reste, comme voulu' 'elle attend un OK'
    [void][Dr.W]::PostMessageW($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)   # WM_CLOSE
    Note (Wait-Fin $p 30) 'annuler : le processus se termine' ''
    if (-not $p.HasExited) { $p.Kill() }
    Test-Proprete $d1 'annuler'
    ''

    # ------------------------------------------------------- 2. La croix
    'On ferme par la croix pendant que ca travaille'
    $d2 = Join-Path $base 'croix'
    New-Lot $d2 $Files
    $p = Start-Batch $d2
    $h = Get-Fenetre
    Start-Sleep -Seconds 3
    [void][Dr.W]::PostMessageW($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    Note (Wait-Fin $p 30) 'croix : le processus se termine' ''
    if (-not $p.HasExited) { $p.Kill() }
    Start-Sleep -Seconds 2
    Test-Proprete $d2 'croix'
    ''

    # ------------------------------------------------------- 3. Deux a la fois
    'Deux conversions lancees en meme temps'
    $d3 = Join-Path $base 'deux-a'
    $d4 = Join-Path $base 'deux-b'
    New-Lot $d3 6
    New-Lot $d4 6
    $pa = Start-Batch $d3
    Start-Sleep -Milliseconds 600
    $pb = Start-Batch $d4
    $finA = Wait-Fin $pa 180
    $finB = Wait-Fin $pb 180
    foreach ($q in $pa, $pb) { if (-not $q.HasExited) { $q.Kill() } }
    Note ($finA -and $finB) 'deux : les deux se terminent' ('a {0}, b {1}' -f $finA, $finB)
    $na = @(Get-ChildItem -LiteralPath $d3 -Filter '*_jipeg.*').Count
    $nb = @(Get-ChildItem -LiteralPath $d4 -Filter '*_jipeg.*').Count
    Note ($na + $nb -eq 12) 'deux : aucun fichier perdu' ('{0} + {1} sur 12' -f $na, $nb)
    Test-Proprete $d3 'deux'
    ''

    # ------------------------------------------- 4. La source disparait
    'On supprime une source pendant le lot'
    $d5 = Join-Path $base 'disparu'
    New-Lot $d5 $Files
    $p = Start-Batch $d5
    [void](Get-Fenetre)
    Start-Sleep -Seconds 2
    $cible = Get-ChildItem -LiteralPath $d5 -Filter 'p1*.png' | Select-Object -Last 1
    if ($cible) { Remove-Item -LiteralPath $cible.FullName -Force -ErrorAction SilentlyContinue }
    Note ($null -ne $cible) 'disparu : une source a ete supprimee' $(if ($cible) { $cible.Name } else { '' })
    $fin = Wait-Fin $p 180
    if (-not $p.HasExited) { [void][Dr.W]::PostMessageW((Get-Fenetre), 0x0010, [IntPtr]::Zero, [IntPtr]::Zero); $fin = Wait-Fin $p 30 }
    if (-not $p.HasExited) { $p.Kill() }
    Note $fin 'disparu : le lot va au bout quand meme' ''
    Test-Proprete $d5 'disparu'
} finally {
    Get-Process | Where-Object { $_.MainWindowTitle -eq 'Jipeg' } | ForEach-Object { $_.Kill() }
    $reglages = Get-JipegSettings
    $reglages.closeWhenDone = $avantClose
    Save-JipegSettings $reglages
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}
''
if ($fautes) { "  $fautes ecart(s)" } else { '  rien ne casse et rien ne traine, quoi qu on fasse pendant' }
exit $(if ($fautes) { 1 } else { 0 })
