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

/// A tiny catalog item: a git subcommand and its one-line description — the
/// text IS the search surface (`SearchableMetadata.renderBlock()`).
public struct GitCommand: SearchableMetadata {
    public let id: String
    public let summary: String

    public init(id: String, summary: String) {
        self.id = id
        self.summary = summary
    }

    public func renderBlock() -> String { summary }
}

/// The fixture catalog `CatalogSearch` searches: five common git
/// subcommands.
public let gitCommands: [GitCommand] = [
    GitCommand(id: "commit", summary: "Record staged changes as a new snapshot in the repository history."),
    GitCommand(id: "push", summary: "Upload local branch history to a remote server."),
    GitCommand(id: "pull", summary: "Download and merge remote branch history."),
    GitCommand(id: "branch", summary: "List, create, or delete lines of independent development."),
    GitCommand(id: "stash", summary: "Temporarily set aside uncommitted edits to switch tasks."),
]

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

/// Formats ranked matches, one line each, with their per-signal breakdown.
///
/// - Parameter matches: the matches to format, in ranked order.
/// - Returns: one formatted line per match, joined by newlines.
public func formatMatches(_ matches: [Match<GitCommand>]) -> String {
    matches.enumerated().map { index, match in
        let breakdown =
            match.signals.map {
                String(format: "bm25=%.3f trigram=%.3f cosine=%.3f", $0.bm25, $0.trigram, $0.cosine)
            } ?? "no signals"
        return String(format: "%d. %@  score=%.3f  [%@]", index + 1, match.id, match.score, breakdown)
    }.joined(separator: "\n")
}
