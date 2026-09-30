@testable import FoundationModelsMetadataRegistry
import InMemoryTracing
import TelemetryTestSupport
import Testing
import Tracing

/// Tests for the spans of the registry (the OpenTelemetry design of
/// 2026-09-28, part A): one span for each search, one child span for each
/// call to a ranker, and one span for each catalog update and each catalog
/// embed.
///
/// Each test runs inside `TelemetryCapture.run(forbidding:)`, with the query
/// text and the content of each item as forbidden strings. Thus each test
/// also proves rule 4 ("no content") for the spans that it reads. Each test
/// makes its searchers inside the capture, because the capture binds its
/// tracer to the task of the test. No test here bootstraps the logging
/// system: the capture does that one time for the process.
@Suite("Registry tracing")
struct RegistryTracingTests {
    typealias FixtureItem = EmbeddingTests.FixtureItem
    typealias Key = RegistryTelemetry.AttributeKey
    typealias SpanName = RegistryTelemetry.SpanName

    // MARK: - Fixtures

    /// The catalog that each searcher starts from.
    static let catalog = [
        FixtureItem(id: "deploy", block: "ships the current build to production servers"),
        FixtureItem(id: "rollback", block: "returns production to the previous release"),
        FixtureItem(id: "status", block: "reports the health of each running service"),
    ]

    /// The catalog that `update(items:)` loads. It adds one item, so the
    /// reload changes the content and embeds only the new item.
    static let reloadedCatalog = catalog + [
        FixtureItem(id: "restart", block: "stops and starts each process of the service"),
    ]

    /// The query text of each search.
    static let query = "ship the build to production"

    /// The strings that no span attribute may hold: the query text and each
    /// rendered block of both catalogs.
    static let forbidden = [query] + reloadedCatalog.map(\.block)

    /// The `limit` of each search. It is larger than each catalog, so no
    /// result is cut.
    static let searchLimit = 10

    /// The length of each vector of the fixture.
    static let vectorLength = 2

    /// The vector of the query and of each block.
    static let vectorsByText: [String: [Float]] = Dictionary(
        uniqueKeysWithValues: forbidden.map { ($0, [Float](repeating: 1, count: vectorLength)) },
    )

    /// The id that the scripted selection model picks.
    static let selectedID = catalog[0].id

    /// The error that a failing embedder throws.
    struct EmbedFailure: Error {}

    /// Makes an embedder that gives a vector for each fixture text.
    static func makeEmbedder() -> FakeEmbedder {
        FakeEmbedder(vectorsByText: vectorsByText)
    }

    /// Makes an embedder whose each call throws `EmbedFailure`.
    static func makeFailingEmbedder() -> FakeEmbedder {
        FakeEmbedder(failure: EmbedFailure())
    }

