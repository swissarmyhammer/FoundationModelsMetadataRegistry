/// The first-search embed catch-up of `MetadataSearcher` (plan.md §5, §8): a
/// searcher built synchronously with an embedder embeds its pending catalog
/// entries at its first search, one time, or awaits the one embed of a
/// `SharedCatalogEmbedding`.
extension MetadataSearcher {
  /// Where the one-time embed catch-up a synchronously built searcher runs at its first search stands.
  ///
  /// `init(items:mode:weights:embedder:selection:onDiagnostic:)` and
  /// `init(index:mode:weights:embedder:selection:onDiagnostic:)` are
  /// synchronous and cannot await an embedder, so a searcher built that
  /// way over not-yet-embedded
  /// items starts cosine-blind. Rather than reporting
  /// `.embeddingUnavailable` on every search until a caller runs
  /// `update(items:)`, the first `search(intent:limit:)` embeds every
  /// pending block itself, one time, before it ranks (plan.md §5, §8).
  /// One enum rather than a flag beside an optional task, so "not started",
  /// "in flight" and "finished" can never hold at once.
  enum FirstSearchCatchUp {
    /// No search has run yet; the first one runs the catch-up.
    case pending

    /// A search started the catch-up. Every search that arrives while
    /// `task` runs awaits it instead of embedding the same blocks a
    /// second time.
    case running(Task<Void, Never>)

    /// The catch-up ran, or `update(items:)` took the catch-up over, or
    /// there is no embedder to run it with.
    case done
  }

  /// Runs the first-search catch-up (see `FirstSearchCatchUp`) if it is still pending, or awaits the one in flight.
  ///
  /// Returns at once when the catch-up is `.done`. The stored `Task` is
  /// what makes two searches that arrive before the first embed resolves
  /// share one embedder call: the second one awaits the first one's task
  /// instead of embedding the same blocks again. The task is created here,
  /// stored in `firstSearchCatchUp`, and awaited by every caller, so it
  /// never outlives the catch-up it runs. Internal, not private, because
  /// `search(intent:limit:)` lives in its own file.
  func catchUpEmbeddingsBeforeFirstSearch() async {
    switch firstSearchCatchUp {
    case .done:
      return
    case .running(let task):
      await task.value
    case .pending:
      let task = Task { await self.runFirstSearchCatchUp() }
      firstSearchCatchUp = .running(task)
      await task.value
    }
  }

  /// Embeds every catalog entry that carries no embedding yet, then marks the first-search catch-up `.done`.
  ///
  /// A no-op -- no diagnostic, no embedder call -- when no embedder is
  /// configured or nothing is pending (an index that
  /// `MetadataIndex.build(items:embedder:previous:onDiagnostic:)` already
  /// embedded), so a searcher that needs no catch-up pays nothing
  /// beyond this check on its first search. Marks `.done` on every exit,
  /// a transient embed failure included: the catch-up runs one time, and
  /// the next `update(items:)` retries whatever is still pending.
  ///
  /// A searcher built with `init(sharing:mode:weights:selection:
  /// onDiagnostic:)` does not embed the catalog itself. It awaits the one
  /// shared embed of its `SharedCatalogEmbedding` and merges that batch
  /// into its own live `index`, through the same hash-checked
  /// `MetadataIndex.EmbeddedBatch.merged(into:)` as its own catch-up. Thus
  /// an `update(items:)` that changed `index` during the shared embed
  /// always wins. When the shared embed failed, there is no batch and this
  /// searcher stays keyword-only for the pending entries.
  private func runFirstSearchCatchUp() async {
    defer { firstSearchCatchUp = .done }
    if let sharedEmbedding {
      guard let batch = await sharedEmbedding.embeddedBatch() else { return }
      index = batch.merged(into: index)
      return
    }
    guard let embedder else { return }
    await catchUpEmbeddings(with: embedder, source: .firstSearch)
  }
}
