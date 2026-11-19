import CryptoKit
import Foundation

/// The save side of a stored catalog, as a searcher sees it: the searcher
/// does not need `Item: Codable` to hold one.
protocol CatalogSaving<Item>: Sendable {
  /// The item type of the catalog.
  associatedtype Item: SearchableMetadata

  /// Asks for a save of `index`. Returns at once; the write runs on the
  /// queue of the store.
  func save(_ index: MetadataIndex<Item>)

  /// Returns when each save asked for so far is written (or failed).
  func waitForSaves() async
}

/// One stored catalog in a folder: its load at the start, and its saves
/// (plan.md decision #10). See `CatalogFileFormat` for the files.
///
/// **Saves.** `save(_:)` keeps only the newest index that waits; an older
/// one that waits is replaced, because the newest index holds each change
/// of the older one. A serial queue writes it: it compares the index with
/// the state that the files hold (`mirror`) and appends one journal record
/// with the changes. It writes a new snapshot instead when the order of the
/// catalog is not the order that the appends and removals give, when there
/// is no snapshot, or when the journal is large. A save that has no change
/// writes nothing, so two searchers that share one store and get the same
/// updates write each change one time.
///
/// `@unchecked Sendable`: `pending` is guarded by `lock`, and each other
/// mutable property is read and written only on `queue`.
final class CatalogStore<Item: SearchableMetadata & Codable>: CatalogSaving, @unchecked Sendable {
  /// What the files hold for one id.
  private struct MirrorEntry {
    /// The digests of the stored entry.
    let digests: RenderedTextDigests

    /// Whether the stored entry has a vector.
    let hasVector: Bool
  }

  /// The count of added or changed entries in the journal above which a
  /// save writes a new snapshot. The load builds the features of each such
  /// entry again, so this count bounds the time of a load.
  static var maximumJournalEntries: Int { 4_096 }

  /// The size of the journal above which a save writes a new snapshot.
  static var maximumJournalBytes: Int { 64 << 20 }

  /// The folder and the embedding model id.
  let persistence: CatalogPersistence

  /// Called with `.storedCatalogDropped` and `.catalogSaveFailed`.
  let onDiagnostic: @Sendable (MetadataDiagnostic) -> Void

  /// The serial queue of the load and of each save.
  private let queue = DispatchQueue(label: "FoundationModelsMetadataRegistry.CatalogStore")

  /// Guards `pending`.
  private let lock = NSLock()

  /// The newest index that waits for a save.
  private var pending: MetadataIndex<Item>?

  /// The order of the stored catalog. Only on `queue`.
  private var mirrorOrder: [String] = []

  /// The stored state of each id. Only on `queue`.
  private var mirror: [String: MirrorEntry] = [:]

  /// The generation of the snapshot. Only on `queue`.
  private var generation: UInt64 = 0

  /// Whether the folder holds a good snapshot and a journal of its
  /// generation, to which a record can be appended. Only on `queue`.
  private var canAppend = false

  /// The size of the journal. Only on `queue`.
  private var journalBytes = 0

  /// The count of added or changed entries in the journal. Only on `queue`.
  private var journalEntries = 0

  /// Makes a store for `persistence`. Nothing is read until `load()`.
  ///
  /// - Parameters:
  ///   - persistence: the folder and the embedding model id.
  ///   - onDiagnostic: called with the diagnostics of the store.
  init(
    persistence: CatalogPersistence,
    onDiagnostic: @escaping @Sendable (MetadataDiagnostic) -> Void,
  ) {
    self.persistence = persistence
    self.onDiagnostic = onDiagnostic
  }

  // MARK: - Load

  /// Reads the stored catalog: the snapshot, then the good records of the
  /// journal. Runs on the queue of the store, off the caller's thread.
  ///
  /// A catalog of another format version, of another embedding model, or
  /// that is damaged, is dropped: its files are removed, the store reports
  /// `.storedCatalogDropped`, and the index is empty. A damaged journal
  /// record and each record after it are dropped, and the file is cut
  /// there: the index is the last good state.
  ///
  /// - Returns: the stored index, with its vectors.
  func load() async -> MetadataIndex<Item> {
    await withCheckedContinuation { continuation in
      queue.async {
        continuation.resume(returning: self.loadOnQueue())
      }
    }
  }

