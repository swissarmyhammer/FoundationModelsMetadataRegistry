import Foundation

/// A tokenized, two-field search index over a catalog of `SearchableMetadata` items.
///
/// Built per plan.md §1, §4 and §5 "Scale". Each item's `id` and rendered
/// texts are precomputed one time, when the item is added or changed, into the
/// data the retrieval tier scores against: the same BM25 and trigram
/// statistics as one FoundationModelsRanker `RankedDocument` (`id` as the
/// primary field, `renderIndexedText(from:)` as the body field), kept as
/// sorted ids of two interned vocabularies (`DocumentFeatures`, `Lexicon`);
/// the verbatim block; the digests of the three rendered texts; and an
/// embedding slot in a contiguous matrix (`EmbeddingMatrix`). Precomputing at
/// add time rather than per query is what makes repeated `search()` calls
/// cheap — tokenizing/trigramming happens one time for each item, not one
/// time for each query.
///
/// Each entry lives in a slot. A removed entry frees its slot, and a later
/// entry takes it, so a change of some items does not move the others.
/// `ids` gives the catalog order, which is also the tie-break order of the
/// retrieval tier.
///
/// `MetadataIndex` never interprets an item's text — it only tokenizes
/// and trigrams the opaque text the item renders, and hands back
/// `renderBlock()`'s output verbatim.
public struct MetadataIndex<Item: SearchableMetadata>: Sendable {
  /// One catalog entry's precomputed search data.
  struct Entry: Sendable {
    /// The catalog item itself.
    let item: Item

    /// `item.renderBlock()`, captured once at build time.
    ///
    /// The value every `Match.block` traces back to verbatim, never
    /// re-derived (plan.md §1 "Verbatim by construction, not by
    /// prompt").
    let block: String

    /// SHA-256 digests of this entry's three rendered texts.
    ///
    /// `digests.embeddedText` is the key that a stored embedding is reused
    /// by, and the whole value is what `hasIdenticalContent(to:)` and the
    /// hash guard of an update compare (plan.md §8). See
    /// `RenderedTextDigests`.
    let digests: RenderedTextDigests

    /// The BM25 and trigram statistics of this entry, as interned ids.
    let features: DocumentFeatures
  }

  /// The indexed ids, in catalog order, with duplicates already resolved per the first-wins policy.
  ///
  /// Exactly the set of ids `item(forID:)`/`block(forID:)`/etc. can
  /// resolve.
  public private(set) var ids: [String] = []

  /// The slot of each id of `ids`, at the same position.
  private(set) var slotOrder: [Int] = []

  /// The slot of each id.
  private(set) var slotByID: [String: Int] = [:]

  /// The entries, by slot. A free slot holds `nil`.
  private(set) var entries: [Entry?] = []

  /// The free slots, which the next new entries take.
  private var freeSlots: [Int] = []

  /// The interned vocabularies and the BM25 counters of the live entries.
  var lexicon = Lexicon()

  /// The stored embeddings, by slot.
  private(set) var vectors = EmbeddingMatrix()

  /// The number of entries in this index after duplicate ids are dropped.
  public var count: Int {
    ids.count
  }

  /// Makes an empty index.
  init() {}

  /// Builds an in-memory index from `items`.
  ///
  /// Tokenizes and trigrams each item's `id` and rendered indexed text
  /// exactly once. **Duplicate-id policy**: when two items share an `id`, the
  /// first one (in `items` order) wins; every later duplicate is dropped
  /// and reported via `onDiagnostic(.duplicateId(id:))` — never a crash,
  /// never silent (plan.md §4 "`id` is the join key").
  ///
  /// - Parameters:
  ///   - items: the catalog's items, in the order duplicate resolution
  ///     should prefer (first occurrence wins).
  ///   - onDiagnostic: called for every diagnostic emitted while building
  ///     this index (currently only `.duplicateId`). Defaults to logging
  ///     via `MetadataDiagnostic.log(_:)`.
  public init(
    items: [Item],
    onDiagnostic: @Sendable (MetadataDiagnostic) -> Void = { MetadataDiagnostic.log($0) },
  ) {
    replaceAll(with: items, onDiagnostic: onDiagnostic)
  }

  // MARK: - Lookup

  /// The entry stored under `id`, or `nil` if `id` isn't indexed.
  ///
  /// - Parameter id: the id to look up.
  /// - Returns: the entry, or `nil`.
  func entry(forID id: String) -> Entry? {
    slotByID[id].flatMap { entries[$0] }
  }

  /// The catalog item stored under `id`.
  ///
  /// Returns `nil` if `id` isn't indexed (never indexed, or dropped as a
  /// duplicate).
  ///
  /// - Parameter forID: the id to look up.
  /// - Returns: the catalog item, or `nil` if `id` isn't indexed.
  public func item(forID id: String) -> Item? {
    entry(forID: id)?.item
  }

  /// The rendered block stored under `id`, verbatim from its build-time render.
  ///
  /// Returns `nil` if `id` isn't indexed.
  ///
  /// - Parameter forID: the id to look up.
  /// - Returns: the rendered block, or `nil` if `id` isn't indexed.
  public func block(forID id: String) -> String? {
    entry(forID: id)?.block
  }

