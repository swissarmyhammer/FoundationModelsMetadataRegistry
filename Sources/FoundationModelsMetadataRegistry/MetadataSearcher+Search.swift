/// Hot reload, first-search embed catch-up, and the `.selection`/`.retrieval`
/// search tiers for `MetadataSearcher` (plan.md §5, §6, §8).
extension MetadataSearcher {
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
    ///    total:)`. This call also takes over the first-search catch-up of a
    ///    synchronously built searcher (see `FirstSearchCatchUp`): once a
    ///    reload owns the embedding, a search that lands in this interim
    ///    window serves keyword-only rather than embedding the same pending
    ///    blocks a second time.
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
    /// finishing, and a rebuild would pointlessly drop the cached root
    /// session.
    ///
    /// - Parameter items: the catalog's new/refreshed items, in first-seen-
    ///   wins duplicate-id order (forwarded to `MetadataIndex`'s duplicate-id
    ///   policy).
    public func update(items: [Item]) async {
        // A reload owns the catch-up from here on: whatever this call leaves
        // pending is served keyword-only in the interim and embedded by this
        // call (or the next reload), never by a first search embedding the
        // same blocks a second time behind it.
        firstSearchCatchUp = .done
        let previous = index
        let result = MetadataIndex.incrementalBaseline(
            items: items,
            previous: previous,
            onDiagnostic: onDiagnostic,
        )
        let baseline = result.baseline

        let contentChanged = !baseline.hasIdenticalContent(to: previous)
        guard contentChanged || !result.pendingEmbedIDs.isEmpty else { return }

        index = baseline
        // Only a genuine content change warrants dropping the cached root
        // session -- catching up an embedding for otherwise-unchanged
        // content doesn't affect keyword search or the selection prefix at
        // all, so forcing a re-prefill for it would be pure waste.
        if contentChanged {
            selectionTier = Self.buildSelectionTierIfConfigured(
                config: selectionConfig, index: baseline, onDiagnostic: onDiagnostic,
            )
        }

        guard !result.pendingEmbedIDs.isEmpty, let embedder else { return }
        await catchUpEmbeddings(
            ids: result.pendingEmbedIDs, texts: result.textsToEmbed, embeddedFrom: baseline, with: embedder,
        )
    }

    /// Embeds `texts` through `embedder`, then merges the vectors into the live `index` under `ids`.
    ///
    /// The one place a catch-up batch lands, shared by `update(items:)` and
    /// the first-search catch-up (`runFirstSearchCatchUp()`). Reports the
    /// pending/total gap via `.embedCatchUp` before the embedder call, once.
    ///
    /// Merges into `index` as it stands *after* the suspension -- not into
    /// the stale `baseline` this batch was embedded from -- and only where
    /// `index`'s current entry still matches `baseline`'s block hash for
    /// that id (`MetadataIndex.mergingEmbeddings(ids:vectors:embeddedFrom:
    /// into:)`'s hash check). A concurrent `update(items:)` call may have
    /// moved the catalog on in the meantime (actor reentrancy across the
    /// `await`); its result must win, never be silently clobbered by this
    /// call's now-stale vector finishing late -- including when that
    /// concurrent call re-embedded the *same* id with different content,
    /// not just when it removed the id outright.
    ///
    /// The selection tier is left alone. A merge changes stored vectors and
    /// never content, and the tier ranks nothing, so a caught-up embedding
    /// changes no answer the tier can give.
    ///
    /// An embedder that throws, or returns a vector count other than
    /// `ids.count`, leaves every entry with whatever embedding it had --
    /// graceful degradation, the same as `MetadataIndex.build(items:
    /// embedder:previous:onDiagnostic:)`; a later search then reports the
    /// still-absent embeddings via `.embeddingUnavailable`.
    ///
    /// - Parameters:
    ///   - ids: the ids to embed, positionally aligned with `texts`.
    ///   - texts: the rendered blocks to embed, one per id.
    ///   - baseline: the index this batch was read from -- `ids`' block
    ///     hashes there are what `index`'s current entries must still match
    ///     for the merge to apply.
    ///   - embedder: the embedder to embed `texts` with.
    private func catchUpEmbeddings(
        ids: [String],
        texts: [String],
        embeddedFrom baseline: MetadataIndex<Item>,
        with embedder: any TextEmbedding,
    ) async {
        onDiagnostic(.embedCatchUp(pending: ids.count, total: baseline.count))
        guard let vectors = try? await embedder.embed(texts), vectors.count == ids.count else { return }
        let merged = MetadataIndex.mergingEmbeddings(ids: ids, vectors: vectors, embeddedFrom: baseline, into: index)
        index = merged
    }

    /// Searches the catalog for `intent`, returning at most `limit` matches ordered by descending fused score.
    ///
    /// The first call on a searcher built synchronously with an embedder
    /// embeds every not-yet-embedded catalog entry before it ranks, one
    /// time, whichever tier `mode` selects (see `FirstSearchCatchUp`); every
    /// later call ranks straight away.
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
        await catchUpEmbeddingsBeforeFirstSearch()
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

