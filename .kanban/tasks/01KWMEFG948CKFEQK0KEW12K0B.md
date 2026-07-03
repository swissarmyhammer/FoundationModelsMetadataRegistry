---
depends_on:
- 01KWMEEA0FQB66C11H0V13TGR4
- 01KWMEF459VVJRCTCMMEFWDVMT
position_column: todo
position_ordinal: 8b80
title: 'Examples: Librarian, BigCatalog, and HotReload executables'
---
## What
Build the remaining three `Examples/` executable targets per plan.md §13 (M8), extending the `Package.swift` example-target setup and `ExamplesSmokeTests.swift` created by the CatalogSearch/SemanticSearch task:
- `Examples/Librarian/main.swift` — selection mode end-to-end on a Router model: cached root seeded with a catalog, fork per query, ids-only xgrammar-constrained selection, verbatim blocks out; intent-level queries ("the warmest city on my trip" → `tripCities` + `weather`). The model run is behind the **same opt-in env var as the gated integration suite**; without it the example prints its catalog and exits 0.
- `Examples/BigCatalog/main.swift` — the headroom story: synthetic ~10³-entry catalog (ids = URIs), in-memory retrieval with printed timings (GPU-free), then — only when the env var is set — a selection query that overflows the budget → top-M → one-off session with the `.retrievalCut` diagnostic printed.
- `Examples/HotReload/main.swift` — `update(items:)` bursts (MCP-style add/remove): immediate keyword searchability, embed catch-up progress via `.embedCatchUp`, root + grammar rebuild shown; runs GPU-free with a `FakeEmbedder`-style deterministic embedder, real model only behind the env var.

## Acceptance Criteria
- [ ] All three targets compile as part of `swift build` (CI keeps them compiling via the scaffold task's workflow)
- [ ] `swift run BigCatalog` (no env var) exits 0 GPU-free and prints retrieval timings
- [ ] `swift run Librarian` and `swift run HotReload` (no env var) exit 0 GPU-free on their degraded paths; with the gated-integration env var set they run the full model-backed flow locally

## Tests
- [ ] `Tests/FoundationModelsMetadataRegistryTests/ExamplesSmokeTests.swift` — extend with the GPU-free portions (BigCatalog retrieval timing path, HotReload index-rebuild path with a deterministic embedder), asserting exit/output of the factored entry functions
- [ ] Run `swift build && swift test` — exit 0 without GPU

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.