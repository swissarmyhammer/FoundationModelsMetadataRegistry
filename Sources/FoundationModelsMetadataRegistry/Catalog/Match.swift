/// One retrieval or selection result over a `MetadataIndex<Item>` (plan.md
/// §4): the catalog's own id and verbatim rendered block, plus the fused
/// score and (when retrieval ran) the raw per-signal scores that produced
/// it.
public struct Match<Item: SearchableMetadata>: Sendable {
    /// The matched item's id — identical to `item.id`.
    public let id: String

    /// The matched item's rendered block, **verbatim from the catalog** —
    /// `MetadataIndex`'s stored `renderBlock()` output, never re-derived and
    /// never model output (plan.md §1 "Verbatim by construction, not by
    /// prompt").
    public let block: String

    /// A score in `[0, 1]`, whose meaning follows the tier that made the
    /// match. A retrieval match carries the fused, normalized score. A
    /// selection match carries the model's order as a reciprocal rank: the
    /// first pick scores `1.0`, the n-th pick `1 / n`.
    public let score: Double

    /// The raw per-signal scores that produced `score`, or `nil` for a
    /// selection match. No retrieval signal enters a selection, so a
    /// selection match always carries `nil`.
    public let signals: Signals?

    /// The matched catalog item itself.
    public let item: Item

    /// Creates one retrieval or selection result.
    ///
    /// - Parameters:
    ///   - id: the matched item's id.
    ///   - block: the matched item's rendered block, verbatim from the
    ///     catalog.
    ///   - score: the fused score, in `[0, 1]`.
    ///   - signals: the raw per-signal scores, or `nil` for a selection
    ///     match.
    ///   - item: the matched catalog item.
    public init(id: String, block: String, score: Double, signals: Signals?, item: Item) {
        self.id = id
        self.block = block
        self.score = score
        self.signals = signals
        self.item = item
    }
}
