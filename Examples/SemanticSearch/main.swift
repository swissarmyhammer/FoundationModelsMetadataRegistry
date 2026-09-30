import ExamplesSupport
import FoundationModelsExtras
import FoundationModelsMetadataRegistry

// # SemanticSearch: add an embedding model to keyword search.
//
// The same git-subcommand catalog as `CatalogSearch`, but the searcher also
// has an embedding model. The model embeds each catalog block and the query,
// so a third signal, cosine similarity, joins BM25 and trigram in the fusion.
// Each printed match shows the value of the cosine signal.
//
// The query "save my work" has no keyword in common with the `commit`
// entry. Thus the keyword signals cannot rank `commit` for this query, and
// the cosine signal is the only signal that can. The example prints the
// ranking of the model as it is.
//
// The embedder is `exampleEmbedder` of ExamplesSupport: a `PooledEmbedder` of
// FoundationModelsExtras for Qwen3 Embedding 0.6B, 4-bit, from the Hugging
// Face hub. The embedder loads nothing when you make it. The first search
// embeds the catalog, and then `ModelPool.shared` loads the model. The first
// run downloads the weights (about 0.3 GB) into the Hugging Face cache; a
// later run loads them from the cache.
//
// Run with `--no-embedder` to search without an embedding model. Then the
// searcher uses the keyword signals only, and it reports
// `.embeddingUnavailable` through its diagnostic callback.
//
// Run with `swift run --package-path Examples SemanticSearch` or
// `swift run --package-path Examples SemanticSearch --no-embedder`.

/// The catalog: the shared git subcommands, plus `status`.
let catalog = baseGitCommands + [
    GitCommand(id: "status", block: "Report the current state of the working tree."),
]

let query = "save my work"
let noEmbedder = CommandLine.arguments.contains("--no-embedder")
Report.write("Query: \"\(query)\"\(noEmbedder ? " (--no-embedder)" : "")\n")

/// Writes the one diagnostic that this example is about to the report, and logs each other one.
let printDiagnostic: @Sendable (MetadataDiagnostic) -> Void = { diagnostic in
    if case .embeddingUnavailable = diagnostic {
        Report.write("[diagnostic] embeddingUnavailable: no embedder configured; using keyword signals only.")
    } else {
        MetadataDiagnostic.log(diagnostic)
    }
}

/// The shared embedding model of the examples, or `nil` for `--no-embedder`.
let embedder: PooledEmbedder? = noEmbedder ? nil : exampleEmbedder

let searcher = MetadataSearcher(
    items: catalog,
    mode: .retrieval,
    embedder: embedder,
    onDiagnostic: printDiagnostic,
)
let matches = try await searcher.search(intent: query, limit: 5)
Report.write(formattedMatches(matches: matches))
