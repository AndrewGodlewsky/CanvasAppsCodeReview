# Canvas App Analyzer — Depth Improvements (v-next) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the Canvas App Analyzer's two depth gaps — shallow detection and model-summarized (not enumerated) output — by adding ~21 detectors and shifting enumeration/summary authoring from the model into the deterministic PowerShell script.

**Architecture:** The analyzer (`analyze-canvas.ps1`) gains all new detectors, stamps stable IDs on every finding/lead via a deterministic post-pass, and now *authors* the exhaustive enumeration tables (`.analysis/enumeration.md`) plus a summary-counts block — making completeness true by construction. A new, separate `verify-report.ps1` reconciles the finished report against the machine findings (narrative + leads accounting only). The model writes only the narrative. Everything is proven by a native PowerShell test runner driving a kitchen-sink fixture with asserted golden counts.

**Tech Stack:** Windows PowerShell 5.1 (native only — no Pester, no modules), `System.IO.Compression` for zip, line/indent regex parsing of `.pa.yaml`. Git for version control.

## Global Constraints

- **Read-only.** Never modify the app, never repack, never run `pac canvas pack/unpack`. Read only extracted `\Src\*.pa.yaml` (and `\DataSources\*.json` for connector type only).
- **Native PowerShell only.** No external modules (no Pester). Extraction via `System.IO.Compression.ZipFile` / `Expand-Archive`. Recursive `.msapp` search — no hardcoded path.
- **Single-agent execution.** No sub-agent fan-out. Keep the existing "note fan-out as scale-up path" fallback text unchanged.
- **Decisions D1–D9 are settled** (see `canvas-app-analyzer-improvement-brief.md`). Do not redesign them.
- **Confirmed open decisions:** (1) IDs = `PREFIX-NN` zero-padded sequential over a deterministically sorted list; (2) ND = normalized Levenshtein ratio ≥ 0.90 with a 60-char floor and length bucketing; (3) component classification = content/structure-based, tolerant of both `\Component\` and `\Components\`; (4) enumeration = script-generated sibling `.analysis/enumeration.md` + a small inline summary block the model embeds.
- **Thresholds** are named constants at the top of `analyze-canvas.ps1`, conservative documented defaults, each overridable via `CAA_*` environment variable (so tests trip them on a small fixture).
- **Per-detector citation is mandatory (D6).** A detector is not "done" until its reference-doc section + citation exist. Where no dedicated MS doc exists, cite the general PowerApps coding-guidelines page and **label it** as a general maintainability principle.
- **⚠️ Component-folder doc discrepancy (flagged & accepted):** current MS Learn docs say the component folder is singular `\Component`; the brief's §7.1 assumed plural `\Components`. The chosen classification is content/structure-based and tolerant of both spellings, so it is correct under either reality. Do not "fix" by assuming one spelling.

---

## File Structure

**Modified:**
- `skills/canvas-app-analyzer/scripts/analyze-canvas.ps1` — all new detectors; ID stamping; threshold constants; tokenizer; control depth; component-classification fix; generates `enumeration.md` + summary block.
- `skills/canvas-app-analyzer/SKILL.md` — two-tier authoring; "never fabricate, never omit"; per-control verdicts; run `verify-report.ps1`; batch long-tail backlog.
- `skills/canvas-app-analyzer/reference/coding-standards-and-performance.md` — one section per new detector + citation.
- `test/build-fixture.ps1` — adds the `MaintainabilityKitchenSink.msapp` fixture (grown task-by-task).
- `examples/FieldServiceApp.analysis.md`, `examples/mechanical-findings.json`, `examples/index.json` — regenerated.

**Created:**
- `skills/canvas-app-analyzer/scripts/verify-report.ps1` — deterministic report↔findings reconciliation (gap JSON).
- `test/run-tests.ps1` — native test runner (builds fixtures, runs analyzer once per env config, dot-sources test files, prints pass/fail summary, non-zero exit on failure).
- `test/lib/test-helpers.ps1` — `Assert-Equal`, `Assert-True`, `Assert-Match`, `Assert-IdSet`, `Invoke-Analyzer` (cached), `Get-Findings`.
- `test/tests/*.tests.ps1` — one file per detector/infra task with golden-count + negative-case assertions.

---

## Shared interfaces (defined in early tasks; later tasks consume these)

These signatures are introduced in Tasks 0–8 and reused by every detector task:

- `New-Finding -Prefix -Type -Category -Severity -Confidence -Location -Evidence -Message -SortKey [-Tier] [-Citation] [-Verdict]` → `[pscustomobject]` with `id=$null` (stamped later). `Tier` ∈ `'narrative'|'enumeration'`. (Task 6)
- `New-Lead -Kind -Category -Screen -Control -Property -File -Line -Snippet -Hint` → lead object with `id=$null`. (Task 6)
- `Stamp-Ids [ref]$Findings [ref]$Leads` → assigns `id = "$Prefix-{0:D2}"` per prefix group, ordered by `SortKey`; leads share prefix `L` ordered by `file,line,kind`. (Task 6)
- `Split-FormulaSpans [string]$Text` → `[pscustomobject]@{ Code=<string with each "..." literal replaced by a same-length placeholder>; Strings=@(<literal contents without quotes>) }`. Power Fx string literals are double-quoted with `""` escaping. (Task 3)
- Control records gain `depth` (count of control ancestors) and `ancestors` (array of control names). (Task 4)
- Threshold constants `$T_*` seeded from `CAA_*` env vars. (Task 5)
- `Invoke-Analyzer -Fixture <name.msapp> [-EnvOverrides @{}]` (test helper) → returns parsed `mechanical-findings.json`; caches the default (no-override) run. (Task 0)
- `Get-Findings $mech -Prefix 'UV'` (test helper) → array of findings whose `prefix` matches. (Task 0)

---

# Phase 0 — Test infrastructure

### Task 0: Native test runner + helpers + kitchen-sink fixture skeleton

**Files:**
- Create: `test/lib/test-helpers.ps1`
- Create: `test/run-tests.ps1`
- Create: `test/tests/00-smoke.tests.ps1`
- Modify: `test/build-fixture.ps1` (add kitchen-sink skeleton)

**Interfaces:**
- Produces: `Assert-Equal`, `Assert-True`, `Assert-Match`, `Assert-IdSet`, `Invoke-Analyzer`, `Get-Findings`; the `MaintainabilityKitchenSink.msapp` fixture; `$script:TestPass`/`$script:TestFail` counters.

- [ ] **Step 1: Write the failing smoke test** — `test/tests/00-smoke.tests.ps1`:

```powershell
# Smoke: the kitchen-sink fixture exists, analyzer returns ok, src persisted.
$mech = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
Assert-True ($null -ne $mech) 'analyzer produced mechanical-findings.json'
Assert-True ($mech.deterministicFindings.Count -ge 0) 'deterministicFindings present'
```

- [ ] **Step 2: Run to verify it fails** — `powershell -NoProfile -ExecutionPolicy Bypass -File test/run-tests.ps1`. Expected: FAIL (helpers/fixture/runner not defined yet).

- [ ] **Step 3: Write `test/lib/test-helpers.ps1`:**

```powershell
$script:TestPass = 0; $script:TestFail = 0; $script:Failures = @()
function Assert-True($cond,$msg){ if($cond){$script:TestPass++}else{$script:TestFail++;$script:Failures+=$msg;Write-Host "  FAIL: $msg" -ForegroundColor Red} }
function Assert-Equal($actual,$expected,$msg){ Assert-True ($actual -eq $expected) "$msg (expected '$expected', got '$actual')" }
function Assert-Match($text,$pattern,$msg){ Assert-True ([bool]($text -match $pattern)) "$msg (no match /$pattern/)" }
function Assert-IdSet($findings,$expectedIds,$msg){
    $got = @($findings | ForEach-Object { $_.id } | Sort-Object)
    $exp = @($expectedIds | Sort-Object)
    Assert-True (($got -join ',') -eq ($exp -join ',')) "$msg (expected [$($exp -join ',')], got [$($got -join ',')])"
}
$script:_analyzerCache = @{}
function Invoke-Analyzer {
    param([string]$Fixture,[hashtable]$EnvOverrides=@{})
    $key = $Fixture + '|' + (($EnvOverrides.GetEnumerator()|Sort-Object Name|ForEach-Object{"$($_.Name)=$($_.Value)"}) -join ';')
    if ($script:_analyzerCache.ContainsKey($key)) { return $script:_analyzerCache[$key] }
    $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script = Join-Path $repo 'skills/canvas-app-analyzer/scripts/analyze-canvas.ps1'
    $fixturePath = Join-Path $repo "test/fixtures/$Fixture"
    $outRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('caatest_' + [Guid]::NewGuid().ToString('N'))
    $saved = @{}
    foreach($k in $EnvOverrides.Keys){ $saved[$k]=[Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k,$EnvOverrides[$k]) }
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Path $fixturePath -OutputRoot $outRoot | Out-Null
        $mf = Get-ChildItem -Path $outRoot -Recurse -Filter 'mechanical-findings.json' | Select-Object -First 1
        $result = if ($mf) { Get-Content -LiteralPath $mf.FullName -Raw | ConvertFrom-Json } else { $null }
    } finally {
        foreach($k in $EnvOverrides.Keys){ [Environment]::SetEnvironmentVariable($k,$saved[$k]) }
    }
    $script:_analyzerCache[$key] = $result
    return $result
}
function Get-Findings($mech,[string]$Prefix){ @($mech.deterministicFindings | Where-Object { $_.prefix -eq $Prefix }) }
function Get-Leads($mech){ @($mech.leads) }
```

- [ ] **Step 4: Write `test/run-tests.ps1`:**

```powershell
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
& (Join-Path $here 'build-fixture.ps1') | Out-Null            # regenerate all fixtures
. (Join-Path $here 'lib/test-helpers.ps1')
foreach ($t in Get-ChildItem (Join-Path $here 'tests') -Filter '*.tests.ps1' | Sort-Object Name) {
    Write-Host "RUN $($t.Name)" -ForegroundColor Cyan
    . $t.FullName
}
Write-Host ""
Write-Host "PASS=$script:TestPass FAIL=$script:TestFail" -ForegroundColor ($(if($script:TestFail){'Red'}else{'Green'}))
if ($script:TestFail -gt 0) { exit 1 } else { exit 0 }
```

- [ ] **Step 5: Add kitchen-sink skeleton to `build-fixture.ps1`** (after the existing fixtures, before `Remove-Item -Recurse -Force $stage`). Minimal App + one screen + one component file so the analyzer returns `ok`:

```powershell
# ---- MaintainabilityKitchenSink: planted, known-count fixture (grown per detector) ----
$ks = Join-Path $stage 'ks'; $ksSrc = Join-Path $ks 'Src'; $ksComp = Join-Path $ksSrc 'Components'; $ksDs = Join-Path $ks 'DataSources'
New-Item -ItemType Directory -Path $ksComp,$ksDs -Force | Out-Null
W (Join-Path $ksSrc 'App.pa.yaml') @'
App:
    Properties:
        StartScreen: =MainScreen
        OnStart: =Set(gblTitle, "Kitchen Sink")
'@
W (Join-Path $ksSrc 'MainScreen.pa.yaml') @'
Screens:
    MainScreen:
        Children:
            - lblTitle:
                Control: Label@2.0.0
                Properties:
                    Text: =gblTitle
'@
W (Join-Path $ksComp 'cmpHeader.pa.yaml') @'
ComponentDefinitions:
    cmpHeader:
        Type: CanvasComponent
        CustomProperties:
            HeaderText:
                PropertyKind: Input
                DataType: Text
        Children:
            - lblHeader:
                Control: Label@2.0.0
                Properties:
                    Text: =cmpHeader.HeaderText
'@
W (Join-Path $ksDs 'Orders.json') '{"Name":"Orders","Type":"Table","ApiId":"/providers/microsoft.powerapps/apis/shared_sharepointonline"}'
W (Join-Path $ks 'CanvasManifest.json') '{"Properties":{"Name":"MaintainabilityKitchenSink"}}'
[System.IO.Compression.ZipFile]::CreateFromDirectory($ks, (Join-Path $fix 'MaintainabilityKitchenSink.msapp'))
```

- [ ] **Step 6: Run to verify it passes** — `powershell -NoProfile -ExecutionPolicy Bypass -File test/run-tests.ps1`. Expected: `PASS=2 FAIL=0`.

- [ ] **Step 7: Commit** — `git add test/ && git commit -m "test: native test runner + helpers + kitchen-sink fixture skeleton"`

---

# Phase 1 — Silent-failure infrastructure (highest priority)

### Task 1: §7.1 Component classification — content/structure-based, spelling-tolerant

**Files:**
- Modify: `analyze-canvas.ps1` (the `foreach ($f in $paFiles)` parse loop, currently the `$isComponent = ...` line ~267)
- Test: `test/tests/01-component-classification.tests.ps1`

**Interfaces:**
- Produces: a file is classified as a component when its content declares a component definition, regardless of folder spelling. `$compFiles[$screenLabel]=$true` for component files; component type names available for `UK`/`UP`.

- [ ] **Step 1: Write the failing test:**

```powershell
$mech = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
# index.json must list cmpHeader as a component, and MainScreen as a screen (not a component).
$idx = Get-ChildItem -Path ([System.IO.Path]::GetTempPath()) -Recurse -Filter 'index.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
$index = Get-Content $idx.FullName -Raw | ConvertFrom-Json
Assert-True (@($index.components) -contains 'cmpHeader') 'cmpHeader classified as component'
Assert-True (@($index.screens | ForEach-Object { $_.name }) -contains 'MainScreen') 'MainScreen classified as screen'
Assert-True (-not (@($index.components) -contains 'MainScreen')) 'MainScreen is NOT a component'
```

(Note: prefer reading `index.json` from the analyzer output dir directly; the helper's temp-dir scan above is acceptable for the test but consider extending `Invoke-Analyzer` to also return the index in this task.)

- [ ] **Step 2: Run to verify it fails** — Expected: FAIL (current heuristic misclassifies; `cmpHeader.pa.yaml` filename lacks "Component" and folder may be `Components`).

- [ ] **Step 3: Implement content/structure-based classification.** Replace the `$isComponent = ...` line. Read the file's lines first (move the `Get-Content` above the classification), then:

```powershell
$lines = Get-Content -LiteralPath $f.FullName
# Content/structure signal: a component-definition file declares a CanvasComponent node
# (ComponentDefinitions:, "Type: CanvasComponent", or a top-level CustomProperties block).
# Tolerate BOTH \Component\ and \Components\ folder spellings as a secondary signal.
$headText = ($lines | Select-Object -First 60) -join "`n"
$isComponent = ($headText -imatch '(?m)^\s*ComponentDefinitions\s*:') `
    -or ($headText -imatch '(?im)Type\s*:\s*CanvasComponent') `
    -or ($f.FullName -imatch '[\\/]Components?[\\/]')
$isApp = $f.Name -ieq 'App.pa.yaml'
```

Remove the now-duplicate `$lines = Get-Content ...` later in the loop. Capture component type names into a hashtable `$componentTypes[$screenLabel]=$true` for later UK/UP use (same as `$compFiles`).

- [ ] **Step 4: Run to verify it passes** — Expected: PASS.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "fix: classify components by structure, tolerant of folder spelling (§7.1)"`

---

### Task 2: §7.2 Deterministic ordering for stable IDs

**Files:**
- Modify: `analyze-canvas.ps1` (controls list build; `$variables`/`$collectionList` build from hashtable `.Keys`)
- Test: `test/tests/02-deterministic-order.tests.ps1`

**Interfaces:**
- Produces: `$controls`, `$variables`, `$collectionList` sorted deterministically (by `name`, then `file`, then `line`) before any detector consumes them or IDs are stamped.

- [ ] **Step 1: Write the failing test** — run the analyzer twice and assert byte-identical ordering of the controls/variables arrays:

```powershell
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script = Join-Path $repo 'skills/canvas-app-analyzer/scripts/analyze-canvas.ps1'
$fx = Join-Path $repo 'test/fixtures/MaintainabilityKitchenSink.msapp'
function _run { $o=Join-Path ([IO.Path]::GetTempPath()) ('det_'+[Guid]::NewGuid().ToString('N'))
    & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Path $fx -OutputRoot $o | Out-Null
    (Get-ChildItem $o -Recurse -Filter index.json | Select -First 1).FullName }
$a = Get-Content (_run) -Raw; $b = Get-Content (_run) -Raw
$ja = ($a | ConvertFrom-Json); $jb = ($b | ConvertFrom-Json)
Assert-Equal (($ja.controls|ForEach-Object{$_.name}) -join ',') (($jb.controls|ForEach-Object{$_.name}) -join ',') 'controls order stable'
Assert-Equal (($ja.variables|ForEach-Object{$_.name}) -join ',') (($jb.variables|ForEach-Object{$_.name}) -join ',') 'variables order stable'
```

- [ ] **Step 2: Run to verify it fails** — Expected: may pass by luck on a tiny fixture; force a multi-item case by ensuring the kitchen-sink App.OnStart sets ≥3 globals out of alpha order, then it reliably fails pre-fix. (Add `Set(gblZebra,1);Set(gblApple,2)` to the App.OnStart in build-fixture if needed.)

- [ ] **Step 3: Implement sorting.** After the controls parse loop, replace usages so the canonical list is sorted:

```powershell
$controls = @($controls | Sort-Object name, file, line)
```

After building `$variables` and `$collectionList`:

```powershell
$variables = @($variables | Sort-Object name, scope, definedIn)
$collectionList = @($collectionList | Sort-Object name, definedIn)
```

(Data sources already use `Sort-Object name -Unique`.)

- [ ] **Step 4: Run to verify it passes** — Expected: PASS twice, identical order.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "fix: deterministic ordering of controls/vars/collections for stable IDs (§7.2)"`

---

# Phase 2 — Enabling infrastructure

### Task 3: §7.3 Shared formula tokenizer (string-literal vs code spans)

**Files:**
- Modify: `analyze-canvas.ps1` (add `Split-FormulaSpans` helper near the other helper functions)
- Test: `test/tests/03-tokenizer.tests.ps1`

**Interfaces:**
- Produces: `Split-FormulaSpans([string]$Text)` → `@{ Code=<string, each "..." literal replaced by spaces of equal length>; Strings=@(<unescaped literal contents>) }`.

- [ ] **Step 1: Write the failing test** (dot-source the analyzer's function only is hard; instead test via a thin exposure: add a `-SelfTest` no-op is overkill). Test by calling the function through a small harness script that dot-sources the analyzer's function region. Simplest: copy the function into the test is forbidden (DRY). Instead, assert behavior indirectly is weak. **Chosen approach:** extract `Split-FormulaSpans` is a pure function — add a guarded `if ($args[0] -eq '--__spans')` shim at the very top of `analyze-canvas.ps1` that prints `Split-FormulaSpans($args[1])` as JSON and exits, so tests can invoke it. Test:

```powershell
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script = Join-Path $repo 'skills/canvas-app-analyzer/scripts/analyze-canvas.ps1'
$json = & powershell -NoProfile -ExecutionPolicy Bypass -File $script '--__spans' '=Navigate(HomeScreen) // go home' | ConvertFrom-Json
Assert-Match $json.Code '//\s*go home' 'comment stays in code span'
$json2 = & powershell -NoProfile -ExecutionPolicy Bypass -File $script '--__spans' '=Set(x, "https://example.com/a//b")' | ConvertFrom-Json
Assert-True (-not ($json2.Code -match '//')) 'slashes inside string literal are NOT in code span'
Assert-True (@($json2.Strings) -contains 'https://example.com/a//b') 'URL captured as string literal'
```

- [ ] **Step 2: Run to verify it fails** — Expected: FAIL (shim + function absent).

- [ ] **Step 3: Implement.** Add at the very top of the `try`-block region (before path checks) the self-test shim, and add the function with the other helpers:

```powershell
function Split-FormulaSpans {
    param([string]$Text)
    if ($null -eq $Text) { return [pscustomobject]@{ Code=''; Strings=@() } }
    $code = New-Object System.Text.StringBuilder
    $strings = New-Object System.Collections.ArrayList
    $i = 0; $n = $Text.Length
    while ($i -lt $n) {
        $ch = $Text[$i]
        if ($ch -eq '"') {
            $i++; $lit = New-Object System.Text.StringBuilder
            while ($i -lt $n) {
                if ($Text[$i] -eq '"') {
                    if ($i+1 -lt $n -and $Text[$i+1] -eq '"') { [void]$lit.Append('"'); $i+=2; continue }
                    $i++; break
                }
                [void]$lit.Append($Text[$i]); $i++
            }
            [void]$strings.Add($lit.ToString())
            [void]$code.Append(' ' * ($lit.Length + 2))   # keep column alignment
        } else { [void]$code.Append($ch); $i++ }
    }
    [pscustomobject]@{ Code=$code.ToString(); Strings=@($strings) }
}
```

Self-test shim (top of script, before any work):

```powershell
if ($Path -eq '--__spans') { (Split-FormulaSpans $AppName) | ConvertTo-Json -Compress; exit 0 }
```

(Place after `Split-FormulaSpans` is defined; `$AppName` carries the 2nd positional arg.)

- [ ] **Step 4: Run to verify it passes** — Expected: PASS.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: shared formula tokenizer (string-literal vs code spans) (§7.3)"`

---

### Task 4: §7.4 Persist control nesting depth / ancestor chain

**Files:**
- Modify: `analyze-canvas.ps1` (parse loop — add a control-only stack; record `depth` + `ancestors` on each control)
- Test: `test/tests/04-control-depth.tests.ps1`

**Interfaces:**
- Produces: each `$controls` record gains `depth` (int, count of control ancestors; top-level control = 1) and `ancestors` (string[] of control names). `$curControl` now derives from the control-only stack (nearest control ancestor).

- [ ] **Step 1: Add nested controls to the kitchen-sink fixture** (in `build-fixture.ps1`, MainScreen) — a container holding a container holding a label:

```yaml
            - conOuter:
                Control: GroupContainer@1.3.0
                Children:
                    - conInner:
                        Control: GroupContainer@1.3.0
                        Children:
                            - lblDeep:
                                Control: Label@2.0.0
                                Properties:
                                    Text: ="deep"
```

- [ ] **Step 2: Write the failing test:**

```powershell
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$idx = (Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp') | Out-Null
$index = Get-Content ((Get-ChildItem ([IO.Path]::GetTempPath()) -Recurse -Filter index.json|Sort LastWriteTime|Select -Last 1).FullName) -Raw | ConvertFrom-Json
$deep = $index.controls | Where-Object { $_.name -eq 'lblDeep' } | Select-Object -First 1
Assert-Equal $deep.depth 3 'lblDeep nested 3 controls deep'
```

(Requires `depth` in the index controls projection — add it.)

- [ ] **Step 3: Implement the control-only stack.** In the parse loop, add `$ctrlStack = New-Object System.Collections.Stack` alongside `$stack`. On every line, after popping `$stack`, also pop `$ctrlStack` entries whose `Indent -ge $indent`. When a control is detected, compute `depth = $ctrlStack.Count + 1` and `ancestors = @($ctrlStack.ToArray() | ForEach-Object { $_.Name })` (reverse for root-first), then push `[pscustomobject]@{Indent=$indent;Name=$key}` to `$ctrlStack`. Set `$curControl = $key`. Add `depth` and `ancestors` to the control record. Replace owner resolution (`$owner = $curControl`) to use `$ctrlStack.Peek().Name` when non-empty. Add `depth=$_.depth` to the index `controls` projection.

- [ ] **Step 4: Run to verify it passes** — Expected: PASS (`depth=3`).

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: persist control depth + ancestor chain (§7.4)"`

---

### Task 5: §7.5 Overridable threshold constants

**Files:**
- Modify: `analyze-canvas.ps1` (named constants block near the top, after param block)
- Test: `test/tests/05-thresholds.tests.ps1`

**Interfaces:**
- Produces: `$T_LongFormulaBytes` (500), `$T_DeepIfDepth` (4), `$T_GodScreenControls` (40), `$T_GodScreenBytes` (20000), `$T_ControlTreeDepth` (5), `$T_RepeatedLiteralMin` (3), `$T_NearDupRatio` (0.90), `$T_NearDupMinLen` (60), `$T_GlobalOveruse` (20). Each overridable via `CAA_<UPPER_SNAKE>` env var.

- [ ] **Step 1: Write the failing test** — assert an override changes behavior. Use a tiny self-test echo: add (temporarily testable) a `--__thresholds` shim that prints the resolved values:

```powershell
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script = Join-Path $repo 'skills/canvas-app-analyzer/scripts/analyze-canvas.ps1'
[Environment]::SetEnvironmentVariable('CAA_LONG_FORMULA_BYTES','120')
try { $t = & powershell -NoProfile -ExecutionPolicy Bypass -File $script '--__thresholds' | ConvertFrom-Json }
finally { [Environment]::SetEnvironmentVariable('CAA_LONG_FORMULA_BYTES',$null) }
Assert-Equal $t.T_LongFormulaBytes 120 'env override applied'
```

- [ ] **Step 2: Run to verify it fails** — Expected: FAIL.

- [ ] **Step 3: Implement.** After the param block, add:

```powershell
function _Thr([string]$name,[double]$default){ $v=[Environment]::GetEnvironmentVariable("CAA_$name"); if($v){ if($v -match '^\d+(\.\d+)?$'){return [double]$v} }; return $default }
$T_LongFormulaBytes  = _Thr 'LONG_FORMULA_BYTES' 500
$T_DeepIfDepth       = _Thr 'DEEP_IF_DEPTH' 4
$T_GodScreenControls = _Thr 'GOD_SCREEN_CONTROLS' 40
$T_GodScreenBytes    = _Thr 'GOD_SCREEN_BYTES' 20000
$T_ControlTreeDepth  = _Thr 'CONTROL_TREE_DEPTH' 5
$T_RepeatedLiteralMin= _Thr 'REPEATED_LITERAL_MIN' 3
$T_NearDupRatio      = _Thr 'NEAR_DUP_RATIO' 0.90
$T_NearDupMinLen     = _Thr 'NEAR_DUP_MIN_LEN' 60
$T_GlobalOveruse     = _Thr 'GLOBAL_OVERUSE' 20
```

Self-test shim:

```powershell
if ($Path -eq '--__thresholds') { [ordered]@{ T_LongFormulaBytes=$T_LongFormulaBytes; T_DeepIfDepth=$T_DeepIfDepth; T_GodScreenControls=$T_GodScreenControls; T_GodScreenBytes=$T_GodScreenBytes; T_ControlTreeDepth=$T_ControlTreeDepth; T_RepeatedLiteralMin=$T_RepeatedLiteralMin; T_NearDupRatio=$T_NearDupRatio; T_NearDupMinLen=$T_NearDupMinLen; T_GlobalOveruse=$T_GlobalOveruse } | ConvertTo-Json -Compress; exit 0 }
```

Document each constant with a one-line comment.

- [ ] **Step 4: Run to verify it passes** — Expected: PASS.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: overridable threshold constants (§7.5)"`

---

# Phase 3 — Output architecture (ID stamping, enumeration/summary, verifier)

### Task 6: ID stamping (D3) + finding/lead constructors

**Files:**
- Modify: `analyze-canvas.ps1` (add `New-Finding`, `New-Lead`, `Stamp-Ids`; refactor existing detectors to use them; call `Stamp-Ids` before emit; add `prefix`/`id`/`tier` to every finding)
- Test: `test/tests/06-id-stamping.tests.ps1`

**Interfaces:**
- Produces: every finding has `id` (`PREFIX-NN`), `prefix`, `tier`, `sortKey`; every lead has `id` (`L-NN`). Prefix map: existing detectors get `DN,DS,VP`(var)/`VC`(collection? no — keep `VP` for both), `UV,UC,UD,OS,UR,XD`. See mapping below.

**Prefix map (existing + this task):**
`default-control-name=DN`, `default-screen-name=DS`, `variable-prefix=VP`, `collection-prefix=VP`, `unused-variable=UV`, `unused-collection=UC`, `unused-datasource=UD`, `orphan-screen=OS`, `unreferenced-control=UR`, `exact-duplicate-formula=XD`.

- [ ] **Step 1: Write the failing test:**

```powershell
$mech = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
foreach ($f in $mech.deterministicFindings) {
    Assert-Match $f.id '^[A-Z]{2}-\d{2,}$' "finding has well-formed id ($($f.type))"
}
# Stability: two runs → identical id->location mapping
$m2 = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp' -EnvOverrides @{ CAA_NOCACHE='1' }  # force second run
$map1 = ($mech.deterministicFindings | Sort-Object id | ForEach-Object { "$($_.id):$($_.type):$($_.evidence)" }) -join '|'
$map2 = ($m2.deterministicFindings  | Sort-Object id | ForEach-Object { "$($_.id):$($_.type):$($_.evidence)" }) -join '|'
Assert-Equal $map1 $map2 'IDs stable across runs (DoD #10)'
```

(The `CAA_NOCACHE` override only varies the cache key in the helper; the analyzer ignores it. This guarantees a genuine second invocation.)

- [ ] **Step 2: Run to verify it fails** — Expected: FAIL (no `id` field yet).

- [ ] **Step 3: Implement constructors + stamping.**

```powershell
function New-Finding {
    param($Prefix,$Type,$Category,$Severity,$Confidence,$Location,$Evidence,$Message,$SortKey,[string]$Tier='enumeration',[string]$Citation=$null,$Verdict=$null)
    [pscustomobject]@{ id=$null; prefix=$Prefix; type=$Type; category=$Category; severity=$Severity; confidence=$Confidence; tier=$Tier; citation=$Citation; verdict=$Verdict; location=$Location; evidence=$Evidence; message=$Message; sortKey=[string]$SortKey }
}
function New-Lead {
    param($Kind,$Category,$Screen,$Control,$Property,$File,$Line,$Snippet,$Hint)
    [pscustomobject]@{ id=$null; prefix='L'; category=$Category; kind=$Kind; screen=$Screen; control=$Control; property=$Property; file=$File; line=$Line; snippet=$Snippet; hint=$Hint }
}
function Stamp-Ids {
    param([System.Collections.IEnumerable]$Findings,[System.Collections.IEnumerable]$Leads)
    foreach ($grp in ($Findings | Group-Object prefix)) {
        $i = 0
        foreach ($f in ($grp.Group | Sort-Object sortKey)) { $i++; $f.id = ('{0}-{1:D2}' -f $grp.Name, $i) }
    }
    $j = 0
    foreach ($l in ($Leads | Sort-Object @{e={$_.file}},@{e={[int]$_.line}},@{e={$_.kind}})) { $j++; $l.id = ('L-{0:D2}' -f $j) }
}
```

Refactor each existing `[void]$det.Add([pscustomobject]@{...})` to `[void]$det.Add( (New-Finding -Prefix 'XX' -Type '...' ... -SortKey "...") )`. SortKey convention: `"$file|$line|$evidence"` (or `"$name|$file|$line"` for name-keyed). Set `Tier='narrative'` for Medium+ and `'enumeration'` for Low. Refactor leads to `New-Lead`. Immediately before the emit block: `Stamp-Ids -Findings $det -Leads $leads`.

- [ ] **Step 4: Run to verify it passes** — Expected: PASS (well-formed + stable IDs).

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: stable IDs + finding/lead constructors (D3)"`

---

### Task 7: Script-generated enumeration.md + inline summary block (D2)

**Files:**
- Modify: `analyze-canvas.ps1` (emit `.analysis/enumeration.md` and `.analysis/summary.md`; add file paths to status JSON)
- Test: `test/tests/07-enumeration.tests.ps1`

**Interfaces:**
- Produces: `.analysis/enumeration.md` (one table per `type`, every finding row = `| id | severity | location | evidence |`, citation in the table header), `.analysis/summary.md` (category × severity counts + total + leads count). Status JSON `files` gains `enumeration` and `summary`.

- [ ] **Step 1: Write the failing test:**

```powershell
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp' | Out-Null
$enum = (Get-ChildItem ([IO.Path]::GetTempPath()) -Recurse -Filter 'enumeration.md' | Sort LastWriteTime | Select -Last 1)
Assert-True ($null -ne $enum) 'enumeration.md generated'
$txt = Get-Content $enum.FullName -Raw
$mech = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
foreach ($f in $mech.deterministicFindings) { Assert-Match $txt ([regex]::Escape($f.id)) "enumeration lists $($f.id) (DoD #2)" }
```

- [ ] **Step 2: Run to verify it fails** — Expected: FAIL.

- [ ] **Step 3: Implement** the enumeration + summary builders after `Stamp-Ids`, before emitting JSON. Group `$det` by `category` then `type`; emit a `##`/`###` table per type with the citation line from the finding's `citation`. Build `summary.md` as a category × (High/Med/Low) matrix plus a Confirmed/Potential split and a leads count. Write both with `Out-File -Encoding utf8`. Add to status `files`. Row-count-per-category must equal the emitted total (guaranteed since we iterate the full `$det`).

- [ ] **Step 4: Run to verify it passes** — Expected: PASS (every ID present).

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: script-generated enumeration.md + summary block (D2)"`

---

### Task 8: verify-report.ps1 (D4) + complete/incomplete tests

**Files:**
- Create: `skills/canvas-app-analyzer/scripts/verify-report.ps1`
- Test: `test/tests/08-verify-report.tests.ps1`

**Interfaces:**
- Produces: `verify-report.ps1 -ReportPath <md> -FindingsPath <mechanical-findings.json>` → prints `{ "complete": <bool>, "missing": [<finding ids absent from report, severity High/Medium only>], "unaddressedLeads": [<lead ids absent from report>] }`. Low findings are covered by `enumeration.md` (D2) and are NOT required in the narrative.

- [ ] **Step 1: Write the failing test:**

```powershell
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$verify = Join-Path $repo 'skills/canvas-app-analyzer/scripts/verify-report.ps1'
$mech = Invoke-Analyzer -Fixture 'MaintainabilityKitchenSink.msapp'
$mfPath = (Get-ChildItem ([IO.Path]::GetTempPath()) -Recurse -Filter 'mechanical-findings.json'|Sort LastWriteTime|Select -Last 1).FullName
$required = @($mech.deterministicFindings | Where-Object { $_.severity -in 'High','Medium' } | ForEach-Object { $_.id }) + @($mech.leads | ForEach-Object { $_.id })
# Complete report: mentions every required id
$complete = Join-Path ([IO.Path]::GetTempPath()) ('rep_'+[Guid]::NewGuid().ToString('N')+'.md')
($required -join "`n") | Out-File $complete -Encoding utf8
$r1 = & powershell -NoProfile -ExecutionPolicy Bypass -File $verify -ReportPath $complete -FindingsPath $mfPath | ConvertFrom-Json
Assert-True $r1.complete 'complete report → complete:true (DoD #3)'
# Incomplete: drop the first required id
$incomplete = Join-Path ([IO.Path]::GetTempPath()) ('rep_'+[Guid]::NewGuid().ToString('N')+'.md')
(($required | Select-Object -Skip 1) -join "`n") | Out-File $incomplete -Encoding utf8
$r2 = & powershell -NoProfile -ExecutionPolicy Bypass -File $verify -ReportPath $incomplete -FindingsPath $mfPath | ConvertFrom-Json
Assert-True (-not $r2.complete) 'incomplete report → complete:false'
Assert-True ((@($r2.missing)+@($r2.unaddressedLeads)) -contains $required[0]) 'names the exact missing id'
```

- [ ] **Step 2: Run to verify it fails** — Expected: FAIL (`verify-report.ps1` absent).

- [ ] **Step 3: Implement `verify-report.ps1`:**

```powershell
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ReportPath,[Parameter(Mandatory)][string]$FindingsPath)
$ErrorActionPreference='Stop'
try {
    $report = Get-Content -LiteralPath $ReportPath -Raw
    $mech = Get-Content -LiteralPath $FindingsPath -Raw | ConvertFrom-Json
    $missing = @(); $unaddressed = @()
    foreach ($f in $mech.deterministicFindings) {
        if ($f.severity -in 'High','Medium') {
            if ($report -notmatch ('(?<![\w-])' + [regex]::Escape($f.id) + '(?![\w-])')) { $missing += $f.id }
        }
    }
    foreach ($l in $mech.leads) {
        if ($report -notmatch ('(?<![\w-])' + [regex]::Escape($l.id) + '(?![\w-])')) { $unaddressed += $l.id }
    }
    [ordered]@{ complete=(($missing.Count -eq 0) -and ($unaddressed.Count -eq 0)); missing=$missing; unaddressedLeads=$unaddressed } | ConvertTo-Json -Compress
    exit 0
} catch { @{ complete=$false; error=$_.Exception.Message } | ConvertTo-Json -Compress; exit 0 }
```

- [ ] **Step 4: Run to verify it passes** — Expected: PASS (both cases).

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: verify-report.ps1 narrative/leads reconciliation (D4)"`

---

# Phase 4 — Detectors (test-first; each gated on its prerequisites)

**Per-detector task template** (every detector follows this; only the specifics differ):
1. Plant the pattern in `build-fixture.ps1` (kitchen-sink), with a **negative** companion that must NOT fire.
2. Write the test: exact count + exact IDs (`Assert-IdSet`) + negative assertion.
3. Run → fail.
4. Implement the detector via `New-Finding`/`New-Lead`; add the reference-doc section + wire its `citation`.
5. Run → pass.
6. Commit.

> **ID/severity/tier per detector** comes from brief §3. Citations: reuse existing reference sections where they exist; otherwise add a new section (D6), labeling general-guidance citations.

### Task 9: `CC` — commented-out code blocks (+ paired `MC` non-contradiction)

**Prereq:** Task 3 (tokenizer). **Severity** Low, **tier** enumeration. **Citation:** reference §1 *Comments* (new sub-note: "distinguishing commented-out code from intentional explanatory comments — general maintainability guidance").

- [ ] **Step 1: Fixture** — a control with BOTH a commented-out statement and a legitimate explanatory comment (drives DoD #12):

```yaml
            - btnSubmit:
                Control: Classic/Button@2.2.0
                Properties:
                    OnSelect: |
                        =// Submit the order to the back end
                        Set(gblBusy, true);
                        // Patch(Orders, Defaults(Orders), {Title: txtTitle.Text});
                        Notify("done")
```

Here `// Submit the order…` is prose (must NOT be CC); `// Patch(Orders,…)` is commented-out code (MUST be CC).

- [ ] **Step 2: Test** — `Assert-Equal (Get-Findings $mech 'CC').Count 1`; assert its evidence references the `Patch(` line; assert `MC` does NOT fire on this formula (Task 18 may not exist yet — if running CC before MC, assert only CC; add the MC cross-check assertion when MC lands).

- [ ] **Step 3: Implement.** For each formula, take `Split-FormulaSpans($text).Code`; find `//...` (to end of line) and `/* ... */` spans; for each commented chunk, classify as **code** if it matches `[A-Za-z_]\w*\s*\(` (function call) OR contains `=`/`;`/`{`/`}` AND is not natural-language (heuristic: contains a `(` or `;`). Emit one `CC` finding per control (or per formula) listing the commented-code line(s). Do NOT flag prose-only comments.

```powershell
$spans = Split-FormulaSpans $fm.text
foreach ($m in [regex]::Matches($spans.Code, '//(.*)$', 'Multiline')) {
    $c = $m.Groups[1].Value.Trim()
    if ($c -match '[A-Za-z_]\w*\s*\(' -or $c -match '[;{}]' ) { <# code-like → CC #> }
}
# plus a /\* ... \*/ singleline+multiline scan
```

- [ ] **Step 4-6:** run→pass; add §Comments note + citation; commit.

### Task 10: `UK` — unused custom components

**Prereq:** Task 1 (classification). **Severity** Med, **tier** narrative. **Citation:** new §"Components & reuse" → working-with-large-apps + create-component URLs.

- [ ] **Fixture:** keep `cmpHeader` defined but NEVER instantiate it on any screen (the skeleton already does this → UK fires once). Add a **negative:** a second component `cmpFooter` that IS instantiated (`Control: cmpFooter` on MainScreen) → must NOT fire.
- [ ] **Test:** `Assert-IdSet (Get-Findings $mech 'UK') @('UK-01')`; assert evidence names `cmpHeader`; assert `cmpFooter` absent.
- [ ] **Implement:** component type names = component file stems (from Task 1). Instantiation = any control whose `type` equals a component name (the parser already records control `type` from `Control:`). A defined component with zero instances → `UK`.

### Task 11: `UP` — unused component custom properties

**Prereq:** Task 1, Task 10. **Severity** Low, **tier** enumeration. **Citation:** §"Components & reuse" (labeled general).

- [ ] **Fixture:** give `cmpFooter` (instantiated) two custom properties — one read internally/by instance (`FooterText`), one never referenced (`UnusedProp`). UP fires once.
- [ ] **Test:** `Assert-IdSet (Get-Findings $mech 'UP') @('UP-01')`; evidence names `UnusedProp`.
- [ ] **Implement:** parse `CustomProperties:` child names in each component file; a property is used if `componentName.PropName` OR bare `PropName` appears in any formula (component-internal or instance). Unreferenced → `UP`.

### Task 12: `EH` — empty/stub event handlers

**Prereq:** none beyond Task 6. **Severity** Low, **tier** enumeration. **Citation:** §1 general coding-guidelines (labeled).

- [ ] **Fixture:** a control with `OnSelect: =false` (stub). Negative: a control with a real `OnSelect: =Navigate(...)`.
- [ ] **Test:** `Assert-Equal (Get-Findings $mech 'EH').Count 1`.
- [ ] **Implement:** property name matches `^On[A-Z]` (event) AND normalized text `-eq 'false'` → `EH`. (Truly blank handlers are dropped by the parser — out of scope per brief §3d.)

### Task 13: `HC` — permanently hidden controls

**Severity** Low, **tier** enumeration. **Citation:** §2 *Enhanced performance for hidden controls* / general.

- [ ] **Fixture:** control with `Visible: =false` literal. Negative: `Visible: =gblShowPanel` (dynamic).
- [ ] **Test:** `Assert-Equal (Get-Findings $mech 'HC').Count 1`.
- [ ] **Implement:** a control owns a `Visible` formula whose normalized text `-eq 'false'` → `HC` (note: "hidden permanently; if intentional, consider removing or documenting").

### Task 14: `DB` — dead conditional branches

**Severity** Low, **tier** enumeration. **Citation:** §2 *Code optimization* (labeled).

- [ ] **Fixture:** a formula with `If(false, Notify("x"), Notify("y"))`. Negative: `If(gblFlag, ...)`.
- [ ] **Test:** `Assert-Equal (Get-Findings $mech 'DB').Count 1`.
- [ ] **Implement:** scan code spans for `If\s*\(\s*(false|true)\b` or `Switch` with a literal constant selector → `DB`.

### Task 15: `DC` — duplicate/redundant controls

**Prereq:** Task 4. **Severity** Med, **tier** narrative. **Citation:** §2 *Split long formulas / Redundancy* + components.

- [ ] **Fixture:** two Labels with identical type + identical property set (same Text/Size/Color). Negative: a Label that differs.
- [ ] **Test:** `Assert-Equal (Get-Findings $mech 'DC').Count 1` (one group).
- [ ] **Implement:** signature = `type` + sorted property-name list + hash of normalized property values; group controls by signature; group size ≥ 2 → one `DC` finding listing the members.

### Task 16: `UR` — behavior-aware unreferenced-control verdict (D5 revision)

**Severity** Low, **tier** enumeration, **per-control `verdict`**. **Citation:** §3 *Dead/unused*.

- [ ] **Fixture:** (a) a control never referenced AND with no event handlers AND `Visible: =false` (strong dead candidate); (b) a decorative Label never referenced but `Visible` default true (NOT dead — verdict "decorative/keep"); (c) a control referenced by formula (not flagged).
- [ ] **Test:** assert `UR` count = 2 (both unreferenced get a verdict, but with different `verdict` text); assert the decorative one's `verdict` ≠ "dead candidate"; assert (c) absent. No blanket dismissal — each has an individual reasoned `verdict` (DoD #5).
- [ ] **Implement (replace existing UR loop):** for each unreferenced control compute behavior signals: hasNonDefaultEventHandler (any `On*` formula not `=false`), dataBound (owns an `Items`/`DataSource`/`Default`/`Text` bound to a data source or variable), visibleByDefault (no `Visible:=false`). `verdict='strong-dead-candidate'` only when none hold; else `verdict='likely-decorative-or-layout'` with the reason. Always emit per control (Potential).

### Task 17: `LF` — long/complex formula (wire up `deepNesting`)

**Prereq:** Task 5. **Severity** Med, **tier** narrative. **Citation:** §2 *Split long formulas* + *Formula formatting*.

- [ ] **Fixture:** a formula whose byte length exceeds a test override (`CAA_LONG_FORMULA_BYTES=120`). Negative: a short formula. Run this test with the env override.
- [ ] **Test:** `Invoke-Analyzer -EnvOverrides @{CAA_LONG_FORMULA_BYTES='120'}`; `Assert-Equal (Get-Findings $mech 'LF').Count 1`.
- [ ] **Implement:** for each formula, if `UTF8 byte count > $T_LongFormulaBytes` → `LF`. (Reuses the same signal the digest `deepNesting` trigger already computes; replace the hard-coded `500` there with `$T_LongFormulaBytes`.)

### Task 18: `MC` — complex formula with no comment (paired with CC)

**Prereq:** Task 3, Task 17. **Severity** Low, **tier** enumeration. **Citation:** §1 *Comments*.

- [ ] **Fixture:** reuse the CC fixture control (complex, has a real comment → MC must NOT fire) + a complex formula with ZERO comments (MC fires). This proves CC/MC non-contradiction (DoD #12).
- [ ] **Test:** assert `MC` fires on the comment-less complex formula and NOT on the CC fixture formula; add the deferred CC/MC cross-assertion from Task 9.
- [ ] **Implement:** formula is "complex" if `bytes > $T_LongFormulaBytes` OR deep-If depth ≥ `$T_DeepIfDepth`; if complex AND `Split-FormulaSpans(text).Code` contains no `//` and no `/* */` → `MC`.

### Task 19: `DI` — deep If/Switch nesting

**Prereq:** Task 5. **Severity** Med, **tier** narrative. **Citation:** §2 *With function* / efficient-calculations.

- [ ] **Fixture:** `If(a, If(b, If(c, If(d, 1))))` (depth 4). Negative: depth-2 If. Test with `CAA_DEEP_IF_DEPTH=4`.
- [ ] **Test:** `Assert-Equal (Get-Findings $mech 'DI').Count 1`.
- [ ] **Implement:** scan code spans; compute max nesting depth of `If(`/`Switch(` by tracking paren depth at each `If`/`Switch` token; if ≥ `$T_DeepIfDepth` → `DI`.

### Task 20: `ND` — near-duplicate formulas

**Prereq:** Task 3. **Severity** Med, **tier** narrative. **Citation:** §2 *Redundancy* (labeled general).

- [ ] **Fixture:** two formulas ≥ 60 chars that are identical except for one literal/spacing (near-dup, ratio ≥ 0.90) — and NOT byte-identical (else XD). Negative: two unrelated long formulas.
- [ ] **Test:** `Assert-Equal (Get-Findings $mech 'ND').Count 1`; assert the exact-duplicate fixture still maps to `XD`, not `ND`.
- [ ] **Implement:** normalize each formula (collapse whitespace, lowercase, replace string-literal contents via tokenizer with a constant token). For each pair within ±15% length and ≥ `$T_NearDupMinLen`, skip exact-equal (XD owns those), compute Levenshtein ratio = `1 - dist/maxlen`; if ≥ `$T_NearDupRatio` → one `ND` finding per cluster. Implement `Get-Levenshtein` as a native DP function.

### Task 21: `MV` — magic values (enumeration-only)

**Prereq:** Task 3. **Severity** Low, **tier** enumeration. **Citation:** §1 *Code readability* (labeled general).

- [ ] **Fixture:** a formula with a hardcoded number (`> 1`), an RGBA/hex, and a non-trivial string literal. Negative: `0`, `1`, `true`/`false`, `Parent.X`.
- [ ] **Test:** assert `MV` count equals the planted magic-value count (document the exact number in the fixture comment).
- [ ] **Implement:** from each formula, collect numeric literals in code spans (exclude `0`,`1`, and common UI constants where listed) + string literals (from `.Strings`) + RGBA/hex/GUID patterns. Emit one `MV` per distinct (value, location). Low — enumeration only.

### Task 22: `RL` — repeated literals across formulas

**Prereq:** Task 21. **Severity** Med, **tier** narrative. **Citation:** §1/§2 (labeled general — "centralize constants").

- [ ] **Fixture:** the same literal (e.g. `"https://contoso.example/api"` or a magic number) appearing in ≥ 3 formulas. Negative: a literal used once.
- [ ] **Test:** `Assert-Equal (Get-Findings $mech 'RL').Count 1` with `CAA_REPEATED_LITERAL_MIN=3`.
- [ ] **Implement:** tally MV literal values across all formulas; any value appearing in ≥ `$T_RepeatedLiteralMin` distinct formulas → one `RL` finding (lists locations; recommend a named formula/constant).

### Task 23: `EV` — environment-specific hardcoding (High)

**Prereq:** Task 3. **Severity** High, **tier** narrative. **Citation:** new §"Environment-specific values" → environment-variables ALM URL.

- [ ] **Fixture:** a string literal that is an absolute URL, a GUID, or a recognizable environment name. Negative: a relative path / plain text.
- [ ] **Test:** assert `EV` count = planted count; severity High.
- [ ] **Implement:** scan `.Strings` for `https?://...`, GUID regex, SharePoint/site URLs, `*.crm*.dynamics.com`, env GUIDs → `EV`. Recommend environment variables / config.

### Task 24: `GS` — god screens

**Prereq:** Task 5. **Severity** Med, **tier** narrative. **Citation:** working-with-large-apps.

- [ ] **Fixture:** rely on overrides — run with `CAA_GOD_SCREEN_CONTROLS=3` so MainScreen (with its planted controls) trips it. Negative: a tiny screen.
- [ ] **Test:** `Invoke-Analyzer -EnvOverrides @{CAA_GOD_SCREEN_CONTROLS='3'}`; assert `GS` fires for MainScreen only.
- [ ] **Implement:** per screen, if `controlCount > $T_GodScreenControls` OR `formulaBytes > $T_GodScreenBytes` → `GS`.

### Task 25: `CT` — deep control-tree nesting

**Prereq:** Task 4, Task 5. **Severity** Low, **tier** enumeration. **Citation:** working-with-large-apps.

- [ ] **Fixture:** reuse the `conOuter>conInner>lblDeep` nesting from Task 4. Run with `CAA_CONTROL_TREE_DEPTH=3`.
- [ ] **Test:** `Assert-Equal (Get-Findings $mech 'CT').Count 1` (the depth-3 `lblDeep`).
- [ ] **Implement:** any control with `depth >= $T_ControlTreeDepth` → `CT`.

### Task 26: `IN` — inconsistent naming

**Severity** Low, **tier** enumeration. **Citation:** §1 *Naming*.

- [ ] **Fixture:** within one control type, mix a prefixed name (`btnSave`) and an unprefixed (`Submit`) so the app shows inconsistency without both being default names. Negative: a consistently-named category.
- [ ] **Test:** assert exactly one `IN` finding describing the mixed convention.
- [ ] **Implement:** for variables (and for controls of the same type), if BOTH convention-following and convention-violating members exist, emit one `IN` finding per category naming the inconsistency. (Distinct from `VP`/`DN`, which flag individual violations.)

### Task 27: `OG` — overuse of globals (lead)

**Prereq:** Task 5. **Bucket:** lead (`L-NN`). **Citation:** §2 *With* / named formulas.

- [ ] **Fixture:** declare > N globals (run with `CAA_GLOBAL_OVERUSE=2`) and/or a global used on a single screen. Negative: few globals.
- [ ] **Test:** assert a lead with `kind='overuse-of-globals'` exists and carries an `L-` id.
- [ ] **Implement:** if distinct global count > `$T_GlobalOveruse`, or a global is read on exactly one screen, emit `New-Lead -Kind 'overuse-of-globals'` (model judges whether context/named-formula fits).

### Task 28: `XC` — tight cross-screen coupling (lead)

**Bucket:** lead. **Citation:** working-with-large-apps.

- [ ] **Fixture:** a formula on `MainScreen` referencing a control that belongs to another screen (e.g. `OtherScreen`'s `lblFoo.Text`). Negative: same-screen reference.
- [ ] **Test:** assert a lead with `kind='cross-screen-coupling'`.
- [ ] **Implement:** build a control→screen map; for each formula, if it references `controlName.prop` where `controlName` belongs to a different screen than the formula's screen → `New-Lead -Kind 'cross-screen-coupling'`.

---

# Phase 5 — Finalization

### Task 29: SKILL.md rewrite (D1/D2/D4/D5/D7)

**Files:** Modify `skills/canvas-app-analyzer/SKILL.md`. **No test** (doc) — fold into review.

- [ ] Rewrite the suppression rule from "no padding/no fabrication" → **"Never fabricate, never omit."** Add the two-tier authoring model: the **script** generates `enumeration.md` + `summary.md` (model embeds the summary block and links `enumeration.md`); the **model** writes only the narrative (High/Medium + high-signal RL/EV/GS) + Orientation + lead judgments.
- [ ] Add Step: after authoring, run `verify-report.ps1 -ReportPath <report> -FindingsPath .analysis/mechanical-findings.json`; if `complete:false`, address each `missing`/`unaddressedLeads` ID, then re-run. Spend tokens only on real gaps.
- [ ] Replace blanket unreferenced-control dismissal with **per-control verdicts** (use the `UR` `verdict` field; report each individually).
- [ ] Backlog: batch the Low long-tail into grouped tasks (one ranked task per group), not per-atom.
- [ ] Keep Orientation + the large-app fan-out fallback note unchanged.
- [ ] Commit: `git commit -m "docs: SKILL.md two-tier authoring + verify-report + per-control verdicts"`

### Task 30: Reference-doc completeness pass (D6)

**Files:** Modify `reference/coding-standards-and-performance.md`.

- [ ] Verify every new detector's `citation` points to a real section; add any missing sections (Components & reuse; Environment-specific values; commented-out-code-vs-comments note). For each new detector with no dedicated MS doc (RL, ND, MV, IN, EV-general), confirm the citation is the general coding-guidelines page **and is labeled** as general guidance. Re-check current MS guidance via Microsoft Docs MCP for any new URL; if a documented behavior has shifted, **flag to the user — do not silently adapt.**
- [ ] Commit: `git commit -m "docs: reference sections + citations for all new detectors (D6)"`

### Task 31: Full-suite green + regenerate examples/ (DoD #9)

**Files:** Modify `examples/FieldServiceApp.analysis.md`, `examples/mechanical-findings.json`, `examples/index.json`.

- [ ] Run the full suite: `powershell -NoProfile -ExecutionPolicy Bypass -File test/run-tests.ps1` → `FAIL=0`.
- [ ] Regenerate the example machine files by running the analyzer on `test/fixtures/FieldServiceApp.msapp` and copying `index.json` + `mechanical-findings.json` into `examples/`. Re-author `examples/FieldServiceApp.analysis.md` to reflect the new structure (narrative + embedded summary + linked enumeration + IDs). Run `verify-report.ps1` on it → `complete:true`.
- [ ] Note expected binary churn in committed `.msapp` fixtures (§7.6) — not an error.
- [ ] Commit: `git commit -m "chore: regenerate examples for two-tier output + IDs (DoD #9)"`

---

## Self-Review (run by the planning author against the brief)

- **D1 two-tier:** narrative (Tasks 9–28 tier='narrative') + enumeration (Task 7). ✔
- **D2 script authors enumeration + summary:** Task 7. ✔
- **D3 stable IDs:** Task 6 + Task 2 ordering; DoD #10 tested in Task 6. ✔
- **D4 verify-report:** Task 8 (complete + incomplete). ✔
- **D5 behavior-aware UR:** Task 16. ✔
- **D6 citations:** folded into each detector + Task 30. ✔
- **D7 triage/backlog:** Task 7 summary + Task 29 backlog batching. ✔
- **D8 test-first golden counts + negatives:** every detector task. ✔
- **D9 scope:** no fan-out; out-of-scope detectors absent. ✔
- **§7.1–7.5 before detectors:** Tasks 1–5, each gating later detectors. ✔
- **DoD #4 (CC), #11 (component+UK), #12 (CC/MC):** Tasks 9, 1+10, 9+18. ✔
- **Detector catalog 3a/3b/leads fully covered:** existing (UV,UC,UD,OS,UR,DN,DS,VP,XD) + new (CC,UK,UP,EH,HC,DB,DC,LF,DI,ND,MV,RL,EV,GS,CT,MC,IN,OG,XC). ✔

**Known risk to watch during execution:** several tests read `index.json`/`enumeration.md` by scanning the temp dir for the newest file — if tests run concurrently this is racy. Keep the runner sequential (it is), or extend `Invoke-Analyzer` to return the output directory path alongside the parsed findings (recommended hardening in Task 1).
