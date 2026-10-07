import FoundationModels
import os

// MARK: - Selection-tier model fixtures
//
// The selection tests never use a real model. A selection tier gets a
// `ScriptedLanguageModel`: a FoundationModels `LanguageModel` that loads
// nothing and answers from a script. The tier makes real
// `LanguageModelSession`s on it. No GPU and no download.

/// One generation call that a ``ScriptedLanguageModel`` answered.
///
/// A test compares the calls with `==`, so the type holds only the two texts
/// that a selection test asserts.
struct ScriptedModelCall: Sendable, Equatable {
  /// The text of the instructions entry of the transcript of the call, or
  /// `nil` when the session has no instructions.
  let instructions: String?

  /// The text of the prompt entries of the transcript of the call, with a
  /// blank line between two entries. A new session has one prompt entry, so
  /// this is the text of that one prompt.
  let prompt: String
}

/// One answer in the script of a ``ScriptedLanguageModel``.
enum ScriptedAnswer: Sendable {
  /// Gives this text, for example a `Selection` as JSON.
  case text(String)

  /// Throws `ScriptedLanguageModelError.scriptedFailure`.
  case failure
}

/// The errors that a ``ScriptedLanguageModel`` throws.
enum ScriptedLanguageModelError: Error, Equatable, CustomStringConvertible {
  /// The script has a `.failure` answer for this call.
  case scriptedFailure

  /// The model received more calls than its script has answers. This is a
  /// test bug: the fixture has too few answers.
  case unscripted(answerCount: Int)

  /// A text that names the error.
  var description: String {
    switch self {
    case .scriptedFailure:
      return "ScriptedLanguageModel threw its scripted failure."
    case .unscripted(let answerCount):
      return "ScriptedLanguageModel received more calls than its \(answerCount) scripted answer(s)."
    }
  }
}

/// The script that each copy of one ``ScriptedLanguageModel`` plays, and the
/// log of the calls that it answered.
///
/// A class, because the identity of the script is the cache key of the
/// executor, and because all copies of one model share one log. The mutable
/// state is under one lock, so the class is `Sendable`.
final class ScriptedLanguageModelScript: Sendable {
  /// The answers, in call order.
  private let answers: [ScriptedAnswer]

  /// The calls that the model answered, in order, under one lock.
  private let recordedCalls = OSAllocatedUnfairLock<[ScriptedModelCall]>(initialState: [])

  /// Makes a script.
  ///
  /// - Parameter answers: The answers, in call order.
  init(answers: [ScriptedAnswer]) {
    self.answers = answers
  }

  /// The calls that the model answered, in order.
  var calls: [ScriptedModelCall] { recordedCalls.withLock { $0 } }

  /// Adds `call` to the log and gives the answer for it.
  ///
  /// - Parameter call: The call that the model answers.
  /// - Returns: The text of the answer for this call.
  /// - Throws: `ScriptedLanguageModelError.scriptedFailure` for a
  ///   `.failure` answer, or `.unscripted` when the script has no answer
  ///   left.
  fileprivate func answer(_ call: ScriptedModelCall) throws -> String {
    let index = recordedCalls.withLock { calls -> Int in
      calls.append(call)
      return calls.count - 1
    }
    guard index < answers.count else {
      throw ScriptedLanguageModelError.unscripted(answerCount: answers.count)
    }
    switch answers[index] {
    case .text(let text):
      return text
    case .failure:
      throw ScriptedLanguageModelError.scriptedFailure
    }
  }
}

/// A FoundationModels `LanguageModel` that loads nothing and answers each
/// generation call from a script, in order. It writes each call to the log
/// of the script first.
///
/// All copies of one model share one script, so a test keeps the model it
/// gave to the tier and reads ``calls`` from it.
struct ScriptedLanguageModel: LanguageModel {
  /// The executor that plays the script.
  typealias Executor = ScriptedLanguageModelExecutor

  /// The script that the model plays.
  let script: ScriptedLanguageModelScript

