# Canvas Apps Code Review — Repo Cheat Sheet

A quick map of every folder, script, and skill in this repo: what each one does,
what's inside it, and **which pieces are actually needed for the GitHub Copilot
skill** versus which are build/test/docs scaffolding.

---

## 1. What this repo *is*

An **installable agent plugin** named `canvas-apps-code-review`. It contains one
**skill** (`canvas-app-analyzer`) that performs a **read-only audit of a Power Apps
Canvas app**: unzip the `.msapp` / solution `.zip`, read the `.pa.yaml` source, and
produce a structured Markdown review report. The same plugin format works in
**VS Code Copilot, GitHub Copilot CLI, and Claude Code**.

**The hybrid design** (the one idea that explains everything): a deterministic
**PowerShell script** does the mechanical, reproducible work (unzip, inventory,
exhaustive detection, enumeration tables); the **AI model** does the judgment work
(confirm/reject leads, assign severity, write the narrative).
Script = completeness; model = reasoning.

---

## 2. Top-level map — needed vs. scaffolding

| Path | What it is | Needed at skill runtime? |
|---|---|---|
| **`plugin.json`** | Plugin manifest (name, description, version) | ✅ **Yes** — makes it installable |
| **`skills/canvas-app-analyzer/`** | **The actual skill** (see §3) | ✅ **Yes — this is the product** |
| `README.md` | Repo front door: install instructions, design overview | ⚠️ Helpful, not loaded at runtime |
| `CHEATSHEET.md` | This file | ❌ Docs |
| `examples/` | A real sample report + the script's JSON output | ❌ Demo only |
| `test/` | Synthetic fixtures + the full test suite | ❌ Dev-time only |
| `docs/` | The plan + design specs (superpowers workflow) | ❌ Dev-time only |
| `canvas-app-analyzer-*.md` (4 files) | Spec / planning / brief docs | ❌ Dev-time only |
| `canvas-analysis/` | **Runtime *output* folder** the skill writes to | ❌ Generated, git-ignored |
| `.superpowers/` | Progress ledger from the build (git-ignored scratch) | ❌ Build scratch |
| `.claude/`, `.gitignore` | Local agent settings / ignore rules | ❌ Housekeeping |

