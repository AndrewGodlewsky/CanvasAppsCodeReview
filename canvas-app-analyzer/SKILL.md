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

## How it works (hybrid: script does mechanics, you do judgment)

A PowerShell helper does the deterministic work (unzip, inventory, default-name / unused /
duplicate detection) and emits machine files. **You** read those, apply judgment using the two
bundled reference files, and author the report. The script gives you a complete, line-anchored
worklist so you never have to scan every YAML file by hand.

## Step 1 - Run the helper script

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

When `status` is `ok`, the JSON tells you the `outputDir` and the relative paths under it
(`.analysis/index.json`, `.analysis/index.md`, `.analysis/mechanical-findings.json`, `src/`, and
the `report` filename to write).

## Step 2 - Orient yourself

Read, in order:
1. `<outputDir>/.analysis/index.json` - the full inventory (app meta, screens with weight +
   trigger flags, controls, data sources + connector type, variables, collections, navigation,
   start screen).
2. `<outputDir>/.analysis/index.md` - the same as a quick human digest (optional once you have the JSON).
3. `<outputDir>/.analysis/mechanical-findings.json` - `deterministicFindings[]` (already
   confirmed, ready to report) and `leads[]` (candidates **you must judge**).

## Step 3 - Load the authority references (cite them in every finding)

Read both bundled files and keep them open as you write:
- `reference/delegation.md` - authority for **Delegation & data efficiency**.
- `reference/coding-standards-and-performance.md` - authority for the other five categories.

**Every finding you report must cite the specific bundled guidance (and its embedded Microsoft
Learn URL) it rests on.** This matters: you are telling a team their inherited app is "wrong," so
findings must stand on a cited authority, not bare model opinion.

## Step 4 - Targeted reads (keep large apps in context)

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

## Step 5 - Judge each lead

For every entry in `leads[]`, use the references to decide if it's a real finding, then assign
**Severity** and **Confidence**:

- **Delegation leads:** resolve the data source's connector type (it's in `index.json.dataSources`)
  and check the function + predicate against the matrix in `delegation.md`. **Skip** anything whose
  source is a collection, context variable, or static Excel (no delegation needed - false positive).
  **Every delegation finding you keep is tagged `Potential - verify row count`** (the source has no
  row counts; a non-delegable query is harmless on a small list and broken on a large one). Phrase
  impact as: "if the source can exceed 500/2,000 rows, results are silently truncated."
- **Performance leads** (heavy `App.OnStart`, `Navigate` in OnStart, N+1, `Concurrent`
  opportunities): confirm against `coding-standards-and-performance.md`. `Navigate`-in-OnStart is
  Confirmed; OnStart->Formulas and N+1 are high-value; Concurrent only when calls are independent.
- **Error-handling leads** (mutation without `IfError`/`Errors()`): judge risk - some operations
  are low-risk; tag confidence accordingly.

**Confidence rule of thumb:** `Confirmed` = provable from the source alone (default names, unused
data, duplicates, `Navigate` in OnStart). `Potential` = impact depends on a runtime fact the source
doesn't contain (row counts for delegation; whether an unreferenced control is purely decorative;
whether an orphan screen is reached via a variable).

**Severity rule of thumb:** `High` = silently wrong results or broken/badly-slow behavior;
`Medium` = real perf or maintainability cost; `Low` = minor cleanup. Most `deterministicFindings`
already carry sensible severities - keep them unless you have a reason to adjust.

## Step 6 - Write the report

Write to `<outputDir>/<report>` (e.g. `<outputDir>/FieldServiceApp.analysis.md`) with **exactly**
this structure:

### 1. Summary table (top)
A counts table: rows = the six categories, columns = High / Medium / Low (and a Confirmed vs
Potential split if helpful). For fast triage.

### 2. Orientation
A newcomer should be able to read this top-to-bottom and understand the app:
- **Purpose** (infer from screens, data, labels).
- **Screen inventory** (from `index.json`).
- **Navigation map** (from `navigation[]` - render as a simple list or arrows).
- **Data sources & connectors** (from `dataSources[]`).
- **Components** (if any) and **key dependencies**.

### 3. Findings - organized by the six categories (in this order)
1. **Delegation & data efficiency**
2. **Performance**
3. **Redundancy & reuse**
4. **Maintainability & naming**
5. **Dead / unused**
6. **Error handling & resilience**

Each finding carries **all** of:
- **Severity** (High / Medium / Low)
- **Confidence** (Confirmed / Potential - needs verification)
- **Precise location** - screen -> control -> property + the `src/...pa.yaml` path (and line).
- **Evidence** - the offending formula snippet (from the real source you read).
- **Why it matters** - with a **citation** to the bundled reference (name its section + the MS URL).
- **Recommended remediation.**

### 4. Remediation Backlog (closing)
Ranked, de-duplicated action items by **severity x confidence x rough effort**. Confirmed-High
floats to the top; Potential items rank lower and are clearly flagged so nobody implements a fix
for a problem that might not exist. Each item references the finding(s) it resolves. **This section
is the explicit hand-off to the downstream planning/implementing agent.**

## Hard rules (do not violate)

- **Read-only.** No edits, no repacking, no `pac canvas pack/unpack`.
- **No padding, no fabrication.** If a category is clean, write "**No issues found.**" - never
  invent weak findings to fill it out.
- **Every delegation finding is `Potential - verify row count`.** No exceptions.
- **Every finding cites a bundled reference** (section + embedded Microsoft Learn URL).
- **Don't flag delegation on collections / context variables / static Excel** (no delegation needed).
- The persisted `src/` folder and the report stay on disk - they are lasting assets and the
  report's location citations must remain clickable. Don't delete them.
