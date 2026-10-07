import FoundationModelsExtras
import Tracing

/// Index-build/update-time embedding support for `MetadataIndex`: hash-keyed
/// incremental re-embedding (plan.md §8), the redundant-update guard, and
/// the batch-merge helpers `MetadataSearcher`'s catch-up paths call through.
extension MetadataIndex {
  /// The result of `incrementalBaseline(items:previous:onDiagnostic:)`: the
  /// rebuilt baseline index, plus the ids of every entry still needing an
  /// embedder call.
  struct IncrementalBaseline: Sendable {
    /// The rebuilt index, with every reusable embedding already carried
    /// over from `previous`.
    let baseline: MetadataIndex<Item>

    /// The ids of every entry `baseline` still has no embedding for.
    let pendingEmbedIDs: [String]
  }

  /// The vectors of one embed batch, and the index that the batch was embedded from.
  ///
  /// `embedPendingEntries(with:source:onDiagnostic:)` makes it. The caller merges
  /// it with `merged(into:)`, into the index that it has after the embed.
  struct EmbeddedBatch: Sendable {
    /// The ids of the embedded entries, positionally aligned with `vectors`.
    let ids: [String]

    /// One vector for each id in `ids`.
    let vectors: [[Float]]

    /// The index that the batch was embedded from. Its embedded-text
    /// hashes are what the merge target must still match.
    let source: MetadataIndex<Item>

    /// Returns a copy of `index` with the vectors of this batch merged in.
    ///
    /// The merge goes through the hash check of
    /// `mergingEmbeddings(ids:vectors:embeddedFrom:into:)`: a vector lands
    /// only where the entry of `index` still has the embedded text that
    /// the vector was made from.
    ///
    /// - Parameter index: the index to merge into. This is `source` for
    ///   an index build, or the live index of a searcher, which can have
    ///   changed during the embed.
    /// - Returns: a copy of `index` with the vectors applied wherever the
    ///   hash check passed.
    func merged(into index: MetadataIndex<Item>) -> MetadataIndex<Item> {
      mergingEmbeddings(ids: ids, vectors: vectors, embeddedFrom: source, into: index)
    }
  }

  /// Builds an in-memory index from `items` with optional async embedding.
  ///
  /// Indexes `items` the same way `init(items:onDiagnostic:)` does
  /// (tokenizing, trigramming — always synchronous), then embeds each
  /// item's rendered embedded text through `embedder` (plan.md §5, §8) —
  /// embedding is the one part of index-build that's async, because
  /// it's the one part that may call out to a model.
  ///
  /// **Hash-keyed incremental re-embedding**: an item whose `id` and
  /// embedded-text `Entry.digests.embeddedText` both match `previous`'s,
  /// *and*
  /// whose `previous` entry actually carries a non-`nil` embedding,
  /// reuses that stored embedding rather than re-embedding unchanged
  /// text. A hash match against a `nil` previous embedding (no embedder
  /// was configured, or a transient embed failure, at that prior build)
  /// is **not** reused — the item is queued for embedding again here,
  /// exactly like a brand-new item, so it catches up as soon as an
  /// embedder is actually available instead of staying cosine-blind
  /// forever just because its text never changed (plan.md §8 "embed
  /// catch-up"). `embedder.embed(texts:)` is called with exactly the
  /// new-or-changed-or-never-embedded texts, batched into a single
  /// call, never once per item. This is what makes `update(items:)`
  /// (plan.md §8, a later task) cheap to call on every upstream change
  /// notification: unchanged, already-embedded items cost nothing here.
  ///
  /// - Parameters:
  ///   - items: same as `init(items:onDiagnostic:)`.
  ///   - embedder: the embedder to embed new-or-changed texts with. `nil`
  ///     leaves every embedding `nil` (identical to `init(items:
  ///     onDiagnostic:)`) — callers report `.embeddingUnavailable`
  ///     themselves (plan.md §5); this initializer never does, since it
  ///     has no `onDiagnostic` case reserved for "no embedder configured".
  ///   - previous: the prior build of this index, if any, to reuse
  ///     embeddings from for unchanged `(id, embedded-text-hash)` pairs.
  ///     Defaults to `nil` (nothing to reuse — every item is embedded
  ///     fresh).
  ///   - onDiagnostic: forwarded to `init(items:onDiagnostic:)` for
  ///     duplicate-id reporting.
  /// - Returns: the built index, with embeddings populated wherever
  ///   `embedder` was configured and ran successfully. If
  ///   `embedder.embed(texts:)`
  ///   throws, every item that would have been (re-)embedded this call is
  ///   left with whatever embedding it already had (`nil` for a new item) —
  ///   graceful degradation, matching plan.md §5's "no embedder configured"
  ///   handling rather than propagating a transient embedding failure.
  public static func build(
    items: [Item],
    embedder: (any PooledEmbedding)?,
    previous: MetadataIndex<Item>? = nil,
    onDiagnostic: @Sendable (MetadataDiagnostic) -> Void = { MetadataDiagnostic.log($0) },
  ) async -> MetadataIndex<Item> {
    let baseline = incrementalBaseline(items: items, previous: previous, onDiagnostic: onDiagnostic)
      .baseline
    // An index build reports no `.embedCatchUp`: the embed is part of the
    // build, not a catch-up of an index that exists already.
    guard let embedder,
      let batch = await baseline.embedPendingEntries(with: embedder, source: .build)
    else { return baseline }
    return batch.merged(into: baseline)
  }

