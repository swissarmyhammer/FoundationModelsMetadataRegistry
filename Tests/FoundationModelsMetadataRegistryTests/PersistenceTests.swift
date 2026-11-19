import Foundation
import Testing

@testable import FoundationModelsMetadataRegistry

/// Tests for the persistence option (plan.md decision #10): a searcher keeps
/// its catalog and its vectors in a folder, and a new searcher over the same
/// folder searches with no catalog embed.
struct PersistenceTests {
  // MARK: - Fixtures

  /// A `Codable` catalog item.
  struct StoredItem: SearchableMetadata, Codable, Equatable {
    let id: String
    let block: String

    func renderBlock() -> String {
      block
    }
  }

  /// The catalog of the tests.
  static let catalog = [
    StoredItem(id: "deploy", block: "deploy the service to production"),
    StoredItem(id: "commit", block: "commit the staged changes"),
    StoredItem(id: "search", block: "search the session transcripts"),
    StoredItem(id: "export", block: "export the session as markdown"),
  ]

  /// A distinct vector for each text of the tests.
  static let vectors: [String: [Float]] = [
    "deploy the service to production": [1, 0, 0, 0],
    "commit the staged changes": [0, 1, 0, 0],
    "search the session transcripts": [0, 0, 1, 0],
    "export the session as markdown": [0, 0, 0.5, 1],
    "save my work": [0, 0.9, 0.1, 0],
    "push the branch": [0.2, 0.8, 0, 0],
  ]

  /// The model id of the tests.
  static let modelID = "test-embedder-1"

