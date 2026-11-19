import Foundation
import FoundationModelsExtras
import Tracing

/// Index-build/update-time embedding support for `MetadataIndex`: hash-keyed
/// incremental re-embedding (plan.md §8), the redundant-update guard, and
/// the batch-merge helpers `MetadataSearcher`'s catch-up paths call through.
extension MetadataIndex {
  /// The ids, the embedded texts and the embedded-text digests of the
  /// entries that wait for an embed, positionally aligned.
  struct PendingEmbeddings: Sendable {
    /// The ids, in catalog order.
    var ids: [String] = []

    /// The embedded text of each id.
    var texts: [String] = []

    /// The digest of each embedded text.
    var digests: [Data] = []
  }

  /// The vectors of one embed batch, and the embedded-text digest of each id
  /// at the time of the embed.
  ///
  /// `embedPendingEntries(with:source:limit:onDiagnostic:)` makes it. The
  /// caller merges it with `merge(_:)` or `merged(into:)`, into the index that
  /// it has after the embed. The batch keeps no copy of the index that it was
  /// embedded from: the digests are all that the merge checks.
  struct EmbeddedBatch: Sendable {
    /// The ids of the embedded entries, positionally aligned with `vectors`.
    let ids: [String]

    /// One vector for each id in `ids`.
    let vectors: [[Float]]

    /// The digest of the embedded text of each id, when the batch was
    /// embedded. The merge target must still have these digests.
    let embeddedTextDigests: [Data]

    /// Returns a copy of `index` with the vectors of this batch merged in.
    ///
    /// A vector lands only where the entry of `index` still has the
    /// embedded text that the vector was made from (see `merge(_:)`).
    ///
    /// - Parameter index: the index to merge into.
    /// - Returns: a copy of `index` with the vectors applied wherever the
    ///   hash check passed.
    func merged(into index: MetadataIndex<Item>) -> MetadataIndex<Item> {
      var merged = index
      merged.merge(self)
      return merged
    }
  }