**The shippable island = `plugin.json` + `skills/canvas-app-analyzer/`.**
Delete everything else and the skill still installs and runs. (That is exactly what
the README's "copy the skill folder" install does.)

---

## 3. Inside the skill — `skills/canvas-app-analyzer/`

The only part that matters at runtime.

| File | Lines | Role | Authored by |
|---|---|---|---|
| **`SKILL.md`** | ~254 | The instructions Copilot follows. The 7-step workflow: run script → orient → load references → targeted reads → judge leads → write report → verify. | The model reads & obeys this |
| **`scripts/analyze-canvas.ps1`** | 2001 | **The engine.** Unzips, finds the `.msapp`, extracts `\Src\*.pa.yaml`, inventories screens/controls/data sources, runs all **21 detectors**, and writes `index.json`, `enumeration.md`, `summary.md`, `mechanical-findings.json`. | Script (deterministic) |
| **`scripts/verify-report.ps1`** | 75 | **The checker.** After the model writes the report, reconciles it against the findings — flags any High/Med finding or lead the narrative forgot. Returns `{complete, missing[], unaddressedLeads[]}`. | Script |
| **`reference/delegation.md`** | 115 | Cited authority for **delegation & data-efficiency** findings (the delegation matrix). | Static reference |
| **`reference/coding-standards-and-performance.md`** | 368 | Cited authority for the **other five** categories (one section per detector, Microsoft-Learn-grounded). | Static reference |
| **`README.md`** | — | The skill's own full install + usage guide. | Docs |

### The 7-step contract in SKILL.md (the skill's spine)

1. **Run** `analyze-canvas.ps1`, branch on its `status` (`ok` / `no-canvas-app` / `legacy-no-src` / `multiple-apps` / `app-not-found` / `error`).
2. **Orient** — read `index.json`, `mechanical-findings.json`, `summary.md`, `enumeration.md`.
3. **Load references** — must cite one in every finding.
4. **Targeted reads** — only open the `.pa.yaml` lines the leads point at (keeps big apps in context).
5. **Judge leads** — confirm/reject, assign Severity + Confidence; delegation is always tagged *"Potential — verify row count."*
6. **Write the report** — embed `summary.md`, link `enumeration.md`, write narrative for High/Med findings + UR verdicts + leads.
7. **Verify** — run `verify-report.ps1` until `complete: true`.

> **Two-tier division of labor:** the script *authors* `enumeration.md` and
> `summary.md` (so the exhaustive long-tail can never be accidentally omitted by a
> model), while the model authors only the *narrative*. `verify-report.ps1` is the
> seam that enforces the handoff — a deterministic guard that catches a model that
> forgot a finding.

---

## 4. The two scripts at a glance

### `analyze-canvas.ps1` — input → output

- **In:** a path to a solution `.zip` or a bare `.msapp`.
- **Does:** native-PowerShell extraction (no `pac`, no external modules), regex/indent
  parse of `.pa.yaml`, runs 21 detectors.
- **Out** (into `canvas-analysis/<App>/.analysis/`): `index.json` (inventory),
  `index.md` (human digest), `mechanical-findings.json` (`deterministicFindings[]` +
  `leads[]`), `enumeration.md` (every finding as a table row), `summary.md` (counts
  block). Plus a persisted copy of `src/`.
- **Prints:** one JSON status object to stdout.

### `verify-report.ps1` — the completeness gate

- **In:** the finished report `.md` + `mechanical-findings.json`.
- **Does:** word-boundary checks that every High/Med finding ID and every lead ID
  appears in the narrative (Low is excluded — it is covered by `enumeration.md`).
- **Out:** `{complete, missing[], unaddressedLeads[]}`.

---

## 5. Supporting structure (not shipped — how it was built & proven)

| Path | Contents | Purpose |
|---|---|---|
| `test/build-fixture.ps1` | Builds 6 synthetic `.msapp` / `.zip` fixtures incl. the `MaintainabilityKitchenSink` that plants every detector pattern | Generates test inputs |
| `test/run-tests.ps1` + `test/lib/test-helpers.ps1` | Native-PS test harness (no Pester): `Invoke-Analyzer`, `Assert-*` helpers | Runs the suite |
| `test/tests/00–28*.tests.ps1` | One test file per task/detector (**590 assertions, all green**) | Proves each detector |
| `test/fixtures/*.msapp, *.zip` | The 6 built fixtures | Test data (git-ignored churn) |
| `examples/*` | `FieldServiceApp.analysis.md` + the script's `index.json` / `mechanical-findings.json` / `summary.md` / `enumeration.md` | Shows real output |
| `docs/superpowers/plans/2026-06-21-…depth.md` | The 32-task implementation plan | Build roadmap |
| `docs/superpowers/specs/…plugin-design.md` | Plugin-packaging design spec | Design record |
| `canvas-app-analyzer-spec.md` + 3 planning/brief `.md` | The vetted design briefs | Origin docs |

---

## 6. The 21 detectors (what the engine finds)

**Findings** (`deterministicFindings[]`, each gets a `PREFIX-NN` ID):
UV, UC, UD, UR\*, OS, DN, DS, VP, XD (pre-existing)
+ CC, UK, UP, EH, HC, DB, DC, LF, MC, DI, ND, MV, RL, **EV (High)**, GS, CT, IN (new).

**Leads** (`L-NN`, the model must judge): OG (overuse-globals), XC (cross-screen coupling).

UR carries a per-control `verdict` (`strong-dead-candidate` / `likely-decorative-or-layout`).

These roll up into the **six report sections**: Delegation · Performance ·
Redundancy · Maintainability · Dead/unused · Error-handling.

| Prefix | Detector | Severity / tier |
|---|---|---|
| UV / UC / UD | Unused variables / controls / data sources | Low / enum |
| UR | Unreferenced control (behavior-aware verdict) | Low / narrative |
| OS | Heavy / risky `App.OnStart` | Med / narrative |
| DN / DS | Default names / duplicate signatures | Med / narrative |
| VP | Naming-convention violation | Low / enum |
| XD | Exact-duplicate formula | Med / narrative |
| CC | Commented-out code | Low / enum |
| UK | Unused component | Med / narrative |
| UP | Unused custom property | Low / enum |
| EH | Stub event handler | Low / enum |
| HC | Permanently hidden control | Low / enum |
| DB | Dead branch (`If(true/false)`) | Low / enum |
| DC | Duplicate controls | Med / narrative |
| LF | Long formula (byte count) | Med / narrative |
| MC | Complex, no comment | Low / enum |
| DI | Deep `If` nesting | Med / narrative |
| ND | Near-duplicate (Levenshtein ≥ 0.90) | Med / narrative |
| MV | Magic values | Low / enum |
| RL | Repeated literals | Med / narrative |
| EV | Environment-specific hardcoding | **High** / narrative |
| GS | God screen | Med / narrative |
| CT | Control-tree depth | Low / enum |
| IN | Inconsistent naming | Low / enum |
| OG | Overuse of globals | Lead (`L-NN`) |
| XC | Cross-screen coupling | Lead (`L-NN`) |

---

## 7. TL;DR — "What do I actually need?"

> To **ship / install the skill**: `plugin.json` + the `skills/canvas-app-analyzer/`
> folder (SKILL.md, the 2 scripts, the 2 reference docs). That's it.
>
> Everything else — `test/`, `docs/`, `examples/`, the `*-spec.md` / `*-brief.md`
> files, `canvas-analysis/`, `.superpowers/` — is **how it was built, tested, and
> documented**, not what runs.

### Install (quick reference)

```bash
# GitHub Copilot CLI — one command
copilot plugin install AndrewGodlewsky/CanvasAppsCodeReview

# Or copy just the skill folder (universal; needs only git + a filesystem)
git clone https://github.com/AndrewGodlewsky/CanvasAppsCodeReview.git /tmp/caar
mkdir -p .github/skills            # per-repo; or ~/.copilot/skills for user-wide
cp -r /tmp/caar/skills/canvas-app-analyzer .github/skills/
```

### Run the engine directly (no Copilot needed)

```powershell
# Build the synthetic fixtures
powershell -NoProfile -File test/build-fixture.ps1

# Analyze one
powershell -NoProfile -ExecutionPolicy Bypass `
  -File skills/canvas-app-analyzer/scripts/analyze-canvas.ps1 `
  -Path test/fixtures/SampleSolution.zip
```
