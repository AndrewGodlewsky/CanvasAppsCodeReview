# FieldServiceApp — Canvas App Analysis Report

## 1. Summary

<!-- BEGIN summary.md (verbatim) -->
# Analysis Summary - FieldServiceApp

## Findings by category and severity

| Category | High | Med | Low | Total |
| --- | --- | --- | --- | --- |
| Maintainability & naming | 0 | 2 | 11 | 13 |
| Dead / unused | 0 | 1 | 11 | 12 |
| Redundancy & reuse | 0 | 2 | 0 | 2 |
| Delegation & data efficiency | 0 | 0 | 0 | 0 |
| Performance | 0 | 0 | 0 | 0 |
| Error handling & resilience | 0 | 0 | 0 | 0 |
| **Total** | 0 | 5 | 22 | 27 |

## Confidence split

| Confidence | Count |
| --- | --- |
| Confirmed | 19 |
| Potential | 8 |

**Total deterministic findings: 27**

**Judgment leads: 7**
<!-- END summary.md -->

[Full cleanup backlog -> enumeration.md](enumeration.md)

---

## 2. Orientation

### Purpose

FieldServiceApp is a simple field-service-style order-management app. The app loads the current user's name and pre-fetches two SharePoint lists (Orders and Customers) on startup, shows open orders in a gallery on the home screen, and allows the user to navigate to a detail screen where they can view and patch orders.

### Screen Inventory

| Screen | Controls | Formula bytes | Notes |
| --- | --- | --- | --- |
| HomeScreen | 3 | 207 | Start screen; shows filtered open orders |
| DetailScreen | 3 | 189 | Order detail + save |
| OrphanScreen | 1 | 24 | Never navigated to; likely dead |

**Start screen:** `HomeScreen` (declared in `App.StartScreen` *and* via `Navigate` in `App.OnStart` — the Navigate is redundant and harmful; see L-03).

### Navigation Map

```
App.OnStart  -->  Navigate(HomeScreen)   [redundant — App.StartScreen = HomeScreen already]
HomeScreen   -->  Navigate(DetailScreen) via Button2.OnSelect
```

OrphanScreen is not reachable from any Navigate call and is not the start screen.

### Data Sources & Connectors

| Name | Connector |
| --- | --- |
| Orders | SharePoint |
| Customers | SharePoint |
| Archive | SharePoint |

`Archive` is connected but never referenced in any formula (see `UD-01`).

### Components

None defined or used.

---

## 3. Findings

### 3.1 Delegation & data efficiency

No deterministic delegation findings were emitted by the script. Two delegation leads are judged in section 4 (L-04, L-07).

### 3.2 Performance

No deterministic performance findings were emitted by the script. Three performance leads are judged in section 4 (L-01, L-02, L-03).

### 3.3 Redundancy & reuse

---

#### DC-01 — Medium | Confirmed
**Duplicate controls** — `lblSame` and `lblWelcome` are copy-paste duplicates with an identical control type and property set.

- **Location:** `DetailScreen` → `lblSame` (`src/DetailScreen.pa.yaml:13`); `HomeScreen` → `lblWelcome` (`src/HomeScreen.pa.yaml:15`)
- **Evidence:**
  ```
  // src/DetailScreen.pa.yaml:16
  Text: =Concatenate("Hello ", gblUser, " welcome to the application dashboard")
  // src/HomeScreen.pa.yaml:18
  Text: =Concatenate("Hello ", gblUser, " welcome to the application dashboard")
  ```
- **Why it matters:** Duplicate controls create silent drift — updating one without the other produces inconsistent UX. As the app grows, the maintenance cost compounds.
  *Citation: coding-standards-and-performance.md §2 "Duplicate / redundant controls" + §5 "Components & reuse" — https://learn.microsoft.com/power-apps/maker/canvas-apps/working-with-large-apps*
- **Remediation:** Extract this label into a Canvas Component with an `InputText` property for the greeting text, and replace both occurrences with component instances.

---

