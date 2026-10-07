import FoundationModelsExtras
import Tracing

/// Hot reload, the search entry point and the `.selection` search tier for
/// `MetadataSearcher` (plan.md §6, §8). The `.retrieval` tier lives in
/// `MetadataSearcher+RetrievalTier.swift`, and the first-search embed
/// catch-up lives in `MetadataSearcher+FirstSearchCatchUp.swift`.
extension MetadataSearcher {
  /// Hot-reloads this searcher's catalog from `items`.
  ///
  /// 1. Re-renders blocks and rebuilds the tokenized/trigram indexes
  ///    synchronously (`MetadataIndex.incrementalBaseline(items:previous:
  ///    onDiagnostic:)`) and assigns the result to `index` immediately —
  ///    items are keyword-searchable (`.retrieval`/`.auto`'s BM25 +
  ///    trigram signals) before this call even reaches the embedder.
  /// 2. Re-embeds incrementally: only items whose `(id, block-hash)`
  ///    changed since the previous index are embedded, reusing every other
  ///    item's stored embedding. The embed runs in the single-flight reload
  ///    loop (see `ReloadEmbedLoop`), so a burst of calls embeds only the
  ///    newest catalog: when an embed is in flight, this call does not start
  ///    one of its own. It records that a newer catalog is pending, and the
  ///    loop embeds the pending ids of the current `index` when the embed in
  ///    flight ends. A burst of N calls thus causes at most two embed calls.
  ///    This step awaits the loop — an actor reentrancy point, so a
  ///    concurrent `search(intent:limit:)` interleaves and sees the
  ///    already-rebuilt keyword indexes with cosine absent for the
  ///    still-pending items (the absent-signal rule, plan.md §5), never
  ///    blocked behind the whole re-embed. Each real embed call reports its
  ///    pending/total gap one time via `MetadataDiagnostic.embedCatchUp(
  ///    pending:total:)`, so a call that joins a loop in flight reports
  ///    nothing of its own. This call also takes over the first-search
  ///    catch-up of a synchronously built searcher (see
  ///    `FirstSearchCatchUp`): once a
  ///    reload owns the embedding, a search that lands in this interim
  ///    window serves keyword-only rather than embedding the same pending
  ///    blocks a second time.
  /// 3. Rebuilds the selection tier over the new index. The new tier
  ///    assembles its prefix from the new catalog, so the next
  ///    `.selection`/`.auto` search sends the new catalog and the new id
  ///    set to the model. Each selection prompt goes to a new
  ///    `LanguageModelSession` on `SelectionConfig.model`, and nothing is
  ///    cached between searches.
  ///
  /// Hash-guarded: if `items` renders to content identical to what's
  /// already indexed (same ids, same block hashes) *and* nothing is
  /// pending an embed (every entry already carries a real embedding, or
  /// none is expected), this call is a complete no-op — no re-embedding,
  /// no selection-tier rebuild, no diagnostics — so callers may forward
  /// every upstream change notification (file watcher, MCP `listChanged`)
  /// without coalescing them first. The searcher coalesces a burst itself
  /// (step 2), so a caller never pays for the catalogs between the first
  /// and the newest. Content-identical but still catching
  /// up (e.g. a prior embed call failed transiently) still re-embeds, just
  /// without rebuilding the selection tier — nothing keyword/selection-
  /// relevant changed, only the still-missing embedding is worth
  /// finishing, and a rebuild would assemble the same prefix again.
  ///
  /// When this call returns, the embed catch-up that includes its own
  /// catalog is done (plan.md §8): a call that joins a loop in flight
  /// waits for the same loop, which embeds the current `index` before it
  /// stops. A caller that awaits `update(items:)` thus sees the embeddings
  /// of the newest catalog at once, the same as a caller that sends no
  /// burst. An embed that fails leaves its items pending for the next call.
  ///
  /// Each call runs in one `RegistryTelemetry.SpanName.catalogUpdate` span,
  /// the hash-guarded no-op included. The span records the item count, the
  /// size of the new catalog, whether the content changed, and the count
  /// of entries that wait for an embed. The embed of the reload loop runs
  /// in its own child `catalogEmbed` span. A call that assigns a new
  /// baseline records its size in the
  /// `RegistryTelemetry.MetricName.catalogSize` gauge. The hash-guarded
  /// no-op records nothing.
  ///
  /// - Parameter items: the catalog's new/refreshed items, in first-seen-
  ///   wins duplicate-id order (forwarded to `MetadataIndex`'s duplicate-id
  ///   policy).
  public func update(items: [Item]) async {
    await RegistryTelemetry.tracer(explicit: nil).withSpan(RegistryTelemetry.SpanName.catalogUpdate)
    { span in
      span.attributes[RegistryTelemetry.AttributeKey.catalogItemCount] = items.count
      await reload(items: items, recordingIn: span)
    }
  }

