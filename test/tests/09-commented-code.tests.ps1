# Task 9: CC — commented-out code detector
# Fixture: MaintainabilityKitchenSink (extended with btnSubmit containing BOTH
# a prose comment and a commented-out Patch() statement).
# Expected: exactly 1 CC finding (the Patch line); the prose comment must NOT fire.

$mech = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
Assert-True ($null -ne $mech) 'CC: kitchen-sink produced mechanical-findings.json'

# --- Test 1: exactly 1 CC finding on the kitchen-sink fixture ---
# Note: force into a plain array so .Count is reliable even when ConvertFrom-Json returns
# a bare PSCustomObject for a single-element result (PowerShell 5.1 behavior).
[array]$ccFindings = @(Get-Findings $mech 'CC')
Assert-Equal $ccFindings.Count 1 'CC: exactly 1 CC finding (the commented-out Patch line)'

# --- Test 2: the CC finding's evidence/message references the Patch call ---
$ccFinding = $ccFindings | Select-Object -First 1
Assert-True ($null -ne $ccFinding) 'CC: CC finding object is not null'
$ccEvidence = if ($ccFinding) { "$($ccFinding.evidence) $($ccFinding.message)" } else { '' }
Assert-Match $ccEvidence 'Patch' 'CC: finding evidence or message references the Patch() call'

# --- Test 3: the prose comment line did NOT generate a CC finding (no false positive) ---
# If the count is exactly 1 (verified above) and that 1 references Patch, the prose is clean.
# Explicitly assert the prose text is not in any CC finding evidence.
$allCcEvidence = ($ccFindings | ForEach-Object { "$($_.evidence) $($_.message)" }) -join ' '
Assert-True (-not ($allCcEvidence -imatch 'Submit the order to the back end')) `
    'CC: prose comment "Submit the order to the back end" must NOT appear in any CC finding'

# --- Test 4: CC finding has correct severity (Low) and tier (enumeration) ---
if ($ccFinding) {
    Assert-Equal $ccFinding.severity 'Low' 'CC: severity is Low'
    Assert-Equal $ccFinding.tier 'enumeration' 'CC: tier is enumeration'
    Assert-Equal $ccFinding.prefix 'CC' 'CC: prefix is CC'
}

# --- Test 5: CC finding has a citation ---
if ($ccFinding) {
    Assert-True (-not [string]::IsNullOrWhiteSpace($ccFinding.citation)) 'CC: finding has a non-empty citation'
}
