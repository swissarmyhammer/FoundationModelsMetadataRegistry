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

Shape:
1. Build a `MetadataSearcher` in `.selection` mode over `IntegrationCatalog`'s **base** group, wired to a real `LanguageModelSession` exactly as in `^xmt6fmc`.
2. `await searcher.update(items:)` with a catalog that adds the reserved **add-only** item and removes an item, leaving the reserved **remove-only** item out.
3. Search with the intent that only the add-only item can answer. Assert its id is returned.
4. Search with the intent that only the remove-only item could have answered. Assert that id is never returned, and no `.unknownSelectedId` fires for it.

`update(items:)` is at `Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift:346`, and rebuilds the tier on a content change at `:354-366`. `search(intent:limit:)` is at `:410`.

Use only intents `^nwt7nz4` measured at 5/5, and the disjoint fixture groups `^jzba4xn` built. Wrap model calls in `ModelAvailability.recordingEnvironmentFaults(_:)`; call `try ModelAvailability.requireAvailable()` first.

### Why this one is ours

Ranker's four real-model tests drive its own `Searcher` facade and its own `.selectionDefault` preamble. None calls `update(items:)` — its facade has no hot reload; its own doc comment says the catalog is fixed for the facade's lifetime. The rebuild path is this package's, over this package's `MetadataIndex` conformance to `SelectionCatalog`, with this package's `.librarianDefault`.

That combination — our catalog conformance feeding Ranker's `assemblePrefix` — is exactly where the `## <id>` defect lived, and Ranker found it, not us.

### The remove half is the load-bearing one

The add half is nearly a restatement of `^xmt6fmc`. The remove half is what no other test covers: proving a stale cached root does not keep answering with a deleted id. Weight the effort accordingly.

### Scope

Under-budget path only. No embed catch-up or cosine assertions: this package ships no real embedder, and FoundationModels exposes no embedding API — `embedding` returns zero hits in the SDK interface.

## Acceptance Criteria

- [ ] `await searcher.update(items:)` is called on a live searcher, not a freshly constructed one.
- [ ] An intent answerable only by the add-only item returns that id.
- [ ] An intent the removed item would have answered never returns the removed id.
- [ ] No `.unknownSelectedId` diagnostic fires for the removed id.
- [ ] Model calls wrapped in `recordingEnvironmentFaults(_:)`; `try requireAvailable()` first.

## Tests

- [ ] `HotReloadRealModelTests.swift` — the add half and the remove half.
- [ ] Run `swift test --package-path IntegrationTests` three times; record the rate in a comment on this card.
- [ ] Prove the remove half can fail: temporarily skip the `update(items:)` call so the removed item is still in the catalog, confirm the test fails, revert. This mutates the product path, not the expectation.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.