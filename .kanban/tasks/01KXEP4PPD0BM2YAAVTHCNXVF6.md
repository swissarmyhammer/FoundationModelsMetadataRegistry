---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01kxesx5b660q7jmmyeee2a0d8
  text: 'Picked up by /finish (scoped-batch, iteration 1). Fresh card, no prior attempts. Plan: /implement → /test → /commit checkpoint → /review HEAD~1..HEAD.'
  timestamp: 2026-07-13T22:35:01.862116+00:00
- actor: claude-code
  id: 01kxet02trrx500thebd9an5w2
  text: 'Started /implement. Verified card against reality: 7 ported files exist under Search/ and Embedding/, 3 redundant test suites exist, rename call sites confirmed in MetadataIndex.swift / MetadataSearcher.swift / CatalogTests.swift. Verified sibling RankKit checkout exports BM25.primaryFieldWeight=5.0 / BM25.bodyFieldWeight=1.0 and carries BM25Tests/TrigramTests/RRFTests. Plan: delete ported files (RED), add dep + @_exported reexport + renames (GREEN), swift test GPU-free.'
  timestamp: 2026-07-13T22:36:37.592047+00:00
- actor: claude-code
  id: 01kxethgmj0f4qg5p3capevsks
  text: |-
    Implementation complete and green; leaving in doing for /review per the finish pipeline.

    What changed:
    - Package.swift: added `rankKitPackage` named constant (matching the manifest's constant pattern), `.package(url: https://github.com/swissarmyhammer/RankKit, branch: main)`, and `.product(name: RankKit, package: RankKit)` on the main library target only.
    - Added Sources/FoundationModelsMetadataRegistry/RankKitReexport.swift with blanket `@_exported import RankKit` — NO scoped-reexport fallback needed, no ambiguity anywhere in Tests/ or Examples/.
    - Deleted the 7 ported files (Search/BM25|Trigram|Tokenizer|RRF|Hit.swift, Embedding/TextEmbedding|RoutedEmbedderAdapter.swift) and the 3 redundant suites (BM25Tests, TrigramTests, RRFTests).
    - Renamed idFieldWeight→primaryFieldWeight / blockFieldWeight→bodyFieldWeight in MetadataIndex.swift, MetadataSearcher.swift, CatalogTests.swift (code + doc comments). grep across Sources/Tests/Examples returns zero matches.
    - Package.resolved pins rankkit branch main rev 3f1ab08.

    TDD: RED observed (build failed "cannot find type 'Signals' in scope" after deletions), GREEN restored by dep+reexport+renames.

    Evidence: swift build exit 0; swift test (GPU-free, no METADATA_REGISTRY_INTEGRATION_TESTS) exit 0, 97 tests in 9 suites passed. The 3 build warnings (swift-jinja unused-dep x2, mlx bundle mutated-node) reproduce identically on clean HEAD — none introduced (verified via stash/build/pop).

    Double-check verdict: REVISE with one comment-only finding — my shim comment wrongly claimed local SelectionTier shadows RankKit's for clients (local one is `internal actor SelectionTier<Item>`, so clients actually resolve RankKit's public SelectionTier via the re-export). Applied the reviewer's suggested wording verbatim and re-ran swift test (97/97 green). Did not re-spawn double-check: fix was comment-only, exactly the reviewer's own suggestion, zero behavioral surface.

    Discovery worth noting for the future selection-tier migration task: because local SelectionTier is internal, RankKit's public (non-generic) SelectionTier actor is now newly visible API surface to package clients — documented in RankKitReexport.swift.
  timestamp: 2026-07-13T22:46:08.786180+00:00
position_column: doing
position_ordinal: '80'
title: 'Adopt RankKit: replace ported search primitives with the shared dependency'
---
## What

First step of the migration onto `swissarmyhammer/RankKit` (the extraction this repo's own plan.md decision #9 pre-authorized, and RankKit's plan.md §6a defers to this repo). Replace the byte-identical ported primitives with the RankKit dependency, keeping this package's public API stable via re-export. Later tasks (create via `/plan`) migrate `MetadataSearcher` onto `HybridRanker`/`RankedDocument`/`CosineScoring` and the selection tier onto RankKit's `Selection/` — do NOT touch those pipelines here beyond the mechanical renames below.

