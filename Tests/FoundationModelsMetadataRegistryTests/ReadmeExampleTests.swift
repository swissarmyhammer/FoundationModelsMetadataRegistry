import Testing

import FoundationModelsMetadataRegistry

/// Runs the README's usage example and asserts the ranking it advertises.
///
/// The README is the first thing a reader of this package sees, and nothing
/// else compiles it. Transcribing the example here gives it a compiler: a
/// change to the public API that would break the example breaks this target's
/// build, and a change to ranking that would demote `commit` fails
/// `commitRanksFirstForTheReadmeQuery()`.
///
/// A plain `import` — not `@testable` — on purpose. The example is what a
/// consumer writes, so it must reach every type it names through the public
/// surface alone.
@Suite("README usage example")
struct ReadmeExampleTests {
    /// The catalog item type the README's example declares, transcribed from
    /// it.
    ///
    /// Nested inside the suite rather than declared at file scope because
    /// `ExamplesSupport` exports a `GitCommand` of its own, and two of that
    /// name visible in one test target would silently shadow each other.
    struct GitCommand: SearchableMetadata {
        /// This command's id — the README example's join key, and what its
        /// printed output names.
        let id: String

        /// This command's one-line description, the text retrieval scores.
        let block: String

        /// Renders the block retrieval indexes, per `SearchableMetadata`.
        ///
        /// - Returns: the block, verbatim.
        func renderBlock() -> String { block }
    }

    /// The catalog the README's example searches, transcribed from it.
    private static let commands = [
        GitCommand(id: "commit", block: "Record staged changes as a new snapshot in the repository history."),
        GitCommand(id: "push", block: "Upload local branch history to a remote server."),
        GitCommand(id: "pull", block: "Download and merge remote branch history."),
        GitCommand(id: "branch", block: "List, create, or delete lines of independent development."),
        GitCommand(id: "stash", block: "Temporarily set aside uncommitted edits to switch tasks."),
    ]

    /// The intent the README's example searches for.
    private static let intent = "commit changes to git"

    /// The result limit the README's example asks for.
    private static let limit = 3

    /// The id the README says takes first rank for `intent`.
    private static let topRankedID = "commit"

    /// The README, relative to the repository root.
    private static let readmeFileName = "README.md"

    @Test("the README example returns its limit of matches, commit first")
    func commitRanksFirstForTheReadmeQuery() async throws {
        let searcher = MetadataSearcher(items: Self.commands, mode: .retrieval)
        let matches = try await searcher.search(intent: Self.intent, limit: Self.limit)

        let rankedIDs = matches.map(\.id)
        #expect(
            rankedIDs.count == Self.limit,
            "The README shows a limit of \(Self.limit) matches; got \(rankedIDs)."
        )
        #expect(
            rankedIDs.first == Self.topRankedID,
            """
            The README says \(Self.topRankedID) takes the first rank for "\(Self.intent)"; \
            the ranking was \(rankedIDs).
            """
        )
    }

    @Test("the README still spells the example this suite runs")
    func readmeStillSpellsThisExample() throws {
        let readme = try RepositoryFiles.text(at: Self.readmeFileName)
        var missing: [String] = []
        for line in Self.exampleLines() where !readme.contains(line) {
            missing.append(line)
        }
        #expect(
            missing.isEmpty,
            """
            This suite runs the README's example, so every line of it must still be in \
            \(Self.readmeFileName). Update both together; these lines are no longer there: \
            \(missing)
            """
        )
    }

    /// Spells the lines of the README's example this suite reproduces, in the
    /// README's own formatting.
    ///
    /// Built from the suite's fixtures rather than written out a second time,
    /// so the two cannot disagree: changing a fixture changes what the drift
    /// guard looks for.
    ///
    /// - Returns: one line of the README's Swift code block per entry.
    private static func exampleLines() -> [String] {
        commands.map { #"GitCommand(id: "\#($0.id)", block: "\#($0.block)")"# }
            + [
                "let searcher = MetadataSearcher(items: commands, mode: .retrieval)",
                #"let matches = try await searcher.search(intent: "\#(intent)", limit: \#(limit))"#,
            ]
    }
}
