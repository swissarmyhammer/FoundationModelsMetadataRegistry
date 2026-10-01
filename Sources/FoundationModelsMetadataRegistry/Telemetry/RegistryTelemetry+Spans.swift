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
  /// When `body` throws, the span records the error, the error status and
  /// the type of the error (``recordFailure(_:on:)``), and this function
  /// throws the same error.
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
      { span in try await run(body, recordingFailureOn: span) },
    )
  }

  /// Runs `body` in `span`, and marks the span as failed when `body`
  /// throws.
  ///
  /// - Parameters:
  ///   - body: the call.
  ///   - span: the open span of the call.
  /// - Returns: the value of `body`.
  /// - Throws: the error of `body`, after ``recordFailure(_:on:)``.
  private nonisolated(nonsending) static func run<Output>(
    _ body: nonisolated(nonsending) (any Span) async throws -> Output,
    recordingFailureOn span: any Span,
  ) async throws -> Output {
    do {
      return try await body(span)
    } catch {
      recordFailure(error, on: span)
      throw error
    }
  }

  /// Marks `span` as failed because of `error`.
  ///
  /// Sets the error status with no message, and sets
  /// ``AttributeKey/errorType`` to the name of the type of `error`. The
  /// message of `error` never goes into an attribute or into the status,
  /// because a message can hold the query text or the content of an item.
  ///
  /// - Parameters:
  ///   - error: the error that ended the call of the span.
  ///   - span: the span to mark.
  private static func recordFailure(_ error: any Error, on span: any Span) {
    span.setStatus(SpanStatus(code: .error))
    span.attributes[AttributeKey.errorType] = String(describing: type(of: error))
  }
}