    /// Makes a selection configuration whose scripted model picks
    /// `selectedID`.
    static func makeSelectionConfig() -> SelectionConfig {
        let factory = RecordingSessionFactory(responses: [#"{"ids":["\#(selectedID)"]}"#])
        return SelectionConfig(model: factory.makeSession)
    }

    /// Returns the one span named `name` that ended in `context`.
    ///
    /// - Parameters:
    ///   - name: the operation name of the span.
    ///   - context: the capture that holds the spans.
    /// - Returns: the span.
    /// - Throws: when no span or more than one span has the name.
    static func onlySpan(named name: String, in context: TelemetryCapture.Context) throws -> FinishedInMemorySpan {
        let spans = context.spans.filter { $0.operationName == name }
        try #require(spans.count == 1, "expected one span named \(name), found \(spans.count)")
        return spans[0]
    }

    /// Returns the spans named `name` that ended in `context`.
    ///
    /// - Parameters:
    ///   - name: the operation name of the spans.
    ///   - context: the capture that holds the spans.
    /// - Returns: the spans, in the order of their end.
    static func spans(named name: String, in context: TelemetryCapture.Context) -> [FinishedInMemorySpan] {
        context.spans.filter { $0.operationName == name }
    }

    // MARK: - Search spans

    @Test
    func retrievalSearchWithNoEmbedderRanksWithTheKeywordSignalsOnly() async throws {
        try await TelemetryCapture.run(forbidding: Self.forbidden) { context in
            let searcher = MetadataSearcher(items: Self.catalog, mode: .retrieval, onDiagnostic: { _ in })
            let matches = try await searcher.search(intent: Self.query, limit: Self.searchLimit)

            let search = try Self.onlySpan(named: SpanName.search, in: context)
            #expect(search.attributes.get(Key.searchMode) == .string("retrieval"))
            #expect(search.attributes.get(Key.searchTier) == .string("retrieval"))
            #expect(search.attributes.get(Key.searchLimit) == .int64(Int64(Self.searchLimit)))
            #expect(search.attributes.get(Key.searchResultCount) == .int64(Int64(matches.count)))
            #expect(search.attributes.get(Key.catalogSize) == .int64(Int64(Self.catalog.count)))
            #expect(search.attributes.get(Key.searchRankers) == .stringArray(["bm25", "trigram"]))

            let rank = try Self.onlySpan(named: SpanName.rank, in: context)
            #expect(rank.parentSpanID == search.spanID)
            #expect(rank.traceID == search.traceID)
            #expect(rank.attributes.get(Key.rankRanker) == .string("hybrid"))
            #expect(rank.attributes.get(Key.rankCandidateCount) == .int64(Int64(Self.catalog.count)))
        }
    }

    @Test
    func retrievalSearchWithAnEmbeddedCatalogAlsoRanksWithCosine() async throws {
        try await TelemetryCapture.run(forbidding: Self.forbidden) { context in
            let searcher = await MetadataSearcher(items: Self.catalog, mode: .retrieval, embedder: Self.makeEmbedder())
            _ = try await searcher.search(intent: Self.query, limit: Self.searchLimit)

            let search = try Self.onlySpan(named: SpanName.search, in: context)
            #expect(search.attributes.get(Key.searchRankers) == .stringArray(["bm25", "trigram", "cosine"]))
            let rank = try Self.onlySpan(named: SpanName.rank, in: context)
            #expect(rank.parentSpanID == search.spanID)
        }
    }

    @Test
    func retrievalSearchLeavesOutAKeywordSignalWithAZeroWeight() async throws {
        try await TelemetryCapture.run(forbidding: Self.forbidden) { context in
            let searcher = MetadataSearcher(
                items: Self.catalog,
                mode: .retrieval,
                weights: Weights(bm25: 0, trigram: 1, cosine: 0),
                onDiagnostic: { _ in },
            )
            _ = try await searcher.search(intent: Self.query, limit: Self.searchLimit)

            let search = try Self.onlySpan(named: SpanName.search, in: context)
            #expect(search.attributes.get(Key.searchRankers) == .stringArray(["trigram"]))
        }
    }

    @Test
    func selectionSearchRanksWithTheSelectionTier() async throws {
        try await TelemetryCapture.run(forbidding: Self.forbidden) { context in
            let searcher = MetadataSearcher(
                items: Self.catalog,
                mode: .selection,
                selection: Self.makeSelectionConfig(),
            )
            let matches = try await searcher.search(intent: Self.query, limit: Self.searchLimit)

            let search = try Self.onlySpan(named: SpanName.search, in: context)
            #expect(search.attributes.get(Key.searchMode) == .string("selection"))
            #expect(search.attributes.get(Key.searchTier) == .string("selection"))
            #expect(search.attributes.get(Key.searchResultCount) == .int64(Int64(matches.count)))
            #expect(search.attributes.get(Key.catalogSize) == .int64(Int64(Self.catalog.count)))
            #expect(search.attributes.get(Key.searchRankers) == .stringArray(["selection"]))

            let rank = try Self.onlySpan(named: SpanName.rank, in: context)
            #expect(rank.parentSpanID == search.spanID)
            #expect(rank.attributes.get(Key.rankRanker) == .string("selection"))
            #expect(rank.attributes.get(Key.rankCandidateCount) == .int64(Int64(Self.catalog.count)))
        }
    }

    @Test
    func autoSearchNamesTheModeAndTheTierThatAnswered() async throws {
        try await TelemetryCapture.run(forbidding: Self.forbidden) { context in
            let withTier = MetadataSearcher(items: Self.catalog, mode: .auto, selection: Self.makeSelectionConfig())
            let withoutTier = MetadataSearcher(items: Self.catalog, mode: .auto, onDiagnostic: { _ in })
            _ = try await withTier.search(intent: Self.query, limit: Self.searchLimit)
            _ = try await withoutTier.search(intent: Self.query, limit: Self.searchLimit)

            let searches = Self.spans(named: SpanName.search, in: context)
            #expect(searches.map { $0.attributes.get(Key.searchMode) } == [.string("auto"), .string("auto")])
            #expect(searches.map { $0.attributes.get(Key.searchTier) } == [.string("selection"), .string("retrieval")])
            let ranks = Self.spans(named: SpanName.rank, in: context)
            #expect(ranks.map(\.parentSpanID) == searches.map(\.spanID))
        }
    }

    @Test
    func selectionSearchWithNoSelectionTierEndsItsSpanWithAnErrorAndNoMessage() async throws {
        try await TelemetryCapture.run(forbidding: Self.forbidden) { context in
            let searcher = MetadataSearcher(items: Self.catalog, mode: .selection)
            await #expect(throws: SelectionTierUnavailable.self) {
                try await searcher.search(intent: Self.query, limit: Self.searchLimit)
            }

            let search = try Self.onlySpan(named: SpanName.search, in: context)
            #expect(search.status == SpanStatus(code: .error))
            #expect(search.attributes.get(Key.errorType) == .string("SelectionTierUnavailable"))
            #expect(search.attributes.get(Key.searchResultCount) == nil)
            #expect(Self.spans(named: SpanName.rank, in: context).isEmpty)
            let message = String(describing: SelectionTierUnavailable())
            #expect(!context.places.contains { $0.description.contains(message) })
        }
    }

    @Test
    func selectionSearchWhoseSessionThrowsRecordsTheErrorTypeAndNoMessage() async throws {
        try await TelemetryCapture.run(forbidding: Self.forbidden) { context in
            let factory = RecordingSessionFactory(responses: [])
            let searcher = MetadataSearcher(
                items: Self.catalog,
                mode: .selection,
                selection: SelectionConfig(model: factory.makeSession),
            )
            let error = try #require(await #expect(throws: (any Error).self) {
                try await searcher.search(intent: Self.query, limit: Self.searchLimit)
            })

            let errorType = String(describing: type(of: error))
            let search = try Self.onlySpan(named: SpanName.search, in: context)
            let rank = try Self.onlySpan(named: SpanName.rank, in: context)
            #expect(search.status == SpanStatus(code: .error))
            #expect(rank.status == SpanStatus(code: .error))
            #expect(search.attributes.get(Key.errorType) == .string(errorType))
            #expect(rank.attributes.get(Key.errorType) == .string(errorType))
            let message = String(describing: error)
            #expect(!context.places.contains { $0.description.contains(message) })
        }
    }
}

