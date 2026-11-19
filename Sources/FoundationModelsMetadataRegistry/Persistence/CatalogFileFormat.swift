import CryptoKit
import Foundation

/// The file format of a stored catalog (plan.md decision #10).
///
/// A folder holds two files:
///
/// - `catalog.snapshot`: the whole catalog at one generation. The magic,
///   the format version, the generation, the embedding model id, the term
///   and trigram vocabularies, then each entry in catalog order: its id, its
///   item as JSON, its block, the three digests, its features (the interned
///   ids, `DocumentFeatures.words`) and its vector. The last 32 bytes are the
///   SHA-256 of all the bytes before them. The file is written to
///   `catalog.snapshot.tmp` and then renamed, so a crash leaves the old
///   snapshot or the new one, never a part.
/// - `catalog.journal`: the changes after the snapshot. The magic, the
///   format version and the generation of its snapshot, then records. Each
///   record is the length of its payload, the SHA-256 of the payload, and
///   the payload: the removed ids, the added or changed entries (with no
///   features: the load makes them again from the item and the block), and
///   the new vectors with the digest of their embedded text. A record that
///   is short or whose digest is wrong ends the journal: the load keeps the
///   records before it, which is the last good state.
///
/// A journal of another generation than the snapshot is left from a crash
/// during a new snapshot, and the load ignores it. All numbers are little
/// endian.
enum CatalogFileFormat {
  /// The version of this format. A stored catalog of another version is
  /// dropped.
  static let version: UInt32 = 1

  /// The first bytes of a snapshot.
  static let snapshotMagic = Array("MDRSNAP1".utf8)

  /// The first bytes of a journal.
  static let journalMagic = Array("MDRJRNL1".utf8)

  /// The name of the snapshot file.
  static let snapshotFileName = "catalog.snapshot"

  /// The name of the journal file.
  static let journalFileName = "catalog.journal"

  /// The suffix of a file while it is written.
  static let temporarySuffix = ".tmp"

  /// The count of bytes of a SHA-256 digest.
  static let digestByteCount = 32

  /// The value of a vector count that means "no vector".
  static let noVector = UInt32.max

  /// The SHA-256 of `bytes`.
  static func digest(_ bytes: UnsafeRawBufferPointer) -> [UInt8] {
    Array(SHA256.hash(data: bytes))
  }
}

/// Why a stored catalog cannot be read.
enum CatalogReadError: Error, Equatable {
  /// The catalog is of another format version.
  case formatVersion

  /// The catalog was written for another embedding model.
  case embeddingModel

  /// The bytes are short, damaged, or do not decode.
  case damaged

  /// The reason of the `storedCatalogDropped` diagnostic.
  var dropReason: StoredCatalogDropReason {
    switch self {
    case .formatVersion: .formatVersion
    case .embeddingModel: .embeddingModel
    case .damaged: .damaged
    }
  }
}

/// Appends the fields of the format to a byte buffer.
struct CatalogByteWriter {
  /// The bytes written so far.
  var bytes: [UInt8] = []

  /// Appends a 32-bit number.
  mutating func uint32(_ value: UInt32) {
    withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
  }

  /// Appends a 64-bit number.
  mutating func uint64(_ value: UInt64) {
    withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
  }

  /// Appends raw bytes with no length.
  mutating func raw(_ value: some Sequence<UInt8>) {
    bytes.append(contentsOf: value)
  }

  /// Appends a byte count and the bytes.
  mutating func data(_ value: some Collection<UInt8>) {
    uint32(UInt32(value.count))
    bytes.append(contentsOf: value)
  }

  /// Appends a string as a byte count and its UTF-8 bytes.
  mutating func string(_ value: String) {
    data(Array(value.utf8))
  }

  /// Appends a count and 32-bit numbers.
  mutating func words(_ value: [UInt32]) {
    uint32(UInt32(value.count))
    value.withUnsafeBytes { raw in
      if UInt32(littleEndian: 1) == 1 {
        bytes.append(contentsOf: raw)
      } else {
        for word in value { uint32(word) }
      }
    }
  }

  /// Appends a vector: its count and its floats, or `noVector`.
  mutating func vector(_ value: [Float]?) {
    guard let value else {
      uint32(CatalogFileFormat.noVector)
      return
    }
    words(value.map(\.bitPattern))
  }
}

/// Reads the fields of the format from a byte buffer.
///
/// Each read checks the bounds and throws `CatalogReadError.damaged` past
/// the end.
struct CatalogByteReader {
  /// The bytes.
  let bytes: UnsafeRawBufferPointer

