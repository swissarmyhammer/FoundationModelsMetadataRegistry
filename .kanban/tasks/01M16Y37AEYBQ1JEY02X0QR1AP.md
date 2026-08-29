---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m1717gm8jt598f85zqeksyfs
  text: |-
    Research done. Findings:

    - `SemanticSearchCore.runSemanticSearch(query:embedder:limit:onDiagnostic:)` has NO default for `embedder`. `HotReloadCore.runHotReloadBurst(burst:query:limit:embedder:)` already defaults `embedder` to `DeterministicEmbedder()`. The card asks for a test that calls "SemanticSearchCore's entry function with the default embedder", so `runSemanticSearch` gets the same default: `embedder: (any TextEmbedding)? = DeterministicEmbedder()`. That matches the prevailing pattern in the sibling core.
    - `IntegrationTests/.../RouterIntegrationTests.swift` calls `SemanticSearchCore.runSemanticSearch(query:embedder:onDiagnostic:)` with an explicit embedder, so a new default breaks nothing there. That package is owned by a later task; not touched here.
    - `ExamplesSupport.isMetadataRegistryIntegrationEnabled` / `metadataRegistryIntegrationEnvVar` stay: `Examples/Librarian/main.swift` and `Examples/BigCatalog/main.swift` still read them, and sibling task ^mjp69rx owns those.
    - `DeterministicEmbedder` hashes UTF-8 bytes into a unit-normalized vector with non-negative components, so cosine over any two non-empty texts is > 0. The "cosine signal is present" assertion is therefore `signals.cosine > 0.0`, not an equality.
    - `Package.swift` target dependency lists are untouched: `SemanticSearchCore`/`HotReloadCore` keep their `LiveRouterSupport` target dependency until ^b2487hc removes it. Removing only the imports still builds.
  timestamp: 2026-08-29T15:11:52.968640+00:00
- actor: claude-code
  id: 01m171qccfnpekxw6af53n6y6h
  text: |-
    Implementation landed. TDD cycle, both directions watched:

    RED — added the two `ExamplesSmokeTests` tests first. `swift test --filter ExamplesSmokeTests` failed to compile: `error: missing argument for parameter 'embedder' in call`, which is the feature being absent, not a typo.

    GREEN — `runSemanticSearch` gained `embedder: (any TextEmbedding)? = DeterministicEmbedder()`. `swift test` = 106 tests in 9 suites, all pass (was 104).

    Also proved the second test discriminates, rather than passing for free: temporarily wrote the wrong implementation (`embedder: embedder ?? DeterministicEmbedder()` inside the body, so the default would leak into the `--no-embedder` path). That made it fail on both claims — `recorder.diagnostics.contains(.embeddingUnavailable)` and `matches.allSatisfy { $0.signals?.cosine == 0.0 }` — then reverted.

    Decisions worth carrying forward:

    - The doc comment could no longer claim "a paraphrased query ranks where keywords alone miss". `DeterministicEmbedder` hashes bytes, it does not model meaning, so `commit` does not rank first for "save my work" -- it lands 4th. The rewritten docs say the example demonstrates how the cosine signal is wired in, not ranking quality. Writing the old claim over the new embedder would have been a false doc comment.
    - `HotReload/main.swift`'s `printBurst(_:label:)` lost its `label` parameter, because deleting the "Live" branch left one caller passing one constant. The printed prefix is still "GPU-free step N", so the output is byte-identical to before.
    - Removed the `RouterIntegrationTests....` cross-reference from `HotReloadCore.swift`. The acceptance criterion is literal ("neither file names `Router`"), and it pointed into the sibling `IntegrationTests/` package. Replaced with a self-contained description of the churn shape.

    Scope held exactly to the card: `Examples/LiveRouterSupport/` untouched, `Package.swift` untouched (`SemanticSearchCore`/`HotReloadCore` keep their now-unused `LiveRouterSupport` target dependency until ^b2487hc removes it -- it still builds), `LibrarianCore`/`BigCatalogCore` untouched for ^mjp69rx.

    Known deliberate divergence for the reviewer: `LibrarianCore` and `BigCatalogCore` are near-copies that still carry the live-Router path and the `METADATA_REGISTRY_INTEGRATION_TESTS` gate. That is not an incomplete propagation -- sibling task ^mjp69rx owns those two files.
  timestamp: 2026-08-29T15:20:32.911047+00:00
