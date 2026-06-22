# Task 22: RL — repeated-literals detector (narrative, Medium, Confirmed)
# Fixture: MaintainabilityKitchenSink (extended with lblRepA/B/C in MainScreen)
#
# Three controls planted that each use "SharedConstantToken_RL" in 3 distinct formulas:
#   - lblRepA.Text:  ="SharedConstantToken_RL"
#   - lblRepB.Text:  =Concatenate("SharedConstantToken_RL", " suffix")
#   - lblRepC.Text:  =If(gblZebra > 0, "SharedConstantToken_RL", "other")
#
# "SharedConstantToken_RL" appears in 3 DISTINCT formulas → exactly ONE RL finding.
# A once-used literal (e.g. lblMagic's 8675309) must NOT be an RL finding.
#
# Total expected RL count: 1 (only SharedConstantToken_RL reaches the threshold of 3
# distinct formulas; verified by running against the grown fixture before committing).

$mech = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
Assert-True ($null -ne $mech) 'RL: kitchen-sink produced mechanical-findings.json'

# --- Test 1: exactly ONE RL finding for SharedConstantToken_RL ---
[array]$rlShared = @($mech.deterministicFindings | Where-Object {
    $_.prefix -eq 'RL' -and
    ($_.evidence -match 'SharedConstantToken_RL' -or $_.message -match 'SharedConstantToken_RL')
})
Assert-Equal $rlShared.Count 1 'RL: exactly one RL finding for SharedConstantToken_RL'

# --- Test 2: that finding lists 3 distinct locations (check evidence field) ---
$rlFinding = $rlShared[0]
# Evidence lists locations as "src/<file>:<line>" entries separated by "; "
[array]$locationMatches = @([regex]::Matches($rlFinding.evidence, 'src/[^;:)]+:\d+'))
Assert-Equal $locationMatches.Count 3 'RL: SharedConstantToken_RL finding lists 3 distinct locations'

# --- Test 3: structural fields of the RL finding ---
Assert-Equal $rlFinding.severity   'Medium'    'RL: severity is Medium'
Assert-Equal $rlFinding.tier       'narrative' 'RL: tier is narrative'
Assert-Equal $rlFinding.prefix     'RL'        'RL: prefix is RL'
Assert-Equal $rlFinding.confidence 'Confirmed' 'RL: confidence is Confirmed'

# --- Test 4: citation is non-empty ---
Assert-True (-not [string]::IsNullOrWhiteSpace($rlFinding.citation)) 'RL: finding has a non-empty citation'

# --- Test 5: a once-used literal (8675309) is NOT in any RL finding ---
[array]$rlForMagicNum = @($mech.deterministicFindings | Where-Object {
    $_.prefix -eq 'RL' -and
    ($_.evidence -match '8675309' -or $_.message -match '8675309')
})
Assert-Equal $rlForMagicNum.Count 0 'RL: once-used literal 8675309 does NOT produce an RL finding'

# --- Test 6: total RL count is exactly 1 ---
# Verified: no other literal in the kitchen-sink fixture reaches 3 distinct formulas.
# (The " - " separator appears in 2 formulas (lblNdA, lblNdB); "Guest" appears in 2;
#  "Same content" appears in 2 (lblDupeA, lblDupeB); "15" (Size) appears in 2 formulas.)
[array]$allRl = @(Get-Findings $mech 'RL')
Assert-Equal $allRl.Count 1 'RL: total RL finding count is 1'
