import BenchmarkSupport
import FoundationModelsDecision
import FoundationModelsMetadataRegistry

/// The errors that a ``LabelDecisionModel`` throws.
enum LabelDecisionModelError: Error, Equatable {
  /// The model was made to fail each batch.
  case scriptedFailure
}

/// A FoundationModelsDecision `DecisionModel` that loads nothing and gives
/// P(yes) from the labels of the benchmark intents.
///
/// The state of the session is the text of the intent. Each question is the
/// one that ``question(id:block:)`` makes, so its instructions are the id of
/// the candidate. The model gives P(yes) = 1 when the intent labels that id,
/// and P(yes) = 0 for all other ids.
struct LabelDecisionModel: DecisionModel {
  /// The identifier of this test model.
  let modelID = "label-decision-model"

  /// No limits: each question of the decision tier is binary.
  let capabilities = DecisionCapabilities()

  /// The relevant ids of each intent text.
  let relevantIDsByIntent: [String: Set<String>]

  /// Whether the executor throws `LabelDecisionModelError.scriptedFailure`
  /// for each batch.
  let fails: Bool

  /// Makes a label decision model.
  ///
  /// - Parameters:
  ///   - intents: the labeled intents whose labels give P(yes).
  ///   - fails: whether each batch throws
  ///     `LabelDecisionModelError.scriptedFailure`. Defaults to `false`.
  init(intents: [LabeledIntent], fails: Bool = false) {
    relevantIDsByIntent = Dictionary(
      intents.map { ($0.text, $0.relevantIDs) },
      uniquingKeysWith: { first, _ in first },
    )
    self.fails = fails
  }

  /// Makes the question for one candidate: a binary question whose
  /// instructions are the id of the candidate. Give it to a
  /// `DecisionConfig`, so that the model can read the id.
  ///
  /// - Parameters:
  ///   - id: the id of the candidate.
  ///   - block: the block of the candidate, which the question does not use.
  /// - Returns: a `.binary` question with `id` as its instructions.
  @Sendable static func question(id: String, block: String) -> Question {
    .binary(instructions: id)
  }

  /// Makes an executor that answers from the labels of this model.
  ///
  /// - Returns: a new `LabelDecisionExecutor`.
  func makeExecutor() -> any DecisionModelExecutor {
    LabelDecisionExecutor(model: self)
  }
}

/// The executor of a ``LabelDecisionModel``.
struct LabelDecisionExecutor: DecisionModelExecutor {
  /// The model that this executor answers for.
  let model: LabelDecisionModel

  /// Answers each question with P(yes) = 1 when the intent of `state`
  /// labels the id of the question, else with P(yes) = 0.
  ///
  /// - Parameters:
  ///   - questions: the questions of the batch, made with
  ///     `LabelDecisionModel.question(id:block:)`.
  ///   - state: the state of the session: the text of the intent.
  /// - Returns: one `.binary` answer for each question, in order.
  /// - Throws: `LabelDecisionModelError.scriptedFailure` when the model was
  ///   made to fail.
  func decide(_ questions: [Question], about state: DecisionState) async throws
    -> DecisionSession.Response
  {
    if model.fails {
      throw LabelDecisionModelError.scriptedFailure
    }
    let relevantIDs = Self.relevantIDs(for: state, in: model)
    return DecisionSession.Response(
      modelID: model.modelID,
      answers: questions.map { .binary(probability: Self.probability(of: $0, relevantIDs)) },
    )
  }

  /// The relevant ids of the intent that `state` holds.
  ///
  /// - Parameters:
  ///   - state: the state of the session.
  ///   - model: the model that holds the labels.
  /// - Returns: the labels of the intent, or an empty set for a state that
  ///   is not the text of a labeled intent.
  static func relevantIDs(for state: DecisionState, in model: LabelDecisionModel) -> Set<String> {
    guard case .text(let intent) = state else { return [] }
    return model.relevantIDsByIntent[intent] ?? []
  }

  /// P(yes) for one question.
  ///
  /// - Parameters:
  ///   - question: a question that `LabelDecisionModel.question(id:block:)`
  ///     made.
  ///   - relevantIDs: the labels of the intent.
  /// - Returns: 1 when the id of the question is in `relevantIDs`, else 0.
  static func probability(of question: Question, _ relevantIDs: Set<String>) -> Double {
    guard case .binary(let id, _) = question else { return 0 }
    return relevantIDs.contains(id) ? 1 : 0
  }
}
