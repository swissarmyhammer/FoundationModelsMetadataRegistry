import FoundationModelsExtras
import Logging
import Tracing

/// The helpers that open the spans of the registry.
extension RegistryTelemetry {
  /// Makes a new logger of the registry, with the label ``loggerLabel``.
  ///
  /// Each call makes a new logger, and no logger is kept in a `static let`.
  /// A logger keeps the log handler of the time that it was made, so a
  /// kept logger that was made before the host bootstrapped its logging
  /// backend would never reach that backend.
  ///
  /// - Returns: a logger of the registry.
  static func makeLogger() -> Logger {
    Logger(label: loggerLabel)
  }

  /// Runs `body` in one span that can wait for a long time, and marks the
  /// span as failed when `body` throws.
  ///
  /// Rule 8 of the OpenTelemetry design of 2026-09-28, hang detection: a
  /// call that waits on a model session or on an embedder opens its span
  /// through `TracedCall.run` of FoundationModelsExtras. That helper also
  /// writes one "enter" log record when the call starts, so a call that
  /// hangs still shows in the logging backend. The tracer is resolved late,
  /// through ``tracer(explicit:)``, at each call.
  ///
  /// When `body` throws, `TracedCall.run` gives the span the error status
  /// with no message, and sets ``AttributeKey/errorType``. Then this
  /// function throws the same error. The span never gets the message of the
  /// error, because a message can hold the query text or the content of an
  /// item.
  ///
  /// Rule 4: `spanName` and `attributes` hold no content of the caller.
  ///
  /// - Parameters:
  ///   - spanName: the name of the span, from ``SpanName``.
  ///   - attributes: the attributes of the span, set before the "enter"
  ///     record is written. The keys come from ``AttributeKey``.
  ///   - body: the call. It gets the open span, and it runs on the actor of
  ///     the caller.
  /// - Returns: the value of `body`.
  /// - Throws: the error of `body`.
  nonisolated(nonsending) static func withTracedSpan<Output>(
    _ spanName: String,
    attributes: SpanAttributes,
    _ body: nonisolated(nonsending) (any Span) async throws -> Output,
  ) async throws -> Output {
    try await TracedCall.run(
      spanName,
      tracer: tracer(explicit: nil),
      logger: makeLogger(),
      attributes: { $0.merge(attributes) },
      body,
    )
  }

  /// Runs one call to a ranker that waits on a model in one
  /// ``SpanName/rank`` span, and records its duration in the
  /// ``MetricName/rankDuration`` timer of `ranker`.
  ///
  /// The span opens through ``withTracedSpan(_:attributes:_:)`` (rule 8),
  /// because a model can wait for a long time. The span holds
  /// ``AttributeKey/rankRanker`` and ``AttributeKey/rankCandidateCount``.
  /// The call records one duration value, also when `body` throws.
  ///
  /// - Parameters:
  ///   - ranker: the ranker that `body` calls.
  ///   - rankedCount: the count of candidates that the ranker ranks.
  ///   - body: the call to the ranker. It runs on the actor of the caller.
  /// - Returns: the value of `body`.
  /// - Throws: the error of `body`.
  nonisolated(nonsending) static func withTracedRank<Output>(
    _ ranker: Ranker,
    rankedCount: Int,
    _ body: nonisolated(nonsending) () async throws -> Output,
  ) async throws -> Output {
    let attributes: SpanAttributes = [
      AttributeKey.rankRanker: .string(ranker.rawValue),
      AttributeKey.rankCandidateCount: rankedCount.toSpanAttribute(),
    ]
    return try await withTracedSpan(SpanName.rank, attributes: attributes) { _ in
      try await rankTimer(for: ranker).measure { try await body() }
    }
  }
}
