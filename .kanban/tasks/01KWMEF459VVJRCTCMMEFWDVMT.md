---
depends_on:
- 01KWMECNX02RYW074R5DFHQ4EA
position_column: todo
position_ordinal: 8a80
title: 'Examples: CatalogSearch and SemanticSearch executables'
---
## What
Build the first two `Examples/` executable targets per plan.md §13 (M8), added to `Package.swift` as executable targets depending on the library (demos only — the library never depends on them):
- `Examples/CatalogSearch/main.swift` — the ~30-line hello world: a handful of fixture items conforming to `SearchableMetadata`, keyword-only `MetadataSearcher(mode: .retrieval)` (no embedder, no model), one query, printed `Match`es with per-signal `Signals`. Runs anywhere, GPU-free.
- `Examples/SemanticSearch/main.swift` — CatalogSearch plus `RoutedEmbedderAdapter`: a paraphrased query ("save my work" → `commit`) ranks where keywords miss; `--no-embedder` flag demonstrates keyword-only degradation and prints its diagnostic.

## Acceptance Criteria
- [ ] `swift run CatalogSearch` prints ranked matches with signals, exit 0, no model downloads
- [ ] `swift run SemanticSearch --no-embedder` prints the degradation diagnostic and keyword-only results, exit 0, GPU-free
- [ ] Both targets compile as part of `swift build` (CI keeps them compiling)

## Tests
- [ ] `Tests/FoundationModelsMetadataRegistryTests/ExamplesSmokeTests.swift` — invoke the example entry logic (factored into a callable function per example) and assert on its output for the GPU-free paths
- [ ] Run `swift build && swift test` — exit 0

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.