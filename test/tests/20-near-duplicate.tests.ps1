# Task 20: ND — near-duplicate formula detector (Levenshtein)
# Fixture: MaintainabilityKitchenSink (extended with lblNdA and lblNdB)
#   lblNdA.Text = =If(gblTitle = "Kitchen Sink Demo App", Concatenate("Welcome to ", gblTitle, " main dashboard view"), "Default application title goes here")
#   lblNdB.Text = =If(gblTitle = "Kitchen Sink Demo App", Concatenate("Welcome to ", gblTitle, " main homepage view"), "Default application title goes here")
#
# After struct-normalization (lowercase + collapse whitespace + blank string-literal contents),
# both formulas become structurally IDENTICAL (differ only in "dashboard" vs "homepage" inside
# string literals). Levenshtein ratio = 1.0 >= $T_NearDupRatio (0.90) → ND fires.
# Raw texts differ → XD does NOT fire; and ND's raw-identical-skip does NOT exclude them.
#
# Expected: exactly 1 ND finding (the lblNdA/lblNdB cluster).
#
# The planted exact-duplicate pair (lblDupeA/lblDupeB, Text: ="Same content") is:
#   (a) too short to reach $T_NearDupMinLen (60 chars), AND
#   (b) raw-identical → would be skipped by the raw-identical guard in ND even if long enough.
#   → Must NOT appear in ND findings.
#
# Severity: Medium, Tier: narrative, Prefix: ND, Confidence: Confirmed.

$mech = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
Assert-True ($null -ne $mech) 'ND: kitchen-sink produced mechanical-findings.json'

# --- Test 1: exactly 1 ND finding ---
[array]$nd = @(Get-Findings $mech 'ND')
Assert-Equal $nd.Count 1 'ND: exactly 1 ND finding (lblNdA/lblNdB cluster)'

# --- Test 2: the finding references both lblNdA and lblNdB ---
$ndFinding = $nd[0]
$ndText = "$($ndFinding.evidence) $($ndFinding.message)"
Assert-Match $ndText 'lblNdA' 'ND: finding references lblNdA'
Assert-Match $ndText 'lblNdB' 'ND: finding references lblNdB'

# --- Test 3: the planted exact-duplicate pair must NOT appear in ND findings ---
[array]$ndOnDupe = @($nd | Where-Object {
    $txt = "$($_.evidence) $($_.message)"
    $txt -imatch 'lblDupeA' -or $txt -imatch 'lblDupeB'
})
Assert-Equal $ndOnDupe.Count 0 'ND: lblDupeA/lblDupeB (exact dups, short) must NOT appear in ND findings'

# --- Test 4: correct structural fields ---
Assert-Equal $ndFinding.severity   'Medium'    'ND: severity is Medium'
Assert-Equal $ndFinding.tier       'narrative' 'ND: tier is narrative'
Assert-Equal $ndFinding.prefix     'ND'        'ND: prefix is ND'
Assert-Equal $ndFinding.confidence 'Confirmed' 'ND: confidence is Confirmed'

# --- Test 5: citation is non-empty ---
Assert-True (-not [string]::IsNullOrWhiteSpace($ndFinding.citation)) 'ND: finding has a non-empty citation'
