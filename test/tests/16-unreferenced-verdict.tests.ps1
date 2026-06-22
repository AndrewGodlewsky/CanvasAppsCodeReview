# Task 16: UR — behavior-aware per-control verdicts (D5)
# Fixture: MaintainabilityKitchenSink (extended below with lblAnchor/lblAnchorRef).
#
# Controls of interest:
#   lblHidden  -> Visible: =false, Text: ="never shown", no handler, unreferenced
#                 Expected verdict: strong-dead-candidate
#   lblTitle   -> Text: =gblTitle (data-bound to a variable), visible, unreferenced
#                 Expected verdict: likely-decorative-or-layout
#   lblAnchor  -> Text: ="anchor"; lblAnchorRef -> Text: =lblAnchor.Text
#                 lblAnchor IS referenced via lblAnchorRef.Text, so NOT in UR findings

$mech = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
Assert-True ($null -ne $mech) 'UR16: kitchen-sink produced mechanical-findings.json'

[array]$ur = @(Get-Findings $mech 'UR')
Assert-True ($ur.Count -gt 0) 'UR16: at least one UR finding exists'

# --- Test 1: every UR finding has a non-empty verdict (no blanket dismissal) ---
[array]$missingVerdict = @($ur | Where-Object { [string]::IsNullOrWhiteSpace($_.verdict) })
Assert-Equal $missingVerdict.Count 0 'UR16: every UR finding has a non-empty verdict (D5 - no blanket dismissal)'

# --- Test 2: lblHidden gets strong-dead-candidate ---
[array]$hiddenFindings = @($ur | Where-Object { $_.location.control -eq 'lblHidden' })
Assert-Equal $hiddenFindings.Count 1 'UR16: exactly one UR finding for lblHidden'
Assert-Equal $hiddenFindings[0].verdict 'strong-dead-candidate' 'UR16: lblHidden verdict is strong-dead-candidate (invisible, no data, no handler)'

# --- Test 3: lblTitle gets likely-decorative-or-layout (data-bound to gblTitle) ---
[array]$titleFindings = @($ur | Where-Object { $_.location.control -eq 'lblTitle' })
Assert-Equal $titleFindings.Count 1 'UR16: exactly one UR finding for lblTitle'
Assert-Equal $titleFindings[0].verdict 'likely-decorative-or-layout' 'UR16: lblTitle verdict is likely-decorative-or-layout (surfaces data via Text=gblTitle)'

# --- Test 4: lblAnchor must NOT appear in UR findings (it is referenced by lblAnchorRef.Text) ---
[array]$anchorFindings = @($ur | Where-Object { $_.location.control -eq 'lblAnchor' })
Assert-Equal $anchorFindings.Count 0 'UR16: lblAnchor does NOT appear in UR findings (it is referenced by lblAnchorRef.Text)'

# --- Test 5: every UR finding has the correct structural fields ---
foreach ($f in $ur) {
    Assert-Equal $f.prefix       'UR'          "UR16: finding $($f.id) has prefix UR"
    Assert-Equal $f.severity     'Low'         "UR16: finding $($f.id) has severity Low"
    Assert-Equal $f.confidence   'Potential'   "UR16: finding $($f.id) has confidence Potential"
    Assert-Equal $f.tier         'enumeration' "UR16: finding $($f.id) has tier enumeration"
}
