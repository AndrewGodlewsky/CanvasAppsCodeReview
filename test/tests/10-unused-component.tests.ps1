# Task 10: UK — unused custom component detector
# Fixture: MaintainabilityKitchenSink
#   cmpHeader   -> defined, NEVER instantiated     -> flagged UK-01
#   cmpFooter   -> defined, instantiated on MainScreen via "Control: cmpFooter" -> NOT flagged

$mech = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
Assert-True ($null -ne $mech) 'UK: kitchen-sink produced mechanical-findings.json'

# --- Test 1: exactly 1 UK finding (only cmpHeader is unused) ---
[array]$uk = @(Get-Findings $mech 'UK')
Assert-Equal $uk.Count 1 'UK: exactly 1 UK finding (cmpHeader unused; cmpFooter is instantiated)'

# --- Test 2: the UK finding ID set is exactly {UK-01} ---
Assert-IdSet $uk @('UK-01') 'UK: finding ID set is exactly UK-01'

# --- Test 3: the UK finding evidence/message names cmpHeader ---
$ukFinding = $uk | Select-Object -First 1
$ukText = if ($ukFinding) { "$($ukFinding.evidence) $($ukFinding.message)" } else { '' }
Assert-Match $ukText 'cmpHeader' 'UK: finding references cmpHeader'

# --- Test 4: cmpFooter must NOT appear in any UK finding ---
$allUkText = ($uk | ForEach-Object { "$($_.evidence) $($_.message)" }) -join ' '
Assert-True (-not ($allUkText -imatch 'cmpFooter')) 'UK: cmpFooter must NOT appear in any UK finding'

# --- Test 5: correct severity (Medium) and tier (narrative) ---
if ($ukFinding) {
    Assert-Equal $ukFinding.severity  'Medium'    'UK: severity is Medium'
    Assert-Equal $ukFinding.tier      'narrative' 'UK: tier is narrative'
    Assert-Equal $ukFinding.prefix    'UK'        'UK: prefix is UK'
}

# --- Test 6: UK finding has a non-empty citation ---
if ($ukFinding) {
    Assert-True (-not [string]::IsNullOrWhiteSpace($ukFinding.citation)) 'UK: finding has a non-empty citation'
}
