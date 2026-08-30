---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m1aeep4hnm63de5rk258kevf
  text: |-
    Research done. What the code says:

    - `MetadataSearcher` is `public actor MetadataSearcher<Item: SearchableMetadata>`. The synchronous `init(items:mode:weights:selection:onDiagnostic:)` is the one the cold suite uses, and it is the one this suite needs too.
    - `update(items:)` rebuilds the tier only on `contentChanged`, through the same `buildSelectionTierIfConfigured(config:index:weights:embedder:onDiagnostic:)` the initializer calls. That is the rebuild the remove half measures: a fresh `SelectionTier` has no cached root session and re-assembles its prefix from the new index.
    - With no embedder, `update(items:)` returns right after the rebuild (`guard !pendingEmbedIDs.isEmpty, let embedder else { return }`), so no embed catch-up runs and no `.embedCatchUp` fires. That matches the card's scope.
    - `computeCosineScores` reports `.embeddingUnavailable` whenever no embedder is wired, and `buildSelectionTierIfConfigured` wires that closure as the tier's `retrievalRanking`. That is why the diagnostic assertion must filter for `.unknownSelectedId` and never test the collection for emptiness.
    - `IntegrationCatalog` already reserves `addOnly` (`sharpenSkates`) and `removeOnly` (`dyeWool`), and its own note says to compose the starting catalog as `base + [removeOnly]`.

    Shared wiring: `ColdSelectionRealModelTests` holds the searcher construction and the `.unknownSelectedId` filter privately. A second suite needs both verbatim, so they move to `Support/SelectionScenario.swift` and both suites call them. Two real callers, no speculative abstraction.
  timestamp: 2026-08-30T23:00:42.769706+00:00
- actor: claude-code
  id: 01m1aepwnvd90av0n2pmx87znh
  text: |-
    RED first, exactly as the card asks. With the `await searcher.update(items: reloadedCatalog)` line deleted from the helper, `swift test --package-path IntegrationTests --filter HotReload` failed 2 of 2:

    ```
    ✘ "a hot reload makes the removed id unreachable" — Expectation failed:
      !answer.ids.contains(IntegrationCatalog.removeOnly.id)
      answer.ids → ["dyeWool"]
    ```

    The add half failed on the same mutation, because the added id is absent until the reload runs. Both halves therefore depend on the one call under test. The line was restored, and both passed.

    Rate after the restore: 3 consecutive `swift test --package-path IntegrationTests` runs, **5 tests in 4 suites green each time, 3/3**. Six real-model query outcomes across the three runs, all correct, zero `.unknownSelectedId`. Root `swift test`: 115 tests in 12 suites, unchanged. `swift build --package-path IntegrationTests --build-tests`: 0 warnings, 0 errors.

    Two design notes for the next agent:

    **The shared wiring moved.** `ColdSelectionRealModelTests` held the `.selection` searcher construction and the `.unknownSelectedId` filter as private members. A second suite needs both verbatim, so they now live in `Support/SelectionScenario.swift` as `makeSearcher(over:reporting:)` and `expectNoUnknownSelectedId(among:answering:sourceLocation:)`, and both suites call them. Two real callers, not a speculative abstraction. `expectNoUnknownSelectedId` takes `sourceLocation: SourceLocation = #_sourceLocation` so a failure still reports the scenario's own line rather than the helper's. The cold suite lost its now-unused `import FoundationModels` with the move.

    **Both halves share one hot reload.** `startingCatalog` is `base + [removeOnly]` and `reloadedCatalog` is `base + [addOnly]`, so one `update(items:)` both adds and removes. Each test runs its own searcher through that same reload and then asks exactly one question of it, so neither half depends on whether a reused searcher would be warm.

    Swift Testing surfaces a failing test's `///` doc comment in the failure output. The suite doc is long, so a red run in this file prints a wall of prose above the real message. Not a defect, just what a failure here looks like.
  timestamp: 2026-08-30T23:05:11.611360+00:00
