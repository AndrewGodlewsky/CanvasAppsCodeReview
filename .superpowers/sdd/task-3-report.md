# Task 3 Report — §7.3 Shared Formula Tokenizer

## Status: DONE

## Files Changed

- **Modified**: `skills/canvas-app-analyzer/scripts/analyze-canvas.ps1`
  - Added `Split-FormulaSpans` function (lines 113–144) between `Expand-ZipArchive` and the `$ControlTypeWords` array
  - Added `__spans` self-test shim (lines 167–176) as the first thing inside the `try` block

- **Created**: `test/tests/03-tokenizer.tests.ps1`

## The Function

`Split-FormulaSpans [string]$Text` scans a Power Fx formula character by character:
- When it encounters `"`, it enters string-literal mode, collecting characters until the closing `"`.
- `""` (two consecutive double-quotes) inside a literal is collapsed to a single `"` in the unescaped content (Power Fx escape rule).
- The string-literal token (including its surrounding quotes) is replaced in `.Code` by spaces of equal length, preserving column positions.
- Returns `[pscustomobject]@{ Code=<string>; Strings=@(<array of unescaped literal contents>) }`.
- Empty/null input returns `Code=''`, `Strings=@()`.

## The Self-Test Shim

Located inside the `try` block before any real analysis work. Checks `if ($Path -eq '__spans')`. When active:
1. Reads the formula from `$env:CAA_SPANS_FORMULA` (preferred) or falls back to `$AppName`.
2. Calls `Split-FormulaSpans` and emits the result as compact JSON.
3. Exits 0.

**Shim isolation from normal runs**: The sentinel `__spans` is not a valid filesystem path. In normal operation `$Path` is always a path to a `.zip` or `.msapp` file. The check `$Path -eq '__spans'` is false for all real invocations. The `finally` block's temp-dir cleanup still runs because `exit 0` inside a `try` block triggers `finally` in PowerShell.

## Deviation from Brief: Sentinel Value and Formula Passing

The brief specifies `'--__spans'` (double-dash) as the sentinel and passing the formula as the 2nd positional argument. Both fail in practice due to PowerShell's argument binding rules:

1. **Double-dash sentinel**: With `[CmdletBinding()]` (and even without it when `[Parameter()]` attributes are present), PowerShell's parameter binder treats any argument starting with `-` or `--` as a named parameter. `--__spans` is parsed as `-__spans` (a named switch), which does not exist and throws `NamedParameterNotFound`.

2. **Double-quotes in subprocess args**: When a parent PowerShell process passes a string containing `"` characters to a child `powershell -File` process, the double-quotes are stripped by the Windows command-line argument parser. Formulas like `=Set(x, "https://example.com")` arrive with the quotes removed.

**Resolutions applied**:
- Sentinel changed to `__spans` (no dashes) — binds cleanly to `$Path` as a positional string.
- Formula text is passed via `$env:CAA_SPANS_FORMULA` (set by test before invocation, unset in `finally`). Environment variables survive subprocess boundaries with full fidelity. The shim falls back to `$AppName` for simple, quote-free formulas.

These are pragmatic deviations forced by PowerShell's behaviour, not design choices. The spirit of the brief (shim activated by a special `$Path` value, formula as a second argument, compact JSON output) is faithfully preserved.

## Test Cases

| # | Input formula | Assertion |
|---|---|---|
| 1 | `=Navigate(HomeScreen) // go home` | `.Code` matches `//\s*go home` |
| 2 | `=Set(x, "https://example.com/a//b")` | `.Code` contains no `//`; `.Strings` contains `https://example.com/a//b` |
| 3 | `=Concatenate("say ""hi""")` | `.Strings` contains `say "hi"` |
| 4 | `""` (empty) | `.Code == ''`; `.Strings.Count == 0` |

## Full Test Run Output

```
RUN 00-smoke.tests.ps1
RUN 01-component-classification.tests.ps1
RUN 02-deterministic-order.tests.ps1
RUN 03-tokenizer.tests.ps1

PASS=24 FAIL=0
```

Tasks 0–2 results: all 19 prior tests still pass (no regression). 5 new tests added by Task 3, all passing.

## Concerns

None. The implementation is a pure character-scanner with no dependencies. The env-var passthrough is cleaned up in `finally` so it cannot leak into subsequent test runs. The shim is isolated from normal analyzer runs by the sentinel string check.

---

## Reviewer Fix Report — Column-invariant bug (Task 3 review)

### Bug

`Split-FormulaSpans` violated the invariant `.Code.Length == $Text.Length` for two input classes:

1. **Escaped quotes (`""`)**: Each `""` pair inside a string literal is consumed as 2 input characters but collapsed to 1 character in `$lit`. The old code emitted `$lit.Length + 2` spaces, which is 1 short per `""` pair.
2. **Unterminated literals**: When a string has no closing `"`, the inner loop exits at end-of-text without incrementing `$i` for a closing quote that was never there. The old code still added `2` for the surrounding quotes, so the replacement was 1 space too long (it would actually exceed input length).

### Before/After — the single changed line

```powershell
# BEFORE (line 138 in the original):
[void]$code.Append(' ' * ($lit.Length + 2))

# AFTER — uses consumed input length, not unescaped content length:
[void]$code.Append(' ' * ($i - $startIndex))
```

The fix also adds `$startIndex = $i` immediately before `$i++` at the opening quote (the line preceding the inner `while` loop), so `$startIndex` records the index of the `"` and `$i` after the loop is the index of the first character after the token.

### New Tests Added to `test/tests/03-tokenizer.tests.ps1`

| # | Input | New assertions |
|---|---|---|
| 5 | `=Concatenate("say ""hi""")` | `.Code.Length -eq $input5.Length` (invariant with escaped quotes); `.Strings` contains `say "hi"` |
| 6 | `=Set(x, "abc` (no closing quote) | `.Code.Length -eq $input6.Length` (invariant for unterminated literal); `.Strings` contains `abc` |
| 4 (strengthened) | `""` (empty input) | Added `-is [array]` assertion alongside existing `.Count -eq 0` |

### Full Test Run Output

```
RUN 00-smoke.tests.ps1
RUN 01-component-classification.tests.ps1
RUN 02-deterministic-order.tests.ps1
RUN 03-tokenizer.tests.ps1

PASS=29 FAIL=0
```

24 pre-existing tests: all pass (no regression). 5 new tests added by this fix: all pass.

### Concerns

None. The existing `// go home` and `https://...//...` tests (Tests 1 and 2) continue to pass — they only exercise normal string literals with no `""` pairs and no unterminated literals, so the space-count change does not affect them.
