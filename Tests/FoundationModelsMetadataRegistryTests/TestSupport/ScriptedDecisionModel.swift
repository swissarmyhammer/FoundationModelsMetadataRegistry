import FoundationModelsDecision
import os

// MARK: - Decision-tier model fixtures
//
// The decision tests never use a real model. A decision tier gets a
// `ScriptedDecisionModel`: a FoundationModelsDecision `DecisionModel` that
// loads nothing and gives P(yes) for each question from a closure. The tier
// makes a real `DecisionSession` on it. No GPU and no download.

/// One batch of questions that a ``ScriptedDecisionModel`` received.
struct ScriptedDecisionBatch: Sendable, Equatable {
  /// The questions of the batch, in order.
  let questions: [Question]

  /// The state of the session that asked the batch.
  let state: DecisionState
}

/// The errors that a ``ScriptedDecisionModel`` throws.
enum ScriptedDecisionModelError: Error, Equatable {
  /// The model was made to fail each batch.
  case scriptedFailure
}

/// The log of the batches that each copy of one ``ScriptedDecisionModel``
/// received.
///
/// A class, because all copies of one model and all of its executors share
/// one log. The mutable state is under one lock, so the class is `Sendable`.
final class ScriptedDecisionLog: Sendable {
  /// The batches that the model received, in order, under one lock.
  private let recordedBatches = OSAllocatedUnfairLock<[ScriptedDecisionBatch]>(initialState: [])

  /// The batches that the model received, in order.
  var batches: [ScriptedDecisionBatch] { recordedBatches.withLock { $0 } }

  /// Adds `batch` to the log.
  ///
  /// - Parameter batch: the batch that the model received.
  func record(_ batch: ScriptedDecisionBatch) {
    recordedBatches.withLock { $0.append(batch) }
  }
}

/// A FoundationModelsDecision `DecisionModel` that loads nothing and gives
/// P(yes) for each binary question from a closure.
///
/// The executor writes each batch to the shared log first. It then waits
/// on the gate, when the model has one, and then throws when the model was
/// made to fail. Else it gives one `.binary` answer for each question, with
/// the probability that `probability` gives for that question.
///
/// All copies of one model share one log, so a test keeps the model that it
/// gave to the `DecisionConfig` and reads ``batches`` from it.
struct ScriptedDecisionModel: DecisionModel {
  /// The identifier of this test model.
  let modelID = "scripted-decision-model"

  /// No limits: each question of the decision tier is binary.
  let capabilities = DecisionCapabilities()

  /// Gives P(yes) for one question.
  let probability: @Sendable (Question) -> Double

  /// Whether the executor throws `ScriptedDecisionModelError.scriptedFailure`
  /// for each batch.
  let fails: Bool

  /// The gate that the executor signals and then waits on before it answers,
  /// or `nil` to answer at once. A test uses the gate to hold a search in
  /// the model call.
  let gate: EmbedGate?

  /// The log of the batches that this model received.
  let log = ScriptedDecisionLog()

  /// Makes a scripted decision model.
  ///
  /// - Parameters:
  ///   - fails: whether each batch throws
  ///     `ScriptedDecisionModelError.scriptedFailure`. Defaults to `false`.
  ///   - gate: the gate to wait on before each answer, or `nil` (the
  ///     default) to answer at once.
  ///   - probability: gives P(yes) for one question.
  init(
    fails: Bool = false,
    gate: EmbedGate? = nil,
    probability: @escaping @Sendable (Question) -> Double,
  ) {
    self.fails = fails
    self.gate = gate
    self.probability = probability
  }

  /// The batches that this model received, in order.
  var batches: [ScriptedDecisionBatch] { log.batches }

  /// Makes an executor that answers from this model.
  ///
  /// - Returns: a new `ScriptedDecisionExecutor`.
  func makeExecutor() -> any DecisionModelExecutor {
    ScriptedDecisionExecutor(model: self)
  }
}

/// The executor of a ``ScriptedDecisionModel``.
struct ScriptedDecisionExecutor: DecisionModelExecutor {
  /// The model that this executor answers for.
  let model: ScriptedDecisionModel

  /// Records the batch, waits on the gate of the model, and answers each
  /// question with the probability that the model gives for it.
  ///
  /// - Parameters:
  ///   - questions: the questions of the batch.
  ///   - state: the state of the session.
  /// - Returns: one `.binary` answer for each question, in order.
  /// - Throws: `ScriptedDecisionModelError.scriptedFailure` when the model
  ///   was made to fail.
  func decide(_ questions: [Question], about state: DecisionState) async throws
    -> DecisionSession.Response
  {
    model.log.record(ScriptedDecisionBatch(questions: questions, state: state))
    if let gate = model.gate {
      await gate.signalStarted()
      await gate.waitForRelease()
    }
    if model.fails {
      throw ScriptedDecisionModelError.scriptedFailure
    }
    return DecisionSession.Response(
      modelID: model.modelID,
      answers: questions.map { .binary(probability: model.probability($0)) },
    )
  }
}
