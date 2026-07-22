# Power Platform Code Apps Resources

## Knowledge

### Local briefs (compressed, cited — start here)
- [Programming model & developer workflow](../docs/research/2026-07-21-code-apps-programming-model.md)
  What a code app is, architecture, SDK, CLI workflow, comparison to canvas/model-driven/PCF. Use for: mental model, "what is it" questions.
- [Licensing & distribution at scale](../docs/research/2026-07-21-code-apps-licensing-distribution.md)
  Premium requirement, M365 gap, list prices, 5,000-seat cost sketch, request quotas. Use for: any money or seat question.
- [ALM, CI/CD & governance](../docs/research/2026-07-21-code-apps-alm-governance.md)
  Git one-way flow, solutions, pipelines, DLP, Conditional Access, auth, testing. Use for: "does our DevOps survive" questions.
- [Hard limits & developer adaptation](../docs/research/2026-07-21-code-apps-limits-adaptation.md)
  No mobile/offline, delegation semantics, CSP, quotas, lock-in asymmetry. Use for: tier-admission reviews and the honest cons list.
- [The tier ADR](../docs/decisions/2026-07-21-code-apps-tier-adoption.md)
  The decision itself — the case study every lesson ties back to.

### Primary sources
- [Code apps overview — Microsoft Learn](https://learn.microsoft.com/power-apps/developer/code-apps/overview)
  The front door. Use for: definitions, prerequisites, licensing statement.
- [Code apps architecture — Microsoft Learn](https://learn.microsoft.com/power-apps/developer/code-apps/architecture)
  What runs where; host vs. app responsibilities. Use for: the runtime mental model.
- [System limits & configuration — Microsoft Learn](https://learn.microsoft.com/power-apps/developer/code-apps/system-limits-configuration)
  CSP, size limits, unsupported hosts. Use for: hard-limit citations.
- [Connect to data / Dataverse — Microsoft Learn](https://learn.microsoft.com/power-apps/developer/code-apps/how-to/connect-to-data)
  The connector data tier and generated typed clients. Use for: data-layer questions.
- [pac code CLI reference — Microsoft Learn](https://learn.microsoft.com/power-platform/developer/cli/reference/code)
  CLI commands (preview; being replaced by the npm CLI). Use for: workflow specifics.
- [GA announcement — Power Platform blog](https://www.microsoft.com/en-us/power-platform/blog/power-apps/generally-available-host-and-run-code-apps-in-power-apps/)
  GA date (2026-02-05) and positioning. Use for: status and roadmap claims.
- [Power Platform Licensing Guide (PDF)](https://cdn-dynmedia-1.microsoft.com/is/content/microsoftcorp/microsoft/bade/documents/products-and-services/en-us/bizapps/Power-Platform-Licensing-Guide.pdf)
  The licensing authority. Use for: entitlements; note it lags new features — flag silence, don't infer.
- [Power Apps pricing](https://www.microsoft.com/power-platform/products/power-apps/pricing)
  List prices. Use for: cost sketches (prices change — always re-check).
- [Request limits & allocations — Microsoft Learn](https://learn.microsoft.com/power-platform/admin/api-request-limits-allocations#licensed-user-request-limits)
  Per-user daily request quotas by license. Use for: throughput ceilings.
- [microsoft/PowerAppsCodeApps — GitHub](https://github.com/microsoft/PowerAppsCodeApps)
  Templates, samples, candid limitations in docs/issues. Use for: what Learn doesn't say yet.

## Wisdom (Communities)

- [microsoft/PowerAppsCodeApps Discussions](https://github.com/microsoft/PowerAppsCodeApps/discussions)
  Highest-signal venue; Microsoft engineers answer directly (the "no mobile ETA" admission came from here). Use for: roadmap reality checks, gaps.
- [Power Apps community forum](https://community.powerplatform.com/forums/thread/?groupid=24bb08d6-c396-4a3c-9048-83a9c83d3b78)
  Official forum; mixed signal, occasionally staffed by Microsoft. Use for: error-message archaeology.

## Gaps

- No dedicated code-apps entry located in official release plans — GA status rests on blog + docs + repo.
- Licensing Guide is silent on per-app PAYG validity for code apps specifically — unresolved; ask the Microsoft licensing contact.
- No first-party "when NOT to use code apps" guidance exists — our limits brief fills this, but it's inference from documented constraints.
