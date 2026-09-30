import ExamplesSupport
import FoundationModelsExtras
import FoundationModelsMetadataRegistry

// # Librarian: let a model select the tools for a request.
//
// A `MetadataSearcher` in `.selection` mode gives the whole catalog to a
// language-model session and asks it which items the request needs. The
// searcher seeds one root session with the catalog, and forks that session
// for each query, so the catalog prefix is processed one time only. The
// session returns ids only. The searcher maps each id back to its catalog
// block, so each result is catalog text, not generated text. When the model
// gives an id that is not in the catalog, the searcher drops that id and
// reports `.unknownSelectedId` through its diagnostic callback.
//
// The query "the warmest city on my trip" needs two tools: `tripCities` to
// get the cities, and `weather` to compare them. No single tool answers it,
// and keyword ranking alone cannot find that pair. The model must reason
// about the task.
//
// The model is a `PooledModel` of FoundationModelsExtras for Qwen3 4B,
// 4-bit, from the Hugging Face hub. The model loads nothing when you make
// it. The first search asks the factory for a session, and then
// `ModelPool.shared` loads the model. The first run downloads the weights
// (about 2.3 GB) into the Hugging Face cache; a later run loads them from
// the cache. The example prints what the model selects, and the selection
// can change from one run to the next.
//
// Run with `swift run --package-path Examples Librarian`.

/// A trip-planning tool: its id and a description of what it does.
typealias TripPlanningTool = SearchableFixtureItem

/// The trip-planning catalog. It is small, so its prefix fits the default
/// capacity of `SelectionConfig`, and the searcher uses one cached root
/// session.
let catalog: [TripPlanningTool] = [
    TripPlanningTool(id: "tripCities", block: "Lists every city on the user's trip itinerary, in visit order."),
    TripPlanningTool(
        id: "weather",
        block: "Looks up current weather conditions, including temperature, for a named city.",
    ),
    TripPlanningTool(id: "currency", block: "Converts an amount between two currencies for trip budgeting."),
    TripPlanningTool(id: "packingList", block: "Suggests a packing list based on the trip's destinations and weather."),
    TripPlanningTool(id: "flightStatus", block: "Checks the status of a booked flight by its confirmation number."),
]

print("Trip-planning catalog (\(catalog.count) tools):")
for tool in catalog {
    print("- \(tool.id): \(tool.block)")
}

let query = "the warmest city on my trip"
print("\nQuery: \"\(query)\"\n")

/// The selection model. It loads nothing until the first session.
let qwen = PooledModel(ref: "mlx-community/Qwen3-4B-4bit")

let searcher = MetadataSearcher(
    items: catalog,
    mode: .selection,
    selection: SelectionConfig(model: { try await qwen.session(instructions: $0) }),
)
let matches = try await searcher.search(intent: query, limit: 5)
print(formattedMatches(matches: matches))
