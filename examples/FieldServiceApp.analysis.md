# Canvas App Analysis - FieldServiceApp

> Read-only analysis produced by the **canvas-app-analyzer** skill. Source app:
> `FieldServiceApp.msapp`. Persisted source for citations: [`src/`](./src). Generated from the
> deterministic index in [`.analysis/index.json`](./.analysis/index.json) plus model judgment
> grounded in the bundled Microsoft Learn references.

## 1. Summary

| Category | High | Medium | Low | Total |
| --- | --- | --- | --- | --- |
| Delegation & data efficiency | 0 | 0 | 0 | 0 |
| Performance | 1 | 2 | 0 | 3 |
| Redundancy & reuse | 0 | 1 | 0 | 1 |
| Maintainability & naming | 0 | 2 | 1 | 3 |
| Dead / unused | 0 | 1 | 3 | 4 |
| Error handling & resilience | 0 | 1 | 0 | 1 |
| **Total** | **1** | **7** | **4** | **12** |

Confidence split: **7 Confirmed**, **5 Potential** (need a runtime fact to confirm - row counts,
screen reachability, or operation risk).

The headline is **performance**, not delegation: the two data queries the scanner flagged as
delegation candidates both use the `=` operator, which *does* delegate on SharePoint, so they are
fine. The real costs are an overloaded `App.OnStart` (with a `Navigate` that blocks first render)
and a per-row (N+1) lookup pattern.

## 2. Orientation

**Purpose (inferred).** A small field-service app: a home screen lists open orders from a SharePoint
"Orders" list and greets the signed-in user; a detail screen works with an order/customer record and
saves changes back to SharePoint.

**Screens (3).**

| Screen | Controls | Role |
| --- | --- | --- |
| HomeScreen | 3 | Start screen; lists open orders, welcome label, nav button |
| DetailScreen | 3 | Order/customer detail gallery + Save button |
| OrphanScreen | 1 | Not reachable via navigation (see finding D-5) |

**Navigation map.**
```
App.OnStart --Navigate--> HomeScreen   (start screen; also App.StartScreen = HomeScreen)
HomeScreen  --Navigate--> DetailScreen (Button2.OnSelect)
OrphanScreen : no inbound Navigate()   <-- orphan
```

**Data sources / connectors (3, all SharePoint).** `Orders` (used), `Customers` (used),
`Archive` (connected but never referenced - see D-4).

**Variables & collections.** Globals: `gblUser` (used), `gblCount` (unused), `unusedVar` (unused).
Collections: `colOrders` (used), `colCustomers` (unused).

**Components / key dependencies.** No components. App depends on three SharePoint lists; all data
loading happens in `App.OnStart`.

## 3. Findings

### 1. Delegation & data efficiency

**No issues found.**

Two candidates were evaluated against the SharePoint delegation matrix and cleared:
- `HomeScreen -> galOrders.Items` = `Filter(Orders, Status = "Open")` ([src/HomeScreen.pa.yaml:9](./src/HomeScreen.pa.yaml)) - `Filter` with the `=` operator **delegates** on SharePoint.
- `DetailScreen -> Gallery1.OnSelect` = `LookUp(Customers, Id = ThisRecord.CustId)` ([src/DetailScreen.pa.yaml:8](./src/DetailScreen.pa.yaml)) - `LookUp` with `=` **delegates** on SharePoint (the *performance* problem with this line is its N+1 context - see P-3).

