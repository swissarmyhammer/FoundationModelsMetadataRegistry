---
depends_on:
- 01KWMECNX02RYW074R5DFHQ4EA
- 01KWMEDXA34D8ZPB8AEZE57A3J
position_column: todo
position_ordinal: '8880'
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