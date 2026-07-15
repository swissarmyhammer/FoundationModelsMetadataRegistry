import CryptoKit
import Foundation

/// A tokenized, two-field search index over a catalog of `SearchableMetadata` items.
///
/// Built per plan.md §1, §4 (decision #10: no persistence, no database —
/// everything lives in memory and is rebuilt wholesale from the caller's
/// items). Each item's `id` and rendered `renderBlock()` are precomputed
/// once at `init` into the data the retrieval tier scores against: a BM25
/// field-weighted term frequency (`id` at `BM25.primaryFieldWeight`, block at
/// `BM25.bodyFieldWeight` — the `symbol_path`/body treatment
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
    /// One catalog entry's precomputed search data, keyed by `id` in `entriesByID`.
    private struct Entry: Sendable {
        /// The catalog item itself.
        let item: Item

        /// `item.renderBlock()`, captured once at build time.
        ///
        /// The value every `Match.block` traces back to verbatim, never
        /// re-derived (plan.md §1 "Verbatim by construction, not by
        /// prompt").
        let block: String

        /// The field-weighted term frequency across both fields.
        ///
        /// `id`'s tokens are weighted `BM25.primaryFieldWeight`, `block`'s
        /// tokens weighted `BM25.bodyFieldWeight` — the `tf` term
        /// `BM25Corpus.score` needs.
        let weightedTermFrequency: [String: Double]

        /// This entry's distinct term set: `Set(weightedTermFrequency.keys)`.
        ///
        /// Cached separately so `BM25Corpus.init(queryTokens:documents:)`
        /// doesn't rebuild it from `weightedTermFrequency` on every query.
        let termSet: Set<String>

        /// This entry's unweighted token count across both fields.
        ///
        /// The `|D|` value `BM25Corpus.score` needs for length
        /// normalization.
        let documentLength: Int

        /// This entry's canonical trigram set for `item.id`.
        let idTrigramSet: Set<String>

        /// This entry's canonical trigram set for `block`.
        let blockTrigramSet: Set<String>

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
    private let entriesByID: [String: Entry]

    /// The number of entries in this index after duplicate ids are dropped.
    public var count: Int { ids.count }

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
    /// Tokenizes `item.id` and its rendered block, then builds the
    /// field-weighted term frequency and term set, and the per-field
    /// trigram sets.
    ///
    /// - Parameter item: the catalog item to precompute an `Entry` for.
    /// - Returns: the precomputed entry, ready to store under `item.id`.
    private static func buildEntry(item: Item) -> Entry {
        let block = item.renderBlock()
        let idTokens = Tokenizer.tokenize(text: item.id)
        let blockTokens = Tokenizer.tokenize(text: block)

        var weightedTermFrequency: [String: Double] = [:]
        for token in idTokens {
            weightedTermFrequency[token, default: 0.0] += BM25.primaryFieldWeight
        }
        for token in blockTokens {
            weightedTermFrequency[token, default: 0.0] += BM25.bodyFieldWeight
        }

        return Entry(
            item: item,
            block: block,
            weightedTermFrequency: weightedTermFrequency,
            termSet: Set(weightedTermFrequency.keys),
            documentLength: idTokens.count + blockTokens.count,
            idTrigramSet: Trigram.canonicalTrigramSet(text: item.id),
            blockTrigramSet: Trigram.canonicalTrigramSet(text: block),
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
    /// the copy-paste `entriesByID[id]?.field` pattern lived here eight
    /// times before being unified.
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

    /// The field-weighted BM25 term frequency for `id`, or `nil` if `id` isn't indexed.
    ///
    /// - Parameter forID: the id to look up.
    /// - Returns: the field-weighted term frequency, or `nil` if `id`
    ///   isn't indexed.
    public func weightedTermFrequency(forID id: String) -> [String: Double]? {
        value(forID: id, keyPath: \.weightedTermFrequency)
    }

    /// The distinct term set for `id`, or `nil` if `id` isn't indexed.
    ///
    /// - Parameter forID: the id to look up.
    /// - Returns: the distinct term set, or `nil` if `id` isn't indexed.
    public func termSet(forID id: String) -> Set<String>? {
        value(forID: id, keyPath: \.termSet)
    }

    /// The unweighted token count across both fields for `id`, or `nil` if `id` isn't indexed.
    ///
    /// - Parameter forID: the id to look up.
    /// - Returns: the unweighted token count, or `nil` if `id` isn't
    ///   indexed.
    public func documentLength(forID id: String) -> Int? {
        value(forID: id, keyPath: \.documentLength)
    }

    /// The canonical `id`-field trigram set for `id`, or `nil` if `id` isn't indexed.
    ///
    /// - Parameter forID: the id to look up.
    /// - Returns: the canonical `id`-field trigram set, or `nil` if `id`
    ///   isn't indexed.
    public func idTrigramSet(forID id: String) -> Set<String>? {
        value(forID: id, keyPath: \.idTrigramSet)
    }

    /// The canonical block-field trigram set for `id`, or `nil` if `id` isn't indexed.
    ///
    /// - Parameter forID: the id to look up.
    /// - Returns: the canonical block-field trigram set, or `nil` if `id`
    ///   isn't indexed.
    public func blockTrigramSet(forID id: String) -> Set<String>? {
        value(forID: id, keyPath: \.blockTrigramSet)
    }

    /// The embedding stored for `id`, or `nil` if `id` isn't indexed or not yet embedded.
    ///
    /// `nil` until `MetadataIndex.build(items:embedder:previous:
    /// onDiagnostic:)` fills this storage slot.
    ///
    /// - Parameter forID: the id to look up.
    /// - Returns: the stored embedding, or `nil` if `id` isn't indexed or
    ///   not yet embedded.
    public func embedding(forID id: String) -> [Float]? {
        value(forID: id, keyPath: \.embedding) ?? nil
    }

    // MARK: - Embedding at index-build/update time

    /// Builds an in-memory index from `items` with optional async embedding.
    ///
    /// Indexes `items` the same way `init(items:onDiagnostic:)` does
    /// (tokenizing, trigramming — always synchronous), then embeds each
    /// item's rendered block through `embedder` (plan.md §5, §8) —
    /// embedding is the one part of index-build that's async, because
    /// it's the one part that may call out to a model.
    ///
    /// **Hash-keyed incremental re-embedding**: an item whose `id` and
    /// rendered-block `Entry.blockHash` both match `previous`'s, *and*
    /// whose `previous` entry actually carries a non-`nil` embedding,
    /// reuses that stored embedding rather than re-embedding unchanged
    /// text. A hash match against a `nil` previous embedding (no embedder
    /// was configured, or a transient embed failure, at that prior build)
    /// is **not** reused — the item is queued for embedding again here,
    /// exactly like a brand-new item, so it catches up as soon as an
    /// embedder is actually available instead of staying cosine-blind
    /// forever just because its text never changed (plan.md §8 "embed
    /// catch-up"). `embedder.embed(_:)` is called with exactly the
    /// new-or-changed-or-never-embedded blocks, batched into a single
    /// call, never once per item. This is what makes `update(items:)`
    /// (plan.md §8, a later task) cheap to call on every upstream change
    /// notification: unchanged, already-embedded items cost nothing here.
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
        let (baseline, pendingEmbedIDs, textsToEmbed) = incrementalBaseline(items: items, previous: previous, onDiagnostic: onDiagnostic)
        guard let embedder, !pendingEmbedIDs.isEmpty,
            let vectors = try? await embedder.embed(textsToEmbed), vectors.count == pendingEmbedIDs.count
        else {
            return baseline
        }
        return mergingEmbeddings(ids: pendingEmbedIDs, vectors: vectors, embeddedFrom: baseline, into: baseline)
    }

    /// The synchronous, hash-guarded half of index-build/update: indexes
    /// `items` exactly like `init(items:onDiagnostic:)` (tokenizing,
    /// trigramming), then reuses `previous`'s stored embedding for every
    /// item whose `id` and rendered-block hash both match a `previous` entry
    /// that actually carries a non-`nil` embedding.
    ///
    /// Factored out of `build(items:embedder:previous:onDiagnostic:)` so
    /// `MetadataSearcher.update(items:)` (plan.md §8, hot reload) can assign
    /// the returned baseline to its actor-isolated `index` *before* awaiting
    /// an embedder call with the returned `pendingEmbedIDs`/`textsToEmbed` —
    /// actor reentrancy across that later `await` is what lets a concurrent
    /// `search(intent:limit:)` see this rebuilt baseline and serve
    /// keyword-only results for the still-pending items in the interim,
    /// rather than blocking behind the whole re-embed.
    ///
    /// - Parameters:
    ///   - items: the catalog's items, in first-seen-wins duplicate-id order.
    ///   - previous: the prior build of this index, if any, to reuse
    ///     embeddings from for unchanged `(id, block-hash)` pairs.
    ///   - onDiagnostic: forwarded to `init(items:onDiagnostic:)` for
    ///     duplicate-id reporting.
    /// - Returns: the baseline index (embeddings carried over wherever reuse
    ///   applied, `nil` everywhere else), plus the ids and matching texts
    ///   still needing an embedder call, positionally aligned.
    static func incrementalBaseline(
        items: [Item],
        previous: MetadataIndex<Item>?,
        onDiagnostic: @Sendable (MetadataDiagnostic) -> Void
    ) -> (baseline: MetadataIndex<Item>, pendingEmbedIDs: [String], textsToEmbed: [String]) {
        let baseline = MetadataIndex(items: items, onDiagnostic: onDiagnostic)
        var entriesByID = baseline.entriesByID
        var pendingEmbedIDs: [String] = []
        var textsToEmbed: [String] = []

        for id in baseline.ids {
            guard let entry = entriesByID[id] else { continue }
            // Reusing `previousEntry.embedding` is only valid when there is
            // an actual embedding to reuse: a `nil` embedding (no embedder
            // configured, or a transient embed failure, at the prior build)
            // must never be copied forward as if it were a cached result —
            // that would leave the item cosine-blind forever even once an
            // embedder becomes available, defeating "embed catch-up"
            // (plan.md §8). A hash match with no prior embedding still
            // queues the item for embedding below, same as a brand-new item.
            if let previousEntry = previous?.entriesByID[id],
                previousEntry.blockHash == entry.blockHash,
                let previousEmbedding = previousEntry.embedding {
                entriesByID[id] = Self.withEmbedding(previousEmbedding, replacing: entry)
            } else {
                pendingEmbedIDs.append(id)
                textsToEmbed.append(entry.block)
            }
        }

        return (MetadataIndex(ids: baseline.ids, entriesByID: entriesByID), pendingEmbedIDs, textsToEmbed)
    }

    /// Returns a copy of `index` with `ids`' embeddings replaced by `vectors`
    /// (positionally aligned) — but only where `index`'s *current* entry for
    /// that id still has the same block hash as `source`'s (the baseline
    /// this batch was actually embedded from). Everything else is
    /// unchanged.
    ///
    /// Merges into whichever index is passed as `into` — `build(items:
    /// embedder:previous:onDiagnostic:)` merges into its own freshly
    /// computed `baseline` (also passed as `source`, so the hash check is
    /// trivially satisfied there), while `MetadataSearcher.update(items:)`
    /// merges into its *current* `index` (which may have moved on since
    /// this re-embed started, if another `update(items:)` call interleaved
    /// during the `await`) rather than the stale baseline it kicked the
    /// embed off from.
    ///
    /// The hash check is what makes that safe for the same id changing
    /// *twice* across overlapping updates, not just an id being removed: if
    /// a slower call A (re-embedding id `"x"`'s old text) resolves after a
    /// faster, later call B has already re-embedded `"x"`'s *new* text and
    /// merged it in, `index`'s current entry for `"x"` carries B's hash,
    /// which no longer matches A's `source` hash for the old text — so A's
    /// stale vector is skipped instead of silently overwriting B's correct,
    /// newer one (which would otherwise pair fresh block text with a vector
    /// embedded from stale text, with no diagnostic and no way to detect the
    /// corruption later, since the hash would still nominally "match" a
    /// naive by-id-only merge). An id no longer present in `index` at all is
    /// likewise simply skipped, never resurrected.
    ///
    /// - Parameters:
    ///   - ids: the ids to set embeddings for.
    ///   - vectors: one embedding per id, positionally aligned with `ids`.
    ///   - source: the index this embed batch was actually computed from —
    ///     `ids`' block hashes here are what `index`'s current entries must
    ///     still match for the merge to apply.
    ///   - index: the index to merge into.
    /// - Returns: a copy of `index` with those embeddings applied wherever
    ///   the hash check passed.
    static func mergingEmbeddings(
        ids: [String],
        vectors: [[Float]],
        embeddedFrom source: MetadataIndex<Item>,
        into index: MetadataIndex<Item>
    ) -> MetadataIndex<Item> {
        var entriesByID = index.entriesByID
        for (id, vector) in zip(ids, vectors) {
            guard let entry = entriesByID[id], let sourceEntry = source.entriesByID[id],
                entry.blockHash == sourceEntry.blockHash
            else { continue }
            entriesByID[id] = Self.withEmbedding(vector, replacing: entry)
        }
        return MetadataIndex(ids: index.ids, entriesByID: entriesByID)
    }

    /// Whether `self` and `other` index the same ids, in the same order,
    /// each with an identical rendered-block hash — `update(items:)`'s
    /// redundant-update guard (plan.md §8 "hash-guarded"): calling `update`
    /// with content identical to what's already indexed must cost nothing
    /// (no re-embed, no selection-tier rebuild, no diagnostics), so callers
    /// may forward every upstream change notification without coalescing
    /// first. Embeddings are deliberately not part of this comparison —
    /// `update(items:)` only ever calls this against a freshly rendered
    /// baseline, never against an index still catching up on embeddings, so
    /// there's no case where embeddings alone would need to make two
    /// otherwise-identical indexes compare unequal.
    ///
    /// - Parameter other: the index to compare against.
    /// - Returns: whether both indexes are content-identical.
    func hasIdenticalContent(to other: MetadataIndex<Item>) -> Bool {
        guard ids == other.ids else { return false }
        return ids.allSatisfy { entriesByID[$0]?.blockHash == other.entriesByID[$0]?.blockHash }
    }

    /// Returns a copy of `entry` with its `embedding` replaced by `embedding`.
    ///
    /// Every other field carries over unchanged. `Entry`'s fields are all
    /// `let`, so replacing one means rebuilding the whole value; this is
    /// the single place that does so — both `build`'s reuse and
    /// freshly-embedded branches go through it.
    ///
    /// - Parameters:
    ///   - embedding: the embedding to store, or `nil`.
    ///   - replacing: the entry to copy, with `embedding` replaced.
    /// - Returns: the copied entry with its embedding replaced.
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

    /// Reconstructs an index directly from already-precomputed `ids` and `entriesByID`.
    ///
    /// The internal counterpart to `init(items:onDiagnostic:)` that
    /// `build(items:embedder:previous:onDiagnostic:)` uses to return a new
    /// index after filling in embeddings, without re-tokenizing or
    /// re-trigramming anything `baseline` already computed.
    ///
    /// - Parameters:
    ///   - ids: the precomputed ids, in first-seen order.
    ///   - entriesByID: the precomputed entries, keyed by id.
    private init(ids: [String], entriesByID: [String: Entry]) {
        self.ids = ids
        self.entriesByID = entriesByID
    }
}

// MARK: - FoundationModelsRanker selection-catalog conformance

/// Conforms `MetadataIndex` to FoundationModelsRanker's `SelectionCatalog` —
/// the narrow contract Ranker's `SelectionTier` drives its assembled prefix
/// and verbatim result lookup through (that protocol was written to
/// generalize exactly this type). `ids` is satisfied by the stored property
/// above; the two lookups forward to this index's existing accessors under
/// the protocol's `forId` spelling.
extension MetadataIndex: SelectionCatalog {
    /// A (typically shorter) summary of `id`'s item — its
    /// `SearchableMetadata.renderSummaryBlock()` — used to seed the
    /// selection tier's assembled prefix instead of the full block
    /// (plan.md §4).
    ///
    /// - Parameter forId: the id to look up.
    /// - Returns: the id's summary text, or `nil` if `id` isn't indexed.
    public func summaryBlock(forId id: String) -> String? {
        item(forID: id)?.renderSummaryBlock()
    }

    /// `id`'s full, verbatim rendered block — `block(forID:)` under the
    /// protocol's spelling; what a model-selected id resolves to in the
    /// tier's returned results.
    ///
    /// - Parameter forId: the id to look up.
    /// - Returns: the id's verbatim block, or `nil` if `id` isn't indexed.
    public func block(forId id: String) -> String? {
        block(forID: id)
    }
}
