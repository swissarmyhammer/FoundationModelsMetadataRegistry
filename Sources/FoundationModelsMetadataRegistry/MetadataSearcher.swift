/// Per-signal fusion weights for `MetadataSearcher`'s retrieval tier (plan.md
/// §5): the relative weight `RRF.fuse(rankedLists:weights:k:)` gives each of
/// the BM25, trigram, and cosine rankings.
///
/// A weight of `0.0` excludes that signal from the fused ranking entirely —
/// its ranked list (and weight) are left out of `RRF.fuse`/`RRF.normalize`'s
/// inputs altogether, rather than included at zero, so the normalization
/// ceiling never counts a signal that couldn't have scored anything (plan.md
/// §5 "absent-signal rule", generalized from CodeContextKit's
/// `SearchWeights`/`SearchCode.fuseRankings`).
public struct Weights: Sendable, Equatable {
    /// The weight applied to the BM25 keyword-ranking signal.
    public var bm25: Double

    /// The weight applied to the trigram fuzzy-ranking signal.
    public var trigram: Double

    /// The weight applied to the cosine semantic-ranking signal. Only takes
    /// effect when the searcher is configured with an embedder (`init(items:
    /// mode:weights:embedder:onDiagnostic:)` or `init(index:mode:weights:
    /// embedder:onDiagnostic:)`) — without one, cosine never ranks anything
    /// regardless of this weight.
    public var cosine: Double

    /// Creates a set of per-signal fusion weights.
    ///
    /// - Parameters:
    ///   - bm25: the weight applied to the BM25 signal. Defaults to `1.0`.
    ///   - trigram: the weight applied to the trigram signal. Defaults to
    ///     `1.0`.
    ///   - cosine: the weight applied to the cosine signal. Defaults to
    ///     `1.0`.
    public init(bm25: Double = 1.0, trigram: Double = 1.0, cosine: Double = 1.0) {
        self.bm25 = bm25
        self.trigram = trigram
        self.cosine = cosine
    }
}

