# Task 24: GS — god-screen detector (Medium, narrative, Confirmed)
# Fixture: MaintainabilityKitchenSink (single screen: MainScreen, ~30 controls)
#
# Strategy: threshold-driven, deterministic, NO new fixture screen needed.
#   Run A: override CAA_GOD_SCREEN_CONTROLS=3 so MainScreen (>>3 controls) IS a god screen.
#   Run B: override both thresholds extremely high so NO screen qualifies.
#
# MainScreen default control count ~30 (< default 40) so the default-threshold suite run
# does NOT produce a GS finding — no interference with other tests.

# ---------------------------------------------------------------------------
# Run A: lower control threshold to 3 → MainScreen is flagged
# ---------------------------------------------------------------------------
$mechA = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp' -EnvOverrides @{ CAA_GOD_SCREEN_CONTROLS = '3' }
Assert-True ($null -ne $mechA) 'GS Run A: kitchen-sink produced mechanical-findings.json'

[array]$gs = @(Get-Findings $mechA 'GS')

# Test 1: exactly 1 GS finding (only one screen in this fixture)
Assert-Equal $gs.Count 1 'GS Run A: exactly 1 GS finding (MainScreen exceeds control threshold 3)'

# Test 2: finding names MainScreen
$gsF = $gs[0]
Assert-Equal $gsF.location.screen 'MainScreen' 'GS Run A: finding location.screen is MainScreen'

# Test 3: structural fields — severity, tier, prefix, confidence
Assert-Equal $gsF.severity   'Medium'    'GS Run A: severity is Medium'
Assert-Equal $gsF.tier       'narrative' 'GS Run A: tier is narrative'
Assert-Equal $gsF.prefix     'GS'        'GS Run A: prefix is GS'
Assert-Equal $gsF.confidence 'Confirmed' 'GS Run A: confidence is Confirmed'

# Test 4: citation is non-empty
Assert-True (-not [string]::IsNullOrWhiteSpace($gsF.citation)) 'GS Run A: finding has a non-empty citation'

# Test 5: evidence mentions control count or byte count
Assert-True ($gsF.evidence -match '\d') 'GS Run A: evidence contains a number (control count or byte count)'

# ---------------------------------------------------------------------------
# Run B: raise both thresholds far above any real value → no GS findings
# ---------------------------------------------------------------------------
$mechB = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp' `
    -EnvOverrides @{ CAA_GOD_SCREEN_CONTROLS = '1000'; CAA_GOD_SCREEN_BYTES = '100000000' }
Assert-True ($null -ne $mechB) 'GS Run B: kitchen-sink produced mechanical-findings.json'

[array]$gsB = @(Get-Findings $mechB 'GS')

# Test 6: zero GS findings when both thresholds far exceed actual values
Assert-Equal $gsB.Count 0 'GS Run B: 0 GS findings when thresholds are very high'

# ---------------------------------------------------------------------------
# Confirm default run (no overrides) does NOT produce GS findings
# (MainScreen has ~30 controls < default 40, formulaBytes < default 20000)
# ---------------------------------------------------------------------------
$mechDef = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
[array]$gsDef = @(Get-Findings $mechDef 'GS')

# Test 7: default threshold run produces 0 GS findings (MainScreen ~30 controls < 40)
Assert-Equal $gsDef.Count 0 'GS Default: 0 GS findings at default thresholds (MainScreen ~30 controls < 40 default)'
