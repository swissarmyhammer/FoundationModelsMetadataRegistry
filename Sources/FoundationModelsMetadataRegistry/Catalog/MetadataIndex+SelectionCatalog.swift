/// Conforms `MetadataIndex` to FoundationModelsRanker's `SelectionCatalog`.
///
/// `SelectionCatalog` is the narrow contract Ranker's `SelectionTier` drives
/// its assembled prefix and verbatim result lookup through (that protocol was
/// written to generalize exactly this type). `ids` is satisfied by the stored
/// property above and `block(forID:)` by this index's existing accessor; only
/// `summaryBlock(forID:)` needs a dedicated implementation here.
extension MetadataIndex: SelectionCatalog {
    /// A (typically shorter) summary of `id`'s item, from `SearchableMetadata.renderSummaryBlock()`.
    ///
    /// Used to seed the selection tier's assembled prefix instead of the
    /// full block (plan.md §4).
    ///
    /// - Parameter id: the id to look up.
    /// - Returns: the id's summary text, or `nil` if `id` isn't indexed.
    public func summaryBlock(forID id: String) -> String? {
        item(forID: id)?.renderSummaryBlock()
    }
}