  /// Does the work of `update(items:)` in its span.
  ///
  /// - Parameters:
  ///   - items: the catalog's new/refreshed items.
  ///   - span: the `catalogUpdate` span, which gets the catalog size, the
  ///     content-changed flag and the pending embed count.
  private func reload(items: [Item], recordingIn span: any Span) async {
    // A reload owns the catch-up from here on: whatever this call leaves
    // pending is served keyword-only in the interim and embedded by this
    // call (or the next reload), never by a first search embedding the
    // same blocks a second time behind it.
    firstSearchCatchUp = .done
    let previous = index
    let result = MetadataIndex.incrementalBaseline(
      items: items,
      previous: previous,
      onDiagnostic: onDiagnostic,
    )
    let baseline = result.baseline

    let contentChanged = !baseline.hasIdenticalContent(to: previous)
    span.attributes[RegistryTelemetry.AttributeKey.catalogSize] = baseline.count
    span.attributes[RegistryTelemetry.AttributeKey.catalogContentChanged] = contentChanged
    span.attributes[RegistryTelemetry.AttributeKey.catalogPendingEmbedCount] =
      result.pendingEmbedIDs.count
    guard contentChanged || !result.pendingEmbedIDs.isEmpty else { return }

    index = baseline
    RegistryTelemetry.recordCatalogSize(baseline.count)
    // Rebuild the selection tier only when the content changed. An
    // embedding catch-up for the same content does not change keyword
    // search or the selection prefix, so a rebuild would assemble the
    // same prefix again.
    if contentChanged {
      selectionTier = Self.buildSelectionTierIfConfigured(
        config: selectionConfig, index: baseline, onDiagnostic: onDiagnostic,
      )
    }

    guard !result.pendingEmbedIDs.isEmpty, let embedder else { return }
    await embedNewestCatalog(with: embedder)
  }

  /// Embeds every entry of the live `index` that has no embedding, then merges the vectors into the live `index`.
  ///
  /// The one place a catch-up batch lands, shared by the reload embed loop
  /// (`runReloadEmbedLoop(with:)`) and the first-search catch-up
  /// (`runFirstSearchCatchUp()`). Internal, not private, because both
  /// callers live in their own files. The embed goes through
  /// `MetadataIndex.embedPendingEntries(with:source:onDiagnostic:)`: a no-op
  /// when nothing is pending, and otherwise one `.embedCatchUp` report
  /// before the embedder call, which runs in one `catalogEmbed` span.
  ///
  /// Merges into `index` as it stands *after* the suspension -- not into
  /// the stale baseline this batch was embedded from -- and only where
  /// `index`'s current entry still matches the baseline's block hash for
  /// that id (`MetadataIndex.EmbeddedBatch.merged(into:)`'s hash check).
  /// A concurrent `update(items:)` call may have
  /// moved the catalog on in the meantime (actor reentrancy across the
  /// `await`); its result must win, never be silently clobbered by this
  /// call's now-stale vector finishing late -- including when that
  /// concurrent call re-embedded the *same* id with different content,
  /// not just when it removed the id outright.
  ///
  /// The selection tier is left alone. A merge changes stored vectors and
  /// never content, and the tier ranks nothing, so a caught-up embedding
  /// changes no answer the tier can give.
  ///
  /// An embedder that throws, or returns a vector count other than the
  /// pending count, leaves every entry with whatever embedding it had --
  /// graceful degradation, the same as `MetadataIndex.build(items:
  /// embedder:previous:onDiagnostic:)`; a later search then reports the
  /// still-absent embeddings via `.embeddingUnavailable`.
  ///
  /// - Parameters:
  ///   - embedder: the embedder to embed the pending entries with.
  ///   - source: the path that started this catch-up, for the embed span:
  ///     `.reload` or `.firstSearch`.
  func catchUpEmbeddings(with embedder: any PooledEmbedding, source: RegistryTelemetry.EmbedSource)
    async
  {
    let batch = await index.embedPendingEntries(
      with: embedder, source: source, onDiagnostic: onDiagnostic)
    guard let batch else { return }
    index = batch.merged(into: index)
  }