/// The catalog update and catalog embed spans.
extension RegistryTracingTests {
    // MARK: - Catalog update spans

    @Test
    func updateThatChangesTheContentEmbedsTheNewItemInAChildSpan() async throws {
        try await TelemetryCapture.run(forbidding: Self.forbidden) { context in
            let searcher = await MetadataSearcher(items: Self.catalog, mode: .retrieval, embedder: Self.makeEmbedder())
            await searcher.update(items: Self.reloadedCatalog)

            let update = try Self.onlySpan(named: SpanName.catalogUpdate, in: context)
            #expect(update.attributes.get(Key.catalogItemCount) == .int64(Int64(Self.reloadedCatalog.count)))
            #expect(update.attributes.get(Key.catalogSize) == .int64(Int64(Self.reloadedCatalog.count)))
            #expect(update.attributes.get(Key.catalogContentChanged) == .bool(true))
            #expect(update.attributes.get(Key.catalogPendingEmbedCount) == .int64(1))

            let reloads = Self.spans(named: SpanName.catalogEmbed, in: context)
                .filter { $0.attributes.get(Key.embedSource) == .string("reload") }
            try #require(reloads.count == 1)
            #expect(reloads[0].parentSpanID == update.spanID)
            #expect(reloads[0].attributes.get(Key.embedPendingCount) == .int64(1))
            #expect(reloads[0].attributes.get(Key.catalogSize) == .int64(Int64(Self.reloadedCatalog.count)))
            #expect(reloads[0].attributes.get(Key.embedOutcome) == .string("embedded"))
        }
    }

    @Test
    func updateWithIdenticalContentIsANoOpThatStillEndsItsSpan() async throws {
        try await TelemetryCapture.run(forbidding: Self.forbidden) { context in
            let searcher = await MetadataSearcher(items: Self.catalog, mode: .retrieval, embedder: Self.makeEmbedder())
            await searcher.update(items: Self.catalog)

            let update = try Self.onlySpan(named: SpanName.catalogUpdate, in: context)
            #expect(update.attributes.get(Key.catalogItemCount) == .int64(Int64(Self.catalog.count)))
            #expect(update.attributes.get(Key.catalogSize) == .int64(Int64(Self.catalog.count)))
            #expect(update.attributes.get(Key.catalogContentChanged) == .bool(false))
            #expect(update.attributes.get(Key.catalogPendingEmbedCount) == .int64(0))
            let reloads = Self.spans(named: SpanName.catalogEmbed, in: context)
                .filter { $0.attributes.get(Key.embedSource) == .string("reload") }
            #expect(reloads.isEmpty)
        }
    }

    @Test
    func reloadEmbedThatFailsEndsItsSpanWithTheFailedOutcome() async throws {
        try await TelemetryCapture.run(forbidding: Self.forbidden) { context in
            let searcher = await MetadataSearcher(
                items: Self.catalog,
                mode: .retrieval,
                embedder: Self.makeFailingEmbedder(),
                onDiagnostic: { _ in },
            )
            await searcher.update(items: Self.reloadedCatalog)

            let reloads = Self.spans(named: SpanName.catalogEmbed, in: context)
                .filter { $0.attributes.get(Key.embedSource) == .string("reload") }
            try #require(reloads.count == 1)
            #expect(reloads[0].attributes.get(Key.embedPendingCount) == .int64(Int64(Self.reloadedCatalog.count)))
            #expect(reloads[0].attributes.get(Key.embedOutcome) == .string("failed"))
        }
    }

