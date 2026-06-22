# Task 25: CT — deep control-tree nesting detector (Low, enumeration, Confirmed)
# Fixture: MaintainabilityKitchenSink.msapp
# Nesting in fixture (from Task 4): conOuter=1, conInner=2, lblDeep=3
#
# Strategy: threshold-driven, deterministic, NO new fixture needed.
#   Run A: override CAA_CONTROL_TREE_DEPTH=3 → lblDeep (depth 3) fires; conInner (2) and conOuter (1) do not.
#   Run Default: threshold=5 (default) → no control reaches depth 5 → 0 CT findings.

# ---------------------------------------------------------------------------
# Run A: lower threshold to 3 → lblDeep qualifies, conInner and conOuter do not
# ---------------------------------------------------------------------------
$mechA = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp' -EnvOverrides @{ CAA_CONTROL_TREE_DEPTH = '3' }
Assert-True ($null -ne $mechA) 'CT Run A: kitchen-sink produced mechanical-findings.json'

[array]$ct = @(Get-Findings $mechA 'CT')

# Test 1: exactly 1 CT finding at threshold 3 (only lblDeep has depth 3)
Assert-Equal $ct.Count 1 'CT Run A: exactly 1 CT finding at threshold 3 (only lblDeep qualifies)'

# Test 2: the finding names lblDeep
$ctF = $ct[0]
Assert-Equal $ctF.location.control 'lblDeep' 'CT Run A: finding location.control is lblDeep'

# Test 3: structural fields — severity, tier, prefix, confidence
Assert-Equal $ctF.severity   'Low'         'CT Run A: severity is Low'
Assert-Equal $ctF.tier       'enumeration' 'CT Run A: tier is enumeration'
Assert-Equal $ctF.prefix     'CT'          'CT Run A: prefix is CT'
Assert-Equal $ctF.confidence 'Confirmed'   'CT Run A: confidence is Confirmed'

# Test 4: citation is non-empty
Assert-True (-not [string]::IsNullOrWhiteSpace($ctF.citation)) 'CT Run A: finding has a non-empty citation'

# Test 5: evidence contains a depth number
Assert-True ($ctF.evidence -match '\d') 'CT Run A: evidence contains a number (depth)'

# ---------------------------------------------------------------------------
# Run A: verify conOuter (depth 1) is NOT among CT findings at threshold 3
# ---------------------------------------------------------------------------
$ctControls = @($ct | ForEach-Object { $_.location.control })
Assert-True ($ctControls -notcontains 'conOuter') 'CT Run A: conOuter (depth 1) is NOT flagged at threshold 3'
Assert-True ($ctControls -notcontains 'conInner') 'CT Run A: conInner (depth 2) is NOT flagged at threshold 3'

# ---------------------------------------------------------------------------
# Run Default: threshold=5 (default) → 0 CT findings (no control reaches depth 5)
# ---------------------------------------------------------------------------
$mechDefault = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
Assert-True ($null -ne $mechDefault) 'CT Default: kitchen-sink produced mechanical-findings.json'

[array]$ctDefault = @(Get-Findings $mechDefault 'CT')

# Test 6: 0 CT findings at default threshold (no control is nested 5+ levels deep)
Assert-Equal $ctDefault.Count 0 'CT Default: 0 CT findings at default threshold 5 (no control reaches depth 5)'