  /// The work of `load()`, on the queue.
  private func loadOnQueue() -> MetadataIndex<Item> {
    let fileManager = FileManager.default
    try? fileManager.createDirectory(at: persistence.folder, withIntermediateDirectories: true)
    guard fileManager.fileExists(atPath: persistence.snapshotURL.path) else {
      try? fileManager.removeItem(at: persistence.journalURL)
      return MetadataIndex()
    }
    var index: MetadataIndex<Item>
    do {
      index = try readSnapshot()
    } catch {
      drop(reason: (error as? CatalogReadError ?? .damaged).dropReason)
      return MetadataIndex()
    }
    readJournal(into: &index)
    remember(index)
    return index
  }

  /// Removes the stored files and reports why.
  private func drop(reason: StoredCatalogDropReason) {
    try? FileManager.default.removeItem(at: persistence.snapshotURL)
    try? FileManager.default.removeItem(at: persistence.journalURL)
    canAppend = false
    onDiagnostic(.storedCatalogDropped(reason: reason))
  }

  /// Reads and checks the snapshot.
  ///
  /// - Returns: the index of the snapshot.
  /// - Throws: a `CatalogReadError`.
  private func readSnapshot() throws -> MetadataIndex<Item> {
    let data: Data
    do {
      data = try Data(contentsOf: persistence.snapshotURL, options: .alwaysMapped)
    } catch {
      throw CatalogReadError.damaged
    }
    return try data.withUnsafeBytes { raw -> MetadataIndex<Item> in
      let digestCount = CatalogFileFormat.digestByteCount
      guard raw.count > digestCount else { throw CatalogReadError.damaged }
      var reader = CatalogByteReader(raw)
      let magic = try reader.raw(CatalogFileFormat.snapshotMagic.count)
      guard Array(raw[magic]) == CatalogFileFormat.snapshotMagic else {
        throw CatalogReadError.damaged
      }
      guard try reader.uint32() == CatalogFileFormat.version else {
        throw CatalogReadError.formatVersion
      }
      let body = UnsafeRawBufferPointer(rebasing: raw[0..<(raw.count - digestCount)])
      guard CatalogFileFormat.digest(body) == Array(raw[(raw.count - digestCount)...]) else {
        throw CatalogReadError.damaged
      }
      var bodyReader = CatalogByteReader(body, offset: reader.offset)
      let generation = try bodyReader.uint64()
      guard try bodyReader.string() == persistence.embeddingModelID else {
        throw CatalogReadError.embeddingModel
      }
      let index = try Self.readSnapshotBody(&bodyReader)
      guard bodyReader.isAtEnd else { throw CatalogReadError.damaged }
      self.generation = generation
      return index
    }
  }

  /// Reads the vocabularies and the entries of a snapshot.
  private static func readSnapshotBody(_ reader: inout CatalogByteReader) throws
    -> MetadataIndex<Item>
  {
    let terms = try (0..<Int(reader.uint32())).map { _ in try reader.string() }
    let trigrams = try (0..<Int(reader.uint32())).map { _ in try reader.string() }
    let entryCount = Int(try reader.uint32())
    var stored: [StoredEntry] = []
    stored.reserveCapacity(entryCount)
    for _ in 0..<entryCount {
      let entry = try reader.entry(withFeatures: true)
      guard let features = entry.features,
        Self.idsAreInRange(features, termCount: terms.count, trigramCount: trigrams.count)
      else { throw CatalogReadError.damaged }
      stored.append(entry)
    }
    let items = try decodeItems(stored)
    var index = MetadataIndex<Item>()
    index.lexicon = Lexicon(terms: terms, trigrams: trigrams)
    for (entry, item) in zip(stored, items) {
      guard item.id == entry.id, index.entry(forID: entry.id) == nil,
        let features = entry.features
      else { throw CatalogReadError.damaged }
      index.store(
        MetadataIndex<Item>.Entry(
          item: item, block: entry.block, digests: entry.digests, features: features),
        vector: entry.vector)
    }
    return index
  }

  /// Whether each id of `features` names a term or a trigram of the
  /// vocabularies.
  private static func idsAreInRange(_ features: DocumentFeatures, termCount: Int, trigramCount: Int)
    -> Bool
  {
    let words = features.words
    let terms = DocumentFeatures.headerCount..<(DocumentFeatures.headerCount + features.termCount)
    let trigramStart = DocumentFeatures.headerCount + 2 * features.termCount
    return terms.allSatisfy { Int(words[$0]) < termCount }
      && words[trigramStart...].allSatisfy { Int($0) < trigramCount }
  }

