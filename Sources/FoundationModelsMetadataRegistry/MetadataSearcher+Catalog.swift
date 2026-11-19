/// The public read of the catalog of `MetadataSearcher`.
extension MetadataSearcher {
  /// The items of the catalog, in catalog order.
  ///
  /// For a searcher made with `CatalogPersistence`, these are the stored
  /// items from the moment that the async initializer returns, before any
  /// embed ends. A caller uses them to compare its own items with the stored
  /// catalog: to upsert only the changed items, and to remove the items that
  /// are gone.
  ///
  /// - Returns: each item of the catalog, in catalog order.
  public func items() -> [Item] {
    index.ids.compactMap { index.item(forID: $0) }
  }

  /// The ids of the catalog, in catalog order.
  ///
  /// - Returns: each id of the catalog, in catalog order.
  public func ids() -> [String] {
    index.ids
  }
}