- actor: claude-code
  id: 01m171qht2h0r3gf6pfkh3rtgv
  text: |-
    ### implement — changed
    - evidence: 5 files — Examples/SemanticSearchCore/SemanticSearchCore.swift, Examples/HotReloadCore/HotReloadCore.swift, Examples/SemanticSearch/main.swift, Examples/HotReload/main.swift, Tests/FoundationModelsMetadataRegistryTests/ExamplesSmokeTests.swift. `swift build` clean (only the pre-existing mlx `missing creator for mutated node` warning, present at baseline). `swift test` = 106 tests in 9 suites, 0 failures (was 104). `swift run SemanticSearch` prints cosine=0.898/0.875 on ranked matches; `swift run SemanticSearch --no-embedder` prints the embeddingUnavailable diagnostic with cosine=0.000; `swift run HotReload` prints all 4 burst steps plus the rebuild demo. All GPU-free, no network.
    - next: /review
  timestamp: 2026-08-29T15:20:38.466547+00:00
- actor: claude-code
  id: 01m1723jnykd3dyv88cksy6tkj
  text: |-
    ### review — findings
    - evidence: 1 finding (1 confirmed, 0 refuted) — Examples/HotReload/main.swift:19
    - scope: review sha HEAD~1..HEAD (commit 7766b4f)
    - next: remove the unused free function `printBurst(_:)` from Examples/HotReload/main.swift, then run /review again.
  timestamp: 2026-08-29T15:27:12.574294+00:00
- actor: claude-code
  id: 01m172475mbraa37y251zej84v
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 5 files: Examples/SemanticSearchCore/SemanticSearchCore.swift, Examples/HotReloadCore/HotReloadCore.swift, Examples/SemanticSearch/main.swift, Examples/HotReload/main.swift, Tests/FoundationModelsMetadataRegistryTests/ExamplesSmokeTests.swift
    - test: green — swift test, 106 tests in 9 suites, 0 failed, 0 repo warnings; swift build --package-path IntegrationTests clean rebuild verified
    - commit: 7766b4f refactor(examples): remove live-Router embedder path from demo cores
    - review: findings — Examples/HotReload/main.swift:19 code-hygiene/dead-code-swift, printBurst(_:) left with no caller after the METADATA_REGISTRY_INTEGRATION_TESTS gate was deleted
  timestamp: 2026-08-29T15:27:33.556894+00:00
- actor: claude-code
  id: 01m172esybpg6ptwg5gzhzd4xh
  text: |-
    Finding resolved. What the dead-code-swift rule actually saw, and why the fix is whole-file:

    Ran the rule's own tool by hand to see the full picture, not only the one reported line. Swift 6.4 writes the index store to `.build/out`, not `.build/debug/index/store`:

        swift build --build-tests
        periphery scan --skip-build --index-store-path .build/out \
          --retain-public --retain-objc-accessible --retain-swift-ui-previews \
          --retain-codable-properties --relative-results --report-exclude 'Tests/**'

    Before the fix, periphery reported FOUR declarations in `Examples/HotReload/main.swift`, not one:

        :19 Unused function 'printBurst(_:)'
        :20 Unused function 'printBurst(_:label:)'
        :29 Unused property 'steps'
        :34 Unused property 'rebuild'

    The review reported only `printBurst(_:)` because its scope was the changed lines. The other three are the same cause. Every one of those declarations IS referenced -- but only from top-level code in the same `main.swift`, and periphery's index does not attribute those references once the file also declares a free function. The sibling `Examples/SemanticSearch/main.swift`, which is pure top-level statements with no `func`, reports nothing at all. That is the shape the rule accepts.

    Fix: deleted the free function `printBurst(_:)` and inlined its `for` loop into the top-level code, so `HotReload/main.swift` now has the same shape as `SemanticSearch/main.swift` -- imports, a file doc comment, then top-level statements only. The doc comment on the function became a `//` comment above the loop it describes.

    After the fix periphery reports `* No unused code detected.` for the WHOLE workspace, so the `steps` and `rebuild` reports went with it. No `periphery:ignore` marker was used; the declarations are gone rather than suppressed.

    Checked the other file whose gate was removed in the same commit, `Examples/SemanticSearch/main.swift`, for the same class of orphan: none. Its `import Foundation` was already dropped in that commit; `import ExamplesSupport` is still live (`DeterministicEmbedder`, `formattedMatches`) and `import SemanticSearchCore` is still live (`query`, `runSemanticSearch`, `printDiagnostic`). Periphery agrees -- no finding there.

    Verification that the change is behaviour-free: captured `swift run HotReload` output before the edit and diffed it against the output after. Byte identical, all 14 lines.

    Also re-verified every acceptance criterion on the card and checked those boxes: grep over the four files finds no `LiveRouterSupport`, `Router`, `buildLiveEmbedder`, `RoutedEmbedderAdapter`, or `METADATA_REGISTRY_INTEGRATION_TESTS`; both demos and `--no-embedder` run GPU-free with no network.

    Scope held: `Examples/LiveRouterSupport/`, `LibrarianCore`, `BigCatalogCore` and `Package.swift` untouched.
  timestamp: 2026-08-29T15:33:20.459770+00:00
