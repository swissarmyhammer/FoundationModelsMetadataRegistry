import FoundationModelsMetadataRegistry

/// One search configuration that the benchmark measures: a name, and a
/// function that makes a searcher over the catalog.
///
/// Each configuration searches with the same `limit` and the same intents,
/// so that the rows of a report compare only the configurations.
public struct BenchmarkConfiguration: Sendable {
  /// The name of each configuration that the `RankingBenchmark` executable
  /// can run, in the order of a run.
  public enum Name: String, CaseIterable, Sendable {
    /// Keyword retrieval with no embedder.
    case retrievalKeyword = "retrieval-keyword"
    /// Retrieval with the keyword signals and the cosine signal of an
    /// embedder.
    case retrievalSemantic = "retrieval-semantic"
    /// The selection tier with Qwen3 4B.
    case selectionQwen = "selection-qwen3-4b"
    /// The selection tier with the Apple system language model.
    case selectionApple = "selection-apple"
    /// The decision tier with Qwen3 4B and the generic prompt format.
    case decisionQwen = "decision-qwen3-4b"
    /// The decision tier with the decider 4B GGUF model and its own prompt
    /// format.
    case decisionDecider = "decision-decider-4b"
    /// The decision tier with the H2O-Lightning 4B GGUF model. The native
    /// decision code of llama.cpp makes the prompt and reads the answer.
    case decisionH2OLightning = "decision-h2o-lightning-4b"
  }

  /// The maximum count of matches of each search, for each configuration.
  /// It is also the recall cutoff of the report.
  public static let limit = 5

  /// The names of all the configurations, in the order of a run.
  public static let allNames = Name.allCases.map(\.rawValue)

  /// The name of the configuration.
  public let name: String

  /// Tells why the configuration cannot run on this computer, or gives
  /// `nil` when it can run. The runner asks before it makes a searcher.
  public let unavailableReason: @Sendable () -> String?

  /// Makes the searcher of this configuration over the catalog items.
  public let makeSearcher: @Sendable ([BenchmarkItem]) -> MetadataSearcher<BenchmarkItem>

  /// Makes a configuration.
  ///
  /// - Parameters:
  ///   - name: the name of the configuration.
  ///   - unavailableReason: tells why the configuration cannot run, or
  ///     gives `nil` when it can run. Defaults to a configuration that can
  ///     always run.
  ///   - makeSearcher: makes the searcher over the catalog items.
  public init(
    name: String,
    unavailableReason: @escaping @Sendable () -> String? = { nil },
    makeSearcher: @escaping @Sendable ([BenchmarkItem]) -> MetadataSearcher<BenchmarkItem>,
  ) {
    self.name = name
    self.unavailableReason = unavailableReason
    self.makeSearcher = makeSearcher
  }
}