> Caveat to verify: if `Status` is a SharePoint **Choice** column, confirm the `=` comparison still
> delegates in your environment - choice/lookup subfields have delegation quirks
> (`reference/delegation.md` -> "SharePoint", https://learn.microsoft.com/power-apps/maker/canvas-apps/delegation-overview).

### 2. Performance

**P-1 - `Navigate` inside `App.OnStart` blocks first render**
- **Severity:** High  **Confidence:** Confirmed
- **Location:** App -> `OnStart` ([src/App.pa.yaml:4](./src/App.pa.yaml))
- **Evidence:** `... Set(unusedVar, 42); Navigate(HomeScreen, ScreenTransition.None)`
- **Why it matters:** A `Navigate` anywhere in `App.OnStart` forces the *entire* OnStart to finish
  before the first screen renders, delaying perceived load. (`reference/coding-standards-and-performance.md`
  -> "Navigate in App.OnStart -> use App.StartScreen", https://learn.microsoft.com/power-apps/maker/canvas-apps/fast-app-page-load)
- **Remediation:** Remove the `Navigate`; the app already declares `App.StartScreen = HomeScreen`,
  which is the declarative replacement. Ensure `StartScreen` doesn't depend on a global set later in
  OnStart (no race).

**P-2 - Overloaded `App.OnStart` (static init belongs in `App.Formulas`)**
- **Severity:** Medium  **Confidence:** Confirmed
- **Location:** App -> `OnStart` ([src/App.pa.yaml:4](./src/App.pa.yaml))
- **Evidence:** `Set(gblUser, User().FullName); ClearCollect(colOrders, Orders); ClearCollect(colCustomers, Customers); Set(unusedVar, 42); ...`
- **Why it matters:** Moving static initializations out of `App.OnStart` into named formulas in
  `App.Formulas` (immutable, lazily evaluated) has cut load time by up to ~80%.
  (`reference/coding-standards-and-performance.md` -> "App.OnStart overload -> use App.Formulas",
  https://learn.microsoft.com/power-apps/maker/canvas-apps/efficient-calculations)
- **Remediation:** Make `gblUser` a named formula (`gblUser = User().FullName`). Drop `unusedVar`
  (see D-2) and the `colCustomers` load (see D-3). Keep `Set` only for state that actually mutates.

**P-3 - Per-row (N+1) `LookUp` inside `ForAll`**
- **Severity:** Medium  **Confidence:** Potential - high impact
- **Location:** DetailScreen -> `Gallery1.OnSelect` ([src/DetailScreen.pa.yaml:8](./src/DetailScreen.pa.yaml))
- **Evidence:** `ForAll(colOrders, LookUp(Customers, Id = ThisRecord.CustId))`
- **Why it matters:** A `LookUp` evaluated once per row of `colOrders` generates one network call
  per row - a classic N+1 that scales badly. (`reference/coding-standards-and-performance.md` ->
  "Select N+1 data queries", https://learn.microsoft.com/power-platform/architecture/key-concepts/performance/top-issues)
- **Remediation:** Batch up front - e.g. `ClearCollect(colCustomers, Customers)` once, then read
  the local collection, or reshape with related columns at the source so the customer field arrives
  with the order. (Note: `colCustomers` is already loaded in OnStart but unused - wiring this lookup
  to it would fix both P-3 and D-3.)

### 3. Redundancy & reuse

**R-1 - Identical formula duplicated across two labels**
- **Severity:** Medium  **Confidence:** Confirmed
- **Location:** HomeScreen -> `lblWelcome.Text` ([src/HomeScreen.pa.yaml:18](./src/HomeScreen.pa.yaml)) and DetailScreen -> `lblSame.Text` ([src/DetailScreen.pa.yaml:16](./src/DetailScreen.pa.yaml))
- **Evidence:** `=Concatenate("Hello ", gblUser, " welcome to the application dashboard")`
- **Why it matters:** Duplicated logic drifts out of sync and inflates maintenance. Extract to a
  single source of truth. (`reference/coding-standards-and-performance.md` -> "Split long formulas /
  duplicated formulas" and "With function", https://learn.microsoft.com/power-apps/maker/canvas-apps/working-with-large-apps)
- **Remediation:** Promote to a named formula in `App.Formulas` (e.g.
  `gblWelcomeText = "Hello " & gblUser & " welcome to the application dashboard"`) and reference it
  from both labels.

### 4. Maintainability & naming

**M-1 - Default control name `Gallery1`**
- **Severity:** Medium  **Confidence:** Confirmed
- **Location:** DetailScreen -> `Gallery1` ([src/DetailScreen.pa.yaml:4](./src/DetailScreen.pa.yaml))
- **Evidence:** `Gallery1 (Gallery)`
- **Why it matters:** Auto-generated names hide intent. (`reference/coding-standards-and-performance.md`
  -> control-prefix table, https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-readability)
- **Remediation:** Rename with the `gal` prefix + purpose, e.g. `galCustomerOrders`.

**M-2 - Default control name `Button2`**
- **Severity:** Medium  **Confidence:** Confirmed
- **Location:** HomeScreen -> `Button2` ([src/HomeScreen.pa.yaml:10](./src/HomeScreen.pa.yaml))
- **Evidence:** `Button2 (Classic/Button)`
- **Why it matters:** Same as M-1. (`reference/coding-standards-and-performance.md` -> control-prefix table.)
- **Remediation:** Rename with the `btn` prefix + purpose, e.g. `btnGoToDetails`.

**M-3 - Global variable missing the `gbl` prefix**
- **Severity:** Low  **Confidence:** Confirmed
- **Location:** App -> `OnStart` ([src/App.pa.yaml:4](./src/App.pa.yaml))
- **Evidence:** `Set(unusedVar, 42)` - global variable `unusedVar`
- **Why it matters:** The convention is `gbl`/`loc`/`col`/`scp` prefixes for scannable scope.
  (`reference/coding-standards-and-performance.md` -> "Variables & collections".) Moot if removed
  per D-2.
- **Remediation:** Remove it (D-2); otherwise rename to `gbl...`.

### 5. Dead / unused

**D-1 - Unused global `gblCount`** - **Low / Confirmed.** Set in `HomeScreen.OnVisible`
(`Set(gblCount, CountRows(colOrders))`, [src/HomeScreen.pa.yaml](./src/HomeScreen.pa.yaml)) but
never read. Remove it (and its `CountRows` call) or bind it to a control.
(`reference/coding-standards-and-performance.md` -> "Dead / unused".)

**D-2 - Unused global `unusedVar`** - **Low / Confirmed.** `Set(unusedVar, 42)`
([src/App.pa.yaml:4](./src/App.pa.yaml)) is never read. Remove it.

**D-3 - Unused collection `colCustomers`** - **Low / Confirmed.**
`ClearCollect(colCustomers, Customers)` runs in OnStart ([src/App.pa.yaml:4](./src/App.pa.yaml)) but
the collection is never referenced. Either remove the load (faster startup) or use it to fix the N+1
in P-3 - the better option.

**D-4 - Unused data source `Archive`** - **Medium / Confirmed.** The SharePoint `Archive` list is
connected but never referenced in any formula. Remove the connection to shrink the app and its
permission surface. (`reference/coding-standards-and-performance.md` -> "Dead / unused" - data
sources.)

**D-5 - Orphan screen `OrphanScreen`** - **Medium / Potential.** Never targeted by a `Navigate()`
and not the start screen ([src/OrphanScreen.pa.yaml](./src/OrphanScreen.pa.yaml)). Verify it isn't
reached via a variable-driven navigation before deleting it.

> **Controls reference-check (no findings):** the scanner flagged 7 controls as never referenced by
> another formula. On review, all are user-visible/interactive (galleries, nav/save buttons, display
> labels), so per the guidance ("never referenced **and** not user-visible/interactive") **none are
> dead.** No action.

### 6. Error handling & resilience

**E-1 - `Patch` to SharePoint with no error handling**
- **Severity:** Medium  **Confidence:** Potential
- **Location:** DetailScreen -> `btnSave.OnSelect` ([src/DetailScreen.pa.yaml:12](./src/DetailScreen.pa.yaml))
- **Evidence:** `Patch(Orders, Defaults(Orders), {Title: "x"})`
- **Why it matters:** A save that can fail (network/permission/validation) gives the user no signal
  if it does. (`reference/coding-standards-and-performance.md` -> "Error handling & resilience",
  https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-optimization)
- **Remediation:** Wrap in `IfError(...)` and/or check `Errors(Orders)` after the `Patch`, surfacing
  a record-level message near the Save button. (Tagged Potential - judge how critical this save is.)

## 4. Remediation Backlog (hand-off to the planning/implementing agent)

Ranked by severity x confidence x rough effort. Confirmed-High first; Potential items flagged so no
one fixes a problem that might not exist.

| # | Action | Fixes | Sev | Conf | Effort |
| --- | --- | --- | --- | --- | --- |
| 1 | Remove `Navigate(HomeScreen)` from `App.OnStart`; rely on `App.StartScreen` | P-1 | High | Confirmed | XS |
| 2 | Move static init out of `App.OnStart` into `App.Formulas`; drop dead init | P-2, D-1, D-2, M-3 | Medium | Confirmed | M |
| 3 | Extract the duplicated welcome string to one named formula | R-1 | Medium | Confirmed | S |
| 4 | Rename `Gallery1` -> `galCustomerOrders`, `Button2` -> `btnGoToDetails` | M-1, M-2 | Medium | Confirmed | S |
| 5 | Remove the unused `Archive` connection | D-4 | Medium | Confirmed | XS |
| 6 | Replace the N+1 `ForAll(... LookUp ...)` with the already-loaded `colCustomers` | P-3, D-3 | Medium | Potential (verify row counts/behavior) | M |
| 7 | Add `IfError`/`Errors()` around the `btnSave` `Patch` | E-1 | Medium | Potential (judge criticality) | S |
| 8 | Confirm `OrphanScreen` is truly unreachable, then delete | D-5 | Medium | Potential (verify reachability) | XS |
| 9 | If `Status` is a Choice column, verify the `Filter(Orders, Status=...)` still delegates | (delegation caveat) | - | Potential (verify in env) | XS |

**Top priority:** items 1-5 are Confirmed and low-risk - do them first. Items 6-9 need a runtime
fact verified before implementing.
