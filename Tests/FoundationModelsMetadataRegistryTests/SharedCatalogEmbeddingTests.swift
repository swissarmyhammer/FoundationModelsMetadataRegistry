@testable import FoundationModelsMetadataRegistry
import Testing

/// Tests for `SharedCatalogEmbedding` and `MetadataSearcher.init(sharing:
/// mode:weights:selection:onDiagnostic:)` (plan.md §5, §8): two or more
/// searchers that are built synchronously over one index share one
/// first-search embed of the catalog. Every embedder here is a scripted fake
/// behind the `TextEmbedding` seam.
struct SharedCatalogEmbeddingTests {
    typealias FixtureItem = EmbeddingTests.FixtureItem

    // MARK: - Fixtures

    /// The catalog that every test in this suite searches. No item carries an
    /// embedding when the index is built.
    static let catalog = [
        FixtureItem(id: "commit", block: "records a snapshot of staged changes"),
        FixtureItem(id: "status", block: "reports the state of the working tree"),
        FixtureItem(id: "push", block: "uploads local commits to a remote"),
        FixtureItem(id: "log", block: "shows the history of commits"),
    ]

    /// The rendered blocks of `catalog`, in catalog order. This is the one
    /// batch that a catalog embed gives to the embedder.
    static let catalogBlocks = catalog.map(\.block)

    /// Three fixed queries. Each query has a vector in `vectorsByText`, so
    /// cosine contributes to each ranking.
    static let queries = ["save my work", "send to the server", "working tree"]

    /// The width of every vector in `vectorsByText`.
    static let embeddingDimension = 3

    /// The `limit` of every search in this suite. It is larger than the
    /// catalog, so no result is cut and each test reads the full ranking.
    static let searchLimit = 10

    /// The vector of each catalog block and each query.
    static let vectorsByText: [String: [Float]] = [
        catalog[0].block: [1, 0, 0],
        catalog[1].block: [0, 1, 0],
        catalog[2].block: [0, 0, 1],
        catalog[3].block: [1, 1, 0],
        queries[0]: [1, 0, 0],
        queries[1]: [0, 0, 1],
        queries[2]: [0, 1, 0],
    ]

    /// Two different weight sets for the ranking parity test.
    static let weightSets = [Weights(), Weights(bm25: 0.5, trigram: 0.25, cosine: 2.0)]

    /// A counting `FakeEmbedder` that maps each text in `vectorsByText`.
    static func countingEmbedder() -> FakeEmbedder {
        FakeEmbedder(dimension: embeddingDimension, vectorsByText: vectorsByText)
    }

    /// The error that the failing embedder throws.
    struct EmbedFailure: Error {}

    // MARK: - One catalog embed for two searchers

    @Test
    func twoSharingSearchersEmbedTheCatalogOneTimeAtTheFirstSearch() async throws {
        let embedder = Self.countingEmbedder()
        let shared = SharedCatalogEmbedding(index: MetadataIndex(items: Self.catalog), embedder: embedder)
        let first = MetadataSearcher(sharing: shared)
        let second = MetadataSearcher(sharing: shared)
        // Construction embeds nothing: the catalog embed occurs at the first
        // search, not at init.
        #expect(embedder.embeddedBatches.isEmpty)

        _ = try await first.search(intent: Self.queries[0], limit: Self.searchLimit)
        _ = try await second.search(intent: Self.queries[1], limit: Self.searchLimit)

        // One catalog batch in total, then one query batch for each search.
        #expect(embedder.embeddedBatches == [Self.catalogBlocks, [Self.queries[0]], [Self.queries[1]]])
    }

    @Test
    func sharedEmbeddingReportsEmbedCatchUpOneTime() async throws {
        let recorder = DiagnosticRecorder()
        let shared = SharedCatalogEmbedding(
            index: MetadataIndex(items: Self.catalog),
            embedder: Self.countingEmbedder(),
            onDiagnostic: { recorder.record($0) },
        )
        let first = MetadataSearcher(sharing: shared, onDiagnostic: { recorder.record($0) })
        let second = MetadataSearcher(sharing: shared, onDiagnostic: { recorder.record($0) })

        _ = try await first.search(intent: Self.queries[0], limit: Self.searchLimit)
        _ = try await second.search(intent: Self.queries[0], limit: Self.searchLimit)

        // One report for the one catalog embed, and no `.embeddingUnavailable`:
        // each searcher ranks over the shared vectors.
        let catalogCount = Self.catalog.count
        #expect(recorder.diagnostics == [.embedCatchUp(pending: catalogCount, total: catalogCount)])
    }

