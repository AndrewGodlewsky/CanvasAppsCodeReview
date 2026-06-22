# Coding Standards & Performance Reference — Canvas App Analyzer

> Authority for the **Performance**, **Redundancy & reuse**, **Maintainability & naming**,
> **Dead/unused**, and **Error handling** findings. Bundled inside the skill for reproducible,
> citable findings. **Re-verify against source URLs periodically.**
>
> Sources (verified current as of 2026-06):
> - Coding guidelines overview: https://learn.microsoft.com/power-apps/guidance/coding-guidelines/overview
> - Code readability (naming, comments): https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-readability
> - Code optimization: https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-optimization
> - Build large & complex canvas apps: https://learn.microsoft.com/power-apps/maker/canvas-apps/working-with-large-apps
> - Performance tips: https://learn.microsoft.com/power-apps/maker/canvas-apps/performance-tips
> - Fast (efficient) calculations: https://learn.microsoft.com/power-apps/maker/canvas-apps/efficient-calculations
> - Fast app/page load: https://learn.microsoft.com/power-apps/maker/canvas-apps/fast-app-page-load
> - Select N+1 / top performance issues: https://learn.microsoft.com/power-platform/architecture/key-concepts/performance/top-issues
> - Power CAT Toolkit (the human equivalent of this skill): referenced by the coding guidelines overview

---
## 1. Naming & maintainability (high-confidence, mechanical)

