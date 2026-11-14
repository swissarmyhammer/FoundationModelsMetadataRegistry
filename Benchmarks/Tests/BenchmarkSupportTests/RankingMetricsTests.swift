import Testing

@testable import BenchmarkSupport

/// The metric functions, measured on inputs that a person can compute by hand.
///
/// Each test gives one ranked list and one set of relevant ids, and compares
/// the result with the value that the comment above the test computes.
@Suite("Ranking metrics")
struct RankingMetricsTests {
  /// The relevant id is first, so hit@1 is 1.
  @Test("hit@1 is 1 when the first id is relevant")
  func hitAt1IsOneWhenTheFirstIDIsRelevant() {
    let expected = 1.0
    #expect(RankingMetrics.hitAt1(ranked: ["a", "b"], relevant: ["a"]) == expected)
  }

  /// The relevant id is second, so hit@1 is 0.
  @Test("hit@1 is 0 when the first id is not relevant")
  func hitAt1IsZeroWhenTheFirstIDIsNotRelevant() {
    let expected = 0.0
    #expect(RankingMetrics.hitAt1(ranked: ["a", "b"], relevant: ["b"]) == expected)
  }

  /// An empty list has no first id, so hit@1 is 0.
  @Test("hit@1 is 0 for an empty list")
  func hitAt1IsZeroForAnEmptyList() {
    let expected = 0.0
    #expect(RankingMetrics.hitAt1(ranked: [], relevant: ["a"]) == expected)
  }

  /// The top two ids are `a` and `x`. One of the two relevant ids is in them,
  /// so recall@2 is 1 / 2.
  @Test("recall@k counts the relevant ids in the top k")
  func recallCountsTheRelevantIDsInTheTopK() {
    let cutoff = 2
    let expected = 0.5
    let recall = RankingMetrics.recall(
      at: cutoff,
      ranked: ["a", "x", "b", "c"],
      relevant: ["a", "b"],
    )
    #expect(recall == expected)
  }

  /// The top three ids hold both relevant ids, so recall@3 is 1.
  @Test("recall@k is 1 when the top k hold every relevant id")
  func recallIsOneWhenTheTopKHoldEveryRelevantID() {
    let cutoff = 3
    let expected = 1.0
    let recall = RankingMetrics.recall(
      at: cutoff,
      ranked: ["a", "x", "b", "c"],
      relevant: ["a", "b"],
    )
    #expect(recall == expected)
  }

  /// The cutoff is larger than the list, so the whole list counts. One of
  /// the two relevant ids is in it, so recall is 1 / 2.
  @Test("recall@k reads the whole list when k is larger than the list")
  func recallReadsTheWholeListWhenKIsLargerThanTheList() {
    let cutoff = 10
    let expected = 0.5
    let recall = RankingMetrics.recall(at: cutoff, ranked: ["a"], relevant: ["a", "b"])
    #expect(recall == expected)
  }

  /// An empty list finds no relevant id, so recall is 0.
  @Test("recall@k is 0 for an empty list")
  func recallIsZeroForAnEmptyList() {
    let cutoff = 5
    let expected = 0.0
    #expect(RankingMetrics.recall(at: cutoff, ranked: [], relevant: ["a"]) == expected)
  }

  /// No id is relevant, so there is nothing to recall, and recall is 0.
  @Test("recall@k is 0 when no id is relevant")
  func recallIsZeroWhenNoIDIsRelevant() {
    let cutoff = 5
    let expected = 0.0
    #expect(RankingMetrics.recall(at: cutoff, ranked: ["a"], relevant: []) == expected)
  }

  /// The first relevant id is third, so the reciprocal rank is 1 / 3.
  @Test("reciprocal rank is one over the rank of the first relevant id")
  func reciprocalRankIsOneOverTheRankOfTheFirstRelevantID() {
    let rank = 3.0
    let expected = 1.0 / rank
    let reciprocalRank = RankingMetrics.reciprocalRank(
      ranked: ["x", "y", "a", "b"],
      relevant: ["a", "b"],
    )
    #expect(reciprocalRank == expected)
  }

