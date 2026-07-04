import Foundation
import Testing

@testable import FoundationModelsMetadataRegistry

/// Tests for the selection tier's under-budget path (plan.md §6, M3): a
/// cached root session seeded once with the assembled prefix, `fork()` per
/// `search()` call, the summary-vs-full block separation
/// (`renderSummaryBlock()` seeds the prefix; `renderBlock()` is what a
/// `Match` carries back verbatim), ids-only decoding, verbatim lookup by id,
/// unknown-id filtering + diagnostic, and the id-enum grammar's contents.
/// Driven entirely against the internal `AgentSession` seam via scripted
/// fakes (`TestSupport/SelectionFixtures.swift`) — zero GPU, no Router
/// dependency, the same pattern Multitool's `LibrarianTests` established.
/// The over-budget path and `.auto`'s real resolution are covered in
/// `OverBudgetTests`.
struct SelectionTests {
    // MARK: - Fixtures

    struct FixtureItem: SearchableMetadata {
        let id: String
        let block: String
        let summary: String?

        init(id: String, block: String, summary: String? = nil) {
            self.id = id
            self.block = block
            self.summary = summary
        }

        func renderBlock() -> String { block }
        func renderSummaryBlock() -> String { summary ?? block }
    }

    static let catalog: [FixtureItem] = [
        FixtureItem(id: "deploy", block: "ships containers to a kubernetes cluster"),
        FixtureItem(id: "rollback", block: "reverts the last release"),
    ]

    // MARK: - Cached root + fork-per-call

    @Test
    func eachSearchCallForksTheCachedRootSessionExactlyOnce() async throws {
        let root = RootSessionRespondCalledDirectlySession(forkResponses: [
            #"{"ids":["deploy"]}"#,
            #"{"ids":["rollback"]}"#,
        ])
        let factoryCallCount = CallCounter()
        let config = SelectionConfig(model: { _ in
            factoryCallCount.increment()
            return root
        })
        let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

        let first = try await searcher.search(intent: "first task", limit: 5)
        let second = try await searcher.search(intent: "second task", limit: 5)

        #expect(root.forkCount == 2)
        // The session factory ran exactly once -- the root is created and
        // cached on the first call, never rebuilt on the second.
        #expect(factoryCallCount.count == 1)
        #expect(first.map(\.id) == ["deploy"])
        #expect(second.map(\.id) == ["rollback"])
    }

    // MARK: - Summary vs full block separation

