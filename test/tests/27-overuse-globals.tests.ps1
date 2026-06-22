# Task 27: OG — overuse-of-globals lead (LEAD, kind='overuse-of-globals', L-NN id)
# Detection: if count of DISTINCT global variables > $T_GlobalOveruse (default 20), emit ONE
# app-level OG lead via New-Lead (not New-Finding). OG is a judgment lead — the model decides
# whether per-variable refactoring to context-var or named-formula is warranted.
#
# Fixture: MaintainabilityKitchenSink.msapp
#   Globals: gblZebra, gblApple, gblTitle, gblMango, plainGlobalNoPrefix, gblBusy = 6 distinct
#   Default threshold (20): 6 < 20 → 0 OG leads (negative test).
#   Lowered threshold (2):  6 > 2  → 1 OG lead (positive test).

# ---------------------------------------------------------------------------
# Run A (threshold=2): expect exactly 1 OG lead
# ---------------------------------------------------------------------------
$mech = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp' -EnvOverrides @{ CAA_GLOBAL_OVERUSE = '2' }
Assert-True ($null -ne $mech) 'OG Run A: kitchen-sink produced mechanical-findings.json'

[array]$og = @($mech.leads | Where-Object { $_.kind -eq 'overuse-of-globals' })

# Test 1: exactly 1 OG lead fires when threshold is 2
Assert-Equal $og.Count 1 'OG Run A: exactly 1 overuse-of-globals lead (threshold=2, 6 globals > 2)'

# Test 2: lead has a non-empty id (L-NN format)
$ogL = $og[0]
Assert-True (-not [string]::IsNullOrWhiteSpace($ogL.id)) 'OG Run A: lead has a non-empty id'
Assert-True ($ogL.id -match '^L-\d{2,}$') 'OG Run A: lead id matches L-NN format (e.g. L-01)'

# Test 3: lead has a non-empty hint
Assert-True (-not [string]::IsNullOrWhiteSpace($ogL.hint)) 'OG Run A: lead has a non-empty hint'

# Test 4: hint mentions global variable count
Assert-True ($ogL.hint -imatch '\d+') 'OG Run A: hint contains a number (global var count)'

# Test 5: kind is exactly 'overuse-of-globals'
Assert-Equal $ogL.kind 'overuse-of-globals' 'OG Run A: lead kind is overuse-of-globals'

# Test 6: category is Maintainability & naming
Assert-Equal $ogL.category 'Maintainability & naming' 'OG Run A: lead category is Maintainability & naming'

# ---------------------------------------------------------------------------
# Run Default (threshold=20): expect 0 OG leads (kitchen-sink has 6 globals < 20)
# ---------------------------------------------------------------------------
$mechDefault = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
Assert-True ($null -ne $mechDefault) 'OG Default: kitchen-sink produced mechanical-findings.json'

[array]$ogDefault = @($mechDefault.leads | Where-Object { $_.kind -eq 'overuse-of-globals' })

# Test 7: 0 OG leads at default threshold (6 globals < 20)
Assert-Equal $ogDefault.Count 0 'OG Default: 0 overuse-of-globals leads at default threshold 20 (6 globals < 20)'
