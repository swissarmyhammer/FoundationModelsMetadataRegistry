import FoundationModelsExtras
import FoundationModelsMetadataRegistry
import Testing

/// The most minutes that `PooledEmbedderRealModelTests` can take. A first run
/// downloads the model. It is a file constant, not a member of the suite: the
/// `@Suite` trait of a type cannot read a member of that type.
private let pooledEmbedderTimeLimitMinutes = 10

/// The scenario in this package that embeds with a real MLX embedding model
/// through a FoundationModelsExtras `PooledEmbedder` (plan.md §5, decision
/// #16).
///
/// **What this measures.** A `MetadataSearcher` that a synchronous
/// initializer builds over `PooledEmbedder(ref:)` embeds nothing at `init`.
/// Its first search loads the model from `ModelPool.shared`, embeds the
/// catalog, and ranks it. The query is a paraphrase of one catalog entry, and
/// it shares no word with that entry, so only the cosine signal can find it.
/// The searcher gives weight to the cosine signal only, thus the first match
/// is the entry whose vector is nearest to the vector of the query.
///
/// The first run downloads the model from Hugging Face.
@Suite(
  "PooledEmbedder against a real embedding model",
  .timeLimit(.minutes(pooledEmbedderTimeLimitMinutes)))
struct PooledEmbedderRealModelTests {
  /// The embedding model that the searcher loads.
  static let embeddingModel: ModelRef = "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ"

  /// One catalog entry: a tool name and the one-line description that the
  /// model embeds.
  struct Tool: SearchableMetadata {
    /// The id of the tool.
    let id: String

    /// The description of the tool.
    let block: String

    /// Renders the description, verbatim.
    ///
    /// - Returns: the description.
    func renderBlock() -> String {
      block
    }
  }

  /// The id of the tool that `query` paraphrases.
  static let paraphrasedID = "weather"

  /// Four tools with unrelated meanings.
  static let catalog = [
    Tool(id: paraphrasedID, block: "Reports the forecast of rain and temperature for a city."),
    Tool(id: "files", block: "Lists the files and folders in a directory."),
    Tool(id: "email", block: "Sends an electronic mail message to a contact."),
    Tool(id: "music", block: "Plays a song from the audio library."),
  ]

  /// A paraphrase of the description of the weather tool that shares no
  /// word with it.
  static let query = "Will it be sunny tomorrow in Paris?"

  /// Weights that let the cosine signal alone rank the catalog.
  static let cosineOnly = Weights(bm25: 0, trigram: 0, cosine: 1)

  @Test("the cosine signal ranks the paraphrased tool first")
  func cosineRanksTheParaphraseFirst() async throws {
    let searcher = MetadataSearcher(
      items: Self.catalog,
      mode: .retrieval,
      weights: Self.cosineOnly,
      embedder: PooledEmbedder(ref: Self.embeddingModel),
    )

    let matches = try await searcher.search(intent: Self.query, limit: Self.catalog.count)

    let first = try #require(matches.first)
    #expect(
      first.id == Self.paraphrasedID,
      "the ranking was \(matches.map { "\($0.id)=\($0.signals?.cosine ?? 0)" })",
    )
    let cosine = try #require(first.signals?.cosine)
    #expect(cosine > 0)
  }
}