#### XD-01 — Medium | Confirmed
**Exact-duplicate formula** — the `Concatenate` greeting formula appears verbatim in two controls across two screens.

- **Location:** `DetailScreen` → `lblSame.Text` (`src/DetailScreen.pa.yaml:16`); `HomeScreen` → `lblWelcome.Text` (`src/HomeScreen.pa.yaml:18`)
- **Evidence:**
  ```powerfx
  =Concatenate("Hello ", gblUser, " welcome to the application dashboard")
  ```
- **Why it matters:** Any change (e.g. wording update) must be made in two places; it is easy to miss one. Named formulas in `App.Formulas` eliminate this.
  *Citation: coding-standards-and-performance.md §2 "Split long formulas / duplicated formulas" — https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-optimization*
- **Remediation:** Create a named formula in `App.Formulas`, e.g. `fmlGreeting = Concatenate("Hello ", gblUser, " welcome to the application dashboard")`, and reference `fmlGreeting` in both labels.

> Note: DC-01 and XD-01 describe the same pair of controls from different lenses (structural duplication vs. formula duplication). Both remediation paths converge on componentization or a named formula.

---

### 3.4 Maintainability & naming

---

#### DN-01 — Medium | Confirmed
**Default control name** — `Gallery1` on DetailScreen uses a default auto-generated name.

- **Location:** `DetailScreen` → `Gallery1` (`src/DetailScreen.pa.yaml:4`)
- **Evidence:** `Gallery1 (Gallery)`
- **Why it matters:** Default names make the formula bar unreadable and leave the control's purpose opaque.
  *Citation: coding-standards-and-performance.md §1 "Control names — 3-char type prefix" — https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-readability*
- **Remediation:** Rename to `galOrderDetail` (or a similar intent-expressing name with the `gal` prefix per the abbreviation table).

---

#### DN-02 — Medium | Confirmed
**Default control name** — `Button2` on HomeScreen uses a default auto-generated name.

- **Location:** `HomeScreen` → `Button2` (`src/HomeScreen.pa.yaml:10`)
- **Evidence:** `Button2 (Classic/Button)`
- **Why it matters:** Same as DN-01. The `Navigate` in its `OnSelect` makes the intent "go to details" — the name should encode that.
  *Citation: coding-standards-and-performance.md §1 "Control names" — https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-readability*
- **Remediation:** Rename to `btnGoToDetail`.

---

### 3.5 Dead / unused

---

#### OS-01 — Medium | Potential — needs verification
**Orphan screen** — `OrphanScreen` is never targeted by any `Navigate()` call and is not the start screen.

- **Location:** `src/OrphanScreen.pa.yaml:1`
- **Evidence:** `screen 'OrphanScreen'` — no Navigate edge points to it in the navigation graph.
- **Why it matters:** Dead screens inflate app package size and confuse maintainers. Rated "Potential" because a screen could theoretically be reached via a variable holding the screen reference (`Navigate(varTargetScreen, ...)`); the static source cannot confirm total absence of runtime paths.
  *Citation: coding-standards-and-performance.md §3 "Dead / unused" — https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-readability*
- **Remediation:** Confirm with the original developer that no dynamic navigation reaches `OrphanScreen`. If confirmed unreachable, delete it (and `lblOrphan` with it).

---

### 3.6 Per-control unreferenced verdicts (UR-*)

The script detected 7 controls never referenced by any other formula. All 7 carry verdict `likely-decorative-or-layout` — each is visible and/or has a live event handler or surfaced data. They must not be dismissed as a batch; each is reported individually below.

---

**UR-01 — Low | Potential** — `lblSame` (DetailScreen, `src/DetailScreen.pa.yaml:13`)
Verdict: `likely-decorative-or-layout` — visible label that surfaces data via its `Text` formula.
Recommendation: Intentional greeting display. Given DC-01/XD-01, it should be replaced by a component instance rather than deleted.

