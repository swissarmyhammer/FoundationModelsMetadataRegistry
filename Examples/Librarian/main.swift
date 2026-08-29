import ExamplesSupport
import LibrarianCore

/// # `.selection` mode end-to-end (plan.md §13 M8).
///
/// A cached root session, seeded once with the whole trip-planning catalog,
/// `fork()`s a fresh child per query; output is ids-only, grammar-constrained,
/// mapped back to verbatim blocks. The intent-level query "the warmest city
/// on my trip" requires picking both `tripCities` and `weather` -- no single
/// tool answers it alone, and `LibrarianCore`'s scripted `DemoAgentSession`
/// names exactly those two, so the whole run is GPU-free and needs no
/// network. Run with `swift run Librarian`.
///
/// The actual logic lives in `LibrarianCore` so it stays a plain library the
/// same shape as `CatalogSearchCore`/`SemanticSearchCore`; this file is just
/// the runnable entry point.

printCatalog()

print("\nQuery: \"\(librarianQuery)\"\n")
let matches = try await runLibrarianSelection(query: librarianQuery)
print(formattedMatches(matches: matches))
