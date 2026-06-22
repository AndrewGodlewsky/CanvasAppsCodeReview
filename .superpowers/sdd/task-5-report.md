# Task 5 Report — Overridable Threshold Constants (§7.5)

## Status: COMPLETE

## What was done

### Implementation (`skills/canvas-app-analyzer/scripts/analyze-canvas.ps1`)

Added two new sections to the script:

**1. `_Thr` helper + nine `$T_*` constants** — inserted after the `Expand-ZipArchive` helper and before `Resolve-Connector`, so the constants are available for both the self-test shim and all downstream detector code:

| Constant | Env var | Default |
|---|---|---|
| `$T_LongFormulaBytes` | `CAA_LONG_FORMULA_BYTES` | 500 |
| `$T_DeepIfDepth` | `CAA_DEEP_IF_DEPTH` | 4 |
| `$T_GodScreenControls` | `CAA_GOD_SCREEN_CONTROLS` | 40 |
| `$T_GodScreenBytes` | `CAA_GOD_SCREEN_BYTES` | 20000 |
| `$T_ControlTreeDepth` | `CAA_CONTROL_TREE_DEPTH` | 5 |
| `$T_RepeatedLiteralMin` | `CAA_REPEATED_LITERAL_MIN` | 3 |
| `$T_NearDupRatio` | `CAA_NEAR_DUP_RATIO` | 0.90 |
| `$T_NearDupMinLen` | `CAA_NEAR_DUP_MIN_LEN` | 60 |
| `$T_GlobalOveruse` | `CAA_GLOBAL_OVERUSE` | 20 |

**2. `__thresholds` self-test shim** — added inside the `try` block immediately after the existing `__spans` shim. Uses `$Path -eq '__thresholds'` (no double-dash) to avoid the PS 5.1 named-parameter parse error. Emits all nine constants as compact JSON and exits 0. Normal runs (real file paths) are completely unaffected.

### Test (`test/tests/05-thresholds.tests.ps1`)

Four assertions covering:
1. `CAA_LONG_FORMULA_BYTES=120` env override is reflected (value becomes 120)
2. Default of 500 is returned when no override is set
3. All nine `T_*` keys are present in the JSON output
4. A normal run with a bad file path returns `status=error` (shim not triggered)

## Test results

```
PASS=46 FAIL=0
```

Tasks 0–4: 35 tests unaffected. Task 5: 11 new tests all passing.

## Key design decisions

- **No `--` prefix on sentinel**: PS 5.1 with `-File` + `[CmdletBinding()]` throws `NamedParameterNotFound` for args starting with `--`. Used bare `__thresholds` sentinel matching the existing `__spans` pattern.
- **Placement of `_Thr` and `$T_*`**: Outside the `try` block so they are available before the sentinel check. This matches how `$ControlTypeWords` and `$alwaysLocalFns` are structured.
- **`_Thr` regex `^\d+(\.\d+)?$`**: Accepts integers and decimals; rejects empty strings, negative values, and non-numeric garbage — safe for both integer and float thresholds.
