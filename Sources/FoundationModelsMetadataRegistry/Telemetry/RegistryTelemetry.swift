import Tracing

/// The telemetry vocabulary of the registry: the name of each span it opens,
/// the key of each span attribute, the name of each metric, the key of each
/// log metadata value, the label of its logger, and the rule that selects
/// the tracer of a call.
///
/// This file is the one home of the vocabulary, so each name has one
/// spelling. A name here is part of the observable surface of the registry:
/// a dashboard, a query or an alert of a host application can use it. Thus
/// change a name only as a deliberate break.
///
/// Each name starts with the module prefix ``namePrefix``, so the telemetry
/// of the registry is easy to find among the telemetry of the host
/// application.
///
/// The registry is a library. It uses the telemetry APIs only:
/// swift-distributed-tracing, swift-log and swift-metrics. It does not
/// bootstrap a backend. An executable of the family bootstraps the backend.
/// Until an executable does, each span, each logger and each metric of the
/// registry does nothing, so an application that does not observe pays
/// nothing.
///
/// ## No content in the telemetry
///
/// A span attribute, a log message, a log metadata value and a metric
/// dimension must never hold the query text (the `intent` of a search), the
/// content of a catalog item (a rendered block, an indexed text or an
/// embedded text), or a vector. The telemetry leaves the process through the
/// backend that the host application bootstrapped, and the registry cannot
/// know where that backend sends it. Thus the telemetry must not hold the
/// content of the caller. Identifiers, names, counts and sizes are safe.
/// Content is not safe.
enum RegistryTelemetry {
    /// The text that each name of the vocabulary starts with: the module
    /// name and a dot.
    static let namePrefix = "FoundationModelsMetadataRegistry."

    /// The label of the logger of the registry.
    static let loggerLabel = namePrefix + "MetadataDiagnostic"

    // The span tasks of the OpenTelemetry design add the first names.
    // periphery:ignore
    /// The operation name of each span that the registry opens.
    ///
    /// Each name starts with ``RegistryTelemetry/namePrefix``.
    enum SpanName {}

    // The span tasks of the OpenTelemetry design add the first keys.
    // periphery:ignore
    /// The key of each attribute that a span of the registry holds.
    ///
    /// Read the "no content" rule of ``RegistryTelemetry`` before you add a
    /// key. A key names an identifier, a name, a count or a size. It never
    /// names content of the caller.
    enum AttributeKey {}

    // The metrics task of the OpenTelemetry design adds the first names.
    // periphery:ignore
    /// The name of each metric that the registry records.
    ///
    /// Each name starts with ``RegistryTelemetry/namePrefix``. A dimension of
    /// a metric obeys the "no content" rule of ``RegistryTelemetry``.
    enum MetricName {}

    // The logging task of the OpenTelemetry design adds the first keys.
    // periphery:ignore
    /// The key of each metadata value that a log record of the registry
    /// holds.
    ///
    /// Read the "no content" rule of ``RegistryTelemetry`` before you add a
    /// key. A metadata value is an identifier, a name, a count or a size.
    enum MetadataKey {}

    /// Selects the tracer that a call opens its span through.
    ///
    /// `nil` resolves the tracer late: the call reads the tracer at the time
    /// of the call, not at the time the caller made its handle. Thus an
    /// application that bootstraps a tracing backend after it makes a
    /// searcher still gets the spans of that searcher.
    ///
    /// - Parameter explicit: The tracer that the caller set, or `nil` to read
    ///   the bootstrapped tracer at the call.
    /// - Returns: `explicit` when it is set, else
    ///   `InstrumentationSystem.tracer`.
    static func tracer(explicit: (any Tracer)?) -> any Tracer {
        explicit ?? InstrumentationSystem.tracer
    }
}
