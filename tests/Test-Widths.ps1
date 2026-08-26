# Measures every translated string against the box it has to fit in. A label is
# a fixed rectangle: text longer than it is simply cut off, and there is no way
# to see that except by measuring it.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
# On mesure les sources, pas la copie installee : c'est le depot qu'on verifie.
$src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
. (Join-Path $src 'Jipeg-Common.ps1')

# key, available width in design units, which font
# Une entree dont la cle contient un + designe une etiquette qui affiche
# plusieurs chaines collees par un saut de ligne. Mesurees une par une, deux
# d'entre elles tenaient largement ; collees, la derniere ligne passait sous les
# boutons. On mesure ce qui est affiche, pas ce qui est stocke.
#
# lignes : combien de lignes le cadre peut montrer. Sans cette limite on ne
# verifie que la largeur, et un texte qui se replie une fois de trop est coupe
# en bas sans que rien ne le dise.
$BOXES = @(
    @{ k = 'inChkHint+inRestart'; w = 456; f = 'hint'; lignes = 3 }
    @{ k = 'inWhere+inNoAdmin';   w = 480; f = 'hint'; lignes = 2 }
    @{ k = 'lblQuality';  w = 176; f = 'body' }   # label column, up to the field at 204
    @{ k = 'lblChroma';   w = 176; f = 'body' }
    @{ k = 'lblLanguage'; w = 176; f = 'body' }
    @{ k = 'lblTheme';    w = 176; f = 'body' }
    @{ k = 'hintQuality'; w = 468; f = 'hint' }
    @{ k = 'hintChroma';  w = 468; f = 'hint' }
    @{ k = 'hintTheme';   w = 468; f = 'hint' }
    @{ k = 'hintMica';    w = 442; f = 'hint' }
    @{ k = 'hintAuto';    w = 442; f = 'hint' }
    @{ k = 'hintClose';   w = 442; f = 'hint' }
    @{ k = 'chkMica';     w = 442; f = 'body' }   # AutoSize, but the card stops here
    @{ k = 'chkAuto';     w = 442; f = 'body' }
    @{ k = 'chkClose';    w = 442; f = 'body' }
    @{ k = 'btnCheck';    w = 152; f = 'body' }   # 160 button less its padding
    @{ k = 'btnUpdate';   w = 152; f = 'body' }
    @{ k = 'btnUpToDate'; w = 152; f = 'body' }
    @{ k = 'btnOK';       w = 92;  f = 'body' }
    @{ k = 'btnCancel';   w = 92;  f = 'body' }
    @{ k = 'secConv';       w = 400; f = 'section' }
    @{ k = 'secAppearance'; w = 400; f = 'section' }
    @{ k = 'secUpdates';    w = 400; f = 'section' }
    @{ k = 'secFinish';     w = 400; f = 'section' }
    @{ k = 'updChecking';   w = 320; f = 'hint' }
    @{ k = 'updNoReach';    w = 320; f = 'hint' }
    @{ k = 'updLatest';     w = 320; f = 'hint' }
    @{ k = 'updNoStart';    w = 320; f = 'hint' }
    @{ k = 'updInstalled';  w = 320; f = 'hint' }
    @{ k = 'updNothing';    w = 320; f = 'hint' }
    @{ k = 'updFailed';     w = 320; f = 'hint' }
)
$fonts = @{ body = $JipegFont; hint = $JipegFontHint; section = $JipegFontSection }
$flags = [System.Windows.Forms.TextFormatFlags]::NoPrefix
$bad = 0
foreach ($code in $JipegLangs.Keys) {
    $L = Import-JipegLang $code
    $over = @()
    foreach ($b in $BOXES) {
        $txt = (($b.k -split '\+') | ForEach-Object { [string]$L[$_] }) -join [Environment]::NewLine
        if (-not $txt.Trim()) { continue }
        if ($b.lignes) {
            # repliee dans la largeur reelle : c'est la hauteur qui deborde
            $sz = [System.Windows.Forms.TextRenderer]::MeasureText(
                    $txt, $fonts[$b.f], (New-Object System.Drawing.Size($b.w, 1000)),
                    ($flags -bor [System.Windows.Forms.TextFormatFlags]::WordBreak))
            $h1 = [System.Windows.Forms.TextRenderer]::MeasureText('Ag', $fonts[$b.f]).Height
            $lignes = [math]::Ceiling($sz.Height / [double]$h1)
            if ($lignes -gt $b.lignes) {
                $over += ('{0} tient sur {1} lignes, {2} prevues' -f $b.k, $lignes, $b.lignes)
            }
            continue
        }
        $px = [System.Windows.Forms.TextRenderer]::MeasureText(
                $txt, $fonts[$b.f], (New-Object System.Drawing.Size(10000, 100)), $flags).Width
        if ($px -gt $b.w) { $over += ('{0} {1}>{2}' -f $b.k, $px, $b.w) }
    }
    if ($over.Count) {
        $bad++
        '{0} : {1} DEBORDENT' -f $code, $over.Count
        foreach ($o in $over) { '      ' + $o }
    } else {
        '{0} : tout tient' -f $code
    }
}
''
if ($bad) { "$bad langue(s) a reprendre" } else { '10/10 : aucune chaine ne deborde de sa boite' }
