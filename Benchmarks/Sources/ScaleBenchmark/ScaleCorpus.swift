import Foundation
import FoundationModelsExtras
import FoundationModelsMetadataRegistry

/// One chunk of a session transcript: the item kind of the session search of
/// D207, with a text of at most 2,000 characters.
struct ChunkItem: SearchableMetadata, Codable {
  /// The id, `<session>/<ordinal>`.
  let id: String

  /// The text of the chunk.
  let text: String

  func renderBlock() -> String {
    text
  }
}

/// A deterministic random generator (SplitMix64), so each run makes the same
/// corpus.
struct SplitMix64: RandomNumberGenerator {
  /// The state.
  var state: UInt64

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var value = state
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }
}

/// The synthetic corpus of the cost gate.
///
/// The words follow a Zipf distribution over a vocabulary of 20,000 made-up
/// words, with some code identifiers, paths and numbers, as in the
/// transcripts of agent sessions. Each text has a random length from 500 to
/// 2,000 characters.
enum ScaleCorpus {
  /// The count of distinct plain words.
  static let vocabularySize = 20_000

  /// The shortest and the longest text, in characters.
  static let textLength = 500...2_000

  /// The made-up plain words, most frequent first.
  static let vocabulary: [String] = {
    let syllables = [
      "ka", "lo", "mi", "ne", "ru", "sa", "te", "vi", "zo", "pa", "de", "fi", "gu", "ha", "jo",
      "bri", "sto", "pla", "cre", "dro", "ex", "in", "un", "re", "or", "an", "el", "is", "at",
    ]
    var generator = SplitMix64(state: 1)
    var words = Set<String>()
    var ordered: [String] = []
    while ordered.count < vocabularySize {
      let count = Int.random(in: 1...4, using: &generator)
      let word = (0..<count).map { _ in syllables.randomElement(using: &generator)! }.joined()
      if words.insert(word).inserted { ordered.append(word) }
    }
    return ordered
  }()

  /// The cumulative Zipf weights of `vocabulary`.
  static let cumulativeWeights: [Double] = {
    var total = 0.0
    return (1...vocabularySize).map { rank in
      total += 1.0 / Double(rank)
      return total
    }
  }()

  /// One random plain word, by the Zipf distribution.
  static func word(using generator: inout SplitMix64) -> String {
    let target = Double.random(in: 0..<cumulativeWeights.last!, using: &generator)
    var low = 0
    var high = cumulativeWeights.count - 1
    while low < high {
      let middle = (low + high) / 2
      if cumulativeWeights[middle] <= target { low = middle + 1 } else { high = middle }
    }
    return vocabulary[low]
  }

  /// One random token: mostly a plain word, sometimes an identifier, a path
  /// or a number.
  static func token(using generator: inout SplitMix64) -> String {
    switch Int.random(in: 0..<20, using: &generator) {
    case 0:
      return word(using: &generator) + word(using: &generator).capitalized
    case 1:
      return "/\(word(using: &generator))/\(word(using: &generator)).swift"
    case 2:
      return String(Int.random(in: 0..<100_000, using: &generator))
    default:
      return word(using: &generator)
    }
  }

  /// One random text of a random length in `textLength`.
  static func text(using generator: inout SplitMix64) -> String {
    let target = Int.random(in: textLength, using: &generator)
    var text = ""
    text.reserveCapacity(target + 32)
    while text.count < target {
      if !text.isEmpty {
        text += Int.random(in: 0..<12, using: &generator) == 0 ? ". " : " "
      }
      text += token(using: &generator)
    }
    return String(text.prefix(textLength.upperBound))
  }

  /// The items of the corpus: `count` chunks, 20 for each session.
  ///
  /// - Parameters:
  ///   - count: the count of items.
  ///   - seed: the seed of the generator.
  /// - Returns: the items.
  static func items(count: Int, seed: UInt64) -> [ChunkItem] {
    var generator = SplitMix64(state: seed)
    return (0..<count).map { index in
      ChunkItem(id: "session-\(index / 20)/\(index % 20)", text: text(using: &generator))
    }
  }

  /// The queries of the search measurement: one to four words, from the
  /// frequent words to the rare words, and one identifier.
  static func queries(using generator: inout SplitMix64) -> [String] {
    var queries: [String] = []
    for wordCount in 1...4 {
      for _ in 0..<3 {
        queries.append(
          (0..<wordCount).map { _ in word(using: &generator) }.joined(separator: " "))
      }
    }
    queries.append(vocabulary[vocabularySize - 1])
    queries.append("\(vocabulary[3])\(vocabulary[7].capitalized) failed")
    return queries
  }
}

/// A fast deterministic embedder: the vector of a text is a function of the
/// SHA-free hash of its UTF-8 bytes. It stands for the model of the
/// `embedding` slot (embeddinggemma-300m), with its dimension, and costs
/// almost nothing, so the measurements show the registry alone.
struct HashEmbedder: PooledEmbedding {
  /// The dimension of embeddinggemma-300m.
  static let dimension = 768

  /// Counts the texts of the calls with more than one text: the catalog
  /// embeds, not the query embeds.
  let catalogTexts = CatalogTextCounter()

  func embed(texts: [String]) async throws -> [[Float]] {
    if texts.count > 1 { catalogTexts.add(texts.count) }
    return texts.map(Self.vector)
  }

  /// The vector of one text.
  static func vector(_ text: String) -> [Float] {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in text.utf8 {
      hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
    }
    var generator = SplitMix64(state: hash)
    return (0..<dimension).map { _ in Float.random(in: -1...1, using: &generator) }
  }
}

/// A thread-safe count.
final class CatalogTextCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var total = 0

  /// Adds `count`.
  func add(_ count: Int) {
    lock.lock()
    total += count
    lock.unlock()
  }

  /// The count so far.
  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return total
  }
}
