/// The result of one search for one labeled intent.
public struct IntentOutcome: Sendable {
  /// The intent that the search used.
  public let intent: LabeledIntent

  /// The ids that the search returned, best first.
  public let rankedIDs: [String]

  /// The time that the search took.
  public let latency: Duration

  /// Makes one outcome.
  ///
  /// - Parameters:
  ///   - intent: the intent that the search used.
  ///   - rankedIDs: the ids that the search returned, best first.
  ///   - latency: the time that the search took.
  public init(intent: LabeledIntent, rankedIDs: [String], latency: Duration) {
    self.intent = intent
    self.rankedIDs = rankedIDs
    self.latency = latency
  }
}

/// The mean metrics of the intents that have an answer: lexical, paraphrase
/// and multi-step.
public struct AnswerableMetrics: Codable, Equatable, Sendable {
  /// The mean hit@1.
  public let hitAt1: Double

  /// The mean recall at the cutoff of the report.
  public let recallAtCutoff: Double

  /// The mean reciprocal rank.
  public let meanReciprocalRank: Double
}

/// The mean metrics of the off-topic intents, which have no answer.
public struct OffTopicMetrics: Codable, Equatable, Sendable {
  /// The fraction of the searches that returned no id.
  public let emptyRate: Double

  /// The mean count of returned ids that are not relevant.
  public let meanFalsePositiveCount: Double
}

/// The metrics of one kind of intent. An intent with an answer and an
/// off-topic intent have different metrics.
public enum KindMetrics: Codable, Equatable, Sendable {
  /// The metrics of the lexical, paraphrase or multi-step intents.
  case answerable(AnswerableMetrics)
  /// The metrics of the off-topic intents.
  case offTopic(OffTopicMetrics)
}

/// The aggregate metrics of the intents of one kind.
public struct KindSummary: Codable, Equatable, Sendable {
  /// The kind of the intents.
  public let kind: LabeledIntent.Kind

  /// The count of the intents of this kind.
  public let intentCount: Int

  /// The mean metrics of the intents of this kind.
  public let metrics: KindMetrics
}

/// The ranking metrics: pure functions over the ranked ids that a search
/// returned and the ids that are relevant.
public enum RankingMetrics {
  /// The fraction for the 50th percentile.
  static let medianFraction = 0.5

  /// The fraction for the 95th percentile.
  static let p95Fraction = 0.95

  /// Tells if the first ranked id is relevant.
  ///
  /// - Parameters:
  ///   - ranked: the returned ids, best first.
  ///   - relevant: the ids that answer the intent.
  /// - Returns: 1 when the first id is relevant, else 0. An empty list gives 0.
  public static func hitAt1(ranked: [String], relevant: Set<String>) -> Double {
    ranked.first.map(relevant.contains) == true ? 1 : 0
  }

  /// The fraction of the relevant ids that are in the first `cutoff` ranked
  /// ids.
  ///
  /// - Parameters:
  ///   - cutoff: the count of ranked ids to read. A cutoff larger than the
  ///     list reads the whole list.
  ///   - ranked: the returned ids, best first.
  ///   - relevant: the ids that answer the intent.
  /// - Returns: the recall in `[0, 1]`. When no id is relevant, there is
  ///   nothing to recall, and the result is 0.
  public static func recall(at cutoff: Int, ranked: [String], relevant: Set<String>) -> Double {
    guard !relevant.isEmpty else { return 0 }
    let found = Set(ranked.prefix(cutoff)).intersection(relevant)
    return Double(found.count) / Double(relevant.count)
  }

  /// One over the rank of the first relevant id.
  ///
  /// - Parameters:
  ///   - ranked: the returned ids, best first.
  ///   - relevant: the ids that answer the intent.
  /// - Returns: `1 / rank` of the first relevant id, where the first id has
  ///   rank 1. When no ranked id is relevant, the result is 0.
  public static func reciprocalRank(ranked: [String], relevant: Set<String>) -> Double {
    guard let index = ranked.firstIndex(where: relevant.contains) else { return 0 }
    return 1 / Double(index + 1)
  }

  /// Tells if a search returned no id. This is the correct result for an
  /// off-topic intent.
  ///
  /// - Parameter ranked: the returned ids.
  /// - Returns: `true` when `ranked` is empty.
  public static func isEmpty(ranked: [String]) -> Bool {
    ranked.isEmpty
  }

  /// The count of returned ids that are not relevant. For an off-topic
  /// intent, each returned id is a false positive.
  ///
  /// - Parameters:
  ///   - ranked: the returned ids.
  ///   - relevant: the ids that answer the intent.
  /// - Returns: the count of ids in `ranked` that are not in `relevant`.
  public static func falsePositiveCount(ranked: [String], relevant: Set<String>) -> Int {
    ranked.filter { !relevant.contains($0) }.count
  }

  /// The arithmetic mean of `values`.
  ///
  /// - Parameter values: the values to average.
  /// - Returns: the mean, or `nil` when `values` is empty.
  public static func mean(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    return values.reduce(0, +) / Double(values.count)
  }