  /// The offset of the next read.
  var offset: Int

  /// Makes a reader at `offset`.
  init(_ bytes: UnsafeRawBufferPointer, offset: Int = 0) {
    self.bytes = bytes
    self.offset = offset
  }

  /// Whether each byte was read.
  var isAtEnd: Bool { offset >= bytes.count }

  /// Checks that `count` more bytes are there.
  private func require(_ count: Int) throws {
    guard count >= 0, offset + count <= bytes.count else { throw CatalogReadError.damaged }
  }

  /// Reads a 32-bit number.
  mutating func uint32() throws -> UInt32 {
    try require(4)
    defer { offset += 4 }
    return UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
  }

  /// Reads a 64-bit number.
  mutating func uint64() throws -> UInt64 {
    try require(8)
    defer { offset += 8 }
    return UInt64(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
  }

  /// Reads `count` raw bytes, as a range of `bytes`.
  mutating func raw(_ count: Int) throws -> Range<Int> {
    try require(count)
    defer { offset += count }
    return offset..<(offset + count)
  }

  /// Reads a byte count and the bytes, as a range of `bytes`.
  mutating func dataRange() throws -> Range<Int> {
    try raw(Int(uint32()))
  }

  /// Reads a byte count and the bytes.
  mutating func data() throws -> Data {
    let range = try dataRange()
    return Data(UnsafeRawBufferPointer(rebasing: bytes[range]))
  }

  /// Reads a string.
  mutating func string() throws -> String {
    let range = try dataRange()
    return String(decoding: UnsafeRawBufferPointer(rebasing: bytes[range]), as: UTF8.self)
  }

  /// Reads a count and 32-bit numbers.
  mutating func words() throws -> [UInt32] {
    let count = Int(try uint32())
    let range = try raw(count * 4)
    return [UInt32](unsafeUninitializedCapacity: count) { target, initialized in
      UnsafeMutableRawBufferPointer(target).copyMemory(
        from: UnsafeRawBufferPointer(rebasing: bytes[range]))
      if UInt32(littleEndian: 1) != 1 {
        for index in 0..<count { target[index] = UInt32(littleEndian: target[index]) }
      }
      initialized = count
    }
  }

  /// Reads a vector, or `nil` for `noVector`.
  mutating func vector() throws -> [Float]? {
    let start = offset
    guard try uint32() != CatalogFileFormat.noVector else { return nil }
    offset = start
    return try words().map(Float.init(bitPattern:))
  }
}

/// The parts of one stored entry, before its item is decoded.
struct StoredEntry: Sendable {
  /// The id.
  let id: String

  /// The item, as JSON.
  let itemJSON: Data

  /// The block.
  let block: String

  /// The three digests.
  let digests: RenderedTextDigests

  /// The features, or `nil` in a journal record.
  let features: DocumentFeatures?

  /// The vector, or `nil`.
  let vector: [Float]?
}

extension CatalogByteWriter {
  /// Appends one entry.
  ///
  /// - Parameters:
  ///   - id: the id.
  ///   - itemJSON: the item, as JSON.
  ///   - block: the block.
  ///   - digests: the three digests.
  ///   - features: the features, or `nil` for a journal record.
  ///   - vector: the vector, or `nil`.
  mutating func entry(
    id: String, itemJSON: Data, block: String, digests: RenderedTextDigests,
    features: DocumentFeatures?, vector: [Float]?,
  ) {
    string(id)
    data(itemJSON)
    string(block)
    data(digests.block)
    data(digests.indexedText)
    data(digests.embeddedText)
    if let features { words(features.words) }
    self.vector(vector)
  }
}

extension CatalogByteReader {
  /// Reads one entry.
  ///
  /// - Parameter withFeatures: whether the entry holds its features (a
  ///   snapshot entry) or not (a journal entry).
  /// - Returns: the entry.
  mutating func entry(withFeatures: Bool) throws -> StoredEntry {
    let id = try string()
    let itemJSON = try data()
    let block = try string()
    let digests = RenderedTextDigests(
      blockDigest: try data(), indexedTextDigest: try data(), embeddedTextDigest: try data())
    var features: DocumentFeatures?
    if withFeatures {
      guard let decoded = DocumentFeatures(words: try words()) else {
        throw CatalogReadError.damaged
      }
      features = decoded
    }
    return StoredEntry(
      id: id, itemJSON: itemJSON, block: block, digests: digests, features: features,
      vector: try vector())
  }
}
