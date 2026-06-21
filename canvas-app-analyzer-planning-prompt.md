# Planning Prompt — Canvas App Analyzer skill

Paste this to your planning/implementing agent. It assumes the agent can read
`canvas-app-analyzer-spec.md` in the same directory.

---

You are building a **GitHub Copilot CLI skill** called **Canvas App Analyzer**. The complete,
already-vetted design brief is in `canvas-app-analyzer-spec.md` — **read it in full before
planning.** It is decision-complete; treat its "Key design decisions" appendix as settled and
do **not** re-litigate those choices.

## Your job
1. **Plan first, then implement.** Produce a step-by-step implementation plan and let me review it
   before you write code. Break it into small, independently verifiable steps.
2. **Build the skill** as a Copilot CLI `SKILL.md` plus its bundled assets (helper script +
   reference files), following the spec exactly.

## Hard constraints (from the spec — do not deviate)
- **Read-only.** The skill never modifies the app. No `pac canvas pack`, no writing into `.msapp`.
- **Use the current extraction method**, not deprecated tooling: a `.msapp`/solution `.zip` is a
  plain archive — extract with `Expand-Archive`, **find `.msapp` files by recursive search (no
  hardcoded path — raw-export and `pac solution unpack` layouts differ)**, and read only
  `\Src\*.pa.yaml`. Do **not** use `pac canvas unpack` or the retired `.fx.yaml` format. `pac` is
  not required.
- **Single-agent v1.** Do not build sub-agent fan-out; only document it as an extension point.
- **Hybrid architecture:** a **PowerShell** helper script does the deterministic mechanical work
  (unzip, inventory, default-name / unused / exact-duplicate detection, emit an index); the model
  does judgment work (orientation, delegation, redundancy, severity, report authoring).
- **Output:** one Markdown report per app under `./canvas-analysis/<AppName>/`, with persisted
  `src/`, the six finding categories, per-finding **severity + confidence**, **no padding**, and a
  closing **Remediation Backlog**.

## Verify before you trust (the spec says this area changes)
- At build time, **re-check the current Microsoft guidance** via the links in the spec's reference
  section (Microsoft Docs MCP or web) to confirm the `.pa.yaml` source layout and the
  `pac canvas unpack` deprecation still hold. If anything has shifted, **flag it to me** before
  coding around it — do not silently adapt.

## Delivered assets — do NOT re-author
The two authority files (`reference/delegation.md` and `reference/coding-standards-and-performance.md`)
are written, vetted, and grounded in current Microsoft Learn docs. **Ship them as-is** and wire the
skill to read them. Your only jobs here: pick where they live in the skill (e.g., `reference/`), and
make the SKILL.md instruct the model to **cite them in every finding**. If you believe something in
them is wrong or stale, **flag it to me — do not silently rewrite.**

## Open implementation decisions — propose options, don't guess silently
The spec is intentionally not prescriptive on these. In your plan, **recommend an approach for each
and let me confirm:**
1. **Helper-script output format** — the exact schema of the index + mechanical-findings files the
   script emits for the model to consume.
2. **SKILL.md trigger/description** — the frontmatter `description` wording that makes Copilot CLI
   activate the skill at the right time, and how the user invokes it (argument = path to zip).
3. **Large-app handling** — how the index keeps a many-screen app within context in the
   single-agent v1 (chunking/targeted reads), short of the documented sub-agent extension.

## Definition of done
- The skill runs end-to-end on a sample solution `.zip`: **finds `.msapp` files via recursive search**
  (no hardcoded path), detects multiple apps and prompts, handles **zero apps found** and the legacy
  "no `\Src`" case each with a clear stop message, and produces a report matching the spec's structure
  (summary table -> orientation -> six-category findings with severity+confidence -> remediation backlog).
- Deterministic findings come from the script; judgment findings cite bundled guidance.
- A short **README/usage note** explains install, invocation from the VS Code terminal, and the
  `pac` prerequisite **only if** you end up needing it (the spec's path avoids it — justify any
  dependency you add).

Start by reading the spec and giving me the plan.
