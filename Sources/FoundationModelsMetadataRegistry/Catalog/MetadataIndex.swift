import CryptoKit
import Foundation

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

        /// SHA-256 digest of `block`'s UTF-8 bytes — the "block-hash" half of
        /// the `(id, block-hash)` key `MetadataIndex.build(items:embedder:
        /// previous:onDiagnostic:)` reuses embeddings by (plan.md §8): two
        /// builds' entries for the same `id` with equal `blockHash` carry the
        /// same rendered text, so a stored embedding is still valid and
        /// re-embedding would be wasted work.
        let blockHash: Data

        /// This entry's embedding, or `nil` until `MetadataIndex.build(items:
        /// embedder:previous:onDiagnostic:)` fills it (plan.md §5 "Embedding
        /// storage slots"; §8 incremental re-embedding).
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
            blockHash: Self.hash(block: block),
            embedding: nil
        )
    }

    /// SHA-256 digest of `block`'s UTF-8 bytes — see `Entry.blockHash`.
    private static func hash(block: String) -> Data {
        Data(SHA256.hash(data: Data(block.utf8)))
    }

    // MARK: - Lookup

    /// Looks up one precomputed field of the `Entry` stored under `id`, or
    /// `nil` if `id` isn't indexed (never indexed, or dropped as a
    /// duplicate). Every public lookup method below is a one-line
    /// specialization of this accessor over a single `Entry` key path —
    /// the copy-paste `entriesById[id]?.field` pattern lived here eight
    /// times before being unified.
    private func value<T>(forId id: String, keyPath: KeyPath<Entry, T>) -> T? {
        entriesById[id]?[keyPath: keyPath]
    }

    /// The catalog item stored under `id`, or `nil` if `id` isn't indexed
    /// (never indexed, or dropped as a duplicate).
    public func item(forId id: String) -> Item? {
        value(forId: id, keyPath: \.item)
    }

    /// The rendered block stored under `id`, verbatim from `renderBlock()`
    /// at build time — or `nil` if `id` isn't indexed.
    public func block(forId id: String) -> String? {
        value(forId: id, keyPath: \.block)
    }

    /// The field-weighted BM25 term frequency for `id`, or `nil` if `id`
    /// isn't indexed.
    public func weightedTermFrequency(forId id: String) -> [String: Double]? {
        value(forId: id, keyPath: \.weightedTermFrequency)
    }

    /// The distinct term set for `id`, or `nil` if `id` isn't indexed.
    public func termSet(forId id: String) -> Set<String>? {
        value(forId: id, keyPath: \.termSet)
    }

    /// The unweighted token count across both fields for `id`, or `nil` if
    /// `id` isn't indexed.
    public func documentLength(forId id: String) -> Int? {
        value(forId: id, keyPath: \.documentLength)
    }

    /// The canonical `id`-field trigram set for `id`, or `nil` if `id` isn't
    /// indexed.
    public func idTrigramSet(forId id: String) -> Set<String>? {
        value(forId: id, keyPath: \.idTrigramSet)
    }

    /// The canonical block-field trigram set for `id`, or `nil` if `id`
    /// isn't indexed.
    public func blockTrigramSet(forId id: String) -> Set<String>? {
        value(forId: id, keyPath: \.blockTrigramSet)
    }

    /// The embedding stored for `id` — `nil` until `MetadataIndex.build(items:
    /// embedder:previous:onDiagnostic:)` fills this storage slot, or if `id`
    /// isn't indexed.
    public func embedding(forId id: String) -> [Float]? {
        value(forId: id, keyPath: \.embedding) ?? nil
    }

    // MARK: - Embedding at index-build/update time

    /// Builds an in-memory index from `items` the same way `init(items:
    /// onDiagnostic:)` does (tokenizing, trigramming — always synchronous),
    /// then embeds each item's rendered block through `embedder` (plan.md
    /// §5, §8) — embedding is the one part of index-build that's async,
    /// because it's the one part that may call out to a model.
    ///
    /// **Hash-keyed incremental re-embedding**: an item whose `id` and
    /// rendered-block `Entry.blockHash` both match `previous`'s, *and* whose
    /// `previous` entry actually carries a non-`nil` embedding, reuses that
    /// stored embedding rather than re-embedding unchanged text. A hash match
    /// against a `nil` previous embedding (no embedder was configured, or a
    /// transient embed failure, at that prior build) is **not** reused —
    /// the item is queued for embedding again here, exactly like a brand-new
    /// item, so it catches up as soon as an embedder is actually available
    /// instead of staying cosine-blind forever just because its text never
    /// changed (plan.md §8 "embed catch-up"). `embedder.embed(_:)` is called
    /// with exactly the new-or-changed-or-never-embedded blocks, batched
    /// into a single call, never once per item. This is what makes
    /// `update(items:)` (plan.md §8, a later task) cheap to call on every
    /// upstream change notification: unchanged, already-embedded items cost
    /// nothing here.
    ///
    /// - Parameters:
    ///   - items: same as `init(items:onDiagnostic:)`.
    ///   - embedder: the embedder to embed new-or-changed blocks with. `nil`
    ///     leaves every embedding `nil` (identical to `init(items:
    ///     onDiagnostic:)`) — callers report `.embeddingUnavailable`
    ///     themselves (plan.md §5); this initializer never does, since it
    ///     has no `onDiagnostic` case reserved for "no embedder configured".
    ///   - previous: the prior build of this index, if any, to reuse
    ///     embeddings from for unchanged `(id, block-hash)` pairs. Defaults
    ///     to `nil` (nothing to reuse — every item is embedded fresh).
    ///   - onDiagnostic: forwarded to `init(items:onDiagnostic:)` for
    ///     duplicate-id reporting.
    /// - Returns: the built index, with embeddings populated wherever
    ///   `embedder` was configured and ran successfully. If `embedder.embed(_:)`
    ///   throws, every item that would have been (re-)embedded this call is
    ///   left with whatever embedding it already had (`nil` for a new item) —
    ///   graceful degradation, matching plan.md §5's "no embedder configured"
    ///   handling rather than propagating a transient embedding failure.
    public static func build(
        items: [Item],
        embedder: (any TextEmbedding)?,
        previous: MetadataIndex<Item>? = nil,
        onDiagnostic: @Sendable (MetadataDiagnostic) -> Void = { MetadataDiagnostic.log($0) }
    ) async -> MetadataIndex<Item> {
        let baseline = MetadataIndex(items: items, onDiagnostic: onDiagnostic)
        guard let embedder else { return baseline }

        var entriesById = baseline.entriesById
        var idsToEmbed: [String] = []
        var textsToEmbed: [String] = []

        for id in baseline.ids {
            guard let entry = entriesById[id] else { continue }
            // Reusing `previousEntry.embedding` is only valid when there is
            // an actual embedding to reuse: a `nil` embedding (no embedder
            // configured, or a transient embed failure, at the prior build)
            // must never be copied forward as if it were a cached result —
            // that would leave the item cosine-blind forever even once an
            // embedder becomes available, defeating "embed catch-up"
            // (plan.md §8). A hash match with no prior embedding still
            // queues the item for embedding below, same as a brand-new item.
            if let previousEntry = previous?.entriesById[id],
                previousEntry.blockHash == entry.blockHash,
                let previousEmbedding = previousEntry.embedding {
                entriesById[id] = Self.withEmbedding(previousEmbedding, replacing: entry)
            } else {
                idsToEmbed.append(id)
                textsToEmbed.append(entry.block)
            }
        }

        if !idsToEmbed.isEmpty, let vectors = try? await embedder.embed(textsToEmbed), vectors.count == idsToEmbed.count {
            for (id, vector) in zip(idsToEmbed, vectors) {
                guard let entry = entriesById[id] else { continue }
                entriesById[id] = Self.withEmbedding(vector, replacing: entry)
            }
        }

        return MetadataIndex(ids: baseline.ids, entriesById: entriesById)
    }

    /// Returns a copy of `entry` with its `embedding` replaced by `embedding`
    /// — every other field carried over unchanged. `Entry`'s fields are all
    /// `let`, so replacing one means rebuilding the whole value; this is the
    /// single place that does so; both `build`'s reuse and freshly-embedded
    /// branches go through it.
    private static func withEmbedding(_ embedding: [Float]?, replacing entry: Entry) -> Entry {
        Entry(
            item: entry.item,
            block: entry.block,
            weightedTermFrequency: entry.weightedTermFrequency,
            termSet: entry.termSet,
            documentLength: entry.documentLength,
            idTrigramSet: entry.idTrigramSet,
            blockTrigramSet: entry.blockTrigramSet,
            blockHash: entry.blockHash,
            embedding: embedding
        )
    }

    /// Reconstructs an index directly from already-precomputed `ids` and
    /// `entriesById` — the internal counterpart to `init(items:onDiagnostic:)`
    /// that `build(items:embedder:previous:onDiagnostic:)` uses to return a
    /// new index after filling in embeddings, without re-tokenizing or
    /// re-trigramming anything `baseline` already computed.
    private init(ids: [String], entriesById: [String: Entry]) {
        self.ids = ids
        self.entriesById = entriesById
    }
}
