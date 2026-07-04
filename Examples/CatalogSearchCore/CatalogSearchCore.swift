import ExamplesSupport
import Foundation
import FoundationModelsMetadataRegistry

/// # `CatalogSearch`'s entry logic (plan.md §13 M1).
///
/// The ~30-line hello world: fixture items conformed to `SearchableMetadata`,
/// a keyword-only `MetadataSearcher(mode: .retrieval)` — no embedder, no
/// model, no session — one query, `Match`es with their per-signal
/// `Signals`. Factored into this library target (rather than living
/// directly in `CatalogSearch`'s `main.swift`) so `ExamplesSmokeTests` can
/// import and invoke it directly, GPU-free, with no `swift run` subprocess
/// spawning.
///
/// The `GitCommand` fixture type and the match formatter are shared with
/// `SemanticSearchCore` via `ExamplesSupport`; only the fixture catalog and
/// the search entry point live here.

/// The fixture catalog `CatalogSearch` searches: five common git
/// subcommands — the shared `ExamplesSupport.baseGitCommands` prefix as-is.
public let gitCommands: [GitCommand] = baseGitCommands

/// Runs the M1 core over the fixture catalog: a keyword-only
/// `MetadataSearcher(mode: .retrieval)` fusing BM25 + character-trigram Dice
/// via RRF (plan.md §5) — no embedder, no model, no session.
///
/// - Parameters:
///   - query: the search query.
///   - limit: the maximum number of matches to return. Defaults to `5`.
/// - Returns: the ranked matches, best first.
public func runCatalogSearch(query: String, limit: Int = 5) async throws -> [Match<GitCommand>] {
    let searcher = MetadataSearcher(items: gitCommands, mode: .retrieval)
    return try await searcher.search(intent: query, limit: limit)
}
