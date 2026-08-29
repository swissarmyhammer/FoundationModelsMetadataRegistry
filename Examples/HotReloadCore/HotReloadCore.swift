import ExamplesSupport
import Foundation
import FoundationModelsMetadataRegistry

/// # `HotReload`'s entry logic (plan.md §13 M8): `update(items:)` bursts.
///
/// An MCP-style add/remove burst (`update(items:)` calls forwarded without
/// coalescing, exactly like an MCP `listChanged` handler would) driven
/// against a `MetadataSearcher`, GPU-free: `runHotReloadBurst(burst:query:
/// limit:embedder:)` replays the burst and, after every step, immediately
/// searches -- proving items are keyword-searchable right away -- while
/// capturing every diagnostic that step emitted, including
/// `.embedCatchUp(pending:total:)`'s progress. `runSelectionRootRebuildDemo()`
/// shows the companion story for the `.selection` tier: a real catalog
/// change drops the cached root session and its candidate-id grammar,
/// rebuilding both against the new catalog on the next search (plan.md §8).
///
/// Both paths run against a small deterministic embedder
/// (`ExamplesSupport.DeterministicEmbedder`) -- a `FakeEmbedder`-style test
/// double, but defined in `ExamplesSupport` since production code (a library
/// target) can't import a test-target type. That is the only embedder this
/// example ever builds, so it touches no network and no GPU.
///
/// Factored into this library target (rather than living directly in
/// `HotReload`'s `main.swift`) so `ExamplesSmokeTests` can invoke both
/// paths directly, with no `swift run` subprocess spawning.

// MARK: - Fixture catalog

/// This example's domain-flavored alias for `ExamplesSupport`'s shared
/// `SearchableFixtureItem`: an MCP-resource-shaped id and description.
public typealias HotReloadTool = SearchableFixtureItem

/// The three tools this example's burst adds and removes, mirroring an MCP
/// server's own `listChanged` churn: tools appear, stay across a redundant
/// forward, and drop out again.
/// The first tool in the burst sequence: present from the initial add.
public let hotReloadToolA = HotReloadTool(id: "toolA", block: "reads a file from disk")

/// The second tool in the burst sequence: added alongside `hotReloadToolA`,
/// then survives the later remove-and-add step.
public let hotReloadToolB = HotReloadTool(id: "toolB", block: "writes a file to disk")

/// The third tool in the burst sequence: added only in the final
/// remove-and-add step, replacing `hotReloadToolA`.
public let hotReloadToolC = HotReloadTool(id: "toolC", block: "deletes a file from disk")

/// The MCP-style add/remove burst this example replays against a live
/// `MetadataSearcher`: an initial add, a second add, a redundant forward of
/// identical content, then a remove-and-add -- the same shape
/// `HotReloadTests.mcpStyleAddAndRemoveBurstStaysSearchableAndEmbedsOnlyNetNewItems()`
/// exercises.
public let hotReloadBurst: [[HotReloadTool]] = [
    [hotReloadToolA],
    [hotReloadToolA, hotReloadToolB],
    [hotReloadToolA, hotReloadToolB],
    [hotReloadToolB, hotReloadToolC],
]

// MARK: - GPU-free burst replay

/// One burst step's result: the ids `update(items:)` was called with, the
/// diagnostics that call emitted, and the ids an immediate keyword search
/// found right afterward.
public struct BurstStepResult: Sendable {
    /// The ids passed to `update(items:)` for this step, in catalog order.
    public let appliedIds: [String]

    /// The diagnostics `update(items:)` emitted for this step.
    public let diagnostics: [MetadataDiagnostic]

    /// The ids an immediate `search(intent:limit:)` call found right after
    /// this step's `update(items:)` returned.
    public let searchResultIds: [String]
}

/// Replays `burst` against a fresh `MetadataSearcher`, one `update(items:)`
/// call per step, searching for `query` immediately after each -- proving
/// items are keyword-searchable right away -- while capturing every
/// diagnostic that step's `update(items:)` call emitted (plan.md §8).
///
/// - Parameters:
///   - burst: the sequence of catalog snapshots to replay, one
///     `update(items:)` call per entry. Defaults to `hotReloadBurst`.
///   - query: the search query run immediately after every step. Defaults
///     to `"file"` -- every burst tool's description mentions "file".
///   - limit: the maximum number of matches each step's search returns.
///     Defaults to `5`.
///   - embedder: the embedder to embed the catalog and query with. Defaults
///     to a fresh `DeterministicEmbedder()` -- GPU-free, and what every
///     caller uses; the parameter stays open so a test can replay the same
///     burst against a different embedder, or against none at all.
/// - Returns: one `BurstStepResult` per entry in `burst`, in order.
public func runHotReloadBurst(
    burst: [[HotReloadTool]] = hotReloadBurst,
    query: String = "file",
    limit: Int = 5,
    embedder: (any TextEmbedding)? = DeterministicEmbedder()
) async throws -> [BurstStepResult] {
    let log = DiagnosticLog()
    let searcher = await MetadataSearcher(
        items: [HotReloadTool](),
        embedder: embedder,
        onDiagnostic: { log.record($0) }
    )

    var steps: [BurstStepResult] = []
    steps.reserveCapacity(burst.count)
    for items in burst {
        let before = log.count
        await searcher.update(items: items)
        let stepDiagnostics = log.diagnostics(since: before)
        let searchResults = try await searcher.search(intent: query, limit: limit)
        steps.append(
            BurstStepResult(
                appliedIds: items.map(\.id),
                diagnostics: stepDiagnostics,
                searchResultIds: searchResults.map(\.id)
            )
        )
    }
    return steps
}