  /// The synchronous, hash-guarded half of index-build/update.
  ///
  /// Indexes `items` exactly like `init(items:onDiagnostic:)` (tokenizing,
  /// trigramming), then reuses `previous`'s stored embedding for every
  /// item whose `id` and embedded-text hash both match a `previous` entry
  /// that actually carries a non-`nil` embedding.
  ///
  /// Factored out of `build(items:embedder:previous:onDiagnostic:)` so
  /// `MetadataSearcher.update(items:)` (plan.md §8, hot reload) can assign
  /// the returned baseline to its actor-isolated `index` *before* awaiting
  /// an embedder call for the returned `pendingEmbedIDs` —
  /// actor reentrancy across that later `await` is what lets a concurrent
  /// `search(intent:limit:)` see this rebuilt baseline and serve
  /// keyword-only results for the still-pending items in the interim,
  /// rather than blocking behind the whole re-embed.
  ///
  /// - Parameters:
  ///   - items: the catalog's items, in first-seen-wins duplicate-id order.
  ///   - previous: the prior build of this index, if any, to reuse
  ///     embeddings from for unchanged `(id, embedded-text-hash)` pairs.
  ///   - onDiagnostic: forwarded to `init(items:onDiagnostic:)` for
  ///     duplicate-id reporting.
  /// - Returns: the baseline index (embeddings carried over wherever reuse
  ///   applied, `nil` everywhere else), plus the ids still needing an
  ///   embedder call.
  static func incrementalBaseline(
    items: [Item],
    previous: MetadataIndex<Item>?,
    onDiagnostic: @Sendable (MetadataDiagnostic) -> Void,
  ) -> IncrementalBaseline {
    let baseline = MetadataIndex(items: items, onDiagnostic: onDiagnostic)
    var entriesByID = baseline.entriesByID

    for id in baseline.ids {
      // Reusing `previousEntry.embedding` is only valid when there is
      // an actual embedding to reuse: a `nil` embedding (no embedder
      // configured, or a transient embed failure, at the prior build)
      // must never be copied forward as if it were a cached result —
      // that would leave the item cosine-blind forever even once an
      // embedder becomes available, defeating "embed catch-up"
      // (plan.md §8). A hash match with no prior embedding leaves the
      // entry's embedding `nil`, so `pendingEmbeddings()` below queues
      // it for embedding, same as a brand-new item.
      //
      // The embedded text alone decides reuse: a vector is a function
      // of the text it was computed from, so an item whose block or
      // indexed text changed while its embedded text did not still
      // carries a valid vector.
      guard let entry = entriesByID[id],
        let previousEntry = previous?.entriesByID[id],
        previousEntry.digests.embeddedText == entry.digests.embeddedText,
        let previousEmbedding = previousEntry.embedding
      else { continue }
      entriesByID[id] = Self.withEmbedding(previousEmbedding, replacing: entry)
    }

    let reused = MetadataIndex(ids: baseline.ids, entriesByID: entriesByID)
    return IncrementalBaseline(baseline: reused, pendingEmbedIDs: reused.pendingEmbeddings().ids)
  }

  /// The ids and embedded texts of every entry with no embedding yet, positionally aligned, in `ids` order.
  ///
  /// This is the batch an embed catch-up hands the embedder (plan.md §8).
  /// `incrementalBaseline(items:previous:onDiagnostic:)` reads its ids off
  /// the baseline it just built, and `embedPendingEntries(with:source:
  /// onDiagnostic:)` reads it for each catalog embed.
  ///
  /// - Returns: the pending ids and their embedded texts, or two empty
  ///   arrays when every entry already carries an embedding.
  func pendingEmbeddings() -> (ids: [String], texts: [String]) {
    let pending = ids.compactMap { id -> (id: String, text: String)? in
      guard let entry = entriesByID[id], entry.embedding == nil else { return nil }
      return (id, entry.embeddedText)
    }
    return (pending.map(\.id), pending.map(\.text))
  }

