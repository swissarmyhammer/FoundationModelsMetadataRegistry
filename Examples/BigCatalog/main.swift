import BigCatalogCore
import ExamplesSupport
import Foundation

/// # The headroom story (plan.md §13 M8).
///
/// A synthetic ~10^3-entry catalog (ids = URIs) proves the in-memory
/// retrieval story scales well past the half-dozen-item demos
/// `CatalogSearch`/`SemanticSearch` use, with printed timings. It then runs a
/// selection query over that same catalog that overflows the assembled-prefix
/// budget, forcing the over-budget top-M + one-off session path (plan.md §6)
/// and printing the `.retrievalCut` diagnostic. Both paths are GPU-free and
/// need no network -- the one-off session is a scripted `DemoAgentSession`.
/// Run with `swift run BigCatalog`.
///
/// The actual logic lives in `BigCatalogCore` so `ExamplesSmokeTests` and
/// `OverBudgetTests` can invoke both paths directly; this file is just the
/// runnable entry point.

let catalog = makeBigCatalog()
print("Synthetic catalog size: \(catalog.count) entries")
print("Query: \"\(bigCatalogNeedleQuery)\"\n")

let retrieval = try await runBigCatalogRetrieval(catalog: catalog, query: bigCatalogNeedleQuery)
print(String(format: "Retrieval over %d entries took %.4fs (GPU-free, in-memory)\n", retrieval.catalogCount, retrieval.elapsed))
print(formattedMatches(matches: retrieval.matches))

print("\nRunning the over-budget selection query (GPU-free, scripted session)...\n")
let selected = try await runBigCatalogOverBudgetSelection(
    catalog: catalog,
    query: bigCatalogNeedleQuery,
    onDiagnostic: printDiagnostic
)
print(formattedMatches(matches: selected))
