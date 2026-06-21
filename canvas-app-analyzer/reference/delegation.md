# Delegation Reference — Canvas App Analyzer

> Authority for all **Delegation & data efficiency** findings. Bundled inside the skill so findings
> are reproducible and citable. **Re-verify against the source URLs periodically** — Microsoft
> changes delegation support over time.
>
> Sources (verified current as of 2026-06):
> - Delegation overview: https://learn.microsoft.com/power-apps/maker/canvas-apps/delegation-overview
> - SharePoint delegable functions: https://learn.microsoft.com/power-apps/maker/canvas-apps/connections/connection-sharepoint-online#power-apps-delegable-functions-and-operations-for-sharepoint
> - SQL Server delegable functions: https://learn.microsoft.com/power-apps/maker/canvas-apps/connections/sql-connection-overview#power-apps-functions-and-operations-delegable-to-sql-server
> - Dataverse delegable functions: https://learn.microsoft.com/power-apps/maker/canvas-apps/connections/connection-common-data-service#power-apps-delegable-functions-and-operations-for-dataverse
> - Small data payloads: https://learn.microsoft.com/power-apps/maker/canvas-apps/small-data-payloads

## What delegation is (one paragraph for the report's "why it matters")
Delegation is when Power Fx translates an expression into a query the data source runs **server-side**,
returning only matching rows. When an expression is **non-delegable**, Power Apps instead pulls only
the first **500 records** (default; raisable to a max of **2,000** in app settings: Settings > General >
Data row limit) to the device and processes locally. If the source holds more rows than that limit, the
app **silently returns incorrect/partial results** — the single most damaging and hardest-to-spot
class of Canvas bug. **If any part of a query expression is non-delegable, Power Apps delegates none of it.**

## CRITICAL — why every delegation finding is "Potential, needs verification"
The `.pa.yaml` source contains the data source **type** (from `\DataSources`) and the **formula**, but
**NOT the row count**. A non-delegable `Filter` against a 50-row list is harmless; against a 50,000-row
list it's broken. The analyzer can prove the *pattern* but not the *impact*. Always phrase findings as:
*"Non-delegable `<function>` against `<connector>` data source `<name>`; impact depends on row count —
verify the source size. If it can exceed 500/2,000 rows, results will be silently truncated."*

## Delegable functions (the delegable set, per delegation overview)
These **can** delegate, *if the specific connector supports them* (see per-connector tables below):
- **Filtering / lookup:** `Filter`, `Search`, `First`, `LookUp`
- **Sorting:** `Sort`, `SortByColumns`
- **Inside Filter/LookUp predicates:** `And`/`&&`, `Or`/`||`, `Not`/`!`; `In` (**base data source columns
  only** — not on related/lookup tables); `=`, `<>`, `>=`, `<=`, `>`, `<`; `+`, `-`; `TrimEnds`;
  `IsBlank`; `StartsWith`, `EndsWith`; and constants (control properties, global/context variables).
- **Aggregates (backend-dependent):** `Sum`, `Average`, `Min`, `Max`, `CountRows`, `Count`.
- **Mutation (restricted, few sources):** `UpdateIf`, `RemoveIf`.

## Non-delegable functions (ALWAYS local — high-confidence flags)
If these operate directly on a connected large data source, they are non-delegable on **every** connector:
- `FirstN`, `Last`, `LastN`
- `Choices`
- `Concat`
- `Collect`, `ClearCollect`  (collecting an entire large source caps at 500/2,000)
- `GroupBy`, `Ungroup`
- Plus: any predicate function not in the delegable list above (e.g., most text functions like `Left`,
  `Mid`, `Right`, `Upper`, `Lower`, `Len` [except where noted], date functions inside predicates, etc.)

> Note: `AddColumns`/`DropColumns`/`RenameColumns`/`ShowColumns` pass delegation **through to their inner
> table argument**, but their **output** is still capped at the non-delegation limit. A `Filter` inside
> `AddColumns` that runs once per outer row is also an **N+1** pattern (see performance.md).

## Per-connector delegation — the matrix

