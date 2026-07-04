import ExamplesSupport
import Foundation
import FoundationModelsMetadataRegistry
import LiveRouterSupport

/// # `Librarian`'s entry logic (plan.md §13 M8): `.selection` mode end-to-end.
///
/// Generalizes Multitool's shipped `Librarian` (plan.md §6's namesake) over
/// this package's own catalog: a cached root session, seeded once with the
/// whole (under-budget) trip-planning catalog, `fork()`s a fresh child per
/// query so the prefix's KV cache is prefilled once and inherited per call
/// (plan.md §6). Output is ids-only, constrained by an xgrammar id-enum
/// grammar so the model is structurally incapable of inventing a tool that
/// doesn't exist; `MetadataSearcher` maps the returned ids back through the
/// catalog to verbatim blocks -- never model-generated text.
///
/// `librarianQuery` ("the warmest city on my trip") is an intent-level query:
/// no single catalog item answers it directly, so answering it requires
/// picking *both* `tripCities` (to know which cities to check) and
/// `weather` (to compare their conditions) -- exactly the task-decomposition
/// reasoning plan.md §6 says lexical/semantic ranking alone can't do.
///
/// The model run is gated behind
/// `ExamplesSupport.isMetadataRegistryIntegrationEnabled` -- the same opt-in
/// env var the gated `Integration/RouterIntegrationTests.swift` suite uses.
/// Without it, `printCatalog()` prints the catalog and this example exits 0,
/// GPU-free.

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

/// Prints the trip-planning catalog, one line per tool -- the GPU-free path
/// this example runs when
/// `ExamplesSupport.isMetadataRegistryIntegrationEnabled` is unset.
public func printCatalog() {
    print("Trip-planning catalog (\(tripPlanningCatalog.count) tools):")
    for tool in tripPlanningCatalog {
        print("- \(tool.id): \(tool.block)")
    }
}

// MARK: - Gated selection (real model)

/// Runs `query` against `tripPlanningCatalog` through the `.selection` tier,
/// building a fresh `MetadataSearcher` over the catalog for this call.
///
/// - Parameters:
///   - query: the search query.
///   - config: the selection tier configuration to search with -- built by
///     `resolveLiveSelectionConfig()` for a real model run.
///   - limit: the maximum number of matches to return. Defaults to `5`.
/// - Returns: the selected tools' verbatim matches, at most `limit`.
public func runLibrarianSelection(
    query: String,
    config: SelectionConfig,
    limit: Int = 5
) async throws -> [Match<TripPlanningTool>] {
    let searcher = MetadataSearcher(items: tripPlanningCatalog, mode: .selection, selection: config)
    return try await searcher.search(intent: query, limit: limit)
}

/// Resolves a real, on-device model profile through a live `Router` and
/// builds a `SelectionConfig` whose session factory constrains every guided
/// session to `tripPlanningCatalog`'s id-enum grammar -- the only path in
/// this example that touches the network/GPU.
///
/// - Returns: a `SelectionConfig` ready to drive `runLibrarianSelection(
///   query:config:limit:)`.
/// - Throws: whatever `Router.resolve(_:reporting:)` throws, or an encoding
///   error from `idEnumGrammar(ids:)` (not expected for a plain array of
///   strings).
public func resolveLiveSelectionConfig() async throws -> SelectionConfig {
    try await buildSelectionConfig(
        demoLabel: "Librarian",
        name: "librarian-demo",
        description: "Tiny co-resident models sized for a local demo run of the selection tier.",
        ids: tripPlanningCatalog.map(\.id)
    )
}

