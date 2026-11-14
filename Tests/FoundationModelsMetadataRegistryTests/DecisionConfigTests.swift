import FoundationModelsDecision
import FoundationModelsMetadataRegistry
import Testing

/// A `DecisionModel` that answers no question.
///
/// The tests of this file make a `DecisionConfig` and read its values. They
/// never start a decision session, so the executor of this model throws.
private struct UnansweringDecisionModel: DecisionModel {
  /// The error that the executor of this model throws for each batch.
  struct NoAnswer: Error {}

  /// The executor that throws `NoAnswer` for each batch.
  struct Executor: DecisionModelExecutor {
    /// Throws `NoAnswer`. No test of this file asks a question.
    ///
    /// - Parameters:
    ///   - questions: the questions, which this executor does not read.
    ///   - state: the state, which this executor does not read.
    /// - Returns: never.
    /// - Throws: `NoAnswer` always.
    func decide(_ questions: [Question], about state: DecisionState) async throws
      -> DecisionSession.Response
    {
      throw NoAnswer()
    }
  }

  /// The identifier of this test model.
  let modelID = "unanswering-decision-model"

  /// No limits: this model answers no question.
  let capabilities = DecisionCapabilities()

  /// Makes an executor that throws for each batch.
  ///
  /// - Returns: a new `Executor`.
  func makeExecutor() -> any DecisionModelExecutor {
    Executor()
  }
}

/// The values of a `DecisionConfig`: the defaults, the clamps that `init`
/// applies, and the default relevance question.
@Suite("DecisionConfig")
struct DecisionConfigTests {
  /// The candidate count of the default configuration.
  static let expectedDefaultCandidateCount = 20

  /// The minimum probability of the default configuration.
  static let expectedDefaultMinimumProbability = 0.5

  /// A probability below the range `0...1`.
  static let probabilityBelowRange = -1.0

  /// A probability above the range `0...1`.
  static let probabilityAboveRange = 2.0

  /// The lowest candidate count that `init` keeps.
  static let lowestCandidateCount = 1

  /// The id of the catalog entry in the question tests.
  static let entryID = "git-commit"

  /// The block of the catalog entry in the question tests.
  static let entryBlock = "Records the staged changes in a new commit."

  /// Makes a configuration over a model that answers no question.
  ///
  /// - Parameters:
  ///   - candidateCount: the candidate count to give to `init`.
  ///   - minimumProbability: the minimum probability to give to `init`.
  /// - Returns: the new configuration.
  static func makeConfig(
    candidateCount: Int = DecisionConfig.defaultCandidateCount,
    minimumProbability: Double = DecisionConfig.defaultMinimumProbability,
  ) -> DecisionConfig {
    DecisionConfig(
      model: UnansweringDecisionModel(),
      candidateCount: candidateCount,
      minimumProbability: minimumProbability,
    )
  }

  /// Gives the instructions of a binary question.
  ///
  /// - Parameter question: the question.
  /// - Returns: the instructions when `question` is `.binary`, else `nil`.
  static func binaryInstructions(of question: Question) -> String? {
    guard case .binary(let instructions, _) = question else { return nil }
    return instructions
  }

  @Test("The default candidate count is 20")
  func defaultCandidateCount() {
    #expect(
      DecisionConfig(model: UnansweringDecisionModel()).candidateCount
        == Self.expectedDefaultCandidateCount)
  }

  @Test("The default minimum probability is 0.5")
  func defaultMinimumProbability() {
    #expect(
      DecisionConfig(model: UnansweringDecisionModel()).minimumProbability
        == Self.expectedDefaultMinimumProbability)
  }

  @Test("init clamps a candidate count of 0 to 1")
  func clampsCandidateCountToOne() {
    #expect(Self.makeConfig(candidateCount: 0).candidateCount == Self.lowestCandidateCount)
  }

  @Test("init clamps a minimum probability below 0 to 0")
  func clampsMinimumProbabilityToZero() {
    #expect(Self.makeConfig(minimumProbability: Self.probabilityBelowRange).minimumProbability == 0)
  }

  @Test("init clamps a minimum probability above 1 to 1")
  func clampsMinimumProbabilityToOne() {
    #expect(Self.makeConfig(minimumProbability: Self.probabilityAboveRange).minimumProbability == 1)
  }

  @Test("The relevance question is a binary question")
  func relevanceQuestionIsBinary() {
    let question = DecisionConfig.relevanceQuestion(id: Self.entryID, block: Self.entryBlock)
    #expect(Self.binaryInstructions(of: question) != nil)
  }

  @Test("The instructions of the relevance question hold the id of the entry")
  func relevanceQuestionHoldsTheID() throws {
    let question = DecisionConfig.relevanceQuestion(id: Self.entryID, block: Self.entryBlock)
    let instructions = try #require(Self.binaryInstructions(of: question))
    #expect(instructions.contains(Self.entryID))
  }

  @Test("The instructions of the relevance question hold the block of the entry")
  func relevanceQuestionHoldsTheBlock() throws {
    let question = DecisionConfig.relevanceQuestion(id: Self.entryID, block: Self.entryBlock)
    let instructions = try #require(Self.binaryInstructions(of: question))
    #expect(instructions.contains(Self.entryBlock))
  }

  @Test("The default question is the relevance question")
  func defaultQuestionIsTheRelevanceQuestion() {
    let config = Self.makeConfig()
    #expect(
      config.question(Self.entryID, Self.entryBlock)
        == DecisionConfig.relevanceQuestion(id: Self.entryID, block: Self.entryBlock))
  }
}