  /// Returns a copy of `index` with `ids`' embeddings replaced by `vectors`.
  ///
  /// The vectors are positionally aligned with `ids`, and each replacement
  /// applies only where `index`'s *current* entry for that id still has the
  /// same embedded-text hash as `source`'s (the baseline this batch was
  /// actually embedded from). Everything else is unchanged.
  ///
  /// Merges into whichever index is passed as `into` — `build(items:
  /// embedder:previous:onDiagnostic:)` merges into its own freshly
  /// computed `baseline` (also passed as `source`, so the hash check is
  /// trivially satisfied there), while `MetadataSearcher.update(items:)`
  /// merges into its *current* `index` (which may have moved on since
  /// this re-embed started, if another `update(items:)` call interleaved
  /// during the `await`) rather than the stale baseline it kicked the
  /// embed off from.
  ///
  /// The hash check is what makes that safe for the same id changing
  /// *twice* across overlapping updates, not just an id being removed: if
  /// a slower call A (re-embedding id `"x"`'s old text) resolves after a
  /// faster, later call B has already re-embedded `"x"`'s *new* text and
  /// merged it in, `index`'s current entry for `"x"` carries B's hash,
  /// which no longer matches A's `source` hash for the old text — so A's
  /// stale vector is skipped instead of silently overwriting B's correct,
  /// newer one (which would otherwise pair fresh text with a vector
  /// embedded from stale text, with no diagnostic and no way to detect the
  /// corruption later, since the hash would still nominally "match" a
  /// naive by-id-only merge). An id no longer present in `index` at all is
  /// likewise simply skipped, never resurrected.
  ///
  /// - Parameters:
  ///   - ids: the ids to set embeddings for.
  ///   - vectors: one embedding per id, positionally aligned with `ids`.
  ///   - source: the index this embed batch was actually computed from —
  ///     `ids`' embedded-text hashes here are what `index`'s current
  ///     entries must still match for the merge to apply.
  ///   - index: the index to merge into.
  /// - Returns: a copy of `index` with those embeddings applied wherever
  ///   the hash check passed.
  static func mergingEmbeddings(
    ids: [String],
    vectors: [[Float]],
    embeddedFrom source: MetadataIndex<Item>,
    into index: MetadataIndex<Item>,
  ) -> MetadataIndex<Item> {
    var entriesByID = index.entriesByID
    for (id, vector) in zip(ids, vectors) {
      guard let entry = entriesByID[id], let sourceEntry = source.entriesByID[id],
        entry.digests.embeddedText == sourceEntry.digests.embeddedText
      else { continue }
      entriesByID[id] = Self.withEmbedding(vector, replacing: entry)
    }
    return MetadataIndex(ids: index.ids, entriesByID: entriesByID)
  }

  /// Whether `self` and `other` index identical content (same ids, same order, same rendered-text digests).
  ///
  /// This is `update(items:)`'s redundant-update guard (plan.md §8
  /// "hash-guarded"): calling `update` with content identical to what's
  /// already indexed must cost nothing
  /// (no re-embed, no selection-tier rebuild, no diagnostics), so callers
  /// may forward every upstream change notification without coalescing
  /// first. Every rendered text counts here, not just the embedded one
  /// reuse keys on: a changed block is what a `Match` hands back and a
  /// changed indexed text is what the keyword signals score, so an update
  /// carrying either has real work to do. Embeddings are deliberately not
  /// part of this comparison —
  /// `update(items:)` only ever calls this against a freshly rendered
  /// baseline, never against an index still catching up on embeddings, so
  /// there's no case where embeddings alone would need to make two
  /// otherwise-identical indexes compare unequal.
  ///
  /// - Parameter other: the index to compare against.
  /// - Returns: whether both indexes are content-identical.
  func hasIdenticalContent(to other: MetadataIndex<Item>) -> Bool {
    guard ids == other.ids else { return false }
    return ids.allSatisfy { entriesByID[$0]?.digests == other.entriesByID[$0]?.digests }
  }

  /// Returns a copy of `entry` with its `embedding` replaced by `embedding`.
  ///
  /// Every other field carries over unchanged. `Entry`'s fields are all
  /// `let`, so replacing one means rebuilding the whole value; this is
  /// the single place that does so — both `build`'s reuse and
  /// freshly-embedded branches go through it.
  ///
  /// - Parameters:
  ///   - embedding: the embedding to store, or `nil`.
  ///   - replacing: the entry to copy, with `embedding` replaced.
  /// - Returns: the copied entry with its embedding replaced.
  private static func withEmbedding(_ embedding: [Float]?, replacing entry: Entry) -> Entry {
    Entry(
      item: entry.item,
      block: entry.block,
      embeddedText: entry.embeddedText,
      rankedDocument: entry.rankedDocument,
      digests: entry.digests,
      embedding: embedding,
    )
  }

