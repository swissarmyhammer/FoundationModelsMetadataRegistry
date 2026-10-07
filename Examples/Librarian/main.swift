import ExamplesSupport
import FoundationModelsExtras
import FoundationModelsMetadataRegistry

// # Librarian: let a model select the tools for a request.
//
// A `MetadataSearcher` in `.selection` mode gives the whole catalog to a
// language-model session and asks it which items the request needs. The
// catalog prefix is the instructions of the session. Each query makes a new
// session, so no query sees the turns of another. The session returns ids
// only. The searcher maps each id back to its catalog
// block, so each result is catalog text, not generated text. When the model
// gives an id that is not in the catalog, the searcher drops that id and
// reports `.unknownSelectedId` through its diagnostic callback.
//
// The query "the warmest city on my trip" needs two tools: `tripCities` to
// get the cities, and `weather` to compare them. No single tool answers it,
// and keyword ranking alone cannot find that pair. The model must reason
// about the task.
//
// The model is `exampleSelectionModel` of ExamplesSupport: a `PooledModel` of
// FoundationModelsExtras for Qwen3 4B, 4-bit, from the Hugging Face hub. The
// model loads nothing when you make it. The first search sends a prompt to
// the model, and then `ModelPool.shared` loads the model. The first run
// downloads the weights (about 2.3 GB) into the Hugging Face cache; a later
// run loads them from the cache. The example prints what the model selects,
// and the selection can change from one run to the next.
//
// Run with `swift run --package-path Examples Librarian`.

/// A trip-planning tool: its id and a description of what it does.
typealias TripPlanningTool = SearchableFixtureItem

/// The trip-planning catalog. It is small, so its prefix fits the default
/// capacity of `SelectionConfig`, and each search sends one prompt that
/// shows the whole catalog.
let catalog: [TripPlanningTool] = [
  TripPlanningTool(
    id: "tripCities", block: "Lists every city on the user's trip itinerary, in visit order."),
  TripPlanningTool(
    id: "weather",
    block: "Looks up current weather conditions, including temperature, for a named city.",
  ),
  TripPlanningTool(
    id: "currency", block: "Converts an amount between two currencies for trip budgeting."),
  TripPlanningTool(
    id: "packingList",
    block: "Suggests a packing list based on the trip's destinations and weather."),
  TripPlanningTool(
    id: "flightStatus", block: "Checks the status of a booked flight by its confirmation number."),
]

Report.write("Trip-planning catalog (\(catalog.count) tools):")
for tool in catalog {
  Report.write("- \(tool.id): \(tool.block)")
}

let query = "the warmest city on my trip"
Report.write("\nQuery: \"\(query)\"\n")

let searcher = MetadataSearcher(
  items: catalog,
  mode: .selection,
  selection: SelectionConfig(model: exampleSelectionModel),
)
let matches = try await searcher.search(intent: query, limit: 5)
Report.write(formattedMatches(matches: matches))
