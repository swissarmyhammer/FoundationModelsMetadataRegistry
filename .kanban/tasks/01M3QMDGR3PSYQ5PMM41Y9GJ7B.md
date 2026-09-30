---
comments:
- actor: claude-code
  id: 01m3seyvs98bq8jr58zw9n78q4
  text: |-
    Research done.
    - `swift package update`: Ranker 39e3717, Extras c5ca65a. Ranker gives `extension PooledEmbedder: TextEmbedding`. Ranker does not re-export FoundationModelsExtras, so a consumer that names `PooledEmbedder` must `import FoundationModelsExtras`.
    - Only the async `init(items:mode:weights:embedder:selection:onDiagnostic:)` takes `embedder:` with `items:`. Swift lets a sync init and an async init have the same labels. In an async context the compiler picks the async one, so the unit tests call the sync one from a sync helper.
    - `PooledEmbedder(ref:pool:)` loads nothing. Its first `embed(texts:)` acquires the key from the pool. Two embedders with one ref in one pool give one load and one resident model.
    - The IntegrationTests package names only the root product. The real-model test names `PooledEmbedder`, so that package must also depend on the FoundationModelsExtras product.
    - The glob that Extras CI uses is `"*Cmlx*/default.metallib"`. Extras `MLXModelLoader` also installs its own metallib link.
    - The Examples package uses `PooledTextEmbedding` and `embeddingModel:` (HotReload, SemanticSearch, CoalescedBurst). CI does not build Examples. The dispatcher said that Examples can stay as they are. Tasks ^581h9qqtzy and ^fq09vqq will move them.
  timestamp: 2026-09-30T15:29:32.969574+00:00
- actor: claude-code
  id: 01m3sfmckb9yfk3je113nx6j30
  text: |-
    Implementation landed (not committed, not pushed).
    - RED: `PooledEmbedderSearchTests` did not compile ("'async' call in a function that does not support concurrency"), because only the async `init(items:...embedder:...)` existed. `CIWorkflowTests.namesTheMLXMetallib` failed before the ci.yml edit.
    - GREEN: a sync `init(items:mode:weights:embedder:selection:onDiagnostic:)` builds `MetadataIndex(items:)` and sends the embedder to the first-search catch-up. The keyword-only `init(items:...)` now forwards to it with `embedder: nil`. `PooledTextEmbedding.swift`, the `embeddingModel:` init, `PooledTextEmbeddingTests.swift` and `TestSupport/PooledModelStubs.swift` are deleted. `MetadataSearcher.swift` does not import FoundationModelsExtras now.
    - Overload trap (measured with swiftc): in an async context the compiler selects the async overload. Without `await` that is a compile error. Thus the unit test and the real-model test call the sync init from a sync static helper. The README example uses `await` and tells which overload does what.
    - `IntegrationTests/Package.swift` now depends on the FoundationModelsExtras core product (same URL as the root), because the root library does not re-export `PooledEmbedder`.
    - A `@Suite(.timeLimit(.minutes(Self.member)))` trait gave "circular reference resolving attached macro 'Suite'". A file-level constant corrects it.
    - The SwiftPM warning "missing creator for mutated node ... mlx-swift_Cmlx.bundle" comes from the mlx-swift dependency. It was there before this change (the Ranker board records the same warning). No warning comes from a file of this repository.
    - The Examples package does not compile now (HotReload, SemanticSearch, CoalescedBurst use the deleted API). CI does not build Examples. ^581h9qqtzy moves them.
    - Open: the acceptance item "CI green on the pushed commit" needs a push. This step does not push.
  timestamp: 2026-09-30T15:41:18.315744+00:00
- actor: claude-code
  id: 01m3sfmm20zzkv95k8ktjwbm14
  text: |-
    ### implement — changed
    - evidence: 13 files. Changed: Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift, .github/workflows/ci.yml, Tests/FoundationModelsMetadataRegistryTests/CIWorkflowTests.swift, Tests/FoundationModelsMetadataRegistryTests/PackageManifestTests.swift (doc only), IntegrationTests/Package.swift, IntegrationTests/Tests/FoundationModelsMetadataRegistryIntegrationTests/HotReloadRealModelTests.swift (doc only), IntegrationTests/Tests/FoundationModelsMetadataRegistryIntegrationTests/Support/SelectionScenario.swift (doc only), README.md, plan.md. Added: Tests/FoundationModelsMetadataRegistryTests/PooledEmbedderSearchTests.swift, IntegrationTests/Tests/FoundationModelsMetadataRegistryIntegrationTests/PooledEmbedderRealModelTests.swift. Deleted: Sources/FoundationModelsMetadataRegistry/PooledTextEmbedding.swift, Tests/FoundationModelsMetadataRegistryTests/PooledTextEmbeddingTests.swift, Tests/FoundationModelsMetadataRegistryTests/TestSupport/PooledModelStubs.swift. `swift test`: 180 tests in 22 suites passed, 0 issues. `swift test --package-path IntegrationTests`: 6 tests in 5 suites passed (the real Qwen3 embedding test passed in 3.6 s). The one build warning comes from the mlx-swift dependency.
    - next: /review. After commit and push, check that CI (unit and integration jobs) is green.
  timestamp: 2026-09-30T15:41:25.952957+00:00
