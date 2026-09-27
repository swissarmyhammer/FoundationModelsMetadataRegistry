---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3he3ckq8qcx4t0nhgcdbweb
  text: |-
    Research notes (implement):
    - `update(items:)` (MetadataSearcher+Search.swift) calls `catchUpEmbeddings` directly. Each call awaits its own embed. `index.pendingEmbeddings()` on the current index gives the same batch as `incrementalBaseline(...).pendingEmbedIDs`, so the loop can read the pending ids from the live `index` again after each embed.
    - Decision for step 3: `update(items:)` waits for the catch-up that includes its catalog (recommended option). Plan: an enum `ReloadEmbedLoop` (idle / running(task) / runningWithNewerCatalog(task)) on the actor. The first update starts a `Task` loop. Later updates mark "newer catalog" and await the same task. The loop embeds `index.pendingEmbeddings()` and runs one more pass only when a newer catalog arrived during the embed. An embed failure does not loop forever: the loop only repeats on a new request.
    - Two current tests conflict with the coalescing behavior and must change their orchestration, not their intent:
      1. `overlappingUpdatesToTheSameIdNeverLetAnEarlierSlowerEmbedOverwriteALaterFasterOne` (HotReloadBurstTests) awaits update B while the embed of A is blocked. With the wait decision, B waits for the gate, so the test would deadlock. B must run in a Task, and the test releases the gate after B's keyword step is visible.
      2. `concurrentUpdatesRunOneAtATime` (PooledTextEmbeddingTests) expects one embed call for each update. Coalescing removes the stale calls, so the count must be a range: at least one call for each searcher, at most one for each update.
    - HotReloadCore example: add a demo that sends a burst while the first embed is held, and reports the catalog embed calls.
  timestamp: 2026-09-27T12:40:37.239604+00:00
- actor: claude-code
  id: 01m3hee24gja2xqmymhahqkbav
  text: |-
    Implementation landed:
    - `MetadataSearcher.ReloadEmbedLoop` (idle / running / runningWithNewerCatalog) and `reloadEmbedLoop` state. `update(items:)` keeps its keyword step, then calls `embedNewestCatalog(with:)`. The loop `runReloadEmbedLoop(with:)` embeds `index.pendingEmbeddings()` and repeats only when `takeNewerCatalogRequest()` finds a request. `catchUpEmbeddings` and its hash check are unchanged, so `.embedCatchUp` is one for each real embed call. `FirstSearchCatchUp` is unchanged.
    - Decision (step 3): `update(items:)` waits for the catch-up that includes its catalog. Recorded in the doc comment of `update(items:)` and in plan.md §8 item 7.
    - New tests: HotReloadCoalescingTests.swift (`burstEmbedsOnlyTheNewestCatalog`, `burstLeavesNoPendingEmbeddings`, `keywordSearchSeesEachUpdateAtOnce`).
    - Changed orchestration of two current tests (assertions kept exact): the overlap test now runs update B in its own task and waits for its keyword index; `concurrentUpdatesRunOneAtATime` now sends the updates of each searcher in series while the two searchers run at the same time, so the exact count `updateCount` still holds and `maximumCallsInFlight == 1` still proves the pool queue.
    - HotReload example: new `Examples/HotReloadCore/CoalescedBurst.swift` (`runCoalescedHotReloadBurst`), printed by `main.swift`, with a smoke test. `DiagnosticLog` is now internal so that the demo reuses it.
    - Note: the `files` tool `replace_all` edit replaced only one instance; the other instances needed separate edits.

    ### implement — changed
    - evidence: 11 files — Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift, Sources/FoundationModelsMetadataRegistry/MetadataSearcher+Search.swift, plan.md, Examples/HotReloadCore/CoalescedBurst.swift, Examples/HotReloadCore/HotReloadCore.swift, Examples/HotReload/main.swift, Tests/.../HotReloadCoalescingTests.swift, Tests/.../HotReloadBurstTests.swift, Tests/.../PooledTextEmbeddingTests.swift, Tests/.../ExamplesSmokeTests.swift; `swift build --build-tests` clean; filtered `swift test` 42 tests in 5 suites passed.
    - next: /test
  timestamp: 2026-09-27T12:46:26.960944+00:00
- actor: claude-code
  id: 01m3hen59ffav7jp442kbrwr4k
  text: |-
    ### test — green
    - evidence: `swift test` — 141 tests in 14 suites passed, 0 failed, 0 skipped; `swift build --build-tests -Xswiftc -warnings-as-errors` clean; `swiftlint lint` clean; `swiftformat --lint .` 0/66 files.
    - fixes on the way: SwiftLint `file_length` on MetadataSearcher.swift (419) and MetadataSearcher+Search.swift (430) → moved the loop and `ReloadEmbedLoop` to the new MetadataSearcher+ReloadEmbedLoop.swift (`catchUpEmbeddings` is now internal); `line_length` at PooledTextEmbeddingTests.swift:41 → wrapped; SwiftFormat `blankLinesBetweenScopes`, `extensionAccessControl`, `redundantFileprivate` → applied.
    - The nested IntegrationTests package (real model) was not run locally; CI runs it.
    - next: /commit
  timestamp: 2026-09-27T12:50:19.567561+00:00
position_column: doing
position_ordinal: '80'
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