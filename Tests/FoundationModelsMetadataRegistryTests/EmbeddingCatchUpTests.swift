@testable import FoundationModelsMetadataRegistry
import Testing

/// First-search embed catch-up for a synchronously built searcher
/// (plan.md §5, §8): a `MetadataSearcher` built with `init(index:mode:
/// weights:embedder:selection:onDiagnostic:)` over not-yet-embedded items
/// embeds every pending block at its first search, one time, whichever tier
/// answers. Split out of `EmbeddingTests` to keep each file within the
/// project's line-length conventions; shares its `FixtureItem` fixture via
/// `EmbeddingTests`.
extension EmbeddingTests {
    // MARK: - First-search embed catch-up for a synchronously built searcher

    /// The catalog every first-search catch-up test below searches: two items
    /// with no stored embedding, indexed synchronously.
    static let unembeddedItems = [
        FixtureItem(id: "a", block: "alpha block"),
        FixtureItem(id: "b", block: "bravo block"),
    ]

    /// The query the first-search catch-up tests search for.
    static let catchUpQuery = "alpha"

    /// The width of every vector the first-search catch-up tests embed.
    ///
    /// Two components are enough to give one item a cosine of `1.0` against
    /// `catchUpQuery` and the other a cosine of `0.0`.
    static let catchUpEmbeddingDimension = 2

    /// The `limit` the first-search catch-up tests search with.
    ///
    /// Larger than any catalog those tests index, so the limit never
    /// truncates a result and every test reads the whole ranking.
    static let catchUpSearchLimit = 5

    /// A `FakeEmbedder` that maps every block of `unembeddedItems` and the
    /// `catchUpQuery` to a real vector, so a caught-up search can rank by
    /// cosine.
    static func catchUpEmbedder() -> FakeEmbedder {
        FakeEmbedder(
            dimension: catchUpEmbeddingDimension,
            vectorsByText: [
                unembeddedItems[0].block: [1, 0],
                unembeddedItems[1].block: [0, 1],
                catchUpQuery: [1, 0],
            ],
        )
    }

    @Test
    func searcherBuiltSynchronouslyWithAnEmbedderEmbedsEveryBlockAtItsFirstSearchAndOnlyThen() async throws {
        let embedder = Self.catchUpEmbedder()
        let searcher = MetadataSearcher(index: MetadataIndex(items: Self.unembeddedItems), embedder: embedder)
        // Construction embeds nothing: the synchronous initializer cannot
        // await an embedder, and no search has asked for cosine yet.
        #expect(embedder.embeddedBatches.isEmpty)

        _ = try await searcher.search(intent: Self.catchUpQuery, limit: Self.catchUpSearchLimit)

        // The first search embeds every catalog block in one batch, then the
        // query itself.
        let catalogBlocks = Self.unembeddedItems.map(\.block)
        #expect(embedder.embeddedBatches == [catalogBlocks, [Self.catchUpQuery]])

        _ = try await searcher.search(intent: Self.catchUpQuery, limit: Self.catchUpSearchLimit)

        // The second search embeds the query only -- the catalog is caught
        // up and is never re-embedded.
        #expect(embedder.embeddedBatches == [catalogBlocks, [Self.catchUpQuery], [Self.catchUpQuery]])
    }

    @Test
    func firstSearchRanksByCosineOnceTheCatalogIsCaughtUp() async throws {
        let searcher = MetadataSearcher(
            index: MetadataIndex(items: Self.unembeddedItems), embedder: Self.catchUpEmbedder(),
        )

        let matches = try await searcher.search(intent: Self.catchUpQuery, limit: Self.catchUpSearchLimit)

        let first = try #require(matches.first)
        #expect(first.id == "a")
        #expect(first.signals?.cosine != 0.0)
    }