- actor: claude-code
  id: 01m3sfphpadtzeg5ywd8fvw0mm
  text: |-
    ### finish iteration 1 — implement: changed; requirement added before review
    - implement: changed — 14 files (PooledTextEmbedding, the embeddingModel initializer, PooledTextEmbeddingTests, PooledModelStubs deleted; new sync init; ci.yml metallib glob + CIWorkflowTests; IntegrationTests depends on Extras; README/plan.md). Root swift test 180/22 suites passed; IntegrationTests 6/5 suites passed incl. the real Qwen3 embedding test.
    - plan-author decision: the new sync init and the old async init have the same labels, so async code can only reach the async one. Requirement added to the task: one synchronous initializer with `embedder:`; delete the async one; callers drop `await`.
    - next: implement (continued) for that requirement, then test, commit, review
  timestamp: 2026-09-30T15:42:29.066913+00:00
- actor: claude-code
  id: 01m3sfshp6g4bxs0nr7tzhyp8f
  text: |-
    Iteration 2 picked up: the new requirement is one synchronous `embedder:` initializer. Research:
    - The only async initializer in Sources is `MetadataSearcher.init(items:mode:weights:embedder:selection:onDiagnostic:) async`. It calls `MetadataIndex.build(items:embedder:onDiagnostic:)`. `MetadataIndex.build` is a public static function, not an initializer, and tests use it with `init(index:...)`. It stays.
    - Callers with `await MetadataSearcher(`: HotReloadTests (6), RegistryTracingTests (4), EmbeddingTests (3), RegistryMetricsTests (2), HotReloadBurstTests (2), TelemetryContentSafetyTests (2), HotReloadCoalescingTests (1), SearchableMetadataTextsTests (1), README.md (1), plan.md (1).
    - The sync-helper workaround is `makeSearcher(pool:)` in PooledEmbedderSearchTests and `makeSearcher()` in PooledEmbedderRealModelTests.
  timestamp: 2026-09-30T15:44:07.366749+00:00
- actor: claude-code
  id: 01m3sgd547460ec9sgn8er9tj4
  text: |-
    Iteration 2 landed (not committed, not pushed).
    - RED: `PooledEmbedderSearchTests.synchronousInitLoadsNothingAndTheFirstSearchRanksByCosine` now calls `MetadataSearcher(items:embedder:)` with no `await` in an async test body. It did not compile ("actor-isolated initializer ... cannot be called from outside of the actor"), because the compiler selected the async overload.
    - GREEN: deleted `init(items:mode:weights:embedder:selection:onDiagnostic:) async`. It was the only async initializer in Sources. `MetadataIndex.build(items:embedder:previous:onDiagnostic:)` is a public static function, not an initializer; it stays.
    - Interpretation: `init(index:...embedder:...)` also takes `embedder:`. It is synchronous and is the existing seam the requirement names, so it stays. The one initializer with `items` and `embedder:` is the sync one.
    - Removed the sync-helper workaround: `makeSearcher(pool:)` in PooledEmbedderSearchTests and `makeSearcher()` in PooledEmbedderRealModelTests. The tests now call the initializer directly in async code.
    - Tests that need an embedded catalog before a step now use `MetadataIndex.build` + `init(index:embedder:)` (the pattern HotReloadTests already used): HotReloadTests (re-embed counts x2, redundant update + root session, redundant update no diagnostic, embedCatchUp pending 1 of 2), SearchableMetadataTextsTests (block-only update), RegistryTracingTests (update span pending 1; identical update pending 0) and RegistryMetricsTests (identical update records no size) through the new `RegistryTracingTests.makeEmbeddedSearcher()`. Each assertion is unchanged. No test was deleted.
    - Tests with an empty first catalog or that search first only lost the `await`.
    - Doc comments updated in MetadataSearcher.swift and MetadataSearcher+FirstSearchCatchUp.swift. README and plan.md (§8 item 6, §12) updated.
    - Note: `replace_all` of the files tool replaced only the first match in each file; the other sites were edited one by one.
  timestamp: 2026-09-30T15:54:49.863091+00:00