/// Searches a catalog of `SearchableMetadata` on behalf of a Foundation
/// Models session (plan.md §3): an in-memory `MetadataIndex` plus the
/// per-signal `Weights` retrieval fuses by, exposed through one
/// `search(intent:limit:)` entry point.
///
/// `.retrieval` (BM25 (two fields) + character-trigram Dice + cosine, when an
/// embedder is configured, fused by `RRF.fuse(k: 60)` and normalized to
/// `[0, 1]`, plan.md §5) answers with no session, no tokens. Without an
/// `embedder` (or before any catalog item has been embedded), the cosine
/// signal never ranks anything and every `Match.signals.cosine` is `0.0` —
/// the same "no embedding available" value `Signals.cosine` documents, not a
/// crash or a special case (plan.md §5 "absent-signal rule") — and
/// `.embeddingUnavailable` is reported via `onDiagnostic` on every such
/// search, never silently. `.selection` (plan.md §6) drives
/// FoundationModelsRanker's `SelectionTier` when one is configured
/// (`init(..., selection:)`), re-attaching each `SelectionMatch`'s typed
/// `item` by id lookup and mapping its `RankDiagnostic`s into the same-named
/// `MetadataDiagnostic` cases; otherwise it throws
/// `SelectionTierUnavailable` (FoundationModelsRanker's error, re-exported)
/// rather than silently doing something the caller didn't ask for. `.auto`
/// resolves to `.selection`
/// when a selection tier is configured, `.retrieval` otherwise (plan.md §7
/// "selection when a model is configured, else retrieval").
public actor MetadataSearcher<Item: SearchableMetadata> {
    /// The in-memory index built from the catalog's items at `init`, replaced
    /// wholesale by `update(items:)` (plan.md §8, hot reload) on every real
    /// change.
    private var index: MetadataIndex<Item>

    /// The per-signal fusion weights this searcher's retrieval tier uses.
    private let weights: Weights

    /// Which tier `search(intent:limit:)` uses.
    private let mode: SearchMode

    /// The embedder used to embed the *query* text at search time (plan.md
    /// §5 "only the query itself is embedded per search") — `nil` means no
    /// embedder is configured, so cosine ranking is skipped and every search
    /// degrades to keyword-only. Catalog items are never embedded here; that
    /// happens once, at index-build/update time, via `MetadataIndex.build(
    /// items:embedder:previous:onDiagnostic:)` (or, for `update(items:)`,
    /// `MetadataIndex.incrementalBaseline(items:previous:onDiagnostic:)` +
    /// `MetadataIndex.mergingEmbeddings(ids:vectors:embeddedFrom:into:)`).
    /// The same embedder instance is reused for both roles across every
    /// `update`.
    private let embedder: (any TextEmbedding)?

    /// Called for every diagnostic emitted while building the index and
    /// while searching (currently `.duplicateId`, `.embeddingUnavailable`,
    /// `.unknownSelectedId`, and `.embedCatchUp`).
    private let onDiagnostic: @Sendable (MetadataDiagnostic) -> Void

    /// This searcher's selection tier configuration (plan.md §6), or `nil`
    /// when none was supplied at `init` — kept around (rather than only
    /// building `selectionTier` once) so `update(items:)` can rebuild the
    /// tier from the same configuration whenever the index changes.
    private let selectionConfig: SelectionConfig?

    /// This searcher's selection tier (plan.md §6) — FoundationModelsRanker's
    /// `SelectionTier` over this searcher's index (its `SelectionCatalog`
    /// conformance), paired with the index snapshot it was built over — or
    /// `nil` when no `SelectionConfig` was supplied at `init`; `.selection`
    /// throws `SelectionTierUnavailable` in that case, exactly as it did
    /// before a selection tier existed at all. The snapshot is what
    /// `selectionSearch(_:intent:limit:)` re-attaches each returned id's
    /// typed `item` from: the tier answers over that exact catalog, so
    /// looking ids up in the same snapshot keeps `Match.item`/`Match.block`
    /// consistent even if a concurrent `update(items:)` swaps `index` while
    /// a search is suspended in the tier. Rebuilt by `update(items:)` on
    /// every real catalog change (plan.md §8): a fresh `SelectionTier`
    /// starts with no cached root session, a prefix assembled from the new
    /// index, and an id-enum grammar derived from the new id set.
    private var selectionTier: (tier: SelectionTier, snapshot: MetadataIndex<Item>)?

    /// Builds a searcher over `items`, indexing them once at `init` with no
    /// embedder — cosine never ranks anything and every search degrades to
    /// keyword-only, reported via `.embeddingUnavailable` (plan.md §5). Use
    /// `init(items:mode:weights:embedder:onDiagnostic:)` to wire up cosine.
    ///
    /// - Parameters:
    ///   - items: the catalog's items, in first-seen-wins duplicate-id order
    ///     (forwarded to `MetadataIndex.init(items:onDiagnostic:)`).
    ///   - mode: which tier `search(intent:limit:)` uses. Defaults to
    ///     `.auto`, which falls back to `.retrieval` until a selection tier
    ///     is configured.
    ///   - weights: the per-signal fusion weights for the retrieval tier.
    ///     Defaults to `1.0` for every signal.
    ///   - selection: this searcher's selection tier configuration (plan.md
    ///     §6), or `nil` (the default) to leave `.selection` unavailable.
    ///   - onDiagnostic: called for every diagnostic emitted while building
    ///     the index (currently only `.duplicateId`), and by later tiers as
    ///     they land. Defaults to logging via `MetadataDiagnostic.log(_:)`.
    public init(
        items: [Item],
        mode: SearchMode = .auto,
        weights: Weights = Weights(),
        selection: SelectionConfig? = nil,
        onDiagnostic: @escaping @Sendable (MetadataDiagnostic) -> Void = { MetadataDiagnostic.log($0) }
    ) {
        self.init(
            index: MetadataIndex(items: items, onDiagnostic: onDiagnostic),
            mode: mode,
            weights: weights,
            embedder: nil,
            selection: selection,
            onDiagnostic: onDiagnostic
        )
    }

    /// Builds a searcher over `items`, embedding every item's rendered block
    /// through `embedder` at index-build time (plan.md §5, §8) so cosine can
    /// join RRF fusion in `search(intent:limit:)`.
    ///
    /// - Parameters:
    ///   - items: the catalog's items, in first-seen-wins duplicate-id order
    ///     (forwarded to `MetadataIndex.build(items:embedder:previous:
    ///     onDiagnostic:)`).
    ///   - mode: which tier `search(intent:limit:)` uses. Defaults to
    ///     `.auto`, which falls back to `.retrieval` until a selection tier
    ///     is configured.
    ///   - weights: the per-signal fusion weights for the retrieval tier.
    ///     Defaults to `1.0` for every signal.
    ///   - embedder: the embedder to embed every item's block with at build
    ///     time, and the query with at search time. `nil` behaves like
    ///     `init(items:mode:weights:onDiagnostic:)` — keyword-only, with
    ///     `.embeddingUnavailable` reported on every search.
    ///   - selection: this searcher's selection tier configuration (plan.md
    ///     §6), or `nil` (the default) to leave `.selection` unavailable.
    ///   - onDiagnostic: called for every diagnostic emitted while building
    ///     the index and while searching. Defaults to logging via
    ///     `MetadataDiagnostic.log(_:)`.
    public init(
        items: [Item],
        mode: SearchMode = .auto,
        weights: Weights = Weights(),
        embedder: (any TextEmbedding)?,
        selection: SelectionConfig? = nil,
        onDiagnostic: @escaping @Sendable (MetadataDiagnostic) -> Void = { MetadataDiagnostic.log($0) }
    ) async {
        self.init(
            index: await MetadataIndex.build(items: items, embedder: embedder, onDiagnostic: onDiagnostic),
            mode: mode,
            weights: weights,
            embedder: embedder,
            selection: selection,
            onDiagnostic: onDiagnostic
        )
    }

    /// Builds a searcher directly over an already-built `index` — the seam
    /// `update(items:)` (plan.md §8, a later task) and tests needing precise
    /// control over an index's embeddings (e.g. a mix of embedded and
    /// not-yet-embedded items) use instead of re-deriving the index from
    /// `items` on every call.
    ///
    /// - Parameters:
    ///   - index: the prebuilt index to search over.
    ///   - mode: which tier `search(intent:limit:)` uses. Defaults to
    ///     `.auto`.
    ///   - weights: the per-signal fusion weights for the retrieval tier.
    ///     Defaults to `1.0` for every signal.
    ///   - embedder: the embedder to embed the query with at search time.
    ///     Defaults to `nil` (keyword-only).
    ///   - selection: this searcher's selection tier configuration (plan.md
    ///     §6), or `nil` (the default) to leave `.selection` unavailable.
    ///   - onDiagnostic: called for every diagnostic emitted while searching.
    ///     Defaults to logging via `MetadataDiagnostic.log(_:)`.
    public init(
        index: MetadataIndex<Item>,
        mode: SearchMode = .auto,
        weights: Weights = Weights(),
        embedder: (any TextEmbedding)? = nil,
        selection: SelectionConfig? = nil,
        onDiagnostic: @escaping @Sendable (MetadataDiagnostic) -> Void = { MetadataDiagnostic.log($0) }
    ) {
        self.index = index
        self.mode = mode
        self.weights = weights
        self.embedder = embedder
        self.onDiagnostic = onDiagnostic
        self.selectionConfig = selection
        self.selectionTier = selection.map { config in
            Self.buildSelectionTierPair(
                index: index, config: config, weights: weights, embedder: embedder, onDiagnostic: onDiagnostic
            )
        }
    }

    /// Builds FoundationModelsRanker's `SelectionTier` over `index` (its
    /// `SelectionCatalog` conformance), paired with `index` itself as the
    /// snapshot `selectionSearch(_:intent:limit:)` re-attaches typed items
    /// from — the one piece of tier construction both the designated
    /// initializer and `update(items:)` (plan.md §8, hot reload) need
    /// whenever the underlying index changes: a fresh tier starts with no
    /// cached root session and a prefix assembled from `index`. The tier's
    /// `RankDiagnostic`s are mapped into the same-named `MetadataDiagnostic`
    /// cases, and its `retrievalRanking` closure is wired to
    /// `rankEntireCatalog(intent:index:weights:embedder:onDiagnostic:)`
    /// (each `Match` reduced to the item-less `SelectionMatch` the tier
    /// ranks with).
    ///
    /// `static`, not an instance method: the synchronous designated
    /// initializer builds the pair from its own parameters, and SE-0327's
    /// flow-sensitive actor-init isolation forbids writing `selectionTier`
    /// after any method call on `self` — so an instance-method form could
    /// never be shared with `init` at all.
    ///
    /// - Parameters:
    ///   - index: the catalog index the new tier answers `search(intent:
    ///     limit:)` calls over, and the snapshot it is paired with.
    ///   - config: the selection tier configuration to build against.
    ///   - weights: the per-signal fusion weights `retrievalRanking` scores
    ///     the over-budget candidate ranking with.
    ///   - embedder: the embedder `retrievalRanking` embeds the intent with
    ///     for the cosine signal.
    ///   - onDiagnostic: called for every diagnostic the new tier, and its
    ///     `retrievalRanking` closure, emit.
    /// - Returns: a freshly constructed selection tier over `index`, paired
    ///   with `index` as the snapshot it was built over.
    private static func buildSelectionTierPair(
        index: MetadataIndex<Item>,
        config: SelectionConfig,
        weights: Weights,
        embedder: (any TextEmbedding)?,
        onDiagnostic: @escaping @Sendable (MetadataDiagnostic) -> Void
    ) -> (tier: SelectionTier, snapshot: MetadataIndex<Item>) {
        (
            tier: SelectionTier(
                catalog: index,
                config: config,
                onDiagnostic: { onDiagnostic(MetadataDiagnostic($0)) },
                retrievalRanking: { intent in
                    await Self.rankEntireCatalog(
                        intent: intent,
                        index: index,
                        weights: weights,
                        embedder: embedder,
                        onDiagnostic: onDiagnostic
                    ).map { match in
                        SelectionMatch(id: match.id, block: match.block, score: match.score, signals: match.signals)
                    }
                }
            ),
            snapshot: index
        )
    }

    // MARK: - Hot reload (plan.md §8)

    /// Hot-reloads this searcher's catalog from `items`.
    ///
    /// 1. Re-renders blocks and rebuilds the tokenized/trigram indexes
    ///    synchronously (`MetadataIndex.incrementalBaseline(items:previous:
    ///    onDiagnostic:)`) and assigns the result to `index` immediately —
    ///    items are keyword-searchable (`.retrieval`/`.auto`'s BM25 +
    ///    trigram signals) before this call even reaches the embedder.
    /// 2. Re-embeds incrementally: only items whose `(id, block-hash)`
    ///    changed since the previous index are embedded, reusing every other
    ///    item's stored embedding. This step awaits `embedder.embed(_:)` —
    ///    an actor reentrancy point, so a concurrent `search(intent:limit:)`
    ///    interleaves and sees the already-rebuilt keyword indexes with cosine
    ///    absent for the still-pending items (the absent-signal rule, plan.md
    ///    §5), never blocked behind the whole re-embed. The pending/total gap
    ///    is reported once via `MetadataDiagnostic.embedCatchUp(pending:
    ///    total:)`.
    /// 3. Drops the cached selection-tier root session by rebuilding the
    ///    whole tier over the new index: the next under-budget `.selection`/
    ///    `.auto` search re-prefills against the new catalog (one prefix
    ///    re-prefill), and any id-enum grammar a caller derives from the
    ///    tier's candidate ids reflects the new id set.
    ///
    /// Hash-guarded: if `items` renders to content identical to what's
    /// already indexed (same ids, same block hashes) *and* nothing is
    /// pending an embed (every entry already carries a real embedding, or
    /// none is expected), this call is a complete no-op — no re-embedding,
    /// no selection-tier rebuild, no diagnostics — so callers may forward
    /// every upstream change notification (file watcher, MCP `listChanged`)
    /// without coalescing them first. Content-identical but still catching
    /// up (e.g. a prior embed call failed transiently) still re-embeds, just
    /// without rebuilding the selection tier — nothing keyword/selection-
    /// relevant changed, only the still-missing embedding is worth
    /// finishing.
    ///
    /// - Parameter items: the catalog's new/refreshed items, in first-seen-
    ///   wins duplicate-id order (forwarded to `MetadataIndex`'s duplicate-id
    ///   policy).
    public func update(items: [Item]) async {
        let previous = index
        let (baseline, pendingEmbedIDs, textsToEmbed) = MetadataIndex.incrementalBaseline(
            items: items,
            previous: previous,
            onDiagnostic: onDiagnostic
        )

        let contentChanged = !baseline.hasIdenticalContent(to: previous)
        guard contentChanged || !pendingEmbedIDs.isEmpty else { return }

        index = baseline
        // Only a genuine content change warrants dropping the cached root
        // session -- catching up an embedding for otherwise-unchanged
        // content doesn't affect keyword search or the selection prefix at
        // all, so forcing a re-prefill for it would be pure waste.
        if contentChanged {
            selectionTier = selectionConfig.map { config in
                Self.buildSelectionTierPair(
                    index: baseline, config: config, weights: weights, embedder: embedder, onDiagnostic: onDiagnostic
                )
            }
        }

        guard !pendingEmbedIDs.isEmpty, let embedder else { return }

        onDiagnostic(.embedCatchUp(pending: pendingEmbedIDs.count, total: baseline.count))
        // Merges into `index` as it stands *after* this suspension -- not
        // into the stale `baseline` this re-embed started from -- and only
        // where `index`'s current entry still matches `baseline`'s block
        // hash for that id (`mergingEmbeddings(ids:vectors:embeddedFrom:
        // into:)`'s hash check). A concurrent `update(items:)` call may have
        // moved the catalog on in the meantime (actor reentrancy across
        // this `await`); its result must win, never be silently clobbered
        // by this call's now-stale vector finishing late -- including when
        // that concurrent call re-embedded the *same* id with different
        // content, not just when it removed the id outright.
        if let vectors = try? await embedder.embed(textsToEmbed), vectors.count == pendingEmbedIDs.count {
            index = MetadataIndex.mergingEmbeddings(ids: pendingEmbedIDs, vectors: vectors, embeddedFrom: baseline, into: index)
        }
    }

    /// Searches the catalog for `intent`, returning at most `limit` matches
    /// ordered by descending fused score.
    ///
    /// - Parameters:
    ///   - intent: the search query.
    ///   - limit: the maximum number of matches to return. `limit <= 0`
    ///     yields an empty result rather than throwing or crashing.
    /// - Returns: `.retrieval`'s fused, `[0, 1]`-normalized matches;
    ///   `.selection`'s verbatim matches when a selection tier is configured
    ///   (plan.md §6); `.auto`'s resolution of whichever of those applies
    ///   (plan.md §7).
    /// - Throws: `SelectionTierUnavailable` when `mode == .selection` and no
    ///   selection tier is configured (`init(..., selection:)`); otherwise
    ///   whatever the underlying selection session throws.
    public func search(intent: String, limit: Int) async throws -> [Match<Item>] {
        switch mode {
        case .retrieval:
            return await retrievalSearch(intent: intent, limit: limit)
        case .selection:
            guard let selectionTier else { throw SelectionTierUnavailable() }
            return try await Self.selectionSearch(selectionTier, intent: intent, limit: limit)
        case .auto:
            if let selectionTier {
                return try await Self.selectionSearch(selectionTier, intent: intent, limit: limit)
            }
            return await retrievalSearch(intent: intent, limit: limit)
        }
    }

    // MARK: - Selection tier (plan.md §6, via FoundationModelsRanker)

    /// Answers one `.selection`/`.auto` search through FoundationModelsRanker's
    /// `SelectionTier`, then maps each returned `SelectionMatch` into this
    /// package's typed `Match<Item>` by looking its id up in the index
    /// snapshot the tier was built over — the tier's `SelectionCatalog`
    /// carries no item type, so the typed `item` is re-attached here. The
    /// lookup is against `selection.snapshot` (not the actor's live `index`)
    /// so `Match.item` always pairs with the same catalog generation that
    /// produced `Match.block`, even if a concurrent `update(items:)` swapped
    /// the live index while this call was suspended in the tier. Every id
    /// the tier returns resolves in that snapshot by construction (the tier
    /// filters unknown ids itself); the `compactMap` is defensive.
    ///
    /// - Parameters:
    ///   - selection: the tier to search, paired with the index snapshot it
    ///     was built over.
    ///   - intent: the plain-language search intent.
    ///   - limit: the maximum number of matches to return.
    /// - Returns: the selected items' verbatim `Match`es, at most `limit`.
    /// - Throws: whatever the tier's underlying session throws.
    private static func selectionSearch(
        _ selection: (tier: SelectionTier, snapshot: MetadataIndex<Item>),
        intent: String,
        limit: Int
    ) async throws -> [Match<Item>] {
        let selectionMatches = try await selection.tier.search(intent: intent, limit: limit)
        return selectionMatches.compactMap { match in
            guard let item = selection.snapshot.item(forID: match.id) else { return nil }
            return Match(id: match.id, block: match.block, score: match.score, signals: match.signals, item: item)
        }
    }

    // MARK: - Retrieval tier

    /// Sorts document indices by descending normalized fused score, breaking
    /// ties by ascending catalog index for deterministic, first-seen-order
    /// output — the shared ordering both `retrievalSearch(intent:limit:)` and
    /// `rankEntireCatalog(intent:index:weights:embedder:onDiagnostic:)` apply
    /// to `normalized`'s keys.
    ///
    /// - Parameters:
    ///   - indices: the document indices to sort.
    ///   - normalized: doc index -> normalized `[0, 1]` fused score.
    /// - Returns: `indices`, ordered descending by score.
    private static func sortByNormalizedScore(indices: [Int], using normalized: [Int: Double]) -> [Int] {
        indices.sorted { left, right in
            let leftScore = normalized[left] ?? 0.0
            let rightScore = normalized[right] ?? 0.0
            guard leftScore != rightScore else {
                // Deterministic tie-break: first-seen catalog order.
                return left < right
            }
            return leftScore > rightScore
        }
    }

    /// Runs the `.retrieval` tier: BM25 + trigram + cosine rankings fused by
    /// `RRF.fuse(k: 60)`, normalized to `[0, 1]`, mapped back through the
    /// catalog to verbatim `Match`es (plan.md §5). Only ever returns
    /// documents at least one signal actually ranked — contrast
    /// `rankEntireCatalog(intent:index:weights:embedder:onDiagnostic:)`,
    /// which the over-budget selection path needs a full, always-
    /// `index.count`-long ordering from.
    private func retrievalSearch(intent: String, limit: Int) async -> [Match<Item>] {
        guard limit > 0, index.count > 0 else { return [] }

        let signals = await Self.computeSignals(intent: intent, index: index, weights: weights, embedder: embedder, onDiagnostic: onDiagnostic)
        let normalized = Self.fuseAndNormalize(signals: signals, weights: weights)

        let orderedDocumentIndices = Self.sortByNormalizedScore(indices: Array(normalized.keys), using: normalized)

        return Self.buildMatches(
            documentIndices: Array(orderedDocumentIndices.prefix(limit)),
            index: index,
            normalized: normalized,
            signals: signals
        )
    }

    // MARK: - Over-budget candidate ranking (plan.md §6)

    /// Ranks the entire catalog for `intent`, best-first, always returning
    /// exactly `index.count` matches: documents any signal actually ranked
    /// come first, ordered exactly like `retrievalSearch(intent:limit:)`'s
    /// own fused/normalized ranking; every other document follows in
    /// catalog order, scored `0.0` with all-absent `Signals` (the
    /// absent-signal rule, plan.md §5, extended to "no signal ranked this
    /// document at all"). This is `SelectionTier`'s over-budget top-M
    /// candidate source (`SelectionTier.init(index:config:onDiagnostic:
    /// retrievalRanking:)`) — unlike `retrievalSearch(intent:limit:)`, which
    /// only ever returns real matches, the over-budget path needs a full
    /// ordering so its top-M candidate count is always `min(candidateLimit,
    /// index.count)`, never fewer just because a query's signal overlap with
    /// the catalog happens to be sparse.
    ///
    /// - Parameters:
    ///   - intent: the search query.
    ///   - index: the catalog index to rank.
    ///   - weights: the per-signal fusion weights.
    ///   - embedder: the embedder to embed `intent` with for the cosine
    ///     signal, or `nil` to skip it.
    ///   - onDiagnostic: called for every diagnostic emitted while ranking
    ///     (currently only `.embeddingUnavailable`).
    /// - Returns: exactly `index.count` matches, best-first.
    private static func rankEntireCatalog(
        intent: String,
        index: MetadataIndex<Item>,
        weights: Weights,
        embedder: (any TextEmbedding)?,
        onDiagnostic: @Sendable (MetadataDiagnostic) -> Void
    ) async -> [Match<Item>] {
        guard index.count > 0 else { return [] }

        let signals = await computeSignals(intent: intent, index: index, weights: weights, embedder: embedder, onDiagnostic: onDiagnostic)
        let normalized = fuseAndNormalize(signals: signals, weights: weights)

        let rankedIndices = sortByNormalizedScore(indices: Array(normalized.keys), using: normalized)
        let unrankedIndices = index.ids.indices.filter { normalized[$0] == nil }

        return buildMatches(documentIndices: rankedIndices + unrankedIndices, index: index, normalized: normalized, signals: signals)
    }

    /// One (ranking, weight, raw scores) tuple per retrieval signal, as
    /// computed by `computeSignals(intent:index:weights:embedder:
    /// onDiagnostic:)` — the shared input both `retrievalSearch(intent:
    /// limit:)` and `rankEntireCatalog(intent:index:weights:embedder:
    /// onDiagnostic:)` fuse and order differently.
    private struct RetrievalSignals {
        let bm25Ranking: [Int]
        let bm25Scores: [Double]
        let trigramRanking: [Int]
        let trigramScores: [Double]
        let cosineRanking: [Int]
        let cosineScores: [Double]
    }

    /// Computes the BM25, trigram, and cosine signals for `intent` over
    /// `index` — the one piece of per-signal computation
    /// `retrievalSearch(intent:limit:)` and `rankEntireCatalog(intent:index:
    /// weights:embedder:onDiagnostic:)` share.
    ///
    /// - Parameters:
    ///   - intent: the search query.
    ///   - index: the catalog index to score.
    ///   - weights: the per-signal fusion weights (cosine is only computed
    ///     when `weights.cosine > 0.0`).
    ///   - embedder: the embedder to embed `intent` with for the cosine
    ///     signal, or `nil` to skip it.
    ///   - onDiagnostic: called for every diagnostic emitted while computing
    ///     the cosine signal (currently only `.embeddingUnavailable`).
    /// - Returns: every signal's ranking and full-length, positionally
    ///   aligned raw scores.
    private static func computeSignals(
        intent: String,
        index: MetadataIndex<Item>,
        weights: Weights,
        embedder: (any TextEmbedding)?,
        onDiagnostic: @Sendable (MetadataDiagnostic) -> Void
    ) async -> RetrievalSignals {
        let (bm25Ranking, bm25Scores) = computeBM25Ranking(intent: intent, index: index)
        let (trigramRanking, trigramScores) = computeTrigramRanking(intent: intent, index: index)
        // Cosine only runs when configured to actually count: a zero weight
        // means the caller doesn't want the signal, so there's no reason to
        // embed the query or warn about a missing embedder for it.
        let (cosineRanking, cosineScores): ([Int], [Double])
        if weights.cosine > 0.0 {
            (cosineRanking, cosineScores) = await computeCosineRanking(
                intent: intent, index: index, embedder: embedder, onDiagnostic: onDiagnostic
            )
        } else {
            (cosineRanking, cosineScores) = ([], zeroScoresArray(count: index.count))
        }
        return RetrievalSignals(
            bm25Ranking: bm25Ranking,
            bm25Scores: bm25Scores,
            trigramRanking: trigramRanking,
            trigramScores: trigramScores,
            cosineRanking: cosineRanking,
            cosineScores: cosineScores
        )
    }

    /// Fuses `signals` via `RRF.fuse(k: 60)` and normalizes to `[0, 1]`
    /// (plan.md §5), excluding any signal whose weight is `0.0` or whose
    /// ranking is empty from both the fusion and the normalization ceiling
    /// (the "absent-signal rule").
    ///
    /// - Parameters:
    ///   - signals: the per-signal rankings to fuse.
    ///   - weights: the per-signal fusion weights.
    /// - Returns: doc index -> normalized `[0, 1]` fused score, for every
    ///   document any included signal ranked.
    private static func fuseAndNormalize(signals: RetrievalSignals, weights: Weights) -> [Int: Double] {
        let rankedSignals: [(ranking: [Int], weight: Double)] = [
            (signals.bm25Ranking, weights.bm25),
            (signals.trigramRanking, weights.trigram),
            (signals.cosineRanking, weights.cosine),
        ]

        var rankedLists: [[Int]] = []
        var listWeights: [Double] = []
        // Only signals with a positive configured weight AND at least one
        // matching document enter RRF's inputs: an empty ranking would
        // contribute nothing to `fuse` regardless, but leaving its weight out
        // of `normalize`'s ceiling too keeps a perfect single-signal match
        // normalizing to 1.0 instead of being capped below it by an
        // unreachable share (plan.md §5 "absent-signal rule").
        for (ranking, weight) in rankedSignals where weight > 0.0 && !ranking.isEmpty {
            rankedLists.append(ranking)
            listWeights.append(weight)
        }

        let fused = RRF.fuse(rankedLists: rankedLists, weights: listWeights)
        return RRF.normalize(fused: fused, weights: listWeights)
    }

    /// Maps document indices back through the catalog to verbatim
    /// `Match`es, carrying `normalized`'s fused score (`0.0` if absent) and
    /// `signals`' raw per-signal breakdown for each — the shared "build a
    /// `Match`" step `retrievalSearch(intent:limit:)` and
    /// `rankEntireCatalog(intent:index:weights:embedder:onDiagnostic:)`
    /// apply to differently-ordered/truncated `documentIndices`.
    ///
    /// - Parameters:
    ///   - documentIndices: the document indices (into `index.ids`) to map,
    ///     in the order the result should preserve.
    ///   - index: the catalog index to look items/blocks up in.
    ///   - normalized: doc index -> normalized `[0, 1]` fused score.
    ///   - signals: the raw per-signal scores every document was computed
    ///     against.
    /// - Returns: one `Match` per resolvable document index, in order.
    private static func buildMatches(
        documentIndices: [Int],
        index: MetadataIndex<Item>,
        normalized: [Int: Double],
        signals: RetrievalSignals
    ) -> [Match<Item>] {
        documentIndices.compactMap { documentIndex in
            let id = index.ids[documentIndex]
            guard let item = index.item(forID: id), let block = index.block(forID: id) else { return nil }
            return Match(
                id: id,
                block: block,
                score: normalized[documentIndex] ?? 0.0,
                signals: Signals(
                    bm25: signals.bm25Scores[documentIndex],
                    trigram: signals.trigramScores[documentIndex],
                    cosine: signals.cosineScores[documentIndex]
                ),
                item: item
            )
        }
    }

    /// Computes the BM25 keyword-ranking signal: `intent`'s tokens scored
    /// against every catalog entry's precomputed field-weighted term
    /// frequency (`id` ×5, block ×1 — `MetadataIndex`'s two-field indexing).
    ///
    /// - Returns: the matching document indices (into `index.ids`) ranked
    ///   descending by score, and the full-length, positionally aligned raw
    ///   score for every document.
    private static func computeBM25Ranking(intent: String, index: MetadataIndex<Item>) -> (ranking: [Int], scores: [Double]) {
        let queryTokens = Tokenizer.tokenize(text: intent)
        guard !queryTokens.isEmpty else {
            return ([], zeroScoresArray(count: index.count))
        }

        let documents = index.ids.map { id in
            (index.documentLength(forID: id) ?? 0, index.termSet(forID: id) ?? [])
        }
        let corpus = BM25Corpus(queryTokens: queryTokens, documents: documents)
        let scores = index.ids.map { id in
            corpus.score(
                weightedTermFrequency: index.weightedTermFrequency(forID: id) ?? [:],
                documentLength: index.documentLength(forID: id) ?? 0,
                queryTokens: queryTokens
            )
        }
        return (rankingOfPositiveScores(scores: scores), scores)
    }

    /// Computes the trigram fuzzy-ranking signal: `intent`'s canonical
    /// trigram set scored against each catalog entry's `id` (weighted
    /// `BM25.primaryFieldWeight`) and block (weighted `BM25.bodyFieldWeight`)
    /// trigram sets — the same two-field weighting BM25 uses, applied to the
    /// trigram aggregate (`Signals.trigram`'s documented "field-weighted
    /// aggregate across several fields").
    ///
    /// - Returns: the matching document indices (into `index.ids`) ranked
    ///   descending by score, and the full-length, positionally aligned raw
    ///   score for every document.
    private static func computeTrigramRanking(intent: String, index: MetadataIndex<Item>) -> (ranking: [Int], scores: [Double]) {
        let querySet = Trigram.canonicalTrigramSet(text: intent)
        let scores = index.ids.map { id -> Double in
            let idTrigramSet = index.idTrigramSet(forID: id) ?? []
            let blockTrigramSet = index.blockTrigramSet(forID: id) ?? []
            return BM25.primaryFieldWeight * Trigram.dice(querySet: querySet, targetSet: idTrigramSet)
                + BM25.bodyFieldWeight * Trigram.dice(querySet: querySet, targetSet: blockTrigramSet)
        }
        return (rankingOfPositiveScores(scores: scores), scores)
    }

    /// Computes the cosine semantic-ranking signal: `intent` embedded
    /// through `embedder`, scored against each catalog entry's precomputed
    /// block embedding via a brute-force per-row dot product (plan.md §5
    /// "brute-force scoring — plain per-row dot products for cosine — is
    /// exact and effectively instant" at metadata scale; decision #10, no
    /// vector store).
    ///
    /// Degrades to keyword-only and reports `.embeddingUnavailable` via
    /// `onDiagnostic` whenever cosine can't contribute: no `embedder` is
    /// configured, none of the catalog's items carry an embedding yet, or
    /// embedding the query itself fails. An item with no stored embedding
    /// scores `0.0` here regardless — the absent-signal rule (plan.md §5):
    /// it contributes nothing to cosine but still ranks via BM25 + trigram.
    ///
    /// - Returns: the matching document indices (into `index.ids`) ranked
    ///   descending by score, and the full-length, positionally aligned raw
    ///   score for every document.
    private static func computeCosineRanking(
        intent: String,
        index: MetadataIndex<Item>,
        embedder: (any TextEmbedding)?,
        onDiagnostic: @Sendable (MetadataDiagnostic) -> Void
    ) async -> (ranking: [Int], scores: [Double]) {
        guard let embedder, index.ids.contains(where: { index.embedding(forID: $0) != nil }) else {
            return embeddingUnavailableRanking(count: index.count, onDiagnostic: onDiagnostic)
        }

        let queryEmbedding: [Float]
        do {
            guard let firstVector = try await embedder.embed([intent]).first else {
                // A well-behaved `TextEmbedding` conformer returns exactly
                // one vector per input; an empty result for a one-element
                // input is itself a degradation worth reporting, not a
                // silent empty ranking (plan.md §1 "every degradation is
                // reported, never silent").
                return embeddingUnavailableRanking(count: index.count, onDiagnostic: onDiagnostic)
            }
            queryEmbedding = firstVector
        } catch {
            return embeddingUnavailableRanking(count: index.count, onDiagnostic: onDiagnostic)
        }

        let scores = index.ids.map { id -> Double in
            guard let itemEmbedding = index.embedding(forID: id) else { return 0.0 }
            return cosineSimilarity(query: queryEmbedding, target: itemEmbedding)
        }
        return (rankingOfPositiveScores(scores: scores), scores)
    }

    /// Reports `.embeddingUnavailable` and returns the zero-filled ranking
    /// every guard in `computeCosineRanking(intent:index:embedder:
    /// onDiagnostic:)` falls back to when cosine can't contribute: no
    /// `embedder` is configured, none of the catalog's items carry an
    /// embedding yet, or embedding the query itself fails — the shared
    /// "degrade to keyword-only, report it, never silently" response
    /// (plan.md §1, §5).
    ///
    /// - Parameters:
    ///   - count: the number of documents to zero-fill scores for.
    ///   - onDiagnostic: called with `.embeddingUnavailable`.
    /// - Returns: an empty ranking and `count` zero-filled scores.
    private static func embeddingUnavailableRanking(
        count: Int,
        onDiagnostic: @Sendable (MetadataDiagnostic) -> Void
    ) -> (ranking: [Int], scores: [Double]) {
        onDiagnostic(.embeddingUnavailable)
        return ([], zeroScoresArray(count: count))
    }

    /// Cosine similarity between two equal-length vectors: `(a · b) / (|a| |b|)`.
    ///
    /// - Parameters:
    ///   - query: the query's embedding.
    ///   - target: the catalog entry's stored block embedding.
    /// - Returns: the similarity in `[-1.0, 1.0]`, or `0.0` if the vectors
    ///   differ in length or either has zero magnitude (orthogonal-by-
    ///   convention, matching `Signals.cosine`'s documented `0.0` for "either
    ///   the query or the doc lacks an embedding").
    private static func cosineSimilarity(query: [Float], target: [Float]) -> Double {
        guard query.count == target.count, !query.isEmpty else { return 0.0 }

        var dotProduct: Float = 0.0
        var queryMagnitudeSquared: Float = 0.0
        var targetMagnitudeSquared: Float = 0.0
        for index in query.indices {
            dotProduct += query[index] * target[index]
            queryMagnitudeSquared += query[index] * query[index]
            targetMagnitudeSquared += target[index] * target[index]
        }

        guard queryMagnitudeSquared > 0.0, targetMagnitudeSquared > 0.0 else { return 0.0 }
        return Double(dotProduct / (queryMagnitudeSquared.squareRoot() * targetMagnitudeSquared.squareRoot()))
    }

    /// The indices of every positive score, descending by score — the
    /// "graceful degradation, no zero-fill" ranked-list shape
    /// `RRF.fuse(rankedLists:weights:k:)` expects: a document that scored
    /// `0.0` (no match at all for this signal) is simply absent from the
    /// list, exactly as if it weren't in the catalog for this signal.
    private static func rankingOfPositiveScores(scores: [Double]) -> [Int] {
        scores.indices.filter { scores[$0] > 0.0 }.sorted { scores[$0] > scores[$1] }
    }

    /// A `count`-long array of `0.0` scores — the "signal couldn't be
    /// computed" placeholder every signal-ranking function returns alongside
    /// an empty ranking when its guard fails (empty query, disabled weight,
    /// missing embedder).
    private static func zeroScoresArray(count: Int) -> [Double] {
        [Double](repeating: 0.0, count: count)
    }
}
