import Foundation
import FoundationModelsMetadataRegistry

// # Shared types and helpers for the examples.
//
// A simple catalog item type, a small catalog of git subcommands, and a
// formatter that prints ranked matches with their signals.

/// A simple `SearchableMetadata` item: a stable id and a `block` of text. The
/// block is both the description of the item and the text that the searcher
/// indexes.
///
/// Each example gives this type a name that fits its catalog, for example
/// `TripPlanningTool` or `Tool`.
public struct SearchableFixtureItem: SearchableMetadata {
    /// The stable id of the item, unique in its catalog.
    public let id: String

    /// The description of the item, which is also the text that the searcher indexes.
    public let block: String

    /// Creates one item.
    ///
    /// - Parameters:
    ///   - id: the stable id of the item.
    ///   - block: the description of the item.
    public init(id: String, block: String) {
        self.id = id
        self.block = block
    }

    /// Renders this item to the text that the searcher indexes: its block.
    ///
    /// - Returns: the block text of the item.
    public func renderBlock() -> String {
        block
    }
}

/// A git subcommand: its name and a one-line description.
public typealias GitCommand = SearchableFixtureItem

/// A catalog of five common git subcommands.
public let baseGitCommands: [GitCommand] = [
    GitCommand(id: "commit", block: "Record staged changes as a new snapshot in the repository history."),
    GitCommand(id: "push", block: "Upload local branch history to a remote server."),
    GitCommand(id: "pull", block: "Download and merge remote branch history."),
    GitCommand(id: "branch", block: "List, create, or delete lines of independent development."),
    GitCommand(id: "stash", block: "Temporarily set aside uncommitted edits to switch tasks."),
]

/// Formats ranked matches, one line each, with the value of each signal.
///
/// - Parameter matches: the matches to format, in rank order.
/// - Returns: one line for each match, joined by line breaks.
public func formattedMatches(matches: [Match<some SearchableMetadata>]) -> String {
    matches.enumerated().map { index, match in
        let breakdown =
            match.signals.map {
                String(format: "bm25=%.3f trigram=%.3f cosine=%.3f", $0.bm25, $0.trigram, $0.cosine)
            } ?? "no signals"
        return String(format: "%d. %@  score=%.3f  [%@]", index + 1, match.id, match.score, breakdown)
    }.joined(separator: "\n")
}
