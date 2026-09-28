import Logging

/// The single shared diagnostics surface every tier of
/// `FoundationModelsMetadataRegistry` emits through (plan.md §1 "Graceful
/// degradation ... every degradation is reported, never silent"). Generalizes
/// Multitool's `Librarian.PrefilterCutEvent` / `onPrefilterCut` pattern
/// (plan.md §2) into one payload-carrying enum delivered via a single
/// `onDiagnostic: @Sendable (MetadataDiagnostic) -> Void` callback, so later
/// tasks add cases here rather than inventing parallel diagnostic
/// mechanisms.
public enum MetadataDiagnostic: Sendable, Equatable {
    /// Maps one of FoundationModelsRanker's neutral `RankDiagnostic` cases
    /// into the same-named case of this channel — how `MetadataSearcher`
    /// forwards the selection tier's diagnostics (now emitted by Ranker's
    /// `SelectionTier`) through its existing `onDiagnostic` callback
    /// unchanged for consumers.
    ///
    /// - Parameter diagnostic: the Ranker diagnostic to map.
    init(_ diagnostic: RankDiagnostic) {
        switch diagnostic {
        case .retrievalCut(let considered, let kept):
            self = .retrievalCut(considered: considered, kept: kept)
        case .unknownSelectedId(let id):
            self = .unknownSelectedId(id: id)
        case .embeddingUnavailable:
            self = .embeddingUnavailable
        }
    }

    /// A catalog item's `id` collided with one already indexed. The
    /// duplicate is dropped and the first-seen item is kept —
    /// `MetadataIndex`'s duplicate-id policy: never a crash, never silent.
    case duplicateId(id: String)

    /// No embedder is configured (or none of the catalog's items carry an
    /// embedding yet), so cosine ranking was skipped and results degraded to
    /// keyword-only (BM25 + trigram).
    case embeddingUnavailable

    /// The selection model returned an id absent from the current candidate
    /// set. Structurally unreachable given grammar-constrained output
    /// (plan.md §6), but defended against anyway.
    case unknownSelectedId(id: String)

    /// The over-budget capacity fallback (plan.md §6) cut the candidate set
    /// from `considered` items down to `kept` before seeding a one-off
    /// selection session — the `onPrefilterCut` pattern generalized to
    /// ranked retrieval.
    ///
    /// Never reported. FoundationModelsRanker's `SelectionTier` stopped
    /// cutting candidates: over budget it divides the catalog into runs and
    /// gives every run one prompt, so every id reaches a prompt. The case
    /// stays because `RankDiagnostic` keeps its own, and `init(_:)` maps
    /// every case of it.
    case retrievalCut(considered: Int, kept: Int)

    /// Incremental re-embedding (plan.md §8) is still catching up: `pending`
    /// of `total` catalog items have no embedding yet.
    case embedCatchUp(pending: Int, total: Int)

    /// The default `onDiagnostic` conformer every tier falls back to: logs
    /// `diagnostic` rather than doing nothing, so degradation is never silent
    /// even when a caller supplies no callback of its own.
    ///
    /// Writes one `.notice` record through the swift-log logger of the
    /// registry (``RegistryTelemetry/loggerLabel``). Each call makes a new
    /// logger through ``RegistryTelemetry/makeLogger()``, so the record goes
    /// to the log backend that the host bootstrapped, also when the host
    /// bootstrapped it after the first call. The metadata of the record holds
    /// the case name and each associated value under its own
    /// ``RegistryTelemetry/MetadataKey``, so a backend can query a value
    /// without a parse of the message. The record holds ids and counts only,
    /// never content of an item or of a query.
    ///
    /// - Parameter diagnostic: the diagnostic to log.
    public static func log(_ diagnostic: MetadataDiagnostic) {
        let record = diagnostic.logRecord
        RegistryTelemetry.makeLogger().notice(record.message, metadata: record.metadata)
    }

    /// The log record that ``log(_:)`` writes for one diagnostic.
    private struct LogRecord {
        /// The name of the case that the record reports.
        let diagnosticCase: RegistryTelemetry.DiagnosticCase

        /// The message of the record. It holds ids and counts only.
        let message: Logger.Message

        /// The metadata values of the record other than the case name.
        let values: Logger.Metadata

        /// The metadata of the record: ``values``, and the case name under
        /// ``RegistryTelemetry/MetadataKey/diagnosticCase``.
        var metadata: Logger.Metadata {
            values.merging([RegistryTelemetry.MetadataKey.diagnosticCase: .string(diagnosticCase.rawValue)]) { $1 }
        }
    }

    /// The log record that ``log(_:)`` writes for this diagnostic.
    private var logRecord: LogRecord {
        typealias Key = RegistryTelemetry.MetadataKey
        switch self {
        case .duplicateId(let id):
            return LogRecord(
                diagnosticCase: .duplicateId,
                message: "duplicate id \"\(id)\" in catalog; first occurrence kept, duplicate dropped.",
                values: [Key.catalogId: .string(id)],
            )
        case .embeddingUnavailable:
            return LogRecord(
                diagnosticCase: .embeddingUnavailable,
                message: """
                no embedder configured or catalog not yet embedded; \
                results are keyword-only (BM25 + trigram).
                """,
                values: [:],
            )
        case .unknownSelectedId(let id):
            return LogRecord(
                diagnosticCase: .unknownSelectedId,
                message: "selection model returned unknown id \"\(id)\"; ignored.",
                values: [Key.catalogId: .string(id)],
            )
        case .retrievalCut(let considered, let kept):
            return LogRecord(
                diagnosticCase: .retrievalCut,
                message: "retrieval cut candidates from \(considered) to \(kept) before selection.",
                values: [
                    Key.retrievalConsidered: .stringConvertible(considered),
                    Key.retrievalKept: .stringConvertible(kept),
                ],
            )
        case .embedCatchUp(let pending, let total):
            return LogRecord(
                diagnosticCase: .embedCatchUp,
                message: "embedding catch-up: \(pending)/\(total) item(s) pending.",
                values: [
                    Key.embedPendingCount: .stringConvertible(pending),
                    Key.catalogSize: .stringConvertible(total),
                ],
            )
        }
    }
}
