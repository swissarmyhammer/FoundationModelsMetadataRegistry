---
comments:
- actor: claude-code
  id: 01kwn6tb6egffhmqjjvw1bdf3a
  text: 'Picked up by /finish scoped-batch loop (task 8 of batch). Plan: /implement → /test → /commit checkpoint → /review HEAD~1..HEAD.'
  timestamp: 2026-07-04T00:00:25.806433+00:00
- actor: claude-code
  id: 01kwpev7ktvskw94f8hfk1p784
  text: |-
    Implemented the over-budget selection path and .auto resolution (resumed after session interruption; test file OverBudgetTests.swift was already written/RED-confirmed by the prior session).

    Production changes:
    - Sources/.../Selection/SelectionTier.swift: added `retrievalRanking: @Sendable (String) async -> [Match<Item>]` closure param to init; `search()` now calls a new `overBudgetSearch(intent:limit:)` instead of throwing when over budget. It ranks the whole catalog via `retrievalRanking`, takes `Array(ranked.prefix(config.candidateLimit))` as candidates, fires `.retrievalCut(considered: ranked.count, kept: candidates.count)`, builds a one-off prefix via a new `assemblePrefix(preamble:ids:index:)` overload (widened from `private` to internal `static` so tests can compute expected prefix length directly), creates a session via `config.model(prefix)` with NO fork and NO caching, and maps selection ids back to Matches via `matches(forIds:limit:allowedIds:retrievalMatches:)` — a generalized version of the existing verbatim-lookup helper that (a) restricts resolution to the current candidate id set (an id outside it, even a real catalog id, is treated as `.unknownSelectedId`) and (b) attaches the real retrieval score/signals from the candidate's own Match instead of the pure-selection 1.0/nil.
    - Sources/.../MetadataSearcher.swift: `.auto` now resolves to selection when a selectionTier is configured, retrieval otherwise (previously always fell back to retrieval). Refactored the retrieval-tier compute functions (BM25/trigram/cosine + RRF fuse/normalize + Match-building) from instance methods to static, parameterized ones so a new `static func rankEntireCatalog(intent:index:weights:embedder:onDiagnostic:)` could reuse them — it returns exactly `index.count` matches always (real-ranked prefix + zero-signal catalog-order fallback tail), which is what guarantees the over-budget candidate count is always `min(candidateLimit, catalog size)` even when a query's signal overlap is sparse. This closure is wired into `SelectionTier` at `MetadataSearcher.init`.
    - Updated stale "later task" doc comments across SelectionTier/SelectionConfig/SearchMode/MetadataSearcher now that the over-budget path and .auto both exist.
    - Removed the now-invalid `overBudgetPrefixThrowsSelectionTierUnavailableWithoutInvokingTheSessionFactory` test from SelectionTests.swift (its premise — over budget always throws — is no longer true) and updated that file's header doc to point over-budget/.auto coverage at OverBudgetTests.swift.

    Test-file gotcha found: two of the new tests initially failed because default `Weights` has `cosine: 1.0` with no embedder configured, so `rankEntireCatalog`'s cosine computation legitimately fires `.embeddingUnavailable` in addition to `.retrievalCut` — fixed by passing `weights: Weights(cosine: 0.0)` in the two diagnostic-payload tests that assert an exact `recorder.diagnostics` array (this is correct/expected behavior, not a bug).

    Verification:
    - `swift build`: clean, exit 0, no warnings from this package's own code.
    - `swift test --filter OverBudgetTests`: 13/13 passed.
    - `swift test` (full suite): 106/106 passed, 9 suites (94 pre-existing minus the 1 removed stale test, plus 13 new = 106), zero failures, zero warnings.

    Leaving in `doing` for review per /implement workflow.
  timestamp: 2026-07-04T11:39:57.946195+00:00
- actor: claude-code
  id: 01kwpf8xjxp01ymza1mv640cbk
  text: 'Iteration 1: implement resumed after a session-limit interruption, landed green in doing (106 tests passed / 0 failed across 9 suites, TDD red→green verified, double-check PASS). Checkpoint committed at 2610d91. Note: assemblePrefix widened from private to internal-static to support direct test verification; default Weights has cosine:1.0 with no embedder configured, so rankEntireCatalog legitimately also fires .embeddingUnavailable alongside .retrievalCut in some tests (not a bug — tests pass weights: Weights(cosine: 0.0) where an exact diagnostics array is asserted). Proceeding to /review HEAD~1..HEAD.'
  timestamp: 2026-07-04T11:47:26.429057+00:00