- actor: claude-code
  id: 01m172eyfyjtgxaadpn4q24bp8
  text: |-
    ### implement — changed
    - evidence: 1 file — Examples/HotReload/main.swift. `periphery scan` over the workspace: 4 findings before, `No unused code detected` after. `swift build --build-tests` clean (only the pre-existing mlx `missing creator for mutated node` build-system warning, present at baseline). `swift test` = 106 tests in 9 suites, 0 failures. `swift build --package-path IntegrationTests` clean. `swift run HotReload` output diffed byte-identical against the pre-edit capture; `swift run SemanticSearch` prints cosine=0.894/0.899; `--no-embedder` prints the embeddingUnavailable diagnostic with cosine=0.000.
    - next: /review
  timestamp: 2026-08-29T15:33:25.118468+00:00
depends_on:
- 01M16Y2V1034PDVAN8Z0GK3T9F
position_column: doing
position_ordinal: '80'
title: Remove the live-Router embedder path from SemanticSearchCore and HotReloadCore
---
## What

`SemanticSearchCore` and `HotReloadCore` each have one function that resolves a real embedder through a live Router. Both call `buildLiveEmbedder(demoLabel:name:description:)` in `Examples/LiveRouterSupport/`. Replace that path with the GPU-free `DeterministicEmbedder`.

Files to change:
- `Examples/SemanticSearchCore/SemanticSearchCore.swift` — delete `resolveLiveEmbedder()` (line 81) and its `import LiveRouterSupport` (line 4). Add `import ExamplesSupport`. Make the demo use `DeterministicEmbedder()` as its embedder. Keep the `--no-embedder` flag and its keyword-only diagnostic; that path does not change.
- `Examples/HotReloadCore/HotReloadCore.swift` — delete `resolveLiveEmbedder()` (line 320) and its `import LiveRouterSupport` (line 4). The `embedder` parameter already defaults to `DeterministicEmbedder()` (line 154), so the burst keeps working.
- `Examples/SemanticSearch/main.swift` and `Examples/HotReload/main.swift` — delete the `METADATA_REGISTRY_INTEGRATION_TESTS` gate and the branch that calls the deleted function. Both demos now run one GPU-free path always.

Update every doc comment that names Router, `LiveModelLoader`, or "live-Router-resolved embedder".

## Acceptance Criteria

- [x] Neither file imports `LiveRouterSupport`.
- [x] Neither file names `Router`, `buildLiveEmbedder`, or `RoutedEmbedderAdapter`.
- [x] `swift run SemanticSearch` prints ranked matches with a cosine signal, with no network and no GPU.
- [x] `swift run HotReload` prints the burst as before, with no network and no GPU.

## Tests

- [x] `Tests/FoundationModelsMetadataRegistryTests/HotReloadTests.swift` — the existing burst tests pass unchanged.
- [x] `Tests/FoundationModelsMetadataRegistryTests/ExamplesSmokeTests.swift` — add a test that calls `SemanticSearchCore`'s entry function with the default embedder and asserts the cosine signal is present in the returned `Signals`, and a second test that asserts the `--no-embedder` path still emits its keyword-only diagnostic.
- [x] Run `swift test`. All tests pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-08-29 10:24)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 5 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Examples/HotReload/main.swift:19` `code-hygiene/dead-code-swift` — function.free `printBurst(_:)` is unused.
