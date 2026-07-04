import Foundation
import FoundationModelsMetadataRegistry

/// # Shared fixture types and helpers for `Examples/` (plan.md §13).
///
/// `CatalogSearchCore` and `SemanticSearchCore` both search the same tiny
/// git-subcommand catalog and both print matches the same way. Rather than
/// maintain two copies of the fixture type, the common fixture prefix, and
/// the formatter, both `*Core` targets depend on this plain library target
/// and share these pieces; each core still owns its own divergent/additional
/// fixture items locally (`SemanticSearchCore` appends a `status` item so its
/// keyword-only degradation path has something real to rank).

/// A tiny catalog item: a git subcommand and its one-line description.
///
/// The description text IS the search surface (`SearchableMetadata.renderBlock()`).
public struct GitCommand: SearchableMetadata {
    /// The git subcommand's name — e.g. `"commit"` — and its `SearchableMetadata` id.
    public let id: String

    /// The subcommand's one-line description, which is also its rendered search surface.
    public let summary: String

    /// Creates one git subcommand fixture item.
    ///
    /// - Parameters:
    ///   - id: the subcommand's name.
    ///   - summary: the subcommand's one-line description.
    public init(id: String, summary: String) {
        self.id = id
        self.summary = summary
    }

    /// Renders this item to its search surface: the subcommand's summary text.
    ///
    /// - Returns: the item's summary text.
    public func renderBlock() -> String { summary }
}

/// The fixture catalog prefix both examples search: five common git subcommands.
///
/// `CatalogSearchCore` uses this as-is; `SemanticSearchCore` appends its own
/// `status` item on top.
public let baseGitCommands: [GitCommand] = [
    GitCommand(id: "commit", summary: "Record staged changes as a new snapshot in the repository history."),
    GitCommand(id: "push", summary: "Upload local branch history to a remote server."),
    GitCommand(id: "pull", summary: "Download and merge remote branch history."),
    GitCommand(id: "branch", summary: "List, create, or delete lines of independent development."),
    GitCommand(id: "stash", summary: "Temporarily set aside uncommitted edits to switch tasks."),
]

/// Formats ranked matches, one line each, with their per-signal breakdown.
///
/// - Parameter matches: the matches to format, in ranked order.
/// - Returns: one formatted line per match, joined by newlines.
public func formattedMatches(matches: [Match<GitCommand>]) -> String {
    matches.enumerated().map { index, match in
        let breakdown =
            match.signals.map {
                String(format: "bm25=%.3f trigram=%.3f cosine=%.3f", $0.bm25, $0.trigram, $0.cosine)
            } ?? "no signals"
        return String(format: "%d. %@  score=%.3f  [%@]", index + 1, match.id, match.score, breakdown)
    }.joined(separator: "\n")
}
