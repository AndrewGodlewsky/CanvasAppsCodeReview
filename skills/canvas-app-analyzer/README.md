# Canvas App Analyzer (GitHub Copilot CLI skill)

A **read-only** skill that helps a team taking over an unfamiliar Power Apps **Canvas app** both
understand how it works and review it for delegation, performance, redundancy, maintainability,
dead code, and error-handling problems. It produces **one Markdown report per app** that doubles as
a hand-off brief for a downstream planning/implementing agent.

It never modifies the app: it treats the `.msapp` / solution `.zip` as plain archives, reads only
the active `\Src\*.pa.yaml` source, and writes its output to a separate `./canvas-analysis/` folder.

## What's in here

```
canvas-app-analyzer/
  SKILL.md                                   # the skill the model follows
  scripts/analyze-canvas.ps1                 # deterministic helper (unzip + inventory + findings)
  reference/delegation.md                    # cited authority: delegation & data efficiency
  reference/coding-standards-and-performance.md  # cited authority: the other five categories
```

## Prerequisites

- **Windows PowerShell 5.1+ or PowerShell 7** (built into Windows). The script uses only the
  in-box `System.IO.Compression` types - **no external modules**.
- **`pac` (Power Platform CLI) is NOT required.** The skill deliberately avoids it: a `.msapp` and a
  solution `.zip` are ordinary ZIP archives, and the deprecated `pac canvas unpack` / retired
  `.fx.yaml` path is not used. If you ever see the skill suggest installing `pac`, that's a bug -
  it shouldn't.

You also need the app's source as a file: export the **solution `.zip`** (recommended) or a single
app's **`.msapp`** (Power Apps > app > ... > Export, or Power Apps Studio > File > Save as > This
computer). The skill finds the `.msapp` inside a solution automatically by recursive search, so both
raw-export and `pac solution unpack` layouts work.

## Install

GitHub Copilot reads the open **Agent Skills** standard (`SKILL.md`). A skill is a *folder*
containing `SKILL.md`; drop the whole `canvas-app-analyzer/` folder into one of Copilot's skill
directories. The `scripts/` and `reference/` subfolders must stay alongside `SKILL.md` - the skill
reads them by relative path, and Copilot auto-discovers every file in the skill folder.

**Personal (available in every project):**
- `~/.copilot/skills/canvas-app-analyzer/` (Copilot CLI), or `~/.agents/skills/...`, or
  `~/.claude/skills/...`

**Per-repository (checked in with a project):**
- `.github/skills/canvas-app-analyzer/`, or `.claude/skills/...`, or `.agents/skills/...`

Then verify it loaded:
- `/skills list` - confirm `canvas-app-analyzer` appears
- `/skills info canvas-app-analyzer` - inspect it
- `/skills reload` - re-scan after adding or editing the skill in an active session

In VS Code you can also add custom skill locations via the `chat.agentSkillsLocations` setting.

> **Optional - pre-approve the helper script.** By default Copilot asks before running the
> PowerShell helper. If you've reviewed `scripts/analyze-canvas.ps1` and trust it, you can add
> `allowed-tools: shell` to the `SKILL.md` frontmatter to skip that prompt. Leave it off if you
> prefer to approve each run (recommended until you've read the script).

## Use it (VS Code agent mode, or the Copilot CLI in the integrated terminal)

Agent Skills work in **VS Code Copilot agent mode** (the chat/agent panel) *and* in the **GitHub
Copilot CLI** running in the VS Code integrated terminal. Either way, point the skill at your archive
- describe it in natural language and Copilot picks the skill from its description:

> *"Analyze this inherited canvas app: ./MySolution.zip"*

From the Copilot CLI you can also be terse:

```
analyze ./MySolution.zip
```

or describe it in natural language, e.g. *"review this inherited canvas app: ./MySolution.zip"*.
A bare `.msapp` works too: `analyze ./MyApp.msapp`.

What happens:
1. The skill runs `analyze-canvas.ps1`, which unzips, finds the `.msapp`(s), and extracts
   `\Src\*.pa.yaml`.
2. If several apps are found, it lists them and asks which to analyze. If none are found, or the app
   predates the YAML source format, it stops with a clear message (resave in Studio to regenerate).
3. On success it writes, under `./canvas-analysis/<AppName>/`:
   - `src/` - the persisted `.pa.yaml` source (browsable; the report's citations point here).
   - `<AppName>.analysis.md` - the report: summary table -> orientation -> six-category findings
     (each with severity, confidence, location, evidence, why-it-matters + citation) -> remediation
     backlog.
   - `.analysis/` - intermediate machine files (`index.json`, `mechanical-findings.json`,
     `index.md`, `status.json`) kept for reproducibility.

## Running the helper directly (optional)

The script is usable on its own for debugging:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/analyze-canvas.ps1 -Path .\MySolution.zip
# pick a specific app when several exist:
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/analyze-canvas.ps1 -Path .\MySolution.zip -AppName "FieldServiceApp"
```

It always prints a JSON status object to stdout and (on success) writes the files above.

## Scope & boundaries

- **Read-only by design** - it's a diagnosis tool that feeds a separate fix agent; it never edits or
  repackages the app.
- **Six finding categories**, grounded in current Microsoft Learn guidance (bundled and cited).
  Accessibility and responsive-layout checks are intentionally out of scope.
- **Delegation findings are always flagged "Potential - verify row count"** - the `.pa.yaml` source
  contains the connector type but not row counts, so impact can't be proven from source alone.
- **Single-agent (v1).** For very large apps (> ~25 screens) a sub-agent fan-out is documented as an
  extension point but not built.

## Maintenance

The two `reference/` files embed their Microsoft Learn source URLs and a "re-verify periodically"
note - Microsoft changes delegation support and source-format guidance over time. Re-check those
links when revisiting the skill. (Verified current as of 2026-06: `pac canvas unpack`/`pack` remain
deprecated and `\Src\*.pa.yaml` remains the only active source format.)
