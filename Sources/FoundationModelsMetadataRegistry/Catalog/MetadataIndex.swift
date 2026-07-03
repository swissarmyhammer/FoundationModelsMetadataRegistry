/// An in-memory, tokenized two-field search index over a catalog of
/// `SearchableMetadata` items (plan.md §1, §4; decision #10: no persistence,
/// no database — everything lives in memory and is rebuilt wholesale from
/// the caller's items).
///
/// Each item's `id` and rendered `renderBlock()` are precomputed once at
/// `init` into the data the retrieval tier scores against: a BM25
/// field-weighted term frequency (`id` at `BM25.idFieldWeight`, block at
/// `BM25.blockFieldWeight` — the `symbol_path`/body treatment
/// `CodeContextKit`'s `SearchCorpusSnapshot` established, ported here for
/// the `id`/block fields plan.md §4 defines), a trigram set per field, and
/// an embedding storage slot a future task fills at index-build/update time
/// (plan.md §5, §8). Precomputing at `init` rather than per query is what
/// makes repeated `search()` calls cheap — tokenizing/trigramming happens
/// once per item, not once per query.
///
/// `MetadataIndex` never interprets a block's contents — it only tokenizes
/// and trigrams the opaque text `renderBlock()` returns.
public struct MetadataIndex<Item: SearchableMetadata>: Sendable {
    /// One catalog entry's precomputed search data, keyed by `id` in
    /// `entriesById`.
    private struct Entry: Sendable {
        /// The catalog item itself.
        let item: Item

        /// `item.renderBlock()`, captured once at build time — the value
        /// every `Match.block` traces back to verbatim, never re-derived
        /// (plan.md §1 "Verbatim by construction, not by prompt").
        let block: String

        /// The field-weighted term frequency across both fields: `id`'s
        /// tokens weighted `BM25.idFieldWeight`, `block`'s tokens weighted
        /// `BM25.blockFieldWeight` — the `tf` term `BM25Corpus.score` needs.
        let weightedTermFrequency: [String: Double]

        /// `Set(weightedTermFrequency.keys)` — this entry's distinct term
        /// set, cached separately so `BM25Corpus.init(queryTokens:documents:)`
        /// doesn't rebuild it from `weightedTermFrequency` on every query.
        let termSet: Set<String>

        /// This entry's unweighted token count across both fields — the
        /// `|D|` `BM25Corpus.score` needs for length normalization.
        let documentLength: Int

        /// This entry's canonical trigram set for `item.id`.
        let idTrigramSet: Set<String>

        /// This entry's canonical trigram set for `block`.
        let blockTrigramSet: Set<String>

        /// This entry's embedding, or `nil` until a future embedding task
        /// fills it (plan.md §5 "Embedding storage slots"; §8 incremental
        /// re-embedding).
        let embedding: [Float]?
    }

    /// Every indexed id, in first-seen order — duplicates already resolved
    /// by the first-wins policy, so this is exactly the set of ids
    /// `item(forId:)`/`block(forId:)`/etc. can resolve.
    public let ids: [String]

    /// Precomputed search data, keyed by `id`.
    private let entriesById: [String: Entry]

    /// The number of entries in this index (after duplicate ids are
    /// dropped).
    public var count: Int { ids.count }

    /// Builds an in-memory index from `items`, tokenizing and trigramming
    /// each item's `id` and rendered block exactly once.
    ///
    /// **Duplicate-id policy**: when two items share an `id`, the first one
    /// (in `items` order) wins; every later duplicate is dropped and
    /// reported via `onDiagnostic(.duplicateId(id:))` — never a crash, never
    /// silent (plan.md §4 "`id` is the join key").
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
        var entriesById: [String: Entry] = [:]
        ids.reserveCapacity(items.count)
        entriesById.reserveCapacity(items.count)

        for item in items {
            guard entriesById[item.id] == nil else {
                onDiagnostic(.duplicateId(id: item.id))
                continue
            }
            entriesById[item.id] = Self.buildEntry(item: item)
            ids.append(item.id)
        }

        self.ids = ids
        self.entriesById = entriesById
    }

    /// Tokenizes `item.id` and its rendered block, builds the field-weighted
    /// term frequency and term set, and the per-field trigram sets.
    ///
    /// - Parameter item: the catalog item to precompute an `Entry` for.
    /// - Returns: the precomputed entry, ready to store under `item.id`.
    private static func buildEntry(item: Item) -> Entry {
        let block = item.renderBlock()
        let idTokens = Tokenizer.tokenize(text: item.id)
        let blockTokens = Tokenizer.tokenize(text: block)

        var weightedTermFrequency: [String: Double] = [:]
        for token in idTokens {
            weightedTermFrequency[token, default: 0.0] += BM25.idFieldWeight
        }
        for token in blockTokens {
            weightedTermFrequency[token, default: 0.0] += BM25.blockFieldWeight
        }

        return Entry(
            item: item,
            block: block,
            weightedTermFrequency: weightedTermFrequency,
            termSet: Set(weightedTermFrequency.keys),
            documentLength: idTokens.count + blockTokens.count,
            idTrigramSet: Trigram.canonicalTrigramSet(text: item.id),
            blockTrigramSet: Trigram.canonicalTrigramSet(text: block),
            embedding: nil
        )
    }

    // MARK: - Lookup

    /// The catalog item stored under `id`, or `nil` if `id` isn't indexed
    /// (never indexed, or dropped as a duplicate).
    public func item(forId id: String) -> Item? {
        entriesById[id]?.item
    }

    /// The rendered block stored under `id`, verbatim from `renderBlock()`
    /// at build time — or `nil` if `id` isn't indexed.
    public func block(forId id: String) -> String? {
        entriesById[id]?.block
    }

    /// The field-weighted BM25 term frequency for `id`, or `nil` if `id`
    /// isn't indexed.
    public func weightedTermFrequency(forId id: String) -> [String: Double]? {
        entriesById[id]?.weightedTermFrequency
    }

    /// The distinct term set for `id`, or `nil` if `id` isn't indexed.
    public func termSet(forId id: String) -> Set<String>? {
        entriesById[id]?.termSet
    }

    /// The unweighted token count across both fields for `id`, or `nil` if
    /// `id` isn't indexed.
    public func documentLength(forId id: String) -> Int? {
        entriesById[id]?.documentLength
    }

    /// The canonical `id`-field trigram set for `id`, or `nil` if `id` isn't
    /// indexed.
    public func idTrigramSet(forId id: String) -> Set<String>? {
        entriesById[id]?.idTrigramSet
    }

    /// The canonical block-field trigram set for `id`, or `nil` if `id`
    /// isn't indexed.
    public func blockTrigramSet(forId id: String) -> Set<String>? {
        entriesById[id]?.blockTrigramSet
    }

    /// The embedding stored for `id` — `nil` until a future embedding task
    /// fills this storage slot, or if `id` isn't indexed.
    public func embedding(forId id: String) -> [Float]? {
        entriesById[id]?.embedding ?? nil
    }
}
