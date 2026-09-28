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

    /// The operation name of each span that the registry opens.
    ///
    /// Each name starts with ``RegistryTelemetry/namePrefix``.
    enum SpanName {
        /// The span of one `MetadataSearcher.search(intent:limit:)` call. It
        /// also covers the embed catch-up of the first search.
        static let search = namePrefix + "search"

        /// The child span of a search around one call to a ranker: the
        /// hybrid ranker of the retrieval tier, or the selection tier.
        static let rank = namePrefix + "rank"

        /// The span of one `MetadataSearcher.update(items:)` call.
        static let catalogUpdate = namePrefix + "catalog.update"

        /// The span of one embed of the pending entries of a catalog.
        static let catalogEmbed = namePrefix + "catalog.embed"
    }

    /// The key of each attribute that a span of the registry holds.
    ///
    /// Read the "no content" rule of ``RegistryTelemetry`` before you add a
    /// key. A key names an identifier, a name, a count or a size. It never
    /// names content of the caller.
    enum AttributeKey {
        /// The configured `SearchMode` of the searcher, as a `SearchMode` raw
        /// value.
        static let searchMode = "search.mode"

        /// The tier that answered the search, as a ``Tier`` raw value.
        static let searchTier = "search.tier"

        /// The `limit` of the search.
        static let searchLimit = "search.limit"

        /// The count of matches that the search returned.
        static let searchResultCount = "search.result_count"

        /// The signals that ranked the search, as ``Signal`` raw values, in
        /// a fixed order.
        static let searchRankers = "search.rankers"

        /// The count of entries in the catalog index.
        static let catalogSize = "catalog.size"

        /// The ranker of a rank span, as a ``Ranker`` raw value.
        static let rankRanker = "rank.ranker"

        /// The count of candidates that the ranker ranked.
        static let rankCandidateCount = "rank.candidate_count"

        /// The count of items that `update(items:)` received.
        static let catalogItemCount = "catalog.item_count"

        /// Whether `update(items:)` changed the content of the catalog.
        static let catalogContentChanged = "catalog.content_changed"

        /// The count of entries that have no embedding after
        /// `update(items:)` rebuilt the catalog index.
        static let catalogPendingEmbedCount = "catalog.pending_embed_count"

        /// The count of entries that one catalog embed gives to the embedder.
        static let embedPendingCount = "embed.pending_count"

        /// The path that started a catalog embed, as an ``EmbedSource`` raw
        /// value.
        static let embedSource = "embed.source"

        /// The result of a catalog embed, as an ``EmbedOutcome`` raw value.
        static let embedOutcome = "embed.outcome"

        /// The name of the type of the error that a failed span recorded.
        /// Never the message of the error: a message can hold content.
        static let errorType = "error.type"
    }

    /// The tier that answered a search: the value of
    /// ``AttributeKey/searchTier``.
    enum Tier: String {
        /// The retrieval tier: fused BM25, trigram and cosine signals.
        case retrieval

        /// The selection tier: a model session picks the matches.
        case selection
    }

    /// One signal that ranked a search: an element of
    /// ``AttributeKey/searchRankers``.
    enum Signal: String {
        /// The BM25 keyword signal of the retrieval tier.
        case bm25

        /// The character-trigram signal of the retrieval tier.
        case trigram

        /// The cosine signal of the retrieval tier.
        case cosine

        /// The model session of the selection tier.
        case selection
    }

    /// The ranker of a rank span: the value of ``AttributeKey/rankRanker``.
    enum Ranker: String {
        /// `HybridRanker` of FoundationModelsRanker, for the retrieval tier.
        case hybrid

        /// `SelectionTier` of FoundationModelsRanker.
        case selection
    }

    /// The path that started a catalog embed: the value of
    /// ``AttributeKey/embedSource``.
    enum EmbedSource: String {
        /// A pass of the reload embed loop of `update(items:)`.
        case reload

        /// The first-search catch-up of a searcher built synchronously.
        case firstSearch = "first_search"

        /// The one catalog embed of a `SharedCatalogEmbedding`.
        case shared

        /// The embed of `MetadataIndex.build(items:embedder:previous:onDiagnostic:)`.
        case build
    }

    /// The result of a catalog embed: the value of
    /// ``AttributeKey/embedOutcome``.
    enum EmbedOutcome: String {
        /// The embedder gave one vector for each pending entry.
        case embedded

        /// The embedder threw, or gave a count of vectors other than the
        /// count of pending entries.
        case failed
    }

    // The metrics task of the OpenTelemetry design adds the first names.
    // periphery:ignore
    /// The name of each metric that the registry records.
    ///
    /// Each name starts with ``RegistryTelemetry/namePrefix``. A dimension of
    /// a metric obeys the "no content" rule of ``RegistryTelemetry``.
    enum MetricName {}

    /// The key of each metadata value that a log record of the registry
    /// holds.
    ///
    /// Read the "no content" rule of ``RegistryTelemetry`` before you add a
    /// key. A metadata value is an identifier, a name, a count or a size.
    enum MetadataKey {
        /// The name of the `MetadataDiagnostic` case that the record reports,
        /// as a ``DiagnosticCase`` raw value.
        static let diagnosticCase = "diagnostic.case"

        /// The catalog id that a diagnostic names. An id is an identifier of
        /// the catalog, not content of an item, so it is safe.
        static let catalogId = "catalog.id"

        /// The count of candidates that a retrieval cut examined.
        static let retrievalConsidered = "retrieval.considered"

        /// The count of candidates that a retrieval cut kept.
        static let retrievalKept = "retrieval.kept"

        /// The count of catalog entries that have no embedding yet.
        static let embedPendingCount = "embed.pending_count"

        /// The count of entries in the catalog.
        static let catalogSize = "catalog.size"
    }

    /// The name of one `MetadataDiagnostic` case: the value of
    /// ``MetadataKey/diagnosticCase``. The raw value is the name of the case.
    enum DiagnosticCase: String {
        /// `MetadataDiagnostic.duplicateId(id:)`.
        case duplicateId

        /// `MetadataDiagnostic.embeddingUnavailable`.
        case embeddingUnavailable

        /// `MetadataDiagnostic.unknownSelectedId(id:)`.
        case unknownSelectedId

        /// `MetadataDiagnostic.retrievalCut(considered:kept:)`.
        case retrievalCut

        /// `MetadataDiagnostic.embedCatchUp(pending:total:)`.
        case embedCatchUp
    }

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
