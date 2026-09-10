import CryptoKit
import Foundation

/// A tokenized, two-field search index over a catalog of `SearchableMetadata` items.
///
/// Built per plan.md §1, §4 (decision #10: no persistence, no database —
/// everything lives in memory and is rebuilt wholesale from the caller's
/// items). Each item's `id` and rendered `renderBlock()` are precomputed
/// once at `init` into the data the retrieval tier scores against: one
/// FoundationModelsRanker `RankedDocument` (`id` as the primary field,
/// block as the body field — the two-field weighting `CodeContextKit`'s
/// `SearchCorpusSnapshot` established, applied to the `id`/block fields
/// plan.md §4 defines) holding the BM25/trigram statistics `HybridRanker`'s
/// per-signal scorers consume, and an embedding storage slot filled at
/// index-build/update time (plan.md §5, §8). Precomputing at `init` rather
/// than per query is what makes repeated `search()` calls cheap —
/// tokenizing/trigramming happens once per item, not once per query.
///
/// `MetadataIndex` never interprets a block's contents — it only tokenizes
/// and trigrams the opaque text `renderBlock()` returns.
public struct MetadataIndex<Item: SearchableMetadata>: Sendable {
    /// One catalog entry's precomputed search data, keyed by `id` in `entriesByID`.
    struct Entry: Sendable {
        /// The catalog item itself.
        let item: Item

        /// `item.renderBlock()`, captured once at build time.
        ///
        /// The value every `Match.block` traces back to verbatim, never
        /// re-derived (plan.md §1 "Verbatim by construction, not by
        /// prompt").
        let block: String

        /// This entry's precomputed BM25/trigram statistics, stored as one `RankedDocument`.
        ///
        /// `RankedDocument(primaryText: item.id, bodyText: block)` is the
        /// per-document input FoundationModelsRanker's `HybridRanker`
        /// scores its BM25 and trigram signals against.
        let rankedDocument: RankedDocument

        /// SHA-256 digest of `block`'s UTF-8 bytes.
        ///
        /// The "block-hash" half of the `(id, block-hash)` key
        /// `MetadataIndex.build(items:embedder:previous:onDiagnostic:)`
        /// reuses embeddings by (plan.md §8): two builds' entries for the
        /// same `id` with equal `blockHash` carry the same rendered text,
        /// so a stored embedding is still valid and re-embedding would be
        /// wasted work.
        let blockHash: Data

        /// This entry's embedding, or `nil` until it is filled in.
        ///
        /// Filled by `MetadataIndex.build(items:embedder:previous:
        /// onDiagnostic:)` (plan.md §5 "Embedding storage slots"; §8
        /// incremental re-embedding).
        let embedding: [Float]?
    }

    /// The indexed ids, in first-seen order, with duplicates already resolved per the first-wins policy.
    ///
    /// Exactly the set of ids `item(forID:)`/`block(forID:)`/etc. can
    /// resolve.
    public let ids: [String]

    /// Precomputed search data, keyed by `id`.
    let entriesByID: [String: Entry]

    /// The number of entries in this index after duplicate ids are dropped.
    public var count: Int {
        ids.count
    }

    /// Builds an in-memory index from `items`.
    ///
    /// Tokenizes and trigrams each item's `id` and rendered block exactly
    /// once. **Duplicate-id policy**: when two items share an `id`, the
    /// first one (in `items` order) wins; every later duplicate is dropped
    /// and reported via `onDiagnostic(.duplicateId(id:))` — never a crash,
    /// never silent (plan.md §4 "`id` is the join key").
    ///
    /// - Parameters:
    ///   - items: the catalog's items, in the order duplicate resolution
    ///     should prefer (first occurrence wins).
    ///   - onDiagnostic: called for every diagnostic emitted while building
    ///     this index (currently only `.duplicateId`). Defaults to logging
    ///     via `MetadataDiagnostic.log(_:)`.
    public init(
        items: [Item],
        onDiagnostic: @Sendable (MetadataDiagnostic) -> Void = { MetadataDiagnostic.log($0) }
    ) {
        var ids: [String] = []
        var entriesByID: [String: Entry] = [:]
        ids.reserveCapacity(items.count)
        entriesByID.reserveCapacity(items.count)

        for item in items {
            guard entriesByID[item.id] == nil else {
                onDiagnostic(.duplicateId(id: item.id))
                continue
            }
            entriesByID[item.id] = Self.buildEntry(item: item)
            ids.append(item.id)
        }

        self.ids = ids
        self.entriesByID = entriesByID
    }

