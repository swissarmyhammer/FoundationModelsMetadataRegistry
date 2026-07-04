---
comments:
- actor: claude-code
  id: 01kwq14ct63w54ad8q8jv1x2ap
  text: 'Picked up by /finish scoped-batch loop (task 12 of batch, final task in scope). Plan: /implement → /test → /commit checkpoint → /review HEAD~1..HEAD. Note: the opt-in gating env var for real-model paths is METADATA_REGISTRY_INTEGRATION_TESTS, established by the just-completed ^3ncv5a3 task — reuse that exact name.'
  timestamp: 2026-07-04T16:59:32.550881+00:00
- actor: claude-code
  id: 01kwq237gfyck2xx5y0jghvpfz
  text: |-
    Implementation complete, build/test green. Summary:

    - Package.swift: added LibrarianCore/Librarian, BigCatalogCore/BigCatalog, HotReloadCore/HotReload target pairs (mirroring the CatalogSearchCore/SemanticSearchCore *Core-library-plus-thin-executable pattern), and added BigCatalogCore + HotReloadCore to the test target's dependencies (LibrarianCore deliberately NOT added -- its only GPU-free behavior is the catalog print, which needs no dedicated unit test per the task's explicit Tests scope).
    - Examples/ExamplesSupport/ExamplesSupport.swift: generalized `formattedMatches` from `[Match<GitCommand>]` to `<Item: SearchableMetadata>(matches: [Match<Item>])` so all five examples share one formatter; added `metadataRegistryIntegrationEnvVar`/`metadataRegistryIntegrationEnabled` (reads "METADATA_REGISTRY_INTEGRATION_TESTS", the exact literal ^3ncv5a3 established) since all three new examples needed the same gate check (rule-of-three: shared rather than duplicated 3x).
    - Examples/LibrarianCore + Examples/Librarian: trip-planning catalog (tripCities/weather/currency/packingList/flightStatus), `.selection` mode end-to-end -- cached root + fork-per-call (catalog deliberately kept under SelectionConfig's default budget), ids-only xgrammar-constrained via a hand-built JSON Schema (see design note below), intent-level query "the warmest city on my trip". Gated behind the shared env var; ungated path just prints the catalog and exits 0. No new unit tests (task's Tests section didn't ask for any; its only GPU-free behavior is trivial catalog printing).
    - Examples/BigCatalogCore + Examples/BigCatalog: `makeBigCatalog(count:)` synthetic ~1000-entry catalog (ids = URIs) with one deterministic "needle" entry; `runBigCatalogRetrieval` GPU-free retrieval-timing core (tested); gated `runBigCatalogOverBudgetSelection` forces the over-budget top-M + one-off session path via a deliberately tiny `capacityCharacterLimit`, printing `.retrievalCut`.
    - Examples/HotReloadCore + Examples/HotReload: `DeterministicEmbedder` (GPU-free FakeEmbedder-style double, byte-hash + L2-normalize), `runHotReloadBurst` replays an MCP-style add/remove burst against a live `MetadataSearcher`, capturing per-step diagnostics (`.embedCatchUp`) and immediate keyword-search results (tested); `runSelectionRootRebuildDemo` shows the selection tier's cached-root/grammar rebuild on a real catalog change via a scripted `AgentSession` double (tested). Gated `resolveLiveEmbedder` replays the same burst against a real embedder.
    - Tests/.../ExamplesSmokeTests.swift: added 4 new GPU-free tests (BigCatalog retrieval-timing + formatter, HotReload burst-staging + selection-root-rebuild), following the established `@testable import *Core` pattern -- watched them fail to compile first (target had no source files), then implemented until green.

    Design note: `SelectionTier.idEnumGrammar(ids:)` is package-internal, so LibrarianCore/BigCatalogCore each hand-build an equivalent JSON Schema locally (`{"ids": {"type":"array","items":{"enum":[...]}, "uniqueItems":true}}`) rather than reaching into the package's internals or depending on `Selection.generationSchema`'s cross-module accessibility (unverified) -- this is what a real integrator outside the package would do, and `MetadataSearcher`'s selection tier still filters/reports any out-of-candidate id regardless of how the grammar was built.

    Verification (all fresh, no METADATA_REGISTRY_INTEGRATION_TESTS set, no model downloads):
    - `swift build`: exit 0, no new warnings (only the pre-existing unrelated mlx-swift bundle warning).
    - `swift test`: 130/130 passed (126 prior + 4 new), gated RouterIntegrationTests suite correctly skipped.
    - `swift run BigCatalog` / `swift run Librarian` / `swift run HotReload`: all exit 0 on GPU-free/ungated paths with correct output.

    Adversarial double-check review in progress via really-done.
  timestamp: 2026-07-04T17:16:22.927868+00:00
- actor: claude-code
  id: 01kwq31yg86hcxgmk18jy2kzwq
  text: |-
    Adversarial double-check (really-done gate) ran twice, bounded per the skill's contract:

    Round 1 verdict: REVISE, three findings:
    1. `ExamplesSupport`'s new shared `metadataRegistryIntegrationEnvVar`/`metadataRegistryIntegrationEnabled` duplicated (not reused by) `RouterIntegrationTests.swift`'s own pre-existing private declaration of the same gate -- two independent declarations that could silently drift.
    2. `resolveLiveProfile`/`resolveLiveEmbedder`'s Router/LiveModelLoader/ProfileDefinition boilerplate was duplicated four times (SemanticSearchCore pre-existing + my three new LibrarianCore/BigCatalogCore/HotReloadCore copies).
    3. `BigCatalogCore.makeBigCatalog(count:)` had a doc/behavior mismatch for `count <= 0` (doc claimed "count entries long", code always returned exactly 1 entry regardless).

    Fixes applied:
    1. `RouterIntegrationTests.swift` now `import ExamplesSupport` and uses its shared `metadataRegistryIntegrationEnvVar`/`metadataRegistryIntegrationEnabled` directly instead of its own copy.
    2. New shared library target `Examples/LiveRouterSupport` (depends on FoundationModelsRouter + MLX/HuggingFace/Tokenizers only -- deliberately NOT added to `ExamplesSupport`/`CatalogSearchCore`/`CatalogSearch`, which stay GPU-free) hosts one `resolveLiveProfile(demoLabel:name:description:)`; all four call sites (SemanticSearchCore, LibrarianCore, BigCatalogCore, HotReloadCore) now call it instead of duplicating the Router setup.
    3. `makeBigCatalog(count:)` now `guard count > 0 else { return [] }`, doc updated to match.

    Round 2 verdict: PASS. All three findings confirmed resolved; no new issues. It flagged one pre-existing non-blocking observation (idEnumGrammar duplicated between LibrarianCore/BigCatalogCore, not one of the three re-checked findings) -- fixed anyway while cheap, by moving `idEnumGrammar(ids:)` into the same `LiveRouterSupport` target (it already carries the FoundationModelsRouter dependency `Grammar` needs) and having both call sites use the shared one.

    Final verification (fresh, no METADATA_REGISTRY_INTEGRATION_TESTS set, no model downloads):
    - `swift build`: exit 0, no new warnings.
    - `swift test`: 130/130 passed.
    - `swift run BigCatalog` / `swift run Librarian` / `swift run HotReload`: all exit 0 on GPU-free/ungated paths.

    Task is green and ready for /review. Leaving in `doing` per the implement workflow (review moves it to the review column).
  timestamp: 2026-07-04T17:33:09.512983+00:00
- actor: claude-code
  id: 01kwq38s5ntvcf6chd6bjswevb
  text: 'Iteration 1: implement landed green in doing (130 tests passed / 0 failed across 12 suites, all three new executables verified exit 0 on their GPU-free/ungated paths). Checkpoint committed at ed9ed05. Double-check found and fixed real duplication/bugs pre-checkpoint: a 4x-duplicated Router-resolution helper (extracted to new LiveRouterSupport), a duplicated env-var gate declaration (deduplicated into ExamplesSupport, RouterIntegrationTests.swift now reuses it), and a doc/behavior mismatch in makeBigCatalog(count:) for count <= 0. Proceeding to /review HEAD~1..HEAD.'
  timestamp: 2026-07-04T17:36:53.429893+00:00
- actor: claude-code
  id: 01kwq4pdn2avrxmnd0b4637rc4
  text: |-
    Pulled back from `review` to `doing` and fixed all 13 review-finding checklist items (5 distinct issues):

    1. **Fixture-type duplication** (GitCommand / BigCatalogItem / HotReloadTool / TripPlanningTool): collapsed into one generic `SearchableFixtureItem` struct in `Examples/ExamplesSupport/ExamplesSupport.swift` (id + block + init + renderBlock). Each of the four names is now `public typealias X = SearchableFixtureItem` in its own file (`ExamplesSupport.swift`, `BigCatalogCore.swift`, `HotReloadCore.swift`, `LibrarianCore.swift`). Each core's fixture DATA (the literal catalogs) stayed local, per the task's instruction. GitCommand's old `summary:` init label was unified to `block:`; updated both call sites (`ExamplesSupport.baseGitCommands` and `SemanticSearchCore.gitCommands`'s appended `status` item).

    2. **SelectionConfig-building duplication** (BigCatalogCore.runBigCatalogOverBudgetSelection / LibrarianCore.resolveLiveSelectionConfig): extracted `buildSelectionConfig(demoLabel:name:description:ids:capacityCharacterLimit:)` into `Examples/LiveRouterSupport/LiveRouterSupport.swift`. `capacityCharacterLimit: nil` falls back to `SelectionConfig.defaultCapacityCharacterLimit` (same constant SelectionConfig's own init already defaulted to, so LibrarianCore's behavior is unchanged); BigCatalogCore still passes its explicit `2_000` override.

    3. **printDiagnostic duplication** (BigCatalogCore / SemanticSearchCore): extracted `printExampleDiagnostic(_:describingSpecialCase:)` into `ExamplesSupport.swift` (not LiveRouterSupport — it only touches `MetadataDiagnostic`, no Router dependency needed, consistent with ExamplesSupport's "stays GPU-free/Router-free" design). Each core's `printDiagnostic` is now a thin wrapper passing a case-matching closure.

    4. **resolveLiveEmbedder duplication** (HotReloadCore / SemanticSearchCore): extracted `buildLiveEmbedder(demoLabel:name:description:)` into `LiveRouterSupport.swift`; both cores now delegate to it.

    5. **Missing doc comments**: added `///` doc comments to `HotReloadCore.DeterministicEmbedder`'s `dimension` property and `embed(_:)` method.

    Side effects: added `.target(name: packageName)` as a `LiveRouterSupport` dependency in `Package.swift` (needed since the new shared helpers reference `SelectionConfig`/`RoutedAgentSession`/`TextEmbedding`/`RoutedEmbedderAdapter`, which live in the main library target) and `import FoundationModelsMetadataRegistry` in `LiveRouterSupport.swift`. Removed now-dead `import FoundationModelsRouter` from `BigCatalogCore.swift`, `LibrarianCore.swift`, `HotReloadCore.swift`, `SemanticSearchCore.swift` (all Router construction now goes through `LiveRouterSupport`; verified no direct Router-only type usage remained in any of the four).

    Grepped the whole `Examples/` tree after each extraction to confirm zero remaining duplicates of each pattern (fixture types, resolveLiveProfile+idEnumGrammar+SelectionConfig construction, printDiagnostic's if-case/log pattern, RoutedEmbedderAdapter construction).

    Verification (all fresh): `swift build` exit 0, no new warnings (only the pre-existing unrelated mlx-swift bundle warning); `swift test` 130/130 passed across 12 suites; `swift run BigCatalog` / `swift run Librarian` / `swift run HotReload` all exit 0 on their GPU-free/ungated paths (no `METADATA_REGISTRY_INTEGRATION_TESTS` set, no model downloads).

    Adversarial double-check (via really-done) ran once and returned PASS, independently re-verifying build/test/run and each of the 5 fixes (including checking for leftover duplicate call sites, confirming the `summary:`→`block:` rename touched every real call site, confirming no hidden transitive access to the removed Router import, and confirming architectural placement of the two new ExamplesSupport/LiveRouterSupport helpers). Its one non-blocking observation (this kanban task's own checklist not yet flipped) is resolved by this update.

    Leaving the task in `doing` per the implement workflow — ready for `/review`.
  timestamp: 2026-07-04T18:01:48.962638+00:00
- actor: claude-code
  id: 01kwq5q4m7k3gey39z1rbc49n1
  text: |-
    Pulled back from `review` to `doing` and fixed all 10 items in the "2026-07-04 13:04" review-findings checklist (3 distinct issues):

    1. **Boolean naming**: renamed `ExamplesSupport.metadataRegistryIntegrationEnabled` -> `isMetadataRegistryIntegrationEnabled` (is-prefixed per Swift convention). Updated every call site: `Tests/.../Integration/RouterIntegrationTests.swift` (`.enabled(if:)`), `Examples/Librarian/main.swift`, `Examples/BigCatalog/main.swift`, `Examples/HotReload/main.swift`, plus doc-comment references in `BigCatalogCore.swift`, `LibrarianCore.swift`, `HotReloadCore.swift`. Grepped for the old name afterward -- zero remaining references.

    2. **Missing doc comment**: added a `///` doc comment to `HotReloadCore.hotReloadToolB` (and, for consistency/symmetry, to sibling constants `hotReloadToolA`/`hotReloadToolC` too, since they're part of the same public trio and the review's own example message implied documenting the set).

    3. **Package.swift boilerplate** (8 findings, one root cause each of two shapes):
       - Extracted the repeated 8-entry live-Router dependency array (`.target(name: packageName)`, `ExamplesSupport`, `LiveRouterSupport`, Router/MLXHuggingFace/MLXLMCommon/HuggingFace/Tokenizers products) into a top-level constant `liveRouterCoreDependencies: [Target.Dependency]`, reused by `SemanticSearchCore`, `LibrarianCore`, `BigCatalogCore`, and `HotReloadCore` targets (`dependencies: liveRouterCoreDependencies` replacing each 8-line inline array).
       - Extracted the repeated executable-target boilerplate into `func exampleExecutableTarget(name: String, coreName: String) -> Target`, used for all five executables: `CatalogSearch`, `SemanticSearch`, `Librarian`, `BigCatalog`, `HotReload`.
       - Grepped afterward: only one `.executableTarget(` call site remains in the whole manifest (inside the helper itself); the `liveRouterCoreDependencies` array literal appears exactly once. `LiveRouterSupport`'s own (6-entry, different) dependency list and the test target's own (gated-suite) dependency list are legitimately distinct and were left as-is -- they were never part of the flagged duplication.

    Verification (all fresh, no `METADATA_REGISTRY_INTEGRATION_TESTS` set, no model downloads):
    - `swift build`: exit 0, no new warnings (only the pre-existing unrelated mlx-swift bundle warning).
    - `swift test`: 130/130 passed across 12 suites.
    - `swift run BigCatalog` / `swift run Librarian` / `swift run HotReload` / `swift run CatalogSearch` / `swift run SemanticSearch`: all exit 0 on their GPU-free/ungated paths, output unchanged from before the manifest refactor.

    All 10 checklist items under "Review Findings (2026-07-04 13:04)" flipped to `[x]`. Leaving the task in `doing` per the implement workflow -- ready for `/review`.
  timestamp: 2026-07-04T18:19:41.063352+00:00
- actor: claude-code
  id: 01kwq6qpmw7fqf265b17x7qmhq
  text: |-
    Pulled back from `review` to `doing` and fixed the single remaining "2026-07-04 13:24" review-finding checklist item (Package.swift's 5-entry product dependency list still duplicated across `liveRouterCoreDependencies`, the test target's dependencies, and `LiveRouterSupport`'s dependencies):

    - Extracted a new top-level constant `let liveRouterProductDependencies: [Target.Dependency] = [...]` in Package.swift holding the 5 shared product entries (FoundationModelsRouter, MLXHuggingFace, MLXLMCommon, HuggingFace, Tokenizers).
    - `liveRouterCoreDependencies` is now `[.target(name: packageName), .target(name: "ExamplesSupport"), .target(name: "LiveRouterSupport")] + liveRouterProductDependencies` (unchanged 8-entry result).
    - The test target's `dependencies` array now ends with `] + liveRouterProductDependencies` instead of the 5 inline `.product(...)` lines (unchanged 11-entry result: 6 `.target` + the quintet).
    - `LiveRouterSupport`'s target `dependencies` is now `[.target(name: packageName)] + liveRouterProductDependencies` (unchanged 6-entry result).
    - Updated the doc comments above the old `liveRouterCoreDependencies` constant to split into one doc block for the new `liveRouterProductDependencies` (explaining the quintet and its three call sites) and an updated doc block for `liveRouterCoreDependencies` (now described as the 3 base target deps plus the quintet).

    Grepped the whole file afterward: `MLXHuggingFace` and `routerDependencyName, package: routerDependencyName` each now appear in exactly one array literal (`liveRouterProductDependencies`); no remaining duplicate.

    Verification (all fresh, no `METADATA_REGISTRY_INTEGRATION_TESTS` set, no model downloads):
    - `rm -rf .build && swift package describe --type json`: target/dependency graph unchanged -- `product_dependencies` for SemanticSearchCore, LibrarianCore, BigCatalogCore, HotReloadCore, `LiveRouterSupport`, and the test target still each list exactly FoundationModelsRouter/MLXHuggingFace/MLXLMCommon/HuggingFace/Tokenizers, and `target_dependencies` for every target are unchanged from before this fix.
    - `swift build` (clean `.build`): exit 0, no new warnings.
    - `swift test`: 130/130 passed across 12 suites.
    - `swift run CatalogSearch` / `SemanticSearch` / `BigCatalog` / `Librarian` / `HotReload`: all exit 0 on their GPU-free/ungated paths with correct output (catalog prints, retrieval timings, burst diagnostics), unchanged from before the fix.

    Adversarial double-check (via really-done) ran once on the `git diff -- Package.swift`: verdict PASS. It independently re-derived the entry counts (8 / 11 / 6), confirmed only one array literal defines the quintet across the whole manifest, confirmed the doc comments accurately describe the new structure, and confirmed this is a genuine root fix (single named constant reused at all three call sites) rather than a cosmetic change.

    All 1 item under "Review Findings (2026-07-04 13:24)" flipped to `[x]`. Leaving the task in `doing` per the implement workflow -- ready for `/review`.
  timestamp: 2026-07-04T18:37:28.092965+00:00
- actor: claude-code
  id: 01kwq7fpjyzmmc6yxmv4g30vke
  text: |-
    Pulled back from `review` to `doing` and fixed the single remaining "2026-07-04 13:42" review-finding checklist item (4 duplicate occurrences of the "ExamplesSupport" string literal in Package.swift).

    - Added `let examplesSupportName = "ExamplesSupport"` (Package.swift, alongside the other name constants: packageName, routerDependencyName, mlxPackage, huggingFacePackage, transformersPackage), with a doc comment explaining it's referenced by every example's dependency list plus the target's own declaration.
    - Replaced all 4 literal occurrences with the constant:
      1. `liveRouterCoreDependencies`'s `.target(name: "ExamplesSupport")` -> `.target(name: examplesSupportName)`
      2. `exampleExecutableTarget(name:coreName:)`'s `.target(name: "ExamplesSupport")` -> `.target(name: examplesSupportName)`
      3. The test target's `.target(name: "ExamplesSupport")` -> `.target(name: examplesSupportName)`
      4. The `ExamplesSupport` target's own declaration: `name: "ExamplesSupport"` -> `name: examplesSupportName`, and its `path: "Examples/ExamplesSupport"` -> `path: "Examples/\(examplesSupportName)"` (kept in sync since the directory name matches the target name).

    Grepped the file afterward: the literal `"ExamplesSupport"` now appears exactly once, inside the constant's own declaration.

    Verification (all fresh, no `METADATA_REGISTRY_INTEGRATION_TESTS` set, no model downloads):
    - `swift package describe --type json`: target/dependency graph unchanged from the prior iteration -- all 14 targets present with identical `target_dependencies`/`product_dependencies`/`path` values (ExamplesSupport target still resolves to path `Examples/ExamplesSupport` via the interpolated constant).
    - `rm -rf .build && swift build`: exit 0, no warnings at all in this run.
    - `swift test`: 130/130 passed across 12 suites.
    - `swift run CatalogSearch` / `SemanticSearch` / `BigCatalog` / `Librarian` / `HotReload`: all exit 0 on their GPU-free/ungated paths, output unchanged.

    All 4 items under "Review Findings (2026-07-04 13:42)" flipped to `[x]`. Leaving the task in `doing` per the implement workflow -- ready for `/review`.
  timestamp: 2026-07-04T18:50:34.462457+00:00
- actor: claude-code
  id: 01kwq876bs2hfn4ys0rc6zdew4
  text: |-
    Pulled back from `review` to `doing` and fixed the single remaining "2026-07-04 13:54" review-finding checklist item (4 identical `*Core` target declarations in Package.swift: SemanticSearchCore, LibrarianCore, BigCatalogCore, HotReloadCore).

    - Added `func exampleCoreTarget(name: String) -> Target` right after the existing `exampleExecutableTarget(name:coreName:)` helper, mirroring its shape/doc-comment style: `.target(name: name, dependencies: liveRouterCoreDependencies, path: "Examples/\(name)")`.
    - Replaced all four `.target(name: "...Core", dependencies: liveRouterCoreDependencies, path: "Examples/...Core")` blocks with `exampleCoreTarget(name: "...Core")` calls, keeping each target's preceding descriptive doc-comment block in place.
    - Left `CatalogSearchCore` alone per the finding's explicit note -- it has a different (2-entry, non-`liveRouterCoreDependencies`) dependency list since it's the GPU-free/Router-free example, so it correctly does not go through the new helper.
    - Doc-scanned the whole manifest afterward for any other remaining copy-paste target/dependency shapes (this being the 6th consecutive DRY-ness review round): no further duplicate array literals, string literals, or target shapes found. `exampleExecutableTarget` and `exampleCoreTarget` are structurally different (different dependency lists) so were not further merged. `CatalogSearchCore`'s own inline 2-entry dependency array is unique (only such array in the file) and not a duplicate of anything else.

    Verification (all fresh, no `METADATA_REGISTRY_INTEGRATION_TESTS` set, no model downloads):
    - `git stash` / `swift package describe --type json` before vs. after this change, compared as parsed JSON (`python3 -c "json.load(...) == json.load(...)"`): **byte-for-byte-equal parsed structure** -- target/dependency graph is unchanged.
    - `rm -rf .build && swift build`: exit 0, no new warnings.
    - `swift test`: 130/130 passed across 12 suites.
    - `swift run CatalogSearch` / `SemanticSearch` / `BigCatalog` / `Librarian` / `HotReload`: all exit 0 on their GPU-free/ungated paths, output unchanged from before the refactor.

    All 4 items under "Review Findings (2026-07-04 13:54)" flipped to `[x]`. Leaving the task in `doing` per the implement workflow -- ready for `/review`.
  timestamp: 2026-07-04T19:03:24.281923+00:00
depends_on:
- 01KWMEEA0FQB66C11H0V13TGR4
- 01KWMEF459VVJRCTCMMEFWDVMT
position_column: done
position_ordinal: 8b80
title: 'Examples: Librarian, BigCatalog, and HotReload executables'
---
## What\nBuild the remaining three `Examples/` executable targets per plan.md §13 (M8), extending the `Package.swift` example-target setup and `ExamplesSmokeTests.swift` created by the CatalogSearch/SemanticSearch task:\n- `Examples/Librarian/main.swift` — selection mode end-to-end on a Router model: cached root seeded with a catalog, fork per query, ids-only xgrammar-constrained selection, verbatim blocks out; intent-level queries (\"the warmest city on my trip\" → `tripCities` + `weather`). The model run is behind the **same opt-in env var as the gated integration suite**; without it the example prints its catalog and exits 0.\n- `Examples/BigCatalog/main.swift` — the headroom story: synthetic ~10³-entry catalog (ids = URIs), in-memory retrieval with printed timings (GPU-free), then — only when the env var is set — a selection query that overflows the budget → top-M → one-off session with the `.retrievalCut` diagnostic printed.\n- `Examples/HotReload/main.swift` — `update(items:)` bursts (MCP-style add/remove): immediate keyword searchability, embed catch-up progress via `.embedCatchUp`, root + grammar rebuild shown; runs GPU-free with a `FakeEmbedder`-style deterministic embedder, real model only behind the env var.\n\n## Acceptance Criteria\n- [x] All three targets compile as part of `swift build` (CI keeps them compiling via the scaffold task's workflow)\n- [x] `swift run BigCatalog` (no env var) exits 0 GPU-free and prints retrieval timings\n- [x] `swift run Librarian` and `swift run HotReload` (no env var) exit 0 GPU-free on their degraded paths; with the gated-integration env var set they run the full model-backed flow locally\n\n## Tests\n- [x] `Tests/FoundationModelsMetadataRegistryTests/ExamplesSmokeTests.swift` — extend with the GPU-free portions (BigCatalog retrieval timing path, HotReload index-rebuild path with a deterministic embedder), asserting exit/output of the factored entry functions\n- [x] Run `swift build && swift test` — exit 0 without GPU\n\n## Workflow\n- Use `/tdd` — write failing tests first, then implement to make them pass.\n\n## Review Findings (2026-07-04 12:37)\n\nAll items resolved and checked off in a prior iteration (fixture-type dedup, SelectionConfig-building extraction, printDiagnostic extraction, resolveLiveEmbedder extraction, doc comments).\n\n## Review Findings (2026-07-04 13:04)\n\nAll items resolved and checked off in a prior iteration (Boolean naming, missing doc comment, Package.swift boilerplate extraction).\n\n## Review Findings (2026-07-04 13:24)\n\n- [x] `Package.swift:54` — The 5-entry product dependency list (routerDependencyName, MLXHuggingFace, MLXLMCommon, HuggingFace, Tokenizers) appears identically in three separate places, violating the rule that repeated configuration should be a named constant. Maintenance of this list requires updates in three locations instead of one. Extract the 5 products as a shared constant (`let liveRouterProductDependencies: [Target.Dependency] = [...]`) and reuse it across all three locations to maintain a single source of truth.\n\n## Review Findings (2026-07-04 13:42)\n\n- [x] `Package.swift:51` — String literal \"ExamplesSupport\" is duplicated 4 times across the file and should be extracted as a named constant to avoid silent drift. Extract let examplesSupportName = \"ExamplesSupport\" at the top with the other constants (after line 35), then replace all 4 occurrences with examplesSupportName.\n- [x] `Package.swift:68` — String literal \"ExamplesSupport\" is duplicated 4 times across the file and should be extracted as a named constant to avoid silent drift. Extract let examplesSupportName = \"ExamplesSupport\" at the top with the other constants (after line 35), then replace all 4 occurrences with examplesSupportName.\n- [x] `Package.swift:96` — String literal \"ExamplesSupport\" is duplicated 4 times across the file and should be extracted as a named constant to avoid silent drift. Extract let examplesSupportName = \"ExamplesSupport\" at the top with the other constants (after line 35), then replace all 4 occurrences with examplesSupportName.\n- [x] `Package.swift:115` — String literal \"ExamplesSupport\" is duplicated 4 times across the file and should be extracted as a named constant to avoid silent drift. Extract let examplesSupportName = \"ExamplesSupport\" at the top with the other constants (after line 35), then replace all 4 occurrences with examplesSupportName.\n\n## Review Findings (2026-07-04 13:54)\n\n- [x] `Package.swift:127` — Repeated target pattern: identical structure at lines 127, 149, 183, 209 (only name differs) should be abstracted into a helper function. Create exampleCoreTarget(name:) helper function to eliminate duplication, matching the pattern used by exampleExecutableTarget(name:coreName:).\n- [x] `Package.swift:149` — Repeated target pattern: identical structure at lines 127, 149, 183, 209 (only name differs) should be abstracted into a helper function. Create exampleCoreTarget(name:) helper function to eliminate duplication, matching the pattern used by exampleExecutableTarget(name:coreName:).\n- [x] `Package.swift:183` — Repeated target pattern: identical structure at lines 127, 149, 183, 209 (only name differs) should be abstracted into a helper function. Create exampleCoreTarget(name:) helper function to eliminate duplication, matching the pattern used by exampleExecutableTarget(name:coreName:).\n- [x] `Package.swift:209` — Repeated target pattern: identical structure at lines 127, 149, 183, 209 (only name differs) should be abstracted into a helper function. Create exampleCoreTarget(name:) helper function to eliminate duplication, matching the pattern used by exampleExecutableTarget(name:coreName:).\n