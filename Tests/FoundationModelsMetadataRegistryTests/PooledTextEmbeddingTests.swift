import FoundationModelsExtras
@testable import FoundationModelsMetadataRegistry
import Testing

/// Tests for `PooledTextEmbedding` and the `MetadataSearcher` initializer
/// that takes a pooled embedding `ModelRef` (plan.md §5, decision #16).
///
/// Each test uses its own `ModelPool()`, never `ModelPool.shared`, so that
/// the tests share no state. The loaders and the containers are stubs, so no
/// test loads a real model.
struct PooledTextEmbeddingTests {
    // MARK: - Fixtures

    struct FixtureItem: SearchableMetadata {
        let id: String
        let block: String

        func renderBlock() -> String {
            block
        }
    }

    /// The embedding model that each test acquires.
    static let embeddingModel: ModelRef = "stub-org/stub-embedder"

    /// The pool key of `embeddingModel`.
    static let embeddingKey = ModelPoolKey(ref: embeddingModel, role: .embedding)

    /// The bytes of the weights of the stub model.
    static let footprintBytes: Int64 = 4096

    /// The length of each stub vector.
    static let dimension = 2

    /// The vector of each fixture block.
    static let vectorsByText: [String: [Float]] = ["alpha block": [1, 0], "bravo block": [0, 1]]

    /// The catalog of each searcher.
    static let items = [FixtureItem(id: "a", block: "alpha block"), FixtureItem(id: "b", block: "bravo block")]

    /// The number of `update(items:)` calls that each searcher sends in
    /// series, while the other searcher sends its own.
    static let updatesPerSearcher = 8

    /// Makes a stub loader over a new stub model.
    static func makeLoader() -> StubModelLoader {
        StubModelLoader(container: StubEmbeddingModel(dimension: dimension, vectorsByText: vectorsByText))
    }

    /// Makes a searcher over `items` that acquires `embeddingModel` from `pool` through `loader`.
    static func makeSearcher(loader: StubModelLoader, pool: ModelPool) async throws -> MetadataSearcher<FixtureItem> {
        try await MetadataSearcher(
            items: items,
            embeddingModel: embeddingModel,
            footprintBytes: footprintBytes,
            loader: loader,
            pool: pool,
        )
    }

    /// Expects that `searcher` stored the vector of each fixture block.
    static func expectFixtureVectors(in searcher: MetadataSearcher<FixtureItem>) async {
        #expect(await searcher.index.embedding(forID: "a") == [1, 0])
        #expect(await searcher.index.embedding(forID: "b") == [0, 1])
    }

    // MARK: - One load for each key

    @Test
    func twoSearchersShareOneLoad() async throws {
        let pool = ModelPool()
        let loader = Self.makeLoader()

        let first = try await Self.makeSearcher(loader: loader, pool: pool)
        let second = try await Self.makeSearcher(loader: loader, pool: pool)

        #expect(await loader.loadCount == 1)
        #expect(pool.residentModelCount == 1)
        await Self.expectFixtureVectors(in: first)
        await Self.expectFixtureVectors(in: second)
    }

    // MARK: - One queue for each model

    @Test(.timeLimit(.minutes(1)))
    func concurrentUpdatesRunOneAtATime() async throws {
        let pool = ModelPool()
        let loader = Self.makeLoader()
        let first = try await Self.makeSearcher(loader: loader, pool: pool)
        let second = try await Self.makeSearcher(loader: loader, pool: pool)
        let batchesBeforeUpdates = await loader.container.embeddedBatches.count

        // Each searcher sends its updates in series, so each update embeds
        // one new item: a searcher coalesces the updates that arrive while
        // its own embed is in flight (plan.md §8). The two searchers run at
        // the same time, so only the pool keeps their embed calls apart.
        await withTaskGroup(of: Void.self) { group in
            for searcher in [first, second] {
                group.addTask {
                    for index in 0 ..< Self.updatesPerSearcher {
                        let items = Self.items + [FixtureItem(id: "item-\(index)", block: "block \(index)")]
                        await searcher.update(items: items)
                    }
                }
            }
        }

        let searchers = [first, second]
        let updateCount = searchers.count * Self.updatesPerSearcher
        #expect(await loader.container.embeddedBatches.count == batchesBeforeUpdates + updateCount)
        #expect(await loader.container.maximumCallsInFlight == 1)
    }

    // MARK: - Eviction

    /// Builds two searchers that share `embeddingModel`, expects the model to
    /// be resident, and then releases both searchers when it returns.
    static func buildAndReleaseTwoSearchers(loader: StubModelLoader, pool: ModelPool) async throws {
        let first = try await makeSearcher(loader: loader, pool: pool)
        let second = try await makeSearcher(loader: loader, pool: pool)
        #expect(pool.isResident(embeddingKey))
        await expectFixtureVectors(in: first)
        await expectFixtureVectors(in: second)
    }

    @Test(.timeLimit(.minutes(1)))
    func releasingBothSearchersEvictsTheModel() async throws {
        let pool = ModelPool()
        let loader = Self.makeLoader()

        try await Self.buildAndReleaseTwoSearchers(loader: loader, pool: pool)

        var evictions = loader.evictions.makeAsyncIterator()
        let eviction: Void? = await evictions.next()
        #expect(eviction != nil)
        #expect(!pool.isResident(Self.embeddingKey))
    }

    // MARK: - The first loader wins

    @Test
    func firstLoaderWinsAndSearcherEmbedsThroughProtocol() async throws {
        let pool = ModelPool()
        let loaderA = Self.makeLoader()
        let loaderB = Self.makeLoader()
        let holdA = try await pool.acquire(
            Self.embeddingKey,
            footprintBytes: Self.footprintBytes,
            sessionBytes: PooledTextEmbedding.embeddingSessionBytes,
            loader: loaderA,
        )

        let searcher = try await Self.makeSearcher(loader: loaderB, pool: pool)

        #expect(await loaderA.loadCount == 1)
        #expect(await loaderB.loadCount == 0)
        #expect(await loaderA.container.embeddedBatches == [["alpha block", "bravo block"]])
        #expect(await loaderB.container.embeddedBatches.isEmpty)
        await Self.expectFixtureVectors(in: searcher)
        #expect(holdA.key == Self.embeddingKey)
    }
}
