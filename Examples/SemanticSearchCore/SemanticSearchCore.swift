import ExamplesSupport
import Foundation
import FoundationModelsMetadataRegistry
import FoundationModelsRouter
import HuggingFace
import MLXHuggingFace
import MLXLMCommon
import Tokenizers

/// # `SemanticSearch`'s entry logic (plan.md §13 M2).
///
/// `CatalogSearch` plus `RoutedEmbedderAdapter`: the cosine signal joins RRF
/// fusion once a live Router resolves a real embedder, so a paraphrased
/// query ("save my work" -> `commit`) ranks where keywords alone miss.
/// `--no-embedder` demonstrates the graceful keyword-only degradation and
/// its `.embeddingUnavailable` diagnostic, GPU-free. Factored into this
/// library target (rather than living directly in `SemanticSearch`'s
/// `main.swift`) so `ExamplesSmokeTests` can import and invoke the
/// `--no-embedder` path directly, with no `swift run` subprocess spawning.
///
/// The `GitCommand` fixture type and the match formatter are shared with
/// `CatalogSearchCore` via `ExamplesSupport`.

/// The fixture catalog this example searches — `ExamplesSupport.baseGitCommands`
/// (`CatalogSearch`'s five git subcommands) plus `status`, whose block shares
/// the "work" trigrams with `query` ("...the working tree" -- see `query`'s
/// doc) so keyword-only retrieval genuinely surfaces *something* for
/// `--no-embedder`, rather than an empty result set that would make the
/// degradation indistinguishable from "found nothing at all."
public let gitCommands: [GitCommand] =
    baseGitCommands + [
        GitCommand(id: "status", summary: "Report the current state of the working tree.")
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
///     for keyword-only retrieval.
///   - limit: the maximum number of matches to return. Defaults to `5`.
///   - onDiagnostic: called for every diagnostic emitted while indexing and
///     searching.
/// - Returns: the ranked matches, best first.
public func runSemanticSearch(
    query: String,
    embedder: (any TextEmbedding)?,
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

/// Resolves a real, on-device embedding model through a live `Router` and
/// wraps it as a `TextEmbedding` — the only path in this example that
/// touches the network/GPU. Downloads (first run) and loads three small
/// `mlx-community` models sized for a demo run (plan.md §13).
///
/// - Returns: a `RoutedEmbedderAdapter` wrapping the resolved profile's
///   embedding model.
/// - Throws: whatever `Router.resolve(_:reporting:)` throws (unsatisfiable
///   profile, download/load failure).
public func resolveLiveEmbedder() async throws -> any TextEmbedding {
    // In production you build a `Router` with a durable `recordingsDir` and
    // a `LiveModelLoader` configured with a real `Downloader`/
    // `TokenizerLoader`. The `MLXHuggingFace` macros `#hubDownloader()` /
    // `#huggingFaceTokenizerLoader()` expand to code that supplies both,
    // backed by the `HuggingFace` and `Tokenizers` packages linked into this
    // target (mirrors FoundationModelsRouter's own
    // `Examples/MultiModelGeneration`).
    let recordingsDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("SemanticSearch-\(UUID().uuidString)", isDirectory: true)
    let router = Router(
        recordingsDir: recordingsDir,
        loader: LiveModelLoader(
            downloader: #hubDownloader(),
            tokenizerLoader: #huggingFaceTokenizerLoader()
        )
    )

    // Router always resolves all three slots together; deliberately tiny,
    // co-resident models keep this demo cheap even though only `embedding`
    // is exercised below.
    let profileDefinition = ProfileDefinition(
        name: "semantic-search-demo",
        description: "Tiny co-resident models sized for a local demo run of the cosine signal.",
        standard: ["mlx-community/SmolLM-135M-Instruct-4bit"],
        flash: ["mlx-community/SmolLM-135M-Instruct-4bit"],
        embedding: ["mlx-community/bge-small-en-v1.5-4bit"]
    )
    let profile = try await router.resolve(profileDefinition, reporting: ResolutionProgress())
    return RoutedEmbedderAdapter(routedEmbedder: profile.embedding)
}

/// Prints every diagnostic this example's searches emit — `.embeddingUnavailable`
/// is the one `--no-embedder` triggers; every other diagnostic falls back to
/// the package default (plan.md §1 "every degradation is reported, never
/// silent").
///
/// - Parameter diagnostic: the diagnostic to print.
public func printDiagnostic(_ diagnostic: MetadataDiagnostic) {
    if case .embeddingUnavailable = diagnostic {
        print(
            "[diagnostic] embeddingUnavailable: no embedder configured; degrading to keyword-only (BM25 + trigram)."
        )
    } else {
        MetadataDiagnostic.log(diagnostic)
    }
}
