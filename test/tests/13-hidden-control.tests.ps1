# Task 13: HC — permanently hidden control detector
# Fixture: MaintainabilityKitchenSink (extended with lblHidden having Visible: =false)
#   lblHidden.Visible  -> =false literal                   -> flagged HC
#   lblDynamic.Visible -> =gblTitle <> ""  (dynamic expr)  -> NOT flagged
# Expected: exactly 1 HC finding (lblHidden); lblDynamic must NOT be flagged.

$mech = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
Assert-True ($null -ne $mech) 'HC: kitchen-sink produced mechanical-findings.json'

# --- Test 1: exactly 1 HC finding ---
[array]$hc = @(Get-Findings $mech 'HC')
Assert-Equal $hc.Count 1 'HC: exactly 1 HC finding (lblHidden.Visible = false)'

# --- Test 2: the HC finding identifies lblHidden ---
$hcFinding = $hc | Select-Object -First 1
$hcText = if ($hcFinding) { "$($hcFinding.evidence) $($hcFinding.message)" } else { '' }
Assert-Match $hcText 'lblHidden' 'HC: finding references lblHidden'

# --- Test 3: lblDynamic must NOT appear in any HC finding ---
$allHcText = ($hc | ForEach-Object { "$($_.evidence) $($_.message)" }) -join ' '
Assert-True (-not ($allHcText -imatch 'lblDynamic')) 'HC: lblDynamic must NOT appear in any HC finding'

# --- Test 4: correct severity (Low), tier (enumeration), prefix (HC) ---
if ($hcFinding) {
    Assert-Equal $hcFinding.severity  'Low'         'HC: severity is Low'
    Assert-Equal $hcFinding.tier      'enumeration' 'HC: tier is enumeration'
    Assert-Equal $hcFinding.prefix    'HC'          'HC: prefix is HC'
}

# --- Test 5: HC finding has a non-empty citation ---
if ($hcFinding) {
    Assert-True (-not [string]::IsNullOrWhiteSpace($hcFinding.citation)) 'HC: finding has a non-empty citation'
}

# --- Test 6: confidence is Confirmed ---
if ($hcFinding) {
    Assert-Equal $hcFinding.confidence 'Confirmed' 'HC: confidence is Confirmed'
}
