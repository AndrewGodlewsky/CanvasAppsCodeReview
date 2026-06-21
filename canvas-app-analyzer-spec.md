# Skill Spec: Canvas App Analyzer (for GitHub Copilot CLI)

> Hand-off brief for a planning/implementing agent. Produced via a structured design interview.
> Status: ready to plan & implement. v1 scope is single-agent; extension points noted at the end.

## Purpose
A read-only skill that helps a team **taking over unfamiliar (but recently-built) Power Apps Canvas apps** both (a) **understand** how an app works and (b) **review** it for redundancy, efficiency, and maintainability — producing one structured Markdown report per app that doubles as a hand-off to a downstream planning/implementing agent.

The team is "new" to these apps (inherited ownership), not the apps being old — so **comprehension is a first-class goal**, not just linting.

## Platform & format
- **Target:** GitHub **Copilot CLI**, authored as a `SKILL.md` + bundled assets, invoked from the **VS Code integrated terminal** (team stays in VS Code, skill gets real shell/filesystem access).
- **Single-agent** execution for v1 (no sub-agent dependency — see Extension Points).

## Input & extraction pipeline (uses *current* MS guidance — not deprecated tooling)
1. **Input:** a solution **`.zip`** (also accept a bare `.msapp`, since it's the same archive format).
2. **Unzip the solution** (`Expand-Archive`), then **recursively search the extracted tree for `*.msapp`** — do **not** assume a fixed path. The `.msapp` layout differs by export type: a raw solution export zip places them differently (often flatter, near the root) than a `pac solution unpack` / SolutionPackager extract (which uses `canvasapps/<schema-name>/`). A recursive `*.msapp` search is robust to both and keeps the plain-`Expand-Archive`, no-`pac` path intact.
3. **A `.msapp` is itself a ZIP** — extract it directly. **Do NOT use `pac canvas unpack`** (deprecated) or the retired `.fx.yaml` format.
4. **Read only `\Src\*.pa.yaml`** — the active source format (`App.pa.yaml`, one `[Screen].pa.yaml` per screen, `\Src\Component\*.pa.yaml`). Ignore sibling `.json` (explicitly unstable per MS docs).
5. **App-count handling:** if **multiple** Canvas apps are found, list them and **prompt the user to choose which one** to analyze; if **exactly one**, proceed; if **none** (e.g., a solution of only flows/tables), **stop with a clear message** ("no Canvas app found in this zip").
6. **Legacy-format preflight:** if an extracted `.msapp` has **no `\Src\*.pa.yaml`**, **stop with an actionable message** — "this app predates the YAML source format; open it in Power Apps Studio → File → Save as → This computer to regenerate, then re-run." No fallback to unstable `.json`.

### Reference: current Microsoft guidance (verify periodically — this area changes)
- `pac canvas` reference (note pack/unpack deprecation): https://learn.microsoft.com/power-platform/developer/cli/reference/canvas
- View source code files for canvas apps (`\Src\*.pa.yaml`, legacy resave): https://learn.microsoft.com/power-apps/maker/canvas-apps/power-apps-yaml
- Power Platform Git Integration (modern source-control path): https://learn.microsoft.com/power-platform/alm/git-integration/overview
- `pac solution unpack` (alternative cleaner solution extract): https://learn.microsoft.com/power-platform/developer/cli/reference/solution

## Architecture: hybrid (PowerShell script + model judgment)
- **PowerShell helper script** (native `Expand-Archive`, no extra deps) does the **deterministic, mechanical** work:
  - unzip solution + `.msapp`, enumerate apps/screens/controls/data sources
  - compute cut-and-dried findings: **default control names** (e.g. `Gallery3`), **unused variables/controls** (reference counting), **exact duplicate formulas**
  - emit a compact **index** + a **mechanical-findings** file so large apps don't overflow context
- **Model** does the **judgment** work guided by the index: orientation narrative, delegation analysis, redundancy/componentization calls, severity, report authoring.

Rationale: deterministic checks are more accurate and cheaper as code than as LLM pattern-matching across many files; the index keeps large apps within context; runs are reproducible.

## On-disk layout (persisted, citations navigable)
```
./canvas-analysis/<AppName>/
  src/                       # persisted extracted \Src\*.pa.yaml (browsable + citation targets)
  <AppName>.analysis.md      # the report
```
Nothing auto-deleted — the extracted source is a lasting asset for the new owners, and the report's location citations stay clickable.

## Bundled reference material (inside the skill) — ALREADY AUTHORED & VETTED
The authority content findings cite is **already written and grounded in current Microsoft Learn docs**
(verified 2026-06). The implementing agent **ships these two files as-is** into the skill (e.g., under a
`reference/` folder); it does **not** need to author them — only to wire the skill to read them.

1. **`reference/delegation.md`** — authority for all *Delegation & data efficiency* findings:
   - the 500/2,000-record mechanic and why non-delegable = silent wrong results
   - the delegable set vs the always-local non-delegable functions
   - a **per-connector matrix**: full SQL Server table (verbatim from docs) + gotchas, SharePoint traps,
     Dataverse (broadest — the "move here to fix" target), and the collections/variables/static-Excel
     "no delegation needed" rule (prevents false positives)
   - a detection recipe from `.pa.yaml`, including **resolve the data source type first**
   - **Decision baked in:** every delegation finding is tagged **Potential — verify row count** (the
     source has no counts); the pattern can be proven, the impact can't.

2. **`reference/coding-standards-and-performance.md`** — authority for the other five categories:
   - naming (control-prefix table, `loc`/`gbl`/`col`/`scp` variable prefixes, screen-name rules,
     cross-screen uniqueness/suffix rule)
   - performance (`App.OnStart`->`App.Formulas` ~80% win, `Navigate`-in-OnStart->`App.StartScreen`,
     Select N+1, `Concurrent`, 256k-char long-formula / copy-paste duplication, `With`)
   - dead/unused reference-counting checklist; error handling (`IfError`/`Errors()`)
   - note that findings mirror Microsoft's own Power CAT Toolkit / App Checker

- Each file embeds its **source URLs** for citation + a **"re-verify periodically"** maintenance note.
- **Scope boundary (intentional):** accessibility and responsive-layout checks are **excluded** — they
  are not among the agreed six categories. Revisit only if the six categories are expanded.
- Rationale for bundling: reproducibility, speed, and portability (Copilot CLI may lack the Microsoft
  Docs MCP that other environments expose).

## Output report structure

**1. Summary table** (top) — finding counts by severity x category, for fast triage.

**2. Orientation** — purpose, screen inventory, **navigation map** (derived from `Navigate`/`Back` calls), data sources/connectors, components, key dependencies. Goal: a newcomer can read top-to-bottom and understand the app.

**3. Findings** — organized by the **six categories**:
1. **Delegation & data efficiency** — non-delegable `Filter`/`Sort`/`LookUp`/`Search` against large data sources.
2. **Performance** — heavy `App.OnStart`, uncached repeat queries, `ForAll` misuse, `Concurrent` opportunities.
3. **Redundancy & reuse** — duplicated logic/controls/screens that should be **named formulas** or **components**.
4. **Maintainability & naming** — default control names, magic strings/hardcoded IDs, deeply nested formulas, missing comments.
5. **Dead / unused** — unused variables, controls never referenced, data sources connected but unused, screens never navigated to.
6. **Error handling & resilience** — missing `IfError`/`Errors()` handling, unhandled patch failures.

Each finding carries:
- **Severity** (High / Medium / Low)
- **Confidence** (**Confirmed** vs **Potential — needs verification**)
- **Precise location** (screen -> control -> property + `.pa.yaml` file path)
- **Evidence** (the offending formula snippet)
- **Why it matters** (+ citation to bundled MS guidance)
- **Recommended remediation**

Rules:
- **No padding / no fabrication** — clean categories explicitly say "no issues found" rather than inventing weak ones.
- **Delegation findings are flagged Potential** with "impact depends on row count — verify data source size" (the `.pa.yaml` source contains no row counts, only connector type from `\DataSources`).

**4. Remediation Backlog** (closing) — ranked, de-duplicated action items by **severity x confidence x rough effort**; each item references the finding(s) it resolves. Confirmed-High floats to the top; Potential items rank lower and are flagged so nobody implements a fix for a problem that might not exist. **This section is the explicit hand-off to the planning/implementing agent.**

## Boundaries
- **Strictly read-only.** The skill never modifies the app. (Round-tripping `.pa.yaml` back into a working `.msapp` relies on the deprecated `pac canvas pack` and would be fragile.)
- Findings cite an authority (bundled MS guidance), not bare model opinion — important when asserting an inherited app is "wrong."

## Extension points (documented, NOT built in v1)
- **Sub-agent fan-out** for unusually large apps (> ~25 screens): one analysis agent per screen, each given the shared delegation matrix + a fixed severity rubric, followed by a **mandatory reconciliation pass** (normalize severity, dedupe cross-screen findings). Gate on Copilot CLI sub-agent support.
- **JSON findings sidecar** (same data as the report, structured) if a future downstream agent wants fully deterministic input.

## Key design decisions (rationale captured so the implementing agent doesn't re-litigate)
1. **Copilot CLI from the VS Code terminal** — team lives in VS Code but the task needs real shell/filesystem for unzip + multi-file crawl.
2. **Current extraction method** — `.msapp`/`.zip` are plain archives extracted with `Expand-Archive`; **recursively search for `*.msapp`** rather than assuming a fixed path (raw-export vs `pac solution unpack` layouts differ). The old `pac canvas unpack` + `.fx.yaml` path is deprecated/retired; `pac` is not required.
3. **Multiple apps -> prompt to choose** — don't guess which app the user means.
4. **Legacy preflight fails loud** — no analysis of unstable `.json`; tell the user to resave in Studio.
5. **Orientation + Findings** — comprehension leads because the team's core problem is not understanding inherited apps.
6. **Six fixed finding categories** — reproducible, comprehensive, grounded in MS guidance.
7. **Read-only** — diagnosis tool, not an editor; feeds a separate fix agent.
8. **Per-app persisted folder** — navigable citations + lasting source copy.
9. **Bundled reference + delegation matrix** — reproducible, fast, portable.
10. **Confidence tags + no padding** — trust for a team that can't easily verify claims.
11. **Hybrid script + model** — deterministic checks as code, judgment as model.
12. **Single agent v1; sub-agents documented as conditional extension** — portability to Copilot CLI is the dominant constraint.
13. **Prioritized Remediation Backlog** — the bridge to the downstream planning/implementing agent.