    @Test
    func firstSearchReportsEmbedCatchUpOneTimeAndNeverEmbeddingUnavailable() async throws {
        let recorder = DiagnosticRecorder()
        let searcher = MetadataSearcher(
            index: MetadataIndex(items: Self.unembeddedItems),
            embedder: Self.catchUpEmbedder(),
            onDiagnostic: { recorder.record($0) },
        )

        _ = try await searcher.search(intent: Self.catchUpQuery, limit: Self.catchUpSearchLimit)
        _ = try await searcher.search(intent: Self.catchUpQuery, limit: Self.catchUpSearchLimit)

        // Exactly one catch-up report across both searches, and no
        // `.embeddingUnavailable` at all: the catalog is embedded before the
        // first search ranks.
        let catalogCount = Self.unembeddedItems.count
        #expect(recorder.diagnostics == [.embedCatchUp(pending: catalogCount, total: catalogCount)])
    }

    /// Bounded because the gate below has no timeout of its own: a searcher
    /// that never starts the catch-up never signals the gate, and this test
    /// must then fail rather than wait forever.
    @Test(.timeLimit(.minutes(1)))
    func twoConcurrentFirstSearchesEmbedTheCatalogOneTime() async throws {
        let item = FixtureItem(id: "commit", block: "records a snapshot of staged changes")
        let query = "snapshot"
        let gate = EmbedGate()
        // Only the catalog block is gated, so each search's own query embed
        // resolves immediately once the catch-up lets it through.
        let embedder = GatedEmbedder(
            dimension: Self.catchUpEmbeddingDimension,
            vectorsByText: [item.block: [1, 0], query: [1, 0]],
            gate: gate,
            gatedTexts: [item.block],
        )
        let recorder = DiagnosticRecorder()
        let searcher = MetadataSearcher(
            index: MetadataIndex(items: [item]),
            embedder: embedder,
            onDiagnostic: { recorder.record($0) },
        )

        async let firstMatches = searcher.search(intent: query, limit: Self.catchUpSearchLimit)
        // The first search's catch-up is now suspended inside the embedder,
        // so the second search starts while the catalog is still pending.
        await gate.waitForStart()
        async let secondMatches = searcher.search(intent: query, limit: Self.catchUpSearchLimit)
        await gate.release()
        let (first, second) = try await (firstMatches, secondMatches)

        // One catch-up batch for the catalog, then one query embed per
        // search -- the second search waited for the first search's catch-up
        // instead of starting its own.
        #expect(embedder.embeddedBatches.count(where: { $0 == [item.block] }) == 1)
        #expect(recorder.diagnostics == [.embedCatchUp(pending: 1, total: 1)])
        #expect(first.first?.signals?.cosine != 0.0)
        #expect(second.first?.signals?.cosine != 0.0)
    }

    @Test
    func firstSelectionSearchCatchesUpTheCatalogBeforeTheTierRanks() async throws {
        let recorder = DiagnosticRecorder()
        let factory = RecordingSessionFactory(responses: [#"{"ids":["a"]}"#])
        let searcher = MetadataSearcher(
            index: MetadataIndex(items: Self.unembeddedItems),
            mode: .selection,
            embedder: Self.catchUpEmbedder(),
            selection: SelectionConfig(model: factory.makeSession),
            onDiagnostic: { recorder.record($0) },
        )

        let matches = try await searcher.search(intent: Self.catchUpQuery, limit: Self.catchUpSearchLimit)

        // The tier's candidate ranking runs over the caught-up snapshot: the
        // selected item carries a real cosine score, and no
        // `.embeddingUnavailable` was reported on the way.
        let catalogCount = Self.unembeddedItems.count
        #expect(matches.first?.signals?.cosine != 0.0)
        #expect(recorder.diagnostics == [.embedCatchUp(pending: catalogCount, total: catalogCount)])
    }

    @Test
    func searcherBuiltWithNoEmbedderNeverReportsEmbedCatchUpAtItsFirstSearch() async throws {
        let recorder = DiagnosticRecorder()
        let searcher = MetadataSearcher(items: Self.unembeddedItems, onDiagnostic: { recorder.record($0) })

        _ = try await searcher.search(intent: Self.catchUpQuery, limit: Self.catchUpSearchLimit)

        // Unchanged keyword-only degradation: no catch-up to report, and the
        // absent cosine signal is still reported, never silent.
        #expect(recorder.diagnostics == [.embeddingUnavailable])
    }
}
