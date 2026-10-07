import FoundationModelsExtras

/// The single-flight reload embed loop of `MetadataSearcher.update(items:)`
/// (plan.md §8): a burst of updates embeds only the newest catalog.
extension MetadataSearcher {
  /// Where the single-flight embed loop of `update(items:)` stands (plan.md §8).
  ///
  /// A burst of `update(items:)` calls can arrive while an embed is in
  /// flight. Each call replaces `index` at once, so only the newest catalog
  /// is worth an embed. One loop embeds at a time. A call that arrives
  /// while the loop embeds records that a newer catalog is pending and
  /// waits for the same loop. When the embed in flight ends, the loop reads
  /// the pending ids of the current `index` again and embeds them one more
  /// time. Thus a burst of N calls causes at most two embed calls: the one
  /// in flight and one for the newest catalog.
  ///
  /// One enum rather than a flag beside an optional task, so "no loop" and
  /// "a newer catalog is pending" can never hold at once.
  enum ReloadEmbedLoop {
    /// No embed loop runs. The next `update(items:)` that has pending
    /// embeddings starts one.
    case idle

    /// A loop runs `task`, and no catalog arrived after the embed in
    /// flight started. The loop stops when that embed ends.
    case running(Task<Void, Never>)

    /// A loop runs `task`, and an `update(items:)` call replaced the
    /// catalog after the embed in flight started. The loop embeds the
    /// pending ids of the current `index` one more time when that embed
    /// ends.
    case runningWithNewerCatalog(Task<Void, Never>)
  }

  /// Starts the reload embed loop (see `ReloadEmbedLoop`), or joins the one in flight, and awaits it.
  ///
  /// With no loop in flight, this starts one. With a loop in flight, this
  /// marks that a newer catalog is pending, so that the loop embeds the
  /// current `index` one more time when its embed in flight ends. In both
  /// cases the caller awaits the same task, so it returns only after the
  /// loop has embedded a catalog at least as new as the one the caller
  /// assigned. The task is created here, stored in `reloadEmbedLoop`, and
  /// awaited by every caller, so it never outlives the loop it runs.
  ///
  /// - Parameter embedder: the embedder the loop embeds with.
  func embedNewestCatalog(with embedder: any PooledEmbedding) async {
    switch reloadEmbedLoop {
    case .idle:
      let task = Task { await self.runReloadEmbedLoop(with: embedder) }
      reloadEmbedLoop = .running(task)
      await task.value
    case .running(let task), .runningWithNewerCatalog(let task):
      reloadEmbedLoop = .runningWithNewerCatalog(task)
      await task.value
    }
  }

  /// Embeds the pending ids of the current `index`, again while a newer catalog arrived during the embed.
  ///
  /// Each pass reads `index.pendingEmbeddings()` after the previous embed
  /// ended, so a pass never embeds a catalog that a later `update(items:)`
  /// replaced before the pass started. A pass repeats only when
  /// `takeNewerCatalogRequest()` finds a request. Thus a burst of N calls
  /// causes at most two embed calls, and an embed that fails does not loop.
  /// Marks the loop `.idle` on every exit. No `await` stands between the
  /// last check for a request and that mark, so a call that arrives later
  /// starts a new loop and is never lost.
  ///
  /// - Parameter embedder: the embedder to embed each pass with.
  private func runReloadEmbedLoop(with embedder: any PooledEmbedding) async {
    defer { reloadEmbedLoop = .idle }
    repeat {
      await catchUpEmbeddings(with: embedder, source: .reload)
    } while takeNewerCatalogRequest()
  }

  /// Clears a pending newer-catalog request of the reload embed loop.
  ///
  /// - Returns: whether an `update(items:)` call replaced the catalog while
  ///   the embed in flight ran — that is, whether the loop must make one
  ///   more pass.
  private func takeNewerCatalogRequest() -> Bool {
    guard case .runningWithNewerCatalog(let task) = reloadEmbedLoop else { return false }
    reloadEmbedLoop = .running(task)
    return true
  }
}
