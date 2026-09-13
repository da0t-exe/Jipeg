$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$bad = 0
$files = & git -C $repo ls-files --cached --others --exclude-standard
if ($LASTEXITCODE -ne 0) { throw 'Could not list repository files.' }
$files | Where-Object { [IO.Path]::GetExtension($_) -in '.ps1', '.psd1' } | ForEach-Object {
    $file = Join-Path $repo $_
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)
    if ($errors.Count) {
        $bad += $errors.Count
        $errors | ForEach-Object { Write-Output $_ }
    }
}
"PowerShell parse errors: $bad"
exit $(if ($bad) { 1 } else { 0 })
