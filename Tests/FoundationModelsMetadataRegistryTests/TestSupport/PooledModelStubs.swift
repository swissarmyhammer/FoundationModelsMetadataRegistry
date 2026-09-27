import FoundationModelsExtras

/// A stub embedding container for `ModelPool` tests. It loads no real model.
///
/// It records the texts of each `embed(texts:)` call, and the maximum number
/// of calls that ran at the same time. Each call suspends a number of times
/// before it returns, so that a second call that is not queued behind it
/// can start while it runs. Thus `maximumCallsInFlight` is more than 1 when
/// the calls do not go through one queue.
actor StubEmbeddingModel: PooledEmbedding {
    /// The number of times each call suspends before it returns.
    static let suspensionsPerCall = 50

    /// The length of each vector.
    nonisolated let dimension: Int

    /// Exact-text to vector lookup table. A text absent from this table
    /// embeds to an all-zero vector.
    private let vectorsByText: [String: [Float]]

    /// The texts of each `embed(texts:)` call, in call order.
    private(set) var embeddedBatches: [[String]] = []

    /// The number of calls that run now.
    private var callsInFlight = 0

    /// The maximum number of calls that ran at the same time.
    private(set) var maximumCallsInFlight = 0

    /// Makes a stub model that gives the vectors of `vectorsByText`.
    ///
    /// - Parameters:
    ///   - dimension: the length of each vector.
    ///   - vectorsByText: exact-text to vector lookup table.
    init(dimension: Int, vectorsByText: [String: [Float]]) {
        self.dimension = dimension
        self.vectorsByText = vectorsByText
    }

    /// Records the call, suspends `suspensionsPerCall` times, and gives one
    /// vector for each text.
    ///
    /// - Parameter texts: the texts to embed.
    /// - Returns: one vector for each text, in the order of `texts`.
    func embed(texts: [String]) async throws -> [[Float]] {
        embeddedBatches.append(texts)
        callsInFlight += 1
        maximumCallsInFlight = max(maximumCallsInFlight, callsInFlight)
        defer { callsInFlight -= 1 }
        for _ in 0 ..< Self.suspensionsPerCall {
            await Task.yield()
        }
        return texts.map { vectorsByText[$0] ?? [Float](repeating: 0, count: dimension) }
    }
}

/// A stub `PooledModelLoader` that gives one container and counts the loads.
///
/// Each `evict(_:)` call sends one element to `evictions`, so that a test can
/// wait for the eviction job of the pool.
actor StubModelLoader: PooledModelLoader {
    /// The container that each load gives.
    let container: StubEmbeddingModel

    /// The number of `load(_:)` calls.
    private(set) var loadCount = 0

    /// One element for each `evict(_:)` call.
    let evictions: AsyncStream<Void>

    /// The continuation of `evictions`.
    private let evictionContinuation: AsyncStream<Void>.Continuation

    /// Makes a loader that gives `container`.
    ///
    /// - Parameter container: the container that each load gives.
    init(container: StubEmbeddingModel) {
        self.container = container
        (evictions, evictionContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    /// Counts the load and gives `container`, whatever the key is.
    ///
    /// - Returns: `container`.
    func load(_: ModelPoolKey) async throws -> any Sendable {
        loadCount += 1
        return container
    }

    /// Sends one element to `evictions`, whatever the container is.
    func evict(_: any Sendable) async {
        evictionContinuation.yield()
    }
}
