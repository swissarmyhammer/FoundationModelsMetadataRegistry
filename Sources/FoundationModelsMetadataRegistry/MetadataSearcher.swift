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
/// trigram Dice + cosine (when an embedder is configured), fused by
/// `RRF.fuse(k: 60)` and normalized to `[0, 1]` (plan.md §5). There is no
/// session, no tokens yet — cosine is real, but selection isn't. Without an
/// `embedder` (or before any catalog item has been embedded), the cosine
/// signal never ranks anything and every `Match.signals.cosine` is `0.0` —
/// the same "no embedding available" value `Signals.cosine` documents, not a
/// crash or a special case (plan.md §5 "absent-signal rule") — and
/// `.embeddingUnavailable` is reported via `onDiagnostic` on every such
/// search, never silently. `.selection` and `.auto` are stubs until the
/// selection tier (plan.md §6) lands: `.auto` falls back to `.retrieval`
/// (matching plan.md §7's "selection when a model is configured, else
/// retrieval" — no model is ever configured yet), and explicit `.selection`
/// throws `SelectionTierUnavailable` rather than silently doing something
/// the caller didn't ask for.
public actor MetadataSearcher<Item: SearchableMetadata> {
    /// The in-memory index built from the catalog's items at `init`.
    private let index: MetadataIndex<Item>

    /// The per-signal fusion weights this searcher's retrieval tier uses.
    private let weights: Weights

    /// Which tier `search(intent:limit:)` uses.
    private let mode: SearchMode

    /// The embedder used to embed the *query* text at search time (plan.md
    /// §5 "only the query itself is embedded per search") — `nil` means no
    /// embedder is configured, so cosine ranking is skipped and every search
    /// degrades to keyword-only. Catalog items are never embedded here; that
    /// happens once, at index-build/update time, via `MetadataIndex.build(
    /// items:embedder:previous:onDiagnostic:)`.
    private let embedder: (any TextEmbedding)?

    /// Called for every diagnostic emitted while building the index and
    /// while searching (currently `.duplicateId`, `.embeddingUnavailable`,
    /// and `.unknownSelectedId`).
    private let onDiagnostic: @Sendable (MetadataDiagnostic) -> Void

    /// This searcher's selection tier (plan.md §6), or `nil` when no
    /// `SelectionConfig` was supplied at `init` — `.selection` throws
    /// `SelectionTierUnavailable` in that case, exactly as it did before a
    /// selection tier existed at all.
    private let selectionTier: SelectionTier<Item>?

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
        self.selectionTier = selection.map { SelectionTier(index: index, config: $0, onDiagnostic: onDiagnostic) }
    }

    /// Searches the catalog for `intent`, returning at most `limit` matches
    /// ordered by descending fused score.
    ///
    /// - Parameters:
    ///   - intent: the search query.
    ///   - limit: the maximum number of matches to return. `limit <= 0`
    ///     yields an empty result rather than throwing or crashing.
    /// - Returns: `.retrieval`'s fused, `[0, 1]`-normalized matches (the same
    ///   for `.auto`, which does not yet resolve to selection — a later
    ///   task); `.selection`'s verbatim, ids-only matches when a selection
    ///   tier is configured (plan.md §6).
    /// - Throws: `SelectionTierUnavailable` when `mode == .selection` and no
    ///   selection tier is configured (`init(..., selection:)`), or when the
    ///   configured tier's assembled prefix is over budget (the one-off
    ///   session path is a later task); otherwise whatever the underlying
    ///   selection session throws.
    public func search(intent: String, limit: Int) async throws -> [Match<Item>] {
        switch mode {
        case .retrieval, .auto:
            return await retrievalSearch(intent: intent, limit: limit)
        case .selection:
            guard let selectionTier else { throw SelectionTierUnavailable() }
            return try await selectionTier.search(intent: intent, limit: limit)
        }
    }

    // MARK: - Retrieval tier

    /// Runs the `.retrieval` tier: BM25 + trigram + cosine rankings fused by
    /// `RRF.fuse(k: 60)`, normalized to `[0, 1]`, mapped back through the
    /// catalog to verbatim `Match`es (plan.md §5).
    private func retrievalSearch(intent: String, limit: Int) async -> [Match<Item>] {
        guard limit > 0, index.count > 0 else { return [] }

        let (bm25Ranking, bm25Scores) = computeBM25Ranking(intent: intent)
        let (trigramRanking, trigramScores) = computeTrigramRanking(intent: intent)
        // Cosine only runs when configured to actually count: a zero weight
        // means the caller doesn't want the signal, so there's no reason to
        // embed the query or warn about a missing embedder for it.
        let (cosineRanking, cosineScores): ([Int], [Double])
        if weights.cosine > 0.0 {
            (cosineRanking, cosineScores) = await computeCosineRanking(intent: intent)
        } else {
            (cosineRanking, cosineScores) = ([], [Double](repeating: 0.0, count: index.count))
        }

        // One (ranking, weight) pair per signal.
        let signals: [(ranking: [Int], weight: Double)] = [
            (bm25Ranking, weights.bm25),
            (trigramRanking, weights.trigram),
            (cosineRanking, weights.cosine),
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
                signals: Signals(
                    bm25: bm25Scores[documentIndex],
                    trigram: trigramScores[documentIndex],
                    cosine: cosineScores[documentIndex]
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
    private func computeCosineRanking(intent: String) async -> (ranking: [Int], scores: [Double]) {
        let zeroScores = [Double](repeating: 0.0, count: index.count)

        guard let embedder, index.ids.contains(where: { index.embedding(forId: $0) != nil }) else {
            onDiagnostic(.embeddingUnavailable)
            return ([], zeroScores)
        }

        let queryEmbedding: [Float]
        do {
            guard let firstVector = try await embedder.embed([intent]).first else {
                // A well-behaved `TextEmbedding` conformer returns exactly
                // one vector per input; an empty result for a one-element
                // input is itself a degradation worth reporting, not a
                // silent empty ranking (plan.md §1 "every degradation is
                // reported, never silent").
                onDiagnostic(.embeddingUnavailable)
                return ([], zeroScores)
            }
            queryEmbedding = firstVector
        } catch {
            onDiagnostic(.embeddingUnavailable)
            return ([], zeroScores)
        }

        let scores = index.ids.map { id -> Double in
            guard let itemEmbedding = index.embedding(forId: id) else { return 0.0 }
            return Self.cosineSimilarity(queryEmbedding, itemEmbedding)
        }
        return (rankingOfPositiveScores(scores: scores), scores)
    }

    /// Cosine similarity between two equal-length vectors: `(a · b) / (|a| |b|)`.
    ///
    /// - Returns: the similarity in `[-1.0, 1.0]`, or `0.0` if the vectors
    ///   differ in length or either has zero magnitude (orthogonal-by-
    ///   convention, matching `Signals.cosine`'s documented `0.0` for "either
    ///   the query or the doc lacks an embedding").
    private static func cosineSimilarity(_ query: [Float], _ target: [Float]) -> Double {
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
    private func rankingOfPositiveScores(scores: [Double]) -> [Int] {
        scores.indices.filter { scores[$0] > 0.0 }.sorted { scores[$0] > scores[$1] }
    }
}
