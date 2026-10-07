import Testing

@testable import FoundationModelsMetadataRegistry

/// Tests for the vectors that the embedding test doubles give.
///
/// `PooledEmbedding` has no `dimension`, so a double does not declare one. A
/// text that a double does not know embeds to an all-zero vector. That vector
/// must have the length of the registered vectors: the ranker reports
/// `.embeddingUnavailable` when the vectors of one search do not have the
/// same length, and each test that uses a double depends on the same length.
struct EmbeddingTestDoubleTests {
  /// A text that no table of this suite registers.
  static let unregisteredText = "an unregistered text"

  @Test
  func anUnregisteredTextEmbedsToAZeroVectorOfTheRegisteredLength() async throws {
    let embedder = FakeEmbedder(vectorsByText: ["registered": [1, 0, 0]])

    let vectors = try await embedder.embed(texts: ["registered", Self.unregisteredText])

    #expect(vectors == [[1, 0, 0], [0, 0, 0]])
  }

  @Test
  func anUnregisteredTextEmbedsToAZeroVectorOfTheDefaultLengthWhenNoVectorIsRegistered()
    async throws
  {
    let embedder = FakeEmbedder()

    let vectors = try await embedder.embed(texts: [Self.unregisteredText])

    #expect(vectors == [[Float](repeating: 0, count: VectorTable.defaultVectorLength)])
  }

  @Test
  func aGatedEmbedderGivesAZeroVectorOfTheRegisteredLength() async throws {
    let gate = EmbedGate()
    await gate.release()
    let embedder = GatedEmbedder(vectorsByText: ["registered": [0, 1, 0]], gate: gate)

    let vectors = try await embedder.embed(texts: [Self.unregisteredText])

    #expect(vectors == [[0, 0, 0]])
  }
}
