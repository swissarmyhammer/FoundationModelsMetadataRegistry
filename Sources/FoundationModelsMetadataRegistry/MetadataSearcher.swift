import os

/// Per-signal fusion weights for `MetadataSearcher`'s retrieval tier (plan.md
/// §5) — FoundationModelsRanker's `SignalWeights` under this package's
/// established name: the relative weight `HybridRanker` gives each of the
/// BM25, trigram, and cosine rankings when fusing them.
///
/// A weight of `0.0` excludes that signal from the fused ranking entirely —
/// left out of the fusion and the normalization ceiling altogether, rather
/// than included at zero, so the ceiling never counts a signal that couldn't
/// have scored anything (plan.md §5 "absent-signal rule"). `cosine` only
/// takes effect when the searcher is configured with an embedder
/// (`init(items:mode:weights:embedder:onDiagnostic:)` or `init(index:mode:
/// weights:embedder:onDiagnostic:)`) — without one, cosine never ranks
/// anything regardless of this weight — and a zero `cosine` weight skips the
/// cosine computation without an `.embeddingUnavailable` diagnostic.
public typealias Weights = SignalWeights

/// Searches a catalog of `SearchableMetadata` on behalf of a Foundation
/// Models session (plan.md §3): an in-memory `MetadataIndex` plus the
/// per-signal `Weights` retrieval fuses by, exposed through one
/// `search(intent:limit:)` entry point.
///
/// `.retrieval` (BM25 (two fields) + character-trigram Dice + cosine, when an
/// embedder is configured, fused and normalized to `[0, 1]` by
/// FoundationModelsRanker's `HybridRanker`, plan.md §5) answers with no
/// session, no tokens. Without an
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

    /// A selection tier paired with the refreshable index snapshot it ranks
    /// over: the tier's `retrievalRanking` closure reads `snapshot` at call
    /// time, and `selectionSearch(_:intent:limit:)` re-attaches each
    /// returned id's typed `item` from it. Boxed in an
    /// `OSAllocatedUnfairLock` (rather than captured as a plain value) so
    /// `update(items:)` can refresh it in place after an embed catch-up
    /// merges new vectors into the live index — the freshened embeddings
    /// reach the tier's over-budget candidate ranking without rebuilding
    /// the tier (and needlessly dropping its cached root session).
    ///
    /// Invariant: a pair's snapshot always has content (ids, blocks)
    /// identical to its tier's own catalog. Every real content change
    /// replaces the whole pair, and
    /// `MetadataIndex.mergingEmbeddings(ids:vectors:embeddedFrom:into:)`
    /// only ever changes stored vectors (hash-guarded), never content — so
    /// refreshing the snapshot after a merge can never make the ranking or
    /// the `item` lookups disagree with the catalog generation the tier
    /// answers over.
    private typealias ConfiguredSelectionTier = (tier: SelectionTier, snapshot: OSAllocatedUnfairLock<MetadataIndex<Item>>)

    /// This searcher's selection tier (plan.md §6) — FoundationModelsRanker's
    /// `SelectionTier` over this searcher's index (its `SelectionCatalog`
    /// conformance), paired with the refreshable index snapshot it ranks
    /// over (see `ConfiguredSelectionTier`) — or `nil` when no
    /// `SelectionConfig` was supplied at `init`; `.selection` throws
    /// `SelectionTierUnavailable` in that case, exactly as it did before a
    /// selection tier existed at all. The snapshot keeps
    /// `Match.item`/`Match.block` consistent even if a concurrent
    /// `update(items:)` swaps `index` while a search is suspended in the
    /// tier. Rebuilt by `update(items:)` on every real catalog change
    /// (plan.md §8): a fresh `SelectionTier` starts with no cached root
    /// session, a prefix assembled from the new index, and an id-enum
    /// grammar derived from the new id set.
    private var selectionTier: ConfiguredSelectionTier?

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
        self.selectionTier = Self.buildSelectionTierIfConfigured(
            config: selection, index: index, weights: weights, embedder: embedder, onDiagnostic: onDiagnostic
        )
    }

    /// Builds FoundationModelsRanker's `SelectionTier` over `index` (its
    /// `SelectionCatalog` conformance) when `config` is non-`nil`, paired
    /// with `index` boxed as the refreshable snapshot the tier's
    /// `retrievalRanking` reads at call time and
    /// `selectionSearch(_:intent:limit:)` re-attaches typed items from
    /// (see `ConfiguredSelectionTier`) — the one piece of tier construction
    /// both the designated initializer and `update(items:)` (plan.md §8,
    /// hot reload) need whenever the underlying index changes: a fresh tier
    /// starts with no cached root session and a prefix assembled from
    /// `index`. The tier's `RankDiagnostic`s are mapped into the same-named
    /// `MetadataDiagnostic` cases, and its `retrievalRanking` closure is
    /// wired to `rankEntireCatalog(intent:index:weights:embedder:
    /// onDiagnostic:)` over the snapshot's current value (each `Match`
    /// reduced to the item-less `SelectionMatch` the tier ranks with).
    ///
    /// `static`, not an instance method: the synchronous designated
    /// initializer builds the pair from its own parameters, and SE-0327's
    /// flow-sensitive actor-init isolation forbids writing `selectionTier`
    /// after any method call on `self` — so an instance-method form could
    /// never be shared with `init` at all.
    ///
    /// - Parameters:
    ///   - config: the selection tier configuration to build against, or
    ///     `nil` when this searcher has no selection tier.
    ///   - index: the catalog index the new tier answers `search(intent:
    ///     limit:)` calls over, and the snapshot's initial value.
    ///   - weights: the per-signal fusion weights `retrievalRanking` scores
    ///     the over-budget candidate ranking with.
    ///   - embedder: the embedder `retrievalRanking` embeds the intent with
    ///     for the cosine signal.
    ///   - onDiagnostic: called for every diagnostic the new tier, and its
    ///     `retrievalRanking` closure, emit.
    /// - Returns: a freshly constructed selection tier over `index`, paired
    ///   with its refreshable snapshot — or `nil` when `config` is `nil`.
    private static func buildSelectionTierIfConfigured(
        config: SelectionConfig?,
        index: MetadataIndex<Item>,
        weights: Weights,
        embedder: (any TextEmbedding)?,
        onDiagnostic: @escaping @Sendable (MetadataDiagnostic) -> Void
    ) -> ConfiguredSelectionTier? {
        guard let config else { return nil }
        let snapshot = OSAllocatedUnfairLock(initialState: index)
        return (
            tier: SelectionTier(
                catalog: index,
                config: config,
                onDiagnostic: { onDiagnostic(MetadataDiagnostic($0)) },
                retrievalRanking: { intent in
                    await Self.rankEntireCatalog(
                        intent: intent,
                        index: snapshot.withLock { $0 },
                        weights: weights,
                        embedder: embedder,
                        onDiagnostic: onDiagnostic
                    ).map { match in
                        SelectionMatch(id: match.id, block: match.block, score: match.score, signals: match.signals)
                    }
                }
            ),
            snapshot: snapshot
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
    ///    tier's candidate ids reflects the new id set. Once the re-embed's
    ///    vectors merge in, the tier's refreshable ranking snapshot is
    ///    updated in place (see `ConfiguredSelectionTier`), so the caught-up
    ///    embeddings reach the over-budget candidate ranking immediately —
    ///    not only after the next content change.
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
    /// finishing, and it reaches the tier through the snapshot refresh
    /// above rather than a rebuild that would pointlessly drop the cached
    /// root session.
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
            selectionTier = Self.buildSelectionTierIfConfigured(
                config: selectionConfig, index: baseline, weights: weights, embedder: embedder, onDiagnostic: onDiagnostic
            )
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
            let merged = MetadataIndex.mergingEmbeddings(ids: pendingEmbedIDs, vectors: vectors, embeddedFrom: baseline, into: index)
            index = merged
            // Refresh the tier's ranking snapshot in place so the freshly
            // merged embeddings reach the over-budget candidate ranking
            // now, not only after the next content change -- without
            // rebuilding the tier, which would drop its cached root session
            // for no reason (nothing content-relevant changed). Safe across
            // the reentrancy above for the same reason the merge is: the
            // merge never changes content, so `merged` always matches the
            // *current* tier's own catalog generation, whichever `update`
            // call installed it.
            selectionTier?.snapshot.withLock { $0 = merged }
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
    /// package's typed `Match<Item>` by looking its id up in the tier's
    /// paired index snapshot — the tier's `SelectionCatalog` carries no item
    /// type, so the typed `item` is re-attached here. The lookup is against
    /// `selection.snapshot` (not the actor's live `index`) so `Match.item`
    /// always pairs with the same catalog generation that produced
    /// `Match.block`, even if a concurrent `update(items:)` swapped the
    /// live index while this call was suspended in the tier (the snapshot's
    /// content always matches the tier's own catalog — see
    /// `ConfiguredSelectionTier`'s invariant). Every id the tier returns
    /// resolves in that snapshot by construction (the tier filters unknown
    /// ids itself); the `compactMap` is defensive.
    ///
    /// - Parameters:
    ///   - selection: the tier to search, paired with the refreshable index
    ///     snapshot it ranks over.
    ///   - intent: the plain-language search intent.
    ///   - limit: the maximum number of matches to return.
    /// - Returns: the selected items' verbatim `Match`es, at most `limit`.
    /// - Throws: whatever the tier's underlying session throws.
    private static func selectionSearch(
        _ selection: ConfiguredSelectionTier,
        intent: String,
        limit: Int
    ) async throws -> [Match<Item>] {
        let selectionMatches = try await selection.tier.search(intent: intent, limit: limit)
        let snapshot = selection.snapshot.withLock { $0 }
        return selectionMatches.compactMap { match in
            guard let item = snapshot.item(forID: match.id) else { return nil }
            return Match(id: match.id, block: match.block, score: match.score, signals: match.signals, item: item)
        }
    }

    // MARK: - Retrieval tier (plan.md §5, via FoundationModelsRanker)

    /// Runs the `.retrieval` tier through FoundationModelsRanker's
    /// `HybridRanker.topMatches(ids:documents:query:cosineScores:weights:
    /// limit:)`: BM25 + trigram + cosine rankings fused and normalized to
    /// `[0, 1]`, mapped back through the catalog to verbatim `Match`es
    /// (plan.md §5). Only ever returns documents at least one signal
    /// actually ranked — contrast `rankEntireCatalog(intent:index:weights:
    /// embedder:onDiagnostic:)`, which the over-budget selection path needs
    /// a full, always-`index.count`-long ordering from.
    private func retrievalSearch(intent: String, limit: Int) async -> [Match<Item>] {
        guard limit > 0, index.count > 0 else { return [] }

        let cosineScores = await Self.computeCosineScores(
            intent: intent, index: index, weights: weights, embedder: embedder, onDiagnostic: onDiagnostic
        )
        let hits = HybridRanker.topMatches(
            ids: index.ids,
            documents: Self.rankedDocuments(in: index),
            query: intent,
            cosineScores: cosineScores,
            weights: weights,
            limit: limit
        )
        return Self.matches(fromHits: hits, in: index)
    }

    // MARK: - Over-budget candidate ranking (plan.md §6)

    /// Ranks the entire catalog for `intent`, best-first, always returning
    /// exactly `index.count` matches through FoundationModelsRanker's
    /// `HybridRanker.fullOrdering(ids:documents:query:cosineScores:weights:)`:
    /// documents any signal actually ranked come first, ordered exactly like
    /// `retrievalSearch(intent:limit:)`'s own fused/normalized ranking;
    /// every other document follows in catalog order, scored `0.0` with
    /// all-absent `Signals` (the absent-signal rule, plan.md §5, extended to
    /// "no signal ranked this document at all"). This is `SelectionTier`'s
    /// over-budget top-M candidate source (`SelectionTier.init(index:config:
    /// onDiagnostic:retrievalRanking:)`) — unlike `retrievalSearch(intent:
    /// limit:)`, which only ever returns real matches, the over-budget path
    /// needs a full ordering so its top-M candidate count is always
    /// `min(candidateLimit, index.count)`, never fewer just because a
    /// query's signal overlap with the catalog happens to be sparse.
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

        let cosineScores = await computeCosineScores(
            intent: intent, index: index, weights: weights, embedder: embedder, onDiagnostic: onDiagnostic
        )
        let hits = HybridRanker.fullOrdering(
            ids: index.ids,
            documents: rankedDocuments(in: index),
            query: intent,
            cosineScores: cosineScores,
            weights: weights
        )
        return matches(fromHits: hits, in: index)
    }

    // MARK: - Shared ranking inputs and Hit -> Match mapping

    /// Every indexed entry's precomputed `RankedDocument`, positionally
    /// aligned with `index.ids` — the `documents` array both `HybridRanker`
    /// entry points score. Every id in `index.ids` resolves by construction
    /// (`ids` is exactly the set `rankedDocument(forID:)` can answer for),
    /// so the `compactMap` never drops anything; `HybridRanker`'s own
    /// `ids.count == documents.count` precondition would trap if that
    /// invariant ever broke.
    ///
    /// - Parameter index: the catalog index to gather documents from.
    /// - Returns: one `RankedDocument` per indexed id, in `ids` order.
    private static func rankedDocuments(in index: MetadataIndex<Item>) -> [RankedDocument] {
        index.ids.compactMap { index.rankedDocument(forID: $0) }
    }

    /// Computes the raw per-document cosine scores `HybridRanker` fuses as
    /// its cosine signal — `intent` embedded through `embedder`, scored
    /// against each catalog entry's stored block embedding via
    /// `CosineScoring.cosineSimilarity(_:_:)` (plan.md §5 "brute-force
    /// scoring — plain per-row dot products for cosine — is exact and
    /// effectively instant" at metadata scale; decision #10, no vector
    /// store) — or `nil` to skip the signal entirely.
    ///
    /// Degrades to keyword-only (`nil`) and reports `.embeddingUnavailable`
    /// via `onDiagnostic` — exactly once per search — whenever cosine can't
    /// contribute: no `embedder` is configured, none of the catalog's items
    /// carry an embedding yet, or embedding the query itself fails
    /// (including a misbehaving embedder returning no vector at all for a
    /// one-element input — a degradation worth reporting, not a silent
    /// skip; plan.md §1 "every degradation is reported, never silent").
    /// A zero `weights.cosine` also returns `nil`, but *without* the
    /// diagnostic: the caller doesn't want the signal, so there's no reason
    /// to embed the query or warn about a missing embedder for it. An item
    /// with no stored embedding scores `0.0` — the absent-signal rule
    /// (plan.md §5): it contributes nothing to cosine but still ranks via
    /// BM25 + trigram.
    ///
    /// - Parameters:
    ///   - intent: the search query.
    ///   - index: the catalog index whose stored embeddings are scored.
    ///   - weights: the per-signal fusion weights (cosine is only computed
    ///     when `weights.cosine > 0.0`).
    ///   - embedder: the embedder to embed `intent` with, or `nil` to
    ///     degrade to keyword-only.
    ///   - onDiagnostic: called with `.embeddingUnavailable` when cosine
    ///     was wanted but can't contribute.
    /// - Returns: one raw cosine score per document, positionally aligned
    ///   with `index.ids`, or `nil` to skip the cosine signal.
    private static func computeCosineScores(
        intent: String,
        index: MetadataIndex<Item>,
        weights: Weights,
        embedder: (any TextEmbedding)?,
        onDiagnostic: @Sendable (MetadataDiagnostic) -> Void
    ) async -> [Double]? {
        // Cosine only runs when configured to actually count: a zero weight
        // means the caller doesn't want the signal, so there's no reason to
        // embed the query or warn about a missing embedder for it.
        guard weights.cosine > 0.0 else { return nil }
        guard let embedder, index.ids.contains(where: { index.embedding(forID: $0) != nil }),
            let queryEmbedding = try? await embedder.embed([intent]).first
        else {
            onDiagnostic(.embeddingUnavailable)
            return nil
        }

        return index.ids.map { id in
            guard let itemEmbedding = index.embedding(forID: id) else { return 0.0 }
            return CosineScoring.cosineSimilarity(queryEmbedding, itemEmbedding)
        }
    }

    /// Maps FoundationModelsRanker's `Hit`s back into this package's typed
    /// `Match<Item>`es by looking each hit's id up in `index` — the id,
    /// fused score, and raw per-signal `Signals` carry over verbatim, and
    /// the catalog's stored block and typed `item` are re-attached here (a
    /// `Hit` carries neither). Every id a hit carries resolves in `index`
    /// by construction (the hits were ranked over `index.ids`); the
    /// `compactMap` is defensive.
    ///
    /// - Parameters:
    ///   - hits: the ranked hits to map, in the order the result preserves.
    ///   - index: the catalog index to look items/blocks up in.
    /// - Returns: one `Match` per resolvable hit, in order.
    private static func matches(fromHits hits: [Hit], in index: MetadataIndex<Item>) -> [Match<Item>] {
        hits.compactMap { hit in
            guard let item = index.item(forID: hit.id), let block = index.block(forID: hit.id) else { return nil }
            return Match(id: hit.id, block: block, score: hit.score, signals: hit.signals, item: item)
        }
    }
}
