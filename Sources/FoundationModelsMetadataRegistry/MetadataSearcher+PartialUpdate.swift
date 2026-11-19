/// The update of some items of `MetadataSearcher` (plan.md §8): add, replace
/// and remove items by id, with no new build of the other entries.
extension MetadataSearcher {
  /// Adds, replaces and removes some items of this searcher's catalog, and
  /// keeps each other entry as it is.
  ///
  /// Use this method when the caller knows which items changed, for example
  /// the new chunks of one turn of a session, or the items of one deleted
  /// session. Its cost follows the count of items in the call, not the size
  /// of the catalog. `update(items:)` renders and compares each item of the
  /// catalog.
  ///
  /// - An item of `upserting` whose id is not indexed is added at the end of
  ///   the catalog order, in the order of `upserting`.
  /// - An item whose id is indexed replaces that entry in its place. When
  ///   the three rendered texts of the item have the same digests as the
  ///   entry, the entry stays as it is: no new tokenize, no new embed.
  ///   When only the embedded text is the same, the entry keeps its vector.
  /// - Each id of `removing` is removed, with its vector. An id that is not
  ///   indexed is ignored. An id that is also in `upserting` is not
  ///   removed: the upserted item is in the catalog after the call.
  /// - A later duplicate id in `upserting` is dropped and reported with
  ///   `.duplicateId`, the same as in `update(items:)`.
  ///
  /// The rest is the same as `update(items:)`: the hash guard (a call that
  /// changes nothing and leaves nothing to embed is a no-op), the reuse of
  /// vectors by the digest of the embedded text, the single-flight reload
  /// embed loop (the call returns when the embed that includes its own items
  /// is done), the new build of the selection tier when the content
  /// changed, and the end of the first-search catch-up. Each call runs in
  /// one `RegistryTelemetry.SpanName.catalogUpdate` span, whose item count
  /// is the count of `upserting` plus the count of `removing`.
  ///
  /// - Parameters:
  ///   - upserting: the items to add or replace.
  ///   - removing: the ids of the items to remove. Defaults to none.
  public func update(upserting: [Item], removing: [String] = []) async {
    await RegistryTelemetry.tracer(explicit: nil).withSpan(RegistryTelemetry.SpanName.catalogUpdate)
    { span in
      span.attributes[RegistryTelemetry.AttributeKey.catalogItemCount] =
        upserting.count + removing.count
      firstSearchCatchUp = .done
      let change = index.apply(
        upserting: upserting, removing: removing, onDiagnostic: onDiagnostic)
      await finish(change, recordingIn: span)
    }
  }
}
