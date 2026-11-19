import FoundationModelsExtras

/// The persistence option of `MetadataSearcher` and `SharedCatalogEmbedding`
/// (plan.md decision #10): the catalog and its vectors in a folder.
extension MetadataSearcher where Item: Codable {
  /// Builds a searcher over the catalog stored in `persistence.folder`, and
  /// saves each later change there.
  ///
  /// At its start, the searcher reads the stored items, their keyword
  /// statistics and their vectors. It embeds nothing and calls the caller
  /// for nothing, so a catalog of 100,000 items is searchable with cosine in
  /// a few seconds, not after a new embed of each item. An entry that was
  /// stored with no vector (for example after a crash during an embed) is
  /// embedded in the background by the reload embed loop; the searches in
  /// the interim rank it with the keyword signals only.
  ///
  /// The stored catalog is dropped, with a `.storedCatalogDropped`
  /// diagnostic, when its format is old, when it was written for another
  /// `persistence.embeddingModelID`, or when it is damaged. The searcher then
  /// starts empty, and the next update of the caller builds the catalog
  /// again. With an empty folder, the searcher starts empty.
  ///
  /// After each `update(items:)` or `update(upserting:removing:)` that
  /// changes the catalog, and after each embed chunk, the searcher saves on
  /// a background queue, off the path of the caller (see `waitForSaves()`).
  /// A crash keeps the last state that was written. A failed write reports
  /// `.catalogSaveFailed`.
  ///
  /// The search, the ranking, the tiers and the updates are the same as for
  /// a searcher with no persistence.
  ///
  /// - Parameters:
  ///   - persistence: the folder and the id of the embedding model of
  ///     `embedder`.
  ///   - mode: which tier `search(intent:limit:)` uses. Defaults to `.auto`.
  ///   - weights: the per-signal fusion weights for the retrieval tier.
  ///     Defaults to `1.0` for every signal.
  ///   - embedder: the embedder for the queries, and for the items that
  ///     have no stored vector. `nil` keeps the stored vectors and ranks with
  ///     the keyword signals only.
  ///   - selection: this searcher's selection tier configuration, or `nil`.
  ///   - decision: this searcher's decision tier configuration, or `nil`.
  ///   - onDiagnostic: called for every diagnostic, also those of the
  ///     stored catalog. Defaults to logging via `MetadataDiagnostic.log(_:)`.
  public init(
    persistence: CatalogPersistence,
    mode: SearchMode = .auto,
    weights: Weights = Weights(),
    embedder: (any PooledEmbedding)?,
    selection: SelectionConfig? = nil,
    decision: DecisionConfig? = nil,
    onDiagnostic: @escaping @Sendable (MetadataDiagnostic) -> Void = { MetadataDiagnostic.log($0) },
  ) async {
    let store = CatalogStore<Item>(persistence: persistence, onDiagnostic: onDiagnostic)
    let index = await store.load()
    self.init(
      index: index,
      mode: mode,
      weights: weights,
      embedder: embedder,
      sharedEmbedding: nil,
      store: store,
      catchUpAtFirstSearch: false,
      selection: selection,
      decision: decision,
      onDiagnostic: onDiagnostic,
    )
    if embedder != nil, index.pendingEmbeddingCount > 0 {
      Task { await self.embedStoredPendingEntries() }
    }
  }
}

extension MetadataSearcher {
  /// Returns when each save that this searcher asked for so far is written
  /// to its folder, or failed.
  ///
  /// A searcher with no persistence returns at once. Call it before the
  /// process ends, or in a test before a new searcher reads the folder.
  public func waitForSaves() async {
    await store?.waitForSaves()
  }

  /// Embeds the stored entries that have no vector, in the reload embed
  /// loop, unless an update already started the loop.
  func embedStoredPendingEntries() async {
    guard let embedder, case .idle = reloadEmbedLoop, index.pendingEmbeddingCount > 0 else {
      return
    }
    await embedNewestCatalog(with: embedder)
  }
}

extension SharedCatalogEmbedding where Item: Codable {
  /// Makes a shared catalog embed over the catalog stored in
  /// `persistence.folder`. Each searcher built over it with
  /// `MetadataSearcher.init(sharing:mode:weights:selection:decision:onDiagnostic:)`
  /// saves its changes there.
  ///
  /// The stored items and vectors are read here, with no embed. The first
  /// search of any sharing searcher embeds the stored entries that have no
  /// vector, one time, as for a shared embed with no persistence. The stored
  /// catalog is dropped on the same terms as for
  /// `MetadataSearcher.init(persistence:mode:weights:embedder:selection:decision:onDiagnostic:)`.
  ///
  /// Each sharing searcher saves after each change and each embed. A save
  /// writes only what differs from the stored catalog, so when the sharing
  /// searchers get the same updates, each change is written one time. When
  /// they get different updates, the stored catalog is the newest catalog
  /// that any of them saved.
  ///
  /// - Parameters:
  ///   - persistence: the folder and the id of the embedding model of
  ///     `embedder`.
  ///   - embedder: the embedder for the catalog, for each query, and for the
  ///     reloads of each sharing searcher.
  ///   - onDiagnostic: called with `.embedCatchUp` when the catalog embed
  ///     starts, and with the diagnostics of the stored catalog. Defaults to
  ///     logging via `MetadataDiagnostic.log(_:)`.
  public init(
    persistence: CatalogPersistence,
    embedder: any PooledEmbedding,
    onDiagnostic: @escaping @Sendable (MetadataDiagnostic) -> Void = { MetadataDiagnostic.log($0) },
  ) async {
    let store = CatalogStore<Item>(persistence: persistence, onDiagnostic: onDiagnostic)
    let index = await store.load()
    self.init(index: index, embedder: embedder, store: store, onDiagnostic: onDiagnostic)
  }

  /// Returns when each save of the sharing searchers so far is written to
  /// the folder, or failed.
  public nonisolated func waitForSaves() async {
    await store?.waitForSaves()
  }
}
