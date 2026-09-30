import ExamplesSupport
import FoundationModelsMetadataRegistry

// # SemanticSearch: add an embedding model to keyword search.
//
// The same git-subcommand catalog as `CatalogSearch`, but the searcher also
// has an embedding model. The model embeds each catalog block and the query,
// so a third signal, cosine similarity, joins BM25 and trigram in the fusion.
// Each printed match shows the value of the cosine signal.
//
// The query "save my work" has no keyword in common with the `commit`
// entry. Only the cosine signal can find `commit` for it.
//
// The searcher gets the embedding model from `ModelPool.shared` through the
// `LiveModelLoader` of FoundationModelsRouter. The model is a small MLX
// embedding model from the Hugging Face hub; the first run downloads it.
//
// Run with `--no-embedder` to search without an embedding model. Then the
// searcher uses the keyword signals only, and it reports
// `.embeddingUnavailable` through its diagnostic callback. The query shares
// the "work" trigrams with the `status` entry ("working tree"), so the
// keyword-only search still returns a result, but not `commit`.
//
// Run with `swift run --package-path Examples SemanticSearch` or
// `swift run --package-path Examples SemanticSearch --no-embedder`.

/// The catalog: the shared git subcommands, plus `status`.
let catalog = baseGitCommands + [
    GitCommand(id: "status", block: "Report the current state of the working tree."),
]

let query = "save my work"
let noEmbedder = CommandLine.arguments.contains("--no-embedder")
print("Query: \"\(query)\"\(noEmbedder ? " (--no-embedder)" : "")\n")

/// Prints the one diagnostic that this example is about, and logs each other one.
let printDiagnostic: @Sendable (MetadataDiagnostic) -> Void = { diagnostic in
    if case .embeddingUnavailable = diagnostic {
        print("[diagnostic] embeddingUnavailable: no embedder configured; using keyword signals only.")
    } else {
        MetadataDiagnostic.log(diagnostic)
    }
}

let searcher =
    if noEmbedder {
        await MetadataSearcher(items: catalog, mode: .retrieval, embedder: nil, onDiagnostic: printDiagnostic)
    } else {
        try await MetadataSearcher(
            items: catalog,
            mode: .retrieval,
            embeddingModel: exampleEmbeddingModel,
            footprintBytes: exampleEmbeddingFootprintBytes,
            loader: exampleModelLoader(),
            onDiagnostic: printDiagnostic,
        )
    }
let matches = try await searcher.search(intent: query, limit: 5)
print(formattedMatches(matches: matches))
