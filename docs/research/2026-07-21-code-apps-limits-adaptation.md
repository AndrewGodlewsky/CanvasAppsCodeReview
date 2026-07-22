# Power Platform Code Apps: Hard Limits, Constraints, and the Pro-Code Adaptation Cost

## Question

For a pro-code developer at a Fortune 500 deciding between **Power Apps code apps** (React/TypeScript SPA + Power Apps SDK, hosted in Power Platform) and **full pro-code** (React + own backend on Azure): what do you give up with code apps, what are the documented hard limits, and how does the day-to-day change? This is the unsparing cons list, sourced only to primary Microsoft material (learn.microsoft.com, the official Power Platform blog, and microsoft/PowerAppsCodeApps).

Status anchors used throughout:
- Code apps reached **General Availability on 5 February 2026** ([Power Platform Blog, "Generally available: host and run code apps in Power Apps"](https://www.microsoft.com/en-us/power-platform/blog/power-apps/generally-available-host-and-run-code-apps-in-power-apps/)).
- Client library `@microsoft/power-apps` is at **v1.2.2**; the **npm-based CLI is still labelled "(preview)"** even post-GA, and the older `pac code` CLI is documented as "deprecated in a future release" ([client library reference](https://learn.microsoft.com/javascript/api/powerapps-sdk-node/power-apps-client-lib-code-apps?view=powerapps-js-latest); [npm CLI quickstart](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/npm-quickstart)).
- Docs reviewed are current (they reference December 2025 browser Local Network Access changes and a December 2025 CLI v1.51.1), so nothing below is stale as of 2026-07-21 — but the preview/GA split *inside* the toolchain is a live risk (see Q6).

---

## TL;DR (decision-relevant)

1. **No mobile, no offline, no Windows app, ever-present in a browser.** Code apps are **not supported in Power Apps Mobile** (Microsoft: "in our backlog … with no current ETA or plan") or **Power Apps for Windows**, and the default Content Security Policy sets `worker-src 'none'`, which blocks service workers — the mechanism a PWA/offline app needs. These are architectural, not cosmetic. ([Discussion #286](https://github.com/microsoft/PowerAppsCodeApps/discussions/286); [overview#limitations](https://learn.microsoft.com/power-apps/developer/code-apps/overview#limitations); [CSP defaults](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/content-security-policy))
2. **There is no server-side code.** Your "backend" is connectors (1,500+), Dataverse, Power Automate flows, and custom connectors wrapping Azure Functions/APIs. All business logic that can't live in the browser must be pushed into one of those, and every call is a governed Power Platform Request counted against a **per-user 24-hour quota (40,000 for Premium, 6,000 for per-app)**. ([architecture](https://learn.microsoft.com/power-apps/developer/code-apps/architecture); [request limits](https://learn.microsoft.com/power-platform/admin/api-request-limits-allocations))
3. **You inherit canvas-app delegation limits.** Data access is not direct SQL/DB — it goes through the connector/Dataverse tabular runtime. Non-delegable queries silently cap at **500 rows (configurable up to 2,000)**; aggregates cap at **50,000 rows**; `FirstN` is unsupported; there is **no documented multi-row transaction/batch API**. ([delegation overview](https://learn.microsoft.com/power-apps/maker/canvas-apps/delegation-overview); [Dataverse delegable functions](https://learn.microsoft.com/power-apps/maker/canvas-apps/connections/connection-common-data-service#power-apps-delegable-functions-and-operations-for-dataverse))
4. **The default CSP is locked down hard.** `connect-src 'none'` means every external API or telemetry endpoint (including App Insights) must be explicitly allow-listed by an environment admin; `frame-ancestors 'self' https://*.powerapps.com` restricts embedding to Power Apps by default. Custom npm packages are fine *until* they phone home to a non-allow-listed host. ([CSP](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/content-security-policy))
5. **Telemetry has a blind spot and there are no env vars.** App Insights works, but only *after* the app loads — startup/initialization failures appear only in Power Platform Monitor. **Environment variables are not supported**, so per-environment secrets/keys must be stored in Dataverse. ([App Insights how-to](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/set-up-azure-app-insights))
6. **ALM is Power Platform-flavoured.** No Git integration, no solution packager, no source-code integration; you deploy via Pipelines and connection references. The React code lives in *your* repo, but the platform metadata (`power.config.json`, generated services) is not part of Power Platform's own ALM. ([ALM for code apps](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/alm); [overview#limitations](https://learn.microsoft.com/power-apps/developer/code-apps/overview#limitations))
7. **Lock-in is asymmetric: UI ports cleanly, the data/integration layer is a rewrite.** Your Vite/React/TS front end is standard and portable. What you'd rewrite leaving the platform: every `@microsoft/power-apps` SDK call and generated `*Service.ts` file, Entra auth (handled invisibly by the host today), hosting, and all connector/Dataverse access. ([architecture](https://learn.microsoft.com/power-apps/developer/code-apps/architecture))
8. **Microsoft never publishes an explicit "don't use code apps" page** — but the limitations list *is* the guidance. If you need a native mobile app, offline, deep OS integration, custom domains, or you object to per-end-user Power Apps Premium licensing, code apps are the wrong tool. ([overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview))

Legend for each finding: **(a)** documented hard limit · **(b)** preview-status gap that may close · **(c)** inherent architectural constraint unlikely to ever change.

---

## Q1. Documented limitations / considerations (mid-2026)

**The canonical "Limitations" list** ([overview#limitations](https://learn.microsoft.com/power-apps/developer/code-apps/overview#limitations)) — verbatim scope:

- **(a/c) No IP-based access restriction on the app assets.** "The compiled app assets are served from a publicly accessible endpoint that doesn't support IP-based restrictions today." SAS IP Binding / Firewall environment settings don't apply. Microsoft's mitigation is Entra Conditional Access "block by location," not network ACLs. Corollary guidance: **"Don't store sensitive user or organizational data in the app"** — put it in a data source retrieved post-auth. ([system configuration](https://learn.microsoft.com/power-apps/developer/code-apps/system-limits-configuration))
- **(a) No Power Platform Git integration.**
- **(a/c) Not supported in Power Apps for Windows.**
- **(b) No Power BI data integration** (`PowerBIIntegration` function). Code apps *can* be embedded in Power BI reports via the Power Apps visual, but can't consume Power BI data. ("don't yet support" → flagged preview-gap.)
- **(a) No SharePoint forms integration.**

**Mobile** — separately and explicitly: code apps **do not run in the Power Apps Mobile player**. Users must open a browser URL. Microsoft maintainer (eschavez) on the GA-era discussion: *"Mobile player is not something that we support at this time … It is in our backlog of items with no current ETA or plan."* A community reply calls this "one of the major blocker[s] to move out of Canvas Apps in favor of Code Apps." **(b, but effectively (c) today.)** ([Discussion #286](https://github.com/microsoft/PowerAppsCodeApps/discussions/286))

**ALM limitations** ([ALM how-to](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/alm)): code apps **don't support the solution packager** and **don't support source-code (Git) integration**.

**Host/browser constraints:**
- **(c) Single-Page Applications only.** "Code apps support Single-Page Applications (SPAs)." ([architecture](https://learn.microsoft.com/power-apps/developer/code-apps/architecture))
- **(c) The app always runs inside the Power Apps host**, which "manages end-user authentication, app loading, and presenting contextual messages … if an app fails to load." You don't control the load shell. ([architecture#runtime](https://learn.microsoft.com/power-apps/developer/code-apps/architecture#runtime))
- **(a) A Power Apps header/nav bar is injected by the host** when the app plays; you can only suppress it with a `?hideNavBar=true` query-string param on the share URL. ([system configuration](https://learn.microsoft.com/power-apps/developer/code-apps/system-limits-configuration))
- **Custom domains:** not offered. Apps are served from `https://apps.powerapps.com/play/e/{environmentId}/a/{appId}`. No documented custom-domain capability. **(a — absence documented by omission; see Gaps.)**

**App size limit:** the dedicated "System configuration" page documents only hosting behavior and the `hideNavBar` param — it publishes **no hard app/bundle size limit, and no SSR support (SPA only)**. Treated as a documentation gap below, not as "unlimited."

---

## Q2. Backend constraints — there is no server-side code

**Architectural fact:** a running code app has exactly three logical parts — *your code*, the `@microsoft/power-apps` client library, and the *Power Apps host*. None of them is your server. ([architecture#runtime](https://learn.microsoft.com/power-apps/developer/code-apps/architecture#runtime)) **(c)** Any logic that must not run in the browser has to be relocated to one of these documented patterns:

- **Standard connectors** (1,500+), called directly from JavaScript via generated typed services. All connectors are supported *except* **Excel Online (Business)** and **Excel Online (OneDrive)**. ([connect-to-data](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-data))
- **Dataverse** (CRUD + delegable Filter/Sort/Top + paging). ([connect-to-dataverse](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-dataverse))
- **Power Automate flows** — but only **Manual flows using the PowerApps trigger**. Scheduled/automated/other-trigger flows "aren't supported and don't function correctly." Flows must be **solution-aware**; flow-definition changes require re-running `add-flow` (no auto-detect); commands are **npm-CLI only** (not in `pac code`). ([add flows](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/add-flows)) **(a)**
- **Custom connectors wrapping Azure Functions / your own APIs** — this is the sanctioned way to run real server-side business logic. Microsoft's own Azure Functions guidance frames the split: "You write the business logic; the connector platform handles webhook registration, OAuth flows, token refresh, and retry." Note that **Connectors-in-Azure-Functions is itself in public preview**. ([Use connectors in Azure Functions](https://learn.microsoft.com/azure/azure-functions/functions-connectors-overview)) **(b for that specific integration; the general custom-connector path is GA.)**

**Latency / limits that apply to connector calls:**

- **Power Platform Requests (PPR), per user, 24-hour sliding window:** **40,000** for a standard paid Power Platform/Premium license; **6,000** for Power Apps per-app / M365-with-Power-Platform / pay-as-you-go. In Power Apps, PPR = "All API requests to connectors and Microsoft Dataverse." Exceeding it throttles the user (capacity add-ons buy +50,000 each). ([request limits & allocations](https://learn.microsoft.com/power-platform/admin/api-request-limits-allocations); [licensed user request limits](https://learn.microsoft.com/power-platform/admin/api-request-limits-allocations#licensed-user-request-limits)) **(a)**
- **Connector-level throttling** is per-connector on top of PPR; hitting it returns **HTTP 429 "Rate limit is exceeded."** ([understand limits](https://learn.microsoft.com/power-automate/guidance/coding-guidelines/understand-limits#api-throughput-limits-on-connectors)) **(a)**
- **Custom connector limits (Power Apps):** **50 custom connectors per user**; **10,000 requests/min per connection**; **max request content-length to the gateway ≈ 3,182,218 bytes (~3 MB)**; the OpenAPI/Postman definition file must be < 1 MB. ([custom connector FAQ](https://learn.microsoft.com/connectors/custom-connectors/faq)) **(a)**
- **Flow call payload/timeout** (when a code app invokes a flow): synchronous request timeout **120 seconds**; message size **100 MB** (1 GB only where chunking is supported). Long operations must go async — which a synchronous SPA call can't wait on. ([Power Automate limits](https://learn.microsoft.com/power-automate/limits-and-config#request-limits)) **(a)**
- **Dataverse service protection API limits** apply independently, evaluated per user. ([Dataverse API limits](https://learn.microsoft.com/power-apps/developer/data-platform/api-limits)) **(a)**

**Practical read:** there is no place to put a millisecond-latency, high-throughput, transactional, or long-running (>120s sync) server operation *inside* the code-app boundary. That work goes to Azure behind a custom connector — at which point you're maintaining an Azure backend anyway, just reached through the connector runtime instead of directly.

---

## Q3. Data access constraints vs. direct database access

**You never get a direct DB connection.** Access is mediated by the connector/tabular runtime, so canvas-app query semantics apply:

- **Delegation.** Code apps' Dataverse support explicitly covers delegation for **`Filter`, `Sort`, `Top`, and paging** — and *only* those. ([connect-to-dataverse#supported-scenarios](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-dataverse#supported-scenarios)) Anything non-delegable falls back to a client-side row cap: **records past 500 (default; configurable up to 2,000) are silently dropped** — "the formula doesn't return record 501 or higher, even if it matches the criteria." ([delegation overview](https://learn.microsoft.com/power-apps/maker/canvas-apps/delegation-overview#examples)) **(c)**
- **Aggregates and edge functions (Dataverse):** aggregate functions limited to **50,000 rows**; `FirstN` **not supported**; the `In` operator is subject to Dataverse's **15-table query limit**; `UpdateIf`/`RemoveIf` simulate delegation only to the 500/2,000 cap. ([Dataverse delegable functions](https://learn.microsoft.com/power-apps/maker/canvas-apps/connections/connection-common-data-service#power-apps-delegable-functions-and-operations-for-dataverse)) **(a)**
- **Transactions / batch:** the documented Dataverse operations for code apps are single-record **Create / Retrieve / RetrieveMultiple / Update / Delete** via the generated service. **No multi-row transaction or batch/atomic-commit API is documented** for code apps. ([connect-to-dataverse#supported-scenarios](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-dataverse#supported-scenarios)) **(a / gap)**
- **Lookups are awkward:** you must hand-associate via the Web API single-valued-navigation-property pattern; Microsoft says a friendlier API is "coming soon." ([connect-to-dataverse](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-dataverse)) **(b)**
- **File / image handling:** Dataverse image + file upload/download is **preview**, exposed via generated service functions. ([connect-to-dataverse#supported-scenarios](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-dataverse#supported-scenarios)) **(b)**
- **Schema drift is manual:** "If the schema on a connection changes, no command exists to refresh the typed model and service files. Instead, delete the data source and re-add it." ([connect-to-data](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-data)) **(a)**
- **Excel Online** connectors are unsupported as data sources (above).

Versus your own backend, you lose: raw SQL, set-based/batch writes, multi-statement transactions, stored-proc-driven logic beyond the single stored-proc-as-data-source pattern, arbitrary joins across sources, and unbounded result sets.

---

## Q4. Frontend constraints

- **(c) SPA only** (Q1). No SSR, no multi-document routing at the host level; client-side routing within your SPA is up to you, but there is **no documented deep-linking contract into a specific screen** — the only host-level URL knob is `?hideNavBar=true`. ([system configuration](https://learn.microsoft.com/power-apps/developer/code-apps/system-limits-configuration)) (Deep-link behavior = gap.)
- **(a) Default Content Security Policy is restrictive and enforced at the environment level** ([CSP](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/content-security-policy)):
  - `connect-src 'none'` — **every** outbound fetch/XHR/WebSocket to a non-platform host (your own API not behind a connector, Application Insights, any third-party service) is blocked until an admin allow-lists it.
  - `worker-src 'none'` and `manifest-src 'none'` — **no service workers, no web-app manifest → no PWA install, no offline caching.** This is the concrete mechanism behind "no offline."
  - `script-src 'self' <platform>` — **no external/CDN scripts**; you must bundle everything.
  - `frame-src 'none'`, `child-src 'none'`, `form-action 'none'`, `object-src 'self' data:`.
  - `frame-ancestors 'self' https://*.powerapps.com` — **by default the app can only be embedded inside Power Apps**; embedding elsewhere requires an admin to add a source.
- **Offline:** none (above). Additionally, the component-framework guidance Microsoft applies across Power Apps warns **not to use `window.localStorage`/`sessionStorage` for data** ("not secure and not guaranteed to be available reliably"). ([component framework limitations](https://learn.microsoft.com/power-apps/developer/component-framework/limitations)) **(c)**
- **Embedding:**
  - **Power BI reports:** supported via the Power Apps visual. ([overview#limitations](https://learn.microsoft.com/power-apps/developer/code-apps/overview#limitations))
  - **SharePoint forms:** not supported. ([overview#limitations](https://learn.microsoft.com/power-apps/developer/code-apps/overview#limitations))
  - **Teams / SharePoint pages:** **not documented.** Given `frame-ancestors` defaults to `*.powerapps.com`, embedding in Teams or a SharePoint page would require a CSP change and is not a documented, supported scenario. (Gap — do not assume Teams embedding works.)
- **Custom npm packages:** permitted — it's your bundle — but usable only insofar as they respect the CSP (no external network egress, no external scripts, no workers) noted above. **(a, conditional)**
- **Custom domains:** not available (Q1).

---

## Q5. Performance ceilings (documented / reported)

- **No published hard load-time or bundle-size ceiling** exists in the code-apps docs. The nearest concrete numbers are indirect: if a code app is **embedded in Microsoft Teams, Teams enforces a 30-second load timeout** and shows an error past it (general Power Apps constraint). ([Teams known issues](https://learn.microsoft.com/power-apps/teams/known-issues-limitations#studio)) **(a, when embedded in Teams.)**
- **Built-in performance telemetry is limited to two metric types** the client library emits: `sessionLoadSummary` (fields incl. `timeToAppInteractive`, `successfulAppLaunch`, `appLoadResult`) and `networkRequest` (`url`, `method`, `duration`, `statusCode`, `responseSize`). Microsoft's own sample queries recommend tracking the **75th percentile of `timeToAppInteractive`** — i.e., app-open time is the headline perf metric. ([App Insights how-to](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/set-up-azure-app-insights)) **(a)**
- **Throughput ceiling is the PPR quota + connector throttling** from Q2 (per-user 40,000/6,000 per 24h; 429s on connector throttle). For a data-heavy internal app with many users, PPR is the realistic scaling wall, not CPU. **(a)**
- **Effective data-volume ceiling is delegation** (500/2,000-row non-delegable cap; 50,000-row aggregate cap) from Q3. **(c)**

Reported/observed hard numbers for bundle size are **absent from primary sources** — flagged as a gap rather than inferred.

---

## Q6. Day-to-day adaptation for a pro-code dev

**Debugging (local vs hosted):**
- Local loop is `npm run dev` → "Local Play" URL, which must be opened **in the same browser profile as your Power Platform tenant**. ([create-an-app-from-scratch](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/create-an-app-from-scratch)) 
- **Since December 2025, Chrome/Edge block public→localhost requests by default** (Local Network Access), so local dev and any embedded local scenario may need a browser permission grant or `allow="local-network-access"` on iframes. ([same page](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/create-an-app-from-scratch)) **(a)**
- **Telemetry blind spot:** App Insights "only captures telemetry after the app successfully loads. Startup failures — including problems caused by blocked files or failed initialization — don't appear here and only show up in [Power Platform] Monitor." So two tools, and the most painful class of bug (won't-load) is only visible in the platform tool. ([App Insights how-to](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/set-up-azure-app-insights)) **(c)**

**Telemetry / monitoring:**
- **App Insights is supported but manually wired**: install `@microsoft/applicationinsights-web`, then feed the platform's `logMetric` callback (via `setConfig`) into `trackEvent`. You must also **add the App Insights ingestion endpoints to the environment CSP `connect-src`** or telemetry is silently blocked. ([App Insights how-to](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/set-up-azure-app-insights)) **(a)**
- **Platform-side:** Power Platform Monitor plus operational **health metrics in the admin center and maker portal**. ([overview — managed platform capability support](https://learn.microsoft.com/power-apps/developer/code-apps/overview)) 
- **No environment variables:** "Environment variables aren't yet supported for code apps." Per-environment config (e.g., the App Insights key) must be stored in Dataverse or selected via `getContext()`. ([App Insights how-to](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/set-up-azure-app-insights)) **(b/a)**

**Dependency management:**
- Your own `package.json`/Vite toolchain, but **connector data access is code-generated**: adding/removing a data source regenerates typed `*Model.ts`/`*Service.ts` files under `src/generated/…`, and the only "refresh after schema change" path is delete-and-re-add. ([connect-to-data](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-data)) **(a)**

**Upgrade-cadence / breaking-change risk:**
- The support doc itself flags churn: code apps use "developer-facing tooling and samples that evolve rapidly." SDK/CLI behavior mismatches vs. docs, and regressions with no code change, are routed to **standard Microsoft Support**; everything else to GitHub issues. ([feedback & support](https://learn.microsoft.com/power-apps/developer/code-apps/feedback-support)) **(b)**
- **Toolchain is mid-migration even post-GA:** the npm CLI is labelled "(preview)" while it is simultaneously slated to **replace** the `pac code` commands, which are "deprecated in a future release." A pro-code team is adopting a CLI/SDK still in flux. ([npm CLI quickstart](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/npm-quickstart); [overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview)) **(b)**

**ALM:** No Git integration, no solution packager, no source-code integration (Q1). Sanctioned path is **Power Platform Pipelines (Dev→Test→Prod)** plus **connection references** (CLI v1.51.1, Dec 2025) for environment portability. ([ALM](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/alm); [connect-to-data — connection references](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-data)) You run your own Git for the React source; the platform metadata sits outside Git-based ALM.

**Licensing (day-one governance cost):** every **end user needs a Power Apps Premium license**, and the app is automatically a governed Power Platform asset (sharing limits, DLP at launch, Conditional Access, quarantine). ([overview — prerequisites & managed platform support](https://learn.microsoft.com/power-apps/developer/code-apps/overview)) **(a)**

---

## Q7. Lock-in assessment — what ports, what gets rewritten

**Ports cleanly (your IP):** the entire front end. It's a standard Vite/React/TS SPA; "keeping full control over your UI and logic." Templates come from `microsoft/PowerAppsCodeApps` (MIT-licensed). ([overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview); [GA blog](https://www.microsoft.com/en-us/power-platform/blog/power-apps/generally-available-host-and-run-code-apps-in-power-apps/))

**Gets rewritten if you leave the platform** — the whole data/integration/hosting seam ([architecture](https://learn.microsoft.com/power-apps/developer/code-apps/architecture)):
- **The `@microsoft/power-apps` SDK calls** and every generated `*Service.ts` — these are the coupling. Each `SomethingService.getall()/create()/…` maps to a Power Platform connector call and would become your own `fetch` to your own API/DB layer.
- **Authentication** — today the **host silently handles Entra sign-in and token acquisition**. Off-platform you implement MSAL/OAuth yourself.
- **Hosting + the load shell** — the `apps.powerapps.com` endpoint, header, and fail-to-load messaging are Microsoft's; you'd host and build your own shell.
- **Connectors & Dataverse access** — connectors are a Power Platform construct; off-platform you call service SDKs/REST directly, and Dataverse via its Web API or migrate to another store.
- **`power.config.json` + connection references + Pipelines** — platform-specific, discarded.

**Survives the move:** anything you already externalized behind a **custom connector to Azure Functions/your API** — those APIs are yours and keep working; you just call them directly instead of through the connector. This is the strongest argument for pushing logic into your own Azure services early even while on the platform.

**Net:** lock-in is concentrated in the data-access + auth + hosting layer, not the UI. The more logic you put in connectors/flows/Dataverse Power Fx-style semantics, the larger the rewrite; the more you keep in your own Azure backend behind a thin custom connector, the smaller it is.

---

## Q8. Where Microsoft says "use something else"

**There is no dedicated "when not to use code apps" decision page** — a notable absence for a Fortune-500 architecture review. The de-facto guidance is the limitations list itself. Code apps are the wrong choice when you need:
- **A native mobile experience or the Power Apps Mobile player** ([Discussion #286](https://github.com/microsoft/PowerAppsCodeApps/discussions/286)); **offline** ([CSP `worker-src 'none'`](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/content-security-policy)); **a Windows app**, **SharePoint form embedding**, or **Power BI data integration** ([overview#limitations](https://learn.microsoft.com/power-apps/developer/code-apps/overview#limitations)).
- **Custom domains, IP-restricted access at the network layer, or SSR** (not offered / SPA-only).
- **To avoid per-end-user Power Apps Premium licensing** or the per-user PPR ceiling ([licensing / request limits](https://learn.microsoft.com/power-platform/admin/api-request-limits-allocations)).

**Positioning (what Microsoft says it IS for):** "line-of-business web apps" that become "a governed Power Platform asset, giving IT visibility and control without creating friction for developers" — the value proposition is **governance + zero-config Entra auth + connector reach**, explicitly *not* reach/scale beyond the browser. ([overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview); [GA blog, 5 Feb 2026](https://www.microsoft.com/en-us/power-platform/blog/power-apps/generally-available-host-and-run-code-apps-in-power-apps/))

Broader Power Apps design guidance (canvas-oriented, but the reasoning transfers): push cross-connector logic, approvals, and heavy processing to **Power Automate flows** rather than device-side, and reserve in-app logic for "simple logic … make any changes immediately visible on the screen." ([app design guidelines](https://learn.microsoft.com/power-apps/guidance/coding-guidelines/app-design-guidelines); [where to place logic](https://learn.microsoft.com/power-apps/guidance/planning/logic))

**Decision framing for the Fortune-500 reader:** choose code apps when the win is *governed distribution of an internal browser app* (Entra SSO handled for you, DLP/Conditional Access/sharing limits enforced by the platform, connector-mediated access to M365/Dataverse/SaaS) and the app is desktop-browser, online, single-tenant-internal. Choose full pro-code (React + own Azure backend) when you need mobile/offline/custom-domain, a real server tier with transactions and sub-120s-sync or long-running operations, direct database access, unconstrained third-party network egress, per-request scale beyond PPR, or freedom from per-user Premium licensing.

---

## Sources (all primary)

Microsoft Learn — code apps:
- Overview + Limitations + Managed platform capability support — https://learn.microsoft.com/power-apps/developer/code-apps/overview
- Architecture (dev + runtime layers) — https://learn.microsoft.com/power-apps/developer/code-apps/architecture
- System configuration (public endpoint, no IP restriction, hideNavBar) — https://learn.microsoft.com/power-apps/developer/code-apps/system-limits-configuration
- Content Security Policy (default directives) — https://learn.microsoft.com/power-apps/developer/code-apps/how-to/content-security-policy
- Connect to data (connectors; Excel unsupported; connection references; schema-refresh caveat) — https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-data
- Connect to Dataverse (CRUD, delegation Filter/Sort/Top, paging, lookups, file/image preview) — https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-dataverse
- Add Power Automate flows (manual/PowerApps-trigger only) — https://learn.microsoft.com/power-apps/developer/code-apps/how-to/add-flows
- ALM (no solution packager, no source integration; Pipelines) — https://learn.microsoft.com/power-apps/developer/code-apps/how-to/alm
- Set up Azure App Insights (2 metric types; post-load-only; no env vars; CSP allow-list) — https://learn.microsoft.com/power-apps/developer/code-apps/how-to/set-up-azure-app-insights
- Feedback & support (rapidly evolving tooling; support routing) — https://learn.microsoft.com/power-apps/developer/code-apps/feedback-support
- npm CLI quickstart (preview CLI; pac code deprecation) — https://learn.microsoft.com/power-apps/developer/code-apps/how-to/npm-quickstart
- Create app from scratch (Local Play; Dec 2025 Local Network Access) — https://learn.microsoft.com/power-apps/developer/code-apps/how-to/create-an-app-from-scratch
- Client library reference (v1.2.2) — https://learn.microsoft.com/javascript/api/powerapps-sdk-node/power-apps-client-lib-code-apps?view=powerapps-js-latest

Microsoft Learn — platform limits (inherited by code apps):
- Requests limits & allocations (PPR 40,000/6,000; add-ons) — https://learn.microsoft.com/power-platform/admin/api-request-limits-allocations
- Understand platform limits / throttling (429s, connector throughput) — https://learn.microsoft.com/power-automate/guidance/coding-guidelines/understand-limits
- Power Automate limits (120s timeout; 100MB message; retry) — https://learn.microsoft.com/power-automate/limits-and-config
- Custom connector FAQ (50/user; 10,000 rpm; ~3MB gateway content-length) — https://learn.microsoft.com/connectors/custom-connectors/faq
- Delegation overview (500/2,000 cap) — https://learn.microsoft.com/power-apps/maker/canvas-apps/delegation-overview
- Dataverse delegable functions (50,000 aggregate cap; FirstN unsupported; 15-table In) — https://learn.microsoft.com/power-apps/maker/canvas-apps/connections/connection-common-data-service
- Teams known issues (30s embedded load timeout) — https://learn.microsoft.com/power-apps/teams/known-issues-limitations
- Component framework limitations (no localStorage/sessionStorage for data) — https://learn.microsoft.com/power-apps/developer/component-framework/limitations
- Use connectors in Azure Functions (backend pattern; public preview) — https://learn.microsoft.com/azure/azure-functions/functions-connectors-overview
- App design guidelines / where to place logic — https://learn.microsoft.com/power-apps/guidance/coding-guidelines/app-design-guidelines · https://learn.microsoft.com/power-apps/guidance/planning/logic

Official Microsoft blog + GitHub:
- GA announcement, 5 Feb 2026 — https://www.microsoft.com/en-us/power-platform/blog/power-apps/generally-available-host-and-run-code-apps-in-power-apps/
- microsoft/PowerAppsCodeApps README (GA; MIT) — https://github.com/microsoft/PowerAppsCodeApps/blob/main/README.md
- Discussion #286 — Power Apps Mobile support ("backlog … no ETA") — https://github.com/microsoft/PowerAppsCodeApps/discussions/286

---

## Gaps / open questions

1. **No published hard app/bundle-size limit and no explicit load-time SLA.** The "System configuration" page is thin; size/perf ceilings had to be inferred from Teams (30s embed timeout), delegation caps, and PPR quotas. Worth confirming with Microsoft Support for a large SPA.
2. **Teams / SharePoint-page embedding is undocumented.** The default `frame-ancestors 'self' https://*.powerapps.com` implies it won't work without a CSP change, and no supported guidance exists — do not assume Teams embedding.
3. **Deep-linking / routing contract into a specific screen is undocumented.** Only `?hideNavBar=true` is documented at the host level; SPA-internal routing behavior across share/reload is unspecified.
4. **Multi-row transactions / atomic batch writes to Dataverse are not documented for code apps.** Only single-record CRUD via generated services is shown; verify whether the Web-API `$batch`/change-set pattern is usable.
5. **Custom domains** are absent from all docs (concluded unavailable by omission, not by explicit statement).
6. **Preview-within-GA churn:** the npm CLI is "(preview)", Dataverse file/image and Connectors-in-Azure-Functions are preview, and `pac code` is being deprecated — the exact GA/breaking-change timeline for these sub-features is not published.
7. **Connectors-per-app cap:** canvas guidance recommends ≤10 connectors / ≤20 connection references; code apps "follow canvas app sharing limits," but this specific connector-count guidance is **not restated** for code apps — treat as likely-applicable but unconfirmed. ([connections-list](https://learn.microsoft.com/power-apps/maker/canvas-apps/connections-list))
8. **Exact connector-call response-size limit inside a code app** (as opposed to the flow 100MB / custom-connector ~3MB gateway figures) is not separately documented.
