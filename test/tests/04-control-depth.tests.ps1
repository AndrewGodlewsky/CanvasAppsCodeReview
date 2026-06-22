# Task 4: control nesting depth + ancestor chain
# lblDeep is nested 3 controls deep: conOuter > conInner > lblDeep
$result = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
$index  = $result.__index

$deep = $index.controls | Where-Object { $_.name -eq 'lblDeep' } | Select-Object -First 1
Assert-True  ($null -ne $deep)        'lblDeep control found in index'
Assert-Equal $deep.depth 3            'lblDeep nested 3 controls deep'

# Top-level controls must have depth 1
$lblZebra = $index.controls | Where-Object { $_.name -eq 'lblZebra' } | Select-Object -First 1
Assert-Equal $lblZebra.depth 1        'lblZebra (top-level) has depth 1'

# conOuter is a direct child of the screen -> depth 1
$conOuter = $index.controls | Where-Object { $_.name -eq 'conOuter' } | Select-Object -First 1
Assert-Equal $conOuter.depth 1        'conOuter (top-level container) has depth 1'

# conInner is inside conOuter -> depth 2
$conInner = $index.controls | Where-Object { $_.name -eq 'conInner' } | Select-Object -First 1
Assert-Equal $conInner.depth 2        'conInner (nested one level) has depth 2'
