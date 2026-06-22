# Task 11: UP — unused component custom property detector
# Fixture: MaintainabilityKitchenSink
#   cmpHeader.HeaderText   -> defined AND read internally (=cmpHeader.HeaderText)  -> NOT flagged
#   cmpFooter.FooterText   -> defined AND read internally (=cmpFooter.FooterText)  -> NOT flagged
#   cmpFooter.UnusedProp   -> defined, NEVER referenced anywhere                   -> flagged UP-01

$mech = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
Assert-True ($null -ne $mech) 'UP: kitchen-sink produced mechanical-findings.json'

# --- Test 1: exactly 1 UP finding (only cmpFooter.UnusedProp is unreferenced) ---
[array]$up = @(Get-Findings $mech 'UP')
Assert-Equal $up.Count 1 'UP: exactly 1 UP finding (cmpFooter.UnusedProp unused; FooterText and HeaderText are used)'

# --- Test 2: the UP finding names UnusedProp ---
$upFinding = $up | Select-Object -First 1
$upText = if ($upFinding) { "$($upFinding.evidence) $($upFinding.message)" } else { '' }
Assert-Match $upText 'UnusedProp' 'UP: finding references UnusedProp'

# --- Test 3: the UP finding names cmpFooter (the component it belongs to) ---
Assert-Match $upText 'cmpFooter' 'UP: finding references cmpFooter'

# --- Test 4: FooterText must NOT appear in any UP finding ---
$allUpText = ($up | ForEach-Object { "$($_.evidence) $($_.message)" }) -join ' '
Assert-True (-not ($allUpText -imatch 'FooterText')) 'UP: FooterText must NOT appear in any UP finding'

# --- Test 5: HeaderText must NOT appear in any UP finding ---
Assert-True (-not ($allUpText -imatch 'HeaderText')) 'UP: HeaderText must NOT appear in any UP finding'

# --- Test 6: correct severity (Low), tier (enumeration), prefix (UP) ---
if ($upFinding) {
    Assert-Equal $upFinding.severity  'Low'         'UP: severity is Low'
    Assert-Equal $upFinding.tier      'enumeration' 'UP: tier is enumeration'
    Assert-Equal $upFinding.prefix    'UP'          'UP: prefix is UP'
}

# --- Test 7: UP finding has a non-empty citation ---
if ($upFinding) {
    Assert-True (-not [string]::IsNullOrWhiteSpace($upFinding.citation)) 'UP: finding has a non-empty citation'
}
