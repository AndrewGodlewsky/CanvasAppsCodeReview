---
name: canvas-app-analyzer
description: >-
  Read-only analysis of a Power Apps Canvas app from a solution .zip or .msapp - extract the
  .pa.yaml source, inventory screens/controls/data sources, and produce a structured Markdown
  review report covering delegation, performance, redundancy, maintainability, dead code, and
  error handling. Use when the user wants to understand, review, audit, or hand off an inherited
  Canvas app. Invoke with the path to the solution .zip (or bare .msapp) as the argument.
---

# Canvas App Analyzer

You analyze an inherited **Power Apps Canvas app** for a team that has just taken ownership of it.
Two goals, comprehension first: (a) help them **understand** how the app works, and (b) **review**
it for redundancy, efficiency, and maintainability. You produce **one Markdown report per app**
that also serves as a hand-off to a downstream planning/implementing agent.

**You are strictly read-only.** Never modify the app, never write back into a `.msapp`, never run
`pac canvas pack`/`unpack`. You only read extracted `\Src\*.pa.yaml` source.

## How it works (two-tier: script does mechanics + enumeration, you do judgment + narrative)

The PowerShell helper does all deterministic work: unzip, inventory, detection, and — critically —
it **authors the exhaustive enumeration tables and the summary counts block itself**. You are
responsible for the narrative: Orientation, write-ups for High/Medium findings and high-signal
maintainability items, and judgment calls on leads. The script guarantees completeness of
enumeration; the model guarantees completeness of narrative coverage.

## Step 1 — Run the helper script

The user gives you a path to a solution `.zip` (or a bare `.msapp`). Run the script that ships
beside this file at `scripts/analyze-canvas.ps1` (adjust the leading path to wherever the skill is
installed):

```
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts/analyze-canvas.ps1" -Path "<USER_ZIP_PATH>"
```

The script prints a single JSON status object to stdout. **Branch on its `status` field:**

| `status` | What to do |
| --- | --- |
| `ok` | Proceed to Step 2. |
| `no-canvas-app` | **STOP.** Tell the user verbatim: no Canvas app was found in the archive (it may contain only flows/tables). Nothing to analyze. |
| `legacy-no-src` | **STOP.** Relay the message: the app predates the YAML source format. Instruct: open it in Power Apps Studio -> File -> Save as -> This computer, download the new `.msapp`, and re-run. Do **not** attempt to analyze the unstable `.json`. |
| `multiple-apps` | Show the user the `apps[]` list and **ask which one** to analyze. Then re-run the script adding `-AppName "<chosen name>"`. |
| `app-not-found` | The `-AppName` didn't match. Re-show `apps[]` and ask again. |
| `error` | Relay the `message` (and `detail` if present). Do not fabricate a report. |

When `status` is `ok`, the JSON tells you the `outputDir` and all relative paths under it:

| Key in `files` | Path | Authored by |
| --- | --- | --- |
| `index` | `.analysis/index.json` | Script |
| `digest` | `.analysis/index.md` | Script |
| `mechanicalFindings` | `.analysis/mechanical-findings.json` | Script |
| `enumeration` | `.analysis/enumeration.md` | **Script** (exhaustive tables — do NOT paste into report) |
| `summary` | `.analysis/summary.md` | **Script** (counts block — embed at top of report) |
| `src` | `src/` | Script (persisted source) |
| `report` | `<AppName>.analysis.md` | **You** (the narrative report) |

## Step 2 — Orient yourself

Read, in order:
1. `<outputDir>/.analysis/index.json` — the full inventory (app meta, screens with weight +
   trigger flags, controls, data sources + connector type, variables, collections, navigation,
   start screen).
2. `<outputDir>/.analysis/index.md` — the same as a quick human digest (optional once you have the JSON).
3. `<outputDir>/.analysis/mechanical-findings.json` — `deterministicFindings[]` (already
   confirmed, ready to report) and `leads[]` (candidates **you must judge**).
4. `<outputDir>/.analysis/summary.md` — the script-authored counts block. **You will embed this
   verbatim** at the top of your report (do not rewrite or paraphrase it).
