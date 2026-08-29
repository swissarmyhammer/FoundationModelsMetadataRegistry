import ExamplesSupport
import Foundation
import FoundationModelsMetadataRegistry

/// # `SemanticSearch`'s entry logic (plan.md §13 M2).
///
/// `CatalogSearch` plus a third signal: `ExamplesSupport`'s
/// `DeterministicEmbedder` embeds every catalog block and the query, so
/// cosine joins BM25 and trigram in RRF fusion and appears in each match's
/// per-signal breakdown. That embedder hashes text rather than modelling
/// meaning, so this example demonstrates how the cosine signal is wired in,
/// not how well a real model ranks -- which is what keeps it free of network
/// and GPU. `--no-embedder` drops the embedder entirely and demonstrates the
/// graceful keyword-only degradation and its `.embeddingUnavailable`
/// diagnostic.
///
/// Factored into this library target (rather than living directly in
/// `SemanticSearch`'s `main.swift`) so `ExamplesSmokeTests` can import and
/// invoke both paths directly, with no `swift run` subprocess spawning.
///
/// The `GitCommand` fixture type, the `DeterministicEmbedder`, and the match
/// formatter are shared with the other examples via `ExamplesSupport`.

/// The fixture catalog this example searches — `ExamplesSupport.baseGitCommands`
/// (`CatalogSearch`'s five git subcommands) plus `status`, whose block shares
/// the "work" trigrams with `query` ("...the working tree" -- see `query`'s
/// doc) so keyword-only retrieval genuinely surfaces *something* for
/// `--no-embedder`, rather than an empty result set that would make the
/// degradation indistinguishable from "found nothing at all."
public let gitCommands: [GitCommand] =
    baseGitCommands + [
        GitCommand(id: "status", block: "Report the current state of the working tree.")
    ]

/// The paraphrased query this example is built around: it shares no keyword
/// or character trigram with `commit`'s rendered block, so only the cosine
/// signal (once an embedder is configured) can surface `commit` (plan.md §13
/// "a paraphrased query ... ranks where keywords alone miss"). It does share
/// the "work" trigrams with `status`'s block (via "working"), so keyword-only
/// retrieval still returns a real (just semantically wrong) ranking rather
/// than nothing at all -- the degradation `--no-embedder` demonstrates is
/// "misses the right answer," not "returns no answer."
public let query = "save my work"

/// Runs the retrieval search over the fixture catalog, optionally joining
/// the cosine signal when `embedder` is supplied.
///
/// `embedder == nil` behaves exactly like `CatalogSearch`'s keyword-only
/// path, except this async initializer reports `.embeddingUnavailable`
/// through `onDiagnostic` on every such search (plan.md §5) — the
/// degradation `--no-embedder` demonstrates.
///
/// - Parameters:
///   - query: the search query.
///   - embedder: the embedder to embed the catalog and query with, or `nil`
///     for keyword-only retrieval. Defaults to a fresh
///     `DeterministicEmbedder()` — GPU-free, and the only embedder this
///     example ever builds; `--no-embedder` passes `nil` to override it.
///   - limit: the maximum number of matches to return. Defaults to `5`.
///   - onDiagnostic: called for every diagnostic emitted while indexing and
///     searching.
/// - Returns: the ranked matches, best first.
public func runSemanticSearch(
    query: String,
    embedder: (any TextEmbedding)? = DeterministicEmbedder(),
    limit: Int = 5,
    onDiagnostic: @escaping @Sendable (MetadataDiagnostic) -> Void
) async throws -> [Match<GitCommand>] {
    let searcher = await MetadataSearcher(
        items: gitCommands,
        mode: .retrieval,
        embedder: embedder,
        onDiagnostic: onDiagnostic
    )
    return try await searcher.search(intent: query, limit: limit)
}

/// Prints every diagnostic this example's searches emit — `.embeddingUnavailable`
/// is the one `--no-embedder` triggers; every other diagnostic falls back to
/// the package default (plan.md §1 "every degradation is reported, never
/// silent").
///
/// - Parameter diagnostic: the diagnostic to print.
public func printDiagnostic(_ diagnostic: MetadataDiagnostic) {
    printExampleDiagnostic(diagnostic) { diagnostic in
        guard case .embeddingUnavailable = diagnostic else { return nil }
        return "embeddingUnavailable: no embedder configured; degrading to keyword-only (BM25 + trigram)."
    }
}
