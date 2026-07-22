# Licensing, Pricing & Distribution of Power Apps Code Apps at Enterprise Scale

## Question

A pro-code developer at a Fortune 500 company wants to build **Power Apps code apps** (React/TypeScript SPAs on the Power Apps SDK, hosted in Power Platform) and distribute them to **thousands to tens of thousands** of internal users. What does each end user need to be licensed for, what does the developer need, what are the mid-2026 list prices, how does distribution work at scale, what capacity/consumption dimensions scale with users, and what would 5,000 users cost per month under each viable model?

*Research date: 2026-07-21. Primary sources only: learn.microsoft.com, the official Microsoft Power Platform Licensing Guide (July 2026), and first-party Microsoft pricing/licensing-news pages.*

---

## TL;DR

- **Every end user of a code app needs a paid Power Apps license. Microsoft states this explicitly and unconditionally:** "End users that run code apps need a Power Apps Premium license." ([code apps overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview#prerequisites)). There is no free/seeded path.
- **Microsoft 365 / Office 365 seeded Power Apps rights do NOT cover code apps.** M365 seeding ("Power Apps Basic") grants standard connectors and Dataverse for Teams only — not premium/custom connectors or full Dataverse ([Licensing Guide, July 2026, p.8](https://cdn-dynmedia-1.microsoft.com/is/content/microsoftcorp/microsoft/bade/documents/products-and-services/en-us/bizapps/Power-Platform-Licensing-Guide.pdf)). Code apps are treated as premium.
- **Two viable licensing models at scale:** (1) **Power Apps Premium** per user — **$20/user/month** (or **$12/user/month** with 2,000+ new per-user licenses), unlimited apps; (2) **Power Apps per app pay-as-you-go meter** — **$10 per active user/app/month** via Azure, one app ([official pricing](https://www.microsoft.com/power-platform/products/power-apps/pricing); [Licensing Guide p.8](https://cdn-dynmedia-1.microsoft.com/is/content/microsoftcorp/microsoft/bade/documents/products-and-services/en-us/bizapps/Power-Platform-Licensing-Guide.pdf)).
- **The old fixed Power Apps *per-app subscription* is being retired.** Effective **January 2, 2026** it is no longer sold to new customers; only existing EA and CSP customers can keep/renew it ([Microsoft licensing news](https://www.microsoft.com/en-us/licensing/news/power-app-per-app-end-of-sale)). New adopters should plan on Premium or the per-app PAYG meter.
- **Developers build for free.** The **Power Apps Developer Plan** gives up to 3 free developer environments with Dataverse; no license is needed to build canvas/code apps. Dev tooling (VS Code, Node.js, Power Apps CLI/npm CLI) is free ([Developer Plan](https://learn.microsoft.com/power-platform/developer/create-developer-environment); [licensing FAQ](https://learn.microsoft.com/power-platform/admin/powerapps-licensing-faq)).
- **Distribution is share-with-Entra-security-group, exactly like canvas apps.** Use a security group when sharing beyond ~100 users; code apps follow canvas-app sharing limits and Managed Environment governance ([share a canvas app](https://learn.microsoft.com/power-apps/maker/canvas-apps/share-app#classic-app-sharing-experience); [code apps overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview)).
- **Dataverse is NOT required to run a code app**, but it is required if the app uses Dataverse as a data source or uses solution-based ALM ([connect to Dataverse](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-dataverse); [push to solution](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/push-to-solution)).
- **Request limits scale per user:** Power Apps Premium = **40,000 Power Platform requests/user/24h**; per-app/PAYG/M365 users = **6,000/user/24h** ([requests limits](https://learn.microsoft.com/power-platform/admin/api-request-limits-allocations#licensed-user-request-limits)).
- **5,000-user monthly cost:** Premium list **$100,000/mo**; Premium volume ($12) **$60,000/mo**; per-app PAYG **up to $50,000/mo** (bills only users who open the app that month) — see the Cost Sketch section.

---

## 1. What an END USER needs to run a code app

**Bottom line: a paid Power Apps license — Microsoft names Power Apps Premium specifically.**

The code apps overview page has a dedicated heading, "License end users with Power Apps Premium," stating: *"End users that run code apps need a [Power Apps Premium license](https://www.microsoft.com/power-platform/products/power-apps/pricing)."* ([code apps overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview#prerequisites)). This is the single most load-bearing fact for the adoption decision, and it is unambiguous in first-party docs.

### Code apps vs canvas apps — what each requires

For **canvas apps**, the required license depends on the connectors/features used ([license designation](https://learn.microsoft.com/power-apps/maker/canvas-apps/license-designation)):

- **Standard** app (standard connectors only): end user can run it with a Microsoft 365 / Office 365 plan (seeded rights), a Power Apps per app plan, or a per-user plan.
- **Premium** app (≥1 premium connector, custom connector, on-prem gateway, or Dataverse): end user needs a per-app or per-user Power Apps license. M365 seeded rights do **not** cover premium apps.

**Code apps do not get the "standard app" discount.** The docs direct you to Power Apps *Premium* for end users regardless of what the code app connects to. This is consistent with how the platform treats code: the Power Apps component framework doc notes that code components which connect to external services/data "directly through the user's browser client" make the app **premium**, and end users then need **Power Apps** licenses ([component framework licensing](https://learn.microsoft.com/power-apps/developer/component-framework/overview#licensing)). A code app is, by construction, custom code calling connectors/APIs from the browser — so treat it as premium in every case.

### Do Microsoft 365 seeded rights cover code apps? No.

The July 2026 Licensing Guide defines the M365/Office 365 grant as **"Power Apps Basic"**: *"limited Power Apps use rights included with select Microsoft 365 and Office 365 licenses… allows users to customize and extend Microsoft 365 and Office 365 for productivity scenarios, and to deliver a comprehensive low-code extensibility platform for Microsoft Teams only."* The capabilities matrix on p.8 shows Microsoft 365/Office 365 licenses grant **standard connectors** and **Dataverse for Teams only** — **no** premium/custom connectors and **no** full Dataverse ([Licensing Guide, July 2026, p.7-9](https://cdn-dynmedia-1.microsoft.com/is/content/microsoftcorp/microsoft/bade/documents/products-and-services/en-us/bizapps/Power-Platform-Licensing-Guide.pdf)). Appendix B lists the qualifying M365/O365 SKUs (Office 365 E1/E3/E5/F3; M365 Business Basic/Standard/Premium; M365 F3/E3/E5, etc.) — all limited to that Basic grant. Since code apps require Premium, **no Microsoft 365 or Office 365 license by itself ever entitles a user to run a code app.**

---

## 2. What a DEVELOPER needs

**Building and testing is free.**

- **No license to build.** "You don't need a license to build canvas apps" ([Power Apps licensing FAQ](https://learn.microsoft.com/power-platform/admin/powerapps-licensing-faq)). Code apps build on the canvas/maker model; the cost gate is on *running* the published app, not authoring it.
- **Free Power Apps Developer Plan.** Gives up to **3 developer-type environments** with Dataverse included, for building/testing Power Apps, Power Automate, and Dataverse ([get a developer environment](https://learn.microsoft.com/power-apps/maker/maker-create-environment); [create a developer environment](https://learn.microsoft.com/power-platform/developer/create-developer-environment)). Developer environments are single-user and not for production.
- **Free dev tooling.** Code apps require VS Code (or any IDE), Node.js LTS, Git, and the Power Apps CLI / new npm-based CLI (`@microsoft/power-apps`) — all free ([code apps overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview#prerequisites); [npm quickstart](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/npm-quickstart)).
- **Admin must enable code apps on the environment.** A Power Platform / environment admin flips **Settings → Product → Features → Power Apps code apps → Enable**. This can be applied to many environments at once via environment groups/rules ([code apps overview](https://learn.microsoft.com/power-apps/developer/code-apps/overview#enable-code-apps-on-a-power-platform-environment)).
- **Caveat:** a developer who wants to *run* their own app in a **production/managed** environment (not just the dev environment) needs the same Power Apps Premium entitlement as any end user.

---

## 3. List pricing (mid-2026)

All figures below are list prices from the **official Microsoft Power Apps pricing page** and the **Power Platform Licensing Guide (July 2026 edition, PDF metadata created 2026-06-25)**. *Prices change; verify at purchase time. Sources: [powerapps pricing](https://www.microsoft.com/power-platform/products/power-apps/pricing) and [Licensing Guide PDF](https://cdn-dynmedia-1.microsoft.com/is/content/microsoftcorp/microsoft/bade/documents/products-and-services/en-us/bizapps/Power-Platform-Licensing-Guide.pdf).*

### End-user run licenses

| Offer | List price | Scope | Notes |
|---|---|---|---|
| **Power Apps Premium** (per user) | **$20.00 / user / month**, billed annually | Unlimited custom apps + unlimited Power Pages websites | Includes premium & custom connectors, full Dataverse access, Managed Environments. Accrues 250 MB Dataverse DB + 2 GB file per license. |
| **Power Apps Premium — volume tier** | **$12.00 / user / month**, billed annually | Same as above | Requires **2,000+ new per-user licenses**. Directly relevant to a 5,000-seat Fortune 500 rollout. |
| **Power Apps per app pay-as-you-go meter** ("Power Apps Per App Active User-1") | **$10.00 per active user / app / month**, billed via linked Azure subscription | **One** app per meter | Bills only users who open that app ≥1 time in the month. Managed Environments included (Power Apps usage only). Environment gets a one-time 1 GB DB + 1 GB file entitlement. |
| Power Apps per app **subscription** (fixed) | *Not listed in July 2026 guide* | One app | **End of sale for new customers as of Jan 2, 2026** — see §7. Historically ~$5/user/app/month; do not plan new deployments around it. |
| Microsoft 365 / Office 365 ("Power Apps Basic") | Included in M365/O365 | Standard connectors + Dataverse for Teams only | **Does not cover code apps.** |

### Dataverse capacity add-ons (subscription)

| Add-on | Increment | Price |
|---|---|---|
| Dataverse Database capacity | 1 GB | **$40 / GB / month** (billed annually) |
| Dataverse Database Tier 2 (1,000 GB min) | 1 GB | **$30 / GB / month** |
| Dataverse File capacity | 1 GB | **$2 / GB / month** |
| Dataverse Log capacity | 1 GB | **$10 / GB / month** |

### Dataverse capacity meters (pay-as-you-go, per environment overage)

| Meter | Increment | Price |
|---|---|---|
| Dataverse Database capacity | 1 GB | **$48 / GB / month** |
| Dataverse File capacity | 1 GB | **$2.40 / GB / month** |
| Dataverse Log capacity | 1 GB | **$12 / GB / month** |

*(Licensing Guide, July 2026, pp.21-22.)*

### Power Platform requests as a PAYG meter

Overage above the daily request entitlement (see §5) can be billed via the Power Platform requests meter — the guide's illustrative example uses **$0.00004 per request** ([pay-as-you-go meters](https://learn.microsoft.com/power-platform/admin/pay-as-you-go-meters#how-do-meters-work), noting "prices shown… are illustrative only").

---

## 4. Distribution & sharing at scale

### Sharing model — same as canvas apps

Code apps are shared through the standard Power Apps sharing experience. You can share with **individual users or a Microsoft Entra ID security group** ([share a canvas app](https://learn.microsoft.com/power-apps/maker/canvas-apps/share-app#share-an-app-from-power-apps)). Microsoft's explicit guidance for scale:

- *"To avoid degraded experiences, use a security group when sharing the app with over 100 users."* ([share a canvas app – classic sharing](https://learn.microsoft.com/power-apps/maker/canvas-apps/share-app#classic-app-sharing-experience)).
- You **cannot** share with a distribution group or an external group, and you **cannot request licenses for a security group** (only for named individuals) ([request licenses](https://learn.microsoft.com/power-apps/maker/common/request-licenses-for-users)).
- **Share with "Everyone" is disabled by default** and discouraged (it includes all guests who ever signed in). Use a curated security group for org-wide reach ([secure the default environment](https://learn.microsoft.com/power-platform/guidance/adoption/secure-default-environment#prevent-oversharing)).

So the practical distribution pattern for 5,000-50,000 users is: **create/assign an Entra security group, license its members with Power Apps Premium (or PAYG-meter the app), and share the app to the group.** Group membership becomes your access + license-scoping mechanism.

### Managed Environments and sharing governance

Code apps run under **Managed Platform** policies. The code apps overview confirms sharing limits, app quarantine, DLP enforcement at launch, and Conditional Access on an individual app all apply, and that **"Code apps follow canvas app sharing limits."** ([code apps overview – managed platform capability support](https://learn.microsoft.com/power-apps/developer/code-apps/overview)). Managed Environments let admins **limit sharing** — e.g., "Exclude sharing with security groups," or cap the number of individuals an app can be shared to ([limit sharing](https://learn.microsoft.com/power-platform/admin/managed-environment-sharing-limits)). If your governance excludes security-group sharing, that directly constrains large-scale distribution, so align the environment's sharing policy with the rollout plan.

Managed Environments is **included** as an entitlement with Power Apps Premium, Power Apps per app, and the per-app PAYG meter ([licensing FAQ – managed environments](https://learn.microsoft.com/power-platform/admin/powerapps-flow-licensing-faq#power-platform-security-and-governance-licensing-requirements); [Licensing Guide p.24](https://cdn-dynmedia-1.microsoft.com/is/content/microsoftcorp/microsoft/bade/documents/products-and-services/en-us/bizapps/Power-Platform-Licensing-Guide.pdf)). **Enforcement is tightening in 2026:** once an environment is a Managed Environment, *all* active users must hold a qualifying premium license; admin notifications begin **March 2026** and end-user in-app "get a license" notifications begin **June 2026** ([managed environment licensing](https://learn.microsoft.com/power-platform/admin/managed-environment-licensing#faq)). Note footnote 1 of the guide: limited use rights from Dynamics 365 / Microsoft 365 do **not** count as the required "standalone license."

### Environment strategy

Microsoft's enterprise guidance separates **developer** environments (per-maker, relaxed policy, limited scale), **sandbox/test**, and **production** environments ([tenant environment strategy](https://learn.microsoft.com/power-platform/guidance/adoption/environment-strategy)). Code apps support standard **ALM**: put the app in a Dataverse **solution** and export/import dev → test → prod ([code app ALM](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/alm); [push to solution](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/push-to-solution)). Access to an environment can additionally be gated with an Entra security group at the environment level ([control user access](https://learn.microsoft.com/power-platform/admin/control-user-access)).

### Does a code app require Dataverse?

- **To run:** No. The npm CLI can "Deploy safely to environments **without** Dataverse. The app still pushes, just without a solution." ([push to solution](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/push-to-solution)).
- **To use Dataverse data:** Yes — connecting a code app to Dataverse requires "an environment with Dataverse enabled" ([connect to Dataverse](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-dataverse)), and end users invoking flows/Dataverse need appropriate Dataverse security roles (e.g., **App Opener**) ([add flows](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/add-flows#removing-a-flow)).
- **For solution-based ALM:** Yes — the ALM path lists "A Power Platform environment with Dataverse" as a prerequisite ([code app ALM](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/alm)).

---

## 5. Capacity & consumption dimensions that scale with users

### Power Platform request limits (per user, per day — NOT poolable)

Each user's daily request ceiling is set by their license ([requests limits and allocations](https://learn.microsoft.com/power-platform/admin/api-request-limits-allocations#licensed-user-request-limits)):

| License | Requests per user / 24 hours |
|---|---|
| Power Apps **per user** (Premium) and most paid Power Platform/D365 licenses | **40,000** |
| **Power Apps per app**, **Power Apps pay-as-you-go**, **Microsoft 365** licenses, D365 Team Member | **6,000** |
| Power Automate per flow / Copilot Studio | 250,000 |

A "Power Platform request" = every connector call **and** every Dataverse CRUD/assign/share operation, from any client ([what is a request](https://learn.microsoft.com/power-platform/admin/api-request-limits-allocations)). Limits are tracked per individual user and **cannot be pooled** ([licensing FAQ](https://learn.microsoft.com/power-platform/admin/powerapps-flow-licensing-faq#power-platform-product-licensing)). **Implication:** a chatty code app (many connector/Dataverse calls per interaction) can approach the 6,000/day ceiling under a per-app/PAYG license faster than under Premium's 40,000/day — this is a real reason to prefer Premium for data-intensive apps. Overages are billed via the requests PAYG meter (illustrative $0.00004/request) rather than hard-blocking.

### Dataverse storage (tenant-pooled for subscriptions)

Only relevant if the code app uses Dataverse. Entitlements accrue to a tenant-wide pool ([Dataverse capacity FAQ](https://learn.microsoft.com/power-platform/admin/powerapps-flow-licensing-faq#dataverse); [Licensing Guide p.21](https://cdn-dynmedia-1.microsoft.com/is/content/microsoftcorp/microsoft/bade/documents/products-and-services/en-us/bizapps/Power-Platform-Licensing-Guide.pdf)):

- **First** Power Apps Premium purchase → tenant gets a one-time default **10 GB** Dataverse Database capacity.
- **Per Power Apps Premium license accrual:** +250 MB Database, +2 GB File.
- **Per Power Apps per app license accrual:** +50 MB Database, +400 MB File.
- **PAYG environments** get only **1 GB DB + 1 GB File per environment** (no per-user accrual); overage flows to Dataverse capacity meters ($48/GB DB, $2.40/GB File per month).

Worked example from the guide: 10 Premium + 20 Power Automate Premium licenses → 10 GB default + (10+20)×250 MB = 17.5 GB DB pooled, 20 GB default + (10+20)×2 GB = 80 GB File.

### Other metered dimensions

- **Power Automate/RPA:** Power Apps' included flow rights don't include RPA; that needs Power Automate Premium ([Licensing Guide p.8, note 4](https://cdn-dynmedia-1.microsoft.com/is/content/microsoftcorp/microsoft/bade/documents/products-and-services/en-us/bizapps/Power-Platform-Licensing-Guide.pdf)).
- **AI Builder / Copilot:** In-app AI ("App skills," Copilot) requires Power Apps Premium and, for Microsoft 365 Copilot agents, a Microsoft 365 Copilot license; agent customizations consume Copilot Credits (guide p.8-9, notes 5-6). Not required for a plain code app.

---

## 6. Worked cost sketch — 5,000 internal users, one code app

All arithmetic uses the cited July 2026 list prices. Annual = monthly × 12. *These are license run-costs only; add Dataverse capacity add-ons if the app's Dataverse footprint exceeds the pooled entitlement, and Power Automate Premium if it uses RPA.*

### Model A — Power Apps Premium per user (list)
```
5,000 users × $20 / user / month  = $100,000 / month
                                  = $1,200,000 / year
```
Covers **unlimited** code apps + Power Pages per user; 40,000 requests/user/day; +250 MB DB & +2 GB file pooled per user.

### Model B — Power Apps Premium per user (volume tier, 2,000+ new per-user licenses)
```
5,000 users × $12 / user / month  = $60,000 / month
                                  = $720,000 / year
```
Same entitlements as Model A; the $12 rate is available because 5,000 > the 2,000 new-per-user-license threshold ([Licensing Guide p.8](https://cdn-dynmedia-1.microsoft.com/is/content/microsoftcorp/microsoft/bade/documents/products-and-services/en-us/bizapps/Power-Platform-Licensing-Guide.pdf)).

### Model C — Power Apps per app pay-as-you-go meter ($10 / active user / app / month)
The meter bills only **unique active users who open the app in the month**, for **one** app.
```
If all 5,000 open it every month:   5,000 × $10 = $50,000 / month = $600,000 / year
If ~60% open it in a given month:   3,000 × $10 = $30,000 / month = $360,000 / year
If ~30% open it in a given month:   1,500 × $10 = $15,000 / month = $180,000 / year
```
Per-app PAYG environments get only 1 GB DB + 1 GB File; heavy Dataverse use adds capacity-meter cost. Each **additional** code app is billed on its own meter (a user who opens 2 apps in a month = 2 × $10).

### Model D — legacy per-app subscription (existing EA/CSP only; NOT for new adoption)
Retired for new customers Jan 2, 2026 (§7); not listed in the current guide. Historically ~$5/user/app/month → 5,000 × $5 = **$25,000/month = $300,000/year** for one app, *if* your enterprise already holds this SKU under EA/CSP. Treat as unavailable for a fresh deployment and unconfirmable from the current primary guide.

### Choosing between Premium and per-app PAYG

| Situation | Cheaper model |
|---|---|
| Single code app, essentially all 5,000 use it every month | PAYG at $10 (Model C, $50k) **undercuts** Premium volume at $12 (Model B, $60k) — but only for one app |
| Users run **2+** premium/code apps | Premium — 2 × $10 PAYG = $20/user > $12 Premium; Premium is unlimited apps |
| Intermittent usage (a fraction open the app monthly) | PAYG — you pay only for active users, potentially far below Model B |
| Predictable fixed budget, broad app portfolio, data-intensive apps (needs 40k req/day) | Premium |

**Rule of thumb:** PAYG wins for a *single*, *intermittently used* app; Premium wins for *always-on* usage, *multiple* apps per user, or *request-heavy* apps.

---

## 7. Enterprise / volume-licensing nuances Microsoft documents publicly

- **Volume price break is real and documented:** $20 → **$12 per user/month at 2,000+ new per-user licenses** ([Licensing Guide p.8](https://cdn-dynmedia-1.microsoft.com/is/content/microsoftcorp/microsoft/bade/documents/products-and-services/en-us/bizapps/Power-Platform-Licensing-Guide.pdf); mirrored on the [pricing page](https://www.microsoft.com/power-platform/products/power-apps/pricing)).
- **Per-app subscription end of sale (Jan 2, 2026):** the fixed per-app SKU "is no longer available for purchase by new customers." Existing **EA** customers keep and can renew it (with normal annual true-up); existing **CSP** customers unaffected (availability restored ~April 2026); **MPSA** customers keep it until agreement end then get a 60-day migration window. Microsoft consolidates guidance toward **Power Apps Premium** and the **per-app PAYG meter** ([Microsoft licensing news – per app end of sale](https://www.microsoft.com/en-us/licensing/news/power-app-per-app-end-of-sale)). The July 2026 guide reflects this: its "recommended motion" table lists only Premium and the per-app PAYG meter.
- **PAYG requires an Azure subscription** linked for billing; overages (requests, Dataverse) show up in Azure Cost Management ([pay-as-you-go meters](https://learn.microsoft.com/power-platform/admin/pay-as-you-go-meters)).
- **Auto-claim / license reporting:** admins can enable an M365 **auto-claim policy** to assign Premium to active users automatically, and pull a "Users requiring licenses in managed environments" report to find under-licensed users ([managed environment licensing](https://learn.microsoft.com/power-platform/admin/managed-environment-licensing#faq)).
- **Non-profit, government, and academic pricing** exists in the respective channels ([licensing FAQ](https://learn.microsoft.com/power-platform/admin/powerapps-flow-licensing-faq#power-platform-product-licensing)).
- **Buying channel:** Power Platform plans are purchased by M365 admins / through EA/CSP; self-service purchase is also available for some SKUs ([licensing FAQ](https://learn.microsoft.com/power-platform/admin/powerapps-flow-licensing-faq)).

---

## Sources

Primary (first-party Microsoft) sources used:

- Power Apps code apps overview — https://learn.microsoft.com/power-apps/developer/code-apps/overview
- Code apps: connect to Dataverse — https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-dataverse
- Code apps: push to solution — https://learn.microsoft.com/power-apps/developer/code-apps/how-to/push-to-solution
- Code apps: ALM — https://learn.microsoft.com/power-apps/developer/code-apps/how-to/alm
- Code apps: add flows — https://learn.microsoft.com/power-apps/developer/code-apps/how-to/add-flows
- Code apps: npm CLI quickstart — https://learn.microsoft.com/power-apps/developer/code-apps/how-to/npm-quickstart
- Power Apps component framework – licensing — https://learn.microsoft.com/power-apps/developer/component-framework/overview#licensing
- License designation (canvas apps) — https://learn.microsoft.com/power-apps/maker/canvas-apps/license-designation
- Power Apps licensing FAQ — https://learn.microsoft.com/power-platform/admin/powerapps-licensing-faq
- Power Platform licensing FAQs — https://learn.microsoft.com/power-platform/admin/powerapps-flow-licensing-faq
- Requests limits and allocations — https://learn.microsoft.com/power-platform/admin/api-request-limits-allocations
- Pay-as-you-go meters — https://learn.microsoft.com/power-platform/admin/pay-as-you-go-meters
- Managed environment licensing (compliance/enforcement) — https://learn.microsoft.com/power-platform/admin/managed-environment-licensing
- Managed environment sharing limits — https://learn.microsoft.com/power-platform/admin/managed-environment-sharing-limits
- Share a canvas app — https://learn.microsoft.com/power-apps/maker/canvas-apps/share-app
- Request Power Apps licenses for users — https://learn.microsoft.com/power-apps/maker/common/request-licenses-for-users
- Control user access with security groups — https://learn.microsoft.com/power-platform/admin/control-user-access
- Tenant environment strategy — https://learn.microsoft.com/power-platform/guidance/adoption/environment-strategy
- Get a developer environment — https://learn.microsoft.com/power-apps/maker/maker-create-environment
- Create a developer environment (Developer Plan) — https://learn.microsoft.com/power-platform/developer/create-developer-environment
- **Official pricing page** — https://www.microsoft.com/power-platform/products/power-apps/pricing
- **Power Platform Licensing Guide, July 2026 (PDF)** — https://cdn-dynmedia-1.microsoft.com/is/content/microsoftcorp/microsoft/bade/documents/products-and-services/en-us/bizapps/Power-Platform-Licensing-Guide.pdf
- **Microsoft licensing news – Power Apps per app end of sale** — https://www.microsoft.com/en-us/licensing/news/power-app-per-app-end-of-sale

---

## Gaps / open questions

Where the licensing guide and code-apps docs are silent or ambiguous *specifically about code apps*, I flag it here rather than inferring from canvas rules:

1. **"Premium" is asserted but not itemized for code apps.** The code apps overview flatly says end users need Power Apps *Premium*. It does **not** explicitly say the per-app PAYG meter is an accepted substitute for a code app. Because a code app is a single custom app governed like a premium canvas app, the per-app PAYG meter *should* qualify (the meter is designed for "run one custom application" and satisfies Managed Environment licensing for Power Apps usage), but **Microsoft's code-apps docs never name the per-app meter**. Confirm with your Microsoft licensing contact before basing a rollout on PAYG for code apps.
2. **Is a Managed Environment strictly *required* to run a code app?** The docs say code apps *adhere to* Managed Platform policies and *follow canvas-app sharing limits*, and list Managed-Environment features (quarantine, per-app Conditional Access, DLP) as supported — but I found **no first-party statement that a code app can only run in a Managed Environment.** If it is required, the June 2026 all-users-need-premium enforcement applies wholesale. Treat "Managed Environment required" as likely-but-unconfirmed and verify in the admin center for your target environment.
3. **Exact current per-app *subscription* price is unconfirmable from primary sources** — it has been removed from the July 2026 guide because of the Jan 2026 end of sale. The ~$5 figure comes from historical/secondary knowledge, so Model D is illustrative only and applies only to existing EA/CSP holders.
4. **Request-limit behavior of code apps specifically** (how many Power Platform requests a typical code-app session consumes) is not documented; the 6,000 vs 40,000/day distinction matters most for data-heavy apps and should be load-tested.
5. **Guide currency:** the guide used is the **July 2026** edition (PDF created 2026-06-25), current as of this research (2026-07-21) — not stale. The official pricing page corroborated the $20 / $12 / $10 figures on the same date. Re-verify both before contract, since Microsoft revises the guide monthly.
