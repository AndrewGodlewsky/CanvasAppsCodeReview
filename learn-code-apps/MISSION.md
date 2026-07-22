# Mission: Power Platform Code Apps — Lead the Tier

## Why
Our Fortune 500 org decided (ADR, 2026-07-21) to adopt code apps as a bounded portfolio tier. I need to become the internal authority on that tier: the person who defends the decision to stakeholders, sets the reference architecture, and reviews other teams' code-app designs — without escalating to Microsoft or re-reading docs mid-meeting.

## Success looks like
- Explain the code-app runtime architecture (what the host provides vs. what our code owns) unaided, to an executive or an engineer.
- Defend every clause of the tier ADR — admission criteria, logic-placement default, CI/CD path — from primary sources when challenged.
- Review a proposed code app and spot tier violations on sight: delegation traps, quota risks, CSP/telemetry gaps, logic buried in flows.
- Answer licensing questions (who needs Premium, what M365 covers, request quotas, the 5,000-seat math) without looking them up.

## Constraints
- Learning happens in Claude Code sessions in this repo; lessons are self-contained, printable HTML.
- Primary sources only (Microsoft Learn, the Licensing Guide, microsoft/PowerAppsCodeApps) — never community lore.
- The hands-on build track is deliberately deferred (environment code-app toggle not enabled yet).

## Out of scope
- Hands-on building (scaffold / push / deploy) — revisit when leading is fluent; would shift the mission.
- Canvas app authoring, Power Fx, PCF development.
- Non-Microsoft low-code platforms.