    /// Bounded because the gate has no timeout of its own: a shared value
    /// that never starts the catalog embed never signals the gate, and this
    /// test must then fail rather than wait forever.
    @Test(.timeLimit(.minutes(1)))
    func twoConcurrentFirstSearchesOnTwoSharingSearchersEmbedTheCatalogOneTime() async throws {
        let gate = EmbedGate()
        // Only the catalog batch is gated, so the query embed of each search
        // resolves at once after the catalog embed lets it through.
        let embedder = GatedEmbedder(
            dimension: Self.embeddingDimension,
            vectorsByText: Self.vectorsByText,
            gate: gate,
            gatedTexts: Set(Self.catalogBlocks),
        )
        let shared = SharedCatalogEmbedding(index: MetadataIndex(items: Self.catalog), embedder: embedder)
        let firstSearcher = MetadataSearcher(sharing: shared)
        let secondSearcher = MetadataSearcher(sharing: shared)

        async let firstMatches = firstSearcher.search(intent: Self.queries[0], limit: Self.searchLimit)
        // The catalog embed is now suspended inside the embedder, so the
        // second search starts while the catalog is still pending.
        await gate.waitForStart()
        async let secondMatches = secondSearcher.search(intent: Self.queries[0], limit: Self.searchLimit)
        await gate.release()
        let (first, second) = try await (firstMatches, secondMatches)

        #expect(embedder.embeddedBatches.count(where: { $0 == Self.catalogBlocks }) == 1)
        #expect(first.first?.signals?.cosine != 0.0)
        #expect(second.first?.signals?.cosine != 0.0)
    }

    // MARK: - Ranking parity

    @Test(arguments: weightSets)
    func sharingSearcherRanksTheSameAsASearcherWithItsOwnCatchUp(weights: Weights) async throws {
        let index = MetadataIndex(items: Self.catalog)
        let shared = SharedCatalogEmbedding(index: index, embedder: Self.countingEmbedder())
        let sharing = MetadataSearcher(sharing: shared, mode: .retrieval, weights: weights)
        let alone = MetadataSearcher(
            index: index, mode: .retrieval, weights: weights, embedder: Self.countingEmbedder(),
        )

        for query in Self.queries {
            let sharedMatches = try await sharing.search(intent: query, limit: Self.searchLimit)
            let aloneMatches = try await alone.search(intent: query, limit: Self.searchLimit)

            #expect(!sharedMatches.isEmpty)
            #expect(sharedMatches.map(\.id) == aloneMatches.map(\.id))
            #expect(sharedMatches.map(\.score) == aloneMatches.map(\.score))
            #expect(sharedMatches.map(\.signals) == aloneMatches.map(\.signals))
        }
    }

    // MARK: - Failure and isolation

    @Test
    func failedCatalogEmbedLeavesBothSearchersKeywordOnlyWithNoSecondCatalogEmbed() async throws {
        let embedder = FakeEmbedder(dimension: Self.embeddingDimension, failure: EmbedFailure())
        let shared = SharedCatalogEmbedding(index: MetadataIndex(items: Self.catalog), embedder: embedder)
        let first = MetadataSearcher(sharing: shared)
        let second = MetadataSearcher(sharing: shared)

        var everyMatch: [Match<FixtureItem>] = []
        for query in Self.queries {
            try await everyMatch += first.search(intent: query, limit: Self.searchLimit)
            try await everyMatch += second.search(intent: query, limit: Self.searchLimit)
        }

        // Keyword signals still answer, and cosine contributes nothing.
        #expect(!everyMatch.isEmpty)
        #expect(everyMatch.allSatisfy { $0.signals?.cosine == 0.0 })
        // The failed catalog embed is not tried again, by either searcher.
        #expect(embedder.embeddedBatches.count(where: { $0 == Self.catalogBlocks }) == 1)
    }

    @Test
    func updateOnOneSharingSearcherLeavesTheOtherSearcherUnchanged() async throws {
        let shared = SharedCatalogEmbedding(
            index: MetadataIndex(items: Self.catalog), embedder: Self.countingEmbedder(),
        )
        let updated = MetadataSearcher(sharing: shared, mode: .retrieval)
        let untouched = MetadataSearcher(sharing: shared, mode: .retrieval)
        let added = FixtureItem(id: "rebase", block: "replays commits onto another base")

        await updated.update(items: Self.catalog + [added])

        let updatedIDs = try await updated.search(intent: "rebase", limit: Self.searchLimit).map(\.id)
        let untouchedIDs = try await untouched.search(intent: "rebase", limit: Self.searchLimit).map(\.id)
        #expect(updatedIDs.contains(added.id))
        #expect(!untouchedIDs.contains(added.id))
    }
}