**UR-02 — Low | Potential** — `Gallery1` (DetailScreen, `src/DetailScreen.pa.yaml:4`)
Verdict: `likely-decorative-or-layout` — visible gallery surfacing data via `Items`; also has a live `OnSelect` handler with the ForAll/LookUp pattern.
Recommendation: Verify with the original developer; it appears intentionally functional. Also address L-04 (delegation) and L-05 (N+1) on its `OnSelect`.

**UR-03 — Low | Potential** — `btnSave` (DetailScreen, `src/DetailScreen.pa.yaml:9`)
Verdict: `likely-decorative-or-layout` — visible button with a live `OnSelect` handler (`Patch`).
Recommendation: Intentional; no action needed on the UR itself. Address L-06 (missing error handling) on its `OnSelect`.

**UR-04 — Low | Potential** — `Button2` (HomeScreen, `src/HomeScreen.pa.yaml:10`)
Verdict: `likely-decorative-or-layout` — visible button with a live `Navigate` handler.
Recommendation: Intentional navigation control; keep but rename per DN-02.

**UR-05 — Low | Potential** — `lblWelcome` (HomeScreen, `src/HomeScreen.pa.yaml:15`)
Verdict: `likely-decorative-or-layout` — visible label surfacing data via `Text`.
Recommendation: Intentional greeting display. Address with the component/named-formula fix from DC-01/XD-01.

**UR-06 — Low | Potential** — `galOrders` (HomeScreen, `src/HomeScreen.pa.yaml:6`)
Verdict: `likely-decorative-or-layout` — visible gallery surfacing data via `Items`. Primary data surface on HomeScreen.
Recommendation: Intentional; address L-07 (delegation concern on `Filter(Orders, Status = "Open")`).

**UR-07 — Low | Potential** — `lblOrphan` (OrphanScreen, `src/OrphanScreen.pa.yaml:4`)
Verdict: `likely-decorative-or-layout` — visible label, but lives on the orphan screen (OS-01).
Recommendation: If OS-01 is confirmed dead, delete this control along with the screen.

---

### 3.7 Error handling & resilience

No deterministic error-handling findings were emitted. One error-handling lead is judged in section 4 (L-06).

---

## 4. Lead judgments (L-*)

### L-01 — Concurrent opportunity (Performance) — **Upgraded to finding**

**Formula:** `App.OnStart` (`src/App.pa.yaml:4`)
```powerfx
ClearCollect(colOrders, Orders);
ClearCollect(colCustomers, Customers);
```
Two independent `ClearCollect` calls run sequentially. Each waits for the prior SharePoint request to complete. Wrapping them in `Concurrent()` reduces startup time to the duration of the slower request. Neither call depends on the other's result — confirmed by inspection.
**Verdict:** Real finding. **Severity:** Medium | **Confidence:** Confirmed
*Citation: coding-standards-and-performance.md §2 "Concurrent for independent data calls" — https://learn.microsoft.com/power-apps/maker/canvas-apps/performance-tips*
**Remediation:**
```powerfx
Concurrent(
    ClearCollect(colOrders, Orders),
    ClearCollect(colCustomers, Customers)
);
```

---

### L-02 — Heavy App.OnStart (Performance) — **Upgraded to finding**

**Formula:** `App.OnStart` (`src/App.pa.yaml:4`)
```powerfx
=Set(gblUser, User().FullName);
ClearCollect(colOrders, Orders);
ClearCollect(colCustomers, Customers);
Set(unusedVar, 42);
Navigate(HomeScreen, ScreenTransition.None)
```
`User().FullName` is a static computed value that never changes during a session — it belongs in `App.Formulas` as a named formula, avoiding the Set overhead on every load. `unusedVar` is unused (UV-02) and should be removed.
**Verdict:** Real finding. **Severity:** Medium | **Confidence:** Confirmed
*Citation: coding-standards-and-performance.md §2 "App.OnStart overload → use App.Formulas" — https://learn.microsoft.com/power-apps/maker/canvas-apps/fast-app-page-load*
**Remediation:** Move `User().FullName` to `App.Formulas` as `fmlUserName = User().FullName`; remove `Set(unusedVar, 42)`; apply Concurrent from L-01; remove Navigate per L-03.

