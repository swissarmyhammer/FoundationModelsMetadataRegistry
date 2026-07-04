import ExamplesSupport
import Foundation
import FoundationModelsMetadataRegistry
import LiveRouterSupport

/// # `BigCatalog`'s entry logic (plan.md §13 M8): the headroom story.
///
/// A synthetic ~10^3-entry catalog (ids = URIs) proves the retrieval tier's
/// in-memory, GPU-free story scales well past the half-dozen-item demos
/// `CatalogSearch`/`SemanticSearch` use: `runBigCatalogRetrieval(catalog:
/// query:limit:)` builds a keyword-only `MetadataSearcher(mode: .retrieval)`
/// over the whole catalog and reports how long indexing + search actually
/// took. Only when `ExamplesSupport.metadataRegistryIntegrationEnabled` is
/// set does `runBigCatalogOverBudgetSelection(catalog:query:)` also drive
/// the `.selection` tier's **over-budget** path (plan.md §6): the assembled
/// prefix for ~1,000 items overflows any reasonable capacity, so
/// `SelectionTier` ranks the whole catalog, keeps the top-M candidates, and
/// seeds a fresh one-off session with them -- reported via
/// `.retrievalCut(considered:kept:)`.
///
/// Factored into this library target (rather than living directly in
/// `BigCatalog`'s `main.swift`) so `ExamplesSmokeTests` can import and invoke
/// the GPU-free retrieval-timing path directly, with no `swift run`
/// subprocess spawning.

// MARK: - Fixture catalog

/// This example's domain-flavored alias for `ExamplesSupport`'s shared
/// `SearchableFixtureItem`: a URI id (mirrors an MCP resource or a code
/// symbol's stable locator) and a short synthetic description.
public typealias BigCatalogItem = SearchableFixtureItem

/// The id of the one deterministic "needle" entry `makeBigCatalog(count:)`
/// always appends, distinct from every generic filler entry so a query
/// naming it has exactly one real match to find in a haystack of ~10^3
/// otherwise-generic items.
public let bigCatalogNeedleId = "https://example.com/modules/quantum-flux-capacitor"

/// The needle entry's synthetic description.
public let bigCatalogNeedleBlock = "Provides quantum flux capacitor calibration routines for temporal synchronization."

/// A query that shares its distinctive keywords with `bigCatalogNeedleBlock`
/// alone -- every filler entry's generic "component handling ... tasks"
/// phrasing shares none of them.
public let bigCatalogNeedleQuery = "quantum flux capacitor calibration"

/// The synthetic topics filler entries rotate through, giving the catalog
/// some lexical variety without hand-authoring ~1,000 unique descriptions.
private let bigCatalogTopics = [
    "parser", "renderer", "scheduler", "cache", "logger",
    "validator", "compiler", "router", "indexer", "formatter",
]

/// Builds a synthetic catalog of `count` entries: `count - 1` generic filler
/// entries (ids = URIs, e.g. `"https://example.com/modules/module-42"`) plus
/// one deterministic needle entry (`bigCatalogNeedleId`) a query built around
/// `bigCatalogNeedleQuery` can find unambiguously.
///
/// - Parameter count: the total number of entries to build, including the
///   needle. Defaults to `1_000` -- plan.md §13's "~10^3-entry catalog".
///   `count <= 0` yields an empty catalog (no needle either) rather than a
///   negative-length one.
/// - Returns: the synthetic catalog, `count` entries long (`0` entries for
///   `count <= 0`).
public func makeBigCatalog(count: Int = 1_000) -> [BigCatalogItem] {
    guard count > 0 else { return [] }
    let fillerCount = count - 1
    var items: [BigCatalogItem] = []
    items.reserveCapacity(count)

    for index in 0..<fillerCount {
        let topic = bigCatalogTopics[index % bigCatalogTopics.count]
        let id = "https://example.com/modules/module-\(index)"
        let block = "Module #\(index): a \(topic) component handling \(topic)-related tasks for subsystem \(index % 37)."
        items.append(BigCatalogItem(id: id, block: block))
    }
    items.append(BigCatalogItem(id: bigCatalogNeedleId, block: bigCatalogNeedleBlock))
    return items
}

