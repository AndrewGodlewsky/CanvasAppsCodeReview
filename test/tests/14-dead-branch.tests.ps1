# Task 14: DB — dead conditional branch detector
# Fixture: MaintainabilityKitchenSink (extended with lblDead having If(false,...))
#   lblDead.Text  -> =If(false, "never", "always")   -> flagged DB (literal false as If condition)
#   lblLive.Text  -> =If(gblTitle <> "", "has title", "no title") -> NOT flagged (dynamic expr)
# Expected: exactly 1 DB finding (lblDead.Text); lblLive must NOT be flagged.

$mech = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
Assert-True ($null -ne $mech) 'DB: kitchen-sink produced mechanical-findings.json'

# --- Test 1: exactly 1 DB finding ---
[array]$db = @(Get-Findings $mech 'DB')
Assert-Equal $db.Count 1 'DB: exactly 1 DB finding (lblDead.Text has If(false,...))'

# --- Test 2: the DB finding identifies lblDead ---
$dbFinding = $db | Select-Object -First 1
$dbText = if ($dbFinding) { "$($dbFinding.evidence) $($dbFinding.message)" } else { '' }
Assert-Match $dbText 'lblDead' 'DB: finding references lblDead'

# --- Test 3: lblLive must NOT appear in any DB finding ---
$allDbText = ($db | ForEach-Object { "$($_.evidence) $($_.message)" }) -join ' '
Assert-True (-not ($allDbText -imatch 'lblLive')) 'DB: lblLive must NOT appear in any DB finding'

# --- Test 4: correct severity (Low), tier (enumeration), prefix (DB) ---
if ($dbFinding) {
    Assert-Equal $dbFinding.severity  'Low'         'DB: severity is Low'
    Assert-Equal $dbFinding.tier      'enumeration' 'DB: tier is enumeration'
    Assert-Equal $dbFinding.prefix    'DB'          'DB: prefix is DB'
}

# --- Test 5: DB finding has a non-empty citation ---
if ($dbFinding) {
    Assert-True (-not [string]::IsNullOrWhiteSpace($dbFinding.citation)) 'DB: finding has a non-empty citation'
}

# --- Test 6: confidence is Confirmed ---
if ($dbFinding) {
    Assert-Equal $dbFinding.confidence 'Confirmed' 'DB: confidence is Confirmed'
}