- **`Package.swift`**: add `.package(url: "https://github.com/swissarmyhammer/RankKit", branch: "main")` and `.product(name: "RankKit", package: "RankKit")` to the `FoundationModelsMetadataRegistry` library target's dependencies (RankKit itself depends on `FoundationModelsRouter` `main` — SwiftPM unifies with the existing pin; use the remote URL, not a path dep, per the manifest's own CI comment).
- **Create `Sources/FoundationModelsMetadataRegistry/RankKitReexport.swift`** containing `@_exported import RankKit`, so `RRF`, `BM25`, `BM25Corpus`, `Trigram`, `Tokenizer`, `Hit`, `Signals`, `TextEmbedding`, and `RoutedEmbedderAdapter` remain visible to this package's public API and its consumers unchanged (RankKit plan §4.4 explicitly keeps everything `public` to enable exactly this). **Name-collision caveat**: RankKit also exports `SelectionTier`, `SelectionConfig`, `Selection`, `AgentSession`, and `SelectionTierUnavailable`, which this module still declares locally until the later selection-tier migration. Module-local declarations shadow re-exported ones, and a re-exporting module's own declarations shadow the re-exported module's for clients — but if any use site in `Tests/` or `Examples/` still reports ambiguity, switch the shim to scoped re-exports of only the eight replaced names (`@_exported import enum RankKit.RRF`, `@_exported import enum RankKit.BM25`, `@_exported import struct RankKit.BM25Corpus`, `@_exported import enum RankKit.Trigram`, `@_exported import enum RankKit.Tokenizer`, `@_exported import struct RankKit.Hit`, `@_exported import struct RankKit.Signals`, `@_exported import protocol RankKit.TextEmbedding`, `@_exported import struct RankKit.RoutedEmbedderAdapter`) instead of the blanket import.
- **Delete the byte-identical ported copies** (RankKit is now the canonical home):
  - `Sources/FoundationModelsMetadataRegistry/Search/BM25.swift`, `Search/Trigram.swift`, `Search/Tokenizer.swift`, `Search/RRF.swift`, `Search/Hit.swift`
  - `Sources/FoundationModelsMetadataRegistry/Embedding/TextEmbedding.swift`, `Embedding/RoutedEmbedderAdapter.swift`
- **Rename the one API delta** — RankKit neutralized the BM25 field-weight names: `BM25.idFieldWeight` → `BM25.primaryFieldWeight`, `BM25.blockFieldWeight` → `BM25.bodyFieldWeight` at the call sites in `Sources/FoundationModelsMetadataRegistry/Catalog/MetadataIndex.swift` (weighted-term-frequency build), `Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift` (`computeTrigramRanking`), and `Tests/FoundationModelsMetadataRegistryTests/CatalogTests.swift` (weighted-tf expectations). Values are identical (5.0 / 1.0) — no behavior change.
- **Delete the redundant primitive test suites** RankKit already carries verbatim (`Tests/RankKitTests/BM25Tests.swift`, `TrigramTests.swift`, `RRFTests.swift`): `Tests/FoundationModelsMetadataRegistryTests/BM25Tests.swift`, `TrigramTests.swift`, `RRFTests.swift`. Keep `EmbeddingTests.swift` and everything else — the pipeline-level suites are this migration's no-behavior-change proof.

### Subtasks
- [x] Add the RankKit package + product dependency to `Package.swift`
- [x] Add `Sources/FoundationModelsMetadataRegistry/RankKitReexport.swift` with `@_exported import RankKit`
- [x] Delete the 7 ported source files under `Search/` and `Embedding/`
- [x] Rename `BM25.idFieldWeight`/`BM25.blockFieldWeight` call sites to `primaryFieldWeight`/`bodyFieldWeight` in `MetadataIndex.swift`, `MetadataSearcher.swift`, `CatalogTests.swift`
- [x] Delete redundant `BM25Tests.swift`/`TrigramTests.swift`/`RRFTests.swift` and run the full suite

## Acceptance Criteria
- [x] `swift build` succeeds with RankKit resolved from `https://github.com/swissarmyhammer/RankKit` (branch `main`)
- [x] `Sources/FoundationModelsMetadataRegistry/Search/` and `Sources/FoundationModelsMetadataRegistry/Embedding/` no longer exist; `RRF`, `BM25`, `Trigram`, `Tokenizer`, `Hit`, `Signals`, `TextEmbedding`, `RoutedEmbedderAdapter` resolve from RankKit via the `@_exported` re-export
- [x] `grep -r "idFieldWeight\|blockFieldWeight" Sources Tests Examples` returns no matches
- [x] Public API unchanged for consumers: `Examples/` cores (`CatalogSearchCore`, `SemanticSearchCore`, `BigCatalogCore`, `HotReloadCore`, `LibrarianCore`) compile with zero source changes
- [x] Every remaining test passes (`RetrievalSearchTests`, `CatalogTests`, `EmbeddingTests`, `SelectionTests`, `OverBudgetTests`, `HotReloadTests`, `AgentSessionTests`, `ExamplesSmokeTests`, `PackageTests`) — these are the no-behavior-change proof

## Tests
- [x] Update `Tests/FoundationModelsMetadataRegistryTests/CatalogTests.swift` weighted-term-frequency expectations to the renamed `BM25.primaryFieldWeight`/`BM25.bodyFieldWeight` constants (same values, so assertions still prove the ×5/×1 weighting)
- [x] No new tests required beyond that: the existing pipeline suites (`RetrievalSearchTests.swift`, `EmbeddingTests.swift`, `HotReloadTests.swift`, `SelectionTests.swift`, `OverBudgetTests.swift`, `ExamplesSmokeTests.swift`) exercise every re-exported primitive end-to-end and must pass unchanged
- [x] `swift test` (GPU-free default path, no `METADATA_REGISTRY_INTEGRATION_TESTS`) exits 0 with all suites green

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. (Here the RED step is the compile/test failure after deleting the ported files; GREEN is the dependency + re-export restoring the suite.)