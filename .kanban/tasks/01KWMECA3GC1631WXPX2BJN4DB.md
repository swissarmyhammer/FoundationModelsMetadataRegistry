---
comments:
- actor: claude-code
  id: 01kwmxa0f96mhtb0pmzqrx6tss
  text: 'Picked up by /finish scoped-batch loop (task 4 of batch). Plan: /implement → /test → /commit checkpoint → /review HEAD~1..HEAD.'
  timestamp: 2026-07-03T21:14:13.353121+00:00
- actor: claude-code
  id: 01kwmy6zcy3kmpdt9jeg8a8t5d
  text: |-
    Implemented via TDD. New files:
    - Sources/FoundationModelsMetadataRegistry/SearchMode.swift — `enum SearchMode: Sendable { retrieval, selection, auto }`
    - Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift — `Weights` (bm25/trigram/cosine, default 1.0 each), `SelectionTierUnavailable` error, and `actor MetadataSearcher<Item: SearchableMetadata>` with `init(items:mode:weights:onDiagnostic:)` and `search(intent:limit:) async throws -> [Match<Item>]`.
    - Tests/FoundationModelsMetadataRegistryTests/RetrievalSearchTests.swift — 16 tests over a 20-item fixture catalog.

    Design notes (composed from existing Search/Catalog primitives per CodeContextKit's SearchCode.swift precedent, read from the sibling repo):
    - BM25 ranking: `Tokenizer.tokenize` the intent, guard empty tokens, build `BM25Corpus(queryTokens:documents:)` from `index.ids.map { (documentLength(forId:), termSet(forId:)) }`, score each id, keep only positive scores sorted descending (no zero-fill, matches RRF's absent-signal contract).
    - Trigram ranking: per id, `BM25.idFieldWeight * Trigram.dice(query, idTrigramSet) + BM25.blockFieldWeight * Trigram.dice(query, blockTrigramSet)` — reuses the same id/block field weights BM25 uses, matching `Signals.trigram`'s doc comment ("field-weighted aggregate across several fields") and the CodeContextKit precedent exactly.
    - Only signals with configured weight > 0 AND a non-empty ranking enter `RRF.fuse`/`RRF.normalize`'s inputs — keeps the normalization ceiling from counting an unreachable signal.
    - Cosine is always `Signals(cosine: 0.0)` (not nil — `Signals.cosine` is a non-optional `Double` in this codebase's already-shipped Hit.swift), matching the "no embedding available" value that type documents. No embedder tier exists yet.
    - `.auto` silently falls back to `.retrieval` (plan.md §7: "selection when a model is configured, else retrieval" — no model is ever configured in this task). Explicit `.selection` throws `SelectionTierUnavailable` rather than silently substituting retrieval.
    - `limit <= 0` returns `[]` (guarded explicitly — `ArraySlice.prefix(_:)` requires a non-negative count).
    - Tie-break on exactly equal fused scores: ascending index into `index.ids` (first-seen catalog order).

    Ran the adversarial double-check agent against the diff. Verdict: REVISE with one finding — the tie-break branch above had no test forcing an actual score tie (dead code from a coverage standpoint). Fixed by adding `tieBreakFavorsFirstSeenCatalogOrder`: two engineered fixture items whose BM25/trigram rankings cross over (rank0/rank1 vs rank1/rank0), which under equal default weights produces a mathematically exact RRF tie (`1/60 + 1/61` for both, same identity as `RRFTests.fusionMatchesHandComputedAtDefaultK`); asserts the winner flips when catalog order is reversed, proving the tie-break follows first-seen order and not id string or a fixed position. All other findings were "sound, not a bug."

    One dead-end worth noting for future tasks: an initial "migrate" fixture block containing "database" accidentally trigram-overlapped the "release" query test via the "ase" trigram (inside "datab-ase"), inflating a limit test's expected match count from 2 to 3. Fixed by rewording that one fixture block. Any future catalog additions to this fixture should re-verify trigram overlap with existing golden queries (I used a small python script computing character-trigram sets to check).

    Final verification: `swift test` run fresh from package root — 65 tests in 5 suites passed, 0 failures, 0 warnings (49 pre-existing + 16 new). Leaving task in `doing` for review per the implement skill's workflow.
  timestamp: 2026-07-03T21:30:02.526491+00:00
- actor: claude-code
  id: 01kwmycbsy8a0fwjp4nbetxykj
  text: 'Iteration 1: implement landed green in doing (65 tests passed / 0 failed across 5 suites, TDD red→green verified, double-check found a missing tie-break test which was added). Checkpoint committed at b29462b. Note: cosine signal returns 0.0 (not nil) since Signals.cosine is non-optional; .auto falls back to retrieval; .selection throws SelectionTierUnavailable. Proceeding to /review HEAD~1..HEAD.'
  timestamp: 2026-07-03T21:32:59.070853+00:00
- actor: claude-code
  id: 01kwmyzc1aqdpbm8yp9r5pppq4
  text: |-
    Fixed both review findings by extracting a single shared `DiagnosticRecorder` helper:

    - Created `Tests/FoundationModelsMetadataRegistryTests/TestSupport/DiagnosticRecorder.swift` — one top-level `final class DiagnosticRecorder: @unchecked Sendable` with an NSLock-protected `recorded: [MetadataDiagnostic]`, a `diagnostics` getter, and `record(_:)`. Added a doc comment stating the synchronization invariant explicitly: "`recorded` is only ever read (via `diagnostics`) or mutated (via `record(_:)`) while holding `lock`, which is what makes the `@unchecked Sendable` conformance safe" — this satisfies finding 1.
    - Deleted the nested `DiagnosticRecorder` class bodies from both `CatalogTests` (in CatalogTests.swift) and `RetrievalSearchTests` (in RetrievalSearchTests.swift) — satisfies finding 2 (root-caused the duplication rather than just adding the comment to one copy). Both structs' existing unqualified `DiagnosticRecorder()` call sites now resolve to the single shared type since both files already had `@testable import FoundationModelsMetadataRegistry` in scope.
    - SwiftPM's test target has no `sources`/`exclude` restriction, so the new `TestSupport/` subdirectory is auto-included — confirmed by a green build.

    Ran adversarial double-check (via really-done) against the diff. Verdict: REVISE with one minor finding — `RetrievalSearchTests.swift` still had `import Foundation` after its only Foundation user (the deleted nested class) was removed, an unused import. Fixed by removing that import line; confirmed via grep that no other Foundation API (NSLock, Date, URL, Data, Locale, TimeInterval) is used in that file. `CatalogTests.swift` still legitimately needs `Foundation`/`NSLock` for its separate `CallCounter` helper, so nothing to change there.

    Final verification: fresh `swift build` (exit 0, no errors) and fresh `swift test` — 65 tests in 5 suites passed, 0 failures, 0 warnings. Same test count as before (49 pre-existing + 16 in RetrievalSearchTests) since this consolidation removed a duplicate *type*, not any test cases. No production code touched — scope limited to the two test files plus the one new shared test-support file. Leaving task in `doing` for review per the implement skill's workflow.
  timestamp: 2026-07-03T21:43:21.898387+00:00
depends_on:
- 01KWMEBWC11D5XHXEJB6HW6325
position_column: done
position_ordinal: '8380'
title: MetadataSearcher actor with keyword-only .retrieval mode
---
## What\nImplement the searcher core per plan.md §3/§5/§7, in `Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift` + `SearchMode.swift`:\n- `enum SearchMode: Sendable { case retrieval, selection, auto }`\n- `actor MetadataSearcher<Item: SearchableMetadata>` holding a `MetadataIndex`, per-signal `Weights` config (bm25/trigram/cosine, default 1.0 each), and the **`onDiagnostic` callback** (the shared `MetadataDiagnostic` surface from the catalog task) threaded through to the index and later tiers\n- `search(intent: String, limit: Int) -> [Match<Item>]` for `.retrieval`: run BM25 (two fields) + trigram Dice rankings → `RRF.fuse(k: 60)` → `normalize` → map ids back through the catalog to `Match`es carrying verbatim blocks + per-signal `Signals`\n- No session, no tokens, no embedder yet — cosine slot simply absent (absent-signal rule: contributes nothing)\n- `.selection`/`.auto` stubs throw/fall back to retrieval until the selection tasks land\n\n## Acceptance Criteria\n- [x] Fixture query \\\"deploy\\\" ranks the `deploy` item first via id-field weighting even when its block never says \\\"deploy\\\"\n- [x] Returned `Match.score` in [0,1], `signals` populated with raw bm25/trigram values, cosine nil (`Signals.cosine` is a non-optional `Double` in this codebase's Hit.swift, so \\\"absent\\\" is represented as `0.0`, the same value that type documents for \\\"no embedding available\\\" — not a crash or special case)\n- [x] Zero-weight signal is excluded from fusion and from the normalization ceiling\n- [x] Searcher init accepts `onDiagnostic` and forwards index-build diagnostics through it\n\n## Tests\n- [x] `Tests/FoundationModelsMetadataRegistryTests/RetrievalSearchTests.swift` — golden rankings over a fixture catalog (~20 items), limit handling, empty-query and no-hits behavior, weights configuration, diagnostic forwarding\n- [x] Run `swift test` — all pass, no GPU/Router\n\n## Workflow\n- Use `/tdd` — write failing tests first, then implement to make them pass.\n\n## Review Findings (2026-07-03 16:33)\n\n- [x] `Tests/FoundationModelsMetadataRegistryTests/RetrievalSearchTests.swift:50` — @unchecked Sendable requires a documented synchronization invariant, but DiagnosticRecorder lacks a comment explaining the lock's role in protecting shared state. Add a comment documenting the synchronization invariant, e.g., add a line above the class declaration or after the lock property: '/// Synchronization: access to `recorded` is protected by `lock`.'.\n- [x] `Tests/FoundationModelsMetadataRegistryTests/RetrievalSearchTests.swift:52` — DiagnosticRecorder reimplements an existing test utility. The comment at lines 50–51 explicitly acknowledges that this class 'mirrors `CatalogTests.DiagnosticRecorder`', yet the identical implementation is maintained as a separate copy. This thread-safe recording helper should be extracted to a shared test utility and reused across test files rather than duplicated. Extract DiagnosticRecorder to a shared test utility file (e.g., Tests/Support/DiagnosticRecorderTestHelper.swift or Helpers/MetadataDiagnosticTestRecorder.swift) and import/reuse it in both CatalogTests.swift and RetrievalSearchTests.swift.\n