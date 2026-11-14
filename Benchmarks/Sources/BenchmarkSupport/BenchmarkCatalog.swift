import FoundationModelsMetadataRegistry

/// The subject area of a catalog item.
public enum BenchmarkDomain: String, CaseIterable, Codable, Sendable {
  /// Version control with git.
  case git
  /// Files and folders on a disk.
  case fileSystem
  /// Food and kitchen tasks.
  case cooking
  /// Plants, soil and garden tasks.
  case gardening
  /// Instruments, recording and songs.
  case music
  /// Money, banks and taxes.
  case finance
  /// Trips, tickets and luggage.
  case travel
  /// Body, sleep and medicine.
  case health
}

/// One item of the benchmark catalog: a stable id, a domain, and the
/// one-line block that is its search surface.
public struct BenchmarkItem: SearchableMetadata, Equatable {
  /// The id that a label names and that a `Match` gives back.
  public let id: String

  /// The subject area of this item.
  public let domain: BenchmarkDomain

  /// The one-line description that the registry searches.
  public let block: String

  /// Makes one catalog item.
  ///
  /// - Parameters:
  ///   - id: the stable id of the item.
  ///   - domain: the subject area of the item.
  ///   - block: the one-line description of the item.
  public init(id: String, domain: BenchmarkDomain, block: String) {
    self.id = id
    self.domain = domain
    self.block = block
  }

  /// Renders this item to its search surface, which is `block`.
  ///
  /// - Returns: `block`.
  public func renderBlock() -> String {
    block
  }
}

/// The catalog that the benchmark searches: about 60 items in eight domains.
///
/// **Shared words are on purpose.** Some words are in the blocks of more than
/// one domain: "branch" (git, gardening, finance), "scale" (cooking, music,
/// health), "track" (music, health), "record" (git, music, health),
/// "balance" (music, finance, health), "book" (travel, health), "pick" (git,
/// gardening, travel), "tag" (git, travel), "root" (file system, gardening),
/// "water" (cooking, gardening, health) and "file" (file system, finance).
/// Thus a keyword match alone gives wrong answers for some intents, and the
/// benchmark can show which configuration reads the meaning.
public enum BenchmarkCatalog {
  /// All the items of the catalog, grouped by domain.
  public static let items: [BenchmarkItem] =
    gitItems + fileSystemItems + cookingItems + gardeningItems
    + musicItems + financeItems + travelItems + healthItems

  /// The git items.
  static let gitItems = makeItems(
    domain: .git,
    blocks: [
      ("gitCommit", "Record the staged changes in the repository with a commit message."),
      ("gitBranch", "Create a new branch from the current commit."),
      ("gitMerge", "Merge another branch into the current branch."),
      ("gitRebase", "Replay your local commits on top of the updated upstream branch."),
      ("gitStash", "Stash uncommitted changes and restore a clean working tree."),
      ("gitCherryPick", "Cherry-pick one commit from another branch onto the current branch."),
      ("gitTag", "Tag a commit with a release version label."),
      ("gitRevert", "Revert a commit by adding a new commit that undoes it."),
    ],
  )

  /// The file system items.
  static let fileSystemItems = makeItems(
    domain: .fileSystem,
    blocks: [
      ("fsCopyFile", "Copy a file to another folder."),
      ("fsMoveFile", "Move a file to another folder or rename it."),
      ("fsDeleteFile", "Delete a file permanently without the trash."),
      ("fsListDirectory", "List the files in a directory, starting from the root."),
      ("fsCompressFolder", "Compress a folder into a zip archive."),
      ("fsChangePermissions", "Change the read and write permissions of a file."),
      ("fsDiskUsage", "Show how much disk space each folder uses."),
      ("fsFindFile", "Search the whole disk for a file by its name."),
      ("fsSymbolicLink", "Create a symbolic link that points to another file."),
    ],
  )