    // MARK: - Catalog embed spans

    @Test
    func firstSearchCatchUpEmbedsInAChildSpanOfTheSearch() async throws {
        try await TelemetryCapture.run(forbidding: Self.forbidden) { context in
            let searcher = MetadataSearcher(
                index: MetadataIndex(items: Self.catalog),
                mode: .retrieval,
                embedder: Self.makeEmbedder(),
            )
            _ = try await searcher.search(intent: Self.query, limit: Self.searchLimit)

            let search = try Self.onlySpan(named: SpanName.search, in: context)
            let embed = try Self.onlySpan(named: SpanName.catalogEmbed, in: context)
            #expect(embed.parentSpanID == search.spanID)
            #expect(embed.attributes.get(Key.embedSource) == .string("first_search"))
            #expect(embed.attributes.get(Key.embedPendingCount) == .int64(Int64(Self.catalog.count)))
            #expect(embed.attributes.get(Key.catalogSize) == .int64(Int64(Self.catalog.count)))
            #expect(embed.attributes.get(Key.embedOutcome) == .string("embedded"))
        }
    }

    @Test
    func firstSearchCatchUpThatFailsEndsItsSpanWithTheFailedOutcome() async throws {
        try await TelemetryCapture.run(forbidding: Self.forbidden) { context in
            let searcher = MetadataSearcher(
                index: MetadataIndex(items: Self.catalog),
                mode: .retrieval,
                embedder: Self.makeFailingEmbedder(),
                onDiagnostic: { _ in },
            )
            _ = try await searcher.search(intent: Self.query, limit: Self.searchLimit)

            let embed = try Self.onlySpan(named: SpanName.catalogEmbed, in: context)
            #expect(embed.attributes.get(Key.embedSource) == .string("first_search"))
            #expect(embed.attributes.get(Key.embedOutcome) == .string("failed"))
        }
    }

    @Test
    func twoSearchersThatShareOneCatalogEmbedEndOneSharedEmbedSpan() async throws {
        try await TelemetryCapture.run(forbidding: Self.forbidden) { context in
            let shared = SharedCatalogEmbedding(
                index: MetadataIndex(items: Self.catalog),
                embedder: Self.makeEmbedder(),
                onDiagnostic: { _ in },
            )
            let first = MetadataSearcher(sharing: shared, mode: .retrieval)
            let second = MetadataSearcher(sharing: shared, mode: .retrieval)
            _ = try await first.search(intent: Self.query, limit: Self.searchLimit)
            _ = try await second.search(intent: Self.query, limit: Self.searchLimit)

            let embed = try Self.onlySpan(named: SpanName.catalogEmbed, in: context)
            #expect(embed.attributes.get(Key.embedSource) == .string("shared"))
            #expect(embed.attributes.get(Key.embedPendingCount) == .int64(Int64(Self.catalog.count)))
            #expect(embed.attributes.get(Key.catalogSize) == .int64(Int64(Self.catalog.count)))
            #expect(embed.attributes.get(Key.embedOutcome) == .string("embedded"))
        }
    }

    @Test
    func indexBuildEmbedsInABuildSpan() async throws {
        try await TelemetryCapture.run(forbidding: Self.forbidden) { context in
            _ = await MetadataIndex.build(items: Self.catalog, embedder: Self.makeEmbedder())

            let embed = try Self.onlySpan(named: SpanName.catalogEmbed, in: context)
            #expect(embed.attributes.get(Key.embedSource) == .string("build"))
            #expect(embed.attributes.get(Key.embedPendingCount) == .int64(Int64(Self.catalog.count)))
            #expect(embed.attributes.get(Key.catalogSize) == .int64(Int64(Self.catalog.count)))
            #expect(embed.attributes.get(Key.embedOutcome) == .string("embedded"))
        }
    }

    @Test
    func indexBuildWithNothingToEmbedOpensNoEmbedSpan() async throws {
        try await TelemetryCapture.run(forbidding: Self.forbidden) { context in
            let previous = await MetadataIndex.build(items: Self.catalog, embedder: Self.makeEmbedder())
            let embedsBefore = Self.spans(named: SpanName.catalogEmbed, in: context).count
            _ = await MetadataIndex.build(items: Self.catalog, embedder: Self.makeEmbedder(), previous: previous)
            _ = await MetadataIndex.build(items: Self.catalog, embedder: nil)

            #expect(Self.spans(named: SpanName.catalogEmbed, in: context).count == embedsBefore)
        }
    }
}