- actor: claude-code
  id: 01m1aeq1y12npmf0ag5cb5nwf6
  text: |-
    ### implement — changed
    - evidence: 3 files — `IntegrationTests/Tests/FoundationModelsMetadataRegistryIntegrationTests/HotReloadRealModelTests.swift` (new), `.../Support/SelectionScenario.swift` (new, shared wiring extracted from the cold suite), `.../ColdSelectionRealModelTests.swift` (calls the shared wiring; unused `import FoundationModels` dropped). RED: 2 of 2 failed with `update(items:)` removed, `answer.ids → ["dyeWool"]`. GREEN: `swift test --package-path IntegrationTests` 3/3 runs, 5 tests in 4 suites; root `swift test` 115 tests in 12 suites; `swift build --package-path IntegrationTests --build-tests` 0 warnings.
    - next: `/review`
  timestamp: 2026-08-30T23:05:16.993034+00:00
depends_on:
- 01M1A97K9T94SEZ0CA0NWT7NZ4
position_column: doing
position_ordinal: '80'
title: 'Real-model test: update(items:) makes new ids selectable and removed ids unreachable'
---
## What

The second real-model test. It covers the seam FoundationModelsRanker's own suite cannot reach: this package's `update(items:)` rebuilding the selection tier over this package's `MetadataIndex`, then a real model selecting from the rebuilt catalog.

File to create:
- `IntegrationTests/Tests/FoundationModelsMetadataRegistryIntegrationTests/HotReloadRealModelTests.swift`

`update(items:)` is at `Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift:346` and rebuilds the tier on a content change at `:354-366`. `search(intent:limit:)` is at `:410`.

Wire the searcher exactly as `^xmt6fmc` does. Wrap model calls in `ModelAvailability.recordingEnvironmentFaults(_:)`; `try ModelAvailability.requireAvailable()` first.

### Use these intents — measured, do not invent new ones

`^nwt7nz4` measured these beyond the base group specifically for this card:

| catalog | intent | result |
|---|---|---|
| `base + addOnly` | `Sharpen my dull hockey skate blades.` | `sharpenSkates` 5/5 |
| `base + removeOnly` | `Dye this fleece yarn with indigo.` | `dyeWool` 5/5 |
| `base + addOnly` (dyeWool absent) | `Dye this fleece yarn with indigo.` | empty 5/5 |

That third row is what makes the remove half load-bearing rather than vacuous: the same intent that reliably finds `dyeWool` reliably finds **nothing** once the item is gone.

### Shape

1. Build the searcher over `base + removeOnly`.
2. `await searcher.update(items:)` with `base + addOnly` — adding `sharpenSkates`, removing `dyeWool`.
3. Search `Sharpen my dull hockey skate blades.` — assert `sharpenSkates` is returned.
4. Search `Dye this fleece yarn with indigo.` — assert `dyeWool` is never returned, and no `.unknownSelectedId` fires.

### Assert `.unknownSelectedId` specifically — never "no diagnostics"

`^nwt7nz4` found `MetadataDiagnostic.embeddingUnavailable` fires on **every** selection search, 55 of 55 runs: `SelectionTier`'s under-budget path calls `retrievalRanking` once per call to attach `score`/`signals`, and that closure reports the missing embedder. "No diagnostics were recorded" would fail on every run for an unrelated reason. `.unknownSelectedId` fired in zero of 125 measured runs.

### Why this one is ours

Ranker's four real-model tests drive its own `Searcher` facade and its own `.selectionDefault` preamble. None calls `update(items:)` — its facade has no hot reload. The rebuild path is this package's, over this package's `MetadataIndex` conformance to `SelectionCatalog`, with this package's `.librarianDefault`.

The remove half is the load-bearing one: proving a stale cached root does not keep answering with a deleted id. Weight the effort accordingly.

### Scope

Under-budget path only. No embed catch-up or cosine assertions: this package ships no real embedder, and FoundationModels exposes no embedding API.

## Acceptance Criteria

- [x] `await searcher.update(items:)` is called on a live searcher, not a freshly constructed one.
- [x] The add intent returns `sharpenSkates`.
- [x] The remove intent never returns `dyeWool`.
- [x] The diagnostic assertion filters for `.unknownSelectedId` and does **not** assert the absence of all diagnostics.
- [x] Model calls wrapped in `recordingEnvironmentFaults(_:)`; `try requireAvailable()` first.

## Tests

- [x] `HotReloadRealModelTests.swift` — the add half and the remove half.
- [x] Run `swift test --package-path IntegrationTests` three times; record the rate in a comment.
- [x] Prove the remove half can fail: temporarily skip the `update(items:)` call so `dyeWool` is still in the catalog, confirm the test fails, revert. This mutates the product path, not the expectation.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.