import FoundationModelsDecision

/// The configuration of the decision tier of a `MetadataSearcher`.
///
/// The decision tier ranks the relevance of catalog items with a
/// FoundationModelsDecision `DecisionModel`. The model gives the probability
/// of "yes" for one yes-or-no `question` about each item of the whole
/// catalog, in one decision session whose state is the intent. The session
/// gets the questions in batches of at most `batchSize`. An item with a
/// probability below `minimumProbability` is not a match.
///
/// The library takes `any DecisionModel`, as `SelectionConfig` takes
/// `any LanguageModel`. The caller supplies the model, for example a pooled
/// decision model from the `FoundationModelsDecisionPooled` product, which
/// the caller links in its own package.
public struct DecisionConfig: Sendable {
  /// The default largest count of questions in one call to the decision
  /// session.
  public static let defaultBatchSize = 64

  /// The default lowest probability of "yes" that a match must have.
  public static let defaultMinimumProbability = 0.5

  /// The lowest batch size that `init` keeps.
  static let lowestBatchSize = 1

  /// The range of a probability, which `init` clamps `minimumProbability`
  /// to.
  static let probabilityRange = 0.0...1.0

  /// The model that gives P(yes) for each catalog item.
  public let model: any DecisionModel

  /// The largest count of questions in one call to the decision session.
  /// A search asks one question for each catalog item, so a catalog larger
  /// than this value goes to the session in more than one call.
  public let batchSize: Int

  /// An item with a lower P(yes) is not a match.
  public let minimumProbability: Double

  /// The yes-or-no question for the block of one catalog item. The state
  /// of the decision session is the intent.
  public let question: @Sendable (_ id: String, _ block: String) -> Question

  /// Makes a decision tier configuration.
  ///
  /// - Parameters:
  ///   - model: the model that gives P(yes) for each catalog item.
  ///   - batchSize: the largest count of questions in one call to the
  ///     decision session. A value below 1 becomes 1.
  ///   - minimumProbability: the lowest P(yes) that a match must have. A
  ///     value outside `0...1` becomes the nearest end of that range.
  ///   - question: makes the yes-or-no question for one catalog item from
  ///     its id and its block. Defaults to `relevanceQuestion(id:block:)`.
  public init(
    model: any DecisionModel,
    batchSize: Int = defaultBatchSize,
    minimumProbability: Double = defaultMinimumProbability,
    question: @escaping @Sendable (String, String) -> Question = DecisionConfig.relevanceQuestion,
  ) {
    self.model = model
    self.batchSize = max(batchSize, Self.lowestBatchSize)
    self.minimumProbability = min(
      max(minimumProbability, Self.probabilityRange.lowerBound),
      Self.probabilityRange.upperBound,
    )
    self.question = question
  }

  /// Makes the default question: does this catalog entry do what the
  /// request asks?
  ///
  /// The instructions hold the id and the block of the entry. The criteria
  /// say that "yes" means the entry does the requested task, and that "no"
  /// means the entry is unrelated, or only shares words with the request.
  ///
  /// - Parameters:
  ///   - id: the id of the catalog entry.
  ///   - block: the rendered block of the catalog entry.
  /// - Returns: a `.binary` question about the entry.
  public static func relevanceQuestion(id: String, block: String) -> Question {
    .binary(
      instructions: "Does this catalog entry do what the request asks? Entry `\(id)`: \(block)",
      criteria: BinaryCriteria(
        whenTrue: "The entry does the requested task.",
        whenFalse: "The entry is unrelated to the request, or only shares words with the request.",
      ),
    )
  }
}

/// The error that `MetadataSearcher.search(intent:limit:)` throws when the
/// mode is `.decision` and the searcher has no decision tier.
///
/// Give a `DecisionConfig` to `MetadataSearcher.init(..., decision:)` to
/// configure the decision tier. A `.decision` search with no decision tier
/// fails, and does not use a different tier in its place.
public struct DecisionTierUnavailable: Error, Sendable, Equatable {
  /// Makes the error.
  public init() {}
}
