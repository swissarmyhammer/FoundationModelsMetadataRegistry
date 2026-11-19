import Foundation

/// The `.retrieval` ranking of a `MetadataIndex`: the same signals, the same
/// fusion and the same order as FoundationModelsRanker's
/// `HybridRanker.topMatches(ids:documents:query:cosineScores:weights:limit:)`
/// over the `RankedDocument` of each entry, computed from the compact
/// columns of the index (plan.md §5 "Scale").
///
/// - BM25: `BM25Corpus` over all entries, with the document frequencies and
///   the total length kept as counters (`Lexicon`), and the same formula and
///   constants (`BM25.k1`, `BM25.b`, the two field weights).
/// - Trigram: `BM25.primaryFieldWeight * dice(id) + BM25.bodyFieldWeight *
///   dice(body)`, with the same canonical trigram sets, as intersections of
///   sorted id lists.
/// - Cosine: `CosineScoring.cosineSimilarity` with the same sequential
///   `Float` arithmetic, over the matrix rows (`EmbeddingMatrix`).
/// - The rankings, `RRF.fuse`'s arithmetic, `RRF.normalize`'s ceiling and the
///   tie-break by catalog position are those of `HybridRanker`.
///
/// The one difference: `BM25Corpus.score` adds the terms of the query in
/// the order of a `Set`, which changes from process to process. This scorer
/// adds them in the order of their first occurrence in the query. A BM25 sum
/// can thus differ in its last bits, as it can between two processes.
///
/// The scan over the entries runs on all cores (`ParallelWork`).
enum RetrievalScorer {
  /// One ranked position of the catalog.
  struct ScoredPosition: Sendable, Equatable {
    /// The position in `MetadataIndex.ids`.
    let position: Int

    /// The fused score, normalized to `[0, 1]`.
    let score: Double

    /// The raw score of each signal.
    let signals: Signals
  }

  /// The terms of one query that some entry contains, with their IDF.
  private struct QueryTerm: Sendable {
    /// The term id.
    let id: UInt32

    /// The inverse document frequency of the term.
    let idf: Double
  }

  /// Ranks `index` for `query`.
  ///
  /// - Parameters:
  ///   - index: the index to rank.
  ///   - query: the search query.
  ///   - queryVector: the embedding of the query, or `nil` to rank with no
  ///     cosine signal (as `HybridRanker` with `cosineScores: nil`).
  ///   - weights: the fusion weights.
  ///   - limit: the maximum count of positions to return.
  /// - Returns: at most `limit` ranked positions, best first. Only positions
  ///   that at least one fused signal ranked.
  static func topMatches<Item>(
    in index: MetadataIndex<Item>,
    query: String,
    queryVector: PreparedQueryVector?,
    weights: Weights,
    limit: Int,
  ) -> [ScoredPosition] {
    let count = index.count
    guard limit > 0, count > 0 else { return [] }

    let terms = queryTerms(query, in: index)
    let averageLength = Double(index.lexicon.totalLength) / Double(count)
    let trigramSet = Trigram.canonicalTrigramSet(text: query)
    let trigramIDs = trigramSet.compactMap { index.lexicon.trigramID($0) }.sorted()
    let queryTrigramCount = trigramSet.count

    let bm25 = UnsafeMutableBufferPointer<Double>.allocate(capacity: count)
    let trigram = UnsafeMutableBufferPointer<Double>.allocate(capacity: count)
    let cosine = UnsafeMutableBufferPointer<Double>.allocate(capacity: count)
    let hasCosine = UnsafeMutableBufferPointer<Bool>.allocate(capacity: count)
    defer {
      bm25.deallocate()
      trigram.deallocate()
      cosine.deallocate()
      hasCosine.deallocate()
    }
    let outputs = (
      bm25: SendableBuffer(bm25), trigram: SendableBuffer(trigram),
      cosine: SendableBuffer(cosine), hasCosine: SendableBuffer(hasCosine)
    )

    ParallelWork.forEachChunk(count: count) { range in
      for position in range {
        let slot = index.slotOrder[position]
        guard let entry = index.entries[slot] else {
          preconditionFailure("RetrievalScorer: a position names a free slot")
        }
        entry.features.words.withUnsafeBufferPointer { words in
          outputs.bm25[position] = bm25Score(
            words, terms: terms, averageLength: averageLength)
          outputs.trigram[position] = trigramScore(
            words, queryIDs: trigramIDs, queryCount: queryTrigramCount)
        }
        if let queryVector, let score = index.vectors.cosineScore(slot: slot, query: queryVector) {
          outputs.cosine[position] = score
          outputs.hasCosine[position] = true
        } else {
          outputs.cosine[position] = 0.0
          outputs.hasCosine[position] = false
        }
      }
    }

    let rankings: [(ranking: [Int], weight: Double)] = [
      (ranking(count: count) { bm25[$0] > 0.0 ? bm25[$0] : nil }, weights.bm25),
      (ranking(count: count) { trigram[$0] > 0.0 ? trigram[$0] : nil }, weights.trigram),
      (
        queryVector == nil ? [] : ranking(count: count) { hasCosine[$0] ? cosine[$0] : nil },
        weights.cosine
      ),
    ]
    let fused = fuseAndNormalize(rankings, count: count)
    return fused.order.prefix(limit).map { position in
      ScoredPosition(
        position: position,
        score: fused.scores[position],
        signals: Signals(
          bm25: bm25[position], trigram: trigram[position], cosine: cosine[position]),
      )
    }
  }

