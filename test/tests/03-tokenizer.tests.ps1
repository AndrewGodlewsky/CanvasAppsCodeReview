# §7.3 Shared formula tokenizer: Split-FormulaSpans
# Tests the __spans shim which exposes Split-FormulaSpans as compact JSON.
# The shim lives in analyze-canvas.ps1 and is activated by passing '__spans' as $Path.
#
# Note on quoting: PowerShell's child-process argument passing strips bare double-quotes
# from strings when invoking -File. Formulas that contain Power Fx string literals
# (which use double-quote delimiters) are therefore passed via $env:CAA_SPANS_FORMULA
# to avoid quoting loss. Simple, no-string-literal formulas pass via the 2nd positional arg.

$repo   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script = Join-Path $repo 'skills\canvas-app-analyzer\scripts\analyze-canvas.ps1'

function Invoke-Spans {
    param([string]$Formula)
    $env:CAA_SPANS_FORMULA = $Formula
    try {
        $raw = & powershell -NoProfile -ExecutionPolicy Bypass -File $script '__spans'
        return ($raw | ConvertFrom-Json)
    } finally {
        Remove-Item Env:\CAA_SPANS_FORMULA -ErrorAction SilentlyContinue
    }
}

# --- Test 1: // in CODE span (outside any string literal) stays in .Code ---
$json1 = Invoke-Spans '=Navigate(HomeScreen) // go home'
Assert-Match $json1.Code '//\s*go home' 'comment stays in code span'

# --- Test 2: // inside a string literal does NOT appear in .Code ---
$json2 = Invoke-Spans '=Set(x, "https://example.com/a//b")'
Assert-True  (-not ($json2.Code -match '//'))                          'slashes inside string literal are NOT in code span'
Assert-True  (@($json2.Strings) -contains 'https://example.com/a//b') 'URL captured as string literal'

# --- Test 3: escaped quote ("") inside a string literal ---
$json3 = Invoke-Spans '=Concatenate("say ""hi""")'
Assert-True  (@($json3.Strings) -contains 'say "hi"') 'escaped double-quote ("") collapses to single quote in literal'

# --- Test 4: empty / null text ---
$json4 = Invoke-Spans ''
Assert-Equal $json4.Code '' 'empty input -> empty Code'
Assert-True  (@($json4.Strings).Count -eq 0) 'empty input -> empty Strings array'
