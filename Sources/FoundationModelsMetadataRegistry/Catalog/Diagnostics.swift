import os

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
    case retrievalCut(considered: Int, kept: Int)

    /// Incremental re-embedding (plan.md §8) is still catching up: `pending`
    /// of `total` catalog items have no embedding yet.
    case embedCatchUp(pending: Int, total: Int)

    /// Where the default `onDiagnostic` conformer logs.
    private static let logger = Logger(subsystem: "FoundationModelsMetadataRegistry", category: "MetadataDiagnostic")

    /// The default `onDiagnostic` conformer every tier falls back to: logs
    /// `diagnostic` via `Self.logger` rather than doing nothing, so
    /// degradation is never silent even when a caller supplies no callback
    /// of its own.
    ///
    /// - Parameter diagnostic: the diagnostic to log.
    public static func log(_ diagnostic: MetadataDiagnostic) {
        switch diagnostic {
        case .duplicateId(let id):
            logger.notice(
                "duplicate id \"\(id, privacy: .public)\" in catalog; first occurrence kept, duplicate dropped."
            )
        case .embeddingUnavailable:
            logger.notice(
                "no embedder configured or catalog not yet embedded; results are keyword-only (BM25 + trigram)."
            )
        case .unknownSelectedId(let id):
            logger.notice("selection model returned unknown id \"\(id, privacy: .public)\"; ignored.")
        case .retrievalCut(let considered, let kept):
            logger.notice(
                "retrieval cut candidates from \(considered, privacy: .public) to \(kept, privacy: .public) before selection."
            )
        case .embedCatchUp(let pending, let total):
            logger.notice("embedding catch-up: \(pending, privacy: .public)/\(total, privacy: .public) item(s) pending.")
        }
    }
}