  /// The 50th percentile of `durations`, by the nearest-rank method.
  ///
  /// - Parameter durations: the durations, in any order.
  /// - Returns: the median, or `nil` when `durations` is empty.
  public static func p50(of durations: [Duration]) -> Duration? {
    percentile(medianFraction, of: durations)
  }

  /// The 95th percentile of `durations`, by the nearest-rank method.
  ///
  /// - Parameter durations: the durations, in any order.
  /// - Returns: the 95th percentile, or `nil` when `durations` is empty.
  public static func p95(of durations: [Duration]) -> Duration? {
    percentile(p95Fraction, of: durations)
  }

  /// A percentile of `durations`, by the nearest-rank method: the value at
  /// rank `ceil(fraction * count)` of the sorted list, where the first value
  /// has rank 1.
  ///
  /// - Parameters:
  ///   - fraction: the percentile as a fraction in `(0, 1]`.
  ///   - durations: the durations, in any order.
  /// - Returns: the percentile, or `nil` when `durations` is empty.
  static func percentile(_ fraction: Double, of durations: [Duration]) -> Duration? {
    guard !durations.isEmpty else { return nil }
    let sorted = durations.sorted()
    let rank = Int((fraction * Double(sorted.count)).rounded(.up))
    return sorted[min(max(rank, 1), sorted.count) - 1]
  }

  /// The summary of each kind that has outcomes, in the order of
  /// `LabeledIntent.Kind.allCases`.
  ///
  /// - Parameters:
  ///   - outcomes: the outcomes of the searches, of any kinds.
  ///   - recallCutoff: the count of ranked ids that recall reads.
  /// - Returns: one summary for each kind that has at least one outcome.
  public static func summaries(of outcomes: [IntentOutcome], recallCutoff: Int) -> [KindSummary] {
    let outcomesByKind = Dictionary(grouping: outcomes, by: \.intent.kind)
    return LabeledIntent.Kind.allCases.compactMap { kind in
      outcomesByKind[kind].map { summary(of: kind, outcomes: $0, recallCutoff: recallCutoff) }
    }
  }

  /// The summary of the outcomes of one kind.
  ///
  /// - Parameters:
  ///   - kind: the kind of every outcome in `outcomes`.
  ///   - outcomes: the outcomes. The list is not empty.
  ///   - recallCutoff: the count of ranked ids that recall reads.
  /// - Returns: the summary of `outcomes`.
  static func summary(
    of kind: LabeledIntent.Kind,
    outcomes: [IntentOutcome],
    recallCutoff: Int,
  ) -> KindSummary {
    let metrics: KindMetrics
    switch kind {
    case .lexical, .paraphrase, .multiStep:
      metrics = .answerable(answerableMetrics(of: outcomes, recallCutoff: recallCutoff))
    case .offTopic:
      metrics = .offTopic(offTopicMetrics(of: outcomes))
    }
    return KindSummary(kind: kind, intentCount: outcomes.count, metrics: metrics)
  }

  /// The mean metrics of outcomes whose intents have an answer.
  ///
  /// - Parameters:
  ///   - outcomes: the outcomes.
  ///   - recallCutoff: the count of ranked ids that recall reads.
  /// - Returns: the mean hit@1, recall and reciprocal rank.
  static func answerableMetrics(of outcomes: [IntentOutcome], recallCutoff: Int)
    -> AnswerableMetrics
  {
    AnswerableMetrics(
      hitAt1: average(outcomes) { hitAt1(ranked: $0.rankedIDs, relevant: $0.intent.relevantIDs) },
      recallAtCutoff: average(outcomes) {
        recall(at: recallCutoff, ranked: $0.rankedIDs, relevant: $0.intent.relevantIDs)
      },
      meanReciprocalRank: average(outcomes) {
        reciprocalRank(ranked: $0.rankedIDs, relevant: $0.intent.relevantIDs)
      },
    )
  }

  /// The mean metrics of off-topic outcomes.
  ///
  /// - Parameter outcomes: the outcomes.
  /// - Returns: the empty rate and the mean false positive count.
  static func offTopicMetrics(of outcomes: [IntentOutcome]) -> OffTopicMetrics {
    OffTopicMetrics(
      emptyRate: average(outcomes) { isEmpty(ranked: $0.rankedIDs) ? 1 : 0 },
      meanFalsePositiveCount: average(outcomes) {
        Double(falsePositiveCount(ranked: $0.rankedIDs, relevant: $0.intent.relevantIDs))
      },
    )
  }

  /// The mean of one metric over `outcomes`.
  ///
  /// - Precondition: `outcomes` is not empty. `summaries(of:recallCutoff:)`
  ///   groups the outcomes by kind, and a group is never empty.
  /// - Parameters:
  ///   - outcomes: the outcomes to measure.
  ///   - metric: the metric of one outcome.
  /// - Returns: the mean of `metric` over `outcomes`.
  static func average(
    _ outcomes: [IntentOutcome],
    metric: (IntentOutcome) -> Double,
  ) -> Double {
    precondition(!outcomes.isEmpty, "a kind summary needs at least one outcome")
    return outcomes.map(metric).reduce(0, +) / Double(outcomes.count)
  }
}
