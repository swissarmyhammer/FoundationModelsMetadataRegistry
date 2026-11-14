import Testing

@testable import BenchmarkSupport

/// The aggregates for each kind of intent, measured on outcomes that a person
/// can compute by hand.
@Suite("Kind summaries")
struct KindSummaryTests {
  /// The recall cutoff of every summary in this suite.
  static let recallCutoff = 1

  /// The latency of every outcome in this suite. The summaries do not read
  /// it.
  static let latency = Duration.milliseconds(1)

  /// Two lexical outcomes. The first finds `a` at rank 1. The second finds
  /// `a` at rank 2.
  static let lexicalOutcomes = [
    outcome(kind: .lexical, relevant: ["a"], ranked: ["a"]),
    outcome(kind: .lexical, relevant: ["a"], ranked: ["x", "a"]),
  ]

  /// Two off-topic outcomes. The first returns nothing. The second returns
  /// two ids.
  static let offTopicOutcomes = [
    outcome(kind: .offTopic, relevant: [], ranked: []),
    outcome(kind: .offTopic, relevant: [], ranked: ["a", "b"]),
  ]

  /// Makes one outcome for an intent of `kind`.
  ///
  /// - Parameters:
  ///   - kind: the kind of the intent.
  ///   - relevant: the relevant ids of the intent.
  ///   - ranked: the ids that the search returned, in order.
  /// - Returns: the outcome, with the latency of this suite.
  static func outcome(
    kind: LabeledIntent.Kind,
    relevant: Set<String>,
    ranked: [String],
  ) -> IntentOutcome {
    IntentOutcome(
      intent: LabeledIntent(text: "intent", relevantIDs: relevant, kind: kind),
      rankedIDs: ranked,
      latency: latency,
    )
  }

  /// The summaries of the lexical and off-topic outcomes, in that order.
  static func summaries() -> [KindSummary] {
    RankingMetrics.summaries(
      of: offTopicOutcomes + lexicalOutcomes,
      recallCutoff: recallCutoff,
    )
  }

  /// hit@1 is (1 + 0) / 2, recall@1 is (1 + 0) / 2, and the mean reciprocal
  /// rank is (1 + 1/2) / 2.
  @Test("the lexical summary holds the mean of each metric")
  func lexicalSummaryHoldsTheMeanOfEachMetric() {
    let hitAt1 = 0.5
    let recall = 0.5
    let meanReciprocalRank = 0.75
    let expected = KindSummary(
      kind: .lexical,
      intentCount: Self.lexicalOutcomes.count,
      metrics: .answerable(
        AnswerableMetrics(
          hitAt1: hitAt1,
          recallAtCutoff: recall,
          meanReciprocalRank: meanReciprocalRank,
        ),
      ),
    )
    #expect(Self.summaries().first == expected)
  }

  /// One of the two outcomes is empty, and the two outcomes return 0 and 2
  /// ids that are not relevant.
  @Test("the off-topic summary holds the empty rate and the mean false positive count")
  func offTopicSummaryHoldsTheEmptyRateAndTheMeanFalsePositiveCount() {
    let emptyRate = 0.5
    let meanFalsePositiveCount = 1.0
    let expected = KindSummary(
      kind: .offTopic,
      intentCount: Self.offTopicOutcomes.count,
      metrics: .offTopic(
        OffTopicMetrics(emptyRate: emptyRate, meanFalsePositiveCount: meanFalsePositiveCount),
      ),
    )
    #expect(Self.summaries().last == expected)
  }

  /// The input holds no paraphrase and no multi-step outcome, so only the
  /// two kinds that have outcomes get a summary, in the order of
  /// `LabeledIntent.Kind.allCases`.
  @Test("only the kinds that have outcomes get a summary, in kind order")
  func onlyTheKindsThatHaveOutcomesGetASummaryInKindOrder() {
    let expected: [LabeledIntent.Kind] = [.lexical, .offTopic]
    #expect(Self.summaries().map(\.kind) == expected)
  }

  /// No outcome gives no summary.
  @Test("no outcome gives no summary")
  func noOutcomeGivesNoSummary() {
    #expect(RankingMetrics.summaries(of: [], recallCutoff: Self.recallCutoff).isEmpty)
  }
}
