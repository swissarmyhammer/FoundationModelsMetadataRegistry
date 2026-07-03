---
comments:
- actor: claude-code
  id: 01kwn4qceam621b2e23hh2yz09
  text: 'Picked up by /finish scoped-batch loop (task 7 of batch). Plan: /implement → /test → /commit checkpoint → /review HEAD~1..HEAD.'
  timestamp: 2026-07-03T23:23:51.626814+00:00
- actor: claude-code
  id: 01kwn5s47qxrfshxa5kx62qrj2
  text: |-
    Implemented and green. Read Multitool's Librarian.swift, this package's AgentSession/MetadataSearcher/MetadataIndex/Match/Diagnostics, and Router's Grammar/GuidedGeneration before writing any code.

    Created (Sources/FoundationModelsMetadataRegistry/Selection/):
    - Selection.swift — `@Generable struct Selection { var ids: [String] }`, ids-only guided output.
    - SelectionConfig.swift — `model` session-factory closure over the `AgentSession` seam, `preamble` (defaults to `.librarianDefault`, a `String` extension holding Multitool's selectionGuidance verbatim per the task's explicit dot-syntax request), `capacityCharacterLimit` (default 32_000), `candidateLimit` (default 24, stored but unused until the over-budget task lands).
    - SelectionTier.swift — the actor: assembles prefix from preamble + every item's `renderSummaryBlock()` (never `renderBlock()`); under budget, caches root session and forks a child per `search()`; maps ids back through `MetadataIndex` to verbatim `Match`es (score 1.0, signals nil); dedupes repeated ids (first occurrence wins, no diagnostic) before the unknown-id check, which does fire `.unknownSelectedId`; over budget throws `SelectionTierUnavailable` (real one-off path is 01KWMEDXA34D8ZPB8AEZE57A3J, explicitly out of scope here). Static `idEnumGrammar(ids:)` derives `Selection.generationSchema`, injects `enum` + `uniqueItems` into the `ids` array's `items`/array subschema, wraps as `Grammar.jsonSchema(_:)`.

    Modified MetadataSearcher.swift: added optional `selection: SelectionConfig?` to all three public inits; `.selection` mode now delegates to the configured `SelectionTier`, still throwing `SelectionTierUnavailable` when none is configured (unchanged prior behavior, still covered by the pre-existing test in RetrievalSearchTests.swift). `.auto` intentionally left untouched (still always retrieval) — that resolution is 01KWMEDXA34D8ZPB8AEZE57A3J's job.

    Tests: Tests/FoundationModelsMetadataRegistryTests/SelectionTests.swift + TestSupport/SelectionFixtures.swift (RootSessionRespondCalledDirectlySession, RecordingSessionFactory, CallCounter — mirrors Multitool's LibrarianFixtures.swift). TDD followed: wrote the full test file first, ran `swift test`, confirmed RED (missing-symbol compile errors for SelectionConfig/SelectionTier/the new init parameter — not typos), then implemented to GREEN.

    Ran the `really-done` skill's adversarial double-check (subagent_type: double-check) twice (the bounded max). First pass: REVISE with 3 findings, all test-coverage gaps, no correctness bugs — (1) over-budget throw untested with a real config, (2) empty-ids/empty-catalog untested end-to-end, (3) duplicate-id handling untested/undocumented. Fixed all three: added dedup + `uniqueItems` grammar constraint, and 5 new tests. Second pass: REVISE again, but only on one residual sub-point — the duplicate-id test used `limit: 5` so the `limit`-slot-crowding regression it was meant to pin wasn't actually exercised. Fixed by adding `duplicateIdDoesNotConsumeALimitSlotAndCrowdOutALaterLegitimateMatch` (limit: 2, asserts `["deploy","rollback"]` survives past a leading duplicate). Per really-done's "bound the loop to one re-spawn" rule, did not spawn a third double-check; verified the fix directly with a fresh `swift test` run instead.

    Final: `swift build` — exit 0, no new warnings (only the pre-existing unrelated mlx-swift bundle warning). `swift test` — 94/94 passing (up from 80 before this task), 0 failures.

    Leaving in `doing` for /review per the implement workflow.
  timestamp: 2026-07-03T23:42:17.335106+00:00
depends_on:
- 01KWMECA3GC1631WXPX2BJN4DB
- 01KWMED1XXMRMQ4JFB92YPCTGD
position_column: doing
position_ordinal: '80'
title: 'Selection tier: cached root + fork-per-call, ids-only grammar-constrained output'
---
## What
Implement the under-budget selection path per plan.md §6 (M3), generalizing Multitool's shipped `Librarian` (`../FoundationModelsMultitool/Sources/.../Librarian.swift`), in `Sources/FoundationModelsMetadataRegistry/Selection/`:
- `SelectionConfig` — model (via a session-factory closure over the `AgentSession` seam), `preamble` with `.librarianDefault` (lift Multitool's `selectionGuidance` "fewest that suffice, in call order" verbatim, `Librarian.swift:41-45`), `capacityCharacterLimit` default 32_000, `candidateLimit` default 24
- The selection prefix and the capacity computation use **`renderSummaryBlock()`** (plan.md §4: the summary seeds the selection prefix; retrieval indexes the full `renderBlock()`)
- Under budget (assembled preamble + all summary blocks ≤ limit): build a **cached root session** seeded once with the prefix; each `search()` **forks** a child and asks it
- Guided output `@Generable struct Selection { var ids: [String] }`; id-enum grammar built from the current catalog ids (Router `Grammar.jsonSchema` with an enum constraint — the pattern at Multitool `Librarian.swift:143-149`)
- **Verbatim lookup**: returned ids map through the catalog to `Match`es carrying the full `renderBlock()` text (score 1.0, signals nil); any unknown id from the model is filtered and surfaced as the shared `MetadataDiagnostic.unknownSelectedId` case
- `.selection` mode wired into `MetadataSearcher`

## Acceptance Criteria
- [ ] Root session is created once and forked per search (fork count == search count with a scripted fake)
- [ ] A fixture whose `renderSummaryBlock()` differs from `renderBlock()` shows the summary in the session prefix and the full block in returned `Match`es
- [ ] Selection returns catalog blocks by lookup — model output contains only ids, never blocks
- [ ] Unknown id from a (deliberately misbehaving) fake is filtered with `.unknownSelectedId` emitted, not returned
- [ ] Id-enum grammar contains exactly the catalog's current ids

## Tests
- [ ] `Tests/FoundationModelsMetadataRegistryTests/SelectionTests.swift` — scripted `AgentSession` fakes: fork-per-call counts, summary-vs-full block separation, ids-only decode, verbatim lookup identity, unknown-id filtering + diagnostic capture, grammar id-set contents
- [ ] Run `swift test` — all pass, no GPU

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.