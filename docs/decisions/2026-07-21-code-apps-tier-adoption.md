# ADR: Adopt Power Platform code apps as a bounded portfolio tier

- **Date:** 2026-07-21
- **Status:** Accepted
- **Deciders:** Pro-code development organization (Fortune 500, internal apps)
- **Evidence base:** Four primary-source research briefs in `docs/research/`:
  - [Programming model & developer workflow](../research/2026-07-21-code-apps-programming-model.md)
  - [Licensing & distribution at scale](../research/2026-07-21-code-apps-licensing-distribution.md)
  - [ALM, CI/CD & governance](../research/2026-07-21-code-apps-alm-governance.md)
  - [Hard limits & developer adaptation](../research/2026-07-21-code-apps-limits-adaptation.md)

## Context

We evaluated whether to build internal applications as Power Platform **code apps** (React/TypeScript SPAs hosted by Power Apps, GA 2026-02-05) instead of full pro-code applications (React + our own Azure backend). The research established that a wholesale switch is not on the table:

- **Architectural exclusions.** Code apps do not run in the Power Apps Mobile player or Power Apps for Windows, and the default CSP (`worker-src 'none'`) blocks service workers, ruling out offline/PWA. These are architectural, not roadmap gaps.
- **Connector-only data tier.** All data access is connector-brokered with canvas-style delegation semantics (silent row truncation at 500/2,000), per-user daily request quotas (40,000 on Premium), a 120s synchronous ceiling, and no multi-row transaction/batch API.
- **Licensing.** Every end user needs Power Apps Premium; Microsoft 365 seeded rights do not cover code apps. Our target users **already hold Premium broadly**, so marginal license cost is ~$0 — this fact, not list pricing, is what makes the tier economically viable.
- **What survives from our practice.** The app is a normal React/TS repo; Git remains the sole source of truth (`pac code push` uploads compiled output only — there is no download), so our SAST/SCA/PR-review pipeline applies unchanged. Deployment is solution-based; auth is zero-config Entra ID with no custom-IdP escape hatch.
- **Live churn.** The `pac code` CLI is deprecated-in-progress in favor of a preview npm CLI; Test Studio/Test Engine do not cover code apps.

## Decision

Code apps become the **default for a bounded tier** of internal applications. Pro-code remains the path for everything outside it.

1. **Tier admission — all five criteria required:**
   1. Internal audience, desktop-browser only; no mobile, offline, or PWA requirement.
   2. Data fits the connector model: Dataverse/Azure SQL/SharePoint/existing APIs, interactive CRUD volumes, no bulk writes or multi-row transactions, queries that survive delegation limits.
   3. Request volume comfortably inside per-user quotas and the 120s synchronous ceiling.
   4. Entra-only auth; no external users or custom IdP.
   5. Owning team accepts solution-based deployment.
2. **Criticality carve-out:** no tier-1/business-critical apps in the tier for ~12 months (until the CLI migration settles and test tooling matures).
3. **Logic placement — documented default with visible deviation:** presentation logic in the SPA; simple CRUD apps go connector-direct; shared, transactional, long-running, or high-volume logic goes in our own Azure services behind thin custom connectors — not in the SPA, Power Automate flows, or Dataverse plugins. Teams may deviate without approval but must record the deviation in their app's repo.
4. **CI/CD — spike-gated:** a spike (trivial code app, solution export/import across two environments) answers whether a solution transports the compiled bundle or each environment needs its own `pac code push`. Default outcome: existing Azure DevOps/GitHub pipelines at the solution layer. Power Platform Pipelines only if the spike forces it.
   *Status 2026-07-21: spike attempted and halted — `pac code push` returned 403 `CodeAppOperationNotAllowedInEnvironment` (code app operations are disabled per environment by default; enabling them is a Power Platform admin center setting). Spike skipped by decision; the bundle-transport question remains **open** and the existing-CI default stands provisionally until it is answered.*
5. **Ownership:** platform engineering owns the paved road — environment baseline (including **enabling code app operations per environment**, which is off by default — confirmed empirically 2026-07-21), CSP allow-list (App Insights endpoint included from day one), DLP/Conditional Access coordination, CLI version policy, reference architecture — partnering with Power Platform admins on tenant-level settings.
6. **Rollout:** the tier opens to all teams when the paved road ships. No pilot gate.
7. **Verification items (non-gating, in parallel with paved-road build):** confirm with Microsoft (a) whether Managed Environments are strictly required for code apps, (b) whether code apps surface as a distinct type in admin-center inventory, (c) per-app PAYG validity for code apps (moot under broad Premium; relevant only for edge audiences).

## Consequences

**Gained:** developers keep their IDE, React/TS stack, Git, and existing CI/security scanning; the platform supplies hosting, Entra auth, connector-brokered data access, DLP/Conditional Access governance, and sharing at security-group scale — for ~$0 marginal license cost under current entitlements.

**Accepted trades:**
- First-mover teams absorb operational issues a pilot would have found centrally (mitigated by the criticality carve-out).
- The compiled bundle is served from a public endpoint with no IP restriction; mitigation is Conditional Access by location, and nothing sensitive ships in the bundle.
- Apps that outgrow connector ceilings migrate their logic to our Azure services behind custom connectors — which the logic-placement default anticipates, bounding both the ceiling and any future exit cost (the React front-end ports; SDK calls and generated connector services get rewritten).
- Toolchain churn risk is carried by platform engineering (pinned CLI versions, migration tracking) rather than by app teams.

**Revisit triggers:**
- EA/licensing posture changes such that target users no longer hold Premium broadly — the tier's economics re-open.
- Microsoft ships mobile-player or offline support for code apps — tier admission criterion 1.1 re-opens.
- CLI migration completes and test tooling matures — the criticality carve-out (point 2) sunsets on review, not automatically.
- The CI/CD spike contradicts the default — point 4's fallback activates and the paved-road pipeline design is revised before the tier opens.
