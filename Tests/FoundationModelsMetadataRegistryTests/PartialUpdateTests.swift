import Foundation
import Testing

@testable import FoundationModelsMetadataRegistry

/// Tests for `MetadataSearcher.update(upserting:removing:)` (plan.md §8): an
/// update of some items adds, replaces and removes items by id, and builds
/// no entry that did not change.
struct PartialUpdateTests {
  // MARK: - Fixtures

  /// Counts the renders of each id, across threads.
  final class RenderCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    /// Records one render of `id`.
    func record(_ id: String) {
      lock.lock()
      defer { lock.unlock() }
      counts[id, default: 0] += 1
    }

    /// The count of renders of `id` so far.
    func count(_ id: String) -> Int {
      lock.lock()
      defer { lock.unlock() }
      return counts[id, default: 0]
    }
  }

  /// A catalog item that counts its block renders.
  struct CountingItem: SearchableMetadata {
    let id: String
    let block: String
    let counter: RenderCounter

    func renderBlock() -> String {
      counter.record(id)
      return block
    }
  }

  /// A fresh counter and the items `a`, `b` and `c` that count into it.
  static func catalog() -> (counter: RenderCounter, items: [CountingItem]) {
    let counter = RenderCounter()
    let items = [
      CountingItem(id: "a", block: "deploy the service to production", counter: counter),
      CountingItem(id: "b", block: "commit the staged changes", counter: counter),
      CountingItem(id: "c", block: "search the session transcripts", counter: counter),
    ]
    return (counter, items)
  }

  /// A searcher over `items`, with a counting embedder, after one full update.
  static func searcher(
    over items: [CountingItem], embedder: FakeEmbedder, recorder: DiagnosticRecorder? = nil,
  ) async -> MetadataSearcher<CountingItem> {
    let searcher = MetadataSearcher<CountingItem>(
      items: [], mode: .retrieval, embedder: embedder,
      onDiagnostic: { recorder?.record($0) })
    await searcher.update(items: items)
    return searcher
  }

  /// A distinct vector for each text of the fixtures.
  static let vectors: [String: [Float]] = [
    "deploy the service to production": [1, 0, 0, 0],
    "commit the staged changes": [0, 1, 0, 0],
    "search the session transcripts": [0, 0, 1, 0],
    "commit and push the branch": [0, 1, 1, 0],
    "export the session as markdown": [0, 0, 0, 1],
  ]

  // MARK: - Tests

  @Test
  func addsChangesAndRemovesItemsAndEmbedsOnlyTheNewTexts() async {
    let (counter, items) = Self.catalog()
    let embedder = FakeEmbedder(vectorsByText: Self.vectors)
    let searcher = await Self.searcher(over: items, embedder: embedder)
    let vectorOfA = await searcher.index.embedding(forID: "a")

    await searcher.update(
      upserting: [
        CountingItem(id: "b", block: "commit and push the branch", counter: counter),
        CountingItem(id: "d", block: "export the session as markdown", counter: counter),
      ],
      removing: ["c"])

    let index = await searcher.index
    #expect(index.ids == ["a", "b", "d"])
    #expect(index.block(forID: "b") == "commit and push the branch")
    #expect(index.item(forID: "c") == nil)
    #expect(index.embedding(forID: "a") == vectorOfA)
    #expect(index.embedding(forID: "b") == Self.vectors["commit and push the branch"])
    #expect(index.embedding(forID: "d") == Self.vectors["export the session as markdown"])
    #expect(
      embedder.embeddedBatches.last
        == ["commit and push the branch", "export the session as markdown"])
  }

  @Test
  func rendersNoEntryThatIsNotInTheCall() async {
    let (counter, items) = Self.catalog()
    let searcher = await Self.searcher(over: items, embedder: FakeEmbedder())
    let rendersOfA = counter.count("a")
    let rendersOfC = counter.count("c")

    await searcher.update(
      upserting: [CountingItem(id: "b", block: "commit and push the branch", counter: counter)])

    #expect(counter.count("a") == rendersOfA)
    #expect(counter.count("c") == rendersOfC)
  }

  @Test
  func aReplacedItemKeepsItsPlaceAndANewItemGoesToTheEnd() async {
    let (counter, items) = Self.catalog()
    let searcher = await Self.searcher(over: items, embedder: FakeEmbedder())

    await searcher.update(
      upserting: [
        CountingItem(id: "z", block: "a new item", counter: counter),
        CountingItem(id: "a", block: "deploy the service again", counter: counter),
      ])

    #expect(await searcher.index.ids == ["a", "b", "c", "z"])
  }

  @Test
  func anIdInBothListsIsUpserted() async {
    let (counter, items) = Self.catalog()
    let searcher = await Self.searcher(over: items, embedder: FakeEmbedder())

    await searcher.update(
      upserting: [CountingItem(id: "c", block: "search again", counter: counter)],
      removing: ["c", "b"])

    let index = await searcher.index
    #expect(index.ids == ["a", "c"])
    #expect(index.block(forID: "c") == "search again")
  }

  @Test
  func aCallThatChangesNothingIsANoOp() async {
    let (_, items) = Self.catalog()
    let embedder = FakeEmbedder(vectorsByText: Self.vectors)
    let recorder = DiagnosticRecorder()
    let searcher = await Self.searcher(over: items, embedder: embedder, recorder: recorder)
    let batches = embedder.embeddedBatches.count
    let diagnostics = recorder.diagnostics.count

    await searcher.update(upserting: [items[1]], removing: ["not-indexed"])

    #expect(embedder.embeddedBatches.count == batches)
    #expect(recorder.diagnostics.count == diagnostics)
    #expect(await searcher.index.ids == ["a", "b", "c"])
  }

  @Test
  func aDuplicateIdInTheUpsertsIsReported() async {
    let (counter, items) = Self.catalog()
    let recorder = DiagnosticRecorder()
    let searcher = await Self.searcher(
      over: items, embedder: FakeEmbedder(), recorder: recorder)

    await searcher.update(
      upserting: [
        CountingItem(id: "d", block: "first", counter: counter),
        CountingItem(id: "d", block: "second", counter: counter),
      ])

    #expect(recorder.diagnostics.contains(.duplicateId(id: "d")))
    #expect(await searcher.index.block(forID: "d") == "first")
  }

  @Test
  func searchFindsAnAddedItemAndNotARemovedItem() async throws {
    let (counter, items) = Self.catalog()
    let searcher = await Self.searcher(over: items, embedder: FakeEmbedder())

    await searcher.update(
      upserting: [CountingItem(id: "d", block: "export the session as markdown", counter: counter)],
      removing: ["c"])

    let matches = try await searcher.search(intent: "session", limit: 10)
    #expect(matches.first?.id == "d")
    #expect(!matches.contains { $0.id == "c" })
  }
}
