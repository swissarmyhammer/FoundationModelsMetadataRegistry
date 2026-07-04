import ExamplesSupport
import LibrarianCore

/// # `.selection` mode end-to-end on a Router model (plan.md §13 M8).
///
/// A cached root session, seeded once with the whole trip-planning catalog,
/// `fork()`s a fresh child per query; output is ids-only, xgrammar-
/// constrained, mapped back to verbatim blocks. The intent-level query "the
/// warmest city on my trip" requires picking both `tripCities` and
/// `weather` -- no single tool answers it alone. The model run is gated
/// behind `METADATA_REGISTRY_INTEGRATION_TESTS`; without it, this example
/// prints its catalog and exits 0, GPU-free. Run with `swift run Librarian`.
///
/// The actual logic lives in `LibrarianCore` so it stays a plain library the
/// same shape as `CatalogSearchCore`/`SemanticSearchCore`; this file is just
/// the runnable entry point.

if metadataRegistryIntegrationEnabled {
    print("Query: \"\(librarianQuery)\"\n")
    let config = try await resolveLiveSelectionConfig()
    let matches = try await runLibrarianSelection(query: librarianQuery, config: config)
    print(formattedMatches(matches: matches))
} else {
    print("\(metadataRegistryIntegrationEnvVar) not set -- printing the catalog only (GPU-free).")
    print("Set \(metadataRegistryIntegrationEnvVar) to run the real selection query against a live model.\n")
    printCatalog()
}
