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
Assert-True  (@($json4.Strings) -is [array]) 'empty input -> Strings is an array type'
Assert-True  (@($json4.Strings).Count -eq 0) 'empty input -> empty Strings array'

# --- Test 5: column invariant holds with escaped quote ("") ---
# Input: =Concatenate("say ""hi""")
# The "" pairs each consume 2 input chars but collapse to 1 char in $lit,
# so the old $lit.Length+2 was shorter than the consumed input. The fix
# uses (currentIndex - startIndex) so .Code.Length == $Text.Length always.
$input5 = '=Concatenate("say ""hi""")'
$json5 = Invoke-Spans $input5
Assert-Equal $json5.Code.Length $input5.Length 'column invariant: .Code.Length == input length with escaped quotes'
Assert-True  (@($json5.Strings) -contains 'say "hi"') 'escaped quote: .Strings still has unescaped content'

# --- Test 6: unterminated string literal ---
# Input: =Set(x, "abc
# No closing quote -> the inner loop exits at end-of-text, consuming from " to EOT.
# The old code would try to add $lit.Length+2 which includes a closing quote that was never there.
# The fix uses (currentIndex - startIndex) so the count is exact.
$input6 = '=Set(x, "abc'
$json6 = Invoke-Spans $input6
Assert-Equal $json6.Code.Length $input6.Length 'column invariant: .Code.Length == input length for unterminated literal'
Assert-True  (@($json6.Strings) -contains 'abc') 'unterminated literal: content still captured in .Strings'
