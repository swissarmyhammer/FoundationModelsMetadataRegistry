@testable import FoundationModelsMetadataRegistry
import TelemetryTestSupport
import Testing

/// Holds the telemetry of this package to the rules of the OpenTelemetry
/// design of 2026-09-28.
///
/// Rule 3: each name of the vocabulary file ``RegistryTelemetry`` starts with
/// the module prefix, so a span, a log record or a metric of this package is
/// easy to find among the telemetry of the host application.
///
/// Rule 4: a span attribute, a log message, a log metadata value and a metric
/// dimension never hold the query text, the content of a catalog item or a
/// vector. Rule 5: this suite proves rule 4 with `TelemetryCapture` of
/// FoundationModelsExtras. Each test drives one public entry point inside a
/// capture, with a fixture that puts a unique marker in the query text and in
/// each text of an item. The capture records an issue for each place of the
/// telemetry that holds a marker.
///
/// Each test makes its searchers inside the capture, because a logger or a
/// metric that a searcher makes before the first capture does not reach the
/// capture. No test here bootstraps the logging system: the capture does
/// that one time for the process.
@Suite("Telemetry content safety")
struct TelemetryContentSafetyTests {
    /// The prefix that each telemetry name of this package starts with: the
    /// module name and a dot.
    private static let modulePrefix = "FoundationModelsMetadataRegistry."

    /// Each name of ``RegistryTelemetry``. A change that adds a name to
    /// ``RegistryTelemetry`` adds it to this list too.
    private static let registryNames = [
        RegistryTelemetry.loggerLabel,
        RegistryTelemetry.SpanName.search,
        RegistryTelemetry.SpanName.rank,
        RegistryTelemetry.SpanName.catalogUpdate,
        RegistryTelemetry.SpanName.catalogEmbed,
    ]

    @Test("Each RegistryTelemetry name starts with the module prefix", arguments: registryNames)
    func eachNameStartsWithTheModulePrefix(name: String) {
        #expect(name.hasPrefix(Self.modulePrefix))
    }

    // MARK: - Fixture

    /// The unique strings that the fixture puts in the query text, in each
    /// text of an item and in each vector. No telemetry place may hold one.
    private enum Marker {
        /// The marker in each query text.
        static let query = "QueryMarker7f3c"

        /// The marker in each rendered block.
        static let block = "BlockMarker2a9d"

        /// The marker in each text that the keyword signals index.
        static let indexedText = "IndexedMarker5e1b"

        /// The marker in each text that the embedder embeds.
        static let embeddedText = "EmbeddedMarker8c4f"

        /// The marker in each summary block that seeds the selection prefix.
        static let summary = "SummaryMarker6d0e"

        /// The component of each vector of the fixture. Its text is the
        /// vector marker, because a vector reaches telemetry as the text of
        /// its components.
        static let vectorComponent: Float = 0.918273

        /// Each marker, as the capture forbids it.
        static let all = [query, block, indexedText, embeddedText, summary, vectorComponent.description]
    }

    /// A catalog item that puts a marker in each of its texts. Its `id` holds
    /// no marker, because an id is safe in telemetry.
    private struct MarkedItem: SearchableMetadata {
        let id: String

        func renderBlock() -> String {
            "\(Marker.block) \(id) block"
        }

        func renderIndexedText(from block: String) -> String {
            "\(Marker.indexedText) \(block)"
        }

        func renderEmbeddedText(from block: String) -> String {
            "\(Marker.embeddedText) \(block)"
        }

        func renderSummaryBlock() -> String {
            "\(Marker.summary) \(id) summary"
        }
    }

    /// The catalog that each searcher starts from.
    private static let catalog = [MarkedItem(id: "deploy"), MarkedItem(id: "rollback")]

    /// The catalog that `update(items:)` loads. It adds one item, so the
    /// reload changes the content and embeds the new item.
    private static let reloadedCatalog = catalog + [MarkedItem(id: "restart")]

    /// The query text of each search.
    private static let query = "\(Marker.query) deploy block"

    /// The `limit` of each search. It is larger than each catalog, so no
    /// result is cut.
    private static let searchLimit = 10

    /// The width of each vector of the fixture.
    private static let embeddingDimension = 2

    /// The vector of the query and of each embedded text of both catalogs.
    private static let vectorsByText: [String: [Float]] = {
        let vector = [Float](repeating: Marker.vectorComponent, count: embeddingDimension)
        let embeddedTexts = reloadedCatalog.map { $0.renderEmbeddedText(from: $0.renderBlock()) }
        return Dictionary(uniqueKeysWithValues: ([query] + embeddedTexts).map { ($0, vector) })
    }()

    /// The id that the query text names, and that the scripted selection
    /// model picks.
    private static let selectedID = catalog[0].id

