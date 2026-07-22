# Teaching Notes

## Learner preferences
- Pro-code developer (React/TS, mature Git/CI practice) — never re-teach general programming, Git, or CI concepts.
- Prefers primary sources; distrusts community lore. Cite everything.
- Likes recommendations stated up front with reasoning (chose "Recommended" options in grilling, but pushed back once — engages critically, don't soften trade-offs).
- Mission chosen: **Lead the tier** (knowledge track). Hands-on build track explicitly deferred.
- Context: ran the full research → grilling → ADR flow on 2026-07-21. Has *seen* summaries of everything — exposure, not retention. Lessons should assume familiarity with the vocabulary but verify understanding via retrieval.

## Curriculum map (planned; one lesson per session-ish, ZPD permitting)
1. `0001` The code-app mental model — what runs where ✓ (2026-07-21)
2. `0002` The four app models — code vs canvas vs model-driven vs PCF (the "why not canvas?" stakeholder answer)
3. `0003` Licensing — who pays what (Premium, the M365 gap, quotas, the 5,000-seat math)
4. `0004` The connector data tier — typed clients, delegation semantics, the silent-truncation trap
5. `0005` ALM — one-way Git, solutions, pipelines, the open bundle-transport question
6. `0006` Governance & security — DLP, CSP, Conditional Access, the public endpoint
7. `0007` Limits & saying no — the tier-admission review checklist in practice
8. `0008` Capstone — defending the ADR against mock stakeholder challenges (interleaved retrieval of 1–7)

## Working notes
- 2026-07-21: learner requested the full course compiled at once for review → `code-apps-full-course.html` (standalone, all 8 lessons + condensed glossary + sources, inline CSS/JS). Preference noted: wants review-all-at-once over spaced delivery. Lessons 2–8 exist only in the compiled doc, not as individual `lessons/` files — split them out only if the spaced track resumes. Coverage ≠ learning: no learning records were written for 2–8; write them only when retrieval demonstrates understanding.
- Glossary established in `reference/glossary.html` — adhere to its terms in every lesson.
- Quiz answers: equal word count per option (skill rule) — check before shipping each lesson.
- The ADR is the case study; every lesson ends by tying back to a specific ADR clause.
