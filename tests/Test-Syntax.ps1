$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$bad = 0
Get-ChildItem -LiteralPath $repo -Recurse -File | Where-Object {
    $_.Extension -in '.ps1', '.psd1' -and $_.FullName -notlike '*\.git\*'
} | ForEach-Object {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count) {
        $bad += $errors.Count
        $errors | ForEach-Object { Write-Output $_ }
    }
}
"PowerShell parse errors: $bad"
exit $(if ($bad) { 1 } else { 0 })
