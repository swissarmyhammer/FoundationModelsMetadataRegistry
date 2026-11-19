/// The interned vocabularies of one `MetadataIndex`, and the corpus counters
/// that the BM25 signal reads.
///
/// Each distinct term and each distinct character trigram gets one dense
/// `UInt32` id, the first time an entry uses it. An entry keeps its terms and
/// its trigrams as sorted id lists (see `DocumentFeatures`), not as sets of
/// strings, so a catalog of 100,000 items fits in memory and a search compares
/// integers.
///
/// The ids are never given back: a term that no live entry uses keeps its id
/// and its document frequency of zero. A new snapshot of a persisted catalog
/// keeps the same vocabularies, so the ids in the snapshot stay valid.
struct Lexicon: Sendable {
  /// The id of each term.
  private(set) var termIDs: [String: UInt32] = [:]

  /// The text of each term, by id.
  private(set) var terms: [String] = []

  /// The count of live entries that contain each term, by term id.
  ///
  /// This is the document frequency of `BM25Corpus`, kept as a counter so
  /// that a search does not count it again.
  private(set) var documentFrequency: [UInt32] = []

  /// The id of each character trigram.
  private(set) var trigramIDs: [String: UInt32] = [:]

  /// The text of each character trigram, by id.
  private(set) var trigrams: [String] = []

  /// The sum of the document lengths of the live entries, in tokens.
  ///
  /// With the count of live entries, this gives the average document length
  /// of `BM25Corpus`.
  private(set) var totalLength = 0

  /// Makes an empty lexicon.
  init() {}

  /// Makes a lexicon from stored vocabularies, with zero counters.
  ///
  /// The counters come back as each stored entry is added again with
  /// `count(_:)`.
  ///
  /// - Parameters:
  ///   - terms: the text of each term, by id.
  ///   - trigrams: the text of each trigram, by id.
  init(terms: [String], trigrams: [String]) {
    self.terms = terms
    self.trigrams = trigrams
    termIDs = Dictionary(
      terms.enumerated().map { ($1, UInt32($0)) }, uniquingKeysWith: { first, _ in first })
    trigramIDs = Dictionary(
      trigrams.enumerated().map { ($1, UInt32($0)) }, uniquingKeysWith: { first, _ in first })
    documentFrequency = [UInt32](repeating: 0, count: terms.count)
  }

  /// The id of `term`, or `nil` when no entry used it.
  ///
  /// - Parameter term: the term to look up.
  /// - Returns: the id of the term, or `nil`.
  func termID(_ term: String) -> UInt32? {
    termIDs[term]
  }

  /// The id of `trigram`, or `nil` when no entry used it.
  ///
  /// - Parameter trigram: the trigram to look up.
  /// - Returns: the id of the trigram, or `nil`.
  func trigramID(_ trigram: String) -> UInt32? {
    trigramIDs[trigram]
  }

  /// Returns the id of `term`, and gives it a new id the first time.
  ///
  /// - Parameter term: the term to intern.
  /// - Returns: the id of the term.
  mutating func internTerm(_ term: String) -> UInt32 {
    if let id = termIDs[term] { return id }
    let id = UInt32(terms.count)
    termIDs[term] = id
    terms.append(term)
    documentFrequency.append(0)
    return id
  }

  /// Returns the id of `trigram`, and gives it a new id the first time.
  ///
  /// - Parameter trigram: the trigram to intern.
  /// - Returns: the id of the trigram.
  mutating func internTrigram(_ trigram: String) -> UInt32 {
    if let id = trigramIDs[trigram] { return id }
    let id = UInt32(trigrams.count)
    trigramIDs[trigram] = id
    trigrams.append(trigram)
    return id
  }

  /// Adds the terms and the length of one live entry to the counters.
  ///
  /// - Parameter features: the features of the entry.
  mutating func count(_ features: DocumentFeatures) {
    features.forEachTermID { documentFrequency[Int($0)] += 1 }
    totalLength += features.length
  }

  /// Removes the terms and the length of one entry from the counters.
  ///
  /// - Parameter features: the features of the entry, as they were counted.
  mutating func uncount(_ features: DocumentFeatures) {
    features.forEachTermID { documentFrequency[Int($0)] -= 1 }
    totalLength -= features.length
  }
}
