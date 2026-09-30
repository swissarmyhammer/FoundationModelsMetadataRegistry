import FoundationModelsExtras

/// A `TextEmbedding` over one pooled embedding model (plan.md §5, decision #16).
///
/// This adapter keeps one `PooledEmbedder` handle. The handle keeps a
/// `ModelHold`, so the model stays resident in its `ModelPool` while this
/// adapter exists. Each `embed(_:)` call goes to the handle, and the handle
/// sends the call through the one work queue of the model. All holds of one
/// key share that queue, so the calls of all users of the model run one at a
/// time. This adapter adds no queue of its own.
///
/// The first loader of a key wins: the pool gives the container that the
/// first loader made to each later caller, whatever loader that caller gives.
/// Thus this adapter uses the container through the `PooledEmbedding`
/// protocol only, and never casts it to the container type of one loader.
public struct PooledTextEmbedding: TextEmbedding {
    /// The session bytes of an embedding hold. An embedding model opens no
    /// session, so its hold adds no bytes to the footprint of the model.
    static let embeddingSessionBytes: Int64 = 0

    /// The pooled handle that keeps the hold and owns the route to the queue.
    private let embedder: PooledEmbedder

    /// Makes an adapter that keeps `embedder`.
    ///
    /// - Parameter embedder: The pooled embedder handle to forward to.
    public init(embedder: PooledEmbedder) {
        self.embedder = embedder
    }

    /// Acquires a hold of the embedding model of `model` from `pool`, and
    /// makes an adapter that keeps it.
    ///
    /// When the key is not resident, the pool loads it through `loader`.
    /// When the key is resident, the pool adds a hold and does not call
    /// `loader`: the first loader of a key wins.
    ///
    /// - Parameters:
    ///   - model: The embedding model to acquire.
    ///   - footprintBytes: The bytes of the weights of the model. The pool
    ///     counts them only when this call loads the model.
    ///   - loader: The loader that loads the model when it is not resident.
    ///   - pool: The pool to acquire the model from.
    /// - Returns: An adapter that keeps the new hold.
    /// - Throws: What `loader` throws, or
    ///   `PooledEmbedderError.notAnEmbedding(key:containerType:)` when the
    ///   container of the key does not conform to `PooledEmbedding`.
    public static func acquire(
        _ model: ModelRef,
        footprintBytes: Int64,
        loader: any PooledModelLoader,
        from pool: ModelPool,
    ) async throws -> PooledTextEmbedding {
        let hold = try await pool.acquire(
            ModelPoolKey(ref: model, role: .embedding),
            footprintBytes: footprintBytes,
            sessionBytes: embeddingSessionBytes,
            loader: loader,
        )
        return try PooledTextEmbedding(embedder: PooledEmbedder(hold: hold))
    }

    /// Embeds `texts` through the work queue of the pooled model.
    ///
    /// - Parameter texts: The texts to embed.
    /// - Returns: One vector for each text, in the order of `texts`.
    /// - Throws: What the queue or the model throws.
    public func embed(_ texts: [String]) async throws -> [[Float]] {
        try await embedder.embed(texts: texts)
    }
}
