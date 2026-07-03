---
depends_on:
- 01KWMEDGSYSM044AX49AG27GAQ
position_column: todo
position_ordinal: '8780'
title: Over-budget selection path (retrieval top-M → one-off session) and .auto mode
---
## What
Complete the selection tier per plan.md §6/§7 (replaces Multitool's `lexicallyFilter` keep/drop):
- Over budget (preamble + all summary blocks > `capacityCharacterLimit`, using `renderSummaryBlock()` like the under-budget path): retrieval tier ranks the catalog, top-M candidates (default 24, best-first ordering passed to the prompt as summary blocks) seed a **one-off session** — no caching, no fork
- Id-enum grammar for the one-off session is constrained to the top-M candidate ids only
- Report the cut through the shared diagnostics surface as `MetadataDiagnostic.retrievalCut(considered:kept:)` (the generalization of Multitool's `onPrefilterCut`, `Librarian.swift:49,88,204`; default logs)
- `.auto` mode: selection when a model/session factory is configured, else retrieval (plan.md §7)
- Retrieval-tier `signals` attach to over-budget results where retrieval participated

## Acceptance Criteria
- [ ] A catalog whose assembled prefix exceeds the budget takes the one-off path: no root caching, zero forks, candidate count == min(candidateLimit, catalog size)
- [ ] `.retrievalCut` fires with accurate considered/kept counts; under-budget searches never fire it
- [ ] `.auto` resolves to selection with a session factory configured and retrieval without one
- [ ] One-off prompt contains candidate summary blocks in best-first retrieval order

## Tests
- [ ] `Tests/FoundationModelsMetadataRegistryTests/OverBudgetTests.swift` — scripted fakes: budget boundary (at/over limit), top-M membership and ordering, one-off grammar id set, `.retrievalCut` payload capture, `.auto` resolution both ways
- [ ] Run `swift test` — all pass, no GPU

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.