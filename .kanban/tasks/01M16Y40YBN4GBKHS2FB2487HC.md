---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m176g3h2ev6b8p88z1h9c17s
  text: |-
    Research done.

    Verified before deleting: `grep -r LiveRouterSupport` finds it only in `Package.swift` (4 doc-comment mentions + the target declaration) and in `plan.md` (2 historical mentions). No Swift source imports it any more — the two preceding tasks removed every import. `Examples/LiveRouterSupport/LiveRouterSupport.swift` is the sole file that imports `FoundationModelsRouter`, `MLXHuggingFace`, `MLXLMCommon`, `HuggingFace`, or `Tokenizers` anywhere under `Examples/`.

    `IntegrationTests/Package.swift` restates the MLX + Hugging Face products in its OWN manifest and consumes only the `FoundationModelsMetadataRegistry` and `SemanticSearchCore` products of the root package. Both products stay, so this change cannot break it. Will verify with `swift build --package-path IntegrationTests`.

    Manifest prose this change falsifies, and which therefore must move with it:
    - `examplesSupportName`'s doc names `liveRouterCoreDependencies`, a constant this change deletes.
    - The test target's `Jinja` comment claims Jinja is "already linked transitively via `Tokenizers` (through the `*Core` targets above)". After this change no `*Core` target links `Tokenizers`, so the direct `.product(name: "Jinja", …)` entry becomes the only thing keeping the swift-jinja pin used.
    - `mlxPackage` / `huggingFacePackage` / `transformersPackage` docs each claim `SemanticSearchCore` imports or links them. Not true after this change. The dependency ENTRIES stay (task ^3aeakq4 owns them); only the sentence that names a deleted wiring is corrected.
  timestamp: 2026-08-29T16:43:57.346949+00:00
- actor: claude-code
  id: 01m178dtbtcypbayveqmmjnkf9
  text: |-
    Implementation landed.

    TDD: wrote `Tests/FoundationModelsMetadataRegistryTests/PackageManifestTests.swift` first and watched it fail for the right reason — `found: ["HuggingFace", "MLXHuggingFace", "MLXLMCommon", "Tokenizers"]`. The test regex-scans every `.product(name: "…")` entry in `Package.swift` and asserts the set is disjoint from those four, rather than substring-matching the bare names: `MLXHuggingFace` still appears in the manifest's prose, so a bare `contains` would have pinned the comments instead of the wiring. Its doc records the one hole — a product named behind a manifest constant is invisible to a text read, and `swift build` is the backstop there.

    Manifest, beyond the four deletions the card names: `exampleCoreTarget(name:)` was rewritten to the GPU-free shape rather than deleted outright, and all five cores now go through it, `CatalogSearchCore` included — that is the "one new helper so the five declarations stay a single source of truth" the card asked to consider.

    Discovery worth recording: rewriting `exampleCoreTarget` made its body byte-identical to `exampleExecutableTarget`'s except for one identifier in the dependency array — duplication this change would have introduced. Extracted `exampleDependencies(on:)`, which both now call. The two helpers still differ in the SwiftPM factory they call (`.target` vs `.executableTarget`); that is a real difference in build product, not a substituted literal, so they stay two functions.

    Also corrected the manifest prose this change falsified, since a manifest that describes deleted wiring misleads the next reader: the `examplesSupportName` doc (named the deleted `liveRouterCoreDependencies`), the `SemanticSearchCore` and `HotReloadCore` target comments (claimed an MLX link and a `METADATA_REGISTRY_INTEGRATION_TESTS` real-model path that no source has read since the preceding task), the `Jinja` comment (claimed transitive linkage via `Tokenizers`), the package doc comment, and the `mlxPackage`/`huggingFacePackage`/`transformersPackage` docs. The `dependencies:` ENTRIES themselves are untouched — ^3aeakq4 owns those.

    Verification:
    - `rm -rf .build/out && swift build` — Build complete, exit 0. One expected warning: `dependency 'foundationmodelsrouter' is not used by any target`. That is the warning ^3aeakq4 clears; SwiftPM does not report mlx-swift-lm / swift-huggingface / swift-transformers unused, because FoundationModelsRanker still reaches them transitively.
    - `swift test` — 110 tests in 10 suites pass (was 109 in 9; this card adds one suite of one test). Three consecutive clean full-suite runs at 0.300s / 0.300s / 0.305s on a quiet machine.
    - One intermediate run failed on `ExamplesSmokeTests`' `result.elapsed < 5.0` at 5.412s. That is ^b8sg2pk, load-sensitive and pre-existing: the same code measured 0.282s in the first run of this session and 0.30s in each of the three confirming runs. The threshold was NOT raised.
    - `swift run` CatalogSearch / SemanticSearch / Librarian / BigCatalog / HotReload — all exit 0.
    - `swift build --package-path IntegrationTests --build-tests` — Build complete. The nested package restates the MLX and Hugging Face products in its own manifest and consumes only the `FoundationModelsMetadataRegistry` and `SemanticSearchCore` products, both of which survive.
    - `Examples/LiveRouterSupport/` gone (`git rm -r`); `grep -c` for the four product names in `Package.swift` returns 0.
  timestamp: 2026-08-29T17:17:39.578115+00:00
