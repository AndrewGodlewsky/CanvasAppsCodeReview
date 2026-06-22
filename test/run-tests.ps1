<#  Native test runner for the Canvas App Analyzer suite (no Pester / no modules).
    Rebuilds all fixtures, dot-sources lib + every tests/*.tests.ps1, prints a
    PASS/FAIL summary, and exits non-zero on any failure. #>
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

& (Join-Path $here 'build-fixture.ps1') | Out-Null            # regenerate all fixtures
. (Join-Path $here 'lib\test-helpers.ps1')

foreach ($t in Get-ChildItem (Join-Path $here 'tests') -Filter '*.tests.ps1' | Sort-Object Name) {
    Write-Host "RUN $($t.Name)" -ForegroundColor Cyan
    . $t.FullName
}

Clear-AnalyzerTemp   # remove this run's analyzer output dirs from %TEMP%

Write-Host ""
Write-Host "PASS=$script:TestPass FAIL=$script:TestFail" -ForegroundColor $(if ($script:TestFail) { 'Red' } else { 'Green' })
if ($script:TestFail -gt 0) { exit 1 } else { exit 0 }
