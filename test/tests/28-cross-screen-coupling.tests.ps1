# Task 28: XC -- cross-screen-coupling lead (LEAD, kind='cross-screen-coupling', L-NN id)
# Detection: for each formula, scan its code spans for references of the form <controlName>.
# where controlName belongs to a DIFFERENT screen than the formula's own screen.
# Emits one XC lead per (formula, referenced-foreign-control).
#
# Fixture: MaintainabilityKitchenSink.msapp
#   Cross-screen: lblCrossRef.Text (on MainScreen) = =lblOnSecond.Text
#     where lblOnSecond lives on SecondScreen -> 1 XC lead
#   Same-screen:  lblAnchorRef.Text (on MainScreen) = =lblAnchor.Text
#     where lblAnchor also lives on MainScreen -> NOT XC (0 XC leads for this pair)

$mech = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
Assert-True ($null -ne $mech) 'XC: kitchen-sink produced mechanical-findings.json'

[array]$xc = @($mech.leads | Where-Object { $_.kind -eq 'cross-screen-coupling' })

# Test 1: exactly 1 XC lead (lblCrossRef on MainScreen references lblOnSecond on SecondScreen)
Assert-Equal $xc.Count 1 'XC: exactly 1 cross-screen-coupling lead'

# Test 2: lead has an id matching L-NN format
$xcL = $xc[0]
Assert-True (-not [string]::IsNullOrWhiteSpace($xcL.id)) 'XC: lead has a non-empty id'
Assert-True ($xcL.id -match '^L-\d{2,}$') 'XC: lead id matches L-NN format (e.g. L-01)'

# Test 3: hint/snippet mentions the cross-screen coupling details
# Must mention the referenced foreign control (lblOnSecond) or the foreign screen (SecondScreen)
# AND the source control (lblCrossRef) or source screen (MainScreen)
$xcHint = if ($xcL.hint) { $xcL.hint } else { '' }
$xcSnip = if ($xcL.snippet) { $xcL.snippet } else { '' }
$xcCombined = $xcHint + ' ' + $xcSnip
Assert-True ($xcCombined -imatch 'lblOnSecond|SecondScreen') 'XC: lead hint/snippet mentions lblOnSecond or SecondScreen'
Assert-True ($xcCombined -imatch 'lblCrossRef|MainScreen') 'XC: lead hint/snippet mentions lblCrossRef or MainScreen'

# Test 4: the same-screen lblAnchorRef -> lblAnchor reference did NOT create an XC lead
# No XC lead should mention lblAnchor (the same-screen anchor label)
[array]$xcAnchor = @($xc | Where-Object {
    (($_.hint   -ne $null) -and ($_.hint   -imatch 'lblAnchor(?!Ref)')) -or
    (($_.snippet -ne $null) -and ($_.snippet -imatch 'lblAnchor(?!Ref)'))
})
Assert-Equal $xcAnchor.Count 0 'XC: same-screen lblAnchorRef->lblAnchor did not produce an XC lead'
