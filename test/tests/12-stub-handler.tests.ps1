# Task 12: EH — stub/empty event handler detector
# Fixture: MaintainabilityKitchenSink (extended with btnStub having OnSelect: =false)
#   btnStub.OnSelect  -> =false stub                     -> flagged EH
#   btnSubmit.OnSelect -> real multi-statement formula   -> NOT flagged
# Expected: exactly 1 EH finding (btnStub.OnSelect)

$mech = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
Assert-True ($null -ne $mech) 'EH: kitchen-sink produced mechanical-findings.json'

# --- Test 1: exactly 1 EH finding ---
[array]$eh = @(Get-Findings $mech 'EH')
Assert-Equal $eh.Count 1 'EH: exactly 1 EH finding (btnStub.OnSelect = false stub)'

# --- Test 2: the EH finding identifies btnStub and OnSelect ---
$ehFinding = $eh | Select-Object -First 1
$ehText = if ($ehFinding) { "$($ehFinding.evidence) $($ehFinding.message)" } else { '' }
Assert-Match $ehText 'btnStub' 'EH: finding references btnStub'
Assert-Match $ehText 'OnSelect' 'EH: finding references OnSelect'

# --- Test 3: btnSubmit's OnSelect must NOT appear in any EH finding ---
$allEhText = ($eh | ForEach-Object { "$($_.evidence) $($_.message)" }) -join ' '
Assert-True (-not ($allEhText -imatch 'btnSubmit')) 'EH: btnSubmit must NOT appear in any EH finding'

# --- Test 4: correct severity (Low), tier (enumeration), prefix (EH) ---
if ($ehFinding) {
    Assert-Equal $ehFinding.severity  'Low'         'EH: severity is Low'
    Assert-Equal $ehFinding.tier      'enumeration' 'EH: tier is enumeration'
    Assert-Equal $ehFinding.prefix    'EH'          'EH: prefix is EH'
}

# --- Test 5: EH finding has a non-empty citation ---
if ($ehFinding) {
    Assert-True (-not [string]::IsNullOrWhiteSpace($ehFinding.citation)) 'EH: finding has a non-empty citation'
}

# --- Test 6: confidence is Confirmed ---
if ($ehFinding) {
    Assert-Equal $ehFinding.confidence 'Confirmed' 'EH: confidence is Confirmed'
}