### Dataverse — broadest support (recommend as the "preferred" remediation target)
Supports the delegable set above most completely, including `In` on base-table columns, and aggregates
(`CountRows` approximate; `CountIf` exact up to 50,000 rows). When flagging delegation problems on other
connectors, "move to Dataverse" is a legitimate recommended remediation.

### SQL Server — delegable operations by data type (verbatim from docs)
Expressions joined with `And`, `Or`, `Not` are delegable. `-` = not applicable to that type.

| Operation / function | Number | Text | Boolean | DateTime | Guid |
| --- | --- | --- | --- | --- | --- |
| `*, +, -, /` | Yes | - | - | No | - |
| `<, <=, >, >=` | Yes | **No** | **No** | Yes | - |
| `=, <>` | Yes | Yes | Yes | Yes | Yes |
| `Average` | Yes | - | - | - | - |
| `EndsWith` | - | Yes [1] | - | - | - |
| `Filter` | Yes | Yes | Yes | Yes [2] | Yes |
| `In` (substring) | - | Yes [3] | - | - | - |
| `IsBlank` | **No** | **No** | **No** | **No** | **No** |
| `Len` | - | Yes [5] | - | - | - |
| `Lookup` | Yes | Yes | Yes | Yes | Yes |
| `Max` | Yes | - | - | **No** | - |
| `Min` | Yes | - | - | **No** | - |
| `Search` | **No** | Yes | **No** | **No** | - |
| `Sort` | Yes | Yes | Yes | Yes | - |
| `SortByColumns` | Yes | Yes | Yes | Yes | - |
| `StartsWith` | - | Yes [6] | - | - | - |
| `Sum` | Yes | - | - | - | - |
| `UpdateIf, RemoveIf` | Yes [7] | Yes | Yes | Yes | Yes |

SQL gotchas to flag:
- `IsBlank(col)` does **not** delegate — use `col = Blank()` instead (semantically close; won't treat
  `""` as empty; not usable on Guid).
- `StartsWith`/`EndsWith`/`In` only delegate as `(col, "literal")`, **not** `("literal", col)`.
- Direct date filters don't delegate through an on-prem data gateway.
- Avoid `char`/`nchar` (use `varchar`/`nvarchar`) — `Len` and `EndsWith` behave unexpectedly on fixed-width.

### SharePoint — narrower; high-frequency legacy offender
- `IsBlank(col)` does **not** delegate — use `col = Blank()` (works for `=`, not for `<>`).
- `StartsWith` does **not** delegate on subfields of **Choice** or **Lookup** complex types.
- `Search` on text columns is a common non-delegable trap — replace with delegable `Filter` +
  `StartsWith`/`=` where possible, or a server-side view.
- `UpdateIf` / `RemoveIf` only simulate delegation up to the 500/2,000 limit.
- `In` against SharePoint is generally **not** delegable — flag `Filter(list, x in col)` patterns.

### Collections, static Excel imports, context variables — no delegation needed
Already in memory; the full Power Fx language is available. **Do not flag delegation** on a `Filter`/`Sort`
whose source is a collection (`col*`), a context variable, or `Add static data` Excel. The analyzer must
resolve the source type from `\DataSources` before raising a delegation finding (avoids false positives).

## How to detect from `.pa.yaml` (guidance for the analyzer)
1. Resolve each data source name to a **connector type** via the `\DataSources` folder + `Connections`.
2. For each `Filter`/`LookUp`/`Search`/`Sort`/`SortByColumns`/aggregate call whose first argument is a
   **server connector** (not a collection/variable/static Excel), check the function + the predicate's
   operators/functions against the matrix for that connector + the involved column's data type.
3. Flag non-delegable functions from the "ALWAYS local" list as **higher-confidence** delegation issues.
4. Flag connector-specific traps (SQL `Search`/`IsBlank`, SharePoint `Search`/`In`/Choice-`StartsWith`).
5. Every delegation finding is severity-weighted by *likelihood the source is large* but tagged
   **Potential — verify row count** (the source has no counts).
6. Recommended remediations, in order: rewrite with a delegable equivalent; pre-filter via server-side
   view (SharePoint) / stored proc or view (SQL); cache a genuinely-small, slow-changing source to a
   collection in a deferred step; or move the data to Dataverse for broader delegation.