  /// A new empty folder, removed by the caller.
  static func makeFolder() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("PersistenceTests-\(UUID().uuidString)")
  }

  /// A persistent searcher over `folder`.
  static func searcher(
    in folder: URL,
    modelID: String = modelID,
    embedder: FakeEmbedder = FakeEmbedder(vectorsByText: vectors),
    recorder: DiagnosticRecorder = DiagnosticRecorder(),
  ) async -> MetadataSearcher<StoredItem> {
    await MetadataSearcher<StoredItem>(
      persistence: CatalogPersistence(folder: folder, embeddingModelID: modelID),
      mode: .retrieval,
      embedder: embedder,
      onDiagnostic: { recorder.record($0) },
    )
  }

  /// Saves `items` in `folder` through a searcher, and waits for the save.
  static func store(_ items: [StoredItem], in folder: URL) async {
    let searcher = await searcher(in: folder)
    await searcher.update(items: items)
    await searcher.waitForSaves()
  }

  /// The ids and scores of a search.
  static func ranking(_ searcher: MetadataSearcher<StoredItem>, _ intent: String) async throws
    -> [String]
  {
    try await searcher.search(intent: intent, limit: 10).map { "\($0.id) \($0.score)" }
  }

  /// Whether each embed call of `embedder` embedded one query only.
  static func embeddedOnlyQueries(_ embedder: FakeEmbedder, queries: Set<String>) -> Bool {
    embedder.embeddedBatches.allSatisfy { $0.count == 1 && queries.contains($0[0]) }
  }

  // MARK: - Save and load

  @Test
  func aNewSearcherOverTheSameFolderGivesTheSameMatchesWithNoCatalogEmbed() async throws {
    let folder = Self.makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let first = await Self.searcher(in: folder)
    await first.update(items: Self.catalog)
    await first.waitForSaves()
    let expected = try await Self.ranking(first, "save my work")

    let embedder = FakeEmbedder(vectorsByText: Self.vectors)
    let second = await Self.searcher(in: folder, embedder: embedder)

    #expect(await second.index.ids == Self.catalog.map(\.id))
    #expect(try await Self.ranking(second, "save my work") == expected)
    #expect(Self.embeddedOnlyQueries(embedder, queries: ["save my work"]))
    for item in Self.catalog {
      #expect(await second.index.embedding(forID: item.id) == Self.vectors[item.block])
      #expect(await second.index.item(forID: item.id) == item)
    }
  }

  @Test
  func theChangesAfterTheSnapshotComeBackFromTheJournal() async throws {
    let folder = Self.makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let first = await Self.searcher(in: folder)
    await first.update(items: Self.catalog)
    await first.update(
      upserting: [StoredItem(id: "commit", block: "push the branch")], removing: ["search"])
    await first.update(upserting: [StoredItem(id: "late", block: "save my work")])
    await first.waitForSaves()
    let expected = try await Self.ranking(first, "push work")

    let embedder = FakeEmbedder(vectorsByText: Self.vectors)
    let second = await Self.searcher(in: folder, embedder: embedder)

    #expect(await second.index.ids == ["deploy", "commit", "export", "late"])
    #expect(await second.index.block(forID: "commit") == "push the branch")
    #expect(await second.index.embedding(forID: "late") == Self.vectors["save my work"])
    #expect(try await Self.ranking(second, "push work") == expected)
    #expect(Self.embeddedOnlyQueries(embedder, queries: ["push work"]))
  }

  @Test
  func aNewOrderIsSavedAsANewSnapshot() async throws {
    let folder = Self.makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let first = await Self.searcher(in: folder)
    await first.update(items: Self.catalog)
    await first.update(items: Self.catalog.reversed())
    await first.waitForSaves()

    let second = await Self.searcher(in: folder)

    #expect(await second.index.ids == Self.catalog.reversed().map(\.id))
  }

  @Test
  func anEmptyFolderGivesAnEmptySearcherWithNoDiagnostic() async {
    let folder = Self.makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let recorder = DiagnosticRecorder()

    let searcher = await Self.searcher(in: folder, recorder: recorder)

    #expect(await searcher.index.count == 0)
    #expect(recorder.diagnostics.isEmpty)
  }

  // MARK: - Dropped catalogs

  @Test
  func aDifferentModelIdDropsTheStoredCatalog() async {
    let folder = Self.makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    await Self.store(Self.catalog, in: folder)
    let recorder = DiagnosticRecorder()

    let searcher = await Self.searcher(in: folder, modelID: "another-model", recorder: recorder)

    #expect(await searcher.index.count == 0)
    #expect(recorder.diagnostics == [.storedCatalogDropped(reason: .embeddingModel)])
    let again = await Self.searcher(in: folder, recorder: DiagnosticRecorder())
    #expect(await again.index.count == 0)
  }

  @Test
  func aDamagedSnapshotIsDropped() async throws {
    let folder = Self.makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    await Self.store(Self.catalog, in: folder)
    let url = folder.appendingPathComponent(CatalogFileFormat.snapshotFileName)
    var bytes = try Data(contentsOf: url)
    bytes[bytes.count / 2] ^= 0xFF
    try bytes.write(to: url)
    let recorder = DiagnosticRecorder()

    let searcher = await Self.searcher(in: folder, recorder: recorder)

    #expect(await searcher.index.count == 0)
    #expect(recorder.diagnostics == [.storedCatalogDropped(reason: .damaged)])
  }

  @Test
  func aShortSnapshotIsDropped() async throws {
    let folder = Self.makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    await Self.store(Self.catalog, in: folder)
    let url = folder.appendingPathComponent(CatalogFileFormat.snapshotFileName)
    try Data(try Data(contentsOf: url).prefix(40)).write(to: url)
    let recorder = DiagnosticRecorder()

    let searcher = await Self.searcher(in: folder, recorder: recorder)

    #expect(await searcher.index.count == 0)
    #expect(recorder.diagnostics == [.storedCatalogDropped(reason: .damaged)])
  }

  @Test
  func anOldFormatIsDropped() async throws {
    let folder = Self.makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    await Self.store(Self.catalog, in: folder)
    let url = folder.appendingPathComponent(CatalogFileFormat.snapshotFileName)
    var bytes = try Data(contentsOf: url)
    let versionOffset = CatalogFileFormat.snapshotMagic.count
    bytes.replaceSubrange(
      versionOffset..<(versionOffset + 4),
      with: withUnsafeBytes(of: (CatalogFileFormat.version - 1).littleEndian) { Data($0) })
    try bytes.write(to: url)
    let recorder = DiagnosticRecorder()

    let searcher = await Self.searcher(in: folder, recorder: recorder)

    #expect(await searcher.index.count == 0)
    #expect(recorder.diagnostics == [.storedCatalogDropped(reason: .formatVersion)])
  }

  @Test
  func theNextUpdateAfterADropBuildsTheCatalogAgain() async {
    let folder = Self.makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    await Self.store(Self.catalog, in: folder)
    let dropped = await Self.searcher(in: folder, modelID: "another-model")
    await dropped.update(items: Self.catalog)
    await dropped.waitForSaves()

    let reloaded = await Self.searcher(in: folder, modelID: "another-model")

    #expect(await reloaded.index.ids == Self.catalog.map(\.id))
  }

  // MARK: - Crash during a save

  @Test
  func aTornJournalRecordLeavesTheLastGoodState() async throws {
    let folder = Self.makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let first = await Self.searcher(in: folder)
    await first.update(items: Self.catalog)
    await first.update(upserting: [StoredItem(id: "late", block: "save my work")])
    await first.waitForSaves()
    let journal = folder.appendingPathComponent(CatalogFileFormat.journalFileName)
    let goodSize = try Data(contentsOf: journal).count
    await first.update(upserting: [StoredItem(id: "lost", block: "push the branch")])
    await first.waitForSaves()
    // A crash during the append of the last record: only a part of it is
    // on disk.
    let full = try Data(contentsOf: journal)
    try Data(full.prefix(goodSize + 10)).write(to: journal)

    let second = await Self.searcher(in: folder)

    #expect(await second.index.ids == Self.catalog.map(\.id) + ["late"])
    #expect(try Data(contentsOf: journal).count == goodSize)
    // The journal takes new records after the cut.
    await second.update(upserting: [StoredItem(id: "after", block: "push the branch")])
    await second.waitForSaves()
    let third = await Self.searcher(in: folder)
    #expect(await third.index.ids == Self.catalog.map(\.id) + ["late", "after"])
  }

  @Test
  func aLeftTemporarySnapshotDoesNotChangeTheStoredCatalog() async throws {
    let folder = Self.makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    await Self.store(Self.catalog, in: folder)
    // A crash during the write of a new snapshot leaves a part of it.
    try Data("MDRSNAP1 a part".utf8).write(
      to: folder.appendingPathComponent(CatalogFileFormat.snapshotFileName + ".tmp"))

    let searcher = await Self.searcher(in: folder)

    #expect(await searcher.index.ids == Self.catalog.map(\.id))
  }

  // MARK: - Pending embeds

  @Test
  func anEntryStoredWithNoVectorIsEmbeddedInTheBackground() async throws {
    let folder = Self.makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let failing = await Self.searcher(
      in: folder, embedder: FakeEmbedder(failure: CancellationError()))
    await failing.update(items: Self.catalog)
    await failing.waitForSaves()

    let embedder = FakeEmbedder(vectorsByText: Self.vectors)
    let searcher = await Self.searcher(in: folder, embedder: embedder)
    while await searcher.index.pendingEmbeddingCount > 0 {
      await Task.yield()
    }

    #expect(embedder.embeddedBatches.first == Self.catalog.map(\.block))
    await searcher.waitForSaves()
    let reloaded = await Self.searcher(in: folder)
    for item in Self.catalog {
      #expect(await reloaded.index.embedding(forID: item.id) == Self.vectors[item.block])
    }
  }

  // MARK: - Shared embed

  @Test
  func searchersThatShareOneEmbedSaveToOneFolder() async throws {
    let folder = Self.makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let persistence = CatalogPersistence(folder: folder, embeddingModelID: Self.modelID)
    let shared = await SharedCatalogEmbedding<StoredItem>(
      persistence: persistence, embedder: FakeEmbedder(vectorsByText: Self.vectors),
      onDiagnostic: { _ in })
    let keyword = MetadataSearcher(sharing: shared, mode: .retrieval, onDiagnostic: { _ in })
    let semantic = MetadataSearcher(sharing: shared, mode: .retrieval, onDiagnostic: { _ in })
    await keyword.update(items: Self.catalog)
    await semantic.update(items: Self.catalog)
    await keyword.waitForSaves()
    await shared.waitForSaves()

    let embedder = FakeEmbedder(vectorsByText: Self.vectors)
    let reopened = await SharedCatalogEmbedding<StoredItem>(
      persistence: persistence, embedder: embedder, onDiagnostic: { _ in })
    let searcher = MetadataSearcher(sharing: reopened, mode: .retrieval, onDiagnostic: { _ in })

    #expect(reopened.index.ids == Self.catalog.map(\.id))
    _ = try await searcher.search(intent: "save my work", limit: 4)
    #expect(Self.embeddedOnlyQueries(embedder, queries: ["save my work"]))
  }
}