- actor: claude-code
  id: 01m178dz3a3bmfcryje72f6rjv
  text: |-
    ### implement — changed
    - evidence: 3 files. Deleted: Examples/LiveRouterSupport/LiveRouterSupport.swift (and its directory). New: Tests/FoundationModelsMetadataRegistryTests/PackageManifestTests.swift. Changed: Package.swift. `rm -rf .build/out && swift build` clean (1 expected warning, `foundationmodelsrouter` unused, owned by ^3aeakq4). `swift test` = 110 tests in 10 suites, 3 consecutive clean runs at 0.300s/0.300s/0.305s. All 5 `swift run` demos exit 0. `swift build --package-path IntegrationTests --build-tests` Build complete.
    - next: /review
  timestamp: 2026-08-29T17:17:44.426140+00:00
depends_on:
- 01M16Y37AEYBQ1JEY02X0QR1AP
- 01M16Y3MC3EPK5PMPGHMJP69RX
position_column: doing
position_ordinal: '80'
title: Delete the LiveRouterSupport target
---
## What

`Examples/LiveRouterSupport/` exists only to resolve a live `Router` + `LiveModelLoader` for the four demo cores. After the two preceding tasks, nothing imports it. Delete it and the manifest scaffolding that carries the Router, MLX, and Hugging Face products into the demo targets.

Files to change:
- `Examples/LiveRouterSupport/LiveRouterSupport.swift` — delete the file and its directory (128 lines).
- `Package.swift` — delete:
  - the `LiveRouterSupport` target (line 287-291),
  - `liveRouterProductDependencies` (line 99-105),
  - `liveRouterCoreDependencies` (line 116-120),
  - the `exampleCoreTarget(name:)` helper (line 165-171), because every demo core now has the same GPU-free shape as `CatalogSearchCore`.
- `Package.swift` — declare `SemanticSearchCore`, `LibrarianCore`, `BigCatalogCore`, and `HotReloadCore` the same way `CatalogSearchCore` is declared: `.target(name: packageName)` plus `.target(name: examplesSupportName)` only. Consider one new helper that builds that shape, so the five declarations stay a single source of truth.

Do not touch the package-level dependency entries yet. A later task removes them.

## Acceptance Criteria

- [x] `Examples/LiveRouterSupport/` does not exist.
- [x] No target in `Package.swift` names `MLXHuggingFace`, `MLXLMCommon`, `HuggingFace`, or `Tokenizers`.
- [x] Every `Examples/*Core` target depends only on the main library target and `ExamplesSupport`.
- [x] `swift build` completes with no error.

## Tests

- [x] Run `swift test`. All tests pass, including the `ExamplesSmokeTests` added by the two preceding tasks.
- [x] Run `swift run CatalogSearch`, `swift run SemanticSearch`, `swift run Librarian`, `swift run BigCatalog`, and `swift run HotReload`. Each exits 0.
- [x] Add a test in `Tests/FoundationModelsMetadataRegistryTests/PackageManifestTests.swift` (new file) that reads `Package.swift` and asserts it contains no `MLXHuggingFace`, `MLXLMCommon`, `HuggingFace`, or `Tokenizers` product entry. Model it on `CIWorkflowTests.swift`'s `#filePath`-relative file read.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.