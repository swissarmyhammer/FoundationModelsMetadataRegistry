/// The keyword statistics of one catalog entry, as text: the input of
/// `DocumentFeatures`.
///
/// It holds the same data as FoundationModelsRanker's
/// `RankedDocument(primaryText: id, bodyText: indexedText)`, made with the same
/// `Tokenizer` and the same canonical trigram rule, so the two give the same
/// scores. It uses no `Lexicon`, so many entries can be prepared in parallel.
struct PreparedFeatures: Sendable {
  /// The weighted term frequency of each term: `BM25.primaryFieldWeight` for
  /// each occurrence in the id, and `BM25.bodyFieldWeight` for each occurrence
  /// in the indexed text. Both weights are whole numbers, so the sum is exact.
  let termWeights: [String: UInt32]

  /// The count of tokens of the id and of the indexed text.
  let length: Int

  /// The canonical trigram set of the id.
  let primaryTrigrams: Set<String>

  /// The canonical trigram set of the indexed text.
  let bodyTrigrams: Set<String>

  /// Tokenizes and trigrams one entry.
  ///
  /// The canonical trigram set of a text is the set of character trigrams of
  /// its tokens joined with one space, which is what
  /// `Trigram.canonicalTrigramSet(text:)` computes. The tokens are computed
  /// one time for both jobs.
  ///
  /// - Parameters:
  ///   - id: the id of the entry, its primary field.
  ///   - indexedText: the indexed text of the entry, its body field.
  init(id: String, indexedText: String) {
    let primaryTokens = Tokenizer.tokenize(text: id)
    let bodyTokens = Tokenizer.tokenize(text: indexedText)
    var weights: [String: UInt32] = [:]
    let primaryWeight = UInt32(BM25.primaryFieldWeight)
    let bodyWeight = UInt32(BM25.bodyFieldWeight)
    for token in primaryTokens { weights[token, default: 0] += primaryWeight }
    for token in bodyTokens { weights[token, default: 0] += bodyWeight }
    termWeights = weights
    length = primaryTokens.count + bodyTokens.count
    primaryTrigrams = Self.canonicalTrigrams(of: primaryTokens)
    bodyTrigrams = Self.canonicalTrigrams(of: bodyTokens)
  }

  /// The canonical trigram set of a text, from its tokens.
  ///
  /// - Parameter tokens: the tokens of the text.
  /// - Returns: the set of character trigrams of the joined tokens.
  static func canonicalTrigrams(of tokens: [String]) -> Set<String> {
    Set(Tokenizer.charTrigrams(text: tokens.joined(separator: " ")))
  }
}

/// The keyword statistics of one catalog entry, as interned ids in one
/// contiguous array.
///
/// The layout of `words`:
///
/// | Words | Content |
/// |---|---|
/// | 0 | the count of distinct terms, `t` |
/// | 1 | the count of id trigrams, `p` |
/// | 2 | the count of body trigrams, `b` |
/// | 3 | the document length |
/// | 4 ..< 4+t | the term ids, ascending |
/// | 4+t ..< 4+2t | the weighted term frequency of each term |
/// | 4+2t ..< 4+2t+p | the id trigram ids, ascending |
/// | 4+2t+p ..< 4+2t+p+b | the body trigram ids, ascending |
///
/// One array for each entry keeps the allocations few, and the persisted form
/// is the same words.
struct DocumentFeatures: Sendable, Equatable {
  /// The count of header words before the lists.
  static let headerCount = 4

  /// The words of the layout above.
  let words: [UInt32]

  /// Makes features from stored words.
  ///
  /// - Parameter words: words in the layout above.
  /// - Returns: the features, or `nil` when the counts in the header do not
  ///   agree with the count of words.
  init?(words: [UInt32]) {
    guard words.count >= Self.headerCount else { return nil }
    let expected =
      Self.headerCount + 2 * Int(words[0]) + Int(words[1]) + Int(words[2])
    guard expected == words.count else { return nil }
    self.words = words
  }

  /// Interns prepared features into `lexicon`.
  ///
  /// - Parameters:
  ///   - prepared: the features as text.
  ///   - lexicon: the lexicon that gives the ids. New terms and trigrams
  ///     get new ids.
  init(_ prepared: PreparedFeatures, interning lexicon: inout Lexicon) {
    let terms = prepared.termWeights.map { (lexicon.internTerm($0.key), $0.value) }
      .sorted { $0.0 < $1.0 }
    let primary = prepared.primaryTrigrams.map { lexicon.internTrigram($0) }.sorted()
    let body = prepared.bodyTrigrams.map { lexicon.internTrigram($0) }.sorted()
    var words: [UInt32] = []
    words.reserveCapacity(Self.headerCount + 2 * terms.count + primary.count + body.count)
    words.append(UInt32(terms.count))
    words.append(UInt32(primary.count))
    words.append(UInt32(body.count))
    words.append(UInt32(prepared.length))
    words.append(contentsOf: terms.map(\.0))
    words.append(contentsOf: terms.map(\.1))
    words.append(contentsOf: primary)
    words.append(contentsOf: body)
    self.words = words
  }

  /// The count of distinct terms.
  var termCount: Int { Int(words[0]) }

  /// The count of id trigrams.
  var primaryTrigramCount: Int { Int(words[1]) }

  /// The count of body trigrams.
  var bodyTrigramCount: Int { Int(words[2]) }

  /// The document length: the count of tokens of the id and of the indexed text.
  var length: Int { Int(words[3]) }

  /// Calls `body` with each term id.
  ///
  /// - Parameter body: the closure to call.
  func forEachTermID(_ body: (UInt32) -> Void) {
    let start = Self.headerCount
    for index in start..<(start + termCount) { body(words[index]) }
  }
}