  /// Searches the catalog for `intent`, returning at most `limit` matches ordered by descending fused score.
  ///
  /// The first call on a searcher built synchronously with an embedder
  /// embeds every not-yet-embedded catalog entry before it ranks, one
  /// time, whichever tier `mode` selects (see `FirstSearchCatchUp`); every
  /// later call ranks straight away.
  ///
  /// Each call runs in one `RegistryTelemetry.SpanName.search` span, which
  /// also covers the first-search catch-up. The span records the mode, the
  /// limit, the catalog size, the tier that answered, the signals that
  /// ranked and the count of matches. The call to the ranker runs in one
  /// child `rank` span. A model session and an embedder can wait for a long
  /// time, so the span opens through
  /// `RegistryTelemetry.withTracedSpan(_:attributes:_:)` (rule 8, hang
  /// detection). When the call throws, the span records the error status
  /// and the type of the error, never the message of the error. The span
  /// never holds `intent` (rule 4).
  ///
  /// Each call records one `RegistryTelemetry.MetricName.searchDuration`
  /// value, also when it throws, and one
  /// `RegistryTelemetry.MetricName.rankDuration` value when a ranker ran.
  /// No metric dimension holds `intent` (rule 4).
  ///
  /// - Parameters:
  ///   - intent: the search query.
  ///   - limit: the maximum number of matches to return. `limit <= 0`
  ///     yields an empty result rather than throwing or crashing.
  /// - Returns: `.retrieval`'s fused, `[0, 1]`-normalized matches;
  ///   `.selection`'s verbatim matches when a selection tier is configured
  ///   (plan.md §6); `.auto`'s resolution of whichever of those applies
  ///   (plan.md §7).
  /// - Throws: `SelectionTierUnavailable` when `mode == .selection` and no
  ///   selection tier is configured (`init(..., selection:)`); otherwise
  ///   whatever the underlying selection session throws.
  public func search(intent: String, limit: Int) async throws -> [Match<Item>] {
    let attributes: SpanAttributes = [
      RegistryTelemetry.AttributeKey.searchMode: .string(mode.rawValue),
      RegistryTelemetry.AttributeKey.searchLimit: limit.toSpanAttribute(),
    ]
    return try await RegistryTelemetry.withTracedSpan(
      RegistryTelemetry.SpanName.search,
      attributes: attributes,
    ) { span in
      try await self.answer(intent: intent, limit: limit, recordingIn: span)
    }
  }

  /// The answer of one tier, and the facts about it that the search span records.
  struct TierAnswer: Sendable {
    /// The tier that answered.
    let tier: RegistryTelemetry.Tier

    /// The signals that ranked the answer, in a fixed order.
    let signals: [RegistryTelemetry.Signal]

    /// The matches of the answer.
    let matches: [Match<Item>]
  }

  /// The tier that `mode` selects for one search.
  ///
  /// One value for the choice, so the tier that answers and the tier that
  /// the metrics of a failed search name come from the same switch.
  enum TierRoute {
    /// The retrieval tier answers.
    case retrieval

    /// The configured selection tier answers.
    case selection(ConfiguredSelectionTier)

    /// `mode` is `.selection`, and no selection tier is configured.
    case unavailable

    /// The tier of this route, or `nil` for `unavailable`.
    var tier: RegistryTelemetry.Tier? {
      switch self {
      case .retrieval: .retrieval
      case .selection: .selection
      case .unavailable: nil
      }
    }
  }

  /// The tier that `mode` selects now: `.auto` selects the selection tier
  /// when one is configured, and the retrieval tier when none is.
  private var tierRoute: TierRoute {
    switch mode {
    case .retrieval:
      .retrieval
    case .selection:
      selectionTier.map(TierRoute.selection) ?? .unavailable
    case .auto:
      selectionTier.map(TierRoute.selection) ?? .retrieval
    }
  }

  /// Does the work of `search(intent:limit:)` in its span.
  ///
  /// Records one `RegistryTelemetry.MetricName.searchDuration` value, also
  /// when the search throws. The `tier` dimension of a search that returns
  /// is the tier that the span records.
  ///
  /// - Parameters:
  ///   - intent: the search query.
  ///   - limit: the maximum number of matches to return.
  ///   - span: the `search` span, which gets the catalog size, the tier,
  ///     the signals and the count of matches.
  /// - Returns: the matches of the tier that `mode` selects.
  /// - Throws: what `tierAnswer(_:intent:limit:)` throws.
  private func answer(intent: String, limit: Int, recordingIn span: any Span) async throws
    -> [Match<Item>]
  {
    let start = ContinuousClock.now
    await catchUpEmbeddingsBeforeFirstSearch()
    span.attributes[RegistryTelemetry.AttributeKey.catalogSize] = index.count
    let route = tierRoute
    let answer: TierAnswer
    do {
      answer = try await tierAnswer(route, intent: intent, limit: limit)
    } catch {
      RegistryTelemetry.recordSearchDuration(
        start.duration(to: .now), tier: route.tier, outcome: .error)
      throw error
    }
    RegistryTelemetry.recordSearchDuration(
      start.duration(to: .now), tier: answer.tier, outcome: .success)
    span.attributes[RegistryTelemetry.AttributeKey.searchTier] = answer.tier.rawValue
    span.attributes[RegistryTelemetry.AttributeKey.searchRankers] = answer.signals.map(\.rawValue)
    span.attributes[RegistryTelemetry.AttributeKey.searchResultCount] = answer.matches.count
    return answer.matches
  }

