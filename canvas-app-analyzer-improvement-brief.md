# Design Brief: Deepening the Canvas App Analyzer's Analysis Output

> Hand-off brief for a planning/implementing agent. Produced via a structured design interview
> (2026-06-21). Companion to `canvas-app-analyzer-spec.md` (the original v1 spec). This brief
> describes **v-next**: closing the depth gaps in the analysis output without losing readability or
> blowing up token cost.
>
> **Status:** decisions locked, ready to plan & implement.

---

## 1. Problem statement

The shipped skill produces analysis that is **too shallow on two fronts**, confirmed against a real
app run:

1. **Detection gaps — code is not examined deeply enough.**
   - **Commented-out code blocks are a total blind spot.** The script reads every property formula
     into `$formulas` but never scans for `//` or `/* */` tokens, so dead commented code is never
     surfaced for removal.
   - **Controls are not examined for maintainability.** Detection today is limited to default names,
     prefix violations, and *exact* duplicate formulas. There is no detection of long/complex
     formulas, near-duplicates, magic values, god screens, deep nesting, etc. — even though the
     script already parses every control's property formulas (the data is present; the detectors
     are missing). A `deepNesting` trigger flag is computed but **never emitted as a finding**.

2. **Reporting gap — the model summarizes instead of enumerating.**
   - The PowerShell `deterministicFindings[]` loop emits **every** instance it finds (no truncation
     in code), but the model, when authoring the report, presents only "the most egregious" cases.
   - The "no padding / no fabrication" rule (intended to stop *invented* findings) is being misread
     by the model as "be terse / don't enumerate."
   - The unreferenced-control category is **wholesale dismissed** in a single sentence (the example
     report literally says *"all are user-visible… none are dead. No action."*) instead of giving a
     per-control verdict.

**Goal:** the report must present the **full spectrum** of what is found — nothing silently dropped —
while keeping the signal sharp and the token cost bounded. The diagnosis is **both** gaps, but
**detection-led**.

---

## 2. Locked design decisions

### D1 — Two-tier completeness contract
The report has two tiers:
- **Narrative tier (fix-this):** readable write-ups for **High/Medium** findings and high-signal
  maintainability items, plus the Orientation/understanding section. Full detail: severity,
  confidence, precise location, evidence snippet, citation, remediation.
- **Enumeration tier (clean-this-up):** exhaustive tables listing **100% of instances** of every
  category — every unused variable, every default name, every commented block — with ID and
  `file:line`. Framed as bulk cleanup, low individual urgency.

### D2 — The script authors the enumeration tier and the summary; the model authors the narrative
The enumeration tables and the top summary-counts table are **pure data** from
`mechanical-findings.json`. The **script generates them as markdown** (e.g. `.analysis/enumeration.md`
and a summary block). This makes enumeration **complete by construction** — the model cannot drop a
row it never wrote — and removes the long-tail token cost. The model **embeds/links** these tables and
spends its budget only on narrative, orientation, and lead judgment.

