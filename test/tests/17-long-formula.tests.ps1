# Task 17: LF — long-formula detector
# Fixture: MaintainabilityKitchenSink (extended with lblLong: a Label whose Text formula
#   is a long Concatenate string deliberately over ~292 bytes).
# Test uses CAA_LONG_FORMULA_BYTES=250 override to make the count deterministic.
#   At threshold 250, only lblLong exceeds the threshold.
#   At default threshold 500, lblLong (~292 bytes) does NOT exceed — so no LF fires in the
#   default suite run, and no other tests are affected.
#
# Expected with threshold=250:
#   Exactly 1 LF finding, naming lblLong.
#   lblTitle (Text: =gblTitle, tiny) is NOT an LF finding.
#
# Severity: Medium, Tier: narrative, Prefix: LF, Confidence: Confirmed.

$mech = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp' -EnvOverrides @{ CAA_LONG_FORMULA_BYTES = '250' }
Assert-True ($null -ne $mech) 'LF: kitchen-sink produced mechanical-findings.json'

# --- Test 1: exactly 1 LF finding at threshold 250 ---
[array]$lf = @(Get-Findings $mech 'LF')
Assert-Equal $lf.Count 1 'LF: exactly 1 LF finding at threshold 250 (only lblLong qualifies)'

# --- Test 2: the finding names lblLong ---
$lfFinding = $lf[0]
$lfText = "$($lfFinding.evidence) $($lfFinding.message) $($lfFinding.location.control)"
Assert-Match $lfText 'lblLong' 'LF: the single LF finding names lblLong'

# --- Test 3: lblTitle is NOT in LF findings (short formula =gblTitle) ---
[array]$titleLf = @($lf | Where-Object { $_.location.control -eq 'lblTitle' })
Assert-Equal $titleLf.Count 0 'LF: lblTitle (short formula) does NOT appear in LF findings'

# --- Test 4: correct structural fields ---
Assert-Equal $lfFinding.severity   'Medium'    'LF: severity is Medium'
Assert-Equal $lfFinding.tier       'narrative' 'LF: tier is narrative'
Assert-Equal $lfFinding.prefix     'LF'        'LF: prefix is LF'
Assert-Equal $lfFinding.confidence 'Confirmed' 'LF: confidence is Confirmed'

# --- Test 5: citation is non-empty ---
Assert-True (-not [string]::IsNullOrWhiteSpace($lfFinding.citation)) 'LF: finding has a non-empty citation'

# --- Test 6: evidence contains byte count ---
Assert-Match $lfFinding.evidence '\d+' 'LF: evidence contains a numeric byte count'