  /// Answers one search with the tier of `route`.
  ///
  /// - Parameters:
  ///   - route: the tier that `mode` selected.
  ///   - intent: the search query.
  ///   - limit: the maximum number of matches to return.
  /// - Returns: the answer of the tier.
  /// - Throws: `SelectionTierUnavailable` when `route` is `unavailable`;
  ///   otherwise whatever the underlying selection session throws.
  private func tierAnswer(_ route: TierRoute, intent: String, limit: Int) async throws -> TierAnswer
  {
    switch route {
    case .retrieval:
      return await retrievalSearch(intent: intent, limit: limit)
    case .selection(let selection):
      return try await Self.selectionSearch(selection, intent: intent, limit: limit)
    case .unavailable:
      throw SelectionTierUnavailable()
    }
  }

  // MARK: - Selection tier (plan.md §6, via FoundationModelsRanker)

  /// Answers one `.selection`/`.auto` search through FoundationModelsRanker's `SelectionTier`.
  ///
  /// Maps each returned `SelectionMatch` into this
  /// package's typed `Match<Item>` by looking its id up in the tier's
  /// paired index snapshot — the tier's `SelectionCatalog` carries no item
  /// type, so the typed `item` is re-attached here. The lookup is against
  /// `selection.snapshot` (not the actor's live `index`) so `Match.item`
  /// always pairs with the same catalog generation that produced
  /// `Match.block`, even if a concurrent `update(items:)` swapped the
  /// live index while this call was suspended in the tier (the snapshot's
  /// content always matches the tier's own catalog — see
  /// `ConfiguredSelectionTier`'s invariant). Every id the tier returns
  /// resolves in that snapshot by construction (the tier filters unknown
  /// ids itself); the `compactMap` is defensive.
  ///
  /// The call to the tier runs in one `RegistryTelemetry.SpanName.rank`
  /// span, with the `selection` ranker and the snapshot size as the
  /// candidate count. The tier waits on a model session, so the span opens
  /// through `RegistryTelemetry.withTracedSpan(_:attributes:_:)` (rule 8).
  /// The call records one `RegistryTelemetry.MetricName.rankDuration`
  /// value with the `selection` ranker, also when the session throws.
  ///
  /// - Parameters:
  ///   - selection: the tier to search, paired with the index snapshot it
  ///     answers over.
  ///   - intent: the plain-language search intent.
  ///   - limit: the maximum number of matches to return.
  /// - Returns: the selected items' verbatim `Match`es, at most `limit`,
  ///   with the `selection` tier and signal.
  /// - Throws: whatever the tier's underlying session throws.
  private static func selectionSearch(
    _ selection: ConfiguredSelectionTier,
    intent: String,
    limit: Int,
  ) async throws -> TierAnswer {
    let snapshot = selection.snapshot
    let attributes: SpanAttributes = [
      RegistryTelemetry.AttributeKey.rankRanker: .string(
        RegistryTelemetry.Ranker.selection.rawValue),
      RegistryTelemetry.AttributeKey.rankCandidateCount: snapshot.count.toSpanAttribute(),
    ]
    let selectionMatches = try await RegistryTelemetry.withTracedSpan(
      RegistryTelemetry.SpanName.rank,
      attributes: attributes,
    ) { _ in
      try await RegistryTelemetry.rankTimer(for: .selection).measure {
        try await selection.tier.search(intent: intent, limit: limit)
      }
    }
    let matches = selectionMatches.compactMap { match -> Match<Item>? in
      guard let item = snapshot.item(forID: match.id) else { return nil }
      return Match(
        id: match.id, block: match.block, score: match.score, signals: match.signals, item: item)
    }
    return TierAnswer(tier: .selection, signals: [.selection], matches: matches)
  }
}
