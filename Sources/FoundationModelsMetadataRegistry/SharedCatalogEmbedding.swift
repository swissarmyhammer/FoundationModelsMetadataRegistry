/// One first-search catalog embed that two or more `MetadataSearcher`s share
/// (plan.md §5, §8).
///
/// A consumer that must build its searchers with no `await` uses
/// `MetadataSearcher.init(index:mode:weights:embedder:selection:onDiagnostic:)`
/// over a not-yet-embedded index. Each searcher built that way embeds the
/// whole catalog at its own first search, so two searchers over one catalog
/// embed it two times. Build one `SharedCatalogEmbedding` from the index and
/// the embedder, and give it to each searcher through
/// `MetadataSearcher.init(sharing:mode:weights:selection:onDiagnostic:)`.
/// Then the catalog is embedded one time in total:
///
/// ```swift
/// let shared = SharedCatalogEmbedding(index: MetadataIndex(items: items), embedder: embedder)
/// let hints = MetadataSearcher(sharing: shared, mode: .retrieval, weights: hintWeights)
/// let discovery = MetadataSearcher(sharing: shared, weights: discoveryWeights)
/// ```
///
/// The init is synchronous and embeds nothing. The first search of any
/// sharing searcher starts the catalog embed. The embed is single flight:
/// every search that arrives while it runs awaits the same embed, and every
/// later search gets its result at once. A failed embed is not tried again
/// for the life of this value, and each sharing searcher stays keyword-only.
public actor SharedCatalogEmbedding<Item: SearchableMetadata> {
    /// Where the one catalog embed of this value stands.
    ///
    /// One enum rather than an optional task, so "not started" is a named
    /// state and not a missing value.
    enum CatalogEmbed {
        /// No search has asked for the catalog embed yet.
        case pending

        /// A search started the catalog embed. `task` returns the embedded
        /// index. Every later caller awaits the same `task`, also after it
        /// completed, so the catalog is embedded one time only.
        case started(Task<MetadataIndex<Item>, Never>)
    }

    /// The index that each sharing searcher starts from. It is not embedded
    /// here: the catalog embed embeds its pending entries.
    nonisolated let index: MetadataIndex<Item>

    /// The embedder for the catalog embed, and for the queries and reloads of
    /// each sharing searcher.
    nonisolated let embedder: any TextEmbedding

    /// Called with `.embedCatchUp` one time, when the catalog embed starts.
    let onDiagnostic: @Sendable (MetadataDiagnostic) -> Void

    /// The state of the one catalog embed (see `CatalogEmbed`).
    private var catalogEmbed: CatalogEmbed

    /// Makes a shared catalog embed over `index`, synchronously.
    ///
    /// Nothing is embedded here. The first search of a searcher built with
    /// `MetadataSearcher.init(sharing:mode:weights:selection:onDiagnostic:)`
    /// over this value starts the catalog embed.
    ///
    /// - Parameters:
    ///   - index: the catalog index that the sharing searchers search. Its
    ///     entries with no embedding are embedded one time, at the first
    ///     search of any sharing searcher.
    ///   - embedder: the embedder for the catalog, for each query, and for
    ///     the reloads of each sharing searcher.
    ///   - onDiagnostic: called with `.embedCatchUp(pending:total:)` one time,
    ///     when the catalog embed starts. The sharing searchers do not report
    ///     the catalog embed themselves. Defaults to logging via
    ///     `MetadataDiagnostic.log(_:)`.
    public init(
        index: MetadataIndex<Item>,
        embedder: any TextEmbedding,
        onDiagnostic: @escaping @Sendable (MetadataDiagnostic) -> Void = { MetadataDiagnostic.log($0) },
    ) {
        self.index = index
        self.embedder = embedder
        self.onDiagnostic = onDiagnostic
        catalogEmbed = .pending
    }

    /// Returns `index` with its pending entries embedded, and embeds them on the first call only.
    ///
    /// The first call starts the catalog embed in a stored `Task`. Every
    /// other call, concurrent or later, awaits that same task. The task is
    /// not cancelled when a caller is cancelled, so one cancelled search does
    /// not cancel the embed that the other searchers wait for.
    ///
    /// - Returns: `index` with an embedding for each entry that the embed
    ///   gave a vector. When the embed failed, `index` with no new
    ///   embeddings.
    func embeddedIndex() async -> MetadataIndex<Item> {
        switch catalogEmbed {
        case .started(let task):
            return await task.value
        case .pending:
            let index = index
            let embedder = embedder
            let onDiagnostic = onDiagnostic
            let task = Task {
                await Self.embeddingPendingEntries(of: index, with: embedder, onDiagnostic: onDiagnostic)
            }
            catalogEmbed = .started(task)
            return await task.value
        }
    }

    /// Embeds the pending entries of `index` in one batch, and returns the embedded index.
    ///
    /// A no-op, with no diagnostic and no embedder call, when no entry of
    /// `index` is pending. Otherwise reports `.embedCatchUp(pending:total:)`
    /// one time before the embedder call.
    ///
    /// - Parameters:
    ///   - index: the index to embed the pending entries of.
    ///   - embedder: the embedder to embed them with.
    ///   - onDiagnostic: called with `.embedCatchUp(pending:total:)`.
    /// - Returns: `index` with the new vectors merged in, or `index` with no
    ///   change when the embed failed.
    private static func embeddingPendingEntries(
        of index: MetadataIndex<Item>,
        with embedder: any TextEmbedding,
        onDiagnostic: @Sendable (MetadataDiagnostic) -> Void,
    ) async -> MetadataIndex<Item> {
        let pending = index.pendingEmbeddings()
        guard !pending.ids.isEmpty else { return index }
        onDiagnostic(.embedCatchUp(pending: pending.ids.count, total: index.count))
        guard let vectors = await embedder.checkedVectors(for: pending.texts) else { return index }
        return MetadataIndex.mergingEmbeddings(ids: pending.ids, vectors: vectors, embeddedFrom: index, into: index)
    }
}

