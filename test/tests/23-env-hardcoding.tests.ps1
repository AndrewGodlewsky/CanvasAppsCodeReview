# Task 23: EV — environment-specific hardcoding detector (High, narrative, Confirmed)
# Fixture: MaintainabilityKitchenSink (extended with lblEnvHard/lblEnvOk in MainScreen)
#
# Controls planted in the fixture:
#   - lblEnvHard.Text: =Concatenate("https://contoso.sharepoint.test/sites/ProdSite", " | ", "12345678-1234-1234-1234-1234567890ab")
#     -> 2 EV findings: one for the SharePoint URL, one for the GUID
#   - lblEnvOk.Text:   ="just/a/relative/path and plain text"
#     -> 0 EV findings (relative path / plain text must NOT be flagged)
#
# lblMagic.Text: =If(8675309 > 0, "Processing batch alpha", "https://magic.example.test/v2/orders")
#   -> 1 EV finding: "https://magic.example.test/v2/orders" is an absolute URL (env-specific)
#
# Total EV in the kitchen-sink app:
#   lblEnvHard: 2 (SharePoint URL + GUID)
#   lblMagic:   1 (absolute URL https://magic.example.test/v2/orders)
#   = 3 EV findings total

$mech = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
Assert-True ($null -ne $mech) 'EV: kitchen-sink produced mechanical-findings.json'

# --- Test 1: exactly 2 EV findings on lblEnvHard ---
[array]$evHard = @($mech.deterministicFindings | Where-Object { $_.prefix -eq 'EV' -and $_.location.control -eq 'lblEnvHard' })
Assert-Equal $evHard.Count 2 'EV: exactly 2 EV findings on lblEnvHard (URL + GUID)'

# --- Test 2: one EV evidence contains the SharePoint URL ---
[array]$evSharePoint = @($evHard | Where-Object { $_.evidence -match 'sharepoint\.test' })
Assert-Equal $evSharePoint.Count 1 'EV: one lblEnvHard finding has evidence matching sharepoint.test'

# --- Test 3: one EV evidence contains the GUID ---
[array]$evGuid = @($evHard | Where-Object { $_.evidence -match '12345678-1234-1234-1234-1234567890ab' })
Assert-Equal $evGuid.Count 1 'EV: one lblEnvHard finding has evidence matching the planted GUID'

# --- Test 4: 0 EV findings on lblEnvOk (relative/plain text not flagged) ---
[array]$evOk = @($mech.deterministicFindings | Where-Object { $_.prefix -eq 'EV' -and $_.location.control -eq 'lblEnvOk' })
Assert-Equal $evOk.Count 0 'EV: 0 EV findings on lblEnvOk (relative path / plain text must not be flagged)'

# --- Test 5: EV severity is High (key differentiator from MV Low) ---
$firstEv = $evHard[0]
Assert-Equal $firstEv.severity   'High'      'EV: severity is High'
Assert-Equal $firstEv.tier       'narrative' 'EV: tier is narrative'
Assert-Equal $firstEv.prefix     'EV'        'EV: prefix is EV'
Assert-Equal $firstEv.confidence 'Confirmed' 'EV: confidence is Confirmed'

# --- Test 6: citation is non-empty and references environment variables ---
Assert-True (-not [string]::IsNullOrWhiteSpace($firstEv.citation)) 'EV: finding has a non-empty citation'
Assert-Match $firstEv.citation 'environmentvariables|environment.variables|environment-variables' 'EV: citation references environment variables guidance'

# --- Test 7: total EV count is exactly 3 ---
# lblEnvHard: 2 (URL + GUID), lblMagic: 1 (https://magic.example.test/v2/orders), lblEnvOk: 0
[array]$allEv = @(Get-Findings $mech 'EV')
Assert-Equal $allEv.Count 3 'EV: total EV finding count is 3 (lblEnvHard x2 + lblMagic x1)'
