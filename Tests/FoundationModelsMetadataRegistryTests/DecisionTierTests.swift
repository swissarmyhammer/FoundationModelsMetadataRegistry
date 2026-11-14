import FoundationModelsDecision
import Testing

@testable import FoundationModelsMetadataRegistry

/// Tests for the `.decision` search tier: a `DecisionModel` gives the P(yes)
/// of each catalog item, and the retrieval tier gives the signals and the
/// order of equal scores.
///
/// Each test uses a `ScriptedDecisionModel` (`TestSupport`), so no test
/// loads a real model and no test uses a GPU. Each configuration asks a
/// question whose instructions are the id of the candidate, so the script
/// of a test can give a P(yes) for each id.
struct DecisionTierTests {
  // MARK: - Fixtures

  /// A catalog item that also records the catalog it came from.
  struct FixtureItem: SearchableMetadata {
    /// The id of the item.
    let id: String

    /// The block of the item.
    let block: String

    /// The name of the catalog that holds this item.
    let catalogName: String

    /// Makes an item.
    ///
    /// - Parameters:
    ///   - id: the id of the item.
    ///   - block: the block of the item.
    ///   - catalogName: the name of the catalog that holds this item.
    ///     Defaults to `firstCatalogName`.
    init(id: String, block: String, catalogName: String = DecisionTierTests.firstCatalogName) {
      self.id = id
      self.block = block
      self.catalogName = catalogName
    }

    /// Gives the block, verbatim.
    ///
    /// - Returns: `block`.
    func renderBlock() -> String {
      block
    }
  }

  /// The name of the catalog of most tests.
  static let firstCatalogName = "first"

  /// The name of the catalog that a concurrent update loads.
  static let secondCatalogName = "second"

  /// The intent of most tests. Four blocks of `catalog` hold this word.
  static let intent = "release"

  /// The limit of most tests: larger than the catalog.
  static let limit = 10

  /// A P(yes) above the default minimum probability.
  static let highProbability = 0.9

  /// A P(yes) below the default minimum probability.
  static let lowProbability = 0.1

  /// The step between the P(yes) of two candidates in a scripted order.
  static let probabilityStep = 0.1

  /// A limit lower than the count of items that the model says "yes" to.
  static let smallLimit = 2

  /// The count of items in `largeCatalog`.
  static let largeCatalogCount = 150

  /// The batch size of the batch tests.
  static let largeBatchSize = 64

  /// The question counts of the batches for `largeCatalog` and
  /// `largeBatchSize`: two full batches, then the remainder.
  static let largeCatalogBatchSizes = [64, 64, 22]

  /// The catalog of most tests.
  static let catalog: [FixtureItem] = [
    FixtureItem(id: "rollback", block: "reverts the last release"),
    FixtureItem(id: "status", block: "reports current release health"),
    FixtureItem(id: "notes", block: "writes the notes of a release"),
    FixtureItem(id: "tag", block: "marks a release in version control"),
    FixtureItem(id: "deploy", block: "ships containers to a cluster"),
  ]

  /// The id of an item at the start of `widerCatalog` that the retrieval
  /// tier does not find for `intent`.
  static let firstHiddenID = "plugh"

  /// The id of an item at the end of `widerCatalog` that the retrieval tier
  /// does not find for `intent`.
  static let lastHiddenID = "xyzzy"

  /// `catalog` with one item before it and one item after it whose blocks
  /// share no word and no trigram with `intent`.
  static let widerCatalog: [FixtureItem] =
    [FixtureItem(id: firstHiddenID, block: firstHiddenID)] + catalog
    + [FixtureItem(id: lastHiddenID, block: lastHiddenID)]

  /// A catalog of `largeCatalogCount` items.
  static let largeCatalog: [FixtureItem] = (0..<largeCatalogCount).map {
    FixtureItem(id: "item-\($0)", block: "item number \($0)")
  }

  /// The `Signals` of an item that the retrieval tier does not rank: each
  /// signal is `0.0`.
  static let noSignals = Signals(bm25: 0, trigram: 0, cosine: 0)

  /// The catalog of `catalog`, with the same ids, that a concurrent update
  /// loads.
  static let secondCatalog: [FixtureItem] = catalog.map {
    FixtureItem(id: $0.id, block: "\($0.block) again", catalogName: secondCatalogName)
  }

