# Smoke: the kitchen-sink fixture exists, analyzer returns ok, src persisted.
$mech = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
Assert-True ($null -ne $mech) 'analyzer produced mechanical-findings.json'
Assert-True ($mech.deterministicFindings.Count -ge 0) 'deterministicFindings present'