// MARK: - GPU-free retrieval timing

/// One retrieval-timing run's result: the ranked matches, how long indexing
/// + search actually took, and the catalog size that ran against.
public struct RetrievalTimingResult: Sendable {
    /// The ranked matches, best first.
    public let matches: [Match<BigCatalogItem>]

    /// Wall-clock time spent building the index and running the search.
    public let elapsed: TimeInterval

    /// The number of entries in the catalog this run searched.
    public let catalogCount: Int
}

/// Runs the M8 headroom story's GPU-free core: builds a keyword-only
/// `MetadataSearcher(mode: .retrieval)` over `catalog` (no embedder, no
/// model, no session) and searches it for `query`, timing both steps
/// together -- indexing ~10^3 entries is itself part of the "in-memory
/// retrieval" story plan.md §13 wants demonstrated.
///
/// - Parameters:
///   - catalog: the catalog to index and search. Defaults to a fresh
///     `makeBigCatalog()` (1,000 entries).
///   - query: the search query.
///   - limit: the maximum number of matches to return. Defaults to `10`.
/// - Returns: the ranked matches, the elapsed time, and the catalog size.
public func runBigCatalogRetrieval(
    catalog: [BigCatalogItem] = makeBigCatalog(),
    query: String,
    limit: Int = 10
) async throws -> RetrievalTimingResult {
    let start = Date()
    let searcher = MetadataSearcher(items: catalog, mode: .retrieval)
    let matches = try await searcher.search(intent: query, limit: limit)
    let elapsed = Date().timeIntervalSince(start)
    return RetrievalTimingResult(matches: matches, elapsed: elapsed, catalogCount: catalog.count)
}

// MARK: - Gated over-budget selection (real model)

/// Runs the over-budget `.selection` path (plan.md §6) against a real,
/// live-Router-resolved model: `catalog`'s assembled prefix (~1,000 items'
/// worth of summary blocks) overflows any reasonable
/// `SelectionConfig.capacityCharacterLimit`, so `SelectionTier` ranks the
/// whole catalog via its retrieval tier, keeps the top-M candidates, and
/// seeds a fresh, uncached, unforked one-off session with exactly those --
/// reported via `.retrievalCut(considered:kept:)`, printed by
/// `printDiagnostic(_:)`.
///
/// Only ever called behind `ExamplesSupport.metadataRegistryIntegrationEnabled`
/// -- this is the one path in this target that touches the network/GPU.
///
/// - Parameters:
///   - catalog: the catalog to select over.
///   - query: the search query.
///   - limit: the maximum number of matches to return. Defaults to `10`.
/// - Returns: the selected items' matches, at most `limit`.
public func runBigCatalogOverBudgetSelection(
    catalog: [BigCatalogItem],
    query: String,
    limit: Int = 10
) async throws -> [Match<BigCatalogItem>] {
    let config = try await buildSelectionConfig(
        demoLabel: "BigCatalog",
        name: "big-catalog-demo",
        description: "Tiny co-resident models sized for a local demo run of the over-budget selection path.",
        ids: catalog.map(\.id),
        // Deliberately tiny: ~1,000 items' assembled summary-block prefix is
        // always far larger than this, guaranteeing the over-budget path
        // runs rather than the cached-root one.
        capacityCharacterLimit: 2_000
    )
    let searcher = MetadataSearcher(items: catalog, mode: .selection, selection: config, onDiagnostic: printDiagnostic)
    return try await searcher.search(intent: query, limit: limit)
}

/// Prints every diagnostic this example's gated selection search emits --
/// `.retrievalCut` is the one the over-budget path always triggers; every
/// other diagnostic falls back to the package default (plan.md §1 "every
/// degradation is reported, never silent").
///
/// - Parameter diagnostic: the diagnostic to print.
public func printDiagnostic(_ diagnostic: MetadataDiagnostic) {
    printExampleDiagnostic(diagnostic) { diagnostic in
        guard case .retrievalCut(let considered, let kept) = diagnostic else { return nil }
        return "retrievalCut: considered \(considered) candidates, kept the top \(kept) before seeding "
            + "a one-off selection session (over budget)."
    }
}