/// Thread-safe diagnostic log for `runHotReloadBurst(burst:query:limit:
/// embedder:)`'s per-step diagnostic capture -- mirrors the lock-guarded
/// `@unchecked Sendable` pattern the test suite's own `DiagnosticRecorder`
/// uses, reimplemented here since production code (this library target)
/// can't import a test-target type.
private final class DiagnosticLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [MetadataDiagnostic] = []

    /// The number of diagnostics recorded so far.
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return recorded.count
    }

    /// Records one diagnostic.
    ///
    /// - Parameter diagnostic: the diagnostic to record.
    func record(_ diagnostic: MetadataDiagnostic) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(diagnostic)
    }

    /// The diagnostics recorded since `index`.
    ///
    /// - Parameter index: the count previously observed, marking where the
    ///   slice of "new since then" diagnostics begins.
    /// - Returns: every diagnostic recorded at or after `index`.
    func diagnostics(since index: Int) -> [MetadataDiagnostic] {
        lock.lock()
        defer { lock.unlock() }
        guard index < recorded.count else { return [] }
        return Array(recorded[index...])
    }
}

// MARK: - GPU-free selection root/grammar rebuild demo

/// `runSelectionRootRebuildDemo()`'s result: how many times the selection
/// tier's session factory was invoked before and after a real catalog
/// change, and the candidate id set (what a real id-enum grammar would be
/// derived from) each time.
public struct SelectionRebuildDemoResult: Sendable {
    /// How many times the session factory had been invoked after the
    /// initial catalog's first search.
    public let initialFactoryCallCount: Int

    /// How many times the session factory had been invoked in total after a
    /// real catalog change and a second search.
    public let rebuiltFactoryCallCount: Int

    /// The candidate ids the initial (single-item) catalog's cached root
    /// session was built against.
    public let initialCandidateIds: [String]

    /// The candidate ids the rebuilt catalog's new root session is built
    /// against.
    public let updatedCandidateIds: [String]
}

/// Demonstrates the `.selection` tier's cached-root + grammar rebuild on a
/// real catalog change (plan.md §8), GPU-free: a scripted `AgentSession`
/// double stands in for the model (this demo cares about *how many times*
/// and *against what candidate ids* the tier builds a session, not what a
/// real model would pick), so no network or GPU is touched.
///
/// - Returns: the factory call counts and candidate id sets, before and
///   after a real catalog change.
/// - Throws: whatever the underlying selection search throws (not expected
///   against the scripted session below).
public func runSelectionRootRebuildDemo() async throws -> SelectionRebuildDemoResult {
    let factoryCallCount = DemoCallCounter()
    let config = SelectionConfig(model: { _, _ in
        factoryCallCount.increment()
        return ScriptedSelectionSession()
    })

    let initialItems = [hotReloadToolA]
    let searcher = MetadataSearcher(items: initialItems, mode: .selection, selection: config)

    _ = try await searcher.search(intent: "read a file", limit: 5)
    let initialFactoryCallCount = factoryCallCount.count

    let updatedItems = [hotReloadToolA, hotReloadToolB]
    await searcher.update(items: updatedItems)
    _ = try await searcher.search(intent: "read a file", limit: 5)
    let rebuiltFactoryCallCount = factoryCallCount.count

    return SelectionRebuildDemoResult(
        initialFactoryCallCount: initialFactoryCallCount,
        rebuiltFactoryCallCount: rebuiltFactoryCallCount,
        initialCandidateIds: initialItems.map(\.id),
        updatedCandidateIds: updatedItems.map(\.id)
    )
}

/// A minimal scripted `AgentSession` for the GPU-free selection-tier
/// root/grammar-rebuild demo: always answers with an empty selection and
/// touches no model or network -- this demo only cares about *how many
/// times*, and *against what candidate ids*, the tier constructs a session.
private struct ScriptedSelectionSession: AgentSession {
    func respond(to prompt: String) async throws -> String {
        #"{"ids":[]}"#
    }
}

/// A thread-safe call counter, mirroring the lock-guarded `@unchecked
/// Sendable` pattern the test suite's own `CallCounter`/`EmbedCallCounter`
/// use, reimplemented here since production code (this library target)
/// can't import a test-target type.
private final class DemoCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        value += 1
    }
}