5. `<outputDir>/.analysis/enumeration.md` — the script-authored exhaustive tables (one per finding
   type, every deterministic finding as a row). **Do not paste these tables into the narrative
   report.** Instead, add a single link: `[Full cleanup backlog → enumeration.md](.analysis/enumeration.md)`.

## Step 3 — Load the authority references (cite them in every finding)

Read both bundled files and keep them open as you write:
- `reference/delegation.md` — authority for **Delegation & data efficiency**.
- `reference/coding-standards-and-performance.md` — authority for the other five categories.

**Every finding you report must cite the specific bundled guidance (and its embedded Microsoft
Learn URL) it rests on.** This matters: you are telling a team their inherited app is "wrong," so
findings must stand on a cited authority, not bare model opinion.

## Step 4 — Targeted reads (keep large apps in context)

Do **not** read every `.pa.yaml`. Work from the leads and the per-screen `triggers`/`weight` in
`index.json`:
- For each lead, open only the cited `file` at the cited `line` to read the real formula and
  confirm/reject it.
- Read a full screen file only when its `triggers` flag a category you're investigating and the
  leads alone don't give you enough context.
- Process screens heaviest-first (by `formulaBytes`).

> **Large-app extension (not in v1):** if the app exceeds ~25 screens, note in the report that a
> sub-agent fan-out (one agent per screen + a reconciliation pass) would be the scale-up path.
> Still complete the analysis in weight order using targeted reads.

## Step 5 — Judge each lead

For every entry in `leads[]`, use the references to decide if it's a real finding, then assign
**Severity** and **Confidence**:

- **Delegation leads:** resolve the data source's connector type (it's in `index.json.dataSources`)
  and check the function + predicate against the matrix in `delegation.md`. **Skip** anything whose
  source is a collection, context variable, or static Excel (no delegation needed — false positive).
  **Every delegation finding you keep is tagged `Potential — verify row count`** (the source has no
  row counts; a non-delegable query is harmless on a small list and broken on a large one). Phrase
  impact as: "if the source can exceed 500/2,000 rows, results are silently truncated."
- **Performance leads** (heavy `App.OnStart`, `Navigate` in OnStart, N+1, `Concurrent`
  opportunities): confirm against `coding-standards-and-performance.md`. `Navigate`-in-OnStart is
  Confirmed; OnStart->Formulas and N+1 are high-value; Concurrent only when calls are independent.
- **Error-handling leads** (mutation without `IfError`/`Errors()`): judge risk — some operations
  are low-risk; tag confidence accordingly.

**Confidence rule of thumb:** `Confirmed` = provable from the source alone (default names, unused
data, duplicates, `Navigate` in OnStart). `Potential` = impact depends on a runtime fact the source
doesn't contain (row counts for delegation; whether an unreferenced control is purely decorative;
whether an orphan screen is reached via a variable).

**Severity rule of thumb:** `High` = silently wrong results or broken/badly-slow behavior;
`Medium` = real perf or maintainability cost; `Low` = minor cleanup. Most `deterministicFindings`
already carry sensible severities — keep them unless you have a reason to adjust.

## Step 6 — Write the report (narrative only)

Write to `<outputDir>/<report>` (e.g. `<outputDir>/FieldServiceApp.analysis.md`) with **exactly**
this structure:

### 1. Summary (top) — embed the script-generated block

Paste the contents of `.analysis/summary.md` verbatim here. Do not alter or rewrite it.
Add immediately below it a link to the enumeration:

```
[Full cleanup backlog → enumeration.md](.analysis/enumeration.md)
```

This single link is the complete Low-severity backlog. Do not reproduce the enumeration tables
inline.

### 2. Orientation

A newcomer should be able to read this top-to-bottom and understand the app:
- **Purpose** (infer from screens, data, labels).
- **Screen inventory** (from `index.json`).
- **Navigation map** (from `navigation[]` — render as a simple list or arrows).
- **Data sources & connectors** (from `dataSources[]`).
- **Components** (if any) and **key dependencies**.

### 3. Findings — organized by the six categories (in this order)

1. **Delegation & data efficiency**
2. **Performance**
3. **Redundancy & reuse**
4. **Maintainability & naming**
5. **Dead / unused**
6. **Error handling & resilience**

