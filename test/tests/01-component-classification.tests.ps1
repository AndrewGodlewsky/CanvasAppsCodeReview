# §7.1 Component classification: content/structure-based, tolerant of folder spelling.
# cmpHeader.pa.yaml lives under Src\Components\ (plural) and declares ComponentDefinitions:
# + Type: CanvasComponent. The old heuristic (folder match \Component\ singular, or filename
# contains "Component") misses it. After the fix it must appear in index.json.components and
# NOT in index.json.screens.

$mech = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
Assert-True ($null -ne $mech) 'analyzer produced output for kitchen-sink fixture'

$index = $mech.__index
Assert-True ($null -ne $index) 'index.json was produced and attached to result'

# cmpHeader must be classified as a component
Assert-True (@($index.components) -contains 'cmpHeader') 'cmpHeader classified as component (structure-based detection)'

# MainScreen must appear in screens (not excluded)
Assert-True (@($index.screens | ForEach-Object { $_.name }) -contains 'MainScreen') 'MainScreen classified as screen'

# MainScreen must NOT appear as a component
Assert-True (-not (@($index.components) -contains 'MainScreen')) 'MainScreen is NOT a component'
