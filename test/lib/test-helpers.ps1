# Native (Pester-free) test helpers for the Canvas App Analyzer test suite.
# Dot-sourced by run-tests.ps1 before any *.tests.ps1 file runs.

$script:TestPass = 0; $script:TestFail = 0; $script:Failures = @()

function Assert-True($cond, $msg) {
    if ($cond) { $script:TestPass++ }
    else { $script:TestFail++; $script:Failures += $msg; Write-Host "  FAIL: $msg" -ForegroundColor Red }
}
function Assert-Equal($actual, $expected, $msg) {
    Assert-True ($actual -eq $expected) "$msg (expected '$expected', got '$actual')"
}
function Assert-Match($text, $pattern, $msg) {
    Assert-True ([bool]($text -match $pattern)) "$msg (no match /$pattern/)"
}
function Assert-IdSet($findings, $expectedIds, $msg) {
    $got = @($findings | ForEach-Object { $_.id } | Sort-Object)
    $exp = @($expectedIds | Sort-Object)
    Assert-True (($got -join ',') -eq ($exp -join ',')) "$msg (expected [$($exp -join ',')], got [$($got -join ',')])"
}

# Repo root is two levels up from this file (test/lib -> test -> repo).
$script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$script:_analyzerCache = @{}
# Runs analyze-canvas.ps1 against a fixture; caches per (fixture, env-overrides).
# Returns @{ Mech = <parsed mechanical-findings.json>; Index = <parsed index.json>; OutDir = <path> }
# but for back-compat the bare parsed mechanical-findings object is returned (with
# .__index and .__outDir attached) so existing assertions keep working.
function Invoke-Analyzer {
    param([string]$Fixture, [hashtable]$EnvOverrides = @{})
    $key = $Fixture + '|' + (($EnvOverrides.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ';')
    if ($script:_analyzerCache.ContainsKey($key)) { return $script:_analyzerCache[$key] }

    $script = Join-Path $script:RepoRoot 'skills\canvas-app-analyzer\scripts\analyze-canvas.ps1'
    $fixturePath = Join-Path $script:RepoRoot "test\fixtures\$Fixture"
    $outRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('caatest_' + [Guid]::NewGuid().ToString('N'))

    $saved = @{}
    foreach ($k in $EnvOverrides.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $EnvOverrides[$k]) }
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Path $fixturePath -OutputRoot $outRoot | Out-Null
        $mf = Get-ChildItem -Path $outRoot -Recurse -Filter 'mechanical-findings.json' -ErrorAction SilentlyContinue | Select-Object -First 1
        $ix = Get-ChildItem -Path $outRoot -Recurse -Filter 'index.json' -ErrorAction SilentlyContinue | Select-Object -First 1
        $result = if ($mf) { Get-Content -LiteralPath $mf.FullName -Raw | ConvertFrom-Json } else { $null }
        if ($result) {
            $idx = if ($ix) { Get-Content -LiteralPath $ix.FullName -Raw | ConvertFrom-Json } else { $null }
            $result | Add-Member -NotePropertyName '__index' -NotePropertyValue $idx -Force
            $result | Add-Member -NotePropertyName '__outDir' -NotePropertyValue $outRoot -Force
        }
    } finally {
        foreach ($k in $EnvOverrides.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    }
    $script:_analyzerCache[$key] = $result
    return $result
}

function Get-Findings($mech, [string]$Prefix) { @($mech.deterministicFindings | Where-Object { $_.prefix -eq $Prefix }) }
function Get-Leads($mech) { @($mech.leads) }
