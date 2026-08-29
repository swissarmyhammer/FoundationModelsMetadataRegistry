import FoundationModelsMetadataRegistry

// MARK: - GPU-free deterministic embedder

/// A GPU-free, deterministic `TextEmbedding` test double for this demo --
/// `FakeEmbedder`-style (the test suite's own hand-scripted, exact-text
/// lookup double), but hashing every input into a reproducible vector
/// instead of requiring the caller to script one vector per text: `embed(_:)`
/// is a pure function of its input, so the same text always embeds to the
/// same vector, and different texts (almost always) embed to different
/// ones -- enough to exercise real cosine scoring, incremental re-embedding,
/// and embed catch-up deterministically, with no GPU, network, or model.
public struct DeterministicEmbedder: TextEmbedding {
    /// The length of every embedding vector this embedder produces.
    public let dimension: Int

    /// Creates a deterministic embedder.
    ///
    /// - Parameter dimension: the length of every embedding vector this
    ///   embedder produces. Defaults to `8`.
    public init(dimension: Int = 8) {
        self.dimension = dimension
    }

    /// Embeds the given texts into deterministic vectors using a pure hash
    /// function: the same text always embeds to the same vector, and
    /// different texts (almost always) embed to different ones.
    ///
    /// - Parameter texts: the texts to embed.
    /// - Returns: one unit-normalized, `dimension`-length vector per text, in
    ///   the same order as `texts`.
    public func embed(_ texts: [String]) async throws -> [[Float]] {
        texts.map { Self.vector(for: $0, dimension: dimension) }
    }

    /// Hashes `text`'s UTF-8 bytes into a deterministic, unit-normalized
    /// `dimension`-length vector: each byte accumulates into the bucket
    /// `index % dimension`, then the whole vector is normalized so cosine
    /// similarity behaves sensibly.
    ///
    /// - Parameters:
    ///   - text: the text to hash.
    ///   - dimension: the vector length to produce.
    /// - Returns: a deterministic, unit-normalized vector for `text`.
    private static func vector(for text: String, dimension: Int) -> [Float] {
        var buckets = [Float](repeating: 0, count: dimension)
        for (index, byte) in text.utf8.enumerated() {
            buckets[index % dimension] += Float(byte)
        }
        let magnitude = buckets.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        guard magnitude > 0 else { return buckets }
        return buckets.map { $0 / magnitude }
    }
}
