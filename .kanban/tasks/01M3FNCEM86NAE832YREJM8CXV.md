---
assignees:
- claude-code
position_column: todo
position_ordinal: '8280'
title: Coalesce bursts of update(items:) so that only the newest catalog is embedded
---
## Goal
When many `update(items:)` calls arrive while an embed is in flight, embed only the newest catalog. Do not embed the catalogs between them.

## Context
- `update(items:)` (`Sources/FoundationModelsMetadataRegistry/MetadataSearcher+Search.swift:46`) rebuilds the keyword index at once, then calls `catchUpEmbeddings` (`:114`). Each call awaits `embedder.embed(_:)`. Actor reentrancy lets the next call start its own embed during that await.
- The hash check in `MetadataIndex.mergingEmbeddings` discards stale vectors, so the result is correct. But the stale embed calls use compute for no result.
- If the embedder runs its calls one at a time, a burst of N reloads becomes N embed calls in series, and the last catalog waits for all of them. Coalescing removes the stale work in both cases.
- The doc comment on `update(items:)` says that callers can forward every change notification "without coalescing them first". This task keeps that promise inside the searcher.
- The `HotReload` example (`Examples/HotReloadCore/HotReloadCore.swift`) sends bursts of updates. Use it to show the change.
- This task works with any `TextEmbedding`. It has no dependency on other tasks and can start now.

## Steps
1. Keep the keyword index step as it is: each call assigns the new `index` at once, so items are keyword-searchable at once.
2. Add a single-flight embed loop to the actor. If no embed is in flight, start one for the pending ids of the current `index`. If an embed is in flight, mark that more work is pending and return after the keyword step. When the in-flight embed ends and merges, compute the pending ids from the current `index` again and embed them, until nothing is pending.
3. Decide if `update(items:)` must wait for the catch-up that includes its own catalog. Recommended: yes, so that current tests and callers that await `update(items:)` still see the embeddings when the call returns. Record the decision in the doc comment and in `plan.md` §8.
4. Keep `.embedCatchUp` diagnostics correct: one diagnostic for each real embed call, not one for each `update(items:)` call.
5. Keep the interaction with `FirstSearchCatchUp` as it is.

## Acceptance criteria
- [ ] A burst of N `update(items:)` calls while an embed is in flight causes at most 2 embed calls: the one in flight and one for the newest catalog.
- [ ] After the burst, every item of the newest catalog has its embedding.
- [ ] No stale vector is merged (the current hash check stays).
- [ ] Keyword search sees each new catalog at once, the same as now.

## Tests
Use a stub embedder that blocks until the test releases it, and that counts calls and records the texts it gets.
- `burstEmbedsOnlyTheNewestCatalog`: start one update, block the embedder, send 5 more updates, release; expect 2 embed calls, and the second call has only texts from the newest catalog.
- `burstLeavesNoPendingEmbeddings`: after the burst, the index has an embedding for every id.
- `keywordSearchSeesEachUpdateAtOnce`: during the blocked embed, a `.retrieval` search finds an item that only the newest update added.
- Run `swift test`. All tests must pass, including the current hot-reload tests.