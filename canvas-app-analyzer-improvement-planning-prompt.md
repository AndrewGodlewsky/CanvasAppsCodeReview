# Planning Prompt — Canvas App Analyzer: depth improvements (v-next)

Paste everything below the line to your planning/implementing agent. It assumes the agent can read
the repo, especially `canvas-app-analyzer-improvement-brief.md` in this directory.

---

You are improving an existing **GitHub Copilot CLI skill** called **Canvas App Analyzer**
(`skills/canvas-app-analyzer/`). The complete, already-vetted design is in
**`canvas-app-analyzer-improvement-brief.md`** — **read it in full before planning.** It is
decision-complete: treat decisions **D1–D9** and the detector catalog in **§3** as settled, and do
**not** re-litigate them. The original v1 spec (`canvas-app-analyzer-spec.md`) is background context
for how the skill works today.

## Context: what exists today
- `skills/canvas-app-analyzer/SKILL.md` — model-facing instructions.
- `skills/canvas-app-analyzer/scripts/analyze-canvas.ps1` — the deterministic PowerShell analyzer
  (line/indent **regex** parser, not a real Power Fx parser). Emits `index.json` and
  `mechanical-findings.json` (`deterministicFindings[]` + `leads[]`).
- `skills/canvas-app-analyzer/reference/` — `delegation.md` and `coding-standards-and-performance.md`
  (the cited authority files).
- `test/build-fixture.ps1` + `test/fixtures/*` — builds `.msapp` fixtures from raw `.pa.yaml`; covers
  control-flow branches but **no detector-level fixtures yet**.
- `examples/` — a generated sample report + machine files.

## Your job
1. **Plan first, then implement.** Produce a step-by-step plan and let me review it **before** you
   write code. Break it into small, independently verifiable steps — ideally one detector (or one
   architectural change) per step.
2. **Work test-first.** Per **D8**, write the fixture + asserted golden counts (and a negative case)
   for a detector *before* implementing that detector. Use the `tdd` skill.
3. Implement the brief end-to-end.

## What is settled — do NOT redesign
- **Two-tier output (D1):** narrative (fix-this) + exhaustive enumeration (clean-this-up).
- **The script authors the enumeration tables and the summary block; the model writes only the
  narrative (D2).** This is the central architectural change — completeness is guaranteed by
  construction, not by the model.
- **Stable IDs on every finding and lead (D3).** Must be stable across runs on unchanged input.
- **A new, separate `verify-report.ps1` (D4)** does deterministic report↔findings reconciliation and
  emits a gap JSON; the model only spends tokens fixing real gaps. Do **not** fold this into the
  analyzer as a flag.
- **Behavior-aware unreferenced-control verdicts, no blanket dismissal (D5).**
- **Per-detector-type citations; expand the reference docs one section per new detector (D6).**
  General coding-guidelines citation is acceptable where no dedicated MS doc exists — **label it**.
- **Triage split + batched long-tail backlog (D7).**
- **Scope (D9):** Orientation section unchanged; **no sub-agent fan-out**; unused data-source columns,
  accessibility, and the other listed items are **out of scope** — do not build them.

## Hard constraints (unchanged from v1 — do not deviate)
- **Read-only.** Never modify the app, never repack, no `pac canvas pack/unpack`. Read only
  `\Src\*.pa.yaml`.
- **Native PowerShell only** (no extra modules). Extraction via `System.IO.Compression` /
  `Expand-Archive`; recursive `.msapp` search (no hardcoded path).
- **Single-agent execution.** Detection and enumeration are deterministic and scale freely.