- actor: claude-code
  id: 01m3sgdb3dsr109c98cmpet2x8
  text: |-
    ### implement — changed
    - evidence: iteration 2 changed 14 files: Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift, Sources/FoundationModelsMetadataRegistry/MetadataSearcher+FirstSearchCatchUp.swift, Tests/FoundationModelsMetadataRegistryTests/{PooledEmbedderSearchTests,EmbeddingTests,HotReloadTests,HotReloadBurstTests,HotReloadCoalescingTests,RegistryMetricsTests,RegistryTracingTests,SearchableMetadataTextsTests,TelemetryContentSafetyTests}.swift, IntegrationTests/Tests/FoundationModelsMetadataRegistryIntegrationTests/PooledEmbedderRealModelTests.swift, README.md, plan.md. `swift test`: 180 tests in 22 suites passed, 0 issues. `swift test --package-path IntegrationTests`: 6 tests in 5 suites passed. The one build warning ("missing creator for mutated node ... mlx-swift_Cmlx.bundle") comes from the mlx-swift dependency. `grep -rn "await MetadataSearcher(" Sources Tests IntegrationTests README.md plan.md`: no match (exit 1).
    - next: /review. After commit and push, check that CI (unit and integration jobs) is green; that acceptance item is still open.
  timestamp: 2026-09-30T15:54:55.981215+00:00
depends_on:
- 01M3QMDGD8148YNDHWBB1YXAQ1
position_column: doing
position_ordinal: '80'
title: Take PooledEmbedder directly; delete PooledTextEmbedding and the embeddingModel initializer
---
**Wait for:** FoundationModelsRanker task 01M3QMDA82DXPZNEASMVXTP31M ("Depend on Extras; PooledSession is an AgentSession and PooledEmbedder is a TextEmbedding") on the Ranker board: done and pushed.

## What
```swift
let searcher = MetadataSearcher(items: catalog,
                                embedder: PooledEmbedder(ref: "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ"))
// sync init; the first search embeds the catalog (existing catch-up path)
```

- `swift package update`, confirm the new Ranker and Extras revisions.
- Delete `Sources/FoundationModelsMetadataRegistry/PooledTextEmbedding.swift` and `MetadataSearcher.init(items:mode:weights:embeddingModel:footprintBytes:loader:pool:selection:onDiagnostic:)` (`MetadataSearcher.swift` ~line 253).
- A synchronous `MetadataSearcher(items:mode:weights:embedder:selection:onDiagnostic:)` embeds at the first search (`MetadataSearcher+FirstSearchCatchUp.swift`). If only the async init takes `embedder:`, add the synchronous one.
- Delete `Tests/.../PooledTextEmbeddingTests.swift` and `TestSupport/PooledModelStubs.swift`; new tests use `PooledEmbedder(ref: "…", pool: ModelPool(loader: fake))`.
- `.github/workflows/ci.yml` and `Tests/.../CIWorkflowTests.swift`: MLX is now in the graph through Extras; give the shared workflow `integration-metallib-glob` for the real-model test; update the workflow comment and the test that pins "no MLX".
- `README.md`: the `init(items:embeddingModel:footprintBytes:loader:)` paragraph shows `PooledEmbedder(ref: "…")`.

- **Added by the plan author after iteration 1:** `MetadataSearcher` has exactly ONE initializer that takes `embedder:`, and it is synchronous. Delete the async `init(items:mode:weights:embedder:selection:onDiagnostic:) async`. Two initializers with the same labels, where an async context always selects the async one, make the synchronous one impossible to reach from async code (every `main.swift`). The first search embeds the catalog (catch-up path). Change each registry caller from `await MetadataSearcher(` to `MetadataSearcher(` (tests, README, plan.md). A test that needs the catalog embedded before a step does one search first, or uses the existing internal seam. Downstream callers (Skills tests, one Multitool integration test) then only get a warning for an unneeded `await`; their own tasks remove it.

## Acceptance Criteria
- [x] `MetadataSearcher` has one initializer with `embedder:`; it is synchronous; `grep -rn "await MetadataSearcher(" Sources Tests IntegrationTests README.md` finds nothing.
- [x] `PooledTextEmbedding` and the `embeddingModel:` initializer do not exist.
- [x] `MetadataSearcher(items:, embedder: PooledEmbedder(ref: "…"))` is synchronous and the first search reports cosine signals.
- [x] Two searchers with one embedder name share one resident model.
- [ ] CI (unit and integration jobs) is green on the pushed commit.

## Tests
- [x] New `Tests/FoundationModelsMetadataRegistryTests/PooledEmbedderSearchTests.swift`: with `ModelPool(loader:)` and a test loader: embed at the first search; two searchers, one load.
- [x] `IntegrationTests/`: one real test with `PooledEmbedder(ref: "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ")` where the cosine signal ranks a paraphrase first.
- [x] `CIWorkflowTests` pins the metallib input.
- [x] `swift test` and `swift test --package-path IntegrationTests` pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #model-pool