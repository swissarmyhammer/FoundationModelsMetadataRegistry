---
comments:
- actor: claude-code
  id: 01kwpr0b9mdssqqsbrhtxtv6yv
  text: 'Picked up by /finish scoped-batch loop (task 10 of batch; ^jcyn2bd and ^5wax8f7 removed from board as out-of-scope cross-repo tasks per user instruction). Plan: /implement → /test → /commit checkpoint → /review HEAD~1..HEAD.'
  timestamp: 2026-07-04T14:20:02.740719+00:00
- actor: claude-code
  id: 01kwps7x5m4kva5ahcce4t60fs
  text: |-
    Implementation complete and green via TDD.

    What was built:
    - `MetadataIndex.swift`: refactored `build(items:embedder:previous:onDiagnostic:)` into two composable pieces — `incrementalBaseline(items:previous:onDiagnostic:)` (synchronous tokenize/trigram + hash-guarded embedding reuse, returns baseline + pending ids/texts) and `mergingEmbeddings(ids:vectors:embeddedFrom:into:)` (merges a completed embed batch into a target index, verified by block-hash match against the source baseline it was actually computed from — not just by id). Added `hasIdenticalContent(to:)` for the redundant-update guard.
    - `MetadataSearcher.swift`: `index` and `selectionTier` became actor-isolated `var`s; added `selectionConfig` storage and a shared `makeSelectionTier(...)` builder. New `public func update(items:) async`: assigns the synchronously-rebuilt baseline to `index` *before* awaiting the embedder (actor reentrancy lets a concurrent `search()` interleave and see keyword-only results for pending items), reports `.embedCatchUp(pending:total:)`, rebuilds the selection tier (dropping the cached root) only on genuine content change, and merges embed results back into whatever `index` currently is (tolerating a concurrent `update()` on the same call).
    - New test file `Tests/.../HotReloadTests.swift` (12 tests) and two new test-support doubles: `TestSupport/GatedEmbedder.swift` (continuation-based `EmbedGate` actor + a gate-blocking `TextEmbedding`, with an optional `gatedTexts` allowlist so a test can gate one call's text while another resolves immediately — used to deterministically drive overlapping `update()` calls without sleeps).

    Adversarial double-check (via really-done's gate) found two real bugs before I called this done, both fixed with regression tests added first (RED confirmed, then fixed to GREEN):
    1. The redundant-update no-op guard originally fired on content-identical alone, ignoring pending embeds — an item that was indexed but never successfully embedded (e.g. a prior transient embed failure) would stay cosine-blind forever once its content stopped changing. Fixed: the guard is now `contentChanged || !idsToEmbed.isEmpty`, and the selection-tier rebuild is now gated on `contentChanged` specifically (catch-up alone shouldn't drop the cached root). Regression test: `updateStillCatchesUpAnEmbeddingThatNeverSucceededEvenWhenContentIsUnchanged`.
    2. `mergingEmbeddings` originally matched by id only, so two overlapping `update()` calls re-embedding the *same* id with *different* content could let a slower call's stale vector silently overwrite a faster call's newer, correct one (paired with the wrong block hash, no diagnostic, permanent corruption). Fixed: the merge now also requires the target's current block hash to match the hash of the source baseline the batch was embedded from, skipping otherwise. Regression test: `overlappingUpdatesToTheSameIdNeverLetAnEarlierSlowerEmbedOverwriteALaterFasterOne`.

    Final state: `swift build` clean (no new warnings), `swift test` 122/122 passing (110 pre-existing + 12 new in HotReloadTests.swift). Leaving task in `doing` per /implement workflow for /review to pick up.
  timestamp: 2026-07-04T14:41:38.996841+00:00
depends_on:
- 01KWMECNX02RYW074R5DFHQ4EA
- 01KWMEDXA34D8ZPB8AEZE57A3J
position_column: doing
position_ordinal: '80'
title: 'Hot reload: update(items:) with incremental re-embed and cache invalidation'
---
## What
Implement `MetadataSearcher.update(items:)` end-to-end per plan.md §8 (M4):
1. Re-render blocks; rebuild tokenized/trigram indexes synchronously (fast path — items keyword-searchable immediately)
2. Re-embed **incrementally**: only items whose `(id, block-hash)` changed; embedding runs async; retrieval serves keyword-only for not-yet-embedded items in the interim (absent-signal rule), with the catch-up gap surfaced as `MetadataDiagnostic.embedCatchUp(pending:total:)` through the shared `onDiagnostic` surface
3. Drop the cached root session — next under-budget search rebuilds it (one prefix re-prefill)
4. Rebuild the id-enum grammar from the new id set
- Hash-guarded: calling `update` with unchanged items is cheap (no re-embed, no root drop), so callers may forward every upstream notification without coalescing

## Acceptance Criteria
- [ ] After an update burst (add/remove/modify), new items are immediately findable by keyword; modified-only items are the only ones re-embedded (counting `FakeEmbedder`)
- [ ] Redundant `update` with identical items: zero embeds, root session retained (fork count uninterrupted)
- [ ] After a real change: next selection search rebuilds the root exactly once and the grammar id set matches the new catalog
- [ ] Embed catch-up gap observable via `.embedCatchUp` diagnostics with accurate pending/total counts

## Tests
- [ ] `Tests/FoundationModelsMetadataRegistryTests/HotReloadTests.swift` — counting `FakeEmbedder` + scripted session fakes: incremental re-embed counts, redundant-update no-op, root/grammar invalidation, interim keyword-only service, `.embedCatchUp` capture, MCP-style add/remove burst
- [ ] Run `swift test` — all pass, no GPU

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.