import FoundationModelsMetadataRegistry
import Testing

@testable import BenchmarkSupport

/// The benchmark runner, over configurations that load no model: a keyword
/// retrieval configuration, and decision configurations over a
/// `LabelDecisionModel`.
@Suite("Benchmark runner")
struct BenchmarkRunnerTests {
  /// The repeat count of each run in this suite.
  static let repeats = 2

  /// The wait of the first embed call in the warm-up test. It is much
  /// longer than a search over the fixture catalog with stub models.
  static let warmUpDelay = Duration.milliseconds(500)

  /// The intents of each run: all the labeled intents of the fixture.
  static let intents = BenchmarkIntents.all

  /// A configuration that searches with keywords only.
  static let keywordConfiguration = BenchmarkConfiguration(name: "retrieval-keyword") { items in
    MetadataSearcher(items: items, mode: .retrieval)
  }

  /// A decision configuration over a `LabelDecisionModel`.
  ///
  /// The embedder gives each item a cosine of 1. The decision tier asks the
  /// model about each catalog item.
  ///
  /// - Parameters:
  ///   - name: the name of the configuration.
  ///   - fails: whether the model throws for each batch.
  ///   - firstEmbedDelay: the wait of the first embed call.
  /// - Returns: the configuration.
  static func decisionConfiguration(
    name: String,
    fails: Bool = false,
    firstEmbedDelay: Duration = .zero,
  ) -> BenchmarkConfiguration {
    BenchmarkConfiguration(name: name) { items in
      MetadataSearcher(
        items: items,
        mode: .decision,
        embedder: ConstantEmbedder(firstCallDelay: firstEmbedDelay),
        decision: DecisionConfig(
          model: LabelDecisionModel(intents: intents, fails: fails),
          question: LabelDecisionModel.question,
        ),
      )
    }
  }

  /// Runs `configurations` over the fixture.
  ///
  /// - Parameter configurations: the configurations to run.
  /// - Returns: the report of the run.
  static func run(_ configurations: [BenchmarkConfiguration]) async -> BenchmarkReport {
    await BenchmarkRunner.run(
      configurations,
      intents: intents,
      catalog: BenchmarkCatalog.items,
      repeats: repeats,
    )
  }

  /// The measurement of the only row of `report`.
  ///
  /// - Parameter report: a report with one measured row.
  /// - Returns: the measurement of that row.
  /// - Throws: when the report has no row, or its row is not measured.
  static func onlyMeasurement(of report: BenchmarkReport) throws -> BenchmarkReport.Measurement {
    try #require(report.rows.first?.measurement)
  }

  /// The report has one row for each configuration, in the order of the
  /// configurations.
  @Test("the report has one row for each configuration")
  func reportHasOneRowForEachConfiguration() async {
    let configurations = [
      Self.keywordConfiguration, Self.decisionConfiguration(name: "decision-stub"),
    ]
    let report = await Self.run(configurations)
    #expect(report.rows.map(\.name) == configurations.map(\.name))
  }

  /// The recall cutoff of the report is the limit of each search.
  @Test("the recall cutoff of the report is the search limit")
  func recallCutoffOfTheReportIsTheSearchLimit() async {
    let report = await Self.run([Self.keywordConfiguration])
    #expect(report.recallCutoff == BenchmarkConfiguration.limit)
  }

  /// A model that answers from the labels puts a relevant id first for each
  /// intent that has an answer.
  @Test(
    "the label model has hit@1 of 1 for each kind with an answer",
    arguments: [LabeledIntent.Kind.lexical, .paraphrase, .multiStep],
  )
  func labelModelHasHitAt1OfOneForEachKindWithAnAnswer(kind: LabeledIntent.Kind) async throws {
    let report = await Self.run([Self.decisionConfiguration(name: "decision-stub")])
    let metrics = try Self.onlyMeasurement(of: report).metrics(of: kind)
    #expect(try #require(metrics?.answerable).hitAt1 == 1)
  }

  /// A model that answers from the labels gives an empty result for each
  /// off-topic intent.
  @Test("the label model gives an empty result for each off-topic intent")
  func labelModelGivesAnEmptyResultForEachOffTopicIntent() async throws {
    let report = await Self.run([Self.decisionConfiguration(name: "decision-stub")])
    let metrics = try Self.onlyMeasurement(of: report).metrics(of: .offTopic)
    #expect(try #require(metrics?.offTopic).emptyRate == 1)
  }

  /// A configuration whose searches all succeed has no error.
  @Test("a configuration whose searches succeed has an error count of zero")
  func configurationWhoseSearchesSucceedHasAnErrorCountOfZero() async throws {
    let report = await Self.run([Self.keywordConfiguration])
    #expect(try Self.onlyMeasurement(of: report).errorCount == 0)
  }

  /// A model that throws for each batch gives one error for each search,
  /// the warm-up search included, and the run continues.
  @Test("a model that throws gives an error count and the run continues")
  func modelThatThrowsGivesAnErrorCountAndTheRunContinues() async throws {
    let warmUpSearchCount = 1
    let report = await Self.run([
      Self.decisionConfiguration(name: "decision-fails", fails: true)
    ])
    let measurement = try Self.onlyMeasurement(of: report)
    #expect(measurement.errorCount == Self.intents.count * Self.repeats + warmUpSearchCount)
  }

  /// The warm-up search takes the first-embed wait, and the latency
  /// percentiles do not include it.
  @Test("the warm-up search is not in the latency percentiles")
  func warmUpSearchIsNotInTheLatencyPercentiles() async throws {
    let report = await Self.run([
      Self.decisionConfiguration(name: "decision-slow-warm-up", firstEmbedDelay: Self.warmUpDelay)
    ])
    let measurement = try Self.onlyMeasurement(of: report)
    #expect(measurement.firstSearch >= Self.warmUpDelay)
    #expect(measurement.p95 < Self.warmUpDelay)
  }

  /// A configuration that tells a reason to not run gets a row with that
  /// reason, and the runner makes no searcher for it.
  @Test("an unavailable configuration gives its reason and no metrics")
  func unavailableConfigurationGivesItsReasonAndNoMetrics() async throws {
    let reason = "the model is not ready"
    let configuration = BenchmarkConfiguration(
      name: "unavailable",
      unavailableReason: { reason },
      makeSearcher: { items in
        Issue.record("the runner made a searcher for an unavailable configuration")
        return MetadataSearcher(items: items, mode: .retrieval)
      },
    )
    let report = await Self.run([configuration])
    #expect(try #require(report.rows.first).status == .unavailable(reason: reason))
  }
}
