@testable import FoundationModelsMetadataRegistry
import Testing

/// A burst of `MetadataSearcher.update(items:)` calls that arrives while an
/// embed is in flight (plan.md §8): the searcher embeds only the newest
/// catalog, never the catalogs between the first and the newest. Shares the
/// `FixtureItem` fixture of `HotReloadTests`.
extension HotReloadTests {
    // MARK: - Fixtures

    /// The number of `update(items:)` calls the burst sends while the first embed is blocked.
    static let burstUpdateCount = 5

    /// The item of the first catalog. Only the embed of its text blocks on the gate.
    static let firstBurstItem = FixtureItem(id: "first", block: "first catalog block")

    /// An item that every burst catalog holds, and the first catalog does not.
    static let sharedBurstItem = FixtureItem(id: "shared", block: "shared burst block")

    /// The catalog that update `number` of the burst sends.
    ///
    /// - Parameter number: the position of the update in the burst, from 1.
    /// - Returns: `sharedBurstItem` and one item that only this update sends.
    static func burstCatalog(_ number: Int) -> [FixtureItem] {
        [sharedBurstItem, FixtureItem(id: "burst-\(number)", block: "burst block \(number)")]
    }

    /// A searcher whose first embed is blocked while a burst of updates arrives.
    struct BlockedBurst {
        /// The searcher under test.
        let searcher: MetadataSearcher<FixtureItem>

        /// The embedder that records every embed call of `searcher`.
        let embedder: GatedEmbedder

        /// The gate that holds the embed of the first catalog.
        let gate: EmbedGate

        /// The updates that are still in flight: the first one and each one of the burst.
        let updates: [Task<Void, Never>]

        /// Releases the gate and waits for every update to return.
        func finish() async {
            await gate.release()
            for update in updates {
                await update.value
            }
        }
    }

    /// Starts one update, blocks its embed, and then sends `burstUpdateCount` more updates.
    ///
    /// Each burst update runs in its own task. This helper waits until the
    /// keyword index of each update is live before it sends the next, so the
    /// updates arrive in order and every one of them arrives while the first
    /// embed is blocked.
    ///
    /// - Parameter recorder: the recorder that receives every diagnostic of the searcher.
    /// - Returns: the blocked burst. The caller must call `finish()`.
    static func startBlockedBurst(recorder: DiagnosticRecorder) async -> BlockedBurst {
        let gate = EmbedGate()
        let embedder = GatedEmbedder(gate: gate, gatedTexts: [firstBurstItem.block])
        let searcher = await MetadataSearcher(
            items: [FixtureItem](),
            mode: .retrieval,
            embedder: embedder,
            onDiagnostic: { recorder.record($0) },
        )

        var updates = [Task { await searcher.update(items: [firstBurstItem]) }]
        await gate.waitForStart()
        for number in 1 ... burstUpdateCount {
            let catalog = burstCatalog(number)
            updates.append(Task { await searcher.update(items: catalog) })
            let ids = catalog.map(\.id)
            await waitUntilIndex(of: searcher) { $0.ids == ids }
        }
        return BlockedBurst(searcher: searcher, embedder: embedder, gate: gate, updates: updates)
    }

    /// Waits until the live index of `searcher` satisfies `condition`.
    ///
    /// An `update(items:)` call assigns its keyword index before it awaits
    /// the embed loop, so this is how a test knows that an update running in
    /// its own task has arrived. Returns early when the task is cancelled, so
    /// a test time limit ends the wait.
    ///
    /// - Parameters:
    ///   - searcher: the searcher to read the index of.
    ///   - condition: the test that the index must pass.
    static func waitUntilIndex(
        of searcher: MetadataSearcher<FixtureItem>,
        satisfies condition: (MetadataIndex<FixtureItem>) -> Bool,
    ) async {
        while !Task.isCancelled, await !condition(searcher.index) {
            await Task.yield()
        }
    }

    // MARK: - Tests

    @Test(.timeLimit(.minutes(1)))
    func burstEmbedsOnlyTheNewestCatalog() async {
        let recorder = DiagnosticRecorder()
        let burst = await Self.startBlockedBurst(recorder: recorder)

        await burst.finish()

        // The embed in flight, then one embed for the newest catalog: no
        // embed for any catalog between them.
        let newestTexts = Self.burstCatalog(Self.burstUpdateCount).map(\.block)
        #expect(burst.embedder.embeddedBatches == [[Self.firstBurstItem.block], newestTexts])
        // One `.embedCatchUp` for each real embed call, not one for each update.
        #expect(
            recorder.diagnostics == [
                .embedCatchUp(pending: 1, total: 1),
                .embedCatchUp(pending: newestTexts.count, total: newestTexts.count),
            ],
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func burstLeavesNoPendingEmbeddings() async {
        let burst = await Self.startBlockedBurst(recorder: DiagnosticRecorder())

        await burst.finish()

        let index = await burst.searcher.index
        #expect(index.ids == Self.burstCatalog(Self.burstUpdateCount).map(\.id))
        #expect(index.pendingEmbeddings().ids.isEmpty)
        for id in index.ids {
            #expect(index.embedding(forID: id) != nil)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func keywordSearchSeesEachUpdateAtOnce() async throws {
        let burst = await Self.startBlockedBurst(recorder: DiagnosticRecorder())
        let newestItem = try #require(Self.burstCatalog(Self.burstUpdateCount).last)

        // The first embed is still blocked, so only the keyword index can
        // find the item that only the newest update added.
        let matches = try await burst.searcher.search(intent: newestItem.block, limit: 5)

        await burst.finish()
        #expect(matches.first?.id == newestItem.id)
        #expect(matches.first?.signals?.cosine == 0.0)
    }
}
