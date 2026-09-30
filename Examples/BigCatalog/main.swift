import ExamplesSupport
import Foundation
import FoundationModelsExtras
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
//    a `PooledModel` of FoundationModelsExtras for Qwen3 4B, 4-bit, from
//    the Hugging Face hub. The prefix of 1,000 entries is larger than the
//    capacity limit, so the searcher divides the catalog into runs that
//    each fit the limit, and prompts one new session for each run. Each id
//    goes to exactly one prompt, and no entry is cut.
//
// One entry, the "needle", has words that no other entry has, so the query
// has exactly one correct result. The example prints what the model selects
// in each run, and the selection can change from one run to the next. When
// the model gives an id that is not in the catalog, the searcher drops that
// id and reports `.unknownSelectedId` through its diagnostic callback.
//
// The model loads nothing when you make it. The first selection prompt asks
// the factory for a session, and then `ModelPool.shared` loads the model.
// The first run downloads the weights (about 2.3 GB) into the Hugging Face
// cache; a later run loads them from the cache.
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

/// The character limit of the prefix of one selection run.
///
/// Qwen3 4B has a native context of 32,768 tokens. The Qwen3 tokenizer
/// gives about 3.9 characters for each token of the entries of this
/// catalog. Thus a prefix of 48,000 characters is about 12,200 tokens, and
/// the other 20,500 tokens of the context keep space for the task prompt,
/// the chat template and the answer. The prefix of all 1,000 entries is
/// about 116,000 characters (about 29,500 tokens). That is too near the
/// context to keep space for the answer, so the searcher divides the catalog
/// into three runs.
let selectionCapacityCharacterLimit = 48_000

/// The selection model. It loads nothing until the first session.
let qwen = PooledModel(ref: "mlx-community/Qwen3-4B-4bit")

print("\nRunning the over-budget selection query (Qwen3 4B, one prompt for each run)...\n")
let selection = MetadataSearcher(
    items: catalog,
    mode: .selection,
    selection: SelectionConfig(
        model: { try await qwen.session(instructions: $0) },
        capacityCharacterLimit: selectionCapacityCharacterLimit,
    ),
)
let selectedMatches = try await selection.search(intent: query, limit: 10)
print(formattedMatches(matches: selectedMatches))
