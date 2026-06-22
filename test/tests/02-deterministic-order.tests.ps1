# §7.2 Deterministic ordering: controls and variables must be in identical, stable order
# across two independent analyzer runs. The kitchen-sink fixture has variables set in
# non-alphabetical order (gblZebra, gblApple, gblMango, gblTitle) and controls added in
# non-alphabetical order (lblZebra, lblApple, lblTitle) so any hashtable-key ordering
# instability will surface as a mismatch between the two runs.

# Two genuinely separate child-process invocations: different cache keys force two real runs.
# The analyzer ignores unknown CAA_ vars, so both produce real output.
$r1 = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp' -EnvOverrides @{}
$r2 = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp' -EnvOverrides @{ CAA_NOCACHE = '1' }

Assert-True ($null -ne $r1) 'run-1 produced output'
Assert-True ($null -ne $r2) 'run-2 produced output'

$i1 = $r1.__index
$i2 = $r2.__index

Assert-True ($null -ne $i1) 'run-1 index.json attached'
Assert-True ($null -ne $i2) 'run-2 index.json attached'

# Controls order must be stable and alphabetical
$ctrl1 = ($i1.controls | ForEach-Object { $_.name }) -join ','
$ctrl2 = ($i2.controls | ForEach-Object { $_.name }) -join ','
Assert-Equal $ctrl1 $ctrl2 'controls order stable across two runs'

# Variables must include our out-of-alpha-order globals
Assert-True ($i1.variables.Count -ge 4) "at least 4 variables present (got $($i1.variables.Count))"

# Variables order must be stable and alphabetical by name
$var1 = ($i1.variables | ForEach-Object { $_.name }) -join ','
$var2 = ($i2.variables | ForEach-Object { $_.name }) -join ','
Assert-Equal $var1 $var2 'variables order stable across two runs'

# Post-fix sanity: both should be sorted alphabetically by name
$sortedCtrl = ($i1.controls | Sort-Object name | ForEach-Object { $_.name }) -join ','
Assert-Equal $ctrl1 $sortedCtrl 'controls order is alphabetical by name'

$sortedVar = ($i1.variables | Sort-Object name | ForEach-Object { $_.name }) -join ','
Assert-Equal $var1 $sortedVar 'variables order is alphabetical by name'

# Collections order must be stable and alphabetical (colApple before colZebra)
$col1 = ($i1.collections | ForEach-Object { $_.name }) -join ','
$col2 = ($i2.collections | ForEach-Object { $_.name }) -join ','
Assert-Equal $col1 $col2 'collections order stable across two runs'

$sortedCol = ($i1.collections | Sort-Object name | ForEach-Object { $_.name }) -join ','
Assert-Equal $col1 $sortedCol 'collections order is alphabetical by name'
