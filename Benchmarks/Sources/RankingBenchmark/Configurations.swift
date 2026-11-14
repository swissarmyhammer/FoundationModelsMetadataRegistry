import BenchmarkSupport
import FoundationModels
import FoundationModelsDecision
import FoundationModelsDecisionPooled
import FoundationModelsExtras
import FoundationModelsExtrasLlamaCpp
import FoundationModelsMetadataRegistry

/// The real configurations of the benchmark. They load models from Hugging
/// Face at their first search.
///
/// Each configuration except `retrieval-keyword` uses the same embedder, so
/// the candidates of the decision tier are the same as the results of the
/// semantic retrieval. Each embedder and each MLX model is in the shared
/// `ModelPool`, so each model loads one time in the run.
enum Configurations {
  /// The embedder model of each configuration that embeds.
  static let embedderRef: ModelRef = "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ"

  /// The Qwen3 4B model of the selection tier and the decision tier. Both
  /// tiers use the same weights, so the two rows compare only the method.
  static let qwenRef: ModelRef = "mlx-community/Qwen3-4B-4bit"

  /// The decider 4B model. The ref names the GGUF file in the repository.
  static let deciderRef: ModelRef = "Mapika/decider-4b-GGUF/decider-4b-v3-Q4_K_M.gguf"

  /// The H2O-Lightning 4B model. Its GGUF file has the decision type
  /// `h2o-lightning`. The revision is the revision that the model matrix of
  /// FoundationModelsDecision tests.
  static let h2oLightningRef = ModelRef(
    repo: "h2oai/h2o-lightning-4b-gguf", path: "h2o-lightning-4b-Q4_K_M.gguf",
    revision: "61f8d8b7a8c2d84426d0d143ca187f65d235934b")

  /// The pool that loads GGUF files with llama.cpp, for the decider model
  /// and the H2O-Lightning model.
  static let ggufPool = ModelPool(loader: HubModelLoader(gguf: LlamaCppModelLoader()))

  /// Makes the configuration of `name`.
  ///
  /// - Parameter name: the name of the configuration.
  /// - Returns: the configuration.
  static func make(_ name: BenchmarkConfiguration.Name) -> BenchmarkConfiguration {
    switch name {
    case .retrievalKeyword:
      BenchmarkConfiguration(name: name.rawValue) { items in
        MetadataSearcher(items: items, mode: .retrieval)
      }
    case .retrievalSemantic:
      BenchmarkConfiguration(name: name.rawValue) { items in
        MetadataSearcher(items: items, mode: .retrieval, embedder: makeEmbedder())
      }
    case .selectionQwen:
      selection(name, model: { PooledModel(ref: qwenRef) })
    case .selectionApple:
      selection(
        name, model: { SystemLanguageModel.default },
        unavailableReason: systemModelUnavailableReason)
    case .decisionQwen:
      decision(name, model: { PooledDecisionModel(ref: qwenRef) })
    case .decisionDecider:
      decision(
        name,
        model: {
          PooledDecisionModel(ref: deciderRef, pool: ggufPool, format: DeciderPromptFormat())
        })
    case .decisionH2OLightning:
      decision(name, model: { PooledNativeDecisionModel(ref: h2oLightningRef, pool: ggufPool) })
    }
  }

  /// Makes the shared embedder of the configurations that embed.
  ///
  /// - Returns: a pooled embedder of `embedderRef`, which loads nothing
  ///   until its first embed.
  static func makeEmbedder() -> PooledEmbedder {
    PooledEmbedder(ref: embedderRef)
  }

  /// Makes a `.selection` configuration with the librarian preamble.
  ///
  /// - Parameters:
  ///   - name: the name of the configuration.
  ///   - model: makes the language model of the selection tier.
  ///   - unavailableReason: tells why the model cannot run, or gives `nil`.
  /// - Returns: the configuration.
  static func selection(
    _ name: BenchmarkConfiguration.Name,
    model: @escaping @Sendable () -> any LanguageModel,
    unavailableReason: @escaping @Sendable () -> String? = { nil },
  ) -> BenchmarkConfiguration {
    BenchmarkConfiguration(name: name.rawValue, unavailableReason: unavailableReason) { items in
      MetadataSearcher(
        items: items,
        mode: .selection,
        embedder: makeEmbedder(),
        selection: SelectionConfig(model: model(), preamble: .librarianDefault),
      )
    }
  }

  /// Makes a `.decision` configuration with the default batch size, minimum
  /// probability and question.
  ///
  /// - Parameters:
  ///   - name: the name of the configuration.
  ///   - model: makes the decision model.
  /// - Returns: the configuration.
  static func decision(
    _ name: BenchmarkConfiguration.Name,
    model: @escaping @Sendable () -> any DecisionModel,
  ) -> BenchmarkConfiguration {
    BenchmarkConfiguration(name: name.rawValue) { items in
      MetadataSearcher(
        items: items,
        mode: .decision,
        embedder: makeEmbedder(),
        decision: DecisionConfig(model: model()),
      )
    }
  }

  /// Tells why the Apple system language model cannot run on this
  /// computer.
  ///
  /// - Returns: the reason, or `nil` when the model is available.
  @Sendable static func systemModelUnavailableReason() -> String? {
    switch SystemLanguageModel.default.availability {
    case .available:
      nil
    case .unavailable(let reason):
      "the Apple system language model is not available: \(reason)"
    }
  }
}