  /// The distinct terms of `query` that some entry contains, in the order of
  /// their first occurrence, with their IDF as `BM25Corpus` computes it.
  ///
  /// A term that no entry contains scores nothing in any entry, so it is
  /// left out.
  private static func queryTerms<Item>(_ query: String, in index: MetadataIndex<Item>)
    -> [QueryTerm]
  {
    let documentCount = Double(index.count)
    var seen = Set<String>()
    return Tokenizer.tokenize(text: query).compactMap { token in
      guard seen.insert(token).inserted, let id = index.lexicon.termID(token) else { return nil }
      let df = Double(index.lexicon.documentFrequency[Int(id)])
      guard df > 0 else { return nil }
      return QueryTerm(id: id, idf: log(1.0 + (documentCount - df + 0.5) / (df + 0.5)))
    }
  }

  /// The BM25 score of one entry, as `BM25Corpus.score` computes it.
  private static func bm25Score(
    _ words: UnsafeBufferPointer<UInt32>,
    terms: [QueryTerm],
    averageLength: Double,
  ) -> Double {
    guard !terms.isEmpty, averageLength > 0 else { return 0.0 }
    let termCount = Int(words[0])
    let documentLength = Double(words[3])
    let lengthNorm = BM25.k1 * (1.0 - BM25.b + BM25.b * documentLength / averageLength)
    let idsStart = DocumentFeatures.headerCount
    var total = 0.0
    for term in terms {
      guard let offset = find(term.id, in: words, from: idsStart, to: idsStart + termCount)
      else { continue }
      let termFrequency = Double(words[offset + termCount])
      guard termFrequency != 0.0 else { continue }
      total = total + term.idf * termFrequency * (BM25.k1 + 1.0) / (termFrequency + lengthNorm)
    }
    return total
  }

  /// The trigram score of one entry, as `HybridRanker` computes it.
  private static func trigramScore(
    _ words: UnsafeBufferPointer<UInt32>,
    queryIDs: [UInt32],
    queryCount: Int,
  ) -> Double {
    let termCount = Int(words[0])
    let primaryCount = Int(words[1])
    let bodyCount = Int(words[2])
    let primaryStart = DocumentFeatures.headerCount + 2 * termCount
    let bodyStart = primaryStart + primaryCount
    let primaryShared = intersectionCount(
      queryIDs, words, from: primaryStart, to: primaryStart + primaryCount)
    let bodyShared = intersectionCount(queryIDs, words, from: bodyStart, to: bodyStart + bodyCount)
    return BM25.primaryFieldWeight
      * dice(shared: primaryShared, queryCount: queryCount, targetCount: primaryCount)
      + BM25.bodyFieldWeight
      * dice(shared: bodyShared, queryCount: queryCount, targetCount: bodyCount)
  }