### Casing
- **Controls & variables:** camelCase. **Data sources:** PascalCase (name inherited from connector,
  e.g., `Office365Users` — usually not changeable, so don't flag data source casing).

### Control names — 3-char type prefix + purpose (camelCase), e.g. `lblUserName`, `galOrders`
Default names like `Button1`, `Gallery3`, `Label2`, `Screen2` are **maintainability findings** (Confirmed).
Abbreviation table (from docs):

| Control | Abbr | Control | Abbr | Control | Abbr |
| --- | --- | --- | --- | --- | --- |
| Badge | bdg | Form | frm | Rating | rtg |
| Button | btn | Gallery | gal | Rich text editor | rte |
| Camera | cam | Group | grp | Shapes | shp |
| Canvas | can | Header | hdr | Slider | sld |
| Card | crd | Html text | htm | Tab List | tab |
| Charts | chr | Icon | ico | Table | tbl |
| CheckBox | chk | Image | img | Text input | txt |
| Collection | col | Info Button | info | Timer | tmr |
| Combo box | cmb | Label | lbl | Toggle | tgl |
| Component | cmp | Link | lnk | Video | vid |
| Container | con | List box | lst | Progress Bar | pbar |
| Dates | dte | Microphone | mic | Pen Input | pen |
| Drop down | drp | Power BI Tile | pbi | Page section shape | sec |

- **Control names must be unique across the whole app.** A control reused across screens should carry a
  **screen suffix**, e.g. `galBottomNavMenuHS` ("HS" = Home Screen).

### Variables & collections
- **Context (local) variables:** prefix `loc` (e.g., `locSuccessMessage`).
- **Global variables:** prefix `gbl` (e.g., `gblFocusedBorderColor`).
- **Collections:** prefix `col` (e.g., `colUserOrders`).
- **Scope (`With`) variables:** prefix `scp`.
- camelCase; meaningful names. **Flag cryptic/generic names**: `temp`, `var1`, `EID`, `dSub`, `cFV`,
  `hideNxtBtn`. Prefer `EmployeeId`, etc.
- Context & global vars may share a name — flag collisions (forces the disambiguation operator).

### Inconsistent naming (IN) — scoped to variable/collection prefix consistency
When an app uses the naming convention (e.g., `gbl` prefix for globals) in *some* names but not
others within the same category, this is a category-level inconsistency that makes the codebase
harder to audit and maintain — you cannot reliably search for "all global variables" by prefix.

**Detector scope (deliberately narrow to avoid false positives):**
- Applies only to three variable/collection categories: **global variables** (`gbl` prefix),
  **context variables** (`loc` prefix), and **collections** (`col` prefix).
- Controls are explicitly excluded — control prefix conventions are fuzzier and control over
  naming is less consistent, so applying IN to controls would produce false positives.
- IN fires for a category only when it has **at least one compliant member** (correct prefix)
  AND **at least one violating member** (missing prefix). An all-violating category is already
  fully covered by VP (instance-level findings); an all-compliant category is fine.
- Emits **one IN finding per inconsistent category** (category-level), while VP emits one
  finding per violating instance (instance-level). Both detectors may fire on the same app
  — that is correct and intentional (different lenses for the same underlying issue).
- Severity: **Low**. Tier: **enumeration**. Confidence: **Confirmed**.
- Citation: coding-standards-and-performance.md section 1 (Naming & maintainability) —
  https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-readability

### Screen names
- End with the word "Screen"; plain language; spaces OK; avoid abbreviations (screen readers announce
  them — accessibility). Flag `Home`, `LoaderScreen`, `EmpProfDetails` style names.

### Comments
- Power Apps **strips all comments** at package build — they cost nothing at runtime. So "too few
  comments on complex formulas" is a legitimate maintainability finding; comment volume is never a
  performance problem. Encourage `//` and `/* */` on non-obvious logic.

#### Distinguishing commented-out code from explanatory comments
- **Explanatory / prose comments** (e.g. `// Submit the order to the back end`) are **encouraged** on
  complex formulas and must NOT be flagged. They document intent and help future maintainers.
- **Commented-out code** (e.g. `// Patch(Orders, Defaults(Orders), {Title: "x"});`) is a
  maintainability finding (**CC**, Low). Source control already preserves history; leaving dead code
  commented out adds noise, confuses readers, and may cause stale references. **Remove it.**
- **Heuristic to distinguish them:** a comment is treated as commented-out code when its text contains
  a function call pattern (`Identifier(`) OR one of the code characters `;`, `{`, `}`.
  Pure prose (natural-language text without these markers) is NOT flagged.
- The CC detector operates on the **code spans** of each formula (string literals are blanked out
  first), so `//` inside a URL string literal is never mis-classified.
- This distinction also applies to the MC (missing-comments) detector: CC and MC must not contradict
  each other. A formula that has explanatory prose comments does NOT fire CC; a complex formula that
  lacks any comment MAY fire MC. Both findings are consistent with the guidance above.

### Stub/empty event handlers
- An event property (`OnSelect`, `OnChange`, `OnVisible`, `OnStart`, etc.) whose formula is literally
  `false` is a **stub handler** — the maker left the Power Apps Studio default in place without wiring
  up real logic. It is inert at runtime but signals unfinished work and can mislead future maintainers
  into thinking the control responds to the event.
- **Flag (`EH`, Low, Confirmed):** any property whose name matches `^On[A-Z]` and whose formula text,
  after stripping the leading `=` and trimming whitespace, equals `false` (case-insensitive).
- Truly-blank handlers (the property omitted entirely) are already excluded from the YAML source by
  the Power Apps Studio parser and are out of scope for this check.
- Source: general maintainability guidance —
  https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-readability

### Formula formatting
- Long unformatted single-line formulas are a readability finding; the **Format text** command (or line
  breaks + indentation) is the fix.

---
## 2. Performance (mix of Confirmed and Potential)

### App.OnStart overload → use App.Formulas (named formulas)  [HIGH-VALUE]
- Moving static `Set`/`Collect` initialization out of **App.OnStart** into **named formulas in
  App.Formulas** has cut Studio load time by **up to 80%**. Named formulas are **immutable, independent,
  and lazily evaluated** (computed just-in-time when first needed).
- **Flag:** heavy `App.OnStart` (many `Set`/`Collect` statements, especially static values that never
  change). Recommend migrating non-mutated initializations to `App.Formulas`. Keep `Set` only for state
  that genuinely changes. (Named formulas can't be `Set` or mutated.)

### Navigate in App.OnStart → use App.StartScreen  [Confirmed]
- A `Navigate` anywhere in `App.OnStart` (even inside a rarely-hit `If`) forces the **entire** OnStart to
  finish before the first screen renders. Replace with the declarative **App.StartScreen**, e.g.
  `App.StartScreen = If(Param("AdminMode")="1", AdminScreen, HomeScreen)`.
- Caveat to note in remediation: avoid `StartScreen` depending (even transitively, via a named formula)
  on a global set in `OnStart` — race condition.

### Select N+1 data queries  [Potential — high impact]
- **Pattern:** a `LookUp`/`Filter`/data-source call evaluated **per row** of a gallery or `ForAll`
  (e.g., for each truck, look up its driver). Generates one network call per row → very slow loads.
- **Fix:** batch up front with a single `Collect`/`ClearCollect`, then read the local collection; or
  reshape the data at the source (view/related columns); ensure queries are delegable.
- Also covers cross-screen references that re-pull data.

### Concurrent for independent data calls  [Potential]
- Sequential `;`-chained data calls wait for the **sum** of request times; `Concurrent(...)` waits only
  for the **longest**. **Flag** OnStart/OnVisible with multiple independent `ClearCollect`/connector
  calls chained sequentially → recommend `Concurrent`. Caveat: only for calls with **no dependencies**
  on each other; over-use can cause throttling.

### Split long formulas / duplicated formulas  [Confirmed → Redundancy]
- Formulas over ~**256,000 characters** strain Studio (worst apps exceed 1M). Copy-pasting a control
  **duplicates its formulas silently**. Split into reusable **named formulas** / `With` subexpressions.
- **Redundancy findings:** identical formula text repeated across controls/screens → extract to a named
  formula or a **component**; duplicated control/screen layouts → componentize.

### Duplicate / redundant controls  [Confirmed → Redundancy]
- Two or more controls of the **same type** with a **near-identical property set** are almost certainly
  copy-paste duplicates. They cause silent drift — the maker updates one but forgets the other —
  leading to inconsistent UX and compounding maintenance cost.
- **Flag (`DC`, Medium, Confirmed):** group controls by a signature built from `type` + sorted
  `propName=normalizedText` pairs (whitespace-collapsed). Any group with two or more members is a
  redundancy finding. Emit **one finding per group** listing all member controls.
- **Fix:** extract the repeated layout into a **Canvas Component** with input properties for the
  parts that differ, then replace each duplicate with a component instance.
- Source: section 2 above (split long / duplicated formulas) + section 5 (Components & reuse) —
  https://learn.microsoft.com/power-apps/maker/canvas-apps/working-with-large-apps

### With function  [Maintainability/Redundancy]
- `With` creates self-contained, scoped named values to break up complex formulas — preferred over
  context/global variables when a value is only needed locally. Recommend for deeply nested expressions.

### Overuse of globals (OG, lead)  [Maintainability & naming]
- An app with many global variables (`Set`) is a maintenance burden: globals survive across screens,
  making data-flow hard to reason about, and they all initialise in `App.OnStart` (load-time cost).
- **Alternatives to consider per variable:**
  - **`UpdateContext`** (context variable, `loc` prefix) — screen-scoped; reset on each `Navigate`.
    Prefer when a variable is only read/set on one screen.
  - **Named formula in `App.Formulas`** — immutable, lazily evaluated; no `Set` needed. Prefer for
    static computed values (user display name, environment label, etc.).
  - **`With`** — single-formula scope; no variable declaration at all.
- **Flag (`OG`, lead `L-NN`):** when the count of distinct globals exceeds `$T_GlobalOveruse`
  (default 20, override `CAA_GLOBAL_OVERUSE`), emit one app-level lead. The model judges each
  variable and recommends the best alternative. Not all globals are replaceable — stateful flags
  (`gblBusy`, `gblSelected`) legitimately belong in global scope.
- Source: §2 "App.OnStart -> App.Formulas" and "With function" above.

### Deep If/Switch nesting (`DI`, Medium, Confirmed)
- Deeply nested `If`/`Switch` calls (e.g. `If(A, x, If(B, y, If(C, z, If(D, w, v))))`) are a
  readability and maintainability finding. Each additional nesting level forces the reader to hold
  more mental context simultaneously and makes future edits error-prone.
- **Flag (`DI`, Medium, Confirmed, tier: narrative):** any formula whose maximum `If`/`Switch`
  nesting depth in its **code span** (string-literal content excluded) meets or exceeds the
  `$T_DeepIfDepth` threshold (default 4). Power Fx allows optional whitespace between the keyword
  and `(`, so both `If(` and `If (` are counted.
- **Fix:** break the nested chain into a `With` scoped expression, a `Switch` on a shared
  condition, or named formulas (`App.Formulas`) that name each sub-result — whichever best
  communicates intent. Each named value can carry a comment explaining its role.
- Source: §2 "With function" (Maintainability/Redundancy) above +
  https://learn.microsoft.com/power-apps/maker/canvas-apps/efficient-calculations

### Other performance levers (lower-frequency)
- **Explicit Column Selection** (on by default for new apps) + "only fetch needed columns" — pulling wide
  tables with unused columns is a payload finding.
- **Enhanced performance for hidden controls** (default since Dec 2022): controls not initially visible
  aren't rendered — note if an old app predates/disabled it.
- **Permanently hidden controls (`HC`, Low, Confirmed):** a control whose `Visible` property formula
  is the literal `false` is _never_ rendered. If intentional (e.g. a placeholder under construction),
  document the reason in a comment on that formula. If unintentional, either wire up a dynamic
  visibility expression or remove the control entirely — leaving it in increases app package size and
  can confuse future maintainers. This is a general maintainability concern; see
  https://learn.microsoft.com/power-apps/maker/canvas-apps/performance-tips for the hidden-control
  rendering optimisation context.
- **Defer significant updates** to a non-blocking UI step (progress signal) rather than blocking the user.
- **Data sources:** Dataverse fastest (bypasses API Management); Excel connector caps at 2,000 records and
  is not a relational DB — flag Excel-as-database for transactional apps.

### Dead conditional branches
- An `If` call whose **first argument is the literal `true` or `false`** (not a variable or expression)
  has a **permanently dead branch**. `If(false, A, B)` always evaluates to `B`; `If(true, A, B)` always
  evaluates to `A`. The dead branch adds noise, misleads maintainers, and can hide logic that was never
  intended to be disabled this way.
- **Flag (`DB`, Low, Confirmed):** any formula (using code spans — string-literal content is excluded)
  that matches `\bIf\s*\(\s*(false|true)\b` (case-insensitive). Emit one finding per formula, noting
  the count of dead branches. Do NOT flag dynamic conditions such as `If(gblFlag, ...)` or
  `If(someVar = 1, ...)`.
- Source: code optimization / general coding guidelines —
  https://learn.microsoft.com/power-apps/guidance/coding-guidelines/code-optimization

---
## 3. Dead / unused (high-confidence, mechanical)
Flag (via reference counting across all `.pa.yaml`):
- Global/context variables `Set`/`UpdateContext` but never read.
- Collections built but never referenced.
- Controls never referenced by any formula AND not user-visible/interactive (judgment for pure layout).
- **Data sources** present in `\DataSources` but never referenced in any formula.
- Screens never targeted by any `Navigate(...)` and not the start screen (orphan screens).

---
## 4. Error handling & resilience  [Potential]
- `Patch`/`Collect`/`Remove` calls with no surrounding error handling — recommend `IfError(...)` and/or
  checking `Errors(datasource)` after the operation, with user-facing messages (column-level messages
  near the field; record-level near the Save button).
- Network/data operations assuming success; no `IfError` on risky expressions.
- Note: error handling is partly a judgment call (some operations are low-risk) — tag confidence accordingly.

---
## 5. Components & reuse

### Custom components — define once, use everywhere
- Canvas app **components** (`ComponentDefinitions:` / `Type: CanvasComponent`) allow reusable UI
  blocks to be defined once and instantiated on multiple screens. They reduce duplication, enforce
  visual consistency, and cut formula-maintenance cost.
- **Flag: defined but never used (`UK`).** A component file that exists in `\Src\Components\` but
  is never instantiated on any screen is dead code — it increases app package size and confuses
  future maintainers. Either instantiate it or delete it.
- **Flag: missing component opportunities (`UP`).** Identical or near-identical control subtrees on
  multiple screens should be extracted into a component (mirrors the XD / near-dup pattern at the
  control level).
- Sources:
  - Build large & complex canvas apps (components section):
    https://learn.microsoft.com/power-apps/maker/canvas-apps/working-with-large-apps
  - Create a component: https://learn.microsoft.com/power-apps/maker/canvas-apps/create-component

### God screens — decompose oversized screens

A screen that accumulates too many controls or too much formula weight is a **god screen**: a single
screen that does too much, making it hard to navigate in Power Apps Studio, difficult to maintain,
and slow to load (Power Apps loads all controls on a screen before it renders).

**Thresholds (configurable):**
- `controlCount > 40` (env override: `CAA_GOD_SCREEN_CONTROLS`) — too many controls signals that
  the screen handles too many concerns and should be split or componentized.
- `formulaBytes > 20000` (env override: `CAA_GOD_SCREEN_BYTES`) — excessive formula weight on a
  single screen hints at logic that should move to `App.Formulas` named formulas or to components.

**Fix:**
- Decompose into **Canvas Components**: extract repeated control groups into reusable components
  with input properties, then replace the controls with component instances on each screen.
- Use **nested galleries or containers** to group related controls, reducing top-level control count.
- Move shared logic to **App.Formulas** named formulas so formula weight is not duplicated per screen.
- Split concerns across multiple screens if the screen genuinely serves multiple user tasks.

**Flag (`GS`, Medium, Confirmed, tier: narrative):** emit one finding per screen that exceeds either
threshold. Location is the screen; evidence states the control count and formula byte count.

**Authority:** Build large & complex canvas apps:
https://learn.microsoft.com/power-apps/maker/canvas-apps/working-with-large-apps

---
## 6. Environment-specific values (High severity — breaks on deployment)

### Use environment variables, not hardcoded URLs or GUIDs

Hardcoding environment-specific values — absolute URLs, site paths, tenant GUIDs, SharePoint or
Dynamics 365 hostnames — is one of the most common causes of apps that work in development but
silently break when moved to a test or production environment.

**What to avoid:**
- Absolute HTTP/HTTPS URLs (e.g. `"https://contoso.sharepoint.com/sites/ProdSite"`)
- Tenant or record GUIDs (e.g. `"xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"`)
- Environment-specific SharePoint hostnames (`.sharepoint.com`, `.sharepoint.test`)
- Dynamics 365 / Dataverse org URLs (`.crm.dynamics.com`, `.crm4.dynamics.com`, etc.)

**Fix:** Replace every hardcoded environment-specific value with a **Power Apps environment
variable** (`Environment()` function or a named formula backed by an environment variable record).
Environment variables are promoted automatically by solution deployments and can be set per
environment without touching the app itself.

**Flag (`EV`, High, Confirmed, tier: narrative):** any string literal in a formula that matches
an absolute URL (`https?://`), a GUID pattern, or an environment-specific hostname
(`.sharepoint.com/.sharepoint.test`, `.crm*.dynamics.com`). Emit one finding per occurrence.

**Note:** an `EV` finding and an `MV` (magic-value) finding may both fire on the same string
literal — that is intentional. They address different concerns: `MV` (Low) flags any unexplained
literal; `EV` (High) flags the specific deployment-breaking risk.

**Authority:** Microsoft Power Platform ALM — environment variables guidance:
https://learn.microsoft.com/power-apps/maker/data-platform/environmentvariables

---
## 7. Tooling cross-reference
The **Power CAT Toolkit** is Microsoft's own code-review tool implementing much of this guidance (App
Checker / Solution Checker likewise). Where useful, the report can note that a finding aligns with what
those tools flag — reinforces that findings reflect Microsoft's own standards, not just model opinion.
