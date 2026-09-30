/// An exact-text to vector lookup table, shared by the embedding test doubles
/// `FakeEmbedder` and `GatedEmbedder`.
///
/// `TextEmbedding` has no `dimension`: the length of a vector is the length
/// of the vector that the embedder returns. A text absent from this table
/// embeds to an all-zero vector, which contributes nothing to cosine (see the
/// zero-norm guard of the cosine signal). That vector has the length of the
/// registered vectors, because the ranker reports `.embeddingUnavailable`
/// when the vectors of one search do not have the same length.
struct VectorTable {
    /// The length of the all-zero vector of a table that registers no vector.
    ///
    /// Two components are the smallest length in which two vectors can be
    /// orthogonal.
    static let defaultVectorLength = 2

    /// Exact-text to vector lookup table. Each vector has the same length.
    let vectorsByText: [String: [Float]]

    /// The vector of a text absent from `vectorsByText`: all zeros, with the
    /// length of the registered vectors, or `defaultVectorLength` when no
    /// vector is registered.
    var unregisteredVector: [Float] {
        [Float](repeating: 0, count: vectorsByText.values.first?.count ?? Self.defaultVectorLength)
    }

    /// Gives one vector for each text: the registered vector, or
    /// `unregisteredVector` for a text absent from `vectorsByText`.
    ///
    /// - Parameter texts: the texts to embed.
    /// - Returns: one vector for each text, in the order of `texts`.
    func vectors(for texts: [String]) -> [[Float]] {
        let fallback = unregisteredVector
        return texts.map { vectorsByText[$0] ?? fallback }
    }
}
