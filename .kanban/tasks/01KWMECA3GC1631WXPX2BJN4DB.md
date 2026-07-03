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
depends_on:
- 01KWMEBWC11D5XHXEJB6HW6325
position_column: doing
position_ordinal: '80'
title: MetadataSearcher actor with keyword-only .retrieval mode
---
## What
Implement the searcher core per plan.md §3/§5/§7, in `Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift` + `SearchMode.swift`:
- `enum SearchMode: Sendable { case retrieval, selection, auto }`
- `actor MetadataSearcher<Item: SearchableMetadata>` holding a `MetadataIndex`, per-signal `Weights` config (bm25/trigram/cosine, default 1.0 each), and the **`onDiagnostic` callback** (the shared `MetadataDiagnostic` surface from the catalog task) threaded through to the index and later tiers
- `search(intent: String, limit: Int) -> [Match<Item>]` for `.retrieval`: run BM25 (two fields) + trigram Dice rankings → `RRF.fuse(k: 60)` → `normalize` → map ids back through the catalog to `Match`es carrying verbatim blocks + per-signal `Signals`
- No session, no tokens, no embedder yet — cosine slot simply absent (absent-signal rule: contributes nothing)
- `.selection`/`.auto` stubs throw/fall back to retrieval until the selection tasks land

## Acceptance Criteria
- [x] Fixture query "deploy" ranks the `deploy` item first via id-field weighting even when its block never says "deploy"
- [x] Returned `Match.score` in [0,1], `signals` populated with raw bm25/trigram values, cosine nil (`Signals.cosine` is a non-optional `Double` in this codebase's Hit.swift, so "absent" is represented as `0.0`, the same value that type documents for "no embedding available" — not a crash or special case)
- [x] Zero-weight signal is excluded from fusion and from the normalization ceiling
- [x] Searcher init accepts `onDiagnostic` and forwards index-build diagnostics through it

## Tests
- [x] `Tests/FoundationModelsMetadataRegistryTests/RetrievalSearchTests.swift` — golden rankings over a fixture catalog (~20 items), limit handling, empty-query and no-hits behavior, weights configuration, diagnostic forwarding
- [x] Run `swift test` — all pass, no GPU/Router

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.