  /// Decodes the item of each stored entry, in parallel.
  ///
  /// - Throws: `CatalogReadError.damaged` when an item does not decode.
  private static func decodeItems(_ stored: [StoredEntry]) throws -> [Item] {
    let decoded = MetadataIndex<Item>.parallelMap(stored) {
      try? JSONDecoder().decode(Item.self, from: $0.itemJSON)
    }
    var items: [Item] = []
    items.reserveCapacity(decoded.count)
    for item in decoded {
      guard let item else { throw CatalogReadError.damaged }
      items.append(item)
    }
    return items
  }

  /// Applies the good records of the journal to `index`, and cuts the file
  /// after the last good record.
  ///
  /// A journal of another generation, or with a bad header, is removed.
  private func readJournal(into index: inout MetadataIndex<Item>) {
    let url = persistence.journalURL
    guard let data = try? Data(contentsOf: url) else {
      canAppend = writeEmptyJournal()
      return
    }
    var goodEnd = 0
    var entries = 0
    let headerIsGood = data.withUnsafeBytes { raw -> Bool in
      var reader = CatalogByteReader(raw)
      guard let magic = try? reader.raw(CatalogFileFormat.journalMagic.count),
        Array(raw[magic]) == CatalogFileFormat.journalMagic,
        (try? reader.uint32()) == CatalogFileFormat.version,
        (try? reader.uint64()) == generation
      else { return false }
      goodEnd = reader.offset
      while !reader.isAtEnd {
        guard let record = try? Self.readRecord(&reader),
          let applied = try? Self.apply(record, to: index)
        else { break }
        index = applied.index
        entries += applied.entries
        goodEnd = reader.offset
      }
      return true
    }
    guard headerIsGood else {
      canAppend = writeEmptyJournal()
      return
    }
    if goodEnd < data.count {
      do {
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(goodEnd))
        try handle.close()
      } catch {
        canAppend = false
        return
      }
    }
    journalBytes = goodEnd
    journalEntries = entries
    canAppend = true
  }

  /// One record of the journal.
  private struct JournalRecord {
    /// The removed ids.
    let removed: [String]

    /// The added or changed entries.
    let entries: [StoredEntry]

    /// The new vectors: the id, the digest of the embedded text, the vector.
    let vectors: [(id: String, digest: Data, vector: [Float])]
  }

  /// Reads one record and checks its digest.
  private static func readRecord(_ reader: inout CatalogByteReader) throws -> JournalRecord {
    let length = Int(try reader.uint32())
    let digest = try reader.raw(CatalogFileFormat.digestByteCount)
    let payload = try reader.raw(length)
    let payloadBytes = UnsafeRawBufferPointer(rebasing: reader.bytes[payload])
    guard CatalogFileFormat.digest(payloadBytes) == Array(reader.bytes[digest]) else {
      throw CatalogReadError.damaged
    }
    var body = CatalogByteReader(payloadBytes)
    let removed = try (0..<Int(body.uint32())).map { _ in try body.string() }
    let entries = try (0..<Int(body.uint32())).map { _ in try body.entry(withFeatures: false) }
    let vectors = try (0..<Int(body.uint32())).map { _ in
      let id = try body.string()
      let digest = try body.data()
      guard let vector = try body.vector() else { throw CatalogReadError.damaged }
      return (id: id, digest: digest, vector: vector)
    }
    guard body.isAtEnd else { throw CatalogReadError.damaged }
    return JournalRecord(removed: removed, entries: entries, vectors: vectors)
  }

  /// Applies one record to a copy of `index`.
  ///
  /// The features of each entry are made again from its item and its
  /// block, in parallel. A replaced entry keeps its place; a new entry goes
  /// to the end.
  ///
  /// - Returns: the new index and the count of entries of the record.
  /// - Throws: `CatalogReadError.damaged` when an item does not decode.
  private static func apply(_ record: JournalRecord, to index: MetadataIndex<Item>) throws
    -> (index: MetadataIndex<Item>, entries: Int)
  {
    var index = index
    let items = try decodeItems(record.entries)
    for (entry, item) in zip(record.entries, items) where item.id != entry.id {
      throw CatalogReadError.damaged
    }
    index.remove(Set(record.removed))
    let prepared = MetadataIndex<Item>.parallelMap(Array(zip(record.entries, items))) {
      PreparedFeatures(id: $0.0.id, indexedText: $0.1.renderIndexedText(from: $0.0.block))
    }
    for ((entry, item), features) in zip(zip(record.entries, items), prepared) {
      index.store(
        MetadataIndex<Item>.Entry(
          item: item, block: entry.block, digests: entry.digests,
          features: DocumentFeatures(features, interning: &index.lexicon)))
      if let vector = entry.vector {
        index.setVector(vector, forID: entry.id, embeddedTextDigest: entry.digests.embeddedText)
      }
    }
    for vector in record.vectors {
      index.setVector(vector.vector, forID: vector.id, embeddedTextDigest: vector.digest)
    }
    return (index, record.entries.count)
  }

  // MARK: - Save

  /// Asks for a save of `index`, and returns at once.
  ///
  /// - Parameter index: the index to save.
  func save(_ index: MetadataIndex<Item>) {
    lock.lock()
    let wasPending = pending != nil
    pending = index
    lock.unlock()
    guard !wasPending else { return }
    queue.async { self.drain() }
  }

  /// Returns when each save asked for so far is written (or failed).
  func waitForSaves() async {
    await withCheckedContinuation { continuation in
      queue.async { continuation.resume() }
    }
  }

  /// Takes the index that waits and writes it.
  private func drain() {
    lock.lock()
    let index = pending
    pending = nil
    lock.unlock()
    guard let index else { return }
    write(index)
  }

  /// The changes of `index` from the stored state.
  private struct Changes {
    /// The stored ids that `index` does not hold.
    var removed: [String] = []

    /// The ids whose entries are new or changed.
    var entries: [String] = []

    /// The ids whose entries did not change and got a vector.
    var vectors: [String] = []

    /// Whether the order of `index` is the order that the removals and the
    /// appends give.
    var orderFollows = true

    /// Whether there is no change.
    var isEmpty: Bool { removed.isEmpty && entries.isEmpty && vectors.isEmpty && orderFollows }
  }

  /// Compares `index` with the stored state.
  private func changes(of index: MetadataIndex<Item>) -> Changes {
    var changes = Changes()
    changes.removed = mirrorOrder.filter { index.slotByID[$0] == nil }
    var appended: [String] = []
    for (id, slot) in zip(index.ids, index.slotOrder) {
      guard let entry = index.entries[slot] else { continue }
      let hasVector = index.vectors.hasVector(slot: slot)
      guard let stored = mirror[id] else {
        changes.entries.append(id)
        appended.append(id)
        continue
      }
      if stored.digests != entry.digests || (stored.hasVector && !hasVector) {
        changes.entries.append(id)
      } else if !stored.hasVector && hasVector {
        changes.vectors.append(id)
      }
    }
    let removed = Set(changes.removed)
    changes.orderFollows =
      index.ids.elementsEqual(mirrorOrder.lazy.filter { !removed.contains($0) } + appended)
    return changes
  }

  /// Writes the changes of `index`: one journal record, or a new snapshot.
  private func write(_ index: MetadataIndex<Item>) {
    let changes = changes(of: index)
    guard !changes.isEmpty || !canAppend else { return }
    let needsSnapshot =
      !canAppend || !changes.orderFollows
      || journalEntries + changes.entries.count > Self.maximumJournalEntries
      || journalBytes > Self.maximumJournalBytes
    do {
      if needsSnapshot {
        try writeSnapshot(index)
      } else {
        try appendRecord(changes, from: index)
      }
      remember(index)
    } catch {
      // The journal may end in a part of a record now, so the next save
      // writes a new snapshot.
      canAppend = false
      onDiagnostic(.catalogSaveFailed)
    }
  }

  /// Sets the stored state to `index`.
  private func remember(_ index: MetadataIndex<Item>) {
    mirrorOrder = index.ids
    var mirror: [String: MirrorEntry] = [:]
    mirror.reserveCapacity(index.count)
    for (id, slot) in zip(index.ids, index.slotOrder) {
      guard let entry = index.entries[slot] else { continue }
      mirror[id] = MirrorEntry(
        digests: entry.digests, hasVector: index.vectors.hasVector(slot: slot))
    }
    self.mirror = mirror
  }

  /// Appends one journal record with `changes`.
  private func appendRecord(_ changes: Changes, from index: MetadataIndex<Item>) throws {
    var payload = CatalogByteWriter()
    payload.uint32(UInt32(changes.removed.count))
    for id in changes.removed { payload.string(id) }
    payload.uint32(UInt32(changes.entries.count))
    let encoder = JSONEncoder()
    for id in changes.entries {
      guard let entry = index.entry(forID: id) else { continue }
      payload.entry(
        id: id, itemJSON: try encoder.encode(entry.item), block: entry.block,
        digests: entry.digests, features: nil, vector: index.embedding(forID: id))
    }
    payload.uint32(UInt32(changes.vectors.count))
    for id in changes.vectors {
      guard let entry = index.entry(forID: id) else { continue }
      payload.string(id)
      payload.data(entry.digests.embeddedText)
      payload.vector(index.embedding(forID: id))
    }
    var record = CatalogByteWriter()
    record.uint32(UInt32(payload.bytes.count))
    payload.bytes.withUnsafeBytes { record.raw(CatalogFileFormat.digest($0)) }
    record.raw(payload.bytes)

    let handle = try FileHandle(forWritingTo: persistence.journalURL)
    defer { try? handle.close() }
    try handle.seek(toOffset: UInt64(journalBytes))
    try handle.write(contentsOf: record.bytes)
    try handle.synchronize()
    journalBytes += record.bytes.count
    journalEntries += changes.entries.count
  }

  /// Writes a new snapshot of `index` and an empty journal of its
  /// generation.
  private func writeSnapshot(_ index: MetadataIndex<Item>) throws {
    let nextGeneration = generation + 1
    let temporary = persistence.snapshotURL.appendingPathExtension("tmp")
    try FileManager.default.createDirectory(
      at: persistence.folder, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: temporary.path, contents: nil)
    let handle = try FileHandle(forWritingTo: temporary)
    var hasher = SHA256()
    var buffer = CatalogByteWriter()

    func flush(force: Bool) throws {
      guard force || buffer.bytes.count >= 4 << 20 else { return }
      buffer.bytes.withUnsafeBytes { hasher.update(bufferPointer: $0) }
      try handle.write(contentsOf: buffer.bytes)
      buffer.bytes.removeAll(keepingCapacity: true)
    }

    do {
      buffer.raw(CatalogFileFormat.snapshotMagic)
      buffer.uint32(CatalogFileFormat.version)
      buffer.uint64(nextGeneration)
      buffer.string(persistence.embeddingModelID)
      buffer.uint32(UInt32(index.lexicon.terms.count))
      for term in index.lexicon.terms {
        buffer.string(term)
        try flush(force: false)
      }
      buffer.uint32(UInt32(index.lexicon.trigrams.count))
      for trigram in index.lexicon.trigrams {
        buffer.string(trigram)
        try flush(force: false)
      }
      buffer.uint32(UInt32(index.count))
      let encoder = JSONEncoder()
      for (id, slot) in zip(index.ids, index.slotOrder) {
        guard let entry = index.entries[slot] else { continue }
        buffer.entry(
          id: id, itemJSON: try encoder.encode(entry.item), block: entry.block,
          digests: entry.digests, features: entry.features,
          vector: index.vectors.vector(slot: slot))
        try flush(force: false)
      }
      try flush(force: true)
      try handle.write(contentsOf: Array(hasher.finalize()))
      try handle.synchronize()
      try handle.close()
    } catch {
      try? handle.close()
      try? FileManager.default.removeItem(at: temporary)
      throw error
    }
    try Self.replace(persistence.snapshotURL, with: temporary)
    generation = nextGeneration
    canAppend = false
    guard writeEmptyJournal() else { throw CatalogReadError.damaged }
    canAppend = true
  }

  /// Writes an empty journal of the current generation.
  ///
  /// - Returns: whether the journal was written.
  @discardableResult
  private func writeEmptyJournal() -> Bool {
    var header = CatalogByteWriter()
    header.raw(CatalogFileFormat.journalMagic)
    header.uint32(CatalogFileFormat.version)
    header.uint64(generation)
    let temporary = persistence.journalURL.appendingPathExtension("tmp")
    do {
      try Data(header.bytes).write(to: temporary)
      try Self.replace(persistence.journalURL, with: temporary)
    } catch {
      return false
    }
    journalBytes = header.bytes.count
    journalEntries = 0
    return true
  }

  /// Renames `temporary` to `target`, in one step that replaces `target`.
  private static func replace(_ target: URL, with temporary: URL) throws {
    guard rename(temporary.path, target.path) == 0 else {
      throw CocoaError(.fileWriteUnknown)
    }
  }
}