**What belongs in the narrative:** Write up every `High` and `Medium` deterministic finding using
its assigned finding ID (e.g. `UV-01`, `CC-03`). Also write up the following high-signal
maintainability findings regardless of severity: repeated literals (`RL-*`), environment-specific
hardcoding (`EV-*`, High), and god-screens (`GS-*`). For all other Low findings, the enumeration
tables in `enumeration.md` are the record — do not copy them into the narrative.

Each narrative finding entry carries **all** of:
- **ID** from `mechanical-findings.json` (e.g. `**UV-01**`)
- **Severity** (High / Medium / Low)
- **Confidence** (Confirmed / Potential — needs verification)
- **Precise location** — screen → control → property + the `src/...pa.yaml` path (and line)
- **Evidence** — the offending formula snippet (from the real source you read)
- **Why it matters** — with a **citation** to the bundled reference (name its section + the MS URL)
- **Recommended remediation**

**Per-control UR verdicts (unreferenced controls):** Each `UR-*` finding in `mechanical-findings.json`
carries a `verdict` field with one of two values:
- `strong-dead-candidate` — the control has no non-default event handlers, is not data-bound, and
  is permanently hidden. Report each such control individually with a clear recommendation to remove.
- `likely-decorative-or-layout` — the control has signals suggesting it may be intentional (event
  handlers, data binding, or visible by default). Report each individually with its reason and a
  recommendation to verify with the original developer before removing.

**Do not dismiss unreferenced controls as a batch.** Every `UR-*` finding must be reported
individually using the `verdict` field. There is no blanket "all are fine."

### 4. Remediation Backlog (closing)

Ranked, de-duplicated action items by **severity × confidence × rough effort**. Confirmed-High
floats to the top; Potential items rank lower and are clearly flagged so nobody implements a fix
for a problem that might not exist. Each item references the finding ID(s) it resolves.

**Batch the Low long-tail:** do NOT list one backlog item per Low finding instance. Instead, group
each Low category into a single ranked task, e.g.:

> Delete N commented-out blocks (see enumeration.md, CC-\*) — Low / batch effort
> Remove N permanently hidden controls (see enumeration.md, HC-\*) — Low / batch effort

One ranked task per Low category group. The High/Medium items lead; the Low long-tail must not
visually dominate this section.

**This section is the explicit hand-off to the downstream planning/implementing agent.**

## Step 7 — Verify the report

After authoring the report, run `verify-report.ps1` against it:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts/verify-report.ps1" `
  -ReportPath "<outputDir>/<AppName>.analysis.md" `
  -FindingsPath "<outputDir>/.analysis/mechanical-findings.json"
```

The script prints:

```json
{ "complete": <bool>, "missing": [<ids>], "unaddressedLeads": [<ids>] }
```

If `complete` is `false`:
- For each ID in `missing`: it is a High/Medium deterministic finding absent from your narrative.
  Add it to the relevant category section. Spend tokens only on real gaps — do not pad.
- For each ID in `unaddressedLeads`: it is a lead you have not mentioned. Either report it as a
  finding (with your judgment) or explicitly dismiss it with a one-line reason citing the ID.
- Re-run `verify-report.ps1` after each revision until `complete` is `true`.

Low findings are covered by `enumeration.md` and are **not** checked by the verifier. Do not add
Low items to the narrative just to silence the verifier.

## Hard rules (do not violate)

- **Read-only.** No edits, no repacking, no `pac canvas pack/unpack`.
- **Never fabricate, never omit.** Never invent findings that are not in `mechanical-findings.json`
  or supported by your own confirmed reads of the source. And never silently drop a category or
  omit a required finding. Completeness is guaranteed by the script (enumeration.md); the model's
  job is accurate narrative coverage of High/Medium + UR verdicts + leads.
- **Every delegation finding is `Potential — verify row count`.** No exceptions.
- **Every finding cites a bundled reference** (section + embedded Microsoft Learn URL).
- **Don't flag delegation on collections / context variables / static Excel** (no delegation needed).
- **No blanket UR dismissal.** Report each unreferenced control individually with its `verdict`.
- The persisted `src/` folder and the report stay on disk — they are lasting assets and the
  report's location citations must remain clickable. Don't delete them.