  /// The BM25/trigram statistics of `id`, as one FoundationModelsRanker `RankedDocument`.
  ///
  /// The index keeps these statistics as interned ids, so this method makes
  /// the `RankedDocument` again from the stored item and block (`id` as its
  /// primary field, the rendered indexed text as its body field). The
  /// retrieval tier scores the same statistics.
  ///
  /// Returns `nil` if `id` isn't indexed.
  ///
  /// - Parameter forID: the id to look up.
  /// - Returns: the per-document statistics, or `nil` if `id` isn't indexed.
  public func rankedDocument(forID id: String) -> RankedDocument? {
    guard let entry = entry(forID: id) else { return nil }
    return RankedDocument(
      primaryText: id, bodyText: entry.item.renderIndexedText(from: entry.block))
  }

  /// The embedding stored for `id`, or `nil` if `id` isn't indexed or not yet embedded.
  ///
  /// `nil` until `MetadataIndex.build(items:embedder:previous:
  /// onDiagnostic:)`, or a `MetadataSearcher` catch-up merging an embedded
  /// batch, fills this storage slot.
  ///
  /// - Parameter forID: the id to look up.
  /// - Returns: the stored embedding, or `nil` if `id` isn't indexed or
  ///   not yet embedded.
  public func embedding(forID id: String) -> [Float]? {
    slotByID[id].flatMap { vectors.vector(slot: $0) }
  }

  /// Whether at least one entry carries an embedding.
  var hasEmbeddings: Bool {
    vectors.count > 0
  }

  // MARK: - Slots

  /// Stores `entry` under its id: in the same slot when the id is indexed,
  /// else in a free slot at the end of the catalog order.
  ///
  /// The vector of a replaced entry stays when the embedded text did not
  /// change, and is cleared otherwise. The lexicon counters follow.
  ///
  /// - Parameters:
  ///   - entry: the entry to store.
  ///   - vector: the vector for a new entry, or `nil`. A replaced entry
  ///     ignores it.
  mutating func store(_ entry: Entry, vector: [Float]? = nil) {
    let id = entry.item.id
    if let slot = slotByID[id], let old = entries[slot] {
      lexicon.uncount(old.features)
      lexicon.count(entry.features)
      entries[slot] = entry
      if old.digests.embeddedText != entry.digests.embeddedText {
        vectors.set(nil, slot: slot)
      }
      return
    }
    let slot: Int
    if let free = freeSlots.popLast() {
      slot = free
      entries[slot] = entry
    } else {
      slot = entries.count
      entries.append(entry)
    }
    slotByID[id] = slot
    ids.append(id)
    slotOrder.append(slot)
    lexicon.count(entry.features)
    vectors.set(vector, slot: slot)
  }

  /// Removes the entries of `removed` and frees their slots.
  ///
  /// An id that isn't indexed is ignored.
  ///
  /// - Parameter removed: the ids to remove.
  /// - Returns: the ids that were indexed and are now removed, in catalog
  ///   order.
  @discardableResult
  mutating func remove(_ removed: Set<String>) -> [String] {
    guard !removed.isEmpty else { return [] }
    var removedInOrder: [String] = []
    var keptIDs: [String] = []
    var keptSlots: [Int] = []
    keptIDs.reserveCapacity(ids.count)
    keptSlots.reserveCapacity(ids.count)
    for (id, slot) in zip(ids, slotOrder) {
      guard removed.contains(id) else {
        keptIDs.append(id)
        keptSlots.append(slot)
        continue
      }
      removedInOrder.append(id)
      if let old = entries[slot] { lexicon.uncount(old.features) }
      entries[slot] = nil
      vectors.set(nil, slot: slot)
      slotByID[id] = nil
      freeSlots.append(slot)
    }
    guard !removedInOrder.isEmpty else { return [] }
    ids = keptIDs
    slotOrder = keptSlots
    return removedInOrder
  }

  /// Puts the indexed ids in the order of `order`.
  ///
  /// - Parameter order: each indexed id one time, in the new order.
  mutating func reorder(_ order: [String]) {
    precondition(order.count == ids.count, "MetadataIndex.reorder: the order must name each id")
    ids = order
    slotOrder = order.map { id in
      guard let slot = slotByID[id] else {
        preconditionFailure("MetadataIndex.reorder: the order names an id that isn't indexed")
      }
      return slot
    }
  }

  /// Stores `vector` for `id` when its entry still has the embedded text
  /// with the digest `embeddedTextDigest`.
  ///
  /// - Parameters:
  ///   - vector: the vector to store.
  ///   - id: the id of the entry.
  ///   - embeddedTextDigest: the digest of the text that `vector` was
  ///     embedded from.
  /// - Returns: whether the vector was stored.
  @discardableResult
  mutating func setVector(_ vector: [Float], forID id: String, embeddedTextDigest: Data) -> Bool {
    guard let slot = slotByID[id], let entry = entries[slot],
      entry.digests.embeddedText == embeddedTextDigest
    else { return false }
    vectors.set(vector, slot: slot)
    return true
  }
}