  /// Makes a model that plays `answers`, in call order.
  ///
  /// - Parameter answers: The answers, in call order.
  init(answers: [ScriptedAnswer]) {
    self.script = ScriptedLanguageModelScript(answers: answers)
  }

  /// Makes a model that gives `texts`, in call order: the usual script with
  /// no failure.
  ///
  /// - Parameter texts: The text of each answer, in call order.
  init(_ texts: [String]) {
    self.init(answers: texts.map(ScriptedAnswer.text))
  }

  /// Guided generation, so a session can ask for a `Generable` type.
  var capabilities: LanguageModelCapabilities {
    LanguageModelCapabilities([.guidedGeneration])
  }

  /// The cache key of the executor: the identity of the script.
  var executorConfiguration: ScriptedLanguageModelExecutor.Configuration {
    ScriptedLanguageModelExecutor.Configuration(script: ObjectIdentifier(script))
  }

  /// The calls that the model answered, in order.
  var calls: [ScriptedModelCall] { script.calls }
}

/// The executor of ``ScriptedLanguageModel``.
struct ScriptedLanguageModelExecutor: LanguageModelExecutor {
  /// The cache key that the SDK makes and uses again for the executor.
  struct Configuration: Sendable, Hashable {
    /// The identity of the script that the model plays.
    let script: ObjectIdentifier
  }

  /// The model that this executor runs for.
  typealias Model = ScriptedLanguageModel

  /// The token count of the one emitted fragment. The double counts no
  /// tokens.
  private static let emittedTokenCount = 1

  /// The text between the texts of two prompt entries in
  /// `ScriptedModelCall.prompt`.
  private static let promptSeparator = "\n\n"

  /// Makes an executor. The executor reads nothing from the configuration:
  /// the script comes with the model on each call.
  ///
  /// - Parameter configuration: The cache key.
  /// - Throws: Never. `throws` comes from the `LanguageModelExecutor`
  ///   requirement.
  init(configuration: Configuration) throws {}

  /// Writes the call to the log of the script, and emits the answer of the
  /// script.
  ///
  /// - Parameters:
  ///   - request: The generation request with the full transcript.
  ///   - model: The model with the script.
  ///   - channel: The channel that the answer goes into.
  /// - Throws: The error of the script for this call.
  func respond(
    to request: LanguageModelExecutorGenerationRequest,
    model: ScriptedLanguageModel,
    streamingInto channel: LanguageModelExecutorGenerationChannel
  ) async throws {
    let call = ScriptedModelCall(
      instructions: Self.instructionsText(in: request.transcript),
      prompt: Self.promptTexts(in: request.transcript).joined(separator: Self.promptSeparator)
    )
    let text = try model.script.answer(call)
    await channel.send(.response(action: .appendText(text, tokenCount: Self.emittedTokenCount)))
  }

  /// The text of the first instructions entry of `transcript`.
  ///
  /// - Parameter transcript: The transcript of a generation call.
  /// - Returns: The text of the entry, or `nil` when there is none.
  private static func instructionsText(in transcript: Transcript) -> String? {
    transcript.lazy.compactMap { entry -> String? in
      guard case .instructions(let instructions) = entry else { return nil }
      return text(of: instructions.segments)
    }.first
  }

  /// The text of each prompt entry of `transcript`, in order.
  ///
  /// - Parameter transcript: The transcript of a generation call.
  /// - Returns: The text of each prompt entry.
  private static func promptTexts(in transcript: Transcript) -> [String] {
    transcript.compactMap { entry in
      guard case .prompt(let prompt) = entry else { return nil }
      return text(of: prompt.segments)
    }
  }

  /// The text of the text segments of `segments`, joined.
  ///
  /// - Parameter segments: The segments of a transcript entry.
  /// - Returns: The joined text.
  private static func text(of segments: [Transcript.Segment]) -> String {
    segments.compactMap { segment in
      guard case .text(let text) = segment else { return nil }
      return text.content
    }.joined()
  }
}
