---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01kxkmg69hv3c9rh3pqvbex151
  text: 'Picked up by /finish (scoped-batch, no scope). Plan: /implement → /test → /commit checkpoint → /review HEAD~1..HEAD, looping until done. This card blocks ^kh9kfck (retrieval-tier migration), which will be driven next.'
  timestamp: 2026-07-15T19:36:46.129535+00:00
- actor: claude-code
  id: 01kxkmwhsvw8mcmyzfzpdpjggw
  text: |-
    Picked up; research done. Verified Ranker API in ../FoundationModelsRanker: public non-generic `actor SelectionTier` (catalog/config/onDiagnostic/retrievalRanking; search -> [SelectionMatch]; builds maxItems-capped idEnumGrammar itself), `SelectionConfig.model: @Sendable (String, Grammar) -> any AgentSession`, `SelectionCatalog` (ids/summaryBlock(forId:)/block(forId:)), `RankDiagnostic` (retrievalCut/unknownSelectedId/embeddingUnavailable), `SelectionTierUnavailable` declared in Ranker's Searcher.swift, `AgentSession`+`RoutedAgentSession` identical shape.

    Plan: (1) TDD RED — update SelectionFixtures (factory records instructions AND grammar), SelectionTests/OverBudgetTests/HotReloadTests/RouterIntegrationTests to the (String, Grammar) shape + Ranker's SelectionTier.idEnumGrammar/assemblePrefix(catalog:); add regression test asserting the factory-received grammar's enum == this round's candidate ids and maxItems == candidate count (over-budget, candidateLimit 2). (2) GREEN — conform MetadataIndex to SelectionCatalog; rebase MetadataSearcher on Ranker's tier, storing (tier, index-snapshot) pairs so SelectionMatch->Match<Item> id lookups stay consistent with the tier's own catalog across actor reentrancy; map RankDiagnostic->MetadataDiagnostic via an internal init in Diagnostics.swift; delete Selection/*.swift + Session/AgentSession.swift + local SelectionTierUnavailable; keep `.librarianDefault` in a new SelectionPreamble.swift and pass it explicitly in Examples' buildSelectionConfig so prompt text doesn't silently change; reduce reexport file; update LiveRouterSupport (drop hand-built idEnumGrammar + ids param), LibrarianCore/BigCatalogCore call sites, HotReloadCore factory shape; annotate plan.md §5/§6/§8 sentence/decision #12/§12 sample.

    Note on acceptance grep: the bare `SelectionTierUnavailable` pattern will still hit usage sites in MetadataSearcher.swift (`throw SelectionTierUnavailable()` + doc mentions) — the type now comes from Ranker; no local declaration will remain, which is the criterion's stated intent.
  timestamp: 2026-07-15T19:43:31.131799+00:00
