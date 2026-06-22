# Task 8: verify-report.ps1 narrative/leads reconciliation (D4)
# Uses FieldServiceApp (has High/Medium/Low findings + leads) to test the reconciler.

$repo     = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$verify   = Join-Path $repo 'skills\canvas-app-analyzer\scripts\verify-report.ps1'

$mech = Invoke-Analyzer -Fixture 'FieldServiceApp.msapp'

Assert-True ($null -ne $mech) 'FieldServiceApp produced mechanical-findings.json'

# Locate the actual mechanical-findings.json file on disk (needed by verify-report.ps1)
$mfFile = Get-ChildItem $mech.__outDir -Recurse -Filter 'mechanical-findings.json' -ErrorAction SilentlyContinue | Select-Object -First 1
Assert-True ($null -ne $mfFile) 'mechanical-findings.json found on disk'

$mfPath = $mfFile.FullName

# Build the required-id set:
#   - All High/Medium deterministic finding ids
#   - All lead ids
$highMedIds = @($mech.deterministicFindings | Where-Object { $_.severity -in 'High', 'Medium' } | ForEach-Object { $_.id })
$leadIds    = @($mech.leads | ForEach-Object { $_.id })
$required   = @($highMedIds) + @($leadIds)

# Also collect Low finding ids (for the negative assertion)
$lowIds = @($mech.deterministicFindings | Where-Object { $_.severity -eq 'Low' } | ForEach-Object { $_.id })

Assert-True ($required.Count -gt 0) "FieldServiceApp has at least one High/Medium finding or lead (got $($required.Count))"

# --- Test 1: complete case — report mentions every required id ---
$completePath = Join-Path ([IO.Path]::GetTempPath()) ('rep_' + [Guid]::NewGuid().ToString('N') + '.md')
($required -join "`n") | Out-File $completePath -Encoding utf8

$r1 = & powershell -NoProfile -ExecutionPolicy Bypass -File $verify -ReportPath $completePath -FindingsPath $mfPath | ConvertFrom-Json
Assert-True ($null -ne $r1) 'verify-report.ps1 produced JSON for complete report'
Assert-True ($r1.complete -eq $true) 'complete report -> complete:true (DoD #3)'
Assert-Equal (@($r1.missing).Count)            0 'complete report -> missing is empty'
Assert-Equal (@($r1.unaddressedLeads).Count)   0 'complete report -> unaddressedLeads is empty'

# --- Test 2: incomplete case — omit the first required id ---
$incompletePath = Join-Path ([IO.Path]::GetTempPath()) ('rep_' + [Guid]::NewGuid().ToString('N') + '.md')
(($required | Select-Object -Skip 1) -join "`n") | Out-File $incompletePath -Encoding utf8

$r2 = & powershell -NoProfile -ExecutionPolicy Bypass -File $verify -ReportPath $incompletePath -FindingsPath $mfPath | ConvertFrom-Json
Assert-True ($null -ne $r2) 'verify-report.ps1 produced JSON for incomplete report'
Assert-True ($r2.complete -eq $false) 'incomplete report -> complete:false (DoD #3)'
$omittedId = $required[0]
$allReported = @($r2.missing) + @($r2.unaddressedLeads)
Assert-True ($allReported -contains $omittedId) "names the exact missing id '$omittedId'"

# --- Test 3: Low-severity findings are NOT required in the narrative ---
if ($lowIds.Count -gt 0) {
    $lowOnlyPath = Join-Path ([IO.Path]::GetTempPath()) ('rep_' + [Guid]::NewGuid().ToString('N') + '.md')
    # Report contains every required id but intentionally omits all Low ids
    ($required -join "`n") | Out-File $lowOnlyPath -Encoding utf8

    $r3 = & powershell -NoProfile -ExecutionPolicy Bypass -File $verify -ReportPath $lowOnlyPath -FindingsPath $mfPath | ConvertFrom-Json
    $lowAbsentFromMissing = -not ($lowIds | Where-Object { @($r3.missing) -contains $_ })
    Assert-True $lowAbsentFromMissing 'Low-severity finding ids NOT required in narrative (not in missing)'
} else {
    # No Low findings in this fixture — skip gracefully
    Assert-True $true 'Low-severity skip: no Low findings in FieldServiceApp (ok)'
}
