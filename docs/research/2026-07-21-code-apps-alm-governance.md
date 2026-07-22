# ALM, CI/CD, Source Control, and Enterprise Governance for Power Apps Code Apps

*Research date: 2026-07-21. Primary sources only: learn.microsoft.com, the official Microsoft Power Platform blog, and the microsoft/PowerAppsCodeApps GitHub repo. Code apps reached **general availability on 5 February 2026** ([Power Platform blog](https://www.microsoft.com/en-us/power-platform/blog/power-apps/generally-available-host-and-run-code-apps-in-power-apps/)).*

## Question

"Code apps" (Power Apps code apps) are Microsoft's code-first app model: React/TypeScript SPAs using the Power Apps SDK (`@microsoft/power-apps`), hosted in Power Platform. For a pro-code developer at a Fortune 500 company with mature DevOps (Git, PR review, CI pipelines, staged deployments), **which of those practices survive a move to code apps, and where does the Power Platform model force a different approach?** Eight sub-questions: source control, solutions integration, CI/CD, environment strategy, governance/admin, security review surface, authentication, and testing.

## TL;DR

- **Git stays your source of truth, and this is actually cleaner than canvas apps.** A code app is a normal front-end repo (React/TS, `package.json`, `power.config.json`, `src/`). `pac code push` (or `npm run build | pac code push`) uploads the **compiled build output** to Power Platform; the platform stores the built bundle + an app record, **not your source**. There is **no round-trip** — Power Platform Git integration and Solution Packager are explicitly **NOT supported** for code apps ([ALM how-to](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/alm), [overview limitations](https://learn.microsoft.com/power-apps/developer/code-apps/overview)).
- **Code apps ARE solution-aware.** They save to your preferred (non-default) solution automatically, or you target one with `pac code push --solutionName`, or add via **Add existing → App → Code app** in the maker portal. **Connection references** (Power Apps CLI ≥ 1.51.1, Dec 2025) and **environment variables** (`@envvar:` syntax) are supported and make the app portable across Dev/Test/Prod ([ALM how-to](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/alm), [connect-to-data](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-data), [use-environment-variables](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/use-environment-variables)).
- **Officially documented CI/CD path = solution + Power Platform Pipelines** (Dev → Test → Prod with preflight checks). Because a code app is a solution component, the standard **Power Platform Build Tools (Azure DevOps)** and **GitHub Actions for Power Platform** solution import/export machinery applies, with deployment-settings files pre-populating connection references and environment variables — but Microsoft's code-apps docs specifically call out **Pipelines**, and there is **no code-apps-specific Azure DevOps / GitHub Actions walkthrough** yet (flagged as a gap) ([ALM how-to](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/alm), [Pipelines](https://learn.microsoft.com/power-platform/alm/pipelines), [conn-ref/env-var deployment settings](https://learn.microsoft.com/power-platform/alm/conn-ref-env-variables-build-tools)).
- **Governance is inherited, not optional.** Code apps are "governed Power Platform assets": **connector DLP is enforced at app launch/runtime**, Conditional Access (per-app and by-location), tenant isolation, sharing limits, App Quarantine, and admin consent suppression all apply. This is a *gain* over a standalone App Service SPA, but it also means your app must be designed to live *within* DLP ([overview — Managed platform capability support](https://learn.microsoft.com/power-apps/developer/code-apps/overview), [GA blog](https://www.microsoft.com/en-us/power-platform/blog/power-apps/generally-available-host-and-run-code-apps-in-power-apps/)).
- **Authentication is "zero-config" Entra ID; custom end-user auth is not a thing.** The Power Apps host handles end-user sign-in; the app never juggles tokens itself — it calls generated connector services that flow through the platform's connection/consent infrastructure. You cannot bring your own identity provider for app sign-in; custom connectors (Entra OAuth / managed identity) are the extension point for back-end auth ([architecture](https://learn.microsoft.com/power-apps/developer/code-apps/architecture), [GA blog](https://www.microsoft.com/en-us/power-platform/blog/power-apps/generally-available-host-and-run-code-apps-in-power-apps/)).
- **Security review: source-side scanning is unchanged (a strength); the deployed bundle is public client-side code.** Since the source is an ordinary repo, your existing SAST / dependency scanning / SBOM tooling works as-is. The compiled assets are served from a **publicly accessible endpoint with no IP restriction** — Microsoft explicitly says **"Don't store sensitive user or organizational data in the app"** ([system configuration](https://learn.microsoft.com/power-apps/developer/code-apps/system-limits-configuration)).
- **Testing: unit tests are your own JS tooling (Vitest/Jest); E2E is Playwright.** There is **no code-apps-specific unit-test framework**, and **Power Apps Test Studio / Test Engine do not cover code apps**. Microsoft's recommended E2E path is the Playwright samples framework (CI/CD-ready), and the code-apps repo templates ship Playwright E2E tests ([Playwright samples](https://learn.microsoft.com/power-platform/developer/playwright-samples/overview), [Test Studio limitations](https://learn.microsoft.com/power-apps/maker/canvas-apps/test-studio#known-limitations)).
- **The tooling is mid-migration.** The `pac code` CLI commands are being **replaced by an npm-based CLI** (`power-apps init/run/push`) bundled in `@microsoft/power-apps` ≥ 1.0.4; `pac code` will be deprecated. Also note the **CoE Starter Kit is no longer actively maintained** — Microsoft has moved governance/inventory into the Power Platform admin center ([npm quickstart](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/npm-quickstart), [CoE transition](https://learn.microsoft.com/power-platform/guidance/coe/starter-kit)).

---

## 1. Source control: what lives in Git vs. only in Power Platform

**What lives in Git (your repo, exactly like any React/TS project):**
- Your application source (`src/`, components, TypeScript), `package.json`, build config (e.g. Vite/`tsc`), and the **`power.config.json`** metadata file that the client library generates. `power.config.json` holds connection/data-source metadata (including `@envvar:` references) and is used by the CLI to publish; your app logic isn't expected to read it ([architecture](https://learn.microsoft.com/power-apps/developer/code-apps/architecture), [use-environment-variables](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/use-environment-variables)).
- The **generated typed models/services** for each connector (e.g. `Office365UsersModel.ts`, `Office365UsersService.ts` under `src/generated/…`). These are code-generated when you run `pac code add-data-source`, and are regenerated on schema change (there's no refresh command — you delete and re-add the data source) ([connect-to-data](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-data)).

**What `pac code push` sends to Power Platform:** the **compiled app** (the `vite build` / `tsc -b` output). "The PAC CLI `pac code push` command takes a **compiled app** and publishes it in a Power Platform environment" ([architecture](https://learn.microsoft.com/power-apps/developer/code-apps/architecture); [quickstart build+deploy](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/create-an-app-from-scratch)).

**What lives only in Power Platform (never in Git):**
- The **published app record and its versions** (each `pac code push` "Publishes a new version of a Code app") ([pac code reference](https://learn.microsoft.com/power-platform/developer/cli/reference/code)).
- **Connections** (credential-bearing connection instances), **connection references**, **environment-variable values**, sharing/permissions, and the served compiled bundle — all held in the environment/Dataverse.

**Hard limitation — no source round-trip:** Code apps **don't support Power Platform Git integration** and **don't support Solution Packager** ([ALM how-to — Limitations](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/alm)). This is the opposite of canvas apps, where the platform can emit human-readable `*.pa.yaml` source ([canvas source files](https://learn.microsoft.com/power-apps/maker/canvas-apps/power-apps-yaml)).

**Contrast with your current stack:** This is *closer* to a normal pro-code SPA than canvas apps are. Git is the single source of truth for the code; the platform just hosts a build — much like Git → CI → App Service. The difference from App Service: you cannot extract the running app back into source from the platform, so **losing Git means losing your source** (there is no `pac code download`). Discipline that you already have (Git as the authority) is mandatory here, not optional.

## 2. Solutions integration (managed/unmanaged, environment variables, connection references)

- **Can code apps be added to solutions? Yes.** If the environment has a **preferred solution**, new apps save to it by default on `pac code push`; otherwise use `pac code push --solutionName <name>`, or in the maker portal **Solutions → [solution] → Add existing → App → Code app** ([ALM how-to](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/alm)). Microsoft explicitly steers you to a **non-default solution** "to enable healthy ALM from day one."
- **Managed vs. unmanaged:** Code apps follow the standard Power Platform solution model — you develop in an unmanaged solution and promote a managed solution downstream. The general ALM guidance (commit unmanaged solution metadata to source control; deploy managed) applies at the *solution* level ([ALM basics](https://learn.microsoft.com/power-platform/alm/basics-alm)). **Caveat:** because Solution Packager is unsupported for code apps, you **cannot unpack the solution's code-app component into diff-able XML** the way you can for other component types — the code app rides inside the solution as an opaque artifact.
- **Connection references: supported (recent).** "Starting in version **1.51.1** of the Power Apps CLI released in **December 2025**, you can use connection references to add data sources to your code app… This approach makes the solution environment-aware and portable across Dev, Test, and Prod." Bind with `pac code add-data-source -a <apiName> -cr <connectionReferenceLogicalName> -s <solutionID>` ([connect-to-data](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-data)).
- **Environment variables: supported.** Reference env-var **schema names** with the `@envvar:` prefix for dataset/table arguments; the reference is persisted in `power.config.json` and resolved from the target environment at deploy time — "so your code app can move between environments without hardcoding dataset or table values" ([use-environment-variables](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/use-environment-variables)).

**Contrast with your current stack:** Connection references + environment variables are the Power Platform equivalent of per-environment config (App Settings / Key Vault references / IaC parameters). The model is sound, but the transport is the *solution*, not your pipeline artifact — a paradigm shift from "the build is the artifact" to "the solution is the artifact."

## 3. CI/CD: Dev → Test → Prod

**The inner loop:** `npm run dev` (or `pac code run` / `power-apps run`) runs locally with connections; `npm run build | pac code push` publishes ([create-an-app-from-scratch](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/create-an-app-from-scratch)).

**Officially documented promotion path — Power Platform Pipelines:** "Once the app is in a solution, use **Power Platform Pipelines** to deploy across stages (Dev → Test → Prod) with preflight checks for dependencies, connection references, and more" ([ALM how-to → Deploy using Pipelines](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/alm); [Pipelines overview](https://learn.microsoft.com/power-platform/alm/pipelines)). Pipelines is the in-product, admin-configured, solution-based deployment mechanism.

**Azure DevOps & GitHub Actions:** Not called out in the code-apps docs by name, but the mechanism is available because a code app is a **solution component**:
- **Power Platform Build Tools for Azure DevOps** and **GitHub Actions for Power Platform** provide solution export/pack/import tasks for CI/CD ([ALM tools/apps](https://learn.microsoft.com/power-platform/alm/tools-apps-used-alm)).
- **Deployment-settings files** pre-populate connection references and environment variables for **unattended** solution import — the standard way to make Power Platform CI/CD non-interactive ([conn-ref/env-var deployment settings](https://learn.microsoft.com/power-platform/alm/conn-ref-env-variables-build-tools)).

**Officially supported for code apps *specifically* as of mid-2026:** `pac code push` (manual/scriptable) and **Power Platform Pipelines** are the documented, code-apps-named paths. Azure DevOps/GitHub Actions work at the *solution* layer (the same layer Pipelines uses) and therefore apply, but **Microsoft has not published a code-apps-specific ADO/GitHub Actions tutorial** — this is currently community-documented, not first-party (see Gaps). **Not supported:** Power Platform Git integration and Solution Packager, so you cannot wire the classic "unpack solution to XML in a repo" flow around the code app itself ([ALM how-to — Limitations](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/alm)).

**Contrast with your current stack:** In your App Service world, the pipeline artifact (the build) *is* what gets promoted, and rollback is redeploying a prior artifact. Here, the pipeline can still build/test your React code normally, but the **promotion step is solution import/Pipeline**, and the app binary is carried inside the solution. You keep your CI (build + test + scan on PR); you replace your CD target (App Service slots/deploy) with solution promotion.

## 4. Environment strategy Microsoft recommends for enterprises

- **Separate Dev/Test/Prod environments, each with Dataverse.** The prerequisite for code-app ALM is a Dataverse-backed environment and a non-default (preferably *preferred*) solution ([ALM how-to](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/alm)). General Power Platform guidance: develop in a dev environment, maintain at least one test environment for end-to-end testing, promote to production ([co-development governance](https://learn.microsoft.com/power-apps/guidance/co-develop/governance)).
- **Enabling code apps is a per-environment admin toggle** (Admin center → Environment → Settings → Product → Features → *Enable code apps*), and can be set **at scale via environment groups and rules** ([overview — Enable code apps](https://learn.microsoft.com/power-apps/developer/code-apps/overview)).
- **Managed Environments** is the recommended governance layer: sharing limits, data policies, Conditional Access on individual apps, weekly digest, maker welcome content — code apps honor these (see §5) ([Managed environments overview](https://learn.microsoft.com/power-platform/admin/managed-environment-overview)).
- **Licensing:** end users running code apps need a **Power Apps Premium** license ([overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview)).

**Contrast with your current stack:** Your Dev/Test/Prod subscription or resource-group separation maps cleanly onto Power Platform environments. The new tax is that each environment must have code apps explicitly enabled and (for governance features) be a Managed Environment, and every end user needs a premium license — a per-seat cost model that App Service hosting does not impose.

## 5. Governance and admin controls

Microsoft publishes a **"Managed platform capability support"** table for code apps — the authoritative list of what governance applies ([overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview)):

| Capability | Applies to code apps |
| --- | --- |
| **Connector DLP enforcement** | Yes — "**Data Loss policy enforcement during app launch**." GA blog: "**DLP policy enforcement at runtime—protecting your data without code changes.**" |
| **Conditional Access (per individual app)** | Yes |
| **Tenant isolation** (cross-tenant restrictions) | Yes |
| **Sharing limits** | Yes — code apps follow canvas-app sharing limits |
| **App Quarantine** (admin can quarantine a bad app) | Yes |
| **Admin consent-dialog suppression** | Yes — for OAuth Microsoft connectors and custom connectors using Entra ID OAuth |
| **Azure B2B (external users)** | Yes — like canvas apps |
| **Health metrics** | Yes — in Power Platform admin center **and** maker portal |

- **DLP specifically:** Connector-based DLP policies **do apply** to code apps and are enforced **at launch/runtime** — if a code app uses a connector combination that violates a data policy, launch is blocked ([DLP](https://learn.microsoft.com/power-platform/admin/wp-data-loss-prevention)). This is a genuine difference from a standalone App Service SPA, which Power Platform DLP never sees.
- **Admin visibility:** Code apps are governed assets with health/diagnostics in the **Power Platform admin center** and **Monitor** ("Health monitoring and diagnostics through the Power Platform Monitor," GA blog; [monitor Power Apps](https://learn.microsoft.com/power-platform/admin/monitoring/monitor-power-apps)). Tenant-wide inventory of apps/flows/agents is available via the admin center **Inventory** experience and the **Power Platform Inventory API** ([inventory](https://learn.microsoft.com/power-platform/admin/power-platform-inventory)).
- **CoE Starter Kit:** The **CoE Starter Kit is no longer actively maintained**; Microsoft directs governance/inventory/usage/monitoring to the **Power Platform admin center** (Inventory, Usage, Monitor, Actions) and the Inventory API ([CoE transition](https://learn.microsoft.com/power-platform/guidance/coe/starter-kit)). There is **no primary-source statement** that either the legacy CoE kit or PPAC inventory enumerates code apps as a distinct type — treat CoE-toolkit awareness of code apps as an **open question** and prefer PPAC/Inventory API for reporting.

**Contrast with your current stack:** You gain platform-native DLP, per-app Conditional Access, tenant isolation, and quarantine "for free" — controls you'd otherwise assemble from Entra Conditional Access + WAF + your own governance. The trade-off is loss of some autonomy: an admin DLP change can block your app at launch without a code change.

## 6. Security review surface

- **Scanning the source: unchanged, and a strength.** The app is an ordinary front-end repo, so your existing SAST, dependency/SCA scanning (CodeQL, Dependabot, `npm audit`), secret scanning, and SBOM generation run in CI exactly as today. Nothing platform-specific is required. (This is a clear advantage over canvas apps, whose logic is Power Fx inside a binary `.msapp`.)
- **Scanning the deployed app:** The compiled assets are served from a **publicly accessible endpoint that does not support IP-based restrictions** ([system configuration](https://learn.microsoft.com/power-apps/developer/code-apps/system-limits-configuration); [overview limitations](https://learn.microsoft.com/power-apps/developer/code-apps/overview)). It is client-side JS/HTML, inspectable by anyone with access — so treat it as untrusted client code. Microsoft's explicit guidance: **"Don't store sensitive user or organizational data in the app. Store this kind of data in a data source"** retrieved after Entra auth. To restrict network access, use **Conditional Access – block by location** (the SAS IP-binding/firewall environment setting does **not** apply to code apps).
- **Versioning & rollback:** Each `pac code push` "**Publishes a new version**" ([pac code reference](https://learn.microsoft.com/power-platform/developer/cli/reference/code)); the GA blog cites "Power Platform's deployment and **versioning** tools." **Git remains the authoritative rollback mechanism** — re-push a prior commit's build. Canvas apps expose **Details → Versions → Restore** in the portal ([restore a canvas app](https://learn.microsoft.com/power-apps/maker/canvas-apps/restore-an-app)); whether the identical restore UI is exposed for code apps is **not explicitly documented** (open question). Admins can also **Quarantine** a bad app immediately ([overview table](https://learn.microsoft.com/power-apps/developer/code-apps/overview)).

**Contrast with your current stack:** Source-side security review is business-as-usual. The deployed-surface story is *weaker* than App Service in one respect — no IP allow-listing on the app endpoint (you must use Conditional Access instead) — and you cannot put server-side secrets/logic in the app at all; all privileged access must go through connectors.

## 7. Authentication

- **End-user sign-in:** Microsoft **Entra ID**, handled by the platform. "The Power Apps **host manages end-user authentication**, app loading, and presenting contextual messages if an app fails to load" ([architecture — Runtime](https://learn.microsoft.com/power-apps/developer/code-apps/architecture)). GA blog: "**Zero-config authentication through Microsoft Entra ID—no custom auth flows to build.**"
- **How the app gets data/tokens:** Your code does **not** manage connector tokens. It calls the **generated services** (e.g. `Office365UsersService.MyProfile()`), which the **Power Apps client library** routes through the host to Power Platform connector infrastructure (API Hub / consent service handles token exchange and caches consent) ([architecture](https://learn.microsoft.com/power-apps/developer/code-apps/architecture); connector auth pathway: [connect-data-sources](https://learn.microsoft.com/power-platform/admin/security/connect-data-sources)).
- **Consent model:** Same as canvas apps — end users see a **connection consent dialog** on first launch (suppressible by admins for first-party OAuth connectors and Entra-ID-OAuth custom connectors) ([overview table](https://learn.microsoft.com/power-apps/developer/code-apps/overview); [manage connections](https://learn.microsoft.com/power-apps/maker/canvas-apps/add-manage-connections)). **Secure implicit connections** (post-Jan-2024 default) apply, so a shared connection is fronted by a proxy limited to the app's CRUD actions ([connectors overview](https://learn.microsoft.com/power-apps/maker/canvas-apps/connections-list)).
- **Custom auth:** **Not supported for app sign-in** — end-user identity is always Entra ID (Power Apps also does not support External-member identities). For back-end/API auth, the extension point is **custom connectors**, which support Entra ID OAuth and **managed-identity** authentication (no client-secret rotation) ([custom connector Entra auth](https://learn.microsoft.com/connectors/custom-connectors/azure-active-directory-authentication)). You can create connections from the CLI (`pac connection`/`pac code`) — CLI connection creation is in **preview** ([connect-to-data](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-data)).

**Contrast with your current stack:** If your App Service SPA already uses MSAL + Entra ID, the identity provider is the same, but here you **give up control of the auth flow** (no custom scopes/flows in-app, no non-Entra IdP) in exchange for zero-config SSO and platform-managed connection tokens. Data access is mediated by connectors with per-user delegated permissions rather than your own API tier.

## 8. Testing

- **Unit tests: your own JS tooling, run locally.** A code app is a standard TS/JS project, so unit testing uses whatever you choose (Vitest/Jest). **Microsoft provides no code-apps-specific unit-test framework.** Local run/debug is `npm run dev` (Vite dev server, "Local Play") or `pac code run` / `power-apps run` for a local server that loads connections ([create-an-app-from-scratch](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/create-an-app-from-scratch); [pac code reference](https://learn.microsoft.com/power-platform/developer/cli/reference/code)). *(Note: since Dec 2025, Chrome/Edge block public→localhost requests by default; local dev may need a browser permission or `allow="local-network-access"` on embed iframes.)*
- **E2E tests: Playwright is the platform-recommended path.** The **Power Platform Playwright samples** framework writes TypeScript E2E tests for all app types, is **CI/CD-ready** (GitHub Actions, Azure Pipelines), and includes AI-assisted authoring via the Playwright MCP server ([Playwright samples overview](https://learn.microsoft.com/power-platform/developer/playwright-samples/overview)). The **microsoft/PowerAppsCodeApps** repo templates ship end-to-end Playwright tests for template validation ([code apps repo](https://github.com/microsoft/PowerAppsCodeApps)).
- **What does NOT cover code apps:** **Power Apps Test Studio** (Power Fx, canvas-only; code components explicitly unsupported) and the Power Fx **Test Engine** do not test code apps ([Test Studio limitations](https://learn.microsoft.com/power-apps/maker/canvas-apps/test-studio#known-limitations); [Playwright vs Test Engine](https://learn.microsoft.com/power-platform/developer/playwright-samples/overview)).

**Contrast with your current stack:** Unit testing is identical to today (your framework, your CI). E2E via Playwright is likewise familiar. The only "loss" is that Power Platform's built-in low-code test tooling (Test Studio/Test Engine) doesn't reach code apps — which for a pro-code team is a non-issue since you were never going to use Power Fx YAML tests anyway.

---

## Other documented limitations (mid-2026)

From [overview — Limitations](https://learn.microsoft.com/power-apps/developer/code-apps/overview):
- No SAS IP binding / firewall restriction (public endpoint) — use Conditional Access by location.
- **No Power Platform Git integration** and **no Solution Packager** ([ALM how-to](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/alm)).
- **Not supported in Power Apps for Windows.**
- **No Power BI data integration** (`PowerBIIntegration`) yet — but a code app **can be embedded in Power BI** via the Power Apps visual.
- **No SharePoint forms integration.**
- **Excel Online (Business)** and **Excel Online (OneDrive)** connectors are **not yet supported**; all other connectors are ([connect-to-data](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-data)).

**Tooling transition (flag):** The `pac code` commands are being **replaced by an npm CLI** (`power-apps init/run/push/find-dataverse-api`) in `@microsoft/power-apps` ≥ 1.0.4; `pac code` will be deprecated ([npm quickstart](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/npm-quickstart)). Any pipeline scripting `pac code push` should plan to migrate.

## Staleness check (as of 2026-07-21)

Docs reviewed appear **current**: they reference the Power Apps CLI 1.51.1 release (Dec 2025), the Dec 2025 browser local-network-access change, connection-reference support, and the GA milestone (5 Feb 2026). No reviewed page looked stale. The two moving targets to watch are (a) the `pac code` → npm-CLI transition, and (b) roadmap items the GA-era community office hours mention (advanced Dataverse operations, Power Automate/Copilot Studio invocation, GCC support) — none of which are load-bearing for the ALM/governance conclusions above.

---

## Sources

Primary (Microsoft Learn / official blog / official repo):
- Code apps overview (features, limitations, managed-platform capability table): https://learn.microsoft.com/power-apps/developer/code-apps/overview
- ALM for code apps (solutions, Pipelines, limitations): https://learn.microsoft.com/power-apps/developer/code-apps/how-to/alm
- Code apps architecture (what's compiled/published, runtime auth): https://learn.microsoft.com/power-apps/developer/code-apps/architecture
- Connect your code app to data (data sources, connection references, CLI 1.51.1): https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-data
- Use environment variables in code app data sources (`@envvar:`): https://learn.microsoft.com/power-apps/developer/code-apps/how-to/use-environment-variables
- System configuration (public endpoint, no IP restriction, hideNavBar): https://learn.microsoft.com/power-apps/developer/code-apps/system-limits-configuration
- Quickstart: create a code app from scratch (build + `pac code push`): https://learn.microsoft.com/power-apps/developer/code-apps/how-to/create-an-app-from-scratch
- Quickstart: new npm CLI (preview) — CLI transition: https://learn.microsoft.com/power-apps/developer/code-apps/how-to/npm-quickstart
- `pac code` CLI reference (push = new version; add-data-source `-cr`): https://learn.microsoft.com/power-platform/developer/cli/reference/code
- Feedback and support (supported vs. GitHub-issue channels): https://learn.microsoft.com/power-apps/developer/code-apps/feedback-support
- Power Apps client library for code apps reference: https://learn.microsoft.com/javascript/api/powerapps-sdk-node/power-apps-client-lib-code-apps
- GA announcement blog (5 Feb 2026): https://www.microsoft.com/en-us/power-platform/blog/power-apps/generally-available-host-and-run-code-apps-in-power-apps/
- Power Platform Pipelines: https://learn.microsoft.com/power-platform/alm/pipelines
- Pre-populate connection references & environment variables for automated deployment: https://learn.microsoft.com/power-platform/alm/conn-ref-env-variables-build-tools
- ALM basics / tools & apps used for ALM (Build Tools, Package Deployer): https://learn.microsoft.com/power-platform/alm/basics-alm , https://learn.microsoft.com/power-platform/alm/tools-apps-used-alm
- DLP overview: https://learn.microsoft.com/power-platform/admin/wp-data-loss-prevention
- Managed environments overview: https://learn.microsoft.com/power-platform/admin/managed-environment-overview
- Power Platform Inventory (admin center): https://learn.microsoft.com/power-platform/admin/power-platform-inventory
- Monitor Power Apps: https://learn.microsoft.com/power-platform/admin/monitoring/monitor-power-apps
- CoE Starter Kit → admin-center transition: https://learn.microsoft.com/power-platform/guidance/coe/starter-kit
- Manage connections in canvas apps (consent suppression, secure implicit): https://learn.microsoft.com/power-apps/maker/canvas-apps/add-manage-connections , https://learn.microsoft.com/power-apps/maker/canvas-apps/connections-list
- Custom connector Entra ID / managed-identity auth: https://learn.microsoft.com/connectors/custom-connectors/azure-active-directory-authentication
- Power Platform Playwright samples (E2E, CI/CD-ready): https://learn.microsoft.com/power-platform/developer/playwright-samples/overview , https://learn.microsoft.com/power-platform/developer/playwright-samples/local-development
- Test Studio known limitations (no code components): https://learn.microsoft.com/power-apps/maker/canvas-apps/test-studio#known-limitations
- Restore a canvas app to a previous version (canvas-app baseline for versioning UI): https://learn.microsoft.com/power-apps/maker/canvas-apps/restore-an-app
- microsoft/PowerAppsCodeApps repo (templates, samples, Playwright tests, issues): https://github.com/microsoft/PowerAppsCodeApps

## Gaps / open questions

1. **No first-party Azure DevOps / GitHub Actions walkthrough for code apps.** The mechanism (solution import/export + deployment-settings) is documented generally and Pipelines is documented for code apps, but a code-apps-specific ADO/GitHub Actions tutorial is not published by Microsoft as of mid-2026. Verify with a spike that a **solution export from Dev carries the compiled code-app bundle** such that a downstream **import reproduces the running app without a per-environment `pac code push`** — the docs imply Pipelines does this, but the exact export/import mechanics for the app binary aren't spelled out.
2. **Portal versioning/rollback UI for code apps.** `pac code push` creates versions and admins can quarantine, but whether the canvas-style **Details → Versions → Restore** UI is available for code apps is not documented. Confirm in-product; otherwise treat Git re-push as the rollback path.
3. **CoE / inventory enumeration of code apps.** No primary source confirms that the (now-unmaintained) CoE Starter Kit or the admin-center Inventory lists code apps as a distinct app type. Validate via the Power Platform **Inventory API** whether code apps surface and how they're typed.
4. **Solution-carried binary vs. rebuild.** Because Solution Packager is unsupported, the code-app component inside a solution is opaque. Confirm there's no supported way to diff/review the app *as part of the solution* in source control (the intended review surface is the Git repo, pre-build).
5. **`pac code` → npm CLI migration timeline.** `pac code` is slated for deprecation; the exact removal date and whether CI hosts should pin the npm CLI vs. `pac` is unstated. Track before hard-coding either into pipelines.