  /// Merges the vectors of `batch` into this index.
  ///
  /// Each vector applies only where this index's *current* entry for that id
  /// still has the embedded-text digest that the batch recorded. Everything
  /// else is unchanged.
  ///
  /// The digest check is what makes that safe for the same id changing
  /// *twice* across overlapping updates, not just an id being removed: if
  /// a slower embed A (of id `"x"`'s old text) resolves after a faster,
  /// later embed B has already merged `"x"`'s *new* text, this index's entry
  /// for `"x"` carries B's digest, which no longer matches A's — so A's stale
  /// vector is skipped instead of silently overwriting B's correct, newer
  /// one. An id no longer present at all is likewise skipped, never
  /// resurrected.
  ///
  /// - Parameter batch: the batch to merge.
  /// - Returns: the ids whose vectors were stored.
  @discardableResult
  mutating func merge(_ batch: EmbeddedBatch) -> [String] {
    var stored: [String] = []
    for (id, (vector, digest)) in zip(batch.ids, zip(batch.vectors, batch.embeddedTextDigests))
    where setVector(vector, forID: id, embeddedTextDigest: digest) {
      stored.append(id)
    }
    return stored
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
  /// embedded-text digest both match `previous`'s, *and* whose `previous`
  /// entry actually carries an embedding, reuses that stored embedding
  /// rather than re-embedding unchanged text. A hash match against a
  /// missing previous embedding is **not** reused — the item is queued for
  /// embedding again here, exactly like a brand-new item (plan.md §8
  /// "embed catch-up"). `embedder.embed(texts:)` is called with exactly the
  /// new-or-changed-or-never-embedded texts, batched into a single call,
  /// never once per item.
  ///
  /// - Parameters:
  ///   - items: same as `init(items:onDiagnostic:)`.
  ///   - embedder: the embedder to embed new-or-changed texts with. `nil`
  ///     leaves every embedding `nil` (identical to `init(items:
  ///     onDiagnostic:)`).
  ///   - previous: the prior build of this index, if any, to reuse
  ///     embeddings from for unchanged `(id, embedded-text-hash)` pairs.
  ///     Defaults to `nil`.
  ///   - onDiagnostic: forwarded for duplicate-id reporting.
  /// - Returns: the built index, with embeddings populated wherever
  ///   `embedder` was configured and ran successfully. If
  ///   `embedder.embed(texts:)` throws, every item that would have been
  ///   (re-)embedded is left with no embedding — graceful degradation.
  public static func build(
    items: [Item],
    embedder: (any PooledEmbedding)?,
    previous: MetadataIndex<Item>? = nil,
    onDiagnostic: @Sendable (MetadataDiagnostic) -> Void = { MetadataDiagnostic.log($0) },
  ) async -> MetadataIndex<Item> {
    var index = previous ?? MetadataIndex()
    index.replaceAll(with: items, onDiagnostic: onDiagnostic)
    // An index build reports no `.embedCatchUp`: the embed is part of the
    // build, not a catch-up of an index that exists already.
    guard let embedder,
      let batch = await index.embedPendingEntries(with: embedder, source: .build)
    else { return index }
    index.merge(batch)
    return index
  }

  /// The entries with no embedding yet, in catalog order, at most `limit`.
  ///
  /// This is the batch an embed catch-up hands the embedder (plan.md §8).
  /// The embedded text of each entry is rendered again from its item and its
  /// block, so the index does not keep a third copy of each text.
  ///
  /// - Parameter limit: the maximum count of entries. Defaults to all.
  /// - Returns: the pending ids, their embedded texts and their digests, or
  ///   empty arrays when every entry already carries an embedding.
  func pendingEmbeddings(limit: Int = .max) -> PendingEmbeddings {
    var pending = PendingEmbeddings()
    for (id, slot) in zip(ids, slotOrder) {
      guard pending.ids.count < limit else { break }
      guard !vectors.hasVector(slot: slot), let entry = entries[slot] else { continue }
      pending.ids.append(id)
      pending.texts.append(entry.item.renderEmbeddedText(from: entry.block))
      pending.digests.append(entry.digests.embeddedText)
    }
    return pending
  }

  /// The count of entries with no embedding yet.
  var pendingEmbeddingCount: Int {
    count - vectors.count
  }

  /// Whether `self` and `other` index identical content (same ids, same order, same rendered-text digests).
  ///
  /// Embeddings are deliberately not part of this comparison.
  ///
  /// - Parameter other: the index to compare against.
  /// - Returns: whether both indexes are content-identical.
  func hasIdenticalContent(to other: MetadataIndex<Item>) -> Bool {
    guard ids == other.ids else { return false }
    return ids.allSatisfy { entry(forID: $0)?.digests == other.entry(forID: $0)?.digests }
  }
}

/// The one embed step that every catalog embed of this package goes through.
extension MetadataIndex {
  /// Embeds at most `limit` entries of this index that have no embedding, in one batch.
  ///
  /// Every catalog embed calls through this function: index build, the
  /// first-search catch-up and the reload embed loop of `MetadataSearcher`,
  /// and `SharedCatalogEmbedding`. The caller merges the result with
  /// `merge(_:)` or `EmbeddedBatch.merged(into:)`.
  ///
  /// A no-op, with no diagnostic, no span and no embedder call, when no
  /// entry is pending. Otherwise reports `.embedCatchUp(pending:total:)` one
  /// time before the embedder call, with the count of all pending entries.
  /// A failed embed is graceful degradation, not an error that the caller
  /// must handle: the caller keeps the embeddings it had.
  ///
  /// The embedder call runs in one `RegistryTelemetry.SpanName.catalogEmbed`
  /// span, which records the count of entries of the batch, the catalog
  /// size, `source` and the outcome. An embedder can wait for a long time,
  /// so the span opens through `RegistryTelemetry.withTracedSpan(_:attributes:_:)`
  /// (rule 8, hang detection). A failed embed also marks the span as failed.
  ///
  /// - Parameters:
  ///   - embedder: the embedder to embed the pending entries with.
  ///   - source: the path that started this embed, for the span.
  ///   - limit: the maximum count of entries in the batch. Defaults to all.
  ///   - onDiagnostic: called with `.embedCatchUp(pending:total:)` before
  ///     the embedder call. Defaults to reporting nothing.
  /// - Returns: the embedded batch, or `nil` when no entry is pending, when
  ///   `embed(texts:)` throws, or when it returns a vector count other than
  ///   the pending count.
  func embedPendingEntries(
    with embedder: any PooledEmbedding,
    source: RegistryTelemetry.EmbedSource,
    limit: Int = .max,
    onDiagnostic: @Sendable (MetadataDiagnostic) -> Void = { _ in },
  ) async -> EmbeddedBatch? {
    let pendingCount = pendingEmbeddingCount
    guard pendingCount > 0 else { return nil }
    let pending = pendingEmbeddings(limit: limit)
    onDiagnostic(.embedCatchUp(pending: pendingCount, total: count))
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
      return EmbeddedBatch(
        ids: pending.ids, vectors: vectors, embeddedTextDigests: pending.digests)
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