  /// The cooking items.
  static let cookingItems = makeItems(
    domain: .cooking,
    blocks: [
      ("cookBoilPasta", "Boil pasta in salted water until it is tender."),
      ("cookBeatEggs", "Beat eggs with a whisk until they are fluffy."),
      ("cookKneadDough", "Knead bread dough and let it rise in a warm place."),
      ("cookSearSteak", "Sear a steak in a hot cast iron pan."),
      ("cookWeighFlour", "Weigh flour on a kitchen scale before baking."),
      ("cookSimmerStock", "Simmer bones and vegetables in water to make a stock."),
      ("cookPickleCucumbers", "Pickle cucumbers in vinegar and brine."),
      ("cookPreheatOven", "Preheat the oven to the temperature in the recipe."),
    ],
  )

  /// The gardening items.
  static let gardeningItems = makeItems(
    domain: .gardening,
    blocks: [
      ("gardenPruneBranch", "Prune a dead branch from a fruit tree."),
      ("gardenSowSeeds", "Sow seeds in a tray of potting soil."),
      ("gardenWaterRoots", "Water plants deeply so the root grows strong."),
      ("gardenTurnCompost", "Turn the compost pile with a fork to add air."),
      ("gardenPickTomatoes", "Pick ripe tomatoes from the vine."),
      ("gardenTestSoil", "Test the soil pH before you plant."),
      ("gardenSpreadMulch", "Spread mulch around shrubs to keep the soil moist."),
    ],
  )

  /// The music items.
  static let musicItems = makeItems(
    domain: .music,
    blocks: [
      ("musicTuneGuitar", "Tune each guitar string to the correct pitch."),
      ("musicPracticeScale", "Practice a major scale on the piano in every key."),
      ("musicSetMetronome", "Set a metronome to keep a steady beat."),
      ("musicRecordVocal", "Record a vocal track in the studio."),
      ("musicMixTracks", "Mix the tracks and balance the levels."),
      ("musicReadSheet", "Read the notes and rests on sheet music."),
      ("musicChordChart", "Write a chord chart for a song."),
      ("musicMakePlaylist", "Make a playlist of songs for a party."),
    ],
  )

  /// The finance items.
  static let financeItems = makeItems(
    domain: .finance,
    blocks: [
      ("financeReconcile", "Balance your account against the bank statement."),
      ("financeDepositCheck", "Deposit a paper check at a bank branch."),
      ("financeMonthlyBudget", "Plan a monthly budget for rent, food and savings."),
      ("financeFileTaxes", "File your income tax return before the deadline."),
      ("financeTransferMoney", "Transfer money between your checking and savings accounts."),
      ("financeCreditScore", "Look up your credit score and credit report."),
      ("financeIndexFund", "Invest in an index fund for retirement."),
      ("financeSplitBill", "Split a restaurant bill between friends."),
    ],
  )

  /// The travel items.
  static let travelItems = makeItems(
    domain: .travel,
    blocks: [
      ("travelBookFlight", "Book a flight and pick a seat."),
      ("travelOnlineCheckIn", "Check in online and download a boarding pass."),
      ("travelRenewPassport", "Renew a passport before an international trip."),
      ("travelPackBag", "Pack a carry-on bag and attach a luggage tag."),
      ("travelReserveHotel", "Reserve a hotel room near the station."),
      ("travelExchangeCurrency", "Exchange cash into a foreign currency."),
      ("travelTrainTicket", "Buy a train ticket for a scenic route."),
    ],
  )

  /// The health items.
  static let healthItems = makeItems(
    domain: .health,
    blocks: [
      ("healthWeighIn", "Weigh yourself on a bathroom scale every morning."),
      ("healthTrackSleep", "Track how many hours you sleep each night."),
      ("healthRefillPrescription", "Refill a prescription at the pharmacy."),
      ("healthBloodPressure", "Measure your blood pressure and record the result."),
      ("healthStretch", "Do stretches and balance exercises after a run."),
      ("healthDoctorVisit", "Book an appointment with a doctor for a checkup."),
      ("healthDrinkWater", "Drink enough water during the day."),
    ],
  )

  /// Makes the items of one domain.
  ///
  /// - Parameters:
  ///   - domain: the domain of each item.
  ///   - blocks: the id and the block of each item, in order.
  /// - Returns: one item for each pair in `blocks`.
  static func makeItems(
    domain: BenchmarkDomain,
    blocks: [(id: String, block: String)],
  ) -> [BenchmarkItem] {
    blocks.map { BenchmarkItem(id: $0.id, domain: domain, block: $0.block) }
  }
}
