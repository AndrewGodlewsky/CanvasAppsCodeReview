# Design: Package `canvas-app-analyzer` as the `canvas-apps-code-review` agent plugin

**Date:** 2026-06-21
**Status:** Approved (design), pending implementation
**Repo:** `CanvasAppsCodeReview` (origin: `https://github.com/AndrewGodlewsky/CanvasAppsCodeReview.git`)

## Goal

Convert this repository from a manually-installed GitHub Copilot **Agent Skill** (drop the
`canvas-app-analyzer/` folder into a Copilot skills directory) into a one-action-install **Agent
Plugin**. Users should be able to install it directly from the GitHub URL — no Marketplace account,
no publishing pipeline.

## Why an Agent Plugin (vs. a Marketplace extension)

The Agent Plugin format (`plugin.json` at the repo root) is **shared across VS Code, the GitHub
Copilot CLI, and Claude Code**, so a single repo works in all three. It installs from a Git URL via
the **Chat: Install Plugin From Source** command — zero publishing overhead. The skill already
targets "VS Code agent mode + Copilot CLI," so the plugin format matches its existing reach.

A VS Code Marketplace extension (using the `chatSkills` contribution point) was considered and
rejected for now: it gives a literal `code --install-extension` one-liner but costs a publisher
account + `vsce` packaging/CI and is VS Code-only.

## Architecture

A plugin is a `plugin.json` manifest at the repo root plus a `skills/` folder it auto-discovers.
The skill's internals (`SKILL.md`, `scripts/`, `reference/`) are unchanged — only their location
moves. `SKILL.md` references `scripts/` and `reference/` by **relative** path, so those references
remain valid after the move.

## File changes

### 1. Move the skill into the standard location (via `git mv`, preserving history)

```
canvas-app-analyzer/            ->   skills/canvas-app-analyzer/
  SKILL.md                             SKILL.md          (unchanged)
  scripts/analyze-canvas.ps1           scripts/...       (unchanged)
  reference/*.md                       reference/*.md    (unchanged)
  README.md                            README.md         (path refs updated)
```

The skill's `name: canvas-app-analyzer` frontmatter already matches its folder name, so it avoids
the documented "name must match directory or it silently fails to load" trap.

### 2. New `plugin.json` at repo root

```json
{
  "name": "canvas-apps-code-review",
  "description": "Read-only review of Power Apps Canvas apps — extract .pa.yaml source and produce a structured Markdown audit (delegation, performance, redundancy, maintainability, dead code, error handling).",
  "version": "1.0.0",
  "author": "Andrew Godlewsky"
}
```

No `skills` field is needed — it defaults to `skills/` and auto-discovers `canvas-app-analyzer`.
The resulting slash command reads as `/canvas-apps-code-review:canvas-app-analyzer`.

### 3. Update the root `README.md` install section

Lead with the one-action install:

- **VS Code:** Command Palette -> **Chat: Install Plugin From Source** -> paste
  `https://github.com/AndrewGodlewsky/CanvasAppsCodeReview.git`
- Note the same plugin also works in the **GitHub Copilot CLI** and **Claude Code** (shared plugin
  format).
- Keep the existing manual "drop the folder in" instructions as a fallback, with paths updated from
  `canvas-app-analyzer/` to `skills/canvas-app-analyzer/`.

### 4. Leave untouched

`examples/`, `test/`, `canvas-app-analyzer-spec.md`, `canvas-app-analyzer-planning-prompt.md`,
`.gitignore`. These are dev/reference assets; the manifest does not reference them, so they do not
bloat an install but remain useful in the repo.

## Out of scope (YAGNI)

- No VS Code Marketplace extension / `vsce` packaging.
- No changes to the PowerShell helper or the skill's analysis logic.
- No `marketplace.json` registry (only needed for hosting a multi-plugin catalog).

## Success criteria

1. `plugin.json` exists at the repo root and validates (kebab-case name, required fields present).
2. `skills/canvas-app-analyzer/SKILL.md` exists with its internal relative paths (`scripts/`,
   `reference/`) intact.
3. The root `README.md` documents the one-action install from the Git URL.
4. The repo still cleanly supports the legacy manual-install path (folder unchanged, just relocated).

## Delivery

All changes land on the `package-as-agent-plugin` branch for review before merging to `main`.
