---
comments:
- actor: claude-code
  id: 01kwpgy1b4c7va8kr6340pnfn1
  text: 'Picked up by /finish scoped-batch loop (task 9 of batch; ^ze57a3j skipped as stuck on a review-rule contradiction). Plan: /implement → /test → /commit checkpoint → /review HEAD~1..HEAD.'
  timestamp: 2026-07-04T12:16:26.980737+00:00
- actor: claude-code
  id: 01kwphmwmmg2rb12584aaxr6am
  text: |-
    Discovery: on this toolchain (Xcode-beta, Swift 6.4/macOS 27 SDK beta), having the XCTest/Swift-Testing test target `@testable import` an *executable* target (CatalogSearch/SemanticSearch) that calls into the FoundationModelsMetadataRegistry library with a generic `Item: SearchableMetadata` causes a SIGSEGV inside `MetadataIndex.init(items:onDiagnostic:)` (bad array-buffer access) when invoked through the test harness -- even though `swift run CatalogSearch` itself works perfectly and prints correct output. Crash reproduces even for the simplest CatalogSearch-only test. This looks like a toolchain-level bug/limitation in SwiftPM's special "-testable" recompilation of executable targets (visible in the build log as `CatalogSearch-<hash>-testable-t.build`), not a bug in our code.

    Fix: restructured so the testable entry logic lives in plain *library* targets (`CatalogSearchCore`, `SemanticSearchCore`) that both the thin `main.swift` executables and the test target depend on normally -- sidestepping the buggy executable-testable-import path entirely. main.swift files stay thin, calling straight into their Core target. Test file now does `@testable import CatalogSearchCore` / `@testable import SemanticSearchCore`. Re-verifying this resolves the crash next.
  timestamp: 2026-07-04T12:28:55.828047+00:00
- actor: claude-code
  id: 01kwpjenys98y77k54am8em8z8
  text: |-
    Implementation complete and green. Summary:

    **Package.swift**: added `CatalogSearchCore` (library) + `CatalogSearch` (executable), and `SemanticSearchCore` (library) + `SemanticSearch` (executable) targets. New remote dependencies: mlx-swift-lm (same URL/branch as FoundationModelsRouter, unified by SwiftPM), swift-huggingface, swift-transformers -- needed only by SemanticSearchCore's live-Router path (mirrors FoundationModelsRouter's own Examples/MultiModelGeneration). The main library target is unchanged and still never depends on the examples.

    **CatalogSearch** (Examples/CatalogSearch/main.swift + Examples/CatalogSearchCore/CatalogSearchCore.swift): 5-item git-subcommand fixture, keyword-only `MetadataSearcher(mode: .retrieval)`, one query ("commit changes to git"), prints ranked Matches with per-signal Signals. `swift run CatalogSearch` verified: exit 0, `commit` ranks first with real bm25/trigram scores, cosine=0.0 (no embedder).

    **SemanticSearch** (Examples/SemanticSearch/main.swift + Examples/SemanticSearchCore/SemanticSearchCore.swift): same fixture plus a `status` item, default path resolves a live Router + RoutedEmbedderAdapter (network/GPU, compiles but not exercised in tests, per plan.md §13 "compile in CI, run locally"); `--no-embedder` flag builds keyword-only and prints the `.embeddingUnavailable` diagnostic. `swift run SemanticSearch --no-embedder` verified: exit 0, prints diagnostic + `status` ranked (not `commit` -- the degradation is "ranks the wrong thing," not "finds nothing," which required adding the `status` fixture item after the first double-check pass caught the original fixture yielding an empty, vacuously-testable result set).

    **Tests** (Tests/FoundationModelsMetadataRegistryTests/ExamplesSmokeTests.swift): 4 new tests importing `CatalogSearchCore`/`SemanticSearchCore` directly (no `swift run` subprocess). `swift test`: 110/110 passing (106 baseline + 4 new).

    **Toolchain discovery** (see earlier comment): test target `@testable import`-ing an *executable* target directly SIGSEGVs on this toolchain (Xcode-beta/Swift 6.4/macOS 27 SDK beta) inside `MetadataIndex.init`, even though `swift run` of the same executable works fine. Fixed by factoring all testable logic into plain library targets (`*Core`) that both the thin `main.swift` and the test target depend on normally, avoiding SwiftPM's special "-testable executable" build path entirely.

    Two double-check passes run: first caught the vacuous "empty results" degradation demo, fixed by adding the `status` fixture item and tightening assertions; second pass verified the fix independently (re-ran `swift test` and both `swift run` commands) and returned PASS.

    Verification commands run fresh at handoff: `swift build` (exit 0, no warnings besides a pre-existing unrelated mlx-swift bundle warning), `swift test` (110/110 passed), `swift run CatalogSearch` (exit 0), `swift run SemanticSearch --no-embedder` (exit 0). Leaving in `doing` for review per the implement workflow.
  timestamp: 2026-07-04T12:43:00.953897+00:00
depends_on:
- 01KWMECNX02RYW074R5DFHQ4EA
position_column: doing
position_ordinal: '80'
title: 'Examples: CatalogSearch and SemanticSearch executables'
---
## What
Build the first two `Examples/` executable targets per plan.md §13 (M8), added to `Package.swift` as executable targets depending on the library (demos only — the library never depends on them):
- `Examples/CatalogSearch/main.swift` — the ~30-line hello world: a handful of fixture items conforming to `SearchableMetadata`, keyword-only `MetadataSearcher(mode: .retrieval)` (no embedder, no model), one query, printed `Match`es with per-signal `Signals`. Runs anywhere, GPU-free.
- `Examples/SemanticSearch/main.swift` — CatalogSearch plus `RoutedEmbedderAdapter`: a paraphrased query ("save my work" → `commit`) ranks where keywords miss; `--no-embedder` flag demonstrates keyword-only degradation and prints its diagnostic.

Implementation note: each example's entry logic is factored into a plain library target (`CatalogSearchCore`, `SemanticSearchCore`) that the thin `main.swift` and the test target both depend on, instead of the test target `@testable import`-ing the executable target directly — the latter reproducibly SIGSEGVs inside `MetadataIndex.init` under `swift test` on this toolchain (Xcode-beta/Swift 6.4/macOS 27 SDK beta), even though `swift run` of the executable itself works fine. See task comments for details.

## Acceptance Criteria
- [x] `swift run CatalogSearch` prints ranked matches with signals, exit 0, no model downloads
- [x] `swift run SemanticSearch --no-embedder` prints the degradation diagnostic and keyword-only results, exit 0, GPU-free
- [x] Both targets compile as part of `swift build` (CI keeps them compiling)

## Tests
- [x] `Tests/FoundationModelsMetadataRegistryTests/ExamplesSmokeTests.swift` — invoke the example entry logic (factored into a callable function per example) and assert on its output for the GPU-free paths
- [x] Run `swift build && swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.