# Task 15: DC — duplicate/redundant control detector
# Fixture: MaintainabilityKitchenSink (extended with lblDupeA and lblDupeB — identical Label
#   controls with matching type + property set — and lblDifferent whose Size differs).
#   lblDupeA  -> Label, Text="Same content", Color=RGBA(0,0,0,1), Size=15  -> GROUPED (DC)
#   lblDupeB  -> Label, Text="Same content", Color=RGBA(0,0,0,1), Size=15  -> GROUPED (DC)
#   lblDifferent -> Label, Text="Other content", Color=RGBA(0,0,0,1), Size=20 -> NOT grouped
# Expected: exactly 1 DC finding (the lblDupeA/lblDupeB group).

$mech = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
Assert-True ($null -ne $mech) 'DC: kitchen-sink produced mechanical-findings.json'

# --- Test 1: exactly 1 DC finding ---
[array]$dc = @(Get-Findings $mech 'DC')
Assert-Equal $dc.Count 1 'DC: exactly 1 DC finding (lblDupeA+lblDupeB group)'

# --- Test 2: the finding references both lblDupeA and lblDupeB ---
$dcFinding = $dc[0]
$dcText = "$($dcFinding.evidence) $($dcFinding.message)"
Assert-Match $dcText 'lblDupeA' 'DC: finding references lblDupeA'
Assert-Match $dcText 'lblDupeB' 'DC: finding references lblDupeB'

# --- Test 3: lblDifferent must NOT appear in the DC finding ---
Assert-True (-not ($dcText -imatch 'lblDifferent')) 'DC: lblDifferent must NOT appear in DC finding'

# --- Test 4: correct severity (Medium), tier (narrative), prefix (DC) ---
Assert-Equal $dcFinding.severity  'Medium'    'DC: severity is Medium'
Assert-Equal $dcFinding.tier      'narrative' 'DC: tier is narrative'
Assert-Equal $dcFinding.prefix    'DC'        'DC: prefix is DC'

# --- Test 5: DC finding has a non-empty citation ---
Assert-True (-not [string]::IsNullOrWhiteSpace($dcFinding.citation)) 'DC: finding has a non-empty citation'

# --- Test 6: confidence is Confirmed ---
Assert-Equal $dcFinding.confidence 'Confirmed' 'DC: confidence is Confirmed'