  /// No id in the list is relevant, so the reciprocal rank is 0.
  @Test("reciprocal rank is 0 when no id in the list is relevant")
  func reciprocalRankIsZeroWhenNoIDInTheListIsRelevant() {
    let expected = 0.0
    #expect(RankingMetrics.reciprocalRank(ranked: ["x", "y"], relevant: ["a"]) == expected)
  }

  /// An empty list has no rank, so the reciprocal rank is 0.
  @Test("reciprocal rank is 0 for an empty list")
  func reciprocalRankIsZeroForAnEmptyList() {
    let expected = 0.0
    #expect(RankingMetrics.reciprocalRank(ranked: [], relevant: ["a"]) == expected)
  }

  /// An off-topic search that returns nothing is correct.
  @Test("an empty list is empty")
  func anEmptyListIsEmpty() {
    #expect(RankingMetrics.isEmpty(ranked: []))
  }

  /// An off-topic search that returns an id is not empty.
  @Test("a list with an id is not empty")
  func aListWithAnIDIsNotEmpty() {
    #expect(!RankingMetrics.isEmpty(ranked: ["a"]))
  }

  /// Two of the three ids are not relevant, so the count is 2.
  @Test("the false positive count is the count of ids that are not relevant")
  func falsePositiveCountIsTheCountOfIDsThatAreNotRelevant() {
    let expected = 2
    let count = RankingMetrics.falsePositiveCount(ranked: ["a", "b", "c"], relevant: ["b"])
    #expect(count == expected)
  }

  /// An off-topic intent has no relevant id, so each returned id is a false
  /// positive.
  @Test("each id is a false positive when no id is relevant")
  func eachIDIsAFalsePositiveWhenNoIDIsRelevant() {
    let expected = 3
    let count = RankingMetrics.falsePositiveCount(ranked: ["a", "b", "c"], relevant: [])
    #expect(count == expected)
  }

  /// An empty list holds no false positive.
  @Test("the false positive count is 0 for an empty list")
  func falsePositiveCountIsZeroForAnEmptyList() {
    let expected = 0
    #expect(RankingMetrics.falsePositiveCount(ranked: [], relevant: []) == expected)
  }

  /// (1 + 0 + 0.5) / 3 is 0.5.
  @Test("the mean is the sum over the count")
  func meanIsTheSumOverTheCount() {
    let values = [1.0, 0.0, 0.5]
    let expected = 0.5
    #expect(RankingMetrics.mean(values) == expected)
  }

  /// An empty list has no mean.
  @Test("the mean of an empty list is nil")
  func meanOfAnEmptyListIsNil() {
    #expect(RankingMetrics.mean([]) == nil)
  }

  /// Nearest rank: the 50th percentile of four values is the value at rank
  /// ceil(0.5 * 4) = 2, which is 20 ms. The input is not sorted, so the
  /// function must sort it.
  @Test("p50 is the nearest-rank median")
  func p50IsTheNearestRankMedian() {
    let durations: [Duration] = [40, 10, 30, 20].map { .milliseconds($0) }
    let expected = Duration.milliseconds(20)
    #expect(RankingMetrics.p50(of: durations) == expected)
  }

  /// Nearest rank: the 95th percentile of the twenty values 1 ms to 20 ms is
  /// the value at rank ceil(0.95 * 20) = 19, which is 19 ms.
  @Test("p95 is the nearest-rank 95th percentile")
  func p95IsTheNearestRank95thPercentile() {
    let lastMilliseconds = 20
    let durations: [Duration] = (1...lastMilliseconds).reversed().map { .milliseconds($0) }
    let expected = Duration.milliseconds(lastMilliseconds - 1)
    #expect(RankingMetrics.p95(of: durations) == expected)
  }

  /// One value is each percentile of itself.
  @Test("p95 of one value is that value")
  func p95OfOneValueIsThatValue() {
    let only = Duration.milliseconds(5)
    #expect(RankingMetrics.p95(of: [only]) == only)
  }

  /// An empty list has no percentile.
  @Test("p50 of an empty list is nil")
  func p50OfAnEmptyListIsNil() {
    #expect(RankingMetrics.p50(of: []) == nil)
  }

  /// An empty list has no percentile.
  @Test("p95 of an empty list is nil")
  func p95OfAnEmptyListIsNil() {
    #expect(RankingMetrics.p95(of: []) == nil)
  }
}