---

### L-03 — Navigate in App.OnStart (Performance) — **Upgraded to finding, severity elevated**

**Formula:** `App.OnStart` (`src/App.pa.yaml:4`, last statement)
```powerfx
Navigate(HomeScreen, ScreenTransition.None)
```
`Navigate()` inside `App.OnStart` blocks first screen render until the entire OnStart chain finishes. This app already declares `App.StartScreen = HomeScreen`, making the Navigate redundant and purely harmful.
**Verdict:** Confirmed finding. **Severity:** High | **Confidence:** Confirmed
*Citation: coding-standards-and-performance.md §2 "Navigate in App.OnStart → use App.StartScreen" — https://learn.microsoft.com/power-apps/maker/canvas-apps/fast-app-page-load*
**Remediation:** Remove the `Navigate(HomeScreen, ScreenTransition.None)` line from `App.OnStart`. The declarative `App.StartScreen = HomeScreen` already handles routing.

---

### L-04 — Delegation candidate: LookUp inside ForAll (Delegation & data efficiency) — **Potential finding**

**Formula:** `DetailScreen` → `Gallery1.OnSelect` (`src/DetailScreen.pa.yaml:8`)
```powerfx
=ForAll(colOrders, LookUp(Customers, Id = ThisRecord.CustId))
```
`LookUp(Customers, Id = ThisRecord.CustId)` calls a SharePoint data source. The outer `ForAll` iterates over `colOrders` (a local collection — no delegation concern on the outer loop). The `=` equality predicate on `Id` is delegable on SharePoint, so a single `LookUp` would delegate. However, calling it once per row inside `ForAll` is the N+1 pattern (L-05) and the per-row server calls are the primary concern.
**Verdict:** Kept as Potential (delegation is not the root problem here — the N+1 pattern is). **Severity:** Medium | **Confidence:** Potential — verify row count
*Citation: delegation.md §SharePoint — https://learn.microsoft.com/power-apps/maker/canvas-apps/connections/connection-sharepoint-online#power-apps-delegable-functions-and-operations-for-sharepoint*
**Remediation:** Wire up `colCustomers` (which is already populated in `App.OnStart` but never used — UC-01) and replace `LookUp(Customers, ...)` with `LookUp(colCustomers, ...)` for a fully local lookup.

---

### L-05 — N+1 network calls (Performance) — **Upgraded to finding**

**Formula:** `DetailScreen` → `Gallery1.OnSelect` (`src/DetailScreen.pa.yaml:8`)
```powerfx
=ForAll(colOrders, LookUp(Customers, Id = ThisRecord.CustId))
```
`LookUp(Customers, ...)` inside `ForAll(colOrders, ...)` fires one SharePoint round-trip per row of `colOrders`. If `colOrders` holds 50 orders, that is 50 network calls triggered by a single user interaction.
**Verdict:** Real finding. **Severity:** High | **Confidence:** Confirmed
*Citation: coding-standards-and-performance.md §2 "Select N+1 data queries" — https://learn.microsoft.com/power-platform/architecture/key-concepts/performance/top-issues*
**Remediation:** Replace with the already-loaded `colCustomers` collection: `ForAll(colOrders, LookUp(colCustomers, Id = ThisRecord.CustId))`. This collection is populated in `App.OnStart` but currently unused (UC-01); wiring it up here fixes both issues simultaneously.

---

### L-06 — Unhandled mutation: Patch without IfError (Error handling & resilience) — **Upgraded to finding**

**Formula:** `DetailScreen` → `btnSave.OnSelect` (`src/DetailScreen.pa.yaml:12`)
```powerfx
=Patch(Orders, Defaults(Orders), {Title: "x"})
```
`Patch` against a SharePoint list with no `IfError()` wrapper and no `Errors(Orders)` check. A failed write (throttling, permission error, network interruption) silently returns blank; the user receives no feedback and may believe the save succeeded.
**Verdict:** Real finding. **Severity:** Medium | **Confidence:** Confirmed
*Citation: coding-standards-and-performance.md §4 "Error handling & resilience" — https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-optimization*
**Remediation:**
```powerfx
IfError(
    Patch(Orders, Defaults(Orders), {Title: "x"}),
    Notify("Save failed: " & FirstError.Message, NotificationType.Error)
)
```