- actor: claude-code
  id: 01kwpg4n1tndjcyrmkz4cke6md
  text: |-
    Addressed all 6 review-findings duplication/naming items in Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift (pure refactor, no behavior change):

    1&2. Extracted `private static func sortByNormalizedScore(_ indices: [Int], using normalized: [Int: Double]) -> [Int]` (descending fused score, ascending-index tie-break) and replaced the verbatim-duplicated sort comparators in both `retrievalSearch` (called via `Self.sortByNormalizedScore(Array(normalized.keys), using: normalized)`) and `rankEntireCatalog` (called directly since it's already static).

    3&4. Extracted `private static func embeddingUnavailableRanking(count: Int, onDiagnostic: ...) -> (ranking: [Int], scores: [Double])` — reports `.embeddingUnavailable` and returns the zero-filled ranking. Replaced all 3 repeated `onDiagnostic(.embeddingUnavailable); return ([], zeroScores)` blocks in `computeCosineRanking` (no-embedder guard, empty-embed-result guard, catch block) with calls to this helper. Removed the now-unused local `zeroScores` variable.

    5. Renamed `computeBM25Ranking` → `computeBm25Ranking` to match the lowercase-algorithm-name convention (`computeTrigramRanking`, `computeCosineRanking`, `bm25Ranking`/`trigramRanking`/`cosineRanking` properties). Updated its one call site in `computeSignals`. Confirmed via grep zero remaining references to the old name in Sources or Tests.

    6. Extracted `private static func zeroScoresArray(count: Int) -> [Double] { [Double](repeating: 0.0, count: count) }` and replaced all 3 occurrences: `computeSignals`'s cosine-disabled else branch, `computeBm25Ranking`'s empty-query early return, and inside the new `embeddingUnavailableRanking` helper. Confirmed via grep the inline `[Double](repeating: 0.0, count:...)` literal now appears exactly once in the file (inside the helper itself).

    Verification:
    - `swift build`: clean, exit 0.
    - `swift test`: 106/106 passed, 9 suites, zero failures (same count as before — pure refactor).
    - Adversarial double-check agent: PASS — confirmed tie-break semantics unchanged, `count` parameter correct at all embeddingUnavailableRanking call sites, zero leftover references to old BM25 name, zero leftover inline zero-array duplication, and no access-level/placement issues with the new private static helpers.

    All 6 checklist items flipped to [x]. Leaving task in `doing` per orchestrator instructions (not moving to review).
  timestamp: 2026-07-04T12:02:35.194005+00:00
- actor: claude-code
  id: 01kwpgszd1y04fq44b1b9xhh9w
  text: |-
    Pulled back from `review` to fix the first item of the 2026-07-04 07:05 review findings only, per orchestrator instruction.

    Fixed: `Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift` — `static func rankEntireCatalog(...)` was missing an explicit access modifier (defaulted to `internal`). Added `private` so it matches every other helper in the file's explicit-access-control pattern. One-line change, no behavior change.

    Deliberately left unfixed: the second item, which asks to rename `computeBm25Ranking` → `computeBM25Ranking`. This directly contradicts the checked-off 2026-07-04 06:47 finding that required the opposite rename (`computeBM25Ranking` → `computeBm25Ranking`) to match the lowercase `computeTrigramRanking`/`computeCosineRanking` convention. Per orchestrator instruction, this is a genuine oscillating/contradictory finding across review rounds and is being escalated as a blocker for human resolution rather than "fixed" by picking a side. The function's name in the file is untouched (`computeBm25Ranking`, matching the current lowercase state).

    Verification:
    - `swift build`: clean, exit 0.
    - `swift test`: 106/106 passed, 9 suites, zero failures.

    Checklist state: first item of the 2026-07-04 07:05 findings flipped to [x]; second item left unchecked as an open blocker. Leaving task in `doing` per orchestrator instruction (not moving to review).
  timestamp: 2026-07-04T12:14:13.921870+00:00
- actor: claude-code
  id: 01kwpgxepva9cp56p2atyghsdm
  text: 'STUCK — leaving in review, not forcing to done. Checkpoint committed at 6f4cdfe (private-modifier fix applied, 106 tests green). Blocker: the "## Review Findings (2026-07-04 07:05)" checklist''s second item is a genuine contradiction with the already-checked "## Review Findings (2026-07-04 06:47)" item — round 1 mandated renaming computeBM25Ranking → computeBm25Ranking (lowercase, to match computeTrigramRanking/computeCosineRanking''s lowercase-camelCase convention); round 2 (this same file, unchanged in between) mandates the opposite rename back to computeBM25Ranking (treating BM25 as an all-caps acronym). Both cite the same sibling functions as precedent for opposite conclusions — this is an oscillating/contradictory style rule, not a code defect. Per the finish skill''s Scope rule, I am not picking a winner and not editing validators. A human needs to decide the house convention for acronym casing in this codebase (e.g. does BM25 get treated as a proper acronym like URL/ID, or as a regular word like Trigram/Cosine) and then either fix the naming or update the validator rule accordingly. Current state on disk: computeBm25Ranking (lowercase), tests green, all other findings resolved.'
  timestamp: 2026-07-04T12:16:07.899224+00:00
- actor: claude-code
  id: 01kwpqfkgjvg111t177kzy7c26
  text: |-
    Resolved the naming contradiction flagged in the previous comment: a human (the product owner) was asked directly which casing to use for the BM25 function name, given the two review rounds oscillated between `computeBm25Ranking` and `computeBM25Ranking`. The human's decision: BM25 is an acronym and should be treated as all-caps, so `computeBM25Ranking` is correct — this takes precedence over the lowercase-algorithm-name convention argument from the 2026-07-04 06:47 review round.

    Changes made in Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift:
    - Renamed `computeBm25Ranking` → `computeBM25Ranking` (function definition).
    - Updated its one call site in `computeSignals`.
    - Pure rename, no behavior change. Confirmed via grep: zero remaining references to `computeBm25Ranking` in Sources or Tests.

    Checked off the second item of the "## Review Findings (2026-07-04 07:05)" checklist (the one requesting this exact rename) since it is now satisfied.

    Verification:
    - `swift build`: clean, exit 0.
    - `swift test`: 110/110 passed, 10 suites, zero failures, zero warnings.

    Leaving task in `doing` for `/review`.
  timestamp: 2026-07-04T14:10:54.098296+00:00
depends_on:
- 01KWMEDGSYSM044AX49AG27GAQ
position_column: doing
position_ordinal: '80'
title: Over-budget selection path (retrieval top-M → one-off session) and .auto mode
---
## What\nComplete the selection tier per plan.md §6/§7 (replaces Multitool's `lexicallyFilter` keep/drop):\n- Over budget (preamble + all summary blocks > `capacityCharacterLimit`, using `renderSummaryBlock()` like the under-budget path): retrieval tier ranks the catalog, top-M candidates (default 24, best-first ordering passed to the prompt as summary blocks) seed a **one-off session** — no caching, no fork\n- Id-enum grammar for the one-off session is constrained to the top-M candidate ids only\n- Report the cut through the shared diagnostics surface as `MetadataDiagnostic.retrievalCut(considered:kept:)` (the generalization of Multitool's `onPrefilterCut`, `Librarian.swift:49,88,204`; default logs)\n- `.auto` mode: selection when a model/session factory is configured, else retrieval (plan.md §7)\n- Retrieval-tier `signals` attach to over-budget results where retrieval participated\n\n## Acceptance Criteria\n- [ ] A catalog whose assembled prefix exceeds the budget takes the one-off path: no root caching, zero forks, candidate count == min(candidateLimit, catalog size)\n- [ ] `.retrievalCut` fires with accurate considered/kept counts; under-budget searches never fire it\n- [ ] `.auto` resolves to selection with a session factory configured and retrieval without one\n- [ ] One-off prompt contains candidate summary blocks in best-first retrieval order\n\n## Tests\n- [ ] `Tests/FoundationModelsMetadataRegistryTests/OverBudgetTests.swift` — scripted fakes: budget boundary (at/over limit), top-M membership and ordering, one-off grammar id set, `.retrievalCut` payload capture, `.auto` resolution both ways\n- [ ] Run `swift test` — all pass, no GPU\n\n## Workflow\n- Use `/tdd` — write failing tests first, then implement to make them pass.\n\n## Review Findings (2026-07-04 06:47)\n\n- [x] `Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift:189` — The sorting comparator for normalized document scores is verbatim duplicated in rankEntireCatalog — both functions use identical sort-by-descending-score logic with the same tie-breaker. Two blocks differing only in variable names should be extracted into one function. Extract the tie-breaking sort logic into a private static helper: `private static func sortByNormalizedScore(_ indices: [Int], using normalized: [Int: Double]) -> [Int]` and call from both locations.\n- [x] `Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift:230` — This sorting comparator duplicates the identical logic from retrievalSearch (line ~189) — both normalize then sort by descending fused score with identical tie-breaking. Duplicate sorting code inflates maintenance surface area. Call the extracted static helper function instead of repeating the sort comparator.\n- [x] `Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift:356` — Identical error-handling pattern appears three times in computeCosineRanking (lines 356, 368, 375) — each reports .embeddingUnavailable and returns the same zero-filled ranking. Rule of three: extract into a shared helper function. Extract to a private helper method that encapsulates the embedding-unavailable error response, or restructure to call a common error-return path.\n- [x] `Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift:375` — This error handling duplicates the identical pattern from lines 356 and 368 — same onDiagnostic(.embeddingUnavailable) and return ([], zeroScores), repeated three times in computeCosineRanking. Call extracted helper function for this error case.\n- [x] `Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift:418` — Function name `computeBM25Ranking` uses uppercase 'BM25' while similar algorithm functions use lowercase algorithm names: `computeTrigramRanking`, `computeCosineRanking`. The corresponding property names also use lowercase: `bm25Ranking`, `trigramRanking`, `cosineRanking`. This inconsistency breaks the established naming pattern for algorithm-prefixed identifiers within the file. Rename `computeBM25Ranking` to `computeBm25Ranking` to match the lowercase algorithm-name pattern established by `computeTrigramRanking` and `computeCosineRanking`.\n- [x] `Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift:437` — The expression `[Double](repeating: 0.0, count: index.count)` appears three times across signal-ranking functions when a signal cannot be computed (empty query, disabled weight, missing embedder). This repeated initialization pattern should be extracted to a named helper to eliminate duplication and clarify semantics. Extract to a private static helper: `private static func zeroScoresArray(count: Int) -> [Double] { [Double](repeating: 0.0, count: count) }` and replace all three occurrences with calls to this helper.\n\n## Review Findings (2026-07-04 07:05)\n\n- [x] `Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift:267` — The `static func rankEntireCatalog` lacks an explicit access modifier; it defaults to `internal`. Per the access-control rule, library declarations must spell access modifiers explicitly when their intent is API-shaping. This function is specifically designed for `SelectionTier`'s use (per its documentation), yet it breaks the consistent pattern where every other helper function in this file is explicitly marked `private`. Add explicit `private` modifier: `private static func rankEntireCatalog(...)` to clarify that it is not public API and to match the consistent access-control pattern established throughout the file.\n- [x] `Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift:301` — Function `computeBm25Ranking` uses inconsistent capitalization compared to similar algorithm-ranking functions `computeTrigramRanking` and `computeCosineRanking`, which capitalize their algorithm names fully in camelCase style (Trigram, Cosine). The BM25 algorithm should follow the same pattern. Rename `computeBm25Ranking` to `computeBM25Ranking` to match the established convention.\n\n**Note on the second item above:** this directly contradicts the checked-off 2026-07-04 06:47 finding, which required renaming `computeBM25Ranking` → `computeBm25Ranking` for exactly the opposite reason (lowercase to match `computeTrigramRanking`/`computeCosineRanking`'s established pattern, which itself is lowercase camelCase — `Trigram`/`Cosine` are not all-caps acronyms so there is no actual precedent for all-caps `BM25`). The two review passes want opposite casings for the same identifier. Not obeying either blindly — flagging as a contradictory/oscillating rule for a human to resolve; the first item (missing `private` on `rankEntireCatalog`) is a genuine, non-contradictory finding and should be fixed.\n\n**Resolution (2026-07-04):** The human product owner was asked directly and decided: BM25 should be treated as an acronym, all-caps — `computeBM25Ranking` is the correct name. The function has been renamed accordingly and the checklist item above is now checked off.