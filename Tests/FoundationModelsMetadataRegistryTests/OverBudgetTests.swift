@testable import BigCatalogCore
import Foundation
@testable import FoundationModelsMetadataRegistry
import Testing

/// Tests for the selection tier's over-budget path (plan.md §6) and `.auto`
/// mode's real resolution.
///
/// The assembled prefix is the preamble, a `# Candidates` header, and every
/// candidate's `renderSummaryBlock()` under its id as a markdown heading.
/// When that prefix is longer than `capacityCharacterLimit`, the tier divides
/// the catalog ids, in catalog order, into runs whose prefix each fits the
/// budget, and gives every run one prompt on a fresh one-off session. Every
/// id reaches exactly one prompt, the tier cuts nothing, and no
/// `MetadataDiagnostic.retrievalCut` is reported. At or under the budget the
/// tier keeps one cached root session and forks it per call instead.
///
/// `.auto` resolves to selection when a session factory is configured, and to
/// retrieval otherwise. Driven against the internal `AgentSession` seam with
/// scripted fakes (`TestSupport/SelectionFixtures.swift`): no GPU, no
/// external dependency, the same pattern `SelectionTests` established for the
/// under-budget path.
struct OverBudgetTests {
    // MARK: - Fixtures

    struct FixtureItem: SearchableMetadata {
        let id: String
        let block: String
        let summary: String

        func renderBlock() -> String {
            block
        }

        func renderSummaryBlock() -> String {
            summary
        }
    }

    /// Five items whose ids are distinct enough that a `## <id>` heading in
    /// one run's prefix can never be confused with another id's heading.
    static let catalog: [FixtureItem] = [
        FixtureItem(id: "alpha", block: "alpha handles alpha tasks", summary: "SUMMARY_alpha"),
        FixtureItem(id: "bravo", block: "second unrelated block text", summary: "SUMMARY_bravo"),
        FixtureItem(id: "charlie", block: "third unrelated block text", summary: "SUMMARY_charlie"),
        FixtureItem(id: "delta", block: "fourth unrelated block text", summary: "SUMMARY_delta"),
        FixtureItem(id: "echo", block: "fifth unrelated block text", summary: "SUMMARY_echo")
    ]

    /// A `capacityCharacterLimit` of `1` is smaller than the assembled
    /// preamble alone, so every catalog is over budget and no run can hold
    /// more than the one entry the tier cannot split — one prompt per
    /// catalog id, in catalog order.
    static let forcedOverBudgetLimit = 1

