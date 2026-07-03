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

    /// The weight applied to the cosine semantic-ranking signal. No embedder
    /// is wired up yet (a later task lands it), so the cosine signal never
    /// ranks anything and this weight has no effect on `.retrieval` results
    /// today.
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

/// Thrown by `MetadataSearcher.search(intent:limit:)` when `mode ==
/// .selection` and no selection tier is configured. The selection tier
/// (plan.md §6, the dynamic Router session) lands in a later task; until
/// then requesting `.selection` explicitly fails loudly rather than silently
/// substituting retrieval.
public struct SelectionTierUnavailable: Error, Sendable, Equatable {
    public init() {}
}

/// Searches a catalog of `SearchableMetadata` on behalf of a Foundation
/// Models session (plan.md §3): an in-memory `MetadataIndex` plus the
/// per-signal `Weights` retrieval fuses by, exposed through one
/// `search(intent:limit:)` entry point.
///
/// Only `.retrieval` is implemented today — BM25 (two fields) + character-
/// trigram Dice, fused by `RRF.fuse(k: 60)` and normalized to `[0, 1]`
/// (plan.md §5). There is no session, no tokens, and no embedder yet, so the
/// cosine signal never ranks anything and every `Match.signals.cosine` is
/// `0.0` — the same "no embedding available" value `Signals.cosine`
/// documents, not a crash or a special case (plan.md §5 "absent-signal
/// rule"). `.selection` and `.auto` are stubs until the selection tier
/// (plan.md §6) lands: `.auto` falls back to `.retrieval` (matching plan.md
/// §7's "selection when a model is configured, else retrieval" — no model is
/// ever configured yet), and explicit `.selection` throws
/// `SelectionTierUnavailable` rather than silently doing something the
/// caller didn't ask for.
public actor MetadataSearcher<Item: SearchableMetadata> {
    /// The in-memory index built from the catalog's items at `init`.
    private let index: MetadataIndex<Item>

    /// The per-signal fusion weights this searcher's retrieval tier uses.
    private let weights: Weights

    /// Which tier `search(intent:limit:)` uses.
    private let mode: SearchMode

    /// Builds a searcher over `items`, indexing them once at `init`.
    ///
    /// - Parameters:
    ///   - items: the catalog's items, in first-seen-wins duplicate-id order
    ///     (forwarded to `MetadataIndex.init(items:onDiagnostic:)`).
    ///   - mode: which tier `search(intent:limit:)` uses. Defaults to
    ///     `.auto`, which falls back to `.retrieval` until a selection tier
    ///     is configured.
    ///   - weights: the per-signal fusion weights for the retrieval tier.
    ///     Defaults to `1.0` for every signal.
    ///   - onDiagnostic: called for every diagnostic emitted while building
    ///     the index (currently only `.duplicateId`), and by later tiers as
    ///     they land. Defaults to logging via `MetadataDiagnostic.log(_:)`.
    public init(
        items: [Item],
        mode: SearchMode = .auto,
        weights: Weights = Weights(),
        onDiagnostic: @Sendable (MetadataDiagnostic) -> Void = { MetadataDiagnostic.log($0) }
    ) {
        self.mode = mode
        self.weights = weights
        self.index = MetadataIndex(items: items, onDiagnostic: onDiagnostic)
    }

    /// Searches the catalog for `intent`, returning at most `limit` matches
    /// ordered by descending fused score.
    ///
    /// - Parameters:
    ///   - intent: the search query.
    ///   - limit: the maximum number of matches to return. `limit <= 0`
    ///     yields an empty result rather than throwing or crashing.
    /// - Returns: `.retrieval`'s fused, `[0, 1]`-normalized matches; the same
    ///   for `.auto` (no selection tier is configured yet).
    /// - Throws: `SelectionTierUnavailable` when `mode == .selection`.
    public func search(intent: String, limit: Int) async throws -> [Match<Item>] {
        switch mode {
        case .retrieval, .auto:
            return retrievalSearch(intent: intent, limit: limit)
        case .selection:
            throw SelectionTierUnavailable()
        }
    }

    // MARK: - Retrieval tier

    /// Runs the `.retrieval` tier: BM25 + trigram rankings fused by
    /// `RRF.fuse(k: 60)`, normalized to `[0, 1]`, mapped back through the
    /// catalog to verbatim `Match`es (plan.md §5).
    private func retrievalSearch(intent: String, limit: Int) -> [Match<Item>] {
        guard limit > 0, index.count > 0 else { return [] }

        let (bm25Ranking, bm25Scores) = computeBM25Ranking(intent: intent)
        let (trigramRanking, trigramScores) = computeTrigramRanking(intent: intent)

        // One (ranking, weight) pair per signal so adding a fourth (cosine,
        // once an embedder lands) is a one-line addition here rather than a
        // third hand-maintained arm.
        let signals: [(ranking: [Int], weight: Double)] = [
            (bm25Ranking, weights.bm25),
            (trigramRanking, weights.trigram),
        ]

        var rankedLists: [[Int]] = []
        var listWeights: [Double] = []
        // Only signals with a positive configured weight AND at least one
        // matching document enter RRF's inputs: an empty ranking would
        // contribute nothing to `fuse` regardless, but leaving its weight out
        // of `normalize`'s ceiling too keeps a perfect single-signal match
        // normalizing to 1.0 instead of being capped below it by an
        // unreachable share (plan.md §5 "absent-signal rule").
        for (ranking, weight) in signals where weight > 0.0 && !ranking.isEmpty {
            rankedLists.append(ranking)
            listWeights.append(weight)
        }

        let fused = RRF.fuse(rankedLists: rankedLists, weights: listWeights)
        let normalized = RRF.normalize(fused: fused, weights: listWeights)

        let orderedDocumentIndices = normalized.keys.sorted { left, right in
            let leftScore = normalized[left] ?? 0.0
            let rightScore = normalized[right] ?? 0.0
            guard leftScore != rightScore else {
                // Deterministic tie-break: first-seen catalog order.
                return left < right
            }
            return leftScore > rightScore
        }

        return orderedDocumentIndices.prefix(limit).compactMap { documentIndex in
            let id = index.ids[documentIndex]
            guard let item = index.item(forId: id), let block = index.block(forId: id) else { return nil }
            return Match(
                id: id,
                block: block,
                score: normalized[documentIndex] ?? 0.0,
                signals: Signals(bm25: bm25Scores[documentIndex], trigram: trigramScores[documentIndex], cosine: 0.0),
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
    private func computeBM25Ranking(intent: String) -> (ranking: [Int], scores: [Double]) {
        let queryTokens = Tokenizer.tokenize(text: intent)
        guard !queryTokens.isEmpty else {
            return ([], [Double](repeating: 0.0, count: index.count))
        }

        let documents = index.ids.map { id in
            (index.documentLength(forId: id) ?? 0, index.termSet(forId: id) ?? [])
        }
        let corpus = BM25Corpus(queryTokens: queryTokens, documents: documents)
        let scores = index.ids.map { id in
            corpus.score(
                weightedTermFrequency: index.weightedTermFrequency(forId: id) ?? [:],
                documentLength: index.documentLength(forId: id) ?? 0,
                queryTokens: queryTokens
            )
        }
        return (rankingOfPositiveScores(scores: scores), scores)
    }

    /// Computes the trigram fuzzy-ranking signal: `intent`'s canonical
    /// trigram set scored against each catalog entry's `id` (weighted
    /// `BM25.idFieldWeight`) and block (weighted `BM25.blockFieldWeight`)
    /// trigram sets — the same two-field weighting BM25 uses, applied to the
    /// trigram aggregate (`Signals.trigram`'s documented "field-weighted
    /// aggregate across several fields").
    ///
    /// - Returns: the matching document indices (into `index.ids`) ranked
    ///   descending by score, and the full-length, positionally aligned raw
    ///   score for every document.
    private func computeTrigramRanking(intent: String) -> (ranking: [Int], scores: [Double]) {
        let querySet = Trigram.canonicalTrigramSet(text: intent)
        let scores = index.ids.map { id -> Double in
            let idTrigramSet = index.idTrigramSet(forId: id) ?? []
            let blockTrigramSet = index.blockTrigramSet(forId: id) ?? []
            return BM25.idFieldWeight * Trigram.dice(querySet: querySet, targetSet: idTrigramSet)
                + BM25.blockFieldWeight * Trigram.dice(querySet: querySet, targetSet: blockTrigramSet)
        }
        return (rankingOfPositiveScores(scores: scores), scores)
    }

    /// The indices of every positive score, descending by score — the
    /// "graceful degradation, no zero-fill" ranked-list shape
    /// `RRF.fuse(rankedLists:weights:k:)` expects: a document that scored
    /// `0.0` (no match at all for this signal) is simply absent from the
    /// list, exactly as if it weren't in the catalog for this signal.
    private func rankingOfPositiveScores(scores: [Double]) -> [Int] {
        scores.indices.filter { scores[$0] > 0.0 }.sorted { scores[$0] > scores[$1] }
    }
}
