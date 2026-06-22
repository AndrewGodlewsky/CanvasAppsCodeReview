# Task 6: stable IDs + finding/lead constructors (D3)
# Every deterministic finding must have a well-formed id (PREFIX-NN).
# Every lead must have a well-formed id (L-NN).
# IDs must be stable (identical) across two independent analyzer runs.

# Use FieldServiceApp for a non-trivial finding set (default names, duplicate formulas, etc.)
$mech = Invoke-Analyzer -Fixture 'FieldServiceApp.msapp'

Assert-True ($null -ne $mech) 'FieldServiceApp produced mechanical-findings.json'

# --- Test 1: every deterministic finding has a well-formed id ---------------
foreach ($f in $mech.deterministicFindings) {
    Assert-Match $f.id '^[A-Z]{2}-\d{2,}$' "finding has well-formed id (type=$($f.type), id=$($f.id))"
}

# --- Test 2: every lead has a well-formed id --------------------------------
foreach ($l in $mech.leads) {
    Assert-Match $l.id '^L-\d{2,}$' "lead has well-formed id (kind=$($l.kind), id=$($l.id))"
}

# --- Test 3: at least one deterministic finding exists (sanity) -------------
Assert-True ($mech.deterministicFindings.Count -gt 0) "FieldServiceApp has at least one deterministic finding (got $($mech.deterministicFindings.Count))"

# --- Test 4: ID stability across two independent runs (DoD #10) -------------
$mech2 = Invoke-Analyzer -Fixture 'FieldServiceApp.msapp' -EnvOverrides @{ CAA_NOCACHE = '1' }

$map1 = ($mech.deterministicFindings  | Sort-Object id | ForEach-Object { "$($_.id):$($_.type):$($_.evidence)" }) -join '|'
$map2 = ($mech2.deterministicFindings | Sort-Object id | ForEach-Object { "$($_.id):$($_.type):$($_.evidence)" }) -join '|'
Assert-Equal $map1 $map2 'finding IDs stable across runs (DoD #10)'

# --- Test 5: lead ID stability across runs ----------------------------------
$lmap1 = ($mech.leads  | Sort-Object id | ForEach-Object { "$($_.id):$($_.kind):$($_.file):$($_.line)" }) -join '|'
$lmap2 = ($mech2.leads | Sort-Object id | ForEach-Object { "$($_.id):$($_.kind):$($_.file):$($_.line)" }) -join '|'
Assert-Equal $lmap1 $lmap2 'lead IDs stable across runs (DoD #10)'

# --- Test 6b: all deterministic finding IDs are unique (no sortKey collision) -------
Assert-Equal (@($mech.deterministicFindings.id | Sort-Object -Unique).Count) (@($mech.deterministicFindings).Count) 'all finding ids unique'

# --- Test 6: also check MaintainabilityKitchenSink (well-formed IDs if any findings) ---
$mkSink = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
foreach ($f in $mkSink.deterministicFindings) {
    Assert-Match $f.id '^[A-Z]{2}-\d{2,}$' "kitchen-sink finding has well-formed id (type=$($f.type))"
}
foreach ($l in $mkSink.leads) {
    Assert-Match $l.id '^L-\d{2,}$' "kitchen-sink lead has well-formed id (kind=$($l.kind))"
}
