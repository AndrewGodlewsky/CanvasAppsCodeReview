# Task 6 Report: Stable IDs + Finding/Lead Constructors (D3)

## Status: COMPLETE

## What was done

Added three functions to `analyze-canvas.ps1` and refactored all existing detector emits to use them:

### New functions added (after `$alwaysLocalFns` declaration, before `try {`)

- **`New-Finding`** — constructor for deterministic findings. Fields: `id=$null`, `prefix`, `type`, `category`, `severity`, `confidence`, `tier`, `citation`, `verdict`, `location`, `evidence`, `message`, `sortKey`. All downstream fields preserved.
- **`New-Lead`** — constructor for judgment leads. Fields: `id=$null`, `prefix='L'`, `category`, `kind`, `screen`, `control`, `property`, `file`, `line`, `snippet`, `hint`.
- **`Stamp-Ids`** — assigns stable, deterministic IDs. Groups findings by `prefix`, sorts each group by `sortKey`, assigns `PREFIX-NN` (1-based, zero-padded ≥2 digits). Sorts all leads by `(file, [int]line, kind)`, assigns `L-NN`.

### Prefix assignments applied

| Type | Prefix | Tier |
|---|---|---|
| default-control-name | DN | narrative |
| default-screen-name | DS | narrative |
| variable-prefix | VP | enumeration |
| collection-prefix | VP | enumeration |
| unused-variable | UV | enumeration |
| unused-collection | UC | enumeration |
| unused-datasource | UD | enumeration |
| orphan-screen | OS | narrative |
| unreferenced-control | UR | enumeration |
| exact-duplicate-formula | XD | narrative |
| leads | L | n/a |

### SortKey conventions applied

- Name-keyed findings (variables, collections, data sources): `"$name|$file|"`
- Location-keyed findings (controls, screens, duplicates): `"$file|$line|$evidence_or_name"`
- Leads: sorted by `(file, [int]line, kind)` at stamp time

### Stamp-Ids call location

Inserted immediately before the EMIT block (after the leads generation loop).

## Test results

**PASS=85 FAIL=0** — all tests pass including all 6 new tests in `06-id-stamping.tests.ps1`.

New tests cover:
1. Every deterministic finding in FieldServiceApp has well-formed id `^[A-Z]{2}-\d{2,}$`
2. Every lead in FieldServiceApp has well-formed id `^L-\d{2,}$`
3. At least one deterministic finding exists (sanity)
4. Finding IDs stable across two independent runs (DoD #10)
5. Lead IDs stable across two independent runs (DoD #10)
6. MaintainabilityKitchenSink findings/leads also well-formed (when any exist)

## Files modified

- `skills/canvas-app-analyzer/scripts/analyze-canvas.ps1` — added functions + refactored all 10 detector emit blocks + 5 lead emit blocks + added `Stamp-Ids` call
- `test/tests/06-id-stamping.tests.ps1` — new test file (written before implementation, per TDD)
- `.superpowers/sdd/task-6-report.md` — this report

---

## Reviewer Fixes (2026-06-21)

Applied four stability-hardening fixes to `analyze-canvas.ps1` and one new uniqueness test to `06-id-stamping.tests.ps1`.

### Fix A — XD sortKey collision (Important)

**Problem:** XD finding's `-SortKey` used `$snip` (evidence truncated to 240 chars). Two duplicate groups sharing the same first 240 characters got identical sortKeys, causing non-stable Sort-Object ordering and ID swaps.

**Before (line 775):**
```
-SortKey "$($first.file)|$($first.line)|$snip"
```
**After:**
```
-SortKey "$($first.file)|$($first.line)|$k"
```
`$k` is the full normalized formula text (the `$byNorm` hashtable key) — unique per duplicate group, arbitrary length, no truncation risk. Evidence shown to users (`$snip`) is unchanged.

### Fix B — Null line coercion in lead sort (Important)

**Problem:** `Stamp-Ids` sorted leads with `@{e={[int]$_.line}}`. If a lead's `line` is `$null`, PS 5.1 silently coerces it to 0, which is fragile and obscures intent.

**Before (line 256):**
```powershell
foreach ($l in ($Leads | Sort-Object @{e={$_.file}},@{e={[int]$_.line}},@{e={$_.kind}})) {
```
**After:**
```powershell
foreach ($l in ($Leads | Sort-Object @{e={$_.file}},@{e={ if ($null -eq $_.line) { 0 } else { [int]$_.line } }},@{e={$_.kind}})) {
```
Behavior for non-null lines is identical; null lines now explicitly sort as 0 rather than relying on silent coercion.

### Fix C — Typed New-Lead params (Minor)

**Problem:** `New-Lead`'s scalar params had no type annotations, unlike `New-Finding`'s typed params.

**Before (line 227):**
```powershell
param($Kind,$Category,$Screen,$Control,$Property,$File,$Line,$Snippet,$Hint)
```
**After:**
```powershell
param([string]$Kind,[string]$Category,$Screen,$Control,$Property,[string]$File,[string]$Line,[string]$Snippet,[string]$Hint)
```
`$Screen`, `$Control`, `$Property` left untyped as they can legitimately hold non-string values in future.

### Fix D — DS sortKey to file-first convention (Minor)

**Problem:** DS (default-screen-name) finding used name-first sortKey `"$sn|$($rf.file)|1"`, while convention is file-first.

**Before (line 668):**
```
-SortKey "$sn|$($rf.file)|1"
```
**After:**
```
-SortKey "$($rf.file)|1|$sn"
```
OS (orphan-screen) at line 738 has the same format and was intentionally left unchanged as it is a different prefix/group.

### New uniqueness test (06-id-stamping.tests.ps1)

Added Test 6b (inserted before existing Test 6):
```powershell
Assert-Equal (@($mech.deterministicFindings.id | Sort-Object -Unique).Count) (@($mech.deterministicFindings).Count) 'all finding ids unique'
```
Asserts no two findings in FieldServiceApp share an id. Catches sortKey-collision regressions cheaply.

### Run-tests output after fixes

```
RUN 00-smoke.tests.ps1
RUN 01-component-classification.tests.ps1
RUN 02-deterministic-order.tests.ps1
RUN 03-tokenizer.tests.ps1
RUN 04-control-depth.tests.ps1
RUN 05-thresholds.tests.ps1
RUN 06-id-stamping.tests.ps1

PASS=86 FAIL=0
```
(+1 test vs. prior PASS=85; FAIL=0; existing two-run stability assertions still pass.)