  /// Makes a question whose instructions are the id of the candidate.
  ///
  /// - Parameters:
  ///   - id: the id of the candidate.
  ///   - block: the block of the candidate, which this question ignores.
  /// - Returns: a `.binary` question with `id` as its instructions.
  static func idQuestion(id: String, block: String) -> Question {
    .binary(instructions: id)
  }

  /// Gives the id of the candidate that `idQuestion(id:block:)` asked about.
  ///
  /// - Parameter question: a question that `idQuestion(id:block:)` made.
  /// - Returns: the instructions of the question.
  static func candidateID(of question: Question) -> String {
    guard case .binary(let instructions, _) = question else { return "" }
    return instructions
  }

  /// Makes a model that gives the P(yes) of `probabilities` for each
  /// candidate id, and `0` for an id that `probabilities` does not hold.
  ///
  /// - Parameters:
  ///   - probabilities: the P(yes) of each candidate id.
  ///   - fails: whether the model throws for each batch.
  ///   - gate: the gate that the model waits on, or `nil`.
  /// - Returns: the new model.
  static func makeModel(
    _ probabilities: [String: Double] = [:],
    fails: Bool = false,
    gate: EmbedGate? = nil,
  ) -> ScriptedDecisionModel {
    ScriptedDecisionModel(fails: fails, gate: gate) { question in
      probabilities[candidateID(of: question)] ?? 0
    }
  }

  /// Makes a decision configuration that asks `idQuestion(id:block:)`.
  ///
  /// - Parameters:
  ///   - model: the model of the configuration.
  ///   - batchSize: the batch size of the configuration.
  /// - Returns: the new configuration.
  static func makeConfig(
    _ model: ScriptedDecisionModel,
    batchSize: Int = DecisionConfig.defaultBatchSize,
  ) -> DecisionConfig {
    DecisionConfig(model: model, batchSize: batchSize, question: idQuestion)
  }

  /// Makes a `.decision` searcher.
  ///
  /// - Parameters:
  ///   - config: the decision configuration of the searcher.
  ///   - items: the catalog of the searcher. Defaults to `catalog`.
  /// - Returns: the new searcher.
  static func makeSearcher(_ config: DecisionConfig, items: [FixtureItem] = catalog)
    -> MetadataSearcher<FixtureItem>
  {
    MetadataSearcher(items: items, mode: .decision, decision: config)
  }

  /// Gives the ids that the retrieval tier finds for `intent`, in the
  /// retrieval order.
  ///
  /// - Parameter items: the catalog to search. Defaults to `catalog`.
  /// - Returns: the ids of the retrieval matches.
  /// - Throws: what the retrieval search throws.
  static func retrievalIDs(over items: [FixtureItem] = catalog) async throws -> [String] {
    let retrieval = MetadataSearcher(items: items, mode: .retrieval)
    return try await retrieval.search(intent: intent, limit: items.count).map(\.id)
  }

  /// Gives a P(yes) of `highProbability` for each item of `items`.
  ///
  /// - Parameter items: the items that the model says "yes" to.
  /// - Returns: the P(yes) of each id.
  static func highProbabilities(for items: [FixtureItem]) -> [String: Double] {
    Dictionary(uniqueKeysWithValues: items.map { ($0.id, highProbability) })
  }

  // MARK: - Order by P(yes)

  @Test
  func decisionMatchesFollowTheProbabilityOfTheModelNotTheRetrievalOrder() async throws {
    let retrievalIDs = try await Self.retrievalIDs()
    let reversed = Array(retrievalIDs.reversed())
    let probabilities = Dictionary(
      uniqueKeysWithValues: reversed.enumerated().map { position, id in
        (id, Self.highProbability - Double(position) * Self.probabilityStep)
      })
    let searcher = Self.makeSearcher(Self.makeConfig(Self.makeModel(probabilities)))

    let matches = try await searcher.search(intent: Self.intent, limit: Self.limit)

    #expect(matches.map(\.id) == reversed)
  }

  @Test
  func eachDecisionMatchScoreIsTheProbabilityOfTheModel() async throws {
    let model = Self.makeModel(["status": Self.highProbability])
    let searcher = Self.makeSearcher(Self.makeConfig(model))

    let matches = try await searcher.search(intent: Self.intent, limit: Self.limit)

    #expect(matches.map(\.score) == [Self.highProbability])
  }

