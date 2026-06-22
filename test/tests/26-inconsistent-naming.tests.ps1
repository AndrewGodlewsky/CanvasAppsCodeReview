# Task 26: IN -- inconsistent-naming detector (Low, enumeration, Confirmed)
# Scoped definition: IN fires when a VARIABLE-SCOPE CATEGORY (globals / contexts / collections)
# mixes prefixed (conventional) names with unprefixed (violating) names. One finding per
# inconsistent category. Controls are deliberately excluded to avoid false positives.
#
# Fixture: MaintainabilityKitchenSink.msapp (extended with one un-prefixed global)
#   App.OnStart: ...Set(plainGlobalNoPrefix, 99);...
#   MainScreen:  lblPlain references plainGlobalNoPrefix (so it is not flagged by UV)
#
# Baseline: all gbl* globals -> consistent -> 0 IN (confirmed)
# After fixture change:
#   globals = {gblApple, gblBusy, gblMango, gblTitle, gblZebra, plainGlobalNoPrefix}
#   gbl-prefixed: 5; non-prefixed: 1 -> MIXED -> 1 IN finding for "global variables" category
#   contexts: none (0 members) -> N/A (need at least 1 compliant AND 1 violating -> not triggered)
#   collections: colApple, colZebra -> both col* -> consistent -> 0 IN
#
# Expected: exactly 1 IN finding (global-variables category)
# VP ALSO fires on plainGlobalNoPrefix individually -> coexistence of IN + VP

$mech = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
Assert-True ($null -ne $mech) 'IN: kitchen-sink produced mechanical-findings.json'

# ---------------------------------------------------------------------------
# Test 1: exactly 1 IN finding (the globals category inconsistency)
# ---------------------------------------------------------------------------
[array]$in = @(Get-Findings $mech 'IN')
Assert-Equal $in.Count 1 'IN: exactly 1 IN finding (globals category is mixed)'

# ---------------------------------------------------------------------------
# Test 2: the IN finding is for the global-variables category
# ---------------------------------------------------------------------------
$inF = $in[0]
Assert-True ($inF.message -imatch 'global' -or $inF.evidence -imatch 'global') `
    'IN: finding message or evidence references globals'

# ---------------------------------------------------------------------------
# Test 3: finding evidence mentions the offending unprefixed name
# ---------------------------------------------------------------------------
Assert-True ($inF.evidence -imatch 'plainGlobalNoPrefix') `
    'IN: evidence mentions the unprefixed global plainGlobalNoPrefix'

# ---------------------------------------------------------------------------
# Test 4: structural fields -- severity, tier, prefix, confidence
# ---------------------------------------------------------------------------
Assert-Equal $inF.severity   'Low'         'IN: severity is Low'
Assert-Equal $inF.tier       'enumeration' 'IN: tier is enumeration'
Assert-Equal $inF.prefix     'IN'          'IN: prefix is IN'
Assert-Equal $inF.confidence 'Confirmed'   'IN: confidence is Confirmed'

# ---------------------------------------------------------------------------
# Test 5: citation is non-empty
# ---------------------------------------------------------------------------
Assert-True (-not [string]::IsNullOrWhiteSpace($inF.citation)) 'IN: finding has a non-empty citation'

# ---------------------------------------------------------------------------
# Test 6: id is set (non-null, non-empty)
# ---------------------------------------------------------------------------
Assert-True (-not [string]::IsNullOrWhiteSpace($inF.id)) 'IN: finding has a non-empty id'

# ---------------------------------------------------------------------------
# Test 7 (coexistence): VP ALSO fires on plainGlobalNoPrefix individually
# IN (category-level) and VP (instance-level) must both fire -- different lenses
# ---------------------------------------------------------------------------
[array]$vpPlain = @($mech.deterministicFindings | Where-Object {
    $_.prefix -eq 'VP' -and (
        ($_.evidence -imatch 'plainGlobalNoPrefix') -or
        ($_.message  -imatch 'plainGlobalNoPrefix')
    )
})
Assert-Equal $vpPlain.Count 1 'IN+VP coexistence: VP fires on plainGlobalNoPrefix individually'

# ---------------------------------------------------------------------------
# Test 8: collections are consistent (colApple, colZebra all col*) -- no IN for collections
# ---------------------------------------------------------------------------
[array]$inForCols = @($in | Where-Object { $_.evidence -imatch 'collection' -or $_.message -imatch 'collection' })
Assert-Equal $inForCols.Count 0 'IN: no IN finding for collections (all col* -- consistent)'

# ---------------------------------------------------------------------------
# Test 9: context variables not present / consistent -- no IN for contexts
# ---------------------------------------------------------------------------
[array]$inForCtx = @($in | Where-Object { $_.evidence -imatch 'context' -or $_.message -imatch 'context' })
Assert-Equal $inForCtx.Count 0 'IN: no IN finding for context vars (none in fixture -- consistent)'
