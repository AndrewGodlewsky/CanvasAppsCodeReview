# Power Platform "Code Apps": What They Are and the Developer Programming Model

## Question

What exactly are Power Apps **code apps** (Microsoft's code-first app model, `@microsoft/power-apps` SDK, run/hosted inside Power Platform), and what is the developer programming model? Specifically, for a pro-code developer at a large enterprise evaluating code apps as an alternative to full pro-code apps (e.g., React + Azure App Service):

1. Architecture — where the code runs, how it is hosted, what the platform provides at runtime.
2. Developer workflow — scaffolding, the Power Apps SDK, local dev, `pac`/npm CLI, supported frameworks/build tools.
3. Data access — connectors, generated typed models/services, Dataverse, calling Azure/custom APIs.
4. Precise differences vs. canvas apps, model-driven apps, and PCF.
5. GA/preview status of code apps and sub-features as of July 2026.
6. Microsoft's stated intended (and non-intended) use cases.

All claims below are cited to primary Microsoft sources (learn.microsoft.com, the first-party Power Platform blog, and the official `microsoft/PowerAppsCodeApps` GitHub repo). Today's date for staleness checks is **2026-07-21**.

---

## TL;DR

- A **code app** is a code-first **single-page web app** (React/Vue/other, TypeScript, built with Vite) that you write in your own IDE but that **runs hosted inside Power Platform** and gets Power Platform's authentication, connectors, and governance — it is *not* a canvas/model-driven app and *not* a PCF component. [overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview) · [architecture](https://learn.microsoft.com/power-apps/developer/code-apps/architecture)
- Runtime = **your code + the Power Apps client library (`@microsoft/power-apps`, the "Power Apps SDK") + the Power Apps host**. The host handles end-user Microsoft Entra authentication, app loading, and load-failure messaging; the client library brokers all data calls through Power Platform connectors. [architecture](https://learn.microsoft.com/power-apps/developer/code-apps/architecture)
- Compiled assets are **served from a public Power Platform endpoint** (`https://apps.powerapps.com/play/e/{env}/a/{app}`) with **no IP-based restriction** — you use Conditional Access for IP/location control, and you must not store sensitive data in the app bundle. [system configuration](https://learn.microsoft.com/power-apps/developer/code-apps/system-limits-configuration)
- Data access is **connector-based**: adding a data source generates **typed TypeScript model + service files** (e.g., `Office365UsersService`, `AccountsService`) you call from JS. **Dataverse** is a first-class data source (CRUD, delegation for Filter/Sort/Top, paging, metadata). Azure and custom APIs are reached **through connectors/custom connectors**. [connect to data](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-data) · [connect to Dataverse](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-dataverse)
- **Code apps are generally available (GA)** — announced GA on **February 5, 2026** on the Power Platform blog and confirmed GA in the docs and the GitHub repo. [GA blog](https://www.microsoft.com/en-us/power-platform/blog/power-apps/generally-available-host-and-run-code-apps-in-power-apps/)
- Several *sub-features remain in preview* as of July 2026: the **new npm-based CLI**, **creating connections from the CLI**, and **Dataverse image/file upload/download**. The older `pac code` CLI commands are labeled **(Preview)** and are being **deprecated** in favor of the npm CLI. [npm quickstart](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/npm-quickstart) · [pac code](https://learn.microsoft.com/power-platform/developer/cli/reference/code) · [connect to Dataverse](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-dataverse)
- Microsoft positions code apps as **governed line-of-business web apps for pro developers**: "full code-first flexibility" for devs plus "enterprise-grade guardrails" for IT, where "every code app automatically becomes a governed Power Platform asset." End users need a **Power Apps Premium** license. [GA blog](https://www.microsoft.com/en-us/power-platform/blog/power-apps/generally-available-host-and-run-code-apps-in-power-apps/) · [overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview)
- Known boundaries: no Power BI `PowerBIIntegration`, no SharePoint forms integration, not supported in Power Apps for Windows, no Power Platform Git integration, and Excel Online (Business/OneDrive) connectors are not yet supported. [overview – Limitations](https://learn.microsoft.com/power-apps/developer/code-apps/overview)

---

## 1. What exactly is a code app? (Architecture, hosting, runtime)

### Definition
"**Code apps** let developers bring Power Apps capabilities into custom web apps built in a code-first IDE. You can develop locally and run the same app in Power Platform. Build with popular frameworks (React, Vue, and others) while keeping full control over your UI and logic." Key platform-provided features are: Microsoft Entra authentication/authorization; access to Power Platform data sources and **1,500+ connectors, callable directly from JavaScript**; hosting of line-of-business web apps in Power Platform; adherence to Managed Platform policies (sharing limits, Conditional Access, DLP); and simplified ALM. [overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview)

A code app must be an **HTML or TypeScript/JavaScript app**, and code apps **support Single-Page Applications (SPAs)**. [architecture](https://learn.microsoft.com/power-apps/developer/code-apps/architecture)

### The four architectural pieces
Per the official architecture doc, a code app consists of: [architecture](https://learn.microsoft.com/power-apps/developer/code-apps/architecture)

1. **The Power Apps client library for code apps** — the [`@microsoft/power-apps` npm package](https://www.npmjs.com/package/@microsoft/power-apps), "sometimes called the 'Power Apps SDK'". It exposes APIs your app calls directly and contains logic that manages models/services as connections are added/removed.
2. **Generated models/services for connectors** — typed TypeScript files produced when you add a data source.
3. **`power.config.json`** — a generated metadata file used by both the CLI and the client library for connections and for publishing to an environment. "Your app logic isn't expected to interact with the `power.config.json` file."
4. **The Power Apps host** — the Power Platform runtime that serves and runs the published app.

### Where the code runs at runtime
"When a code app runs, there are three logical components: **Your code**, **The Power Apps client library for code apps**, **The Power Apps host**." The client library "exposes APIs that your code can use and the generated models and services your app uses to perform data requests via Power Platform connectors." The host "manages end-user authentication, app loading, and presenting contextual messages to the user if an app fails to load." [architecture – Runtime](https://learn.microsoft.com/power-apps/developer/code-apps/architecture#runtime)

So: **your compiled front-end runs in the end-user's browser**, but data calls are brokered by the client library through Power Platform connectors, and **authentication + app delivery are handled by the Power Platform host** — you do not stand up your own auth, API gateway, or web host.

### How it is hosted
When you publish with `pac code push`, "the compiled app assets are hosted on a publicly accessible endpoint. This endpoint doesn't currently support IP-based access restrictions." Because code apps authenticate with Microsoft Entra ID, Microsoft directs you to use **Conditional Access** for location/IP control. Explicit guidance: "**Don't store sensitive user or organizational data in the app.** Store this kind of data in a data source so the content is retrieved after end-users … go through authentication and authorization checks." [system configuration](https://learn.microsoft.com/power-apps/developer/code-apps/system-limits-configuration)

Published apps run at a Power Platform play URL of the form `https://apps.powerapps.com/play/e/{environment id}/a/{app id}` (a `?hideNavBar=true` query string hides the Power Apps header). [system configuration](https://learn.microsoft.com/power-apps/developer/code-apps/system-limits-configuration)

### Governance the platform provides (relevant to enterprise evaluation)
Code apps inherit Managed Platform capabilities, including: end-user connector-consent dialog; **canvas-app sharing limits**; **App Quarantine**; **DLP enforcement during app launch**; **Conditional Access on an individual app**; admin consent-dialog suppression; tenant isolation; **Azure B2B** external-user access; and operational **health metrics** in the admin center and maker portal. [overview – Managed platform capability support](https://learn.microsoft.com/power-apps/developer/code-apps/overview)

---

## 2. The developer workflow

### Prerequisites and enablement
Code apps require developer tooling on the command line: **an IDE (e.g., VS Code), Node.js (LTS), git, dotnet, npm, and the Power Apps CLI (PAC CLI)**. An admin must **enable code apps per environment** (Power Platform admin center → Environments → Settings → Product → Features → "Power Apps code apps" toggle), and **end users need a Power Apps Premium license**. [overview – Prerequisites](https://learn.microsoft.com/power-apps/developer/code-apps/overview)

### Two CLIs (important nuance)
There are currently **two CLIs**, and Microsoft is mid-transition:

- **PAC CLI `pac code` commands** — the established path. The reference page labels the command group **"(Preview) Commands to manage your Code apps."** Commands include `pac code init`, `pac code push`, `pac code add-data-source`, `pac code delete-data-source`, `pac code list`, `pac code list-datasets`, `pac code list-tables`, `pac code list-sql-stored-procedures`, `pac code list-connection-references`, and `pac code run`. [pac code reference](https://learn.microsoft.com/power-platform/developer/cli/reference/code)
- **New npm-based CLI** — shipped inside `@microsoft/power-apps` **v1.0.4 and higher**. "This new CLI reduces prerequisites for building code apps and **will replace** the Power Platform CLI's `pac code` commands, **which will be deprecated in a future release**." Its quickstart page title is explicitly marked **"(preview)"**. It has four commands: `init`, `run`, `push`, and `find-dataverse-api`, invoked as `power-apps init` / `power-apps push`. [overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview) · [npm quickstart (preview)](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/npm-quickstart)

> Evaluation note: for a Fortune-500 pro-code team, both the "front-door" CLIs are in flux — the classic `pac code` group is flagged Preview and slated for deprecation, and its replacement npm CLI is itself in preview. The underlying **product** is GA, but the tooling surface is still moving.

### Scaffolding a project
Microsoft's quickstarts scaffold from the official GitHub templates via `degit`:

```bash
npx degit github:microsoft/PowerAppsCodeApps/templates/vite my-app
cd my-app
```
[quickstart: create from scratch](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/create-an-app-from-scratch)

Two templates are published in the repo: a **starter** template ("Pre-configured with React, Vite, Tailwind CSS, Tanstack Query, and React Router. Best for most apps") and a **vite** template ("Minimal Vite + React setup … Good for lightweight or custom stacks"). Quick command: `npx degit microsoft/PowerAppsCodeApps/templates/starter my-app`. [PowerAppsCodeApps README](https://github.com/microsoft/PowerAppsCodeApps/blob/main/README.md)

### Full local-to-cloud loop (classic PAC CLI path)
```bash
# 1. Scaffold
npx degit github:microsoft/PowerAppsCodeApps/templates/vite my-app && cd my-app
# 2. Authenticate + select environment
pac auth create
pac env select --environment <Your environment ID>
# 3. Install SDK + initialize the code app
npm install
pac code init --displayname "App From Scratch"
# 4. Run locally
npm run dev            # then open the "Local Play" URL
# 5. Build + publish
npm run build | pac code push   # returns a Power Apps URL to run the app
```
[quickstart: create from scratch](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/create-an-app-from-scratch)

New npm CLI equivalent: `npm install -g @microsoft/power-apps` then `power-apps init --display-name "..." --environment-id <id>` (or interactive `power-apps init`), `npm run dev`, `npm run build` + `power-apps push`. The `npm run build` script itself is `tsc -b && vite build`. [npm quickstart](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/npm-quickstart)

### Local dev experience specifics
- `npm run dev` starts a local dev server; open the **"Local Play"** URL. **Open it in the same browser profile as your Power Platform tenant.** [quickstart](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/create-an-app-from-scratch)
- **Local Network Access restriction (since December 2025):** Chrome and Microsoft Edge block requests from public origins to local endpoints by default. Because the code app connects to `localhost` during development, you may need to grant browser permission or configure enterprise policy; embedded scenarios need `allow="local-network-access"` on the iframe. [npm quickstart – Local Network Access Restrictions](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/npm-quickstart)

### Supported frameworks / build tools
- **Frameworks:** "React, Vue, and others" while "keeping full control over your UI and logic." [overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview)
- **Language/build:** TypeScript/JavaScript SPAs; **Vite** is the reference build tool; the starter template adds Tailwind CSS, Tanstack Query, React Router; samples also use Fluent UI React v9. [architecture](https://learn.microsoft.com/power-apps/developer/code-apps/architecture) · [README](https://github.com/microsoft/PowerAppsCodeApps/blob/main/README.md)
- The Power Apps client library reference is at **version 1.2.2** and is installed via `npm install @microsoft/power-apps`. [client library reference](https://learn.microsoft.com/javascript/api/powerapps-sdk-node/power-apps-client-lib-code-apps?view=powerapps-js-latest)

---

## 3. How data access works

### Connector-based, with generated typed clients
Code apps connect through **Power Platform connectors**. "All connectors are officially supported except" **Excel Online (Business)** and **Excel Online (OneDrive)**. [connect to data](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-data)

The workflow: (1) create/identify a **connection** in Power Apps (or, in preview, from the CLI); (2) add it to the app with `pac code add-data-source`; (3) call the generated service. "When you add the data sources to the app, the process **automatically generates a typed TypeScript model and service file** in the repo. For example, the Office 365 Users data source produces `Office365UsersModel` and `Office365UsersService` files." Generated files land under `src/generated/models` and `src/generated/services`. [connect to data](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-data)

Adding sources:
```powershell
# Non-tabular (e.g., Office 365 Users)
pac code add-data-source -a <apiName> -c <connectionId>
# Tabular (SQL / SharePoint) — needs table + dataset
pac code add-data-source -a <apiName> -c <connectionId> -t <tableId> -d <datasetName>
# SQL stored procedure
pac code add-data-source -a <apiId> -c <connectionId> -d <dataSourceName> -sp <storedProcedureName>
```
Helper discovery commands: `pac code list-datasets`, `pac code list-tables`, `pac code list-sql-stored-procedures`. Important gotcha: **there is no command to refresh a typed model when a connection's schema changes — you must delete and re-add the data source.** [connect to data](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-data)

Calling generated services (typed):
```typescript
import { Office365UsersService } from './generated/services/Office365UsersService';
const profile = (await Office365UsersService.MyProfile_V2("id,displayName,jobTitle")).data;
// Tabular CRUD:
await MobileDeviceInventoryService.getAll();
await MobileDeviceInventoryService.create(record);
await MobileDeviceInventoryService.update(id, changedFields);
await MobileDeviceInventoryService.delete(id);
```
[connect to data](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-data)

### ALM: connection references (portability across Dev/Test/Prod)
"Starting in version **1.51.1** of the Power Apps CLI released in **December 2025**, you can use **connection references** to add data sources … Instead of binding your app directly to a user-specific connection, bind it to a reference. This approach makes the solution environment-aware and portable across Dev, Test, and Prod environments." Command: `pac code add-data-source -a <apiName> -cr <connectionReferenceLogicalName> -s <solutionID>`. [connect to data – connection references](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-data)

### Dataverse (first-class data source)
Prerequisites: the client library, **PAC CLI version 1.46 or later**, and a Dataverse-enabled environment. Add a table with `pac code add-data-source -a dataverse -t <table-logical-name>`, which generates `AccountsModel.ts` / `AccountsService.ts` style files in `/generated/services/`. [connect to Dataverse](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-dataverse)

**Supported Dataverse scenarios:** add entities; retrieve formatted (label) values for option sets; get table metadata (`getMetadata`); work with lookups (single-valued navigation property / associate-on-create today); **image and file upload/download (preview)**; full **CRUD** (Create/Retrieve/RetrieveMultiple/Update/Delete); **delegation** for `Filter`, `Sort`, and `Top`; and **paging**. [connect to Dataverse – Supported scenarios](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-dataverse)

**Not yet supported for Dataverse:** polymorphic lookups; deleting Dataverse data sources through PAC CLI; schema/entity-metadata CRUD; **FetchXML**; and **alternate keys**. [connect to Dataverse – Unsupported scenarios](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-dataverse)

**Dataverse actions/functions:** the npm CLI `find-dataverse-api` (and `add-dataverse-api`) command generates typed services for bound/unbound Dataverse operations, writing `<ApiName>Service.ts` plus schema files and updating `power.config.json`. [add a Dataverse action or function](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/add-dataverse-action-function)

There is a complete **Dataverse sample app** (React/TypeScript) in the repo demonstrating CRUD, lookups, image/file upload/download, and generated services. [connect to Dataverse](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-dataverse) · [samples/Dataverse](https://github.com/microsoft/PowerAppsCodeApps/tree/main/samples/Dataverse)

### Azure and custom APIs
- **Azure SQL:** documented end-to-end via the **SQL Server connector** using **Microsoft Entra ID Integrated** authentication, including tables and **stored procedures** (`pac code add-data-source -a "shared_sql" ...`). End users see a **consent dialog** on first run. [connect to Azure SQL](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-azure-sql)
- **Arbitrary Azure/custom APIs:** reached the same way any Power Platform app reaches them — via a **custom connector** (an OpenAPI/Postman-defined connector), since "all connectors are officially supported" except the two Excel Online ones. Admin **consent-dialog suppression works for both Microsoft connectors and custom connectors that use OAuth (Microsoft Entra ID)**. [custom connectors overview](https://learn.microsoft.com/power-apps/maker/canvas-apps/register-custom-api) · [connect to data](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-data) · [overview – Managed platform](https://learn.microsoft.com/power-apps/developer/code-apps/overview)

> Practical implication vs. React + Azure App Service: you do **not** write your own data/API tier or manage secrets/tokens for these sources — the connector + generated typed client is the data layer, and OAuth/consent is handled by the platform. The trade-off is that everything must go **through a connector** (there is no first-party "call this Azure REST endpoint with a managed identity" path documented for code apps outside connectors), and schema changes require regenerating the typed client.

---

## 4. How code apps differ from canvas apps, model-driven apps, and PCF

| Dimension | **Code apps** | **Canvas apps** | **Model-driven apps** | **PCF (Power Apps Component Framework)** |
|---|---|---|---|---|
| What it is | A full **code-first SPA** (an *application*) hosted in Power Platform [overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview) | A **no-/low-code app** built on a drag-and-drop design surface [what are canvas apps](https://learn.microsoft.com/power-apps/maker/canvas-apps/getting-started) | A **metadata/data-driven app** whose UI is generated from Dataverse [Dataverse developer guide](https://learn.microsoft.com/power-apps/developer/data-platform/overview) | A **reusable code component** embedded *inside* canvas/model-driven apps — not a standalone app [React controls & platform libraries](https://learn.microsoft.com/power-apps/developer/component-framework/react-controls-platform-libraries) |
| Primary author | Pro developer [overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview) | Makers / citizen devs [what are canvas apps](https://learn.microsoft.com/power-apps/maker/canvas-apps/getting-started) | Makers + admins (app designer) [Dataverse developer guide](https://learn.microsoft.com/power-apps/developer/data-platform/overview) | Pro developer [React controls](https://learn.microsoft.com/power-apps/developer/component-framework/react-controls-platform-libraries) |
| Language / logic | TypeScript/JavaScript + your framework; **you own UI + logic** [overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview) | **Power Fx** formulas; declarative + imperative [Power Fx overview](https://learn.microsoft.com/power-platform/power-fx/overview) | Configuration + Dataverse; extend via plug-ins/JS/PCF [Dataverse developer guide](https://learn.microsoft.com/power-apps/developer/data-platform/overview) | TypeScript; implements `init`/`updateView`/`getOutputs`/`destroy` lifecycle [code components](https://learn.microsoft.com/power-apps/developer/component-framework/custom-controls-overview) |
| UI control | Full — arbitrary HTML/React/Vue [overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview) | High within canvas controls/Power Fx [what are canvas apps](https://learn.microsoft.com/power-apps/maker/canvas-apps/getting-started) | Low — standardized Unified Interface [Dataverse developer guide](https://learn.microsoft.com/power-apps/developer/data-platform/overview) | Scoped to the single control's surface [code components](https://learn.microsoft.com/power-apps/developer/component-framework/custom-controls-overview) |
| Data | Connectors (1,500+) + Dataverse via **generated typed services** [connect to data](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-data) | Connectors + Dataverse via Power Fx (delegation) [what are canvas apps](https://learn.microsoft.com/power-apps/maker/canvas-apps/getting-started) | **Dataverse only** — built on and stores its definition in Dataverse [Dataverse developer guide](https://learn.microsoft.com/power-apps/developer/data-platform/overview) | Bound to the host app's data/property; not a data platform itself [code components](https://learn.microsoft.com/power-apps/developer/component-framework/custom-controls-overview) |
| Scaffolding CLI | `pac code init` / `power-apps init` [npm quickstart](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/npm-quickstart) | Maker portal (no CLI) [what are canvas apps](https://learn.microsoft.com/power-apps/maker/canvas-apps/getting-started) | App designer / `AppModule` API [create model-driven apps using code](https://learn.microsoft.com/power-apps/developer/model-driven-apps/create-manage-model-driven-apps-using-code) | `pac pcf init` (`-fw react`) [React controls](https://learn.microsoft.com/power-apps/developer/component-framework/react-controls-platform-libraries) |
| Hosting/run | Standalone app, hosted by Power Platform host [architecture](https://learn.microsoft.com/power-apps/developer/code-apps/architecture) | Hosted by Power Platform; web/mobile/Teams [what are canvas apps](https://learn.microsoft.com/power-apps/maker/canvas-apps/getting-started) | Hosted by Power Platform (Unified Interface) [Dataverse developer guide](https://learn.microsoft.com/power-apps/developer/data-platform/overview) | Runs only inside a host canvas/model-driven app [React controls](https://learn.microsoft.com/power-apps/developer/component-framework/react-controls-platform-libraries) |

**One-line distinctions:**
- **vs. canvas:** same "start from the UI" philosophy and same connector access, but code apps replace Power Fx + the visual designer with your own **TypeScript/React/Vue codebase and IDE workflow**. Code apps follow canvas-app sharing limits and consent behavior. [overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview)
- **vs. model-driven:** model-driven apps are **Dataverse-only, metadata-generated UI**; code apps are UI-first, framework-based, and can use any connector (Dataverse optional). [Dataverse developer guide](https://learn.microsoft.com/power-apps/developer/data-platform/overview)
- **vs. PCF:** PCF produces a **component you drop into another app**, not an application; code apps are the application itself. (A code app cannot be embedded as a control the way a PCF control is.) [React controls & platform libraries](https://learn.microsoft.com/power-apps/developer/component-framework/react-controls-platform-libraries)

---

## 5. GA / preview status as of July 2026

**Product-level: GENERALLY AVAILABLE.** Microsoft announced GA on the first-party Power Platform blog dated **February 5, 2026**: "code apps in Power Apps are now generally available, empowering developers and IT alike." [GA blog](https://www.microsoft.com/en-us/power-platform/blog/power-apps/generally-available-host-and-run-code-apps-in-power-apps/) The GitHub repo README states "**Code apps are generally available**," and the docs overview treats the product as GA. [README](https://github.com/microsoft/PowerAppsCodeApps/blob/main/README.md) · [overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview)

**Sub-features / tooling still in PREVIEW (flagged clearly):**

| Area | Status | Source |
|---|---|---|
| New **npm-based CLI** (`power-apps init/run/push/find-dataverse-api`) | **Preview** (page title marked "(preview)") | [npm quickstart](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/npm-quickstart) |
| Classic **`pac code` command group** | **Preview**, and **to be deprecated** in favor of the npm CLI | [pac code reference](https://learn.microsoft.com/power-platform/developer/cli/reference/code) · [overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview) |
| **Create a connection from the CLI** | **Preview** | [connect to data](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-data) |
| Dataverse **image/file upload & download** | **Preview** | [connect to Dataverse](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-dataverse) |
| **Connection references** for data sources (ALM) | GA path, added in **CLI v1.51.1, December 2025** | [connect to data](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-data) |
| **Dataverse** as a data source | Supported/GA; requires **PAC CLI 1.46+** (with the preview caveats listed in §3) | [connect to Dataverse](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-dataverse) |

Note on the release plan: the **Power Apps 2025 wave 2** and **2026 wave 1** release-plan "planned features" pages do **not** carry a dedicated code-apps feature row in the sections retrieved (the wave content centers on modern controls, offline, Copilot/agents, and search). The authoritative GA signal is therefore the **GA blog + product docs + repo**, not a release-plan row. [2025 wave 2 planned features](https://learn.microsoft.com/power-platform/release-plan/2025wave2/power-apps/planned-features) · [2026 wave 1 planned features](https://learn.microsoft.com/power-platform/release-plan/2026wave1/power-apps/planned-features) (see Gaps, below).

**Version reference points (as of research date):** Power Apps client library reference page = **v1.2.2**; npm CLI shipped in `@microsoft/power-apps` **v1.0.4+**; Dataverse needs PAC CLI **1.46+**; connection references need CLI **1.51.1** (Dec 2025). [client library reference](https://learn.microsoft.com/javascript/api/powerapps-sdk-node/power-apps-client-lib-code-apps?view=powerapps-js-latest) · [overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview) · [connect to Dataverse](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-dataverse) · [connect to data](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-data)

---

## 6. Intended use cases (and non-use cases), per Microsoft

### What Microsoft says they are for
- **Governed line-of-business web apps built by professional developers.** The overview frames code apps as a way to "efficiently build and run business apps on a managed platform" and to enable "publishing and hosting of line-of-business web apps in Power Platform." [overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview)
- **Bridging developer flexibility and IT governance.** The GA blog: code apps "bring the full strength of Power Platform to web developers. Build in any code-first IDE, iterate locally, and run the same app seamlessly within Power Platform," and "**every code app automatically becomes a governed Power Platform asset, giving IT visibility and control without creating friction for developers.**" Positioned as combining "full code-first flexibility" for developers with "enterprise-grade guardrails" for IT. Target audiences: **developers** (familiar frameworks/IDEs) and **IT** (security/compliance/visibility). [GA blog](https://www.microsoft.com/en-us/power-platform/blog/power-apps/generally-available-host-and-run-code-apps-in-power-apps/)
- Governance features cited as the value-add over roll-your-own: zero-config Microsoft Entra ID auth, built-in connector authorization/consent, DLP enforcement at runtime, Conditional Access compliance, health monitoring, and ALM tooling. [GA blog](https://www.microsoft.com/en-us/power-platform/blog/power-apps/generally-available-host-and-run-code-apps-in-power-apps/)

> For the Fortune-500 evaluation, this is the core pitch vs. **React + Azure App Service**: you keep your React/TypeScript codebase and IDE loop, but you **offload auth, hosting, connector-based data access, DLP/Conditional Access/sharing governance, and ALM** to Power Platform — at the cost of a Power Apps Premium license per end user and the connector-only data model.

### Licensing
"End users that run code apps need a **Power Apps Premium** license." [overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview)

### What they are explicitly NOT for / current boundaries
The GA blog does not enumerate exclusions, but the docs list concrete limitations: [overview – Limitations](https://learn.microsoft.com/power-apps/developer/code-apps/overview)
- **No IP-based access restriction** on the hosting endpoint (compiled assets served from a public endpoint; use Conditional Access instead). [overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview) · [system configuration](https://learn.microsoft.com/power-apps/developer/code-apps/system-limits-configuration)
- **No Power Platform Git integration.** [overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview)
- **Not supported in Power Apps for Windows.** [overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview)
- **No Power BI data integration** (`PowerBIIntegration` function) yet — though a code app can be embedded in Power BI reports via the Power Apps visual. [overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview)
- **No SharePoint forms integration.** [overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview)
- **Excel Online (Business) and Excel Online (OneDrive) connectors are not yet supported.** [connect to data](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-data)

---

## Sources (all consulted; primary Microsoft only)

**Microsoft Learn — code apps docs**
- Overview: https://learn.microsoft.com/power-apps/developer/code-apps/overview
- Architecture: https://learn.microsoft.com/power-apps/developer/code-apps/architecture
- System configuration / limits: https://learn.microsoft.com/power-apps/developer/code-apps/system-limits-configuration
- Quickstart (create from scratch, PAC CLI): https://learn.microsoft.com/power-apps/developer/code-apps/how-to/create-an-app-from-scratch
- Quickstart with new npm CLI (preview): https://learn.microsoft.com/power-apps/developer/code-apps/how-to/npm-quickstart
- Connect to data (connectors, generated services, connection references): https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-data
- Connect to Dataverse: https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-dataverse
- Get table metadata: https://learn.microsoft.com/power-apps/developer/code-apps/how-to/get-table-metadata
- Add a Dataverse action or function: https://learn.microsoft.com/power-apps/developer/code-apps/how-to/add-dataverse-action-function
- Connect to Azure SQL: https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-azure-sql

**Microsoft Learn — CLI & client library**
- `pac code` reference (labeled Preview / deprecating): https://learn.microsoft.com/power-platform/developer/cli/reference/code
- Power Apps client library for code apps reference (v1.2.2): https://learn.microsoft.com/javascript/api/powerapps-sdk-node/power-apps-client-lib-code-apps?view=powerapps-js-latest

**Microsoft Learn — comparison anchors (other app types)**
- What are canvas apps: https://learn.microsoft.com/power-apps/maker/canvas-apps/getting-started
- Power Fx overview: https://learn.microsoft.com/power-platform/power-fx/overview
- Overview of creating apps in Power Apps: https://learn.microsoft.com/power-apps/maker/
- Dataverse developer guide (model-driven built on Dataverse): https://learn.microsoft.com/power-apps/developer/data-platform/overview
- Create/manage model-driven apps using code: https://learn.microsoft.com/power-apps/developer/model-driven-apps/create-manage-model-driven-apps-using-code
- PCF — React controls & platform libraries: https://learn.microsoft.com/power-apps/developer/component-framework/react-controls-platform-libraries
- PCF — code components overview: https://learn.microsoft.com/power-apps/developer/component-framework/custom-controls-overview
- Custom connectors for canvas apps: https://learn.microsoft.com/power-apps/maker/canvas-apps/register-custom-api

**Microsoft Learn — release plans**
- Power Apps 2025 wave 2 planned features: https://learn.microsoft.com/power-platform/release-plan/2025wave2/power-apps/planned-features
- Power Apps 2026 wave 1 planned features: https://learn.microsoft.com/power-platform/release-plan/2026wave1/power-apps/planned-features
- Power Apps 2026 wave 1 overview: https://learn.microsoft.com/power-platform/release-plan/2026wave1/power-apps/

**First-party Microsoft blog**
- GA announcement (Feb 5, 2026): https://www.microsoft.com/en-us/power-platform/blog/power-apps/generally-available-host-and-run-code-apps-in-power-apps/

**Official Microsoft GitHub**
- microsoft/PowerAppsCodeApps: https://github.com/microsoft/PowerAppsCodeApps
- README: https://github.com/microsoft/PowerAppsCodeApps/blob/main/README.md
- Templates: https://github.com/microsoft/PowerAppsCodeApps/tree/main/templates
- Samples: https://github.com/microsoft/PowerAppsCodeApps/tree/main/samples
- Dataverse sample: https://github.com/microsoft/PowerAppsCodeApps/tree/main/samples/Dataverse

---

## Gaps / open questions (could not confirm from a primary source)

- **Exact original public-preview date** for code apps. GA is firmly dated (Feb 5, 2026, first-party blog), but I did not find a primary page stating the initial preview announcement date. The topic brief says "announced in 2025"; treat the specific preview date as unconfirmed here.
- **Release-plan feature row for code apps.** The retrieved 2025 wave 2 and 2026 wave 1 Power Apps "planned features" pages did not surface a dedicated code-apps row; GA status rests on the blog + docs + repo. If a wave-specific row exists under a different product area (e.g., a developer/pro-dev or governance section), it was not located.
- **Connector count discrepancy.** The docs overview says **"1,500+ connectors"**; the GA blog phrasing (as fetched) said **"1,400+ connectors."** Minor and non-material, but noted.
- **Non-connector Azure calls.** Docs describe Azure/custom-API access exclusively **via connectors/custom connectors**. I found no primary doc describing a supported way for a code app to call an Azure REST API directly with a managed identity outside the connector model. If that path exists, it isn't documented in the code-apps section.
- **`@microsoft/power-apps` latest published version / release notes.** The client library reference page shows **v1.2.2** and the repo README notes GA, but I did not retrieve a primary changelog enumerating the very latest npm version and its dated release notes (GitHub Releases page was identified but not fetched in full).
- **Staleness:** No consulted page appeared stale relative to 2026-07-21. The 2025 wave 2 planned-features page metadata shows an update timestamp of **2026-06-17**, and code-apps how-to pages reference December 2025 / CLI 1.51.1 changes, indicating current maintenance.