  /// The Dice coefficient, as `Trigram.dice(querySet:targetSet:)` computes it.
  private static func dice(shared: Int, queryCount: Int, targetCount: Int) -> Double {
    guard queryCount > 0, targetCount > 0 else { return 0.0 }
    return 2.0 * Double(shared) / Double(queryCount + targetCount)
  }

  /// The count of `sortedIDs` that are in `words[from..<to]`, which is sorted.
  private static func intersectionCount(
    _ sortedIDs: [UInt32],
    _ words: UnsafeBufferPointer<UInt32>,
    from start: Int,
    to end: Int,
  ) -> Int {
    var shared = 0
    var low = start
    for id in sortedIDs {
      low = lowerBound(id, in: words, from: low, to: end)
      guard low < end else { break }
      if words[low] == id {
        shared += 1
        low += 1
      }
    }
    return shared
  }

  /// The index of `id` in `words[from..<to]`, which is sorted, or `nil`.
  private static func find(
    _ id: UInt32, in words: UnsafeBufferPointer<UInt32>, from start: Int, to end: Int,
  ) -> Int? {
    let index = lowerBound(id, in: words, from: start, to: end)
    return index < end && words[index] == id ? index : nil
  }

  /// The first index of `words[from..<to]`, which is sorted, whose value is
  /// not less than `id`.
  private static func lowerBound(
    _ id: UInt32, in words: UnsafeBufferPointer<UInt32>, from start: Int, to end: Int,
  ) -> Int {
    var low = start
    var high = end
    while low < high {
      let middle = (low + high) / 2
      if words[middle] < id { low = middle + 1 } else { high = middle }
    }
    return low
  }

  /// The positions that `score` gives a score, in `HybridRanker`'s order:
  /// descending score, then ascending position.
  private static func ranking(count: Int, _ score: (Int) -> Double?) -> [Int] {
    var scored: [(score: Double, position: Int)] = []
    for position in 0..<count {
      if let value = score(position) { scored.append((value, position)) }
    }
    scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.position < $1.position }
    return scored.map(\.position)
  }

  /// Fuses the rankings as `HybridRanker` does: only a signal with a positive
  /// weight and at least one ranked position enters `RRF.fuse`'s arithmetic
  /// and `RRF.normalize`'s ceiling.
  ///
  /// - Parameters:
  ///   - rankings: the ranking and the weight of each signal, in the order
  ///     BM25, trigram, cosine.
  ///   - count: the count of positions.
  /// - Returns: the normalized score of each position, and the fused
  ///   positions by descending score, then ascending position.
  private static func fuseAndNormalize(
    _ rankings: [(ranking: [Int], weight: Double)],
    count: Int,
  ) -> (scores: [Double], order: [Int]) {
    var fused = [Double](repeating: 0.0, count: count)
    var ranked = [Bool](repeating: false, count: count)
    var weights: [Double] = []
    for (ranking, weight) in rankings where weight > 0.0 && !ranking.isEmpty {
      weights.append(weight)
      for (rank, position) in ranking.enumerated() {
        fused[position] += weight / (RRF.k + Double(rank))
        ranked[position] = true
      }
    }
    let maximum = weights.reduce(0.0) { $0 + $1 / RRF.k }
    let scores = maximum == 0.0 ? fused.map { _ in 0.0 } : fused.map { $0 / maximum }
    var order = (0..<count).filter { ranked[$0] }
    order.sort { scores[$0] != scores[$1] ? scores[$0] > scores[$1] : $0 < $1 }
    return (scores, order)
  }
}
