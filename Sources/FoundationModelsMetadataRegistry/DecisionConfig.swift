import FoundationModelsDecision

/// The configuration of the decision tier of a `MetadataSearcher`.
///
/// The decision tier ranks the relevance of catalog items with a
/// FoundationModelsDecision `DecisionModel`. The retrieval tier gives the
/// first `candidateCount` candidates. The model then gives the probability
/// of "yes" for one yes-or-no `question` about each candidate, in a decision
/// session whose state is the intent. A candidate with a probability below
/// `minimumProbability` is not a match.
///
/// The library takes `any DecisionModel`, as `SelectionConfig` takes
/// `any LanguageModel`. The caller supplies the model, for example a pooled
/// decision model from the `FoundationModelsDecisionPooled` product, which
/// the caller links in its own package.
public struct DecisionConfig: Sendable {
  /// The default number of retrieval candidates that the model scores for
  /// each search.
  public static let defaultCandidateCount = 20

  /// The default lowest probability of "yes" that a match must have.
  public static let defaultMinimumProbability = 0.5

  /// The lowest candidate count that `init` keeps.
  static let lowestCandidateCount = 1

  /// The range of a probability, which `init` clamps `minimumProbability`
  /// to.
  static let probabilityRange = 0.0...1.0

  /// The model that gives P(yes) for each candidate.
  public let model: any DecisionModel

  /// How many retrieval candidates the model scores for each search.
  public let candidateCount: Int

  /// A candidate with a lower P(yes) is not a match.
  public let minimumProbability: Double

  /// The yes-or-no question for one candidate block. The state of the
  /// decision session is the intent.
  public let question: @Sendable (_ id: String, _ block: String) -> Question

  /// Makes a decision tier configuration.
  ///
  /// - Parameters:
  ///   - model: the model that gives P(yes) for each candidate.
  ///   - candidateCount: how many retrieval candidates the model scores for
  ///     each search. A value below 1 becomes 1.
  ///   - minimumProbability: the lowest P(yes) that a match must have. A
  ///     value outside `0...1` becomes the nearest end of that range.
  ///   - question: makes the yes-or-no question for one candidate from its
  ///     id and its block. Defaults to `relevanceQuestion(id:block:)`.
  public init(
    model: any DecisionModel,
    candidateCount: Int = defaultCandidateCount,
    minimumProbability: Double = defaultMinimumProbability,
    question: @escaping @Sendable (String, String) -> Question = DecisionConfig.relevanceQuestion,
  ) {
    self.model = model
    self.candidateCount = max(candidateCount, Self.lowestCandidateCount)
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
