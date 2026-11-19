import Foundation
import Testing

@testable import FoundationModelsMetadataRegistry

/// `RetrievalScorer` ranks as FoundationModelsRanker's `HybridRanker`: the
/// same ids in the same order, the same fused scores and the same signals,
/// over random catalogs, random queries and random vectors (plan.md §5
/// "Scale": the ranking does not change).
@Suite
struct RetrievalScorerParityTests {
  /// A catalog item with a free id and block.
  struct ParityItem: SearchableMetadata {
    let id: String
    let block: String

    func renderBlock() -> String {
      block
    }
  }

  /// A deterministic random generator (SplitMix64), so a failure repeats.
  struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var value = state
      value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
      value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
      return value ^ (value >> 31)
    }
  }

  /// The words of the random texts: plain words, code identifiers, numbers,
  /// punctuation and non-ASCII words.
  static let words = [
    "deploy", "deployment", "build", "builder", "getUser", "HTTPResponse", "sha256", "utf8",
    "commit", "commits", "push", "pull_request", "merge-conflict", "foo.bar", "don't",
    "kubernetes", "k8s", "café", "naïve", "über", "日本語", "テスト", "error", "errors",
    "search", "searcher", "index", "indexes", "vector", "embed", "embedding", "the", "a",
    "of", "and", "to", "42", "3.14", "-", "--", "...", "x", "yz", "session", "transcript",
  ]

  /// A random text of `count` words.
  static func text(words count: Int, using generator: inout SeededGenerator) -> String {
    (0..<count).map { _ in words.randomElement(using: &generator)! }.joined(separator: " ")
  }

  /// A random catalog of `count` items with blocks of up to `maxWords` words.
  static func catalog(count: Int, maxWords: Int, using generator: inout SeededGenerator)
    -> [ParityItem]
  {
    (0..<count).map { index in
      ParityItem(
        id: "\(words.randomElement(using: &generator)!)-\(index)",
        block: text(words: Int.random(in: 0...maxWords, using: &generator), using: &generator),
      )
    }
  }

  /// Gives about two thirds of the entries of `index` a random vector of
  /// `dimension` floats, and a few entries a vector of another dimension.
  static func embed(
    _ index: inout MetadataIndex<ParityItem>, dimension: Int, using generator: inout SeededGenerator,
  ) {
    for id in index.ids {
      let roll = Int.random(in: 0..<12, using: &generator)
      guard roll < 8 else { continue }
      let size = roll == 0 ? dimension + 1 : roll == 1 ? 0 : dimension
      let vector = (0..<size).map { _ in Float.random(in: -1...1, using: &generator) }
      let digest = index.entry(forID: id)!.digests.embeddedText
      index.setVector(vector, forID: id, embeddedTextDigest: digest)
    }
  }

  /// Asserts that the scorer and `HybridRanker.topMatches` agree on `index`.
  static func expectParity(
    _ index: MetadataIndex<ParityItem>,
    query: String,
    queryVector: [Float]?,
    weights: Weights,
    limit: Int,
  ) {
    let cosineScores = queryVector.map { vector in
      index.ids.map { id in
        index.embedding(forID: id).map { CosineScoring.cosineSimilarity(vector, $0) }
      }
    }
    let hits = HybridRanker.topMatches(
      ids: index.ids,
      documents: index.ids.compactMap { index.rankedDocument(forID: $0) },
      query: query,
      cosineScores: cosineScores,
      weights: weights,
      limit: limit,
    )
    let scored = RetrievalScorer.topMatches(
      in: index, query: query, queryVector: queryVector.map(PreparedQueryVector.init),
      weights: weights, limit: limit)

    #expect(scored.map { index.ids[$0.position] } == hits.map(\.id), "query: \(query)")
    for (mine, theirs) in zip(scored, hits) {
      #expect(abs(mine.score - theirs.score) <= 1e-12, "score of \(theirs.id)")
      #expect(mine.signals.trigram == theirs.signals.trigram, "trigram of \(theirs.id)")
      #expect(mine.signals.cosine == theirs.signals.cosine, "cosine of \(theirs.id)")
      #expect(
        abs(mine.signals.bm25 - theirs.signals.bm25) <= 1e-12 * max(1, abs(theirs.signals.bm25)),
        "bm25 of \(theirs.id)")
    }
  }

  @Test(arguments: [1, 2, 3, 4, 5])
  func agreesWithHybridRankerOnASmallRandomCatalog(seed: UInt64) {
    var generator = SeededGenerator(state: seed)
    var index = MetadataIndex(
      items: Self.catalog(count: 60, maxWords: 30, using: &generator), onDiagnostic: { _ in })
    Self.embed(&index, dimension: 8, using: &generator)
    for _ in 0..<10 {
      let query = Self.text(words: Int.random(in: 0...4, using: &generator), using: &generator)
      let vector = (0..<8).map { _ in Float.random(in: -1...1, using: &generator) }
      Self.expectParity(index, query: query, queryVector: vector, weights: Weights(), limit: 60)
      Self.expectParity(index, query: query, queryVector: nil, weights: Weights(), limit: 7)
      Self.expectParity(
        index, query: query, queryVector: vector,
        weights: Weights(bm25: 0.5, trigram: 0, cosine: 2), limit: 60)
    }
  }

  @Test
  func agreesWithHybridRankerOnACatalogLargeEnoughToScoreInParallel() {
    var generator = SeededGenerator(state: 99)
    var index = MetadataIndex(
      items: Self.catalog(count: 3_000, maxWords: 80, using: &generator), onDiagnostic: { _ in })
    Self.embed(&index, dimension: 16, using: &generator)
    for _ in 0..<4 {
      let query = Self.text(words: Int.random(in: 1...5, using: &generator), using: &generator)
      let vector = (0..<16).map { _ in Float.random(in: -1...1, using: &generator) }
      Self.expectParity(index, query: query, queryVector: vector, weights: Weights(), limit: 3_000)
    }
  }

  @Test
  func agreesWithHybridRankerAfterSomeItemsAreAddedChangedAndRemoved() {
    var generator = SeededGenerator(state: 7)
    let items = Self.catalog(count: 80, maxWords: 25, using: &generator)
    var index = MetadataIndex(items: items, onDiagnostic: { _ in })
    Self.embed(&index, dimension: 4, using: &generator)

    let changed = items.prefix(10).map {
      ParityItem(id: $0.id, block: Self.text(words: 12, using: &generator))
    }
    let added = (0..<10).map {
      ParityItem(id: "added-\($0)", block: Self.text(words: 9, using: &generator))
    }
    index.apply(
      upserting: changed + added, removing: items.suffix(15).map(\.id), onDiagnostic: { _ in })
    // A removed slot is taken again by a later entry.
    index.apply(
      upserting: [ParityItem(id: "late", block: "deploy the searcher")], removing: [],
      onDiagnostic: { _ in })

    for _ in 0..<10 {
      let query = Self.text(words: Int.random(in: 1...4, using: &generator), using: &generator)
      let vector = (0..<4).map { _ in Float.random(in: -1...1, using: &generator) }
      Self.expectParity(index, query: query, queryVector: vector, weights: Weights(), limit: 200)
    }
  }

  @Test
  func theFieldWeightsAreWholeNumbersSoTheStoredTermFrequenciesAreExact() {
    #expect(BM25.primaryFieldWeight == BM25.primaryFieldWeight.rounded())
    #expect(BM25.bodyFieldWeight == BM25.bodyFieldWeight.rounded())
  }
}
