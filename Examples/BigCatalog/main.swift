import ExamplesSupport
import Foundation
import FoundationModelsMetadataRegistry

// # BigCatalog: search a catalog of 1,000 entries.
//
// This example makes a synthetic catalog of 1,000 entries, with URIs as
// ids, and searches it two ways.
//
// 1. Retrieval. A keyword-only `MetadataSearcher` in `.retrieval` mode
//    indexes the catalog in memory and searches it. The example prints how
//    long the index and the search took together.
// 2. Selection over budget. A `MetadataSearcher` in `.selection` mode uses
//    the on-device Apple Intelligence model. The prefix of 1,000 entries is
//    too large for one prompt of that model, so the searcher divides the
//    catalog into runs that each fit the capacity limit, and prompts one new
//    session for each run. Each id goes to exactly one prompt, and no entry
//    is cut.
//
// One entry, the "needle", has words that no other entry has, so the query
// has exactly one correct result. The selected entries are what the model
// selects in each run, so they can change from one run to the next.
//
// Run with `swift run --package-path Examples BigCatalog`.

/// A catalog entry: a URI id and a short synthetic description.
typealias BigCatalogItem = SearchableFixtureItem

/// The id of the one entry that answers the query.
let needleId = "https://example.com/modules/quantum-flux-capacitor"

/// The query. Its words occur in the needle entry only.
let query = "quantum flux capacitor calibration"

/// The topics that the filler entries use in turn, to give the catalog some
/// variety of words.
let topics = [
    "parser", "renderer", "scheduler", "cache", "logger",
    "validator", "compiler", "router", "indexer", "formatter",
]

/// The catalog: 999 filler entries, then the needle.
let catalog: [BigCatalogItem] =
    (0 ..< 999).map { index in
        let topic = topics[index % topics.count]
        return BigCatalogItem(
            id: "https://example.com/modules/module-\(index)",
            block: "Module #\(index): a \(topic) component for \(topic)-related subsystem \(index % 37) tasks.",
        )
    } + [
        BigCatalogItem(
            id: needleId,
            block: "Provides quantum flux capacitor calibration routines for temporal synchronization.",
        ),
    ]

print("Synthetic catalog size: \(catalog.count) entries")
print("Query: \"\(query)\"\n")

// Retrieval: time the index and the search together.
let start = Date()
let retrieval = MetadataSearcher(items: catalog, mode: .retrieval)
let retrievalMatches = try await retrieval.search(intent: query, limit: 10)
let elapsed = Date().timeIntervalSince(start)
print(String(format: "Retrieval over %d entries took %.4fs (in memory, no GPU)\n", catalog.count, elapsed))
print(formattedMatches(matches: retrievalMatches))

// Selection over budget. A capacity of 8,000 characters fits one prompt of
// the on-device model with space for its answer. The prefix of 1,000
// entries is much larger, so the searcher prompts one session for each run.
requireSystemLanguageModel()
print("\nRunning the over-budget selection query (on-device model, one prompt for each run)...\n")
let selection = MetadataSearcher(
    items: catalog,
    mode: .selection,
    selection: exampleSelectionConfig(capacityCharacterLimit: 8000),
)
let selectedMatches = try await selection.search(intent: query, limit: 10)
print(formattedMatches(matches: selectedMatches))
