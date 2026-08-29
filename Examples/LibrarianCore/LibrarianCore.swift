import ExamplesSupport
import FoundationModelsMetadataRegistry

/// # `Librarian`'s entry logic (plan.md §13 M8): `.selection` mode end-to-end.
///
/// Generalizes Multitool's shipped `Librarian` (plan.md §6's namesake) over
/// this package's own catalog: a cached root session, seeded once with the
/// whole (under-budget) trip-planning catalog, `fork()`s a fresh child per
/// query so the prefix's KV cache is prefilled once and inherited per call
/// (plan.md §6). Output is ids-only, constrained by an id-enum grammar the
/// tier derives per call so the session is structurally incapable of
/// inventing a tool that doesn't exist; `MetadataSearcher` maps the returned
/// ids back through the catalog to verbatim blocks -- never generated text.
///
/// `librarianQuery` ("the warmest city on my trip") is an intent-level query:
/// no single catalog item answers it directly, so answering it requires
/// picking *both* `tripCities` (to know which cities to check) and
/// `weather` (to compare their conditions) -- exactly the task-decomposition
/// reasoning plan.md §6 says lexical/semantic ranking alone can't do.
///
/// The session is `ExamplesSupport`'s scripted `DemoAgentSession`, which
/// names exactly those two ids: this example demonstrates how the cached-root
/// selection path is wired and what it returns, not how well a real model
/// decomposes a task -- which is what keeps the whole example free of network
/// and GPU.

// MARK: - Fixture catalog

/// This example's domain-flavored alias for `ExamplesSupport`'s shared
/// `SearchableFixtureItem`: a trip-planning tool's id and a description of
/// what it does.
public typealias TripPlanningTool = SearchableFixtureItem

/// The trip-planning catalog `Librarian` selects over -- small enough that
/// its assembled prefix always stays under `SelectionConfig`'s default
/// capacity, so the cached-root + fork-per-call path always runs (plan.md
/// §6's "under budget" case, not the over-budget one `BigCatalog`
/// demonstrates).
public let tripPlanningCatalog: [TripPlanningTool] = [
    TripPlanningTool(id: "tripCities", block: "Lists every city on the user's upcoming trip itinerary, in visit order."),
    TripPlanningTool(id: "weather", block: "Looks up the current weather conditions, including temperature, for a named city."),
    TripPlanningTool(id: "currency", block: "Converts an amount between two currencies for trip budgeting."),
    TripPlanningTool(id: "packingList", block: "Suggests a packing list based on trip destinations and expected weather."),
    TripPlanningTool(id: "flightStatus", block: "Checks the current status of a booked flight by its confirmation number."),
]

/// The intent-level query this example is built around: answering it
/// requires picking both `tripCities` (which cities to check) and `weather`
/// (comparing their conditions) -- no single catalog item answers it alone.
public let librarianQuery = "the warmest city on my trip"

// MARK: - GPU-free catalog print

/// Prints the trip-planning catalog, one line per tool -- the surface
/// `runLibrarianSelection(query:config:limit:)` then selects over, printed
/// first so the selected ids can be read against the whole catalog.
public func printCatalog() {
    print("Trip-planning catalog (\(tripPlanningCatalog.count) tools):")
    for tool in tripPlanningCatalog {
        print("- \(tool.id): \(tool.block)")
    }
}

// MARK: - GPU-free selection

/// The ids the scripted demo session always names, and so the ids
/// `runLibrarianSelection(query:config:limit:)` returns for `librarianQuery`:
/// the two tools that query genuinely needs, which is what this example is
/// here to show.
public let librarianSelectedIds = ["tripCities", "weather"]

/// Runs `query` against `tripPlanningCatalog` through the `.selection` tier,
/// building a fresh `MetadataSearcher` over the catalog for this call.
///
/// - Parameters:
///   - query: the search query.
///   - config: the selection tier configuration to search with. Defaults to
///     `ExamplesSupport`'s GPU-free `demoSelectionConfig(selectedIds:
///     capacityCharacterLimit:)` scripted with `librarianSelectedIds` -- the
///     only configuration this example ever builds. Its default capacity
///     comfortably fits this small catalog's assembled prefix, so the
///     cached-root + fork-per-call path runs.
///   - limit: the maximum number of matches to return. Defaults to `5`.
/// - Returns: the selected tools' verbatim matches, at most `limit`.
public func runLibrarianSelection(
    query: String,
    config: SelectionConfig = demoSelectionConfig(selectedIds: librarianSelectedIds),
    limit: Int = 5
) async throws -> [Match<TripPlanningTool>] {
    let searcher = MetadataSearcher(items: tripPlanningCatalog, mode: .selection, selection: config)
    return try await searcher.search(intent: query, limit: limit)
}

