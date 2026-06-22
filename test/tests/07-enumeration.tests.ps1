# Task 7: script-generated enumeration.md + summary.md (D2)
# Uses FieldServiceApp (has default names, unused var, duplicate formulas, orphan screen).

$mech = Invoke-Analyzer -Fixture 'FieldServiceApp.msapp'

Assert-True ($null -ne $mech) 'FieldServiceApp produced mechanical-findings.json'

# --- Test 1: enumeration.md is generated (exists, non-empty) ---
$enumFile = Get-ChildItem $mech.__outDir -Recurse -Filter 'enumeration.md' -ErrorAction SilentlyContinue | Select-Object -First 1
Assert-True ($null -ne $enumFile) 'enumeration.md generated'
Assert-True ($enumFile -ne $null -and $enumFile.Length -gt 0) 'enumeration.md is non-empty'

$enumTxt = if ($enumFile) { Get-Content -LiteralPath $enumFile.FullName -Raw } else { '' }

# --- Test 2: completeness (DoD #2) - every deterministicFinding id appears in enumeration.md ---
foreach ($f in $mech.deterministicFindings) {
    Assert-Match $enumTxt ([regex]::Escape($f.id)) "enumeration lists $($f.id) (type=$($f.type)) (DoD #2)"
}

# --- Test 3: summary.md is generated and contains required content ---
$summaryFile = Get-ChildItem $mech.__outDir -Recurse -Filter 'summary.md' -ErrorAction SilentlyContinue | Select-Object -First 1
Assert-True ($null -ne $summaryFile) 'summary.md generated'

$summaryTxt = if ($summaryFile) { Get-Content -LiteralPath $summaryFile.FullName -Raw } else { '' }

# summary.md must contain all six category names
$expectedCategories = @(
    'Maintainability',
    'Dead',
    'Redundancy',
    'Delegation',
    'Performance',
    'Error handling'
)
foreach ($cat in $expectedCategories) {
    Assert-Match $summaryTxt $cat "summary.md contains category '$cat'"
}

# summary.md must contain a total deterministic findings count
$totalCount = $mech.deterministicFindings.Count
Assert-Match $summaryTxt ([regex]::Escape([string]$totalCount)) "summary.md contains total finding count ($totalCount)"

# --- Test 4: status.json files map includes enumeration and summary keys ---
$statusFile = Get-ChildItem $mech.__outDir -Recurse -Filter 'status.json' -ErrorAction SilentlyContinue | Select-Object -First 1
Assert-True ($null -ne $statusFile) 'status.json exists'
if ($statusFile) {
    $statusJson = Get-Content -LiteralPath $statusFile.FullName -Raw | ConvertFrom-Json
    Assert-True ($statusJson.files.PSObject.Properties.Name -contains 'enumeration') 'status.json files.enumeration present'
    Assert-True ($statusJson.files.PSObject.Properties.Name -contains 'summary') 'status.json files.summary present'
}
