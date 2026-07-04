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
depends_on:
- 01KWMEEA0FQB66C11H0V13TGR4
- 01KWMEF459VVJRCTCMMEFWDVMT
position_column: doing
position_ordinal: '80'
title: 'Examples: Librarian, BigCatalog, and HotReload executables'
---
## What
Build the remaining three `Examples/` executable targets per plan.md §13 (M8), extending the `Package.swift` example-target setup and `ExamplesSmokeTests.swift` created by the CatalogSearch/SemanticSearch task:
- `Examples/Librarian/main.swift` — selection mode end-to-end on a Router model: cached root seeded with a catalog, fork per query, ids-only xgrammar-constrained selection, verbatim blocks out; intent-level queries ("the warmest city on my trip" → `tripCities` + `weather`). The model run is behind the **same opt-in env var as the gated integration suite**; without it the example prints its catalog and exits 0.
- `Examples/BigCatalog/main.swift` — the headroom story: synthetic ~10³-entry catalog (ids = URIs), in-memory retrieval with printed timings (GPU-free), then — only when the env var is set — a selection query that overflows the budget → top-M → one-off session with the `.retrievalCut` diagnostic printed.
- `Examples/HotReload/main.swift` — `update(items:)` bursts (MCP-style add/remove): immediate keyword searchability, embed catch-up progress via `.embedCatchUp`, root + grammar rebuild shown; runs GPU-free with a `FakeEmbedder`-style deterministic embedder, real model only behind the env var.

## Acceptance Criteria
- [x] All three targets compile as part of `swift build` (CI keeps them compiling via the scaffold task's workflow)
- [x] `swift run BigCatalog` (no env var) exits 0 GPU-free and prints retrieval timings
- [x] `swift run Librarian` and `swift run HotReload` (no env var) exit 0 GPU-free on their degraded paths; with the gated-integration env var set they run the full model-backed flow locally

## Tests
- [x] `Tests/FoundationModelsMetadataRegistryTests/ExamplesSmokeTests.swift` — extend with the GPU-free portions (BigCatalog retrieval timing path, HotReload index-rebuild path with a deterministic embedder), asserting exit/output of the factored entry functions
- [x] Run `swift build && swift test` — exit 0 without GPU

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.