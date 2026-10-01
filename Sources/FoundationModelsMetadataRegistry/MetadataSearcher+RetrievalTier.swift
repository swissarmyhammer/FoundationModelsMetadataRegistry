import Tracing

/// The `.retrieval` search tier of `MetadataSearcher` (plan.md §5), through
/// FoundationModelsRanker's `HybridRanker`.
extension MetadataSearcher {
  /// Runs the `.retrieval` tier through FoundationModelsRanker's `HybridRanker.topMatches`.
  ///
  /// `HybridRanker.topMatches(ids:documents:query:cosineScores:weights:
  /// limit:)` fuses the BM25 + trigram + cosine rankings and normalizes to
  /// `[0, 1]`; the hits map back through the catalog to verbatim `Match`es
  /// (plan.md §5). Only ever returns documents at least one signal
  /// actually ranked.
  ///
  /// The `HybridRanker` call runs in one `RegistryTelemetry.SpanName.rank`
  /// span, with the `hybrid` ranker and the count of indexed ids as the
  /// candidate count. The call is synchronous and cannot hang, so the span
  /// opens directly on the tracer and writes no "enter" log record. The
  /// call records one `RegistryTelemetry.MetricName.rankDuration` value
  /// with the `hybrid` ranker. A call with no candidate (`limit <= 0` or
  /// an empty catalog) ranks nothing, so it opens no span, records no rank
  /// duration and names no signal.
  ///
  /// Internal, not private, because `search(intent:limit:)` lives in its
  /// own file.
  ///
  /// - Parameters:
  ///   - intent: the search query.
  ///   - limit: the maximum number of matches to return.
  /// - Returns: the fused matches, with the `retrieval` tier and the
  ///   signals that ranked them.
  func retrievalSearch(intent: String, limit: Int) async -> TierAnswer {
    guard limit > 0, !index.ids.isEmpty else {
      return TierAnswer(tier: .retrieval, signals: [], matches: [])
    }

    let index = index
    let weights = weights
    let cosineScores = await Self.computeCosineScores(
      intent: intent, index: index, weights: weights, embedder: embedder, onDiagnostic: onDiagnostic,
    )
    let hits = RegistryTelemetry.tracer(explicit: nil).withSpan(RegistryTelemetry.SpanName.rank) {
      span in
      span.attributes[RegistryTelemetry.AttributeKey.rankRanker] =
        RegistryTelemetry.Ranker.hybrid.rawValue
      span.attributes[RegistryTelemetry.AttributeKey.rankCandidateCount] = index.ids.count
      return RegistryTelemetry.rankTimer(for: .hybrid).measure {
        HybridRanker.topMatches(
          ids: index.ids,
          documents: Self.rankedDocuments(in: index),
          query: intent,
          cosineScores: cosineScores,
          weights: weights,
          limit: limit,
        )
      }
    }
    return TierAnswer(
      tier: .retrieval,
      signals: Self.retrievalSignals(weights: weights, rankedCosine: cosineScores != nil),
      matches: Self.matches(fromHits: hits, in: index),
    )
  }

  /// The signals that ranked one retrieval search, in the fixed order
  /// `bm25`, `trigram`, `cosine`.
  ///
  /// A keyword signal ranks when its weight is greater than zero. The
  /// cosine signal ranks only when the search computed cosine scores.
  ///
  /// - Parameters:
  ///   - weights: the fusion weights of the search.
  ///   - rankedCosine: whether `computeCosineScores(intent:index:weights:
  ///     embedder:onDiagnostic:)` gave scores.
  /// - Returns: the signals that ranked.
  private static func retrievalSignals(weights: Weights, rankedCosine: Bool) -> [RegistryTelemetry
    .Signal]
  {
    let signals: [(signal: RegistryTelemetry.Signal, ranked: Bool)] = [
      (.bm25, weights.bm25 > 0),
      (.trigram, weights.trigram > 0),
      (.cosine, rankedCosine),
    ]
    return signals.filter(\.ranked).map(\.signal)
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
  private static func matches(fromHits hits: [Hit], in index: MetadataIndex<Item>) -> [Match<Item>]
  {
    hits.compactMap { hit in
      guard let item = index.item(forID: hit.id), let block = index.block(forID: hit.id) else {
        return nil
      }
      return Match(id: hit.id, block: block, score: hit.score, signals: hit.signals, item: item)
    }
  }
}
