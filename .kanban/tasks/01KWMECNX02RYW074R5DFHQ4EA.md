---
comments:
- actor: claude-code
  id: 01kwmzfvhvvadt6s4v4agkqs2m
  text: 'Picked up by /finish scoped-batch loop (task 5 of batch). Plan: /implement → /test → /commit checkpoint → /review HEAD~1..HEAD.'
  timestamp: 2026-07-03T21:52:22.075239+00:00
- actor: claude-code
  id: 01kwn09k4gdn8jjhkcyxgyprya
  text: |-
    Implemented via TDD. Wrote Tests/FoundationModelsMetadataRegistryTests/EmbeddingTests.swift (7 tests) + TestSupport/FakeEmbedder.swift first, watched them fail to compile (TextEmbedding didn't exist), then implemented:

    - Sources/.../Embedding/TextEmbedding.swift and RoutedEmbedderAdapter.swift: ported verbatim from ../CodeContextKit/Sources/CodeContextKit/Embedding/ with attribution headers, adjusted doc comments to reference MetadataIndex/MetadataSearcher instead of TreeSitterWorker. RoutedEmbedderAdapter wraps FoundationModelsRouter's `RoutedEmbedder` (public typealias RoutedModel<any LoadedEmbeddingContainer>, confirmed in FoundationModelsRouter/Sources/FoundationModelsRouter/LanguageModelProfile.swift and RoutedEmbedder.swift) — pure pass-through, compiles but isn't exercised (no GPU in unit tests, as instructed).
    - Catalog/MetadataIndex.swift: added `Entry.blockHash` (SHA-256 digest via CryptoKit, matching the precedent in CodeContextKit's Walker.swift), and a new `public static func build(items:embedder:previous:onDiagnostic:) async -> MetadataIndex<Item>` that tokenizes/trigrams synchronously (unchanged from the existing sync init) then embeds only items whose (id, block-hash) don't match `previous`, batching all new/changed blocks into one `embedder.embed(_:)` call. The existing sync `init(items:onDiagnostic:)` is completely untouched in signature/behavior.
    - MetadataSearcher.swift: added an `embedder: (any TextEmbedding)?` + stored `onDiagnostic` closure, two new initializers (`init(items:mode:weights:embedder:onDiagnostic:) async` which builds the index via `MetadataIndex.build`, and `init(index:mode:weights:embedder:onDiagnostic:)` for pre-built indices — the latter is what a future `update(items:)` hot-reload task, and tests needing precise mixed-embedding scenarios, will use). `retrievalSearch` is now `async`, computes a cosine ranking (brute-force per-row dot product, in-memory, no vector store) only when `weights.cosine > 0`, and fires `.embeddingUnavailable` via `onDiagnostic` whenever no embedder is configured or no catalog item carries an embedding yet — never silent. The original sync `init(items:mode:weights:onDiagnostic:)` is unchanged in signature and behavior (embedder defaults to nil internally), so all 65 pre-existing tests pass unmodified.

    Discovery: plan.md §8 (`update(items:)`, hot reload) is a separate later task (this card is only M2 "embedding signal"), so I did NOT add an `update(items:)` method to MetadataSearcher — only the `MetadataIndex.build(items:embedder:previous:onDiagnostic:)` static factory a future update(items:) task can call, which already supports hash-keyed incremental re-embedding (verified by a counting FakeEmbedder test).

    Commands run: `swift build` (clean, exit 0, only a pre-existing unrelated `mlx-swift_Cmlx.bundle` warning) and `swift test` (72/72 tests passed, exit 0 — the prior 65 plus 7 new EmbeddingTests, zero failures/warnings).

    Leaving in `doing` for /review per the implement skill contract.
  timestamp: 2026-07-03T22:06:25.424394+00:00
- actor: claude-code
  id: 01kwn0x13f1kfqvhhzzwpy91fz
  text: |-
    Adversarial double-check (via really-done) found and I fixed one real bug plus one minor gap before finalizing:

    BUG (confirmed, fixed): `MetadataIndex.build`'s hash-keyed reuse used to copy forward `previousEntry.embedding` whenever the block hash matched, even when that embedding was `nil` — permanently locking an item out of ever being embedded once its text stopped changing, even after an embedder became available (contradicts plan.md §8's "embed catch-up"). Fixed the reuse condition to also require a non-nil previous embedding; otherwise the item falls through to be embedded fresh. Added a TDD regression test (`incrementalBuildEmbedsAnItemThatHadNoEmbeddingOnceAnEmbedderBecomesAvailable`) that fails on the old code and passes on the fix. Also rewrote `itemsWithoutEmbeddingsContributeNothingToCosineButStillRankViaKeywordSignals` — it had been (accidentally) locking in the buggy behavior as if it were correct — to construct its mixed embedded/un-embedded scenario legitimately via a two-step build with a deliberately-failing second embedder.

    MINOR GAP (fixed): `MetadataSearcher.computeCosineRanking` didn't fire `.embeddingUnavailable` if `embedder.embed([intent])` returned an empty array without throwing (a contract violation by a misbehaving embedder). Added the diagnostic call on that path too, plus a new test (`searchWithAnEmbedderReturningNoVectorsEmitsEmbeddingUnavailableDiagnostic`) with an inline `EmptyResultEmbedder` conformer.

    Re-ran double-check after the fixes: verdict PASS, with only a non-blocking coverage-gap note (now addressed by the added test above).

    Final verification: `swift build` (exit 0, only a pre-existing unrelated mlx-swift_Cmlx.bundle warning) and `swift test` (74/74 passed, exit 0 — 65 pre-existing + 9 EmbeddingTests, zero failures).

    Task is green and left in `doing` for /review.
  timestamp: 2026-07-03T22:17:02.319256+00:00
depends_on:
- 01KWMECA3GC1631WXPX2BJN4DB
position_column: doing
position_ordinal: '80'
title: 'Embedding signal: TextEmbedding seam, RoutedEmbedderAdapter, cosine in fusion'
---
## What
Add the third signal per plan.md §5 (M2), in `Sources/FoundationModelsMetadataRegistry/Embedding/`:
- Port `TextEmbedding.swift` (~19-line protocol seam) and `RoutedEmbedderAdapter.swift` (~45 lines, wraps Router's `RoutedEmbedder`) from `../CodeContextKit/Sources/CodeContextKit/Embedding/`, with attribution
- `MetadataIndex` stores per-item embeddings keyed by `(id, block-hash)`; embedding happens at index-build/update time, never at query time (only the query itself is embedded per search)
- Cosine ranking joins RRF fusion in `MetadataSearcher.search`; items without embeddings contribute nothing to cosine (absent-signal rule)
- No embedder configured → keyword-only, surfaced as the shared `MetadataDiagnostic.embeddingUnavailable` case through `onDiagnostic` (never silent)
- Brute-force per-row dot products — in-memory, no vector store (decision #10)

## Acceptance Criteria
- [ ] With a `FakeEmbedder`, a paraphrase query ranks the semantically-close item above keyword-only ranking
- [ ] Omitting the embedder degrades to keyword-only and emits `.embeddingUnavailable` via `onDiagnostic`
- [ ] Un-embedded items still rank via BM25 + trigram
- [ ] Embed count is proportional to changed blocks only (hash-keyed), verified by a counting fake

## Tests
- [ ] `Tests/FoundationModelsMetadataRegistryTests/EmbeddingTests.swift` — `FakeEmbedder` (deterministic vectors + call counter): cosine fusion, degradation diagnostic capture, absent-signal, hash-keyed incremental embed
- [ ] Run `swift test` — all pass, no GPU (RoutedEmbedderAdapter compiles but is not exercised)

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.