  /// Reconstructs an index directly from already-precomputed `ids` and `entriesByID`.
  ///
  /// The internal counterpart to `init(items:onDiagnostic:)` that
  /// `build(items:embedder:previous:onDiagnostic:)` uses to return a new
  /// index after filling in embeddings, without re-tokenizing or
  /// re-trigramming anything `baseline` already computed.
  ///
  /// - Parameters:
  ///   - ids: the precomputed ids, in first-seen order.
  ///   - entriesByID: the precomputed entries, keyed by id.
  private init(ids: [String], entriesByID: [String: Entry]) {
    self.ids = ids
    self.entriesByID = entriesByID
  }
}

/// The one embed step that every catalog embed of this package goes through.
extension MetadataIndex {
  /// Embeds the entries of this index that have no embedding, in one batch.
  ///
  /// Every catalog embed calls through this function: index build, the
  /// first-search catch-up and the reload embed loop of `MetadataSearcher`,
  /// and `SharedCatalogEmbedding`. The caller merges the result with
  /// `EmbeddedBatch.merged(into:)`.
  ///
  /// A no-op, with no diagnostic, no span and no embedder call, when no
  /// entry is pending. Otherwise reports `.embedCatchUp(pending:total:)` one
  /// time before the embedder call. A failed embed is graceful degradation,
  /// not an error that the caller must handle: the caller keeps the
  /// embeddings it had.
  ///
  /// The embedder call runs in one `RegistryTelemetry.SpanName.catalogEmbed`
  /// span, which records the pending count, the catalog size, `source` and
  /// the outcome. An embedder can wait for a long time, so the span opens
  /// through `RegistryTelemetry.withTracedSpan(_:attributes:_:)` (rule 8,
  /// hang detection). A failed embed also marks the span as failed.
  ///
  /// - Parameters:
  ///   - embedder: the embedder to embed the pending entries with.
  ///   - source: the path that started this embed, for the span.
  ///   - onDiagnostic: called with `.embedCatchUp(pending:total:)` before
  ///     the embedder call. Defaults to reporting nothing.
  /// - Returns: the embedded batch, or `nil` when no entry is pending, when
  ///   `embed(texts:)` throws, or when it returns a vector count other than
  ///   the pending count.
  func embedPendingEntries(
    with embedder: any PooledEmbedding,
    source: RegistryTelemetry.EmbedSource,
    onDiagnostic: @Sendable (MetadataDiagnostic) -> Void = { _ in },
  ) async -> EmbeddedBatch? {
    let pending = pendingEmbeddings()
    guard !pending.ids.isEmpty else { return nil }
    onDiagnostic(.embedCatchUp(pending: pending.ids.count, total: count))
    let attributes: SpanAttributes = [
      RegistryTelemetry.AttributeKey.embedPendingCount: pending.ids.count.toSpanAttribute(),
      RegistryTelemetry.AttributeKey.catalogSize: count.toSpanAttribute(),
      RegistryTelemetry.AttributeKey.embedSource: .string(source.rawValue),
    ]
    do {
      let vectors = try await RegistryTelemetry.withTracedSpan(
        RegistryTelemetry.SpanName.catalogEmbed,
        attributes: attributes,
      ) { span in
        try await Self.checkedVectors(for: pending.texts, with: embedder, in: span)
      }
      return EmbeddedBatch(ids: pending.ids, vectors: vectors, source: self)
    } catch {
      // Graceful degradation: the span recorded the failure, and the
      // caller keeps the embeddings it had.
      return nil
    }
  }

  /// Embeds `texts` and checks that the embedder gave one vector for each
  /// text, then records the outcome on `span`.
  ///
  /// - Parameters:
  ///   - texts: the embedded texts of the pending entries.
  ///   - embedder: the embedder to embed `texts` with.
  ///   - span: the embed span, which gets `RegistryTelemetry.AttributeKey.embedOutcome`.
  /// - Returns: one vector for each text, in the order of `texts`.
  /// - Throws: the error of `embed(texts:)`, or `EmbedVectorCountMismatch` when
  ///   the embedder gave a count of vectors other than the count of texts.
  private static func checkedVectors(
    for texts: [String],
    with embedder: any PooledEmbedding,
    in span: any Span,
  ) async throws -> [[Float]] {
    let outcomeKey = RegistryTelemetry.AttributeKey.embedOutcome
    do {
      let vectors = try await embedder.embed(texts: texts)
      guard vectors.count == texts.count else {
        throw EmbedVectorCountMismatch()
      }
      span.attributes[outcomeKey] = RegistryTelemetry.EmbedOutcome.embedded.rawValue
      return vectors
    } catch {
      span.attributes[outcomeKey] = RegistryTelemetry.EmbedOutcome.failed.rawValue
      throw error
    }
  }
}

/// Thrown inside a catalog embed when the embedder gives a count of vectors
/// other than the count of texts that it got. The embed span records it as
/// the failure of the embed.
struct EmbedVectorCountMismatch: Error {}
