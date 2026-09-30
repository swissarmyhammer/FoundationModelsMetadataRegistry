import ExamplesSupport
import FoundationModelsMetadataRegistry

// # CatalogSearch: keyword search over a small catalog.
//
// The smallest use of the library. A catalog of git subcommands conforms to
// `SearchableMetadata`, and a `MetadataSearcher` in `.retrieval` mode ranks
// them for one query. The searcher fuses two keyword signals, BM25 and
// character-trigram similarity, with reciprocal rank fusion. There is no
// embedder, no model and no session, so this example needs no GPU and no
// network.
//
// Each printed match shows its rank, its id, its fused score and the value
// of each signal. The cosine signal is always 0 here, because no embedder
// is configured.
//
// Run with `swift run --package-path Examples CatalogSearch`.

let query = "commit changes to git"
Report.write("Query: \"\(query)\"\n")

let searcher = MetadataSearcher(items: baseGitCommands, mode: .retrieval)
let matches = try await searcher.search(intent: query, limit: 5)
Report.write(formattedMatches(matches: matches))
