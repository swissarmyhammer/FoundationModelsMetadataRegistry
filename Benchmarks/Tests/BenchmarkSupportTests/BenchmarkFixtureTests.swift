import Testing

@testable import BenchmarkSupport

/// The invariants of the labeled fixture, measured without a model.
///
/// A benchmark result is only as correct as its labels. These tests make
/// sure that each label names a real item, that each kind of intent has
/// enough intents to give a mean, and that each intent is of the kind its
/// label says.
@Suite("Benchmark fixture")
struct BenchmarkFixtureTests {
  /// The minimum count of intents of each kind.
  static let minimumIntentsPerKind = 8

  /// The minimum count of content words that the blocks of two or more
  /// domains share. These shared words make keyword match give wrong
  /// answers.
  static let minimumSharedTerms = 8

  /// The ids of all the catalog items.
  static let catalogIDs = BenchmarkCatalog.items.map(\.id)

  /// The block of each catalog item, by id.
  static let blocksByID = Dictionary(
    uniqueKeysWithValues: BenchmarkCatalog.items.map { ($0.id, $0.renderBlock()) },
  )

  /// The intents of `kind`.
  ///
  /// - Parameter kind: the kind to keep.
  /// - Returns: the intents of `BenchmarkIntents.all` that are of `kind`.
  static func intents(of kind: LabeledIntent.Kind) -> [LabeledIntent] {
    BenchmarkIntents.all.filter { $0.kind == kind }
  }

  /// The content terms of the relevant blocks of `intent`, one set for each
  /// relevant id.
  ///
  /// - Parameter intent: the intent to read.
  /// - Returns: the content terms of each relevant block.
  static func relevantBlockTerms(of intent: LabeledIntent) -> [Set<String>] {
    intent.relevantIDs.compactMap { blocksByID[$0] }.map(ContentTerms.of)
  }

  @Test("the catalog has no duplicate id")
  func catalogHasNoDuplicateID() {
    #expect(Set(Self.catalogIDs).count == Self.catalogIDs.count)
  }

  @Test("each domain has items")
  func eachDomainHasItems() {
    let domains = Set(BenchmarkCatalog.items.map(\.domain))
    #expect(domains == Set(BenchmarkDomain.allCases))
  }

  @Test("each relevant id names a catalog item")
  func eachRelevantIDNamesACatalogItem() {
    let labels = Set(BenchmarkIntents.all.flatMap(\.relevantIDs))
    #expect(labels.subtracting(Self.catalogIDs).isEmpty)
  }

  @Test("no two intents have the same text")
  func noTwoIntentsHaveTheSameText() {
    let texts = BenchmarkIntents.all.map(\.text)
    #expect(Set(texts).count == texts.count)
  }

  @Test("each kind has enough intents", arguments: LabeledIntent.Kind.allCases)
  func eachKindHasEnoughIntents(kind: LabeledIntent.Kind) {
    #expect(Self.intents(of: kind).count >= Self.minimumIntentsPerKind)
  }

  @Test("off-topic intents have no relevant id")
  func offTopicIntentsHaveNoRelevantID() {
    #expect(Self.intents(of: .offTopic).allSatisfy { $0.relevantIDs.isEmpty })
  }

  @Test("lexical and paraphrase intents have one relevant id")
  func lexicalAndParaphraseIntentsHaveOneRelevantID() {
    let singleAnswerIntents = Self.intents(of: .lexical) + Self.intents(of: .paraphrase)
    #expect(singleAnswerIntents.allSatisfy { $0.relevantIDs.count == 1 })
  }

  @Test("multi-step intents have more than one relevant id")
  func multiStepIntentsHaveMoreThanOneRelevantID() {
    #expect(Self.intents(of: .multiStep).allSatisfy { $0.relevantIDs.count > 1 })
  }

  /// A paraphrase that shares a word with its answer measures keyword match,
  /// not meaning.
  @Test("paraphrase intents share no content word with their relevant blocks")
  func paraphraseIntentsShareNoContentWordWithTheirRelevantBlocks() {
    let leaks = Self.intents(of: .paraphrase).filter { intent in
      let intentTerms = ContentTerms.of(intent.text)
      return Self.relevantBlockTerms(of: intent).contains { !$0.isDisjoint(with: intentTerms) }
    }
    #expect(leaks.isEmpty, "these paraphrases share a word with their answer: \(leaks)")
  }

  /// A lexical intent is the easy case: its answer holds one of its words.
  @Test("lexical intents share a content word with a relevant block")
  func lexicalIntentsShareAContentWordWithARelevantBlock() {
    let misses = Self.intents(of: .lexical).filter { intent in
      let intentTerms = ContentTerms.of(intent.text)
      return Self.relevantBlockTerms(of: intent).allSatisfy { $0.isDisjoint(with: intentTerms) }
    }
    #expect(misses.isEmpty, "these lexical intents share no word with their answer: \(misses)")
  }

  /// Words such as "branch" and "scale" are in more than one domain, so a
  /// keyword match alone gives wrong answers.
  @Test("the blocks of different domains share content words")
  func blocksOfDifferentDomainsShareContentWords() {
    let termsByDomain = Dictionary(grouping: BenchmarkCatalog.items, by: \.domain)
      .mapValues { items in
        items.reduce(into: Set<String>()) { $0.formUnion(ContentTerms.of($1.block)) }
      }
    let domainCountByTerm = termsByDomain.values.flatMap(\.self)
      .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
    let sharedTerms = domainCountByTerm.filter { $0.value > 1 }
    #expect(sharedTerms.count >= Self.minimumSharedTerms)
  }
}
