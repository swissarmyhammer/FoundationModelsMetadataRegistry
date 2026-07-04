import CatalogSearchCore

/// # The ~30-line hello world (plan.md §13 M1).
///
/// A handful of fixture items conformed to `SearchableMetadata`, a
/// keyword-only `MetadataSearcher(mode: .retrieval)` — no embedder, no
/// model, no session — one query, printed `Match`es with their per-signal
/// `Signals`: BM25, trigram, RRF, and explainability on one screen. Runs
/// anywhere, GPU-free. Run with `swift run CatalogSearch`.
///
/// The actual search logic lives in `CatalogSearchCore` so
/// `ExamplesSmokeTests` can invoke it directly; this file is just the
/// runnable entry point.

let query = "commit changes to git"
print("Query: \"\(query)\"\n")
let matches = try await runCatalogSearch(query: query)
print(formatMatches(matches))
