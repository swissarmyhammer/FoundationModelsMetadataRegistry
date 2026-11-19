/// The changes of a `MetadataIndex`: a new catalog (`replaceAll(with:onDiagnostic:)`)
/// and a change of some items (`apply(upserting:removing:onDiagnostic:)`).
///
/// Both reuse each entry whose rendered texts did not change, with its vector.
/// Only the added and the changed items are tokenized and trigrammed.
extension MetadataIndex {
  /// What one change did to an index.
  struct Change: Sendable, Equatable {
    /// The ids whose entries were added or changed, in catalog order of the
    /// change.
    var upserted: [String] = []

    /// The ids that were removed, in the catalog order before the change.
    var removed: [String] = []

    /// Whether the catalog order is not the order that the removals and the
    /// appends alone give.
    var reordered = false

    /// Whether the change did nothing.
    var isEmpty: Bool {
      upserted.isEmpty && removed.isEmpty && !reordered
    }
  }

  /// One item with its rendered texts and digests, before its features.
  struct RenderedItem: Sendable {
    /// The item.
    let item: Item

    /// `item.renderBlock()`.
    let block: String

    /// `item.renderIndexedText(from: block)`.
    let indexedText: String

    /// The digests of the three rendered texts.
    let digests: RenderedTextDigests

    /// Renders `item` one time.
    ///
    /// - Parameter item: the item to render.
    init(_ item: Item) {
      self.item = item
      block = item.renderBlock()
      indexedText = item.renderIndexedText(from: block)
      let embeddedText = item.renderEmbeddedText(from: block)
      digests = RenderedTextDigests(
        block: block, indexedText: indexedText, embeddedText: embeddedText)
    }
  }

  /// The count of items from which rendering and tokenizing run in parallel.
  ///
  /// A small catalog is rendered on the calling thread, so a test double
  /// that counts its renders sees them in order.
  static var parallelThreshold: Int { 256 }

  /// Replaces the catalog with `items`, in their order.
  ///
  /// An entry whose three digests did not change is kept as it is, with its
  /// vector. An entry whose embedded text did not change keeps its vector. An
  /// id that is not in `items` is removed.
  ///
  /// - Parameters:
  ///   - items: the new catalog, in first-seen-wins duplicate-id order.
  ///   - onDiagnostic: called with `.duplicateId` for each dropped duplicate.
  /// - Returns: what the change did.
  @discardableResult
  mutating func replaceAll(
    with items: [Item],
    onDiagnostic: @Sendable (MetadataDiagnostic) -> Void,
  ) -> Change {
    let unique = Self.firstOfEachID(items, onDiagnostic: onDiagnostic)
    let rendered = Self.render(unique)
    let newIDs = Set(rendered.map(\.item.id))
    let previousIDs = ids

    var change = Change()
    change.removed = remove(Set(ids).subtracting(newIDs))
    let changed = rendered.filter { entry(forID: $0.item.id)?.digests != $0.digests }
    change.upserted = changed.map(\.item.id)
    store(changed)

    let order = rendered.map(\.item.id)
    let removed = Set(change.removed)
    let previous = Set(previousIDs)
    let appendedOrder =
      previousIDs.filter { !removed.contains($0) }
      + order.filter { !previous.contains($0) }
    if order != ids { reorder(order) }
    change.reordered = order != appendedOrder
    return change
  }

  /// Adds, replaces and removes some items, and keeps each other entry as it is.
  ///
  /// A replaced item keeps its place in the catalog order, and a new item
  /// goes to the end, in the order of `upserting`. An id in both lists is an
  /// upsert: the item is in the catalog after the call. An item whose three
  /// digests did not change is not built again.
  ///
  /// - Parameters:
  ///   - upserting: the items to add or replace, in first-seen-wins
  ///     duplicate-id order.
  ///   - removing: the ids to remove. An id that isn't indexed is ignored.
  ///   - onDiagnostic: called with `.duplicateId` for each dropped duplicate
  ///     of `upserting`.
  /// - Returns: what the change did.
  @discardableResult
  mutating func apply(
    upserting: [Item],
    removing: some Sequence<String>,
    onDiagnostic: @Sendable (MetadataDiagnostic) -> Void,
  ) -> Change {
    let unique = Self.firstOfEachID(upserting, onDiagnostic: onDiagnostic)
    let rendered = Self.render(unique)
    let upsertedIDs = Set(rendered.map(\.item.id))

    var change = Change()
    change.removed = remove(Set(removing).subtracting(upsertedIDs))
    let changed = rendered.filter { entry(forID: $0.item.id)?.digests != $0.digests }
    change.upserted = changed.map(\.item.id)
    store(changed)
    return change
  }

  /// The count of items whose text features are prepared at one time.
  ///
  /// A prepared item holds its trigrams as a set of strings, which is much
  /// larger than its interned features. Batches bound that memory when a
  /// large catalog is built.
  static var preparationBatchSize: Int { 4_096 }

  /// Tokenizes and stores each rendered item.
  ///
  /// - Parameter rendered: the items to store.
  private mutating func store(_ rendered: [RenderedItem]) {
    for start in stride(from: 0, to: rendered.count, by: Self.preparationBatchSize) {
      let batch = Array(rendered[start..<min(start + Self.preparationBatchSize, rendered.count)])
      let prepared = Self.parallelMap(batch) {
        PreparedFeatures(id: $0.item.id, indexedText: $0.indexedText)
      }
      for (item, features) in zip(batch, prepared) {
        store(
          Entry(
            item: item.item,
            block: item.block,
            digests: item.digests,
            features: DocumentFeatures(features, interning: &lexicon),
          ))
      }
    }
  }

  /// The first item of each id, in order, and a `.duplicateId` diagnostic
  /// for each later one.
  ///
  /// - Parameters:
  ///   - items: the items.
  ///   - onDiagnostic: called with `.duplicateId` for each dropped duplicate.
  /// - Returns: the first item of each id.
  private static func firstOfEachID(
    _ items: [Item],
    onDiagnostic: @Sendable (MetadataDiagnostic) -> Void,
  ) -> [Item] {
    var seen = Set<String>()
    seen.reserveCapacity(items.count)
    var unique: [Item] = []
    unique.reserveCapacity(items.count)
    for item in items {
      guard seen.insert(item.id).inserted else {
        onDiagnostic(.duplicateId(id: item.id))
        continue
      }
      unique.append(item)
    }
    return unique
  }

  /// Renders each item one time.
  ///
  /// - Parameter items: the items.
  /// - Returns: the rendered items, in order.
  static func render(_ items: [Item]) -> [RenderedItem] {
    parallelMap(items) { RenderedItem($0) }
  }

  /// Maps `elements` with `transform`, in parallel when there are
  /// `parallelThreshold` elements or more.
  ///
  /// - Parameters:
  ///   - elements: the elements.
  ///   - transform: a pure function.
  /// - Returns: the results, in order.
  static func parallelMap<Element: Sendable, Result: Sendable>(
    _ elements: [Element],
    _ transform: @Sendable (Element) -> Result,
  ) -> [Result] {
    guard elements.count >= parallelThreshold else { return elements.map(transform) }
    return ParallelWork.map(count: elements.count) { transform(elements[$0]) }
  }
}
