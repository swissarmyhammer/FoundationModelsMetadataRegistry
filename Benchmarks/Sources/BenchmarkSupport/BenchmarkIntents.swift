/// One user intent and the catalog ids that answer it.
public struct LabeledIntent: Equatable, Sendable {
  /// The kind of an intent. The kind tells which metrics apply to it.
  public enum Kind: String, CaseIterable, Codable, Sendable {
    /// The intent shares a content word with its one answer.
    case lexical
    /// The intent shares no content word with its one answer. Only a match
    /// on meaning finds it.
    case paraphrase
    /// The intent asks for more than one step, so more than one id answers
    /// it.
    case multiStep
    /// No catalog item answers the intent, so the correct result is empty.
    case offTopic
  }

  /// The text that the user types.
  public let text: String

  /// The ids of the catalog items that answer `text`. It is empty for an
  /// off-topic intent.
  public let relevantIDs: Set<String>

  /// The kind of this intent.
  public let kind: Kind

  /// Makes one labeled intent.
  ///
  /// - Parameters:
  ///   - text: the text that the user types.
  ///   - relevantIDs: the ids of the catalog items that answer `text`.
  ///   - kind: the kind of the intent.
  public init(text: String, relevantIDs: Set<String>, kind: Kind) {
    self.text = text
    self.relevantIDs = relevantIDs
    self.kind = kind
  }
}

/// The labeled intents that the benchmark searches with: ten of each kind.
///
/// Each label names an id of `BenchmarkCatalog.items`. Some lexical and
/// off-topic intents use a word that is also in an item of another domain
/// ("branch", "scale", "track", "write"), so a keyword match alone ranks a
/// wrong item high.
public enum BenchmarkIntents {
  /// All the intents, grouped by kind.
  public static let all: [LabeledIntent] = lexical + paraphrase + multiStep + offTopic

  /// The intents that share a content word with their one answer.
  static let lexical = makeIntents(
    kind: .lexical,
    labels: [
      ("commit my staged changes", ["gitCommit"]),
      ("create a new branch", ["gitBranch"]),
      ("copy this file to another folder", ["fsCopyFile"]),
      ("boil pasta", ["cookBoilPasta"]),
      ("prune the dead branch on my apple tree", ["gardenPruneBranch"]),
      ("tune my guitar", ["musicTuneGuitar"]),
      ("deposit a check at the bank", ["financeDepositCheck"]),
      ("renew my passport", ["travelRenewPassport"]),
      ("track my sleep", ["healthTrackSleep"]),
      ("weigh myself on the bathroom scale", ["healthWeighIn"]),
    ],
  )

  /// The intents that share no content word with their one answer.
  static let paraphrase = makeIntents(
    kind: .paraphrase,
    labels: [
      ("take back my last save in version control without rewriting history", ["gitRevert"]),
      ("put my half-done edits away for later", ["gitStash"]),
      ("which directories take up the most storage", ["fsDiskUsage"]),
      ("squeeze a whole directory down to one small bundle for emailing", ["fsCompressFolder"]),
      ("how do I make spaghetti noodles soft", ["cookBoilPasta"]),
      ("cut off the withered limb on my apple sapling", ["gardenPruneBranch"]),
      ("my acoustic sounds sour, fix it so the notes ring true", ["musicTuneGuitar"]),
      ("move cash from everyday spending to my rainy day fund", ["financeTransferMoney"]),
      ("I need a new travel document before going abroad", ["travelRenewPassport"]),
      ("remind me to stay hydrated", ["healthDrinkWater"]),
    ],
  )

  /// The intents that more than one item answers.
  static let multiStep = makeIntents(
    kind: .multiStep,
    labels: [
      ("commit my work and tag it as a release", ["gitCommit", "gitTag"]),
      ("make a branch, then merge it back into main when done", ["gitBranch", "gitMerge"]),
      ("find the old report and move it to the archive folder", ["fsFindFile", "fsMoveFile"]),
      ("preheat the oven and knead the bread dough", ["cookPreheatOven", "cookKneadDough"]),
      ("test the soil and then sow the seeds", ["gardenTestSoil", "gardenSowSeeds"]),
      ("record a vocal and then mix the tracks", ["musicRecordVocal", "musicMixTracks"]),
      (
        "plan a budget and move some money into savings",
        ["financeMonthlyBudget", "financeTransferMoney"]
      ),
      ("book a flight and a hotel room for the trip", ["travelBookFlight", "travelReserveHotel"]),
      (
        "weigh myself and log my blood pressure each morning",
        ["healthWeighIn", "healthBloodPressure"]
      ),
      (
        "get euros for the trip and pack my carry-on bag",
        ["travelExchangeCurrency", "travelPackBag"]
      ),
    ],
  )

  /// The intents that no item answers.
  static let offTopic = makeIntents(
    kind: .offTopic,
    labels: [
      ("what is the capital of Australia", []),
      ("translate hello into Japanese", []),
      ("who won the football match last night", []),
      ("write a poem about the ocean", []),
      ("how many keys does an old typewriter have", []),
      ("explain quantum entanglement simply", []),
      ("recommend a good mystery novel", []),
      ("what time is the sunset today", []),
      ("fix the flat tire on my bike", []),
      ("teach my dog to sit", []),
    ],
  )

  /// Makes the intents of one kind.
  ///
  /// - Parameters:
  ///   - kind: the kind of each intent.
  ///   - labels: the text and the relevant ids of each intent, in order.
  /// - Returns: one intent for each pair in `labels`.
  static func makeIntents(
    kind: LabeledIntent.Kind,
    labels: [(text: String, relevantIDs: Set<String>)],
  ) -> [LabeledIntent] {
    labels.map { LabeledIntent(text: $0.text, relevantIDs: $0.relevantIDs, kind: kind) }
  }
}
