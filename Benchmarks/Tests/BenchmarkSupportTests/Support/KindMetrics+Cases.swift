@testable import BenchmarkSupport

/// The value of each case of `KindMetrics`, as an optional, so that a test
/// unwraps it with `#require` and does not use `guard`.
extension KindMetrics {
  /// The metrics of a kind with an answer, or `nil` for the off-topic case.
  var answerable: AnswerableMetrics? {
    if case .answerable(let metrics) = self { metrics } else { nil }
  }

  /// The metrics of the off-topic kind, or `nil` for the answerable case.
  var offTopic: OffTopicMetrics? {
    if case .offTopic(let metrics) = self { metrics } else { nil }
  }
}
