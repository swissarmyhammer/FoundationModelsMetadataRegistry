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

/// A generic `SearchableMetadata` fixture item: a stable id paired with a
/// `block` of text that is both its description and its rendered search
/// surface (`renderBlock()`).
///
/// `GitCommand` (this file), `BigCatalogItem` (`BigCatalogCore`),
/// `HotReloadTool` (`HotReloadCore`), and `TripPlanningTool` (`LibrarianCore`)
/// were four independent types, identical except for their name and the
/// property name holding the description text (`summary` vs `block`). This
/// single generic type replaces all four; each `*Core` target aliases it to
/// its own domain-flavored name for readability at call sites, while keeping
/// its own catalog *data* (the literal fixture arrays) local.
public struct SearchableFixtureItem: SearchableMetadata {
    /// The item's stable id — unique within its catalog.
    public let id: String

    /// The item's description, which is also its rendered search surface.
    public let block: String

    /// Creates one fixture item.
    ///
    /// - Parameters:
    ///   - id: the item's stable id.
    ///   - block: the item's description, also its rendered search surface.
    public init(id: String, block: String) {
        self.id = id
        self.block = block
    }

    /// Renders this item to its search surface: its description block.
    ///
    /// - Returns: the item's block text.
    public func renderBlock() -> String { block }
}

/// `CatalogSearchCore`'s and `SemanticSearchCore`'s domain-flavored alias for
/// `SearchableFixtureItem`: a git subcommand's name and its one-line
/// description.
public typealias GitCommand = SearchableFixtureItem

/// The fixture catalog prefix both examples search: five common git subcommands.
///
/// `CatalogSearchCore` uses this as-is; `SemanticSearchCore` appends its own
/// `status` item on top.
public let baseGitCommands: [GitCommand] = [
    GitCommand(id: "commit", block: "Record staged changes as a new snapshot in the repository history."),
    GitCommand(id: "push", block: "Upload local branch history to a remote server."),
    GitCommand(id: "pull", block: "Download and merge remote branch history."),
    GitCommand(id: "branch", block: "List, create, or delete lines of independent development."),
    GitCommand(id: "stash", block: "Temporarily set aside uncommitted edits to switch tasks."),
]

/// Formats ranked matches, one line each, with their per-signal breakdown.
///
/// Generic over any `SearchableMetadata` item — not just `GitCommand` — so
/// every `Examples/` target (`CatalogSearch`/`SemanticSearch`'s git-command
/// catalog, and `Librarian`/`BigCatalog`/`HotReload`'s own domain-specific
/// catalogs) shares this one formatter instead of each maintaining its own
/// copy.
///
/// - Parameter matches: the matches to format, in ranked order.
/// - Returns: one formatted line per match, joined by newlines.
public func formattedMatches<Item: SearchableMetadata>(matches: [Match<Item>]) -> String {
    matches.enumerated().map { index, match in
        let breakdown =
            match.signals.map {
                String(format: "bm25=%.3f trigram=%.3f cosine=%.3f", $0.bm25, $0.trigram, $0.cosine)
            } ?? "no signals"
        return String(format: "%d. %@  score=%.3f  [%@]", index + 1, match.id, match.score, breakdown)
    }.joined(separator: "\n")
}

// MARK: - Gated real-model opt-in (plan.md §13 M8)

/// The opt-in environment variable that gates every real-model path across
/// `Examples/`: `Librarian`, `BigCatalog`, and `HotReload` each read this
/// exact name to decide between their GPU-free/degraded path (unset, the
/// default -- every example exits 0 with no network/GPU) and their real,
/// live-Router-backed path (set). The identical literal the gated
/// `Integration/RouterIntegrationTests.swift` suite gates its own real-model
/// scenarios behind (`metadataRegistryIntegrationEnvVar` there) -- sharing
/// one name means a single opt-in switch controls both the gated test suite
/// and a real-model run of any of these three examples.
public let metadataRegistryIntegrationEnvVar = "METADATA_REGISTRY_INTEGRATION_TESTS"

/// Whether the gated real-model path is enabled for this run.
public var isMetadataRegistryIntegrationEnabled: Bool {
    ProcessInfo.processInfo.environment[metadataRegistryIntegrationEnvVar] != nil
}

// MARK: - Shared diagnostic printing (plan.md §1)

/// Prints one diagnostic the way every `Examples/` target's own
/// `printDiagnostic(_:)` wants to: special-casing the one diagnostic case
/// central to that example's degradation story with a custom message, and
/// falling back to the package default `MetadataDiagnostic.log(_:)` for
/// every other diagnostic (plan.md §1 "every degradation is reported, never
/// silent").
///
/// `BigCatalogCore` (`.retrievalCut`) and `SemanticSearchCore`
/// (`.embeddingUnavailable`) each defined their own `printDiagnostic(_:)`
/// implementing this identical check-case/print-message/else-log pattern,
/// differing only in which case they special-case and what they print for
/// it. This shared helper is that pattern, parameterized: each `*Core`
/// target's own `printDiagnostic(_:)` calls it with a closure that pattern-
/// matches its one diagnostic case and returns the message to print, or
/// `nil` for every other case.
///
/// - Parameters:
///   - diagnostic: the diagnostic to print.
///   - describe: given `diagnostic`, returns the message to print for it if
///     it's the case this call special-cases, or `nil` to fall back to
///     `MetadataDiagnostic.log(_:)`.
public func printExampleDiagnostic(
    _ diagnostic: MetadataDiagnostic,
    describingSpecialCase describe: (MetadataDiagnostic) -> String?
) {
    if let message = describe(diagnostic) {
        print("[diagnostic] \(message)")
    } else {
        MetadataDiagnostic.log(diagnostic)
    }
}