- actor: claude-code
  id: 01kxkndtyf2wqkpydv26feqf6z
  text: |-
    GREEN milestone: swift build fully green (all Examples targets) and swift test 99/99 passing after the migration + new regression test.

    Discovery/dead end worth knowing: the first test run failed 2 tests (both `maxItems as? Int == nil`) because Package.resolved pinned FoundationModelsRanker at 1c1f302 — the rename commit, one commit BEFORE the maxItems runaway-generation fix (b3ce6f5) on Ranker main. The code I verified in ../FoundationModelsRanker was ahead of the pin. Fixed with `swift package update FoundationModelsRanker`; Package.resolved now pins b3ce6f5 (which is remote main's HEAD; 06a239a exists only in the local Ranker checkout and is a comment-only cleanup, not needed). The regression test did its job — it would have shipped silently uncapped otherwise.

    Remaining: plan.md §5/§6/§8 sentence/decision #12/§12 sample annotations, acceptance grep check, really-done.
  timestamp: 2026-07-15T19:52:57.551392+00:00
- actor: claude-code
  id: 01kxkp4kw0m4f75z004m1h87pg
  text: |-
    Done and green; leaving in doing for /review. really-done verification: fresh `swift build` exit 0 (all Examples targets) and fresh `swift test` 99/99 passing in 9 suites, GPU-free. Adversarial double-check verdict: PASS — confirmed behavior parity line-by-line against the deleted local tier at the pinned Ranker revision (b3ce6f5), no consumer-facing prompt change (only two implicit-preamble sites move to `.selectionDefault`: HotReloadCore's scripted demo and gated RouterIntegrationTests scenario 1, both prompt-text-independent), no stale references, acceptance grep clean of declarations, and the new regression test genuinely pins the ^678h0ex fix through the Ranker path (it caught the stale pin).

    All subtask/acceptance/test checkboxes updated to [x] on the card. Changed files: Sources (MetadataSearcher.swift rebased on Ranker SelectionTier with (tier, snapshot) pairing; MetadataIndex.swift + SelectionCatalog conformance; Diagnostics.swift + RankDiagnostic->MetadataDiagnostic init; new SelectionPreamble.swift; FoundationModelsRankerReexport.swift reduced; deleted Selection/{Selection,SelectionTier,SelectionConfig}.swift and Session/AgentSession.swift), Examples (LiveRouterSupport dropped hand-built idEnumGrammar + ids param, passes .librarianDefault explicitly; LibrarianCore/BigCatalogCore call sites; HotReloadCore factory shape), Tests (SelectionTests, OverBudgetTests + regression test, HotReloadTests, RouterIntegrationTests, SelectionFixtures records grammars), plan.md (§5, §6, §8 step 4, decision #12, §12 sample, §13 blurb), Package.resolved (Ranker pin 1c1f302 -> b3ce6f5). Not committed — orchestrator handles commits.
  timestamp: 2026-07-15T20:05:23.968939+00:00
- actor: claude-code
  id: 01kxkp5wmd32by0cp5pxycy1mq
  text: '/implement complete, task green in doing. Selection tier rebased on Ranker''s public SelectionTier (snapshot-paired for reentrancy-safe id→item lookup); local Selection/ + Session/ files deleted; re-export reduced to plain; LiveRouterSupport wires the tier-supplied Grammar; plan.md annotated. 99/99 tests green. Notable: Package.resolved had Ranker pinned one commit BEFORE the maxItems runaway fix — the new regression test caught it; pin bumped 1c1f302→b3ce6f5 via swift package update. Next: /test, /commit checkpoint, /review.'
  timestamp: 2026-07-15T20:06:05.709165+00:00
- actor: claude-code
  id: 01kxkqsrwy56nvrxdce2bzsyk1
  text: |-
    Review finding (duplicated selection-tier pair construction) fixed; checkbox flipped to [x]. Pulled the card review->doing, worked the finding, leaving in doing.

    What changed (Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift only): folded `makeSelectionTier` and the two hand-built `(tier:snapshot:)` tuples into a single `private static func buildSelectionTierPair(index:config:weights:embedder:onDiagnostic:) -> (tier: SelectionTier, snapshot: MetadataIndex<Item>)`; both the designated init and `update(items:)` now call it, so tier construction and snapshot pairing have one source of truth and can never diverge.

    Deviation from the reviewer's suggested shape, with evidence: the finding asked for a nonisolated *instance* method `buildSelectionTierPair(index:config:)` reusing stored properties with call sites `selection.map { buildSelectionTierPair(index: index, config: $0) }`. That shape is uncompilable on this actor: SE-0327 flow-sensitive actor-init isolation forbids writing the `selectionTier` stored property after any method call on `self` in the synchronous designated init — I implemented it first and the compiler rejected it with "Cannot access property 'selectionTier' here in nonisolated initializer". The static form is the only helper shape shareable by both init and update; the helper's doc comment records this rationale so the next agent doesn't retry the instance form. The finding's substance (single helper owning the pair construction, both sites calling it) is fully satisfied.

    Verification (really-done): fresh `swift build` exit 0, all Examples targets; fresh `swift test` 99/99 in 9 suites green with the 4 gated skips intact. Adversarial double-check verdict: PASS — confirmed the helper body is character-identical to the replaced code at both sites, exactly one `SelectionTier(` construction site remains in the package, no stale `makeSelectionTier` references, pure refactor, no unrelated diff. Not committed — orchestrator handles commits.
  timestamp: 2026-07-15T20:34:25.822381+00:00
- actor: claude-code
  id: 01kxksj0m1r2a8p7md00szp4y2
  text: |-
    Pulled review->doing for the four 15:49 findings. Research done; plan:

    Findings 1-2 (Package.swift): extract `swissArmyHammerOrg` / `huggingFaceOrg` URL-base constants (3 uses each — swift-jinja is the third huggingface one).

    Finding 3: fold `buildSelectionTierPair` + the two `.map{}` call sites into ONE static helper `buildSelectionTierIfConfigured(config: SelectionConfig?, index:weights:embedder:onDiagnostic:) -> (tier:snapshot:)?` (guard-let inside). Still static — the SE-0327 constraint recorded in the prior comment stands; both init and update call it directly, no mapping shape left anywhere.

    Finding 4 root-cause analysis: verified against the PINNED Ranker b3ce6f5 (.build/checkouts, which differs from ../FoundationModelsRanker HEAD): `retrievalRanking` feeds ONLY the over-budget candidate cut (under-budget is pure-selection 1.0/nil, no ranking call). The staleness is real: the closure captures the index VALUE at tier-build time, and embeddings merged post-await never reach it. The reviewer's suggested `contentChanged || !pendingEmbedIDs.isEmpty` rebuild-at-line-239 does NOT fix it (rebuild happens pre-await, so it captures the pre-merge baseline); rebuilding after the merge instead would drop the cached root on every catch-up, violating the documented no-re-prefill optimization. Root fix: pair the tier with a REFRESHABLE snapshot (OSAllocatedUnfairLock<MetadataIndex<Item>>, matching the family's lock pattern); the ranking closure reads it at call time, and update(items:) refreshes it right after the mergingEmbeddings assignment. Reentrancy invariant holds: mergingEmbeddings never changes content (only vectors, hash-guarded), and every content change replaces the whole (tier, snapshot) pair, so a pair's snapshot content always ≡ its tier's catalog content.

    Regression tests (TDD RED first, HotReloadTests): (a) content-unchanged embed catch-up must make merged embeddings visible to the over-budget candidate cut — cosine-only item "z" must enter the top-2 grammar/summaries after catch-up (fails on old code: candidates stay catalog-order x,y); (b) content-identical catch-up retains the cached root session (pins the optimization against the naive rebuild fix).
  timestamp: 2026-07-15T21:05:08.737806+00:00
- actor: claude-code
  id: 01kxkt2sjpe38fba00q7kzxa0v
  text: |-
    All four 15:49 findings implemented; checkboxes flipped to [x]. TDD RED verified first: the new over-budget catch-up regression test failed on the old code exactly as predicted (candidates stayed catalog-order x,y; grammar enum ["x","y"], no z), then GREEN after the fix.

    What changed:
    - Package.swift: `swissArmyHammerOrg` + `huggingFaceOrg` URL-base constants, used by all 6 dependency entries (swift-jinja included). Resolved URLs byte-identical; Package.resolved untouched.
    - MetadataSearcher.swift: single static `buildSelectionTierIfConfigured(config:index:weights:embedder:onDiagnostic:) -> ConfiguredSelectionTier?` replaces `buildSelectionTierPair` + both `.map{}` call sites (finding 3, still static per the SE-0327 constraint). New private typealias `ConfiguredSelectionTier = (tier: SelectionTier, snapshot: OSAllocatedUnfairLock<MetadataIndex<Item>>)`.
    - Finding 4 root fix (NOT the reviewer's literal `contentChanged || !pendingEmbedIDs.isEmpty` suggestion, which cannot work: the rebuild runs BEFORE the awaited embed/merge, so it would still capture the pre-merge baseline; moving the rebuild after the merge would drop the cached root on every catch-up, breaking the documented no-re-prefill optimization): the tier's `retrievalRanking` now reads a refreshable lock-boxed snapshot at call time, and `update(items:)` refreshes it in place immediately after the post-await `mergingEmbeddings` assignment. Cached root survives content-identical catch-ups; merged embeddings reach the over-budget candidate cut immediately. Reentrancy invariant: snapshot content ≡ tier catalog content, because content changes replace the whole pair and mergingEmbeddings is hash-guarded to never change content — a late stale merge writes into the CURRENT pair's box with content matching the current tier.
    - HotReloadTests.swift: regression test (over-budget candidate set must include the cosine-promoted id after a content-unchanged catch-up) + optimization pin (content-identical catch-up retains the cached root; factory called once, root forked twice).

    Verification: swift build exit 0 (all Examples targets; the one-time "missing creator ... Cmlx.bundle" llbuild warning is a transient re-plan artifact after touching Package.swift — gone on subsequent builds, also present on the unmodified tree). swift test: 101 tests in 9 suites, all passing (was 99; +2 new), GPU-free. Double-check agent running. Not committed — orchestrator handles commits.
  timestamp: 2026-07-15T21:14:18.582257+00:00
- actor: claude-code
  id: 01kxktfncybcd7p5w9etdcv091
  text: 'really-done complete; leaving in doing for /review. Fresh verification: swift build exit 0 ("Build complete!", all Examples targets, no warnings); swift test 101 tests in 9 suites all passing, GPU-free. Adversarial double-check verdict: PASS — it independently confirmed the resolved dependency URLs are byte-identical (Package.resolved clean), the helper fold is exact, the snapshot-≡-tier-catalog invariant survives every reentrancy interleaving it tried (mergingEmbeddings provably never changes content via withEmbedding; stale updates only ever write the CURRENT pair''s snapshot; replaced pairs'' snapshots are frozen), the rejected reviewer suggestion is genuinely wrong against the pinned Ranker b3ce6f5 (retrievalRanking only feeds overBudgetSearch; a post-merge rebuild would drop the cached root every catch-up), and the RED claim for the regression test is mechanically sound (zero-vector fallback → catalog-order candidates x,y on old code). All four 15:49 finding checkboxes are [x] on the card. Diff scope: Package.swift, MetadataSearcher.swift, HotReloadTests.swift only. Not committed — orchestrator handles commits.'
  timestamp: 2026-07-15T21:21:20.286759+00:00
- actor: claude-code
  id: 01kxkw6kqdnpaq7279d7zf30y6
  text: |-
    Pulled review->doing for the two 16:25 findings; both implemented and checkboxes flipped to [x].

    Finding 1 (MetadataSearcher.swift): extracted `private static func computeRanking(intent:index:weights:embedder:onDiagnostic:) async -> (signals: RetrievalSignals, normalized: [Int: Double], rankedIndices: [Int])` — the computeSignals -> fuseAndNormalize -> sortByNormalizedScore(Array(normalized.keys)) block both callers shared. retrievalSearch now keeps only its limit-truncated prefix; rankEntireCatalog keeps only its ranked + unranked-tail concatenation. Deviation from the reviewer's literal shape: the helper is static, not an instance `async func` — rankEntireCatalog is static (captured by the tier's retrievalRanking closure) while retrievalSearch is an instance method, so static is the only shape callable from both; the finding's substance (one shared ranking computation, callers own only document selection) is fully satisfied. Also updated the three doc comments (sortByNormalizedScore, RetrievalSignals, computeSignals) that described the old two-caller sharing.

    Finding 2 (HotReloadTests.swift): all THREE local `struct AlwaysFails: Error {}` definitions removed (the finding named two new tests; the original in updateStillCatchesUpAnEmbedding... was the third) and replaced by one shared nested `AlwaysFails` in the Fixtures section with a doc comment.

    Pure refactor, no behavior change — per /tdd's own scope rule no new test written; the existing suite is the safety net. Verification: fresh `swift build` exit 0 (all Examples targets); fresh `swift test` 101 tests in 9 suites all passing, 4 gated skips intact (Gated Router-backed integration suite). Adversarial double-check in flight; not committed — orchestrator handles commits.
  timestamp: 2026-07-15T21:51:20.813389+00:00
- actor: claude-code
  id: 01kxkwjbp00cwgc0f0hb5tnggv
  text: 'really-done complete for the 16:25 findings; leaving in doing for /review. Fresh verification: swift build exit 0 (all Examples targets), swift test 101 tests in 9 suites all passing, 4 gated skips intact. Adversarial double-check verdict: PASS — it independently re-ran swift test (same 101/9 green, gated suite skipped), confirmed the extracted computeRanking body is step-for-step identical to both replaced blocks (same parameter passthrough, ordering/tie-break/normalized/signals unchanged), both guards survived, computeSignals/fuseAndNormalize/sortByNormalizedScore each have exactly one call site now (no residual duplication, no stale orderedDocumentIndices references), exactly one AlwaysFails declaration repo-wide with three resolving usages, and the diff scope is only the two fix targets plus kanban record files. Both 16:25 checkboxes are [x] on the card. Not committed — orchestrator handles commits.'
  timestamp: 2026-07-15T21:57:45.792204+00:00
position_column: doing
position_ordinal: '80'
title: 'Selection-tier migration: rebase MetadataSearcher on FoundationModelsRanker''s SelectionTier and delete the local shadowed copies'
---
## What
Finish the migration that the FoundationModelsRanker adoption (task ^hcnxvf6) started. Retrieval primitives already come from the shared `FoundationModelsRanker` dependency, but the selection tier still exists in BOTH packages, held together by the shadowing arrangement documented in `Sources/FoundationModelsMetadataRegistry/FoundationModelsRankerReexport.swift` (this package's local `public` declarations shadow Ranker's re-exported ones; the local internal `SelectionTier` shadows only inside the module, so external clients already resolve `SelectionTier` to Ranker's public actor). Drive `MetadataSearcher`'s selection path through Ranker's public `SelectionTier` and delete the local duplicates, so the runaway-grammar class of fix (task ^678h0ex) never again needs to land in three places.

Ranker's API (verified in `../FoundationModelsRanker/Sources/FoundationModelsRanker/Selection/`):
- `public actor SelectionTier` (NON-generic): `init(catalog: any SelectionCatalog, config: SelectionConfig, onDiagnostic:, retrievalRanking:)`, `search(intent:limit:) -> [SelectionMatch]`. It builds the maxItems-capped id-enum grammar itself and passes it to the session factory.
- `public protocol SelectionCatalog`: `var ids: [String]`, `func summaryBlock(forId:) -> String?`, `func block(forId:) -> String?` — written specifically to generalize this package's `MetadataIndex<Item>` (see its header comment); conformance is trivial forwarding to `MetadataIndex.item(forID:)?.renderSummaryBlock()` / `MetadataIndex.block(forID:)`.
- `SelectionConfig.model` is `@Sendable (String, Grammar) -> any AgentSession` — the grammar now flows through the factory per call, whereas the local factory is `(String) -> any AgentSession` with the caller pre-baking the grammar. This is the one public API signature change; it ripples to `MetadataSearcher`'s selection init path, `Examples/LiveRouterSupport/LiveRouterSupport.swift` (`buildSelectionConfig` and its hand-rolled `idEnumGrammar(ids:)`, which becomes unnecessary), and the selection tests.
- Diagnostics arrive as `RankDiagnostic` (`.retrievalCut`, `.unknownSelectedId`, `.embeddingUnavailable`); map them into the existing `MetadataDiagnostic` cases so `MetadataSearcher`'s `onDiagnostic` channel is unchanged for consumers.
- `SelectionMatch` carries `id`/`block`/`score`/`signals` but no typed item; `MetadataSearcher` re-attaches `item` by id lookup to produce `Match<Item>`.
- Preamble default is `.selectionDefault`; keep the local `.librarianDefault` name as an alias or migrate call sites — do not silently change the prompt text.

Subtasks:
- [x] Conform `MetadataIndex<Item>` to `SelectionCatalog` in `Sources/FoundationModelsMetadataRegistry/Catalog/MetadataIndex.swift` (forwarding `ids`, `summaryBlock(forId:)`, `block(forId:)`)
- [x] Rebase `MetadataSearcher`'s `.selection` path (`Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift`) on Ranker's `SelectionTier`: adopt the `(String, Grammar)` session-factory shape, map `SelectionMatch` → `Match<Item>` by id, map `RankDiagnostic` → `MetadataDiagnostic`
- [x] Update `Examples/LiveRouterSupport/LiveRouterSupport.swift`: `buildSelectionConfig` vends grammar-guided sessions from the factory's `Grammar` parameter; delete its hand-built `idEnumGrammar(ids:)`
- [x] Delete the shadowed local files — `Sources/FoundationModelsMetadataRegistry/Selection/Selection.swift`, `Selection/SelectionTier.swift`, `Selection/SelectionConfig.swift`, `Session/AgentSession.swift`, and the local `SelectionTierUnavailable` in `MetadataSearcher.swift` (all resolve through the re-export) — and reduce `FoundationModelsRankerReexport.swift` to a plain re-export with no shadowing explanation
- [x] Annotate `plan.md` (§5 superseded note, §6 grammar-ownership sentence, decision #12) to record that the factory now receives the grammar from the tier and the migration is complete

## Acceptance Criteria
- [x] `grep -rn "actor SelectionTier\|struct SelectionConfig\|protocol AgentSession\|struct RoutedAgentSession\|struct Selection\b\|SelectionTierUnavailable" Sources/FoundationModelsMetadataRegistry/` finds no local type declarations — every selection-tier type resolves through the `FoundationModelsRanker` re-export
- [x] `FoundationModelsRankerReexport.swift` contains only the re-export and a one-paragraph rationale; no shadowing rules documented
- [x] `MetadataSearcher.search(intent:limit:)` in `.selection` mode still returns `Match<Item>` with verbatim catalog blocks and typed `item`s (score 1.0/signals nil under budget; real retrieval score/signals over budget)
- [x] Ranker's `.retrievalCut`, `.unknownSelectedId`, and `.embeddingUnavailable` diagnostics surface through `onDiagnostic` as the same-named `MetadataDiagnostic` cases — none silently dropped
- [x] Selection behavior parity holds: root session created once and forked per under-budget call; over-budget path seeds a one-off session with top-`candidateLimit` candidates; the grammar is maxItems-capped (now built inside Ranker's tier)
- [x] `plan.md` §5/§6/decision #12 updated as described

## Tests
- [x] Update `Tests/FoundationModelsMetadataRegistryTests/SelectionTests.swift`, `OverBudgetTests.swift`, and `AgentSessionTests.swift` plus the fakes in `Tests/FoundationModelsMetadataRegistryTests/TestSupport/ScriptedAgentSession.swift` and `TestSupport/SelectionFixtures.swift` to the `(String, Grammar)` factory shape, keeping every existing assertion (fork counts, summary-vs-full block separation, verbatim lookup, unknown-id filtering + diagnostic, retrievalCut counts)
- [x] Add one regression test asserting the `Grammar` handed to the session factory constrains ids to the current candidate set and caps `maxItems` at the candidate count (covers the ^678h0ex fix through the Ranker path)
- [x] Run `swift test` — all suites pass GPU-free (currently 98 tests; count may grow), including `ExamplesSmokeTests`
- [x] `swift build` compiles every Examples target (the gated `RouterIntegrationTests` and Router-backed example paths compile unchanged)

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

Note on sizing: four of the touched files are straight deletions of dead shadowed duplicates and two are comment/doc edits; the substantive implementation is confined to `MetadataIndex.swift`, `MetadataSearcher.swift`, and `LiveRouterSupport.swift` — one concern (resolve the selection tier through Ranker), not several.

## Review Findings (2026-07-15 15:12)

- [x] `Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift:177` — Selection tier initialization is duplicated between the designated init and the update(items:) method. Both blocks construct an identical `(tier:snapshot:)` pair by calling `makeSelectionTier` with the same parameters, differing only in which index variable is passed. This duplication is a maintenance burden: changes to tier construction logic must be applied in both places or they will drift out of sync. Extract a helper instance method `private func buildSelectionTierPair(index: MetadataIndex<Item>, config: SelectionConfig) -> (tier: SelectionTier, snapshot: MetadataIndex<Item>)` that takes the index as a parameter and reuses the stored `weights`, `embedder`, and `onDiagnostic`. Then replace both call sites with `selection.map { buildSelectionTierPair(index: index, config: $0) }` and `selectionConfig.map { buildSelectionTierPair(index: baseline, config: $0) }` respectively.

## Review Findings (2026-07-15 15:49)

- [x] `Package.swift:66` — URL base `https://github.com/swissarmyhammer/` appears 3 times in the dependencies array (lines ~66, ~67, ~68) and should be extracted to a named constant to avoid duplication and ease future updates. Extract `let swissArmyHammerOrg = "https://github.com/swissarmyhammer/"` as a constant and use `.package(url: "\(swissArmyHammerOrg)\(routerDependencyName)", ...)` in each dependency.
- [x] `Package.swift:69` — URL base `https://github.com/huggingface/` appears 3 times in the dependencies array (lines ~69, ~70, ~76) and should be extracted to a named constant to avoid duplication. Extract `let huggingFaceOrg = "https://github.com/huggingface/"` as a constant and reuse it across all three huggingface dependencies.
- [x] `Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift:225` — Selection tier construction is near-duplicated between the designated initializer and update(items:). Both blocks map a config optional to a buildSelectionTierPair call with identical structure, differing only in which optional is mapped (selection vs selectionConfig) and which index is passed (index vs baseline). This invites maintenance drift when the tier-building logic changes. Extract the mapping into a helper method, e.g. `buildSelectionTierIfConfigured(config:index:weights:embedder:onDiagnostic:)`, that returns the mapped tier or nil. Call it from both sites, passing the appropriate optional and index.
- [x] `Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift:239` — Selection tier's ranking omits newly-computed embeddings when content hasn't changed. The tier is rebuilt only when `contentChanged` is true (line 239), but embeddings are merged into `index` regardless (lines 252–254). The tier's `retrievalRanking` closure captured the old index at tier-build time and won't see the subsequently merged embeddings, so selection ranking won't reflect new embeddings until the next content change. Rebuild the selection tier when embeddings are caught up, not just when content changes. Change the condition at line 239 to `if contentChanged || !pendingEmbedIDs.isEmpty` so the tier's `retrievalRanking` closure captures the updated index with newly-merged embeddings.

## Review Findings (2026-07-15 16:25)

- [x] `Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift:508` — retrievalSearch and rankEntireCatalog contain near-identical ranking computation blocks that differ only by variable names (orderedDocumentIndices vs rankedIndices) and method qualifiers (Self. vs none). Duplication creates maintenance burden: fixes to ranking logic must be applied to both methods. Extract the common ranking computation into a shared helper: `private async func computeRanking(intent:index:weights:embedder:onDiagnostic:) -> (signals:RetrievalSignals, normalized:[Int:Double], rankedIndices:[Int])`. Both functions then call it once and handle only their own document-selection logic (limit-based prefix vs. ranked + unranked concatenation).
- [x] `Tests/FoundationModelsMetadataRegistryTests/HotReloadTests.swift:244` — Redefines `struct AlwaysFails: Error {}` locally instead of reusing the identical type already defined in `updateStillCatchesUpAnEmbeddingThatNeverSucceededEvenWhenContentIsUnchanged` (line 221). This type should be extracted to a shared location (nested in HotReloadTests or file-level) and reused across all three test functions that need it. Extract `struct AlwaysFails: Error {}` as a nested struct within HotReloadTests (or top-level in the file) and remove the local redefinition from both newly added test functions, reusing the shared type instead.