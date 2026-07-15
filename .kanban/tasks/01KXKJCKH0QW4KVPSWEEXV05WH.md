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