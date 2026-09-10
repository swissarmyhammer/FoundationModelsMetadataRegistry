/// Per-signal fusion weights for `MetadataSearcher`'s retrieval tier (plan.md §5).
///
/// FoundationModelsRanker's `SignalWeights` under this package's
/// established name: the relative weight `HybridRanker` gives each of the
/// BM25, trigram, and cosine rankings when fusing them.
///
/// A weight of `0.0` excludes that signal from the fused ranking entirely —
/// left out of the fusion and the normalization ceiling altogether, rather
/// than included at zero, so the ceiling never counts a signal that couldn't
/// have scored anything (plan.md §5 "absent-signal rule"). `cosine` only
/// takes effect when the searcher is configured with an embedder
/// (`init(items:mode:weights:embedder:onDiagnostic:)` or `init(index:mode:
/// weights:embedder:onDiagnostic:)`) — without one, cosine never ranks
/// anything regardless of this weight — and a zero `cosine` weight skips the
/// cosine computation without an `.embeddingUnavailable` diagnostic.
public typealias Weights = SignalWeights

/// Searches a catalog of `SearchableMetadata` on behalf of a Foundation Models session (plan.md §3).
///
/// An in-memory `MetadataIndex` plus the per-signal `Weights` retrieval
/// fuses by, exposed through one `search(intent:limit:)` entry point.
///
/// `.retrieval` (BM25 (two fields) + character-trigram Dice + cosine, when an
/// embedder is configured, fused and normalized to `[0, 1]` by
/// FoundationModelsRanker's `HybridRanker`, plan.md §5) answers with no
/// session, no tokens. Without an
/// `embedder` (or before any catalog item has been embedded), the cosine
/// signal never ranks anything and every `Match.signals.cosine` is `0.0` —
/// the same "no embedding available" value `Signals.cosine` documents, not a
/// crash or a special case (plan.md §5 "absent-signal rule") — and
/// `.embeddingUnavailable` is reported via `onDiagnostic` on every such
/// search, never silently. A searcher built synchronously with an embedder
/// over not-yet-embedded items (`init(index:mode:weights:embedder:
/// selection:onDiagnostic:)`) closes that gap itself: its first
/// `search(intent:limit:)` embeds every pending block one time before it
/// ranks (see `FirstSearchCatchUp`), so it never reports
/// `.embeddingUnavailable` for a catalog its embedder could have embedded.
/// `.selection` (plan.md §6) drives
/// FoundationModelsRanker's `SelectionTier` when one is configured
/// (`init(..., selection:)`), re-attaching each `SelectionMatch`'s typed
/// `item` by id lookup and mapping its `RankDiagnostic`s into the same-named
/// `MetadataDiagnostic` cases; otherwise it throws
/// `SelectionTierUnavailable` (FoundationModelsRanker's error, re-exported)
/// rather than silently doing something the caller didn't ask for. `.auto`
/// resolves to `.selection`
/// when a selection tier is configured, `.retrieval` otherwise (plan.md §7
/// "selection when a model is configured, else retrieval").
public actor MetadataSearcher<Item: SearchableMetadata> {
    /// The in-memory index built from the catalog's items at `init`.
    ///
    /// Replaced wholesale by `update(items:)` (plan.md §8, hot reload) on
    /// every real change.
    var index: MetadataIndex<Item>

    /// The per-signal fusion weights this searcher's retrieval tier uses.
    let weights: Weights

    /// Which tier `search(intent:limit:)` uses.
    let mode: SearchMode

    /// The embedder used to embed the *query* text at search time, or `nil` for keyword-only searches.
    ///
    /// Only the query itself is embedded per search (plan.md §5); without an
    /// embedder, cosine ranking is skipped and every search
    /// degrades to keyword-only. Catalog items are embedded in batches, not
    /// per search: at index-build time via `MetadataIndex.build(items:
    /// embedder:previous:onDiagnostic:)`, and by the two catch-ups that
    /// share `catchUpEmbeddings(ids:texts:embeddedFrom:with:)` —
    /// `update(items:)` for the blocks a reload changed, and the first
    /// search for a synchronously built index (see `FirstSearchCatchUp`).
    /// The same embedder instance is reused for both roles across every
    /// `update`.
    let embedder: (any TextEmbedding)?

    /// Called for every diagnostic emitted while building the index and while searching.
    ///
    /// Currently `.duplicateId`, `.embeddingUnavailable`,
    /// `.unknownSelectedId`, and `.embedCatchUp`.
    let onDiagnostic: @Sendable (MetadataDiagnostic) -> Void

    /// This searcher's selection tier configuration (plan.md §6), or `nil` when none was supplied at `init`.
    ///
    /// Kept around (rather than only
    /// building `selectionTier` once) so `update(items:)` can rebuild the
    /// tier from the same configuration whenever the index changes.
    let selectionConfig: SelectionConfig?

    /// A selection tier paired with the index snapshot it answers over.
    ///
    /// `selectionSearch(_:intent:limit:)` re-attaches each returned id's
    /// typed `item` from `snapshot`. A plain value, not a box: the pair is
    /// immutable for the tier's whole lifetime, because every real content
    /// change replaces the pair outright.
    ///
    /// Invariant: a pair's snapshot always has content (ids, blocks)
    /// identical to its tier's own catalog, so an `item` lookup can never
    /// disagree with the catalog generation the tier answered over.
    typealias ConfiguredSelectionTier = (tier: SelectionTier, snapshot: MetadataIndex<Item>)

    /// This searcher's selection tier (plan.md §6), or `nil` when no `SelectionConfig` was supplied at `init`.
    ///
    /// FoundationModelsRanker's
    /// `SelectionTier` over this searcher's index (its `SelectionCatalog`
    /// conformance), paired with the index snapshot it answers over (see
    /// `ConfiguredSelectionTier`). Without one, `.selection` throws
    /// `SelectionTierUnavailable`, exactly as it did before a
    /// selection tier existed at all. The snapshot keeps
    /// `Match.item`/`Match.block` consistent even if a concurrent
    /// `update(items:)` swaps `index` while a search is suspended in the
    /// tier. Rebuilt by `update(items:)` on every real catalog change
    /// (plan.md §8): a fresh `SelectionTier` starts with no cached root
    /// session, a prefix assembled from the new index, and an id-enum
    /// grammar derived from the new id set.
    var selectionTier: ConfiguredSelectionTier?

    /// Where the one-time embed catch-up a synchronously built searcher runs at its first search stands.
    ///
    /// `init(index:mode:weights:embedder:selection:onDiagnostic:)` cannot
    /// await an embedder, so a searcher built that way over not-yet-embedded
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

    /// This searcher's first-search catch-up state (see `FirstSearchCatchUp`).
    ///
    /// Starts `.done` when no embedder is configured — a keyword-only
    /// searcher has nothing to catch up, and its behavior is unchanged —
    /// and `.pending` otherwise.
    var firstSearchCatchUp: FirstSearchCatchUp

    /// Builds a searcher over `items`, indexing them once at `init` with no embedder.
    ///
    /// Cosine never ranks anything and every search degrades to
    /// keyword-only, reported via `.embeddingUnavailable` (plan.md §5). Use
    /// `init(items:mode:weights:embedder:onDiagnostic:)` to wire up cosine.
    ///
    /// - Parameters:
    ///   - items: the catalog's items, in first-seen-wins duplicate-id order
    ///     (forwarded to `MetadataIndex.init(items:onDiagnostic:)`).
    ///   - mode: which tier `search(intent:limit:)` uses. Defaults to
    ///     `.auto`, which falls back to `.retrieval` until a selection tier
    ///     is configured.
    ///   - weights: the per-signal fusion weights for the retrieval tier.
    ///     Defaults to `1.0` for every signal.
    ///   - selection: this searcher's selection tier configuration (plan.md
    ///     §6), or `nil` (the default) to leave `.selection` unavailable.
    ///   - onDiagnostic: called for every diagnostic emitted while building
    ///     the index (currently only `.duplicateId`), and by later tiers as
    ///     they land. Defaults to logging via `MetadataDiagnostic.log(_:)`.
    public init(
        items: [Item],
        mode: SearchMode = .auto,
        weights: Weights = Weights(),
        selection: SelectionConfig? = nil,
        onDiagnostic: @escaping @Sendable (MetadataDiagnostic) -> Void = { MetadataDiagnostic.log($0) },
    ) {
        self.init(
            index: MetadataIndex(items: items, onDiagnostic: onDiagnostic),
            mode: mode,
            weights: weights,
            embedder: nil,
            selection: selection,
            onDiagnostic: onDiagnostic,
        )
    }

    /// Builds a searcher over `items`, embedding every item's rendered block
    /// through `embedder` at index-build time (plan.md §5, §8).
    ///
    /// The stored embeddings are what let cosine join the fused ranking in
    /// `search(intent:limit:)`.
    ///
    /// - Parameters:
    ///   - items: the catalog's items, in first-seen-wins duplicate-id order
    ///     (forwarded to `MetadataIndex.build(items:embedder:previous:
    ///     onDiagnostic:)`).
    ///   - mode: which tier `search(intent:limit:)` uses. Defaults to
    ///     `.auto`, which falls back to `.retrieval` until a selection tier
    ///     is configured.
    ///   - weights: the per-signal fusion weights for the retrieval tier.
    ///     Defaults to `1.0` for every signal.
    ///   - embedder: the embedder to embed every item's block with at build
    ///     time, and the query with at search time. `nil` behaves like
    ///     `init(items:mode:weights:onDiagnostic:)` — keyword-only, with
    ///     `.embeddingUnavailable` reported on every search.
    ///   - selection: this searcher's selection tier configuration (plan.md
    ///     §6), or `nil` (the default) to leave `.selection` unavailable.
    ///   - onDiagnostic: called for every diagnostic emitted while building
    ///     the index and while searching. Defaults to logging via
    ///     `MetadataDiagnostic.log(_:)`.
    public init(
        items: [Item],
        mode: SearchMode = .auto,
        weights: Weights = Weights(),
        embedder: (any TextEmbedding)?,
        selection: SelectionConfig? = nil,
        onDiagnostic: @escaping @Sendable (MetadataDiagnostic) -> Void = { MetadataDiagnostic.log($0) },
    ) async {
        await self.init(
            index: MetadataIndex.build(items: items, embedder: embedder, onDiagnostic: onDiagnostic),
            mode: mode,
            weights: weights,
            embedder: embedder,
            selection: selection,
            onDiagnostic: onDiagnostic,
        )
    }

    /// Builds a searcher directly over an already-built `index`, synchronously.
    ///
    /// This is the seam
    /// `update(items:)` (plan.md §8), a consumer that must build its searcher
    /// with no `await` (a synchronous registry initializer that may start no
    /// task), and tests needing precise control over an index's embeddings
    /// (e.g. a mix of embedded and not-yet-embedded items) use instead of
    /// re-deriving the index from `items` on every call.
    ///
    /// Nothing is embedded here. With an `embedder`, every entry of `index`
    /// that carries no embedding is embedded at the first
    /// `search(intent:limit:)` instead, one time, before that search ranks
    /// (see `FirstSearchCatchUp`) — reported through `.embedCatchUp`, never
    /// through `.embeddingUnavailable`.
    ///
    /// - Parameters:
    ///   - index: the prebuilt index to search over.
    ///   - mode: which tier `search(intent:limit:)` uses. Defaults to
    ///     `.auto`.
    ///   - weights: the per-signal fusion weights for the retrieval tier.
    ///     Defaults to `1.0` for every signal.
    ///   - embedder: the embedder to embed the query with at search time, and
    ///     `index`'s not-yet-embedded entries with at the first search.
    ///     Defaults to `nil` (keyword-only).
    ///   - selection: this searcher's selection tier configuration (plan.md
    ///     §6), or `nil` (the default) to leave `.selection` unavailable.
    ///   - onDiagnostic: called for every diagnostic emitted while searching.
    ///     Defaults to logging via `MetadataDiagnostic.log(_:)`.
    public init(
        index: MetadataIndex<Item>,
        mode: SearchMode = .auto,
        weights: Weights = Weights(),
        embedder: (any TextEmbedding)? = nil,
        selection: SelectionConfig? = nil,
        onDiagnostic: @escaping @Sendable (MetadataDiagnostic) -> Void = { MetadataDiagnostic.log($0) },
    ) {
        self.index = index
        self.mode = mode
        self.weights = weights
        self.embedder = embedder
        self.onDiagnostic = onDiagnostic
        selectionConfig = selection
        firstSearchCatchUp = embedder == nil ? .done : .pending
        selectionTier = Self.buildSelectionTierIfConfigured(
            config: selection, index: index, onDiagnostic: onDiagnostic,
        )
    }

    /// Builds FoundationModelsRanker's `SelectionTier` over `index` when
    /// `config` is non-`nil`, or returns `nil` otherwise.
    ///
    /// The tier is built over `index`'s `SelectionCatalog` conformance, paired
    /// with `index` itself as the snapshot
    /// `selectionSearch(_:intent:limit:)` re-attaches typed items from
    /// (see `ConfiguredSelectionTier`) — the one piece of tier construction
    /// both the designated initializer and `update(items:)` (plan.md §8,
    /// hot reload) need whenever the underlying index changes: a fresh tier
    /// starts with no cached root session and a prefix assembled from
    /// `index`. The tier's `RankDiagnostic`s are mapped into the same-named
    /// `MetadataDiagnostic` cases.
    ///
    /// The tier itself ranks nothing: it makes one prompt that picks, so it
    /// needs neither the fusion weights nor the embedder this searcher's
    /// retrieval tier uses.
    ///
    /// `static`, not an instance method: the synchronous designated
    /// initializer builds the pair from its own parameters, and SE-0327's
    /// flow-sensitive actor-init isolation forbids writing `selectionTier`
    /// after any method call on `self` — so an instance-method form could
    /// never be shared with `init` at all.
    ///
    /// - Parameters:
    ///   - config: the selection tier configuration to build against, or
    ///     `nil` when this searcher has no selection tier.
    ///   - index: the catalog index the new tier answers `search(intent:
    ///     limit:)` calls over, and the paired snapshot.
    ///   - onDiagnostic: called for every diagnostic the new tier emits.
    /// - Returns: a freshly constructed selection tier over `index`, paired
    ///   with its snapshot — or `nil` when `config` is `nil`.
    static func buildSelectionTierIfConfigured(
        config: SelectionConfig?,
        index: MetadataIndex<Item>,
        onDiagnostic: @escaping @Sendable (MetadataDiagnostic) -> Void,
    ) -> ConfiguredSelectionTier? {
        guard let config else { return nil }
        return (
            tier: SelectionTier(
                catalog: index,
                config: config,
                onDiagnostic: { onDiagnostic(MetadataDiagnostic($0)) },
            ),
            snapshot: index,
        )
    }
}