    /// One scripted response for each id of `catalog`, so a single session
    /// shared by every run answers each of its calls instead of running out
    /// of script.
    static let oneResponsePerRun = [String](repeating: #"{"ids":["alpha"]}"#, count: catalog.count)

    // MARK: - One prompt per run, every id in exactly one of them

    @Test
    func overBudgetGivesEveryCatalogIdOnePromptInCatalogOrder() async throws {
        let factory = RecordingSessionFactory(responses: [#"{"ids":["alpha"]}"#])
        let config = SelectionConfig(model: factory.makeSession, capacityCharacterLimit: Self.forcedOverBudgetLimit)
        let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

        _ = try await searcher.search(intent: "alpha", limit: 5)

        // The tier splits rather than cuts, so the prompt count is the run
        // count and the runs follow catalog order.
        let instructions = factory.receivedInstructions
        #expect(instructions.count == Self.catalog.count)
        for (instruction, item) in zip(instructions, Self.catalog) {
            #expect(instruction.contains("## \(item.id)\n\(item.summary)"))
        }
    }

    @Test
    func overBudgetPromptNamesOnlyItsOwnRunsCandidateIds() async throws {
        let factory = RecordingSessionFactory(responses: [#"{"ids":["alpha"]}"#])
        let config = SelectionConfig(model: factory.makeSession, capacityCharacterLimit: Self.forcedOverBudgetLimit)
        let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

        _ = try await searcher.search(intent: "alpha", limit: 5)

        let instructions = factory.receivedInstructions
        for (instruction, item) in zip(instructions, Self.catalog) {
            let otherIds = Self.catalog.map(\.id).filter { $0 != item.id }
            #expect(otherIds.allSatisfy { !instruction.contains("## \($0)") })
        }
    }

    // MARK: - One-off sessions: no caching, no fork

    @Test
    func overBudgetMakesAFreshSessionForEveryRunOfEverySearch() async throws {
        let factoryCallCount = CallCounter()
        let config = SelectionConfig(
            model: { _ in
                factoryCallCount.increment()
                return ScriptedAgentSession([#"{"ids":["alpha"]}"#])
            },
            capacityCharacterLimit: Self.forcedOverBudgetLimit
        )
        let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

        _ = try await searcher.search(intent: "alpha", limit: 5)
        _ = try await searcher.search(intent: "alpha", limit: 5)

        // Unlike the cached-root path, nothing survives a call: each search
        // makes one session for each of its runs.
        #expect(factoryCallCount.count == Self.catalog.count * 2)
    }

    @Test
    func overBudgetSessionIsNeverForked() async throws {
        let session = ScriptedAgentSession(Self.oneResponsePerRun)
        let config = SelectionConfig(
            model: { _ in session },
            capacityCharacterLimit: Self.forcedOverBudgetLimit
        )
        let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

        _ = try await searcher.search(intent: "alpha", limit: 5)

        // A factory source seeds each run's prefix as its own session's
        // instructions, so no run has a parent to fork from.
        #expect(session.forkCount == 0)
        #expect(session.callCount == Self.catalog.count)
    }

    // MARK: - Nothing is cut, so `.retrievalCut` is never reported

    @Test
    func overBudgetSearchNeverFiresRetrievalCut() async throws {
        let recorder = DiagnosticRecorder()
        let factory = RecordingSessionFactory(responses: [#"{"ids":["alpha"]}"#])
        let config = SelectionConfig(model: factory.makeSession, capacityCharacterLimit: Self.forcedOverBudgetLimit)
        let searcher = MetadataSearcher(
            items: Self.catalog,
            mode: .selection,
            selection: config,
            onDiagnostic: { recorder.record($0) }
        )

        _ = try await searcher.search(intent: "alpha", limit: 5)

        // The selection path runs no retrieval at all now, so it reports
        // neither a cut nor the `.embeddingUnavailable` a ranking pass with
        // no embedder used to report.
        #expect(recorder.diagnostics.isEmpty)
    }

    @Test
    func underBudgetSearchNeverFiresRetrievalCut() async throws {
        let recorder = DiagnosticRecorder()
        let factory = RecordingSessionFactory(responses: [#"{"ids":["alpha"]}"#])
        let config = SelectionConfig(model: factory.makeSession)
        let searcher = MetadataSearcher(
            items: Self.catalog,
            mode: .selection,
            selection: config,
            onDiagnostic: { recorder.record($0) }
        )

        _ = try await searcher.search(intent: "alpha", limit: 5)

        #expect(recorder.diagnostics.isEmpty)
    }

    @Test
    func overBudgetWithAnEmptyCatalogReturnsNoMatchesWithoutInvokingTheSessionFactory() async throws {
        let recorder = DiagnosticRecorder()
        let factoryCallCount = CallCounter()
        let config = SelectionConfig(
            model: { _ in
                factoryCallCount.increment()
                return ScriptedAgentSession([#"{"ids":[]}"#])
            },
            capacityCharacterLimit: Self.forcedOverBudgetLimit
        )
        let searcher = MetadataSearcher(
            items: [FixtureItem](),
            mode: .selection,
            selection: config,
            onDiagnostic: { recorder.record($0) }
        )

        let matches = try await searcher.search(intent: "alpha", limit: 5)

        // An empty catalog splits into no runs at all, so there is nothing
        // to prompt and nothing to report.
        #expect(matches.isEmpty)
        #expect(factoryCallCount.count == 0)
        #expect(recorder.diagnostics.isEmpty)
    }

    // MARK: - Verbatim lookup against the whole catalog

    @Test
    func overBudgetIdFromAnotherRunStillResolves() async throws {
        let recorder = DiagnosticRecorder()
        // Every run answers with "alpha" and "charlie", which sit in
        // different runs. The tier looks each answered id up in the whole
        // catalog, so a run's own candidate set never limits what resolves.
        // When the tier still cut candidates, this same answer was reported
        // as `.unknownSelectedId`.
        let factory = RecordingSessionFactory(responses: [#"{"ids":["alpha","charlie"]}"#])
        let config = SelectionConfig(model: factory.makeSession, capacityCharacterLimit: Self.forcedOverBudgetLimit)
        let searcher = MetadataSearcher(
            items: Self.catalog,
            mode: .selection,
            selection: config,
            onDiagnostic: { recorder.record($0) }
        )

        let matches = try await searcher.search(intent: "alpha", limit: 5)

        #expect(matches.map(\.id) == ["alpha", "charlie"])
        #expect(recorder.diagnostics.isEmpty)
    }

    @Test
    func overBudgetIdOutsideTheCatalogIsFilteredAndReportedAsUnknown() async throws {
        let recorder = DiagnosticRecorder()
        let factory = RecordingSessionFactory(responses: [#"{"ids":["alpha","not-a-real-id"]}"#])
        let config = SelectionConfig(model: factory.makeSession, capacityCharacterLimit: Self.forcedOverBudgetLimit)
        let searcher = MetadataSearcher(
            items: Self.catalog,
            mode: .selection,
            selection: config,
            onDiagnostic: { recorder.record($0) }
        )

        let matches = try await searcher.search(intent: "alpha", limit: 5)

        #expect(matches.map(\.id) == ["alpha"])
        #expect(recorder.diagnostics == [.unknownSelectedId(id: "not-a-real-id")])
    }

    // MARK: - The assembled prefix shows the model the candidate ids

    @Test
    func assembledPrefixNamesEachCandidateIdAboveItsSummary() {
        // Ranker fixed a defect here: the prefix used to render each
        // candidate's summary block alone, so the model saw no ids at all
        // while the preamble told it not to invent one, and every selection
        // came back `.unknownSelectedId`. A grammar-backed caller never saw
        // the defect, because the id-enum grammar forced a valid id out of
        // the decoder whatever the prompt said. This package drives the tier
        // with no grammar, so the prefix is the only thing standing between
        // the model and an invented id.
        let prefix = SelectionTier.assemblePrefix(
            preamble: .librarianDefault,
            catalog: MetadataIndex(items: Self.catalog)
        )

        for item in Self.catalog {
            #expect(prefix.contains("## \(item.id)\n\(item.summary)"))
        }
    }

    // MARK: - Selection results are scored by the model's order

    @Test
    func selectionResultsAreScoredByTheModelsOrderAndCarryNoSignals() async throws {
        let factory = RecordingSessionFactory(responses: [#"{"ids":["charlie","alpha"]}"#])
        let config = SelectionConfig(model: factory.makeSession, capacityCharacterLimit: Self.forcedOverBudgetLimit)
        let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

        let matches = try await searcher.search(intent: "alpha", limit: 5)

        // No retrieval signal enters a selection: a pick's score is the
        // reciprocal of its rank in the answer (1/1, then 1/2), and there is
        // no per-signal breakdown to carry.
        #expect(matches.map(\.id) == ["charlie", "alpha"])
        #expect(matches.map(\.score) == [1.0, 1.0 / 2.0])
        #expect(matches.allSatisfy { $0.signals == nil })
    }

    // MARK: - Budget boundary

    @Test
    func prefixExactlyAtTheCapacityLimitUsesTheCachedRootPath() async throws {
        let expectedPrefix = SelectionTier.assemblePrefix(
            preamble: .librarianDefault,
            ids: Self.catalog.map(\.id),
            catalog: MetadataIndex(items: Self.catalog)
        )
        let factoryCallCount = CallCounter()
        let root = RootSessionRespondCalledDirectlySession(forkResponses: [
            #"{"ids":["alpha"]}"#,
            #"{"ids":["alpha"]}"#
        ])
        let config = SelectionConfig(
            model: { _ in
                factoryCallCount.increment()
                return root
            },
            preamble: .librarianDefault,
            capacityCharacterLimit: expectedPrefix.count
        )
        let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

        _ = try await searcher.search(intent: "alpha", limit: 5)
        _ = try await searcher.search(intent: "alpha", limit: 5)

        // Cached-root path: the factory runs exactly once, and every call
        // forks -- the boundary itself (`==`) still counts as "under
        // budget", matching `capacityCharacterLimit`'s own "at or under"
        // documentation.
        #expect(factoryCallCount.count == 1)
        #expect(root.forkCount == 2)
    }

    @Test
    func prefixOneCharacterOverTheCapacityLimitCachesNothingBetweenSearches() async throws {
        let expectedPrefix = SelectionTier.assemblePrefix(
            preamble: .librarianDefault,
            ids: Self.catalog.map(\.id),
            catalog: MetadataIndex(items: Self.catalog)
        )
        let factoryCallCount = CallCounter()
        let config = SelectionConfig(
            model: { _ in
                factoryCallCount.increment()
                return ScriptedAgentSession([#"{"ids":["alpha"]}"#])
            },
            preamble: .librarianDefault,
            capacityCharacterLimit: expectedPrefix.count - 1
        )
        let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

        _ = try await searcher.search(intent: "alpha", limit: 5)
        let sessionsAfterFirstSearch = factoryCallCount.count
        _ = try await searcher.search(intent: "alpha", limit: 5)

        // One character over the budget is enough to leave the cached-root
        // path. How many runs the split makes depends on the fixture's own
        // entry sizes, so the fact under test is that the second search
        // repeats the first one's session count rather than reusing it.
        #expect(sessionsAfterFirstSearch >= 1)
        #expect(factoryCallCount.count == sessionsAfterFirstSearch * 2)
    }
}
