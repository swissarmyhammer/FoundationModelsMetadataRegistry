---
comments:
- actor: claude-code
  id: 01kwn6tb6egffhmqjjvw1bdf3a
  text: 'Picked up by /finish scoped-batch loop (task 8 of batch). Plan: /implement → /test → /commit checkpoint → /review HEAD~1..HEAD.'
  timestamp: 2026-07-04T00:00:25.806433+00:00
- actor: claude-code
  id: 01kwpev7ktvskw94f8hfk1p784
  text: |-
    Implemented the over-budget selection path and .auto resolution (resumed after session interruption; test file OverBudgetTests.swift was already written/RED-confirmed by the prior session).

    Production changes:
    - Sources/.../Selection/SelectionTier.swift: added `retrievalRanking: @Sendable (String) async -> [Match<Item>]` closure param to init; `search()` now calls a new `overBudgetSearch(intent:limit:)` instead of throwing when over budget. It ranks the whole catalog via `retrievalRanking`, takes `Array(ranked.prefix(config.candidateLimit))` as candidates, fires `.retrievalCut(considered: ranked.count, kept: candidates.count)`, builds a one-off prefix via a new `assemblePrefix(preamble:ids:index:)` overload (widened from `private` to internal `static` so tests can compute expected prefix length directly), creates a session via `config.model(prefix)` with NO fork and NO caching, and maps selection ids back to Matches via `matches(forIds:limit:allowedIds:retrievalMatches:)` — a generalized version of the existing verbatim-lookup helper that (a) restricts resolution to the current candidate id set (an id outside it, even a real catalog id, is treated as `.unknownSelectedId`) and (b) attaches the real retrieval score/signals from the candidate's own Match instead of the pure-selection 1.0/nil.
    - Sources/.../MetadataSearcher.swift: `.auto` now resolves to selection when a selectionTier is configured, retrieval otherwise (previously always fell back to retrieval). Refactored the retrieval-tier compute functions (BM25/trigram/cosine + RRF fuse/normalize + Match-building) from instance methods to static, parameterized ones so a new `static func rankEntireCatalog(intent:index:weights:embedder:onDiagnostic:)` could reuse them — it returns exactly `index.count` matches always (real-ranked prefix + zero-signal catalog-order fallback tail), which is what guarantees the over-budget candidate count is always `min(candidateLimit, catalog size)` even when a query's signal overlap is sparse. This closure is wired into `SelectionTier` at `MetadataSearcher.init`.
    - Updated stale "later task" doc comments across SelectionTier/SelectionConfig/SearchMode/MetadataSearcher now that the over-budget path and .auto both exist.
    - Removed the now-invalid `overBudgetPrefixThrowsSelectionTierUnavailableWithoutInvokingTheSessionFactory` test from SelectionTests.swift (its premise — over budget always throws — is no longer true) and updated that file's header doc to point over-budget/.auto coverage at OverBudgetTests.swift.

    Test-file gotcha found: two of the new tests initially failed because default `Weights` has `cosine: 1.0` with no embedder configured, so `rankEntireCatalog`'s cosine computation legitimately fires `.embeddingUnavailable` in addition to `.retrievalCut` — fixed by passing `weights: Weights(cosine: 0.0)` in the two diagnostic-payload tests that assert an exact `recorder.diagnostics` array (this is correct/expected behavior, not a bug).

    Verification:
    - `swift build`: clean, exit 0, no warnings from this package's own code.
    - `swift test --filter OverBudgetTests`: 13/13 passed.
    - `swift test` (full suite): 106/106 passed, 9 suites (94 pre-existing minus the 1 removed stale test, plus 13 new = 106), zero failures, zero warnings.

    Leaving in `doing` for review per /implement workflow.
  timestamp: 2026-07-04T11:39:57.946195+00:00
depends_on:
- 01KWMEDGSYSM044AX49AG27GAQ
position_column: doing
position_ordinal: '80'
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