param([string]$Folder = 'corpus', [int]$Timeout = 600)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$dir  = Join-Path $PSScriptRoot $Folder
$root = Join-Path $env:LOCALAPPDATA 'Jipeg'

# La fenetre reste ouverte jusqu'a OK par defaut : pour un lot on la fait se
# fermer seule, sinon on mesure le temps d'attente et pas la conversion.
. (Join-Path $root 'Jipeg-Common.ps1')
$s = Get-JipegSettings
$avant = $s.closeWhenDone
$s.closeWhenDone = $true
Save-JipegSettings $s

# tous les fichiers, y compris celui qui porte deja le suffixe _jipeg
$files = Get-ChildItem -LiteralPath $dir -File |
         Where-Object { $_.Name -notlike '*_jipeg.jpg' -and $_.Name -notlike '*_jipeg.png' } |
         ForEach-Object { $_.FullName }
$files += (Get-ChildItem -LiteralPath $dir -File |
           Where-Object { $_.Name -eq '58-deja-converti_jipeg.png' } |
           ForEach-Object { $_.FullName })
$files = $files | Select-Object -Unique
"  {0} fichiers passes a la conversion" -f $files.Count

$p = Start-Process powershell.exe -PassThru -WindowStyle Hidden -ArgumentList (
    @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-STA','-File',
      ('"' + (Join-Path $root 'Jipeg-Convert.ps1') + '"')) +
    ($files | ForEach-Object { '"' + $_ + '"' }))
$sw = [System.Diagnostics.Stopwatch]::StartNew()
while (-not $p.HasExited -and $sw.Elapsed.TotalSeconds -lt $Timeout) { Start-Sleep -Milliseconds 500 }
if (-not $p.HasExited) { [void]$p.CloseMainWindow(); Start-Sleep -Seconds 3 }
if (-not $p.HasExited) { $p.Kill(); '  ATTENTION : la fenetre a du etre tuee' }
'  termine en {0}s' -f [math]::Round($sw.Elapsed.TotalSeconds, 1)

$s = Get-JipegSettings
$s.closeWhenDone = $avant
Save-JipegSettings $s
