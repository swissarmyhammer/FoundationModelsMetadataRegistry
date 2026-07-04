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
- actor: claude-code
  id: 01kwpjq31afetk7677xf1cj60a
  text: 'Iteration 1: implement landed green in doing (110 tests passed / 0 failed across 10 suites, TDD red→green verified, swift run of both executables confirmed exit 0 with correct output). Checkpoint committed at 09e8aa9. Discovery: @testable import of an executable target SIGSEGVs on this Xcode-beta/Swift 6.4/macOS 27 SDK toolchain — worked around with the *Core library-target pattern (CatalogSearchCore/SemanticSearchCore), which is good practice regardless of the bug. Added mlx-swift-lm/swift-huggingface/swift-transformers deps for SemanticSearchCore''s live-Router path. Proceeding to /review HEAD~1..HEAD.'
  timestamp: 2026-07-04T12:47:36.490204+00:00
- actor: claude-code
  id: 01kwpkqvjxczskksmpwte53ndc
  text: |-
    Fixed all 5 review-findings duplication items. Root cause: `GitCommand`, the 5-item fixture prefix, and `formatMatches` were verbatim-duplicated between CatalogSearchCore.swift and SemanticSearchCore.swift.

    Fix: added a new shared SwiftPM library target `ExamplesSupport` (Examples/ExamplesSupport/ExamplesSupport.swift) holding the single source of truth for:
    - `GitCommand: SearchableMetadata` (the fixture type)
    - `baseGitCommands: [GitCommand]` (the 5-item common prefix: commit/push/pull/branch/stash)
    - `formatMatches(_:)` (the per-signal match formatter)

    `CatalogSearchCore.gitCommands` is now just `baseGitCommands`. `SemanticSearchCore.gitCommands` is `baseGitCommands + [status item]`, preserving its 6th-item divergence locally as intended. Both `*Core` targets, both executable targets (CatalogSearch/SemanticSearch main.swift), and the test target now depend on/import `ExamplesSupport`; Package.swift wires all four new dependency edges. ExamplesSmokeTests.swift now calls `ExamplesSupport.formatMatches(...)`.

    Adversarial double-check (round 1) caught a real gap: main.swift files imported ExamplesSupport directly but the executableTarget entries in Package.swift didn't declare it as a dependency (relying on SwiftPM's shared-module-search-path leniency rather than the declared graph) -- would break under `--explicit-target-dependency-import-check=error`. Fixed by adding `.target(name: "ExamplesSupport")` to both executableTargets' dependencies. Round 2 double-check independently re-ran `swift build --explicit-target-dependency-import-check=error` (confirmed clean) plus the full verification suite and returned PASS.

    Verification, all run fresh after the fix: `swift build` exit 0; `swift build --explicit-target-dependency-import-check=error` exit 0 (strict check, no undeclared imports); `swift test` -- Test run with 110 tests in 10 suites passed, 0 failures; `swift run CatalogSearch` exit 0, commit ranks first with real bm25/trigram/cosine=0 scores; `swift run SemanticSearch --no-embedder` exit 0, prints embeddingUnavailable diagnostic, status ranks first. No remaining duplicate of GitCommand/formatMatches anywhere in the tree (grep-verified). Leaving in `doing` for review per the implement workflow.
  timestamp: 2026-07-04T13:05:30.205288+00:00
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

## Review Findings (2026-07-04 07:47)

- [x] `Examples/CatalogSearchCore/CatalogSearchCore.swift:19` — GitCommand struct is verbatim-duplicated across both example cores, creating maintenance burden when the type needs to evolve. Extract GitCommand to a shared location (e.g., ExamplesShared or add it to the main library) and import it in both core targets, or merge the two example cores into one parametrized example.
- [x] `Examples/CatalogSearchCore/CatalogSearchCore.swift:32` — The first 5 gitCommands entries are verbatim-duplicated in SemanticSearchCore, diverging only at SemanticSearchCore's 6th item (status). Extract the common 5-item base array to a shared constant in one place, then SemanticSearchCore can extend or override it locally if the 6th item is example-specific.
- [x] `Examples/CatalogSearchCore/CatalogSearchCore.swift:67` — formatMatches function is verbatim-duplicated across both example cores; every line and format string is identical. Move formatMatches to a shared module (ExamplesShared, or the main library) and import it in both cores; the function has no example-specific logic and should not be copied.
- [x] `Examples/SemanticSearchCore/SemanticSearchCore.swift:24` — GitCommand struct is verbatim-duplicated from CatalogSearchCore; both are identical public types with the same conformance and members. Extract GitCommand to a shared location and import it in both cores to avoid maintaining two copies.
- [x] `Examples/SemanticSearchCore/SemanticSearchCore.swift:97` — formatMatches function is verbatim-duplicated from CatalogSearchCore; the implementation and all format strings are identical. Move formatMatches to a shared module and import it in both cores; keeping it 'local' for independence is outweighed by the maintenance cost of identical code in two places.
