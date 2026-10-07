import FoundationModelsExtras
import Testing

@testable import FoundationModelsMetadataRegistry

/// Tests for a `MetadataSearcher` that embeds through a FoundationModelsExtras
/// `PooledEmbedder` (plan.md §5, decision #16).
///
/// FoundationModelsExtras makes `PooledEmbedder` a `PooledEmbedding`, so the
/// searcher takes it as its `embedder:` directly. `PooledEmbedder(ref:pool:)`
/// loads nothing, thus the synchronous initializer embeds nothing, and the
/// first search embeds the catalog (see `FirstSearchCatchUp`).
///
/// Each test makes its own `ModelPool(loader:)` over a `CountingEmbeddingLoader`,
/// never `ModelPool.shared`, so the tests share no state and no test loads a
/// real model.
@Suite("PooledEmbedder search")
struct PooledEmbedderSearchTests {
  // MARK: - Fixtures

  /// A catalog item with a fixed id and block.
  struct FixtureItem: SearchableMetadata {
    /// The id of the item.
    let id: String

    /// The one-line description of the item.
    let block: String

    /// Renders the block, verbatim.
    ///
    /// - Returns: the block.
    func renderBlock() -> String {
      block
    }
  }

  /// The embedding model of each searcher.
  static let embeddingModel: ModelRef = "test-org/test-embedder"

  /// The catalog of each searcher.
  static let items = [
    FixtureItem(id: "a", block: "alpha block"), FixtureItem(id: "b", block: "bravo block"),
  ]

  /// The query of each search. No catalog block shares a token with it, so
  /// only the cosine signal can rank the item with the matching vector.
  static let query = "first letter"

  /// The `limit` of each search: more than the catalog holds.
  static let searchLimit = 5

  /// The number of searchers that embed through one model in one pool.
  static let sharingSearcherCount = 2

  /// The vector of each fixture block, and of `query`, which points at the
  /// vector of the item with id "a".
  static let vectorsByText: [String: [Float]] = [
    "alpha block": [1, 0],
    "bravo block": [0, 1],
    query: [1, 0],
  ]

  /// Makes a pool whose loader gives a `TableEmbeddingModel` over
  /// `vectorsByText`.
  ///
  /// - Returns: the loader, to count its loads, and the pool over it.
  static func makePool() -> (loader: CountingEmbeddingLoader, pool: ModelPool) {
    let loader = CountingEmbeddingLoader(
      container: TableEmbeddingModel(table: VectorTable(vectorsByText: vectorsByText)))
    return (loader, ModelPool(loader: loader))
  }

  // MARK: - Embed at the first search

  /// An async test calls the initializer with no `await`. This compiles only
  /// when the one `embedder:` initializer is synchronous.
  @Test
  func synchronousInitLoadsNothingAndTheFirstSearchRanksByCosine() async throws {
    let (loader, pool) = Self.makePool()

    let searcher = MetadataSearcher(
      items: Self.items, embedder: PooledEmbedder(ref: Self.embeddingModel, pool: pool))
    #expect(await loader.loadCount == 0)

    let matches = try await searcher.search(intent: Self.query, limit: Self.searchLimit)

    #expect(await loader.loadCount == 1)
    let first = try #require(matches.first)
    #expect(first.id == "a")
    #expect(first.signals?.cosine != 0.0)
    #expect(await searcher.index.embedding(forID: "a") == [1, 0])
    #expect(await searcher.index.embedding(forID: "b") == [0, 1])
  }

  // MARK: - One load for each model

  @Test
  func twoSearchersWithOneModelNameShareOneLoad() async throws {
    let (loader, pool) = Self.makePool()
    let searchers = (0..<Self.sharingSearcherCount).map { _ in
      MetadataSearcher(
        items: Self.items, embedder: PooledEmbedder(ref: Self.embeddingModel, pool: pool))
    }

    for searcher in searchers {
      _ = try await searcher.search(intent: Self.query, limit: Self.searchLimit)
    }

    #expect(await loader.loadCount == 1)
    #expect(pool.residentModelCount == 1)
  }
}

/// A `PooledEmbedding` container over a `VectorTable`. It loads no real model.
struct TableEmbeddingModel: PooledEmbedding {
  /// The vectors of the texts.
  let table: VectorTable

  /// Gives the vector of each text from `table`.
  ///
  /// - Parameter texts: the texts to embed.
  /// - Returns: one vector for each text, in the order of `texts`.
  func embed(texts: [String]) async throws -> [[Float]] {
    table.vectors(for: texts)
  }
}

/// A `PooledModelLoader` that gives one container and counts its loads.
actor CountingEmbeddingLoader: PooledModelLoader {
  /// The container that each load gives.
  let container: TableEmbeddingModel

  /// The number of `load(_:)` calls.
  private(set) var loadCount = 0

  /// Makes a loader that gives `container`.
  ///
  /// - Parameter container: the container that each load gives.
  init(container: TableEmbeddingModel) {
    self.container = container
  }

  /// Counts the load and gives `container`, whatever the key is.
  ///
  /// - Returns: `container`.
  func load(_: ModelPoolKey) async throws -> any Sendable {
    loadCount += 1
    return container
  }

  /// Does nothing: `container` holds no memory to give back.
  func evict(_: any Sendable) async {}
}