    // MARK: - First-search embed catch-up (plan.md §5, §8)

    /// Runs the first-search catch-up (see `FirstSearchCatchUp`) if it is still pending, or awaits the one in flight.
    ///
    /// Returns at once when the catch-up is `.done`. The stored `Task` is
    /// what makes two searches that arrive before the first embed resolves
    /// share one embedder call: the second one awaits the first one's task
    /// instead of embedding the same blocks again. The task is created here,
    /// stored in `firstSearchCatchUp`, and awaited by every caller, so it
    /// never outlives the catch-up it runs.
    private func catchUpEmbeddingsBeforeFirstSearch() async {
        switch firstSearchCatchUp {
        case .done:
            return
        case let .running(task):
            await task.value
        case .pending:
            let task = Task { await self.runFirstSearchCatchUp() }
            firstSearchCatchUp = .running(task)
            await task.value
        }
    }

    /// Embeds every catalog entry that carries no embedding yet, then marks the first-search catch-up `.done`.
    ///
    /// A no-op -- no diagnostic, no embedder call -- when no embedder is
    /// configured or nothing is pending (an index the async initializer
    /// already embedded), so a searcher that needs no catch-up pays nothing
    /// beyond this check on its first search. Marks `.done` on every exit,
    /// a transient embed failure included: the catch-up runs one time, and
    /// the next `update(items:)` retries whatever is still pending.
    private func runFirstSearchCatchUp() async {
        defer { firstSearchCatchUp = .done }
        guard let embedder else { return }
        let pending = index.pendingEmbeddings()
        guard !pending.ids.isEmpty else { return }
        await catchUpEmbeddings(ids: pending.ids, texts: pending.texts, embeddedFrom: index, with: embedder)
    }

    // MARK: - Selection tier (plan.md §6, via FoundationModelsRanker)

    /// Answers one `.selection`/`.auto` search through FoundationModelsRanker's `SelectionTier`.
    ///
    /// Maps each returned `SelectionMatch` into this
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
    ///   - selection: the tier to search, paired with the index snapshot it
    ///     answers over.
    ///   - intent: the plain-language search intent.
    ///   - limit: the maximum number of matches to return.
    /// - Returns: the selected items' verbatim `Match`es, at most `limit`.
    /// - Throws: whatever the tier's underlying session throws.
    private static func selectionSearch(
        _ selection: ConfiguredSelectionTier,
        intent: String,
        limit: Int,
    ) async throws -> [Match<Item>] {
        let selectionMatches = try await selection.tier.search(intent: intent, limit: limit)
        let snapshot = selection.snapshot
        return selectionMatches.compactMap { match in
            guard let item = snapshot.item(forID: match.id) else { return nil }
            return Match(id: match.id, block: match.block, score: match.score, signals: match.signals, item: item)
        }
    }

    // MARK: - Retrieval tier (plan.md §5, via FoundationModelsRanker)

    /// Runs the `.retrieval` tier through FoundationModelsRanker's `HybridRanker.topMatches`.
    ///
    /// `HybridRanker.topMatches(ids:documents:query:cosineScores:weights:
    /// limit:)` fuses the BM25 + trigram + cosine rankings and normalizes to
    /// `[0, 1]`; the hits map back through the catalog to verbatim `Match`es
    /// (plan.md §5). Only ever returns documents at least one signal
    /// actually ranked.
    private func retrievalSearch(intent: String, limit: Int) async -> [Match<Item>] {
        guard limit > 0, !index.ids.isEmpty else { return [] }

        let cosineScores = await Self.computeCosineScores(
            intent: intent, index: index, weights: weights, embedder: embedder, onDiagnostic: onDiagnostic,
        )
        let hits = HybridRanker.topMatches(
            ids: index.ids,
            documents: Self.rankedDocuments(in: index),
            query: intent,
            cosineScores: cosineScores,
            weights: weights,
            limit: limit,
        )
        return Self.matches(fromHits: hits, in: index)
    }

    // MARK: - Shared ranking inputs and Hit -> Match mapping

    /// Every indexed entry's precomputed `RankedDocument`, positionally aligned with `index.ids`.
    ///
    /// This is the `documents` array `HybridRanker.topMatches` scores.
    /// Every id in `index.ids` resolves by construction
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
    /// its cosine signal, or `nil` to skip the signal entirely.
    ///
    /// `intent` is embedded through `embedder` and scored
    /// against each catalog entry's stored block embedding via
    /// `CosineScoring.cosineSimilarity(_:_:)` (plan.md §5 "brute-force
    /// scoring — plain per-row dot products for cosine — is exact and
    /// effectively instant" at metadata scale; decision #10, no vector
    /// store).
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
        onDiagnostic: @Sendable (MetadataDiagnostic) -> Void,
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

    /// Maps FoundationModelsRanker's `Hit`s back into this package's typed `Match<Item>`es.
    ///
    /// Each hit's id is looked up in `index` — the id,
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
