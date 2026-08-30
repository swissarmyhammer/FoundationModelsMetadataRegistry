import Foundation
import Testing

@testable import BigCatalogCore
@testable import FoundationModelsMetadataRegistry

/// Tests for the selection tier's over-budget path (plan.md §6) and `.auto`
/// mode's real resolution: when the assembled prefix (preamble + every
/// candidate's `renderSummaryBlock()`) exceeds `capacityCharacterLimit`, the
/// retrieval tier ranks the whole catalog and the top-`candidateLimit`
/// candidates (best-first) seed a fresh, uncached, unforked one-off
/// session — constrained to those candidate ids only — with the cut
/// reported via `MetadataDiagnostic.retrievalCut(considered:kept:)`.
/// `.auto` resolves to selection when a session factory is configured,
/// retrieval otherwise. Driven against the internal `AgentSession` seam via
/// scripted fakes (`TestSupport/SelectionFixtures.swift`), plus this
/// package's real, GPU-free BM25/trigram retrieval tier for deterministic
/// candidate ranking — zero GPU, no external dependency, the same pattern
/// `SelectionTests` established for the under-budget path.
struct OverBudgetTests {
    // MARK: - Fixtures

    struct FixtureItem: SearchableMetadata {
        let id: String
        let block: String
        let summary: String

        func renderBlock() -> String { block }
        func renderSummaryBlock() -> String { summary }
    }

    /// Five items where only `alpha` lexically/fuzzily overlaps with the
    /// `"alpha"` intent used throughout this file — `bravo`/`charlie`/
    /// `delta`/`echo` score `0.0` on every signal, so the over-budget
    /// path's full-catalog ranking is deterministic: `alpha` first (a real
    /// match), then the rest in catalog order (the zero-signal fallback
    /// tail that guarantees the top-M candidate count regardless of how
    /// sparse real matches are).
    static let catalog: [FixtureItem] = [
        FixtureItem(id: "alpha", block: "alpha handles alpha tasks", summary: "SUMMARY_alpha"),
        FixtureItem(id: "bravo", block: "second unrelated block text", summary: "SUMMARY_bravo"),
        FixtureItem(id: "charlie", block: "third unrelated block text", summary: "SUMMARY_charlie"),
        FixtureItem(id: "delta", block: "fourth unrelated block text", summary: "SUMMARY_delta"),
        FixtureItem(id: "echo", block: "fifth unrelated block text", summary: "SUMMARY_echo"),
    ]

    /// A `capacityCharacterLimit` of `1` is smaller than the assembled
    /// preamble alone, so any catalog (even a tiny one) is over budget —
    /// the same trick `SelectionTests` used before this path existed.
    static let forcedOverBudgetLimit = 1

    // MARK: - Top-M membership and ordering