    @Test
    func sessionPrefixUsesSummaryBlockWhileMatchesCarryTheFullRenderedBlock() async throws {
        let item = FixtureItem(id: "deploy", block: "the full, long rendered block text", summary: "short summary")
        let factory = RecordingSessionFactory(responses: [#"{"ids":["deploy"]}"#])
        let config = SelectionConfig(model: factory.makeSession)
        let searcher = MetadataSearcher(items: [item], mode: .selection, selection: config)

        let matches = try await searcher.search(intent: "task", limit: 5)

        let seededInstructions = try #require(factory.receivedInstructions.first)
        #expect(seededInstructions.contains("short summary"))
        #expect(!seededInstructions.contains("the full, long rendered block text"))

        let match = try #require(matches.first)
        #expect(match.block == "the full, long rendered block text")
        #expect(match.score == 1.0)
        #expect(match.signals == nil)
    }

    // MARK: - Ids-only decode + verbatim lookup identity

    @Test
    func selectionDecodesIdsOnlyAndMatchesCarryVerbatimCatalogBlocks() async throws {
        let factory = RecordingSessionFactory(responses: [#"{"ids":["rollback","deploy"]}"#])
        let config = SelectionConfig(model: factory.makeSession)
        let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

        let matches = try await searcher.search(intent: "roll back the last deploy", limit: 5)

        #expect(matches.map(\.id) == ["rollback", "deploy"])
        #expect(matches.map(\.block) == ["reverts the last release", "ships containers to a kubernetes cluster"])
        #expect(matches.allSatisfy { $0.score == 1.0 && $0.signals == nil })
    }

    @Test
    func selectionResultsAreTruncatedToLimit() async throws {
        let factory = RecordingSessionFactory(responses: [#"{"ids":["rollback","deploy"]}"#])
        let config = SelectionConfig(model: factory.makeSession)
        let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

        let matches = try await searcher.search(intent: "roll back the last deploy", limit: 1)

        #expect(matches.map(\.id) == ["rollback"])
    }

    // MARK: - Duplicate id handling: first occurrence wins, no diagnostic

    @Test
    func duplicateIdFromAMisbehavingFakeIsDeduplicatedWithoutADiagnostic() async throws {
        let recorder = DiagnosticRecorder()
        let factory = RecordingSessionFactory(responses: [#"{"ids":["deploy","deploy","rollback"]}"#])
        let config = SelectionConfig(model: factory.makeSession)
        let searcher = MetadataSearcher(
            items: Self.catalog,
            mode: .selection,
            selection: config,
            onDiagnostic: { recorder.record($0) }
        )

        let matches = try await searcher.search(intent: "task", limit: 5)

        #expect(matches.map(\.id) == ["deploy", "rollback"])
        #expect(recorder.diagnostics.isEmpty)
    }

    @Test
    func duplicateIdDoesNotConsumeALimitSlotAndCrowdOutALaterLegitimateMatch() async throws {
        // A tight `limit` of 2 against 3 model-returned ids (one a repeat):
        // if the duplicate consumed a slot the way an unfiltered append
        // would, this would truncate to just ["deploy"]. Deduplication must
        // let "rollback" through instead.
        let factory = RecordingSessionFactory(responses: [#"{"ids":["deploy","deploy","rollback"]}"#])
        let config = SelectionConfig(model: factory.makeSession)
        let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

        let matches = try await searcher.search(intent: "task", limit: 2)

        #expect(matches.map(\.id) == ["deploy", "rollback"])
    }

    // MARK: - Zero-ids model response ("nothing fits")

    @Test
    func emptyIdsModelResponseReturnsEmptyMatchesWithNoDiagnostic() async throws {
        let recorder = DiagnosticRecorder()
        let factory = RecordingSessionFactory(responses: [#"{"ids":[]}"#])
        let config = SelectionConfig(model: factory.makeSession)
        let searcher = MetadataSearcher(
            items: Self.catalog,
            mode: .selection,
            selection: config,
            onDiagnostic: { recorder.record($0) }
        )

        let matches = try await searcher.search(intent: "nothing matches this", limit: 5)

        #expect(matches.isEmpty)
        #expect(recorder.diagnostics.isEmpty)
    }

    // MARK: - Empty catalog

    @Test
    func emptyCatalogSearchReturnsNoMatchesWithoutCrashing() async throws {
        let factory = RecordingSessionFactory(responses: [#"{"ids":[]}"#])
        let config = SelectionConfig(model: factory.makeSession)
        let searcher = MetadataSearcher(items: [FixtureItem](), mode: .selection, selection: config)

        let matches = try await searcher.search(intent: "anything", limit: 5)

        #expect(matches.isEmpty)
    }

    // MARK: - Unknown id filtering + diagnostic

    @Test
    func unknownIdFromAMisbehavingFakeIsFilteredAndReportedAsADiagnostic() async throws {
        let recorder = DiagnosticRecorder()
        let factory = RecordingSessionFactory(responses: [#"{"ids":["deploy","not-a-real-id"]}"#])
        let config = SelectionConfig(model: factory.makeSession)
        let searcher = MetadataSearcher(
            items: Self.catalog,
            mode: .selection,
            selection: config,
            onDiagnostic: { recorder.record($0) }
        )

        let matches = try await searcher.search(intent: "task", limit: 5)

        #expect(matches.map(\.id) == ["deploy"])
        #expect(recorder.diagnostics == [.unknownSelectedId(id: "not-a-real-id")])
    }

    // MARK: - Without a selection config, .selection still throws (unchanged)

    @Test
    func selectionModeWithNoConfigStillThrowsSelectionTierUnavailable() async throws {
        let searcher = MetadataSearcher(items: Self.catalog, mode: .selection)
        await #expect(throws: SelectionTierUnavailable.self) {
            _ = try await searcher.search(intent: "task", limit: 5)
        }
    }

    // MARK: - Grammar id-set contents

    @Test
    func idEnumGrammarContainsExactlyTheCatalogsCurrentIds() throws {
        let grammar = try SelectionTier<FixtureItem>.idEnumGrammar(ids: Self.catalog.map(\.id))

        guard case .jsonSchema(let source) = grammar else {
            Issue.record("expected a .jsonSchema grammar")
            return
        }
        let data = try #require(source.data(using: .utf8))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try #require(root["properties"] as? [String: Any])
        let idsSchema = try #require(properties["ids"] as? [String: Any])
        let itemsSchema = try #require(idsSchema["items"] as? [String: Any])
        let enumValues = try #require(itemsSchema["enum"] as? [String])

        #expect(Set(enumValues) == Set(Self.catalog.map(\.id)))
    }

    @Test
    func idEnumGrammarMarksIdsAsUniqueItems() throws {
        let grammar = try SelectionTier<FixtureItem>.idEnumGrammar(ids: Self.catalog.map(\.id))

        guard case .jsonSchema(let source) = grammar else {
            Issue.record("expected a .jsonSchema grammar")
            return
        }
        let data = try #require(source.data(using: .utf8))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try #require(root["properties"] as? [String: Any])
        let idsSchema = try #require(properties["ids"] as? [String: Any])

        #expect(idsSchema["uniqueItems"] as? Bool == true)
    }

    @Test
    func idEnumGrammarReflectsAnEmptyCatalogAsAnEmptyEnum() throws {
        let grammar = try SelectionTier<FixtureItem>.idEnumGrammar(ids: [])

        guard case .jsonSchema(let source) = grammar else {
            Issue.record("expected a .jsonSchema grammar")
            return
        }
        let data = try #require(source.data(using: .utf8))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try #require(root["properties"] as? [String: Any])
        let idsSchema = try #require(properties["ids"] as? [String: Any])
        let itemsSchema = try #require(idsSchema["items"] as? [String: Any])
        let enumValues = try #require(itemsSchema["enum"] as? [String])

        #expect(enumValues.isEmpty)
    }
}