public extension MetadataSearcher {
    /// Builds a searcher synchronously over the index of `shared`, and shares
    /// the first-search catalog embed of `shared` with every other searcher
    /// built over it.
    ///
    /// Use this initializer when two or more searchers must search one
    /// catalog with different `mode`s or `weights`, and must be built with no
    /// `await`. Each searcher built with `init(index:mode:weights:embedder:
    /// selection:onDiagnostic:)` embeds the catalog at its own first search.
    /// Searchers built with this initializer over one `shared` value cause
    /// one catalog embed in total.
    ///
    /// Nothing is embedded here. The first `search(intent:limit:)` of any
    /// sharing searcher starts the catalog embed of `shared` (single flight),
    /// and the first search of each sharing searcher awaits that one embed
    /// and merges its vectors into its own index. The rankings are the same
    /// as the rankings of a searcher that ran its own catch-up. When the
    /// shared embed fails, each sharing searcher stays keyword-only, and
    /// `shared` does not embed the catalog again.
    ///
    /// Each searcher keeps its own index after its first search:
    /// `update(items:)` on one sharing searcher changes only that searcher,
    /// and embeds its reload through the embedder of `shared`.
    ///
    /// - Parameters:
    ///   - shared: the shared catalog embed. It supplies the index, and the
    ///     embedder for the catalog, for queries and for reloads.
    ///   - mode: which tier `search(intent:limit:)` uses. Defaults to
    ///     `.auto`.
    ///   - weights: the per-signal fusion weights for the retrieval tier.
    ///     Defaults to `1.0` for every signal.
    ///   - selection: this searcher's selection tier configuration (plan.md
    ///     §6), or `nil` (the default) to leave `.selection` unavailable.
    ///   - onDiagnostic: called for every diagnostic emitted while searching.
    ///     The shared catalog embed reports `.embedCatchUp` through the
    ///     `onDiagnostic` of `shared`, not through this one. Defaults to
    ///     logging via `MetadataDiagnostic.log(_:)`.
    init(
        sharing shared: SharedCatalogEmbedding<Item>,
        mode: SearchMode = .auto,
        weights: Weights = Weights(),
        selection: SelectionConfig? = nil,
        onDiagnostic: @escaping @Sendable (MetadataDiagnostic) -> Void = { MetadataDiagnostic.log($0) },
    ) {
        self.init(
            index: shared.index,
            mode: mode,
            weights: weights,
            embedder: shared.embedder,
            sharedEmbedding: shared,
            selection: selection,
            onDiagnostic: onDiagnostic,
        )
    }
}
