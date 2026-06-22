# Task 21: MV — magic-values detector (enumeration, Low, Confirmed)
# Fixture: MaintainabilityKitchenSink (extended with lblMagic in MainScreen)
#
# lblMagic control planted in the fixture:
#   Text: =If(8675309 > 0, "Processing batch alpha", "https://magic.example.test/v2/orders")
#
# Expected MV findings on lblMagic:
#   - number  8675309      (not 0/1 -> flagged)
#   - string  "Processing batch alpha"
#   - string  "https://magic.example.test/v2/orders"
#   = EXACTLY 3 MV findings on lblMagic
#
# The literal "0" in "> 0" is excluded (0 and 1 are trivial).
# RGBA numbers from DC labels (e.g. RGBA(0,0,0,1)) must NOT produce MV findings.

$mech = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
Assert-True ($null -ne $mech) 'MV: kitchen-sink produced mechanical-findings.json'

# --- Test 1: exactly 3 MV findings on lblMagic ---
[array]$mvOnMagic = @($mech.deterministicFindings | Where-Object { $_.prefix -eq 'MV' -and $_.location.control -eq 'lblMagic' })
Assert-Equal $mvOnMagic.Count 3 'MV: exactly 3 MV findings on lblMagic'

# --- Test 2: each expected literal is in evidence ---
[array]$mvWithNumber = @($mvOnMagic | Where-Object { $_.evidence -match '8675309' })
Assert-Equal $mvWithNumber.Count 1 'MV: one finding with evidence containing 8675309'

[array]$mvWithBatch = @($mvOnMagic | Where-Object { $_.evidence -match 'Processing batch alpha' })
Assert-Equal $mvWithBatch.Count 1 'MV: one finding with evidence containing "Processing batch alpha"'

[array]$mvWithUrl = @($mvOnMagic | Where-Object { $_.evidence -match 'magic\.example\.test' })
Assert-Equal $mvWithUrl.Count 1 'MV: one finding with evidence containing magic.example.test URL'

# --- Test 3: 0 and 1 are NOT flagged as MV on lblMagic ---
[array]$mvZeroOnMagic = @($mvOnMagic | Where-Object { $_.evidence -match '^0$' -or $_.evidence -ceq '0' })
Assert-Equal $mvZeroOnMagic.Count 0 'MV: no finding with evidence exactly "0" on lblMagic'

[array]$mvOneOnMagic = @($mvOnMagic | Where-Object { $_.evidence -match '^1$' -or $_.evidence -ceq '1' })
Assert-Equal $mvOneOnMagic.Count 0 'MV: no finding with evidence exactly "1" on lblMagic'

# --- Test 4: structural fields of MV findings ---
$firstMv = $mvOnMagic[0]
Assert-Equal $firstMv.severity   'Low'         'MV: severity is Low'
Assert-Equal $firstMv.tier       'enumeration' 'MV: tier is enumeration'
Assert-Equal $firstMv.prefix     'MV'          'MV: prefix is MV'
Assert-Equal $firstMv.confidence 'Confirmed'   'MV: confidence is Confirmed'

# --- Test 5: citation is non-empty ---
Assert-True (-not [string]::IsNullOrWhiteSpace($firstMv.citation)) 'MV: finding has a non-empty citation'

# --- Test 6: global MV count > 0 (sanity) ---
[array]$allMv = @($mech.deterministicFindings | Where-Object { $_.prefix -eq 'MV' })
Assert-True ($allMv.Count -gt 0) 'MV: at least one MV finding exists globally'