    /// Precomputes one catalog item's search data.
    ///
    /// Renders the item's block once, then precomputes its
    /// `RankedDocument` (tokenizing/trigramming `item.id` and the block —
    /// FoundationModelsRanker's per-document BM25/trigram statistics) and
    /// the block's content hash.
    ///
    /// - Parameter item: the catalog item to precompute an `Entry` for.
    /// - Returns: the precomputed entry, ready to store under `item.id`.
    private static func buildEntry(item: Item) -> Entry {
        let block = item.renderBlock()
        return Entry(
            item: item,
            block: block,
            rankedDocument: RankedDocument(primaryText: item.id, bodyText: block),
            blockHash: Data(SHA256.hash(data: Data(block.utf8))),
            embedding: nil
        )
    }

    // MARK: - Lookup

    /// Looks up one precomputed field of the `Entry` stored under `id`.
    ///
    /// Returns `nil` if `id` isn't indexed (never indexed, or dropped as a
    /// duplicate). Every public lookup method below is a one-line
    /// specialization of this accessor over a single `Entry` key path —
    /// the copy-paste `entriesByID[id]?.field` pattern lived here once per
    /// lookup before being unified.
    ///
    /// - Parameters:
    ///   - forID: the id to look up.
    ///   - keyPath: the `Entry` field to project out.
    /// - Returns: the projected field, or `nil` if `id` isn't indexed.
    private func value<T>(forID id: String, keyPath: KeyPath<Entry, T>) -> T? {
        entriesByID[id]?[keyPath: keyPath]
    }

    /// The catalog item stored under `id`.
    ///
    /// Returns `nil` if `id` isn't indexed (never indexed, or dropped as a
    /// duplicate).
    ///
    /// - Parameter forID: the id to look up.
    /// - Returns: the catalog item, or `nil` if `id` isn't indexed.
    public func item(forID id: String) -> Item? {
        value(forID: id, keyPath: \.item)
    }

    /// The rendered block stored under `id`, verbatim from its build-time render.
    ///
    /// Returns `nil` if `id` isn't indexed.
    ///
    /// - Parameter forID: the id to look up.
    /// - Returns: the rendered block, or `nil` if `id` isn't indexed.
    public func block(forID id: String) -> String? {
        value(forID: id, keyPath: \.block)
    }

    /// The precomputed `RankedDocument` stored under `id`.
    ///
    /// This is the BM25/trigram statistics FoundationModelsRanker's
    /// `HybridRanker` scores this entry with (`id` as its primary field,
    /// the rendered block as its body field).
    ///
    /// Returns `nil` if `id` isn't indexed.
    ///
    /// - Parameter forID: the id to look up.
    /// - Returns: the precomputed per-document statistics, or `nil` if
    ///   `id` isn't indexed.
    public func rankedDocument(forID id: String) -> RankedDocument? {
        value(forID: id, keyPath: \.rankedDocument)
    }

    /// The embedding stored for `id`, or `nil` if `id` isn't indexed or not yet embedded.
    ///
    /// `nil` until `MetadataIndex.build(items:embedder:previous:
    /// onDiagnostic:)`, or a `MetadataSearcher` catch-up merging through
    /// `mergingEmbeddings(ids:vectors:embeddedFrom:into:)`, fills this
    /// storage slot.
    ///
    /// - Parameter forID: the id to look up.
    /// - Returns: the stored embedding, or `nil` if `id` isn't indexed or
    ///   not yet embedded.
    public func embedding(forID id: String) -> [Float]? {
        value(forID: id, keyPath: \.embedding) ?? nil
    }
}
