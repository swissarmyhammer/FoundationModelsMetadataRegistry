---
assignees:
- claude-code
depends_on:
- 01M1A97K9T94SEZ0CA0NWT7NZ4
position_column: todo
position_ordinal: '8280'
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

- [ ] `await searcher.update(items:)` is called on a live searcher, not a freshly constructed one.
- [ ] The add intent returns `sharpenSkates`.
- [ ] The remove intent never returns `dyeWool`.
- [ ] The diagnostic assertion filters for `.unknownSelectedId` and does **not** assert the absence of all diagnostics.
- [ ] Model calls wrapped in `recordingEnvironmentFaults(_:)`; `try requireAvailable()` first.

## Tests

- [ ] `HotReloadRealModelTests.swift` — the add half and the remove half.
- [ ] Run `swift test --package-path IntegrationTests` three times; record the rate in a comment.
- [ ] Prove the remove half can fail: temporarily skip the `update(items:)` call so `dyeWool` is still in the catalog, confirm the test fails, revert. This mutates the product path, not the expectation.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.