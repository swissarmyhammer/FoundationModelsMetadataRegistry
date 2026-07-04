import BigCatalogCore
import ExamplesSupport
import Foundation

/// # The headroom story (plan.md §13 M8).
///
/// A synthetic ~10^3-entry catalog (ids = URIs) proves the in-memory
/// retrieval story scales well past the half-dozen-item demos
/// `CatalogSearch`/`SemanticSearch` use, with printed timings -- GPU-free,
/// no network. Only when `METADATA_REGISTRY_INTEGRATION_TESTS` is set does
/// it also run a selection query that overflows the assembled-prefix
/// budget, forcing the over-budget top-M + one-off session path (plan.md
/// §6), printing the `.retrievalCut` diagnostic. Run with `swift run
/// BigCatalog`.
///
/// The actual logic lives in `BigCatalogCore` so `ExamplesSmokeTests` can
/// invoke the GPU-free retrieval-timing path directly; this file is just the
/// runnable entry point.

let catalog = makeBigCatalog()
print("Synthetic catalog size: \(catalog.count) entries")
print("Query: \"\(bigCatalogNeedleQuery)\"\n")

let retrieval = try await runBigCatalogRetrieval(catalog: catalog, query: bigCatalogNeedleQuery)
print(String(format: "Retrieval over %d entries took %.4fs (GPU-free, in-memory)\n", retrieval.catalogCount, retrieval.elapsed))
print(formattedMatches(matches: retrieval.matches))

if metadataRegistryIntegrationEnabled {
    print("\n\(metadataRegistryIntegrationEnvVar) is set -- running the over-budget selection query against a live model...\n")
    let matches = try await runBigCatalogOverBudgetSelection(catalog: catalog, query: bigCatalogNeedleQuery)
    print(formattedMatches(matches: matches))
} else {
    print("\nSet \(metadataRegistryIntegrationEnvVar) to also run the over-budget selection query against a live model.")
}