    @Test
    func overBudgetSeedsAOneOffSessionWithTopMCandidatesInBestFirstOrder() async throws {
        let factory = RecordingSessionFactory(responses: [#"{"ids":["alpha"]}"#])
        let config = SelectionConfig(
            model: factory.makeSession,
            capacityCharacterLimit: Self.forcedOverBudgetLimit,
            candidateLimit: 2
        )
        let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

        _ = try await searcher.search(intent: "alpha", limit: 5)

        let instructions = try #require(factory.receivedInstructions.first)
        #expect(instructions.contains("SUMMARY_alpha"))
        #expect(instructions.contains("SUMMARY_bravo"))
        #expect(!instructions.contains("SUMMARY_charlie"))
        #expect(!instructions.contains("SUMMARY_delta"))
        #expect(!instructions.contains("SUMMARY_echo"))

        let alphaRange = try #require(instructions.range(of: "SUMMARY_alpha"))
        let bravoRange = try #require(instructions.range(of: "SUMMARY_bravo"))
        #expect(alphaRange.lowerBound < bravoRange.lowerBound)
    }

    // MARK: - One-off session: no caching, no fork

    @Test
    func overBudgetCreatesAFreshSessionPerCallWithoutCaching() async throws {
        let factoryCallCount = CallCounter()
        let config = SelectionConfig(
            model: { _ in
                factoryCallCount.increment()
                return ScriptedAgentSession([#"{"ids":["alpha"]}"#])
            },
            capacityCharacterLimit: Self.forcedOverBudgetLimit,
            candidateLimit: 2
        )
        let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

        _ = try await searcher.search(intent: "alpha", limit: 5)
        _ = try await searcher.search(intent: "alpha", limit: 5)

        // Unlike the cached-root path, a fresh session is created per call.
        #expect(factoryCallCount.count == 2)
    }

    @Test
    func overBudgetSessionIsNeverForked() async throws {
        let session = ScriptedAgentSession([#"{"ids":["alpha"]}"#])
        let config = SelectionConfig(
            model: { _ in session },
            capacityCharacterLimit: Self.forcedOverBudgetLimit,
            candidateLimit: 2
        )
        let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

        _ = try await searcher.search(intent: "alpha", limit: 5)

        #expect(session.forkCount == 0)
        #expect(session.callCount == 1)
    }

    // MARK: - `.retrievalCut` payload capture

    @Test
    func retrievalCutReportsAccurateConsideredAndKeptCounts() async throws {
        let recorder = DiagnosticRecorder()
        let factory = RecordingSessionFactory(responses: [#"{"ids":["alpha"]}"#])
        let config = SelectionConfig(
            model: factory.makeSession,
            capacityCharacterLimit: Self.forcedOverBudgetLimit,
            candidateLimit: 2
        )
        // Cosine damped to zero -- no embedder is configured, and this test
        // only cares about `.retrievalCut`'s payload, not the unrelated
        // `.embeddingUnavailable` a default cosine weight would also report.
        let searcher = MetadataSearcher(
            items: Self.catalog,
            mode: .selection,
            weights: Weights(cosine: 0.0),
            selection: config,
            onDiagnostic: { recorder.record($0) }
        )

        _ = try await searcher.search(intent: "alpha", limit: 5)

        #expect(recorder.diagnostics == [.retrievalCut(considered: 5, kept: 2)])
    }

    @Test
    func candidateCountIsClampedToCatalogSizeWhenCandidateLimitIsLarger() async throws {
        let recorder = DiagnosticRecorder()
        let factory = RecordingSessionFactory(responses: [#"{"ids":["alpha"]}"#])
        // Default `candidateLimit` (24) far exceeds this 5-item catalog.
        let config = SelectionConfig(model: factory.makeSession, capacityCharacterLimit: Self.forcedOverBudgetLimit)
        let searcher = MetadataSearcher(
            items: Self.catalog,
            mode: .selection,
            weights: Weights(cosine: 0.0),
            selection: config,
            onDiagnostic: { recorder.record($0) }
        )

        _ = try await searcher.search(intent: "alpha", limit: 5)

        #expect(recorder.diagnostics == [.retrievalCut(considered: 5, kept: 5)])
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

        #expect(
            !recorder.diagnostics.contains {
                if case .retrievalCut = $0 { return true }
                return false
            }
        )
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

        #expect(matches.isEmpty)
        #expect(factoryCallCount.count == 0)
        #expect(recorder.diagnostics == [.retrievalCut(considered: 0, kept: 0)])
    }

    // MARK: - Candidate-set-only verbatim lookup (one-off candidate id set)

    @Test
    func idOutsideTopMCandidatesIsFilteredAndReportedAsUnknownEvenThoughItIsAValidCatalogId() async throws {
        let recorder = DiagnosticRecorder()
        // "charlie" is a real catalog id, but `candidateLimit: 2` excludes
        // it from this round's candidates (alpha, bravo only) -- the
        // one-off session's admissible ids are this round's candidates,
        // not the wider catalog, so this must be treated as unknown even
        // though "charlie" resolves in the catalog overall.
        let factory = RecordingSessionFactory(responses: [#"{"ids":["alpha","charlie"]}"#])
        let config = SelectionConfig(
            model: factory.makeSession,
            capacityCharacterLimit: Self.forcedOverBudgetLimit,
            candidateLimit: 2
        )
        let searcher = MetadataSearcher(
            items: Self.catalog,
            mode: .selection,
            selection: config,
            onDiagnostic: { recorder.record($0) }
        )

        let matches = try await searcher.search(intent: "alpha", limit: 5)

        #expect(matches.map(\.id) == ["alpha"])
        #expect(recorder.diagnostics.contains(.unknownSelectedId(id: "charlie")))
    }

    // MARK: - The assembled prefix shows the model the candidate ids

    @Test
    func assembledPrefixNamesEachCandidateIdAboveItsSummary() throws {
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

    @Test
    func overBudgetPrefixNamesExactlyThisRoundsCandidateIds() async throws {
        // The over-budget path seeds its one-off session with the top-M
        // candidates only, so the prefix must name alpha and bravo and no
        // other catalog id. This is the fact the id-enum grammar used to
        // carry (task ^678h0ex): the model's admissible id set is this
        // round's candidates, never the wider catalog. With the grammar gone
        // from the tier, the prefix is where that set is stated.
        let factory = RecordingSessionFactory(responses: [#"{"ids":["alpha"]}"#])
        let config = SelectionConfig(
            model: factory.makeSession,
            capacityCharacterLimit: Self.forcedOverBudgetLimit,
            candidateLimit: 2
        )
        let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

        _ = try await searcher.search(intent: "alpha", limit: 5)

        let instructions = try #require(factory.receivedInstructions.first)
        #expect(instructions.contains("## alpha"))
        #expect(instructions.contains("## bravo"))
        #expect(!instructions.contains("## charlie"))
        #expect(!instructions.contains("## delta"))
        #expect(!instructions.contains("## echo"))
    }

    // MARK: - Retrieval-tier signals attach to over-budget results

    @Test
    func overBudgetResultsCarryTheRealRetrievalScoreAndSignals() async throws {
        let factory = RecordingSessionFactory(responses: [#"{"ids":["alpha"]}"#])
        let config = SelectionConfig(
            model: factory.makeSession,
            capacityCharacterLimit: Self.forcedOverBudgetLimit,
            candidateLimit: 2
        )
        let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

        let matches = try await searcher.search(intent: "alpha", limit: 5)

        let alpha = try #require(matches.first)
        #expect(alpha.id == "alpha")
        // Retrieval genuinely ran to rank "alpha" -- this carries the real
        // fused score and per-signal breakdown, same as the under-budget
        // path now attaches to every selected id too (plan.md §3a).
        #expect(alpha.score > 0.0)
        let signals = try #require(alpha.signals)
        #expect(signals.bm25 > 0.0)
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
            #"{"ids":["alpha"]}"#,
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
    func prefixOneCharacterOverTheCapacityLimitUsesTheOneOffPath() async throws {
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
        _ = try await searcher.search(intent: "alpha", limit: 5)

        // One-off path: a fresh session per call, never cached.
        #expect(factoryCallCount.count == 2)
    }

    // MARK: - `.auto` resolution both ways

    @Test
    func autoModeResolvesToSelectionWhenASessionFactoryIsConfigured() async throws {
        // Scripted to return "echo" -- something plain retrieval for the
        // "alpha" intent would never surface, proving `.auto` actually took
        // the selection path rather than silently falling back.
        let factory = RecordingSessionFactory(responses: [#"{"ids":["echo"]}"#])
        let config = SelectionConfig(model: factory.makeSession)
        let searcher = MetadataSearcher(items: Self.catalog, mode: .auto, selection: config)

        let matches = try await searcher.search(intent: "alpha", limit: 5)

        #expect(matches.map(\.id) == ["echo"])
    }

    @Test
    func autoModeFallsBackToRetrievalWhenNoSessionFactoryIsConfigured() async throws {
        let retrieval = MetadataSearcher(items: Self.catalog, mode: .retrieval)
        let auto = MetadataSearcher(items: Self.catalog, mode: .auto)

        let retrievalMatches = try await retrieval.search(intent: "alpha", limit: 5)
        let autoMatches = try await auto.search(intent: "alpha", limit: 5)

        #expect(autoMatches.map(\.id) == retrievalMatches.map(\.id))
        #expect(!autoMatches.isEmpty)
    }

    // MARK: - `BigCatalog`'s over-budget demo (plan.md §13 M8)

    /// The catalog size `bigCatalogDemoOverBudgetSelectionReportsARetrievalCut()`
    /// drives the demo with: comfortably more entries than
    /// `SelectionConfig.defaultCandidateLimit`, so the cut really cuts, and
    /// their assembled summary blocks comfortably exceed the demo's own tiny
    /// capacity limit, so the over-budget path really runs. Far smaller than
    /// the demo's own ~10^3 default, which `ExamplesSmokeTests` already
    /// indexes and times -- this test measures the diagnostic, not the
    /// throughput, and a second ~10^3-entry index running beside that timed
    /// test would only slow it down.
    static let bigCatalogDemoEntryCount = 40

    @Test
    func bigCatalogDemoOverBudgetSelectionReportsARetrievalCut() async throws {
        let recorder = DiagnosticRecorder()
        let catalog = BigCatalogCore.makeBigCatalog(count: Self.bigCatalogDemoEntryCount)

        _ = try await BigCatalogCore.runBigCatalogOverBudgetSelection(
            catalog: catalog,
            query: BigCatalogCore.bigCatalogNeedleQuery,
            onDiagnostic: { recorder.record($0) }
        )

        // The demo's deliberately tiny capacity limit puts this catalog over
        // budget, so the tier ranks every entry and keeps the default top-M
        // before seeding its one-off session.
        #expect(
            recorder.diagnostics.contains(
                .retrievalCut(considered: catalog.count, kept: SelectionConfig.defaultCandidateLimit)
            )
        )
    }
}
