import ExamplesSupport
import SemanticSearchCore

/// # `CatalogSearch` plus a cosine signal (plan.md §13 M2).
///
/// `SemanticSearchCore` embeds the fixture catalog and the query with
/// `ExamplesSupport`'s `DeterministicEmbedder`, so cosine joins BM25 and
/// trigram in RRF fusion and appears in every printed per-signal breakdown.
/// Run with `--no-embedder` to drop the embedder entirely and watch the
/// graceful keyword-only degradation and its `.embeddingUnavailable`
/// diagnostic instead. Both paths are GPU-free and need no network. Run with
/// `swift run SemanticSearch` or `swift run SemanticSearch --no-embedder`.
///
/// The actual search logic lives in `SemanticSearchCore` so
/// `ExamplesSmokeTests` can invoke both paths directly; this file is just the
/// runnable entry point.

let noEmbedder = CommandLine.arguments.contains("--no-embedder")
print("Query: \"\(query)\"\(noEmbedder ? " (--no-embedder)" : "")\n")

// `--no-embedder` passes `nil` to override `runSemanticSearch`'s GPU-free
// `DeterministicEmbedder` default, so cosine drops out of fusion entirely.
let matches = try await runSemanticSearch(
    query: query,
    embedder: noEmbedder ? nil : DeterministicEmbedder(),
    onDiagnostic: printDiagnostic
)
print(formattedMatches(matches: matches))
