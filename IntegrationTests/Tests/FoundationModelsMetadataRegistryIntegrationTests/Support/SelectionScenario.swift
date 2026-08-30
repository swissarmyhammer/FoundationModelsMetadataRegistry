import FoundationModels
import FoundationModelsMetadataRegistry
import Testing
import os

/// The selection-tier wiring every real-model scenario in this package drives,
/// and the one diagnostic reading each of them makes.
///
/// Both members arrived inside `ColdSelectionRealModelTests` and moved here
/// when `HotReloadRealModelTests` became their second caller. What differs
/// between the scenarios is the catalog the searcher stands over and when the
/// scenario builds it; the wiring itself is the same in all of them, and a
/// copy of it in each suite would drift.
enum SelectionScenario {
    /// Builds the `.selection`-mode searcher a real-model scenario drives.
    ///
    /// **Why the preamble is stated rather than inherited.**
    /// FoundationModelsRanker defaults `SelectionConfig.preamble` to its own
    /// neutral `.selectionDefault`, so a scenario that left the parameter out
    /// would measure Ranker's prompt instead of this package's. The librarian
    /// text named here is the preamble `^nwt7nz4` measured every intent
    /// against.
    ///
    /// **Why no embedder.** This package ships none, and FoundationModels
    /// exposes no embedding API, so every scenario runs keyword-only and every
    /// selection search reports `.embeddingUnavailable`. See
    /// `expectNoUnknownSelectedId(among:answering:sourceLocation:)` for what
    /// that costs an assertion.
    ///
    /// - Parameters:
    ///   - items: the catalog this searcher indexes, and the id set its
    ///     selection tier answers from.
    ///   - recorded: the sink each diagnostic the searcher reports is appended
    ///     to. An `OSAllocatedUnfairLock` rather than a recorder class: the
    ///     lock is `Sendable` and `Copyable`, so the `@escaping @Sendable`
    ///     callback captures it directly and no suite needs an
    ///     `@unchecked Sendable` conformance of its own to justify.
    /// - Returns: a searcher in `.selection` mode over `items`, with no cached
    ///   root session yet.
    static func makeSearcher(
        over items: [IntegrationItem],
        reporting recorded: OSAllocatedUnfairLock<[MetadataDiagnostic]>
    ) -> MetadataSearcher<IntegrationItem> {
        MetadataSearcher(
            items: items,
            mode: .selection,
            selection: SelectionConfig(
                model: { instructions in
                    LanguageModelSession(model: .default, instructions: instructions)
                },
                preamble: .librarianDefault
            ),
            onDiagnostic: { diagnostic in recorded.withLock { $0.append(diagnostic) } }
        )
    }

    /// Expects that the model, answering `intent`, named no id its catalog
    /// does not hold.
    ///
    /// **Filter for the case; never test the collection for emptiness.**
    /// `.embeddingUnavailable` fires on **every** selection search this
    /// package makes — 55 of 55 runs measured on `^nwt7nz4` — because
    /// `SelectionTier`'s under-budget path calls `retrievalRanking` once per
    /// call to attach a real `score` and `signals`, and that closure reports
    /// the missing embedder. This package wires no embedder, so an assertion
    /// that no diagnostic was recorded would fail on every run, for a reason
    /// that has nothing to do with the defect a scenario guards.
    ///
    /// - Parameters:
    ///   - diagnostics: everything the searcher reported for one search.
    ///   - intent: the intent that search carried, for the failure text.
    ///   - sourceLocation: the caller's own line, so a failure reports the
    ///     scenario rather than this helper.
    static func expectNoUnknownSelectedId(
        among diagnostics: [MetadataDiagnostic],
        answering intent: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let invented = Self.unknownSelectedIds(among: diagnostics)
        #expect(
            invented.isEmpty,
            """
            the model answered "\(intent)" with \(invented), which is no id of the catalog it was \
            given. That diagnostic fired in none of the 125 cold runs measured on `^nwt7nz4`.
            """,
            sourceLocation: sourceLocation
        )
    }

    /// The ids `MetadataDiagnostic.unknownSelectedId` named among
    /// `diagnostics`, as one comma-separated clause for a failure message.
    ///
    /// - Parameter diagnostics: everything the searcher reported for one
    ///   search.
    /// - Returns: the invented ids, sorted and joined; empty when there were
    ///   none.
    private static func unknownSelectedIds(among diagnostics: [MetadataDiagnostic]) -> String {
        diagnostics
            .compactMap { diagnostic -> String? in
                guard case .unknownSelectedId(let id) = diagnostic else { return nil }
                return id
            }
            .sorted()
            .joined(separator: ", ")
    }
}
