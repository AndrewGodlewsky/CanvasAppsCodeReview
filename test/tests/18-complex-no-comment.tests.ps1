# Task 18: MC — complex formula with no explanatory comment
# Fixture: MaintainabilityKitchenSink (extended with lblComplexNoComment: a Label whose Text
#   formula uses If nesting depth 4, which reaches $T_DeepIfDepth (default 4), and has NO comment.
# Expected at DEFAULT thresholds:
#   Exactly 1 MC finding, naming lblComplexNoComment.
#   btnSubmit (has prose comment + commented-out Patch) must NOT be in MC findings.
#   CC still fires exactly once on btnSubmit (DoD #12 cross-check: CC/MC do not contradict).

$mech = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
Assert-True ($null -ne $mech) 'MC: kitchen-sink produced mechanical-findings.json'

# --- Test 1: exactly 1 MC finding at default thresholds ---
[array]$mc = @(Get-Findings $mech 'MC')
Assert-Equal $mc.Count 1 'MC: exactly 1 MC finding at default thresholds (only lblComplexNoComment qualifies)'

# --- Test 2: the MC finding names lblComplexNoComment ---
$mcFinding = $mc[0]
$mcText = "$($mcFinding.evidence) $($mcFinding.message) $($mcFinding.location.control)"
Assert-Match $mcText 'lblComplexNoComment' 'MC: the single MC finding names lblComplexNoComment'

# --- Test 3: btnSubmit must NOT be in MC findings (it has comments) ---
# This is DoD #12: CC and MC must not contradict each other.
# btnSubmit has BOTH a prose comment AND a commented-out Patch — CC fires on it; MC must NOT.
[array]$mcOnSubmit = @($mc | Where-Object { $_.location.control -eq 'btnSubmit' })
Assert-Equal $mcOnSubmit.Count 0 'MC DoD#12: btnSubmit (has comments) must NOT appear in MC findings'

# --- Test 4: CC still fires exactly once on btnSubmit (DoD #12 cross-check) ---
[array]$cc = @(Get-Findings $mech 'CC')
Assert-Equal $cc.Count 1 'MC DoD#12: CC still fires exactly once (one commented-out Patch on btnSubmit)'
$ccOnSubmit = $cc | Where-Object { $_.location.control -eq 'btnSubmit' }
Assert-True ($null -ne $ccOnSubmit) 'MC DoD#12: CC finding is on btnSubmit'

# --- Test 5: correct structural fields ---
Assert-Equal $mcFinding.severity   'Low'         'MC: severity is Low'
Assert-Equal $mcFinding.tier       'enumeration' 'MC: tier is enumeration'
Assert-Equal $mcFinding.prefix     'MC'          'MC: prefix is MC'
Assert-Equal $mcFinding.confidence 'Confirmed'   'MC: confidence is Confirmed'

# --- Test 6: citation is non-empty and references Comments section ---
Assert-True (-not [string]::IsNullOrWhiteSpace($mcFinding.citation)) 'MC: finding has a non-empty citation'
Assert-Match $mcFinding.citation 'Comments' 'MC: citation references the Comments section'
