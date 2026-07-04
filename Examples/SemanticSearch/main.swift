import ExamplesSupport
import Foundation
import SemanticSearchCore

/// # `CatalogSearch` plus `RoutedEmbedderAdapter` (plan.md §13 M2).
///
/// The cosine signal joins RRF fusion once a live Router resolves a real
/// embedder, so a paraphrased query ("save my work" -> `commit`) now ranks
/// where keywords alone miss. Run with `--no-embedder` to watch the graceful
/// keyword-only degradation and its `.embeddingUnavailable` diagnostic —
/// that path is GPU-free and needs no network. The default path downloads
/// (first run) and loads three small `mlx-community` models and needs
/// Apple silicon + network (plan.md §13 "Router-backed ones compile in CI
/// and run locally against tiny mlx-community models"). Run with `swift run
/// SemanticSearch` or `swift run SemanticSearch --no-embedder`.
///
/// The actual search logic lives in `SemanticSearchCore` so
/// `ExamplesSmokeTests` can invoke its GPU-free path directly; this file is
/// just the runnable entry point.

let noEmbedder = CommandLine.arguments.contains("--no-embedder")
print("Query: \"\(query)\"\(noEmbedder ? " (--no-embedder)" : "")\n")

if noEmbedder {
    let matches = try await runSemanticSearch(query: query, embedder: nil, onDiagnostic: printDiagnostic)
    print(formatMatches(matches))
} else {
    let embedder = try await resolveLiveEmbedder()
    let matches = try await runSemanticSearch(query: query, embedder: embedder, onDiagnostic: printDiagnostic)
    print(formatMatches(matches))
}