    /// Makes an embedder that gives the fixture vector for each fixture text.
    private static func makeEmbedder() -> FakeEmbedder {
        FakeEmbedder(dimension: embeddingDimension, vectorsByText: vectorsByText)
    }

    /// Makes a selection configuration whose scripted model picks
    /// `selectedID`.
    private static func makeSelectionConfig() -> SelectionConfig {
        let factory = RecordingSessionFactory(responses: [#"{"ids":["\#(selectedID)"]}"#])
        return SelectionConfig(model: factory.makeSession)
    }

    /// One sample of each case of `MetadataDiagnostic`, with the fixture ids.
    /// A change that adds a case adds a sample here too.
    private static let diagnostics: [MetadataDiagnostic] = [
        .duplicateId(id: catalog[0].id),
        .embeddingUnavailable,
        .unknownSelectedId(id: catalog[1].id),
        .retrievalCut(considered: catalog.count, kept: 1),
        .embedCatchUp(pending: 1, total: catalog.count),
    ]

    // MARK: - No content in the telemetry

    @Test
    func retrievalSearchWithAnEmbedderKeepsContentOutOfTheTelemetry() async throws {
        let matches = try await TelemetryCapture.run(forbidding: Marker.all) { _ in
            let searcher = await MetadataSearcher(items: Self.catalog, mode: .retrieval, embedder: Self.makeEmbedder())
            return try await searcher.search(intent: Self.query, limit: Self.searchLimit)
        }

        #expect(matches.first?.id == Self.selectedID)
    }

    @Test
    func selectionSearchKeepsContentOutOfTheTelemetry() async throws {
        let matches = try await TelemetryCapture.run(forbidding: Marker.all) { _ in
            let searcher = MetadataSearcher(
                items: Self.catalog,
                mode: .selection,
                selection: Self.makeSelectionConfig(),
            )
            return try await searcher.search(intent: Self.query, limit: Self.searchLimit)
        }

        #expect(matches.map(\.id) == [Self.selectedID])
    }

    /// An error path can leak content too: the search span and the rank span
    /// record the failure of the session, and the capture checks both.
    @Test
    func selectionSearchWhoseSessionThrowsKeepsContentOutOfTheTelemetry() async throws {
        try await TelemetryCapture.run(forbidding: Marker.all) { context in
            let factory = RecordingSessionFactory(responses: [])
            let searcher = MetadataSearcher(
                items: Self.catalog,
                mode: .selection,
                selection: SelectionConfig(model: factory.makeSession),
            )
            await #expect(throws: (any Error).self) {
                try await searcher.search(intent: Self.query, limit: Self.searchLimit)
            }

            #expect(context.spans.contains { $0.status?.code == .error })
        }
    }

    @Test
    func updateItemsKeepsContentOutOfTheTelemetry() async throws {
        let matches = try await TelemetryCapture.run(forbidding: Marker.all) { _ in
            let searcher = await MetadataSearcher(items: Self.catalog, mode: .retrieval, embedder: Self.makeEmbedder())
            await searcher.update(items: Self.reloadedCatalog)
            return try await searcher.search(intent: Self.query, limit: Self.searchLimit)
        }

        #expect(Set(matches.map(\.id)) == Set(Self.reloadedCatalog.map(\.id)))
    }

    @Test
    func searchersThatShareOneCatalogEmbedKeepContentOutOfTheTelemetry() async throws {
        let (retrievalMatches, selectionMatches) = try await TelemetryCapture.run(forbidding: Marker.all) { _ in
            let shared = SharedCatalogEmbedding(
                index: MetadataIndex(items: Self.catalog),
                embedder: Self.makeEmbedder(),
            )
            let retrieval = MetadataSearcher(sharing: shared, mode: .retrieval)
            let selection = MetadataSearcher(sharing: shared, mode: .selection, selection: Self.makeSelectionConfig())
            let retrievalMatches = try await retrieval.search(intent: Self.query, limit: Self.searchLimit)
            let selectionMatches = try await selection.search(intent: Self.query, limit: Self.searchLimit)
            return (retrievalMatches, selectionMatches)
        }

        #expect(retrievalMatches.first?.id == Self.selectedID)
        #expect(selectionMatches.map(\.id) == [Self.selectedID])
    }

    /// The capture is the assertion: it records an issue for each telemetry
    /// place of the log call that holds a marker.
    @Test(arguments: diagnostics)
    func loggingADiagnosticKeepsContentOutOfTheTelemetry(diagnostic: MetadataDiagnostic) async throws {
        try await TelemetryCapture.run(forbidding: Marker.all) { _ in
            MetadataDiagnostic.log(diagnostic)
        }
    }
}
