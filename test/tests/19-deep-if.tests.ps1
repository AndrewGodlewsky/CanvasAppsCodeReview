# Task 19: DI — deep If/Switch nesting detector
# Fixture: MaintainabilityKitchenSink (reuses lblComplexNoComment from Task 18)
#   lblComplexNoComment.Text =If (gblTitle = "a", 1, If (gblTitle = "b", 2, If (gblTitle = "c", 3, If (gblTitle = "d", 4, 5))))
#   This has If/Switch nesting depth 4. At the default $T_DeepIfDepth = 4, DI fires.
# Expected at DEFAULT thresholds:
#   Exactly 1 DI finding, naming lblComplexNoComment.
#   lblLive (Text: =If(gblTitle <> "", ...)) has depth 1 — must NOT fire DI.
# Note: DI and MC BOTH fire on lblComplexNoComment — correct; different prefixes.

$mech = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
Assert-True ($null -ne $mech) 'DI: kitchen-sink produced mechanical-findings.json'

# --- Test 1: exactly 1 DI finding at default thresholds ---
[array]$di = @(Get-Findings $mech 'DI')
Assert-Equal $di.Count 1 'DI: exactly 1 DI finding at default thresholds (only lblComplexNoComment reaches depth 4)'

# --- Test 2: the DI finding names lblComplexNoComment ---
$diFinding = $di[0]
$diText = "$($diFinding.evidence) $($diFinding.message) $($diFinding.location.control)"
Assert-Match $diText 'lblComplexNoComment' 'DI: the single DI finding names lblComplexNoComment'

# --- Test 3: lblLive (depth-1 If) must NOT appear in DI findings ---
[array]$diOnLive = @($di | Where-Object { $_.location.control -eq 'lblLive' })
Assert-Equal $diOnLive.Count 0 'DI: lblLive (depth-1 If) must NOT appear in DI findings'

# --- Test 4: correct structural fields ---
Assert-Equal $diFinding.severity   'Medium'    'DI: severity is Medium'
Assert-Equal $diFinding.tier       'narrative' 'DI: tier is narrative'
Assert-Equal $diFinding.prefix     'DI'        'DI: prefix is DI'
Assert-Equal $diFinding.confidence 'Confirmed' 'DI: confidence is Confirmed'

# --- Test 5: citation is non-empty and references With function / efficient-calculations ---
Assert-True (-not [string]::IsNullOrWhiteSpace($diFinding.citation)) 'DI: finding has a non-empty citation'
Assert-Match $diFinding.citation 'With' 'DI: citation references the With function section'