## Build infrastructure BEFORE detectors (brief §3.5)
A sanity check found enabling work that several detectors depend on. **Implement and test these
first** — two of them fail *silently* (the analyzer still runs but produces wrong output), so they are
the highest priority:
- **§7.1 Fix component classification** (`analyze-canvas.ps1:267` only matches a singular `\Component\`
  path; real source uses `Src\Components\` plural + component-named files). Blocks `UK`/`UP`. **Verify
  the real current layout** before fixing.
- **§7.2 Deterministic ordering for stable IDs** — variables/collections come from hashtables (`.Keys`
  order not guaranteed); sort by name then `file:line` before stamping IDs, or `verify-report.ps1`
  reconciliation breaks.
- **§7.3 Shared formula tokenizer** (string-literal vs. code spans) — `CC` scans code, `MV`/`EV` scan
  strings; without it both are noisy.
- **§7.4 Persist control nesting depth** (enables `CT`).
- **§7.5 Overridable thresholds** (so `GS`/`LF`/`DI`/`CT` are testable on a small fixture).

Follow the **suggested implementation order** at the end of brief §3.5. Each detector step is gated on
its prerequisite being green.

## Detector work (brief §3)
Implement every detector in the catalog with its assigned **ID prefix, severity, and bucket**
(deterministic vs. lead). Notable items:
- **Commented-out code (`CC`)** — the original blind spot; scan **code spans** (via the §7.3
  tokenizer) for `//` and `/* */`, flagging only commented-out *code*, not explanatory prose
  (`CC` must not contradict `MC` — test them together; brief §3d).
- Wire up **long/complex formula (`LF`)** to the already-computed `deepNesting` signal.
- **Magic values (`MV`)** are enumeration-only/Low; **repeated literals (`RL`)** and
  **env-specific hardcoding (`EV`, High)** ride in the narrative.
- **Overuse of globals (`OG`)** and **tight cross-screen coupling (`XC`)** are **leads** (model judges).
- **Thresholds are named constants at the top of the script** with conservative documented defaults.

## Open implementation decisions — propose options, don't guess silently (brief §6)
In your plan, **recommend an approach for each and let me confirm:**
1. **ID scheme format** (prefix + zero-padded index vs. content hash) — must be stable across runs.
2. **Near-duplicate (`ND`) similarity metric + threshold** — tune against the kitchen-sink fixture for
   recall vs. noise.
3. **Component-instantiation detection (`UK`/`UP`)** — how to resolve a component definition against
   its usages across screen files with the regex parser.
4. **Enumeration delivery** — script embeds tables inline in the report vs. links a sibling
   `enumeration.md` (both allowed by D2; pick for readability + clickable citations).

## Verify before you trust
Re-check current Microsoft guidance (Microsoft Docs MCP or web) for any new detector whose citation
isn't already in `coding-standards-and-performance.md`. If a documented behavior has shifted, **flag
it to me — do not silently adapt.**

## Definition of done (brief §5)
1. The analyzer on the **kitchen-sink fixture** produces, for **every** detector, the **exact asserted
   count** with stable IDs.
2. The enumeration tier lists **100% of deterministic findings**; per-category row count equals the
   script's emitted total.
3. `verify-report.ps1` returns `complete: true` for a correct report and the exact missing IDs for a
   deliberately-incomplete one (both cases tested).
4. Commented-out code is detected and counted.
5. Unreferenced controls get **individual, reasoned verdicts** — no blanket dismissal.
6. Narrative leads with High/Medium; the Low long-tail doesn't dominate the summary; the backlog
   batches long-tail cleanup into grouped tasks.
7. Every new finding type cites a reference-doc section (specific MS URL or labeled general guidance).
8. Orientation behavior unchanged; no fan-out introduced.
9. `examples/` regenerated to reflect the new structure (narrative + script-generated enumeration + IDs).
10. **IDs are stable across two runs** on the unchanged kitchen-sink fixture (byte-identical) — tested.
11. **Components are classified correctly** (component file ≠ screen; an unused component is flagged
    by `UK`) — tested.
12. **`CC` and `MC` do not contradict** on a fixture with both commented-out code and a real comment.

Start by reading `canvas-app-analyzer-improvement-brief.md`, then give me the plan.