  @Test
  func eachDecisionMatchKeepsTheRetrievalSignalsOfItsCandidate() async throws {
    let retrieval = MetadataSearcher(items: Self.catalog, mode: .retrieval)
    let retrievalMatch = try #require(
      try await retrieval.search(intent: Self.intent, limit: Self.limit).first(where: {
        $0.id == "status"
      }))
    let model = Self.makeModel(["status": Self.highProbability])
    let searcher = Self.makeSearcher(Self.makeConfig(model))

    let match = try #require(
      try await searcher.search(intent: Self.intent, limit: Self.limit).first)

    #expect(match.signals == retrievalMatch.signals)
  }

  @Test
  func decisionSearchReturnsAtMostLimitMatches() async throws {
    let probabilities = Self.highProbabilities(for: Self.catalog)
    let searcher = Self.makeSearcher(Self.makeConfig(Self.makeModel(probabilities)))

    let matches = try await searcher.search(intent: Self.intent, limit: Self.smallLimit)

    #expect(matches.count == Self.smallLimit)
  }

  // MARK: - The whole catalog

  @Test
  func theRetrievalTierDoesNotFindTheHiddenItemsOfTheWiderCatalog() async throws {
    let retrievalIDs = try await Self.retrievalIDs(over: Self.widerCatalog)

    #expect(Set(retrievalIDs).isDisjoint(with: [Self.firstHiddenID, Self.lastHiddenID]))
  }

  @Test
  func decisionSearchAsksOneQuestionForEachCatalogItemInCatalogOrder() async throws {
    let model = Self.makeModel()
    let searcher = Self.makeSearcher(Self.makeConfig(model), items: Self.widerCatalog)

    _ = try await searcher.search(intent: Self.intent, limit: Self.limit)

    let askedIDs = model.batches.flatMap(\.questions).map(Self.candidateID)
    #expect(askedIDs == Self.widerCatalog.map(\.id))
  }

  @Test
  func anItemThatRetrievalDoesNotFindIsAMatchWhenTheModelSaysYes() async throws {
    let model = Self.makeModel([Self.lastHiddenID: Self.highProbability])
    let searcher = Self.makeSearcher(Self.makeConfig(model), items: Self.widerCatalog)

    let matches = try await searcher.search(intent: Self.intent, limit: Self.limit)

    #expect(matches.map(\.id) == [Self.lastHiddenID])
  }

  @Test
  func anItemThatRetrievalDoesNotFindHasNoSignals() async throws {
    let model = Self.makeModel([Self.lastHiddenID: Self.highProbability])
    let searcher = Self.makeSearcher(Self.makeConfig(model), items: Self.widerCatalog)

    let match = try #require(
      try await searcher.search(intent: Self.intent, limit: Self.limit).first)

    #expect(match.signals == Self.noSignals)
  }

  @Test
  func equalProbabilitiesKeepTheRetrievalOrderAndThenTheCatalogOrder() async throws {
    let retrievalIDs = try await Self.retrievalIDs(over: Self.widerCatalog)
    let unrankedIDs = Self.widerCatalog.map(\.id).filter { !retrievalIDs.contains($0) }
    let model = Self.makeModel(Self.highProbabilities(for: Self.widerCatalog))
    let searcher = Self.makeSearcher(Self.makeConfig(model), items: Self.widerCatalog)

    let matches = try await searcher.search(intent: Self.intent, limit: Self.limit)

    #expect(matches.map(\.id) == retrievalIDs + unrankedIDs)
  }

  @Test
  func anEmptyCatalogAsksTheModelNothing() async throws {
    let model = Self.makeModel()
    let searcher = Self.makeSearcher(Self.makeConfig(model), items: [])

    _ = try await searcher.search(intent: Self.intent, limit: Self.limit)

    #expect(model.batches.isEmpty)
  }

  // MARK: - One batch for each search

  @Test
  func decisionSearchAsksTheModelOneBatch() async throws {
    let model = Self.makeModel()
    let searcher = Self.makeSearcher(Self.makeConfig(model))

    _ = try await searcher.search(intent: Self.intent, limit: Self.limit)

    #expect(model.batches.count == 1)
  }

  @Test
  func aLargeCatalogGoesToTheModelInBatchesOfTheBatchSize() async throws {
    let model = Self.makeModel()
    let config = Self.makeConfig(model, batchSize: Self.largeBatchSize)
    let searcher = Self.makeSearcher(config, items: Self.largeCatalog)

    _ = try await searcher.search(intent: Self.intent, limit: Self.limit)

    #expect(model.batches.map(\.questions.count) == Self.largeCatalogBatchSizes)
  }

  @Test
  func theBatchesOfOneSearchGoToOneDecisionSession() async throws {
    let model = Self.makeModel()
    let config = Self.makeConfig(model, batchSize: Self.largeBatchSize)
    let searcher = Self.makeSearcher(config, items: Self.largeCatalog)

    _ = try await searcher.search(intent: Self.intent, limit: Self.limit)

    #expect(model.executorCount == 1)
  }

  @Test
  func theStateOfTheDecisionSessionIsTheIntent() async throws {
    let model = Self.makeModel()
    let searcher = Self.makeSearcher(Self.makeConfig(model))

    _ = try await searcher.search(intent: Self.intent, limit: Self.limit)

    #expect(model.batches.map(\.state) == [.text(Self.intent)])
  }

  @Test
  func aZeroLimitAsksTheModelNothing() async throws {
    let model = Self.makeModel()
    let searcher = Self.makeSearcher(Self.makeConfig(model))

    _ = try await searcher.search(intent: Self.intent, limit: 0)

    #expect(model.batches.isEmpty)
  }

  @Test
  func aZeroLimitGivesNoMatches() async throws {
    let model = Self.makeModel(["status": Self.highProbability])
    let searcher = Self.makeSearcher(Self.makeConfig(model))

    let matches = try await searcher.search(intent: Self.intent, limit: 0)

    #expect(matches.isEmpty)
  }

  // MARK: - Minimum probability

  @Test
  func aCandidateBelowTheMinimumProbabilityIsNotAMatch() async throws {
    let model = Self.makeModel([
      "status": Self.highProbability, "rollback": Self.lowProbability,
    ])
    let searcher = Self.makeSearcher(Self.makeConfig(model))

    let matches = try await searcher.search(intent: Self.intent, limit: Self.limit)

    #expect(matches.map(\.id) == ["status"])
  }

  @Test
  func aLowProbabilityForEachCandidateGivesNoMatches() async throws {
    let probabilities = Dictionary(
      uniqueKeysWithValues: Self.catalog.map { ($0.id, Self.lowProbability) })
    let searcher = Self.makeSearcher(Self.makeConfig(Self.makeModel(probabilities)))

    let matches = try await searcher.search(intent: Self.intent, limit: Self.limit)

    #expect(matches.isEmpty)
  }

  // MARK: - Routing

  @Test
  func decisionModeWithNoConfigThrowsDecisionTierUnavailable() async throws {
    let searcher = MetadataSearcher(items: Self.catalog, mode: .decision)

    await #expect(throws: DecisionTierUnavailable.self) {
      _ = try await searcher.search(intent: Self.intent, limit: Self.limit)
    }
  }

  @Test
  func autoModeUsesTheDecisionTierAlsoWhenASelectionTierIsConfigured() async throws {
    let model = Self.makeModel()
    let selection = SelectionConfig(model: ScriptedLanguageModel([#"{"ids":["deploy"]}"#]))
    let searcher = MetadataSearcher(
      items: Self.catalog, mode: .auto, selection: selection, decision: Self.makeConfig(model))

    _ = try await searcher.search(intent: Self.intent, limit: Self.limit)

    #expect(model.batches.count == 1)
  }

  // MARK: - Errors

  @Test
  func anErrorOfTheModelGoesToTheCaller() async throws {
    let searcher = Self.makeSearcher(Self.makeConfig(Self.makeModel(fails: true)))

    await #expect(throws: ScriptedDecisionModelError.scriptedFailure) {
      _ = try await searcher.search(intent: Self.intent, limit: Self.limit)
    }
  }

  // MARK: - Concurrent update

  @Test(.timeLimit(.minutes(1)))
  func aConcurrentUpdateDuringTheModelCallDoesNotMixTwoCatalogs() async throws {
    let gate = EmbedGate()
    let probabilities = Self.highProbabilities(for: Self.catalog)
    let searcher = Self.makeSearcher(
      Self.makeConfig(Self.makeModel(probabilities, gate: gate)))

    async let pending = searcher.search(intent: Self.intent, limit: Self.limit)
    await gate.waitForStart()
    await searcher.update(items: Self.secondCatalog)
    await gate.release()
    let matches = try await pending

    #expect(Set(matches.map(\.item.catalogName)) == [Self.firstCatalogName])
    #expect(matches.allSatisfy { $0.block == $0.item.block })
  }
}