### D3 — Stable IDs on every finding and lead
The analyzer stamps a **stable ID** on every `deterministicFinding` and every `lead`
(e.g. `UV-01` unused-var #1, `CC-03` commented-code #3, `L-04` lead #4). IDs are cited in tables and
narrative. This turns completeness-checking into a substring search.

### D4 — Separate, deterministic `verify-report.ps1` (gap-only model spend)
A **new, separate** script (not a flag on the analyzer) reads the finished report `.md`, greps for
every ID from the machine files, and emits a tiny JSON:
```json
{ "complete": false, "missing": ["UV-31"], "unaddressedLeads": ["L-04"] }
```
The model runs it after authoring and **only spends tokens if there is a gap** — and only on the
specific gap. Because the script now generates the enumeration tables (D2), the verifier's real job
is policing the **narrative** and **leads accounting**: every lead must be **reported or
dismissed-with-reason by ID**. This kills blanket dismissal — each unreferenced control needs an
individual, ID'd verdict.

### D5 — Behavior-aware unreferenced-control verdicts (no blanket dismissal)
Replace the name-only reference check. A control is a **strong dead-code candidate** when it is *both*
never referenced by name *and* contributes no behavior: no non-default event handlers, not bound to
data, not visible-by-default. Emit a **per-control verdict with the reason**, so the model reports
each individually rather than dismissing the batch.

### D6 — Per-detector-type citations; reference docs expanded
Citation is required **once per detector type**, not per instance. Enumeration tables cite the
authority once in the table header; narrative findings cite inline. The two reference files gain
**one section per new detector type**, each with its best-available Microsoft Learn URL. Where no
dedicated MS doc exists (repeated literals, tight coupling, near-duplicates), cite the **general
PowerApps coding-guidelines page** and **label it explicitly** as a general maintainability principle.
A detector is not "done" until its reference section + citation exist.

### D7 — Triage: structurally separate "fix-this" from "clean-this-up"
- Summary table stays **category × severity** (script-generated), leading visually with High/Medium;
  the Low long-tail shows as a single count, never an inflated total that drowns a real bug.
- **Narrative = action-required only** (High/Medium + high-signal maintainability: repeated literals,
  env-specific hardcoding, god screens).
- **Enumeration = the cleanup backlog** (every Low instance), clearly framed.
- **Remediation backlog batches the long-tail.** One ranked task per group
  (e.g. *"Delete 30 commented-out blocks (Appendix C) — Low/Confirmed, batch effort"*), not 30 atoms.

### D8 — Test-first with asserted golden counts and negative cases
- Build a **kitchen-sink fixture** (`MaintainabilityKitchenSink.msapp` via `test/build-fixture.ps1`)
  planting a **known count** of every pattern.
- Each detector gets a test asserting **exact expected count + IDs** in `mechanical-findings.json`,
  plus a **negative case** (e.g. a legitimately decorative control that must *not* be flagged dead).
- A test runs `verify-report.ps1` against both a **complete** and a **deliberately-incomplete** report
  and asserts it catches the gap.
- Sequence **test-first** (fixture + expected counts before each detector); use the `tdd` skill.

### D9 — Scope boundaries
- **Orientation/understanding section: unchanged.** Only review depth is in scope.
- **Sub-agent fan-out for large apps: deferred.** Detection and enumeration are deterministic and
  scale freely; only lead-judgment grows with size, and that is bounded and cheap. Keep the existing
  "note fan-out as the scale-up path" fallback.
- **Held out of scope (explicit non-goals for v-next):** unused data-source *columns* (needs schema —
  flag as a known limitation in the report), accessibility checks (`AccessibleLabel`),
  `DelayOutput`/`OnChange` perf patterns, theme/color-constant componentization, format-drift warnings.

---

## 3. Detector catalog

Feasibility tiers reflect the script's line/indent **regex** parser (not a real Power Fx parser):
**Cheap** = formula-text token scan; **Medium** = cross-file/cross-formula reference pass;
**Schema** = needs live connection metadata (out of scope).

### 3a. Dead / unused (existing + new)

| ID prefix | Detector | New? | Feasibility | Severity | Bucket |
| --- | --- | --- | --- | --- | --- |
| UV | Unused variable (set, never read) | existing | Cheap | Low | deterministic |
| UC | Unused collection | existing | Cheap | Low | deterministic |
| UD | Unused data source | existing | Cheap | Low–Med | deterministic |
| OS | Orphan screen | existing | Cheap | Med | deterministic (Potential) |
| UR | Unreferenced control — **behavior-aware verdict (D5)** | revised | Medium | Low | deterministic (Potential) |
| CC | **Commented-out code blocks** (`//`, `/* */`) — count & locate | **new** | Cheap | Low | deterministic |
| UK | **Unused custom components** (defined, never instantiated) | **new** | Medium | Med | deterministic |
| UP | **Unused component custom properties** (defined, never read) | **new** | Medium | Low | deterministic |
| EH | **Empty/stub event handlers** (`OnSelect: false`, blank) | **new** | Cheap | Low | deterministic |
| HC | **Permanently hidden controls** (`Visible = false` literal, never toggled) | **new** | Cheap | Low | deterministic |
| DB | **Dead conditional branches** (`If(false, …)`, `If(true, …)`) | **new** | Cheap | Low | deterministic |
| DC | **Duplicate/redundant controls** (same type + near-identical props) | **new** | Medium | Low | deterministic |
| — | Unused data-source *columns* | **out** | Schema | — | known limitation only |

### 3b. Hard-to-maintain (existing + new)

| ID prefix | Detector | New? | Feasibility | Severity | Bucket |
| --- | --- | --- | --- | --- | --- |
| DN | Default control name | existing | Cheap | Med | deterministic |
| DS | Default screen name | existing | Cheap | Med | deterministic |
| VP | Variable/collection prefix violation | existing | Cheap | Low | deterministic |
| XD | Exact duplicate formula | existing | Cheap | Med | deterministic |
| LF | **Long/complex formula** (over byte/line threshold; wire up `deepNesting`) | **new** | Cheap | Med | deterministic |
| DI | **Deep `If`/`Switch` nesting** (depth ≥ N) | **new** | Cheap-ish | Med | deterministic |
| ND | **Near-duplicate formulas** (normalized similarity) | **new** | Medium | Med | deterministic (tune noise) |
| MV | **Magic values** (numbers, strings, hex/RGBA, GUIDs, URLs, emails) | **new** | Cheap | Low | deterministic (enumeration-only) |
| RL | **Repeated literals across formulas** (same value in N+ places) | **new** | Cheap | Med | deterministic |
| EV | **Environment-specific hardcoding** (URLs, GUIDs, env names) | **new** | Cheap | **High** | deterministic (narrative) |
| GS | **God screens** (control count / formula weight over threshold) | **new** | Cheap | Med | deterministic |
| CT | **Deep control-tree nesting** (containers within containers) | **new** | Cheap-ish | Low | deterministic |
| MC | **Complex formula with no comment** (high complexity + zero `//`) | **new** | Cheap | Low | deterministic |
| IN | **Inconsistent naming** (mixed conventions across the app) | **new** | Medium | Low | deterministic |
| OG | **Overuse of globals** (context/named-formula would fit) | **new** | Judgment | — | **lead** |
| XC | **Tight cross-screen coupling** (control on A references control on B) | **new** | Medium | — | **lead** (model judges) |

**Notes**
- **MV vs RL vs EV:** plain magic values (MV) are Low and live in the enumeration tier only.
  **Repeated literals (RL)** are higher signal ("centralize this") and **env-specific hardcoding (EV)**
  is **High** (breaks on deployment) — both ride in the **narrative**.
- **Leads (OG, XC)** are mechanically flagged but require model judgment; they flow through the
  existing `leads[]` channel and must be addressed-or-dismissed by ID (D4).

### 3c. Thresholds
All thresholds are **named constants at the top of the analyzer script**, documented, conservative
defaults (e.g. formula > ~500 bytes = long; screen > ~40 controls = god screen; `If`/`Switch` depth
≥ 4 = deep). **They must also be overridable** (script param or env var) so tests can trip them with a
small fixture instead of planting 40 controls — see §7.5.

### 3d. Detector semantics — sharpened rules (avoid false positives / self-contradiction)
- **`CC` flags commented-out *code*, not explanatory comments.** The reference doc *encourages* `//`
  and `/* */` comments on complex logic, and **`MC` flags formulas that lack them** — so a naive "count
  every `//`" would penalize good comments and **directly contradict `MC`**. Rule: `CC` flags only
  lines whose commented content is itself a statement/formula (looks like code), never explanatory
  prose. `CC` and `MC` must be tested together on the same fixture to prove they don't fight.
- **`EH` targets stub handlers (`OnSelect: =false`), not blank ones.** The parser drops empty-text
  properties (`analyze-canvas.ps1:343`), so a truly blank `OnSelect:` produces no record and is
  invisible. Scope `EH` to the stub form; plant `=false` in the fixture.
- **`CC` vs `EV`/`MV` have opposite string-literal needs** — see the shared tokenizer in §7.3.

---

## 3.5 Parser-infrastructure prerequisites (build these FIRST)

A sanity check of the detectors against the existing `analyze-canvas.ps1` parser (line/indent regex,
not a real Power Fx parser) and `test/build-fixture.ps1` surfaced infrastructure work that several
detectors **depend on**. These are not detectors; they are enabling changes that must be **implemented
and tested before** the detectors that ride on them, or the test-first sequencing stalls.

### §7.1 — Fix component classification (blocks `UK`, `UP`)
`analyze-canvas.ps1:267` classifies a file as a component only if its path matches `[\\/]Component[\\/]`
(singular) or its filename contains `Component`:
```powershell
$isComponent = ($f.FullName -imatch '[\\/]Component[\\/]') -or ($f.Name -imatch 'Component')
```
Real Power Apps source uses `Src\Components\` (**plural**), and component files are usually named for
the component (e.g. `cmpHeader.pa.yaml`) — matching **neither** condition. Today components are likely
**mis-classified as screens**, so `UK`/`UP` have no reliable basis. **Verify the current on-disk
component folder/file layout** (Microsoft Docs MCP / a real export) and fix the classification before
implementing `UK`/`UP`. This fails *silently* (analyzer still runs) — high priority.

### §7.2 — Deterministic ordering for stable IDs (D3 correctness)
Variables/collections are built from **hashtables** (`$globals`, `$contexts`, `$collections`,
`analyze-canvas.ps1:388–416`) and emitted via `.Keys`, whose order PowerShell does **not** guarantee;
controls come from `Get-ChildItem` order (also not guaranteed). If IDs are assigned by iteration order,
`UV-03` may point to a different item on the next run, **breaking `verify-report.ps1` reconciliation**.
**Sort every finding collection by a deterministic key (name, then `file:line`) before stamping IDs.**
Data sources already do this (`Sort-Object name -Unique`, line 383) — apply the same pattern
everywhere. Also fails silently — high priority.

### §7.3 — Shared formula tokenizer (enables `CC`, `MV`, `EV`, and de-noises them)
`CC` must scan **code outside string literals** (so it ignores `https://` and slashes inside strings),
while `MV`/`EV` must scan **inside string literals** (URLs, GUIDs, env names) — opposite needs. Build
**one small helper** that splits a formula into string-literal spans vs. code spans, and have the
relevant detectors consume it. Without it, `CC` false-matches URLs and `MV`/`EV` miss string content.

### §7.4 — Persist control nesting depth / ancestor chain (enables `CT`)
The parser keeps an indent stack during parse but records controls **flat** (`$controls` has `screen`,
no parent/depth), and the stack pushes non-control nodes (`Children:`, `Properties:`) so stack depth ≠
control depth. Persist each control's **control-ancestor chain** (count only control ancestors) so
`CT` can flag container-within-container nesting.

### §7.5 — Make thresholds overridable (testability for `GS`, `LF`, `DI`, `CT`)
Named threshold constants (§3c) must be overridable via script param or env var so tests can trip
`GS`/`LF`/`DI`/`CT` with a small fixture rather than planting 40 controls.

### §7.6 — `build-fixture.ps1` regenerates ALL fixtures (expected churn)
`test/build-fixture.ps1:11` wipes and rebuilds the entire `fixtures/` dir. Adding the kitchen-sink
fixture means the existing fixtures (`FieldServiceApp.msapp`, `SampleSolution.zip`, multi/no-app/legacy)
get rebuilt too, churning committed `.msapp` bytes (zip timestamps) and the committed sample outputs
under `examples/` and `canvas-analysis/`. Expect binary git noise; regenerate `examples/` deliberately
(DoD #9) and don't treat the byte diffs as errors.

### Suggested implementation order
1. §7.1 component fix + §7.2 deterministic ordering (silent-failure infrastructure, test first).
2. §7.3 tokenizer + §7.4 control-depth + §7.5 overridable thresholds.
3. ID stamping (D3) + script-generated enumeration/summary (D2) + `verify-report.ps1` (D4).
4. Detectors, test-first per §3, each after its prerequisite above is green.
5. Regenerate `examples/`; tighten `SKILL.md`; expand reference docs.

## 4. Files to change / create

| File | Change |
| --- | --- |
| `skills/canvas-app-analyzer/scripts/analyze-canvas.ps1` | Add all 3a/3b deterministic detectors + leads; stamp stable IDs; emit per-category total counts; **generate `enumeration.md` + summary block**; named threshold constants. |
| `skills/canvas-app-analyzer/scripts/verify-report.ps1` | **New.** Deterministic report↔findings reconciliation; emits gap JSON (D4). |
| `skills/canvas-app-analyzer/SKILL.md` | Rewrite suppression rules ("never fabricate, never omit"); two-tier authoring instructions; model writes narrative only + embeds script tables; per-control verdicts (no blanket dismissal); run `verify-report.ps1` and fix gaps; batch long-tail in backlog. |
| `skills/canvas-app-analyzer/reference/coding-standards-and-performance.md` | One section per new maintainability/dead-code detector + citation (D6). Note: comments, formula-formatting, and explicit-column-selection guidance already exist here — wire detectors to them. |
| `skills/canvas-app-analyzer/reference/delegation.md` | No change expected (delegation unchanged). |
| `test/build-fixture.ps1` + `test/fixtures/MaintainabilityKitchenSink.msapp` | **New fixture** planting known counts of every pattern (D8). |
| `test/` (test runner) | Golden-count + negative-case assertions per detector; `verify-report.ps1` complete/incomplete tests. |
| `examples/FieldServiceApp.analysis.md`, `examples/mechanical-findings.json` | Regenerate to reflect the new structure (narrative + script-generated enumeration + IDs). |

---

## 5. Acceptance criteria

1. Running the analyzer on the kitchen-sink fixture produces, for **every** detector, the **exact
   asserted count** of findings with stable IDs (D8).
2. The report's **enumeration tier lists 100% of deterministic findings**; row count per category
   equals the script's emitted total (guaranteed by D2, checked by D4).
3. `verify-report.ps1` returns `complete: true` for a correct report and identifies the exact missing
   IDs for a deliberately-incomplete one.
4. Commented-out code blocks are detected and counted (the original blind spot).
5. Unreferenced controls receive **individual, reasoned verdicts** — no blanket dismissal anywhere.
6. The narrative leads with High/Medium and high-signal maintainability; the Low long-tail does not
   visually dominate the summary; the remediation backlog batches long-tail cleanup into grouped tasks.
7. Every new finding type cites a reference-doc section (specific MS URL or labeled general guidance).
8. Orientation section behavior is unchanged; no sub-agent fan-out introduced.
9. **IDs are stable across runs** on unchanged input — running the analyzer twice on the kitchen-sink
   fixture produces byte-identical IDs (proves §7.2 ordering). A test asserts this.
10. **Components are correctly classified** — the kitchen-sink fixture's component file is recognized as
    a component (not a screen), and an unused component is flagged by `UK` (proves §7.1).
11. **`CC` and `MC` do not contradict** — on a fixture control with both commented-out code and a
    legitimate explanatory comment, `CC` flags only the former and `MC` does not fire on the commented
    formula (proves §3d).

---

## 6. Open implementation details (delegated to the planning agent)

- Exact ID scheme format (prefix + zero-padded index vs. content hash) — must be **stable across runs**
  on unchanged input.
- Near-duplicate (ND) similarity metric and threshold (normalize whitespace/case, then token or
  Levenshtein ratio) — tune against the kitchen-sink fixture to balance recall vs. noise.
- Component-instantiation detection (UK/UP): how to resolve a component definition file against its
  usages across screen files with the regex parser.
- Whether the script embeds enumeration tables inline in the report or the model links to a sibling
  `enumeration.md` (D2 allows either; pick for readability + clickable citations).
