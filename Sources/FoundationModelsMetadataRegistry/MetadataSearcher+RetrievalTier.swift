import FoundationModelsExtras
import Tracing

/// The `.retrieval` search tier of `MetadataSearcher` (plan.md §5), through
/// `RetrievalScorer`, which ranks as FoundationModelsRanker's `HybridRanker`.
extension MetadataSearcher {
  /// Runs the `.retrieval` tier over the live `index`.
  ///
  /// The query is embedded first (`queryVector(for:)`), which can suspend.
  /// Then `rankRetrieval(intent:queryVector:limit:over:)` ranks the live
  /// `index` with no suspension, so a concurrent `update(items:)` cannot
  /// change the index during the rank, and the search keeps no copy of the
  /// index across a suspension.
  ///
  /// Internal, not private, because `search(intent:limit:)` lives in its own
  /// file.
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
    let queryVector = await queryVector(for: intent)
    return rankRetrieval(intent: intent, queryVector: queryVector, limit: limit, over: index)
  }

  /// Ranks `index` for `intent` with `RetrievalScorer`, which gives the same
  /// signals, fusion and order as FoundationModelsRanker's
  /// `HybridRanker.topMatches(ids:documents:query:cosineScores:weights:limit:)`.
  ///
  /// The scorer fuses the BM25 + trigram + cosine rankings and normalizes to
  /// `[0, 1]`; the ranked positions map back through the catalog to verbatim
  /// `Match`es (plan.md §5). Only ever returns documents at least one signal
  /// actually ranked.
  ///
  /// The rank runs in one `RegistryTelemetry.SpanName.rank` span, with the
  /// `hybrid` ranker and the count of indexed ids as the candidate count.
  /// The call is synchronous and cannot hang, so the span opens directly on
  /// the tracer and writes no "enter" log record. The call records one
  /// `RegistryTelemetry.MetricName.rankDuration` value with the `hybrid`
  /// ranker. A call with no candidate (`limit <= 0` or an empty catalog)
  /// ranks nothing, so it opens no span, records no rank duration and names
  /// no signal.
  ///
  /// - Parameters:
  ///   - intent: the search query.
  ///   - queryVector: the embedding of the query, or `nil` to rank with no
  ///     cosine signal.
  ///   - limit: the maximum number of matches to return.
  ///   - index: the index to rank. Each `Match` takes its block and its
  ///     `item` from it.
  /// - Returns: the fused matches, with the `retrieval` tier and the
  ///   signals that ranked them.
  func rankRetrieval(
    intent: String,
    queryVector: PreparedQueryVector?,
    limit: Int,
    over index: MetadataIndex<Item>,
  ) -> TierAnswer {
    guard limit > 0, !index.ids.isEmpty else {
      return TierAnswer(tier: .retrieval, signals: [], matches: [])
    }
    let weights = weights
    let scored = RegistryTelemetry.tracer(explicit: nil).withSpan(RegistryTelemetry.SpanName.rank) {
      span in
      span.attributes[RegistryTelemetry.AttributeKey.rankRanker] =
        RegistryTelemetry.Ranker.hybrid.rawValue
      span.attributes[RegistryTelemetry.AttributeKey.rankCandidateCount] = index.ids.count
      return RegistryTelemetry.rankTimer(for: .hybrid).measure {
        RetrievalScorer.topMatches(
          in: index, query: intent, queryVector: queryVector, weights: weights, limit: limit)
      }
    }
    return TierAnswer(
      tier: .retrieval,
      signals: Self.retrievalSignals(weights: weights, rankedCosine: queryVector != nil),
      matches: Self.matches(fromScored: scored, in: index),
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
  ///   - rankedCosine: whether `queryVector(for:)` gave a vector.
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

  // MARK: - The query vector and the Match mapping

  /// Embeds `intent` for the cosine signal, or returns `nil` to skip the
  /// signal entirely.
  ///
  /// The query is scored against each catalog entry's stored embedding with
  /// the arithmetic of `CosineScoring.cosineSimilarity(_:_:)` (plan.md §5;
  /// decision #10, no vector store, no ANN: an exact scan of a contiguous
  /// matrix).
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
  /// with no stored embedding gets no cosine score — the absent-signal rule
  /// (plan.md §5): it gets no cosine rank, but it can still rank through
  /// BM25 + trigram. Each item with an embedding gets its real score, and
  /// each one ranks, also a zero or negative score.
  ///
  /// - Parameter intent: the search query.
  /// - Returns: the prepared query vector, or `nil` to skip the cosine signal.
  func queryVector(for intent: String) async -> PreparedQueryVector? {
    // Cosine only runs when configured to actually count: a zero weight
    // means the caller doesn't want the signal, so there's no reason to
    // embed the query or warn about a missing embedder for it.
    guard weights.cosine > 0.0 else { return nil }
    guard let embedder, index.hasEmbeddings,
      let queryEmbedding = try? await embedder.embed(texts: [intent]).first
    else {
      onDiagnostic(.embeddingUnavailable)
      return nil
    }
    return PreparedQueryVector(queryEmbedding)
  }

  /// Maps the scored positions back into this package's typed `Match<Item>`es.
  ///
  /// The position of each scored entry is looked up in `index` — the
  /// fused score and the raw per-signal `Signals` carry over verbatim, and
  /// the catalog's stored block and typed `item` are attached here. Every
  /// position resolves in `index` by construction (the positions were
  /// ranked over `index`); the `compactMap` is defensive.
  ///
  /// - Parameters:
  ///   - scored: the ranked positions, in the order the result preserves.
  ///   - index: the catalog index the positions were ranked over.
  /// - Returns: one `Match` per resolvable position, in order.
  private static func matches(
    fromScored scored: [RetrievalScorer.ScoredPosition], in index: MetadataIndex<Item>,
  ) -> [Match<Item>] {
    scored.compactMap { hit in
      guard let entry = index.entries[index.slotOrder[hit.position]] else { return nil }
      return Match(
        id: index.ids[hit.position], block: entry.block, score: hit.score, signals: hit.signals,
        item: entry.item)
    }
  }
}