---

### L-07 — Delegation candidate: Filter on SharePoint Orders (Delegation & data efficiency) — **Potential finding**

**Formula:** `HomeScreen` → `galOrders.Items` (`src/HomeScreen.pa.yaml:9`)
```powerfx
=Filter(Orders, Status = "Open")
```
`Filter` on the SharePoint `Orders` list. The `=` equality predicate on a text column is delegable on SharePoint. However, if `Status` is a Choice column (common for status fields in SharePoint lists), delegation behavior depends on column configuration. If `Orders` grows beyond 500/2,000 rows, any non-delegable portion will silently truncate results.
**Verdict:** Kept as Potential — the formula pattern is delegation-compatible, but column type must be verified. **Severity:** Medium | **Confidence:** Potential — verify row count and column type
*Citation: delegation.md §SharePoint — https://learn.microsoft.com/power-apps/maker/canvas-apps/connections/connection-sharepoint-online#power-apps-delegable-functions-and-operations-for-sharepoint*
**Remediation:** (1) Confirm `Status` is a plain Text column — if it is a Choice column, validate delegation in Studio. (2) If `Orders` can grow beyond 2,000 rows, consider a SharePoint server-side view pre-filtered to "Open" status.

---

## 5. Remediation Backlog

Ranked by severity × confidence × rough effort. High/Medium items lead; Low long-tail is batched.

| Priority | Finding(s) | Action | Effort |
| --- | --- | --- | --- |
| 1 | **L-03** | Remove `Navigate(HomeScreen,...)` from `App.OnStart` | Trivial |
| 2 | **L-05** | Fix N+1: replace `LookUp(Customers,...)` inside ForAll with `LookUp(colCustomers,...)` | Small |
| 3 | **L-02** | Migrate `User().FullName` to `App.Formulas`; remove `Set(unusedVar, 42)` | Small |
| 4 | **L-01** | Wrap the two `ClearCollect` calls in `Concurrent(...)` | Trivial |
| 5 | **L-06** | Wrap `Patch` in `IfError` with `Notify` on failure | Small |
| 6 | **DC-01 + XD-01** | Extract greeting label to Canvas Component or `App.Formulas` named formula | Medium |
| 7 | **OS-01** | Confirm OrphanScreen unreachable; if so, delete it (UR-07 goes with it) | Small |
| 8 | **DN-01** | Rename `Gallery1` → `galOrderDetail` | Trivial |
| 9 | **DN-02** | Rename `Button2` → `btnGoToDetail` | Trivial |
| 10 | **L-07** | Verify `Status` column type on Orders list; verify row count | Investigation |
| 11 | **L-04** | Covered by #2 (wiring up colCustomers eliminates the per-row LookUp) | — |
| — | Low long-tail | Delete 2 unused variables (UV-01, UV-02) — see enumeration.md | Batch / Low |
| — | Low long-tail | Remove unused collection `colCustomers` once L-05 is fixed (UC-01) — see enumeration.md | Batch / Low |
| — | Low long-tail | Disconnect unused data source `Archive` (UD-01) — see enumeration.md | Batch / Low |
| — | Low long-tail | Fix variable prefix violations: rename `unusedVar` or remove it (VP-01, IN-01) — see enumeration.md | Batch / Low |
| — | Low long-tail | Extract 9 magic-value literals to named formulas (MV-01 through MV-09) — see enumeration.md | Batch / Low |

> **Hand-off note for implementing agent:** Start with items 1–5 (all in `App.OnStart` or `btnSave.OnSelect`) — they are load-time and reliability wins with minimal regression risk. Items 6–9 are pure rename/refactor. Items 10–11 require investigation before coding. The Low long-tail (enumeration.md) can be addressed in a separate cleanup sprint.
