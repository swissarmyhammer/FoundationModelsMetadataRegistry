import ExamplesSupport
import FoundationModelsMetadataRegistry

// # `HotReload`'s coalescing demo (plan.md §8): a burst while an embed is in flight.
//
// `runCoalescedHotReloadBurst(burst:query:limit:)` holds the first embed call
// of a `MetadataSearcher`, sends the rest of a burst while that call is held,
// and then releases it. The searcher embeds only the first catalog and the
// newest one: the catalogs between them are never embedded. GPU-free, against
// `ExamplesSupport.DeterministicEmbedder`.

// MARK: - Fixture burst

/// The burst that `runCoalescedHotReloadBurst(burst:query:limit:)` sends.
///
/// Each catalog differs from the one before it, so an immediate keyword
/// search shows when each update has arrived.
public let hotReloadRapidBurst: [[HotReloadTool]] = [
    [hotReloadToolA],
    [hotReloadToolA, hotReloadToolB],
    [hotReloadToolB],
    [hotReloadToolB, hotReloadToolC],
]

// MARK: - Result

/// What `runCoalescedHotReloadBurst(burst:query:limit:)` observed.
public struct CoalescedBurstResult: Sendable {
    /// The number of `update(items:)` calls the burst sent.
    public let updateCount: Int

    /// The texts of each catalog embed call the searcher made, in call order.
    public let catalogEmbedBatches: [[String]]

    /// The `.embedCatchUp` diagnostics the burst emitted: one for each real embed call.
    public let embedCatchUps: [MetadataDiagnostic]

    /// The ids a search for the query found after the burst.
    public let searchResultIds: [String]
}

// MARK: - Burst replay

/// Sends `burst` to a fresh `MetadataSearcher` while its first embed call is held.
///
/// The first update starts an embed, which this function holds. Each later
/// update runs in its own task, and this function waits until a keyword
/// search finds exactly the ids of that update before it sends the next, so
/// every later update arrives while the first embed is held. Then it
/// releases the embed and waits for every update to return.
///
/// - Parameters:
///   - burst: the catalogs to send, one `update(items:)` call for each.
///     Two catalogs in a row must not hold the same ids. Defaults to
///     `hotReloadRapidBurst`.
///   - query: the search query that shows when an update has arrived. Every
///     item of `burst` must match it. Defaults to `"file"`.
///   - limit: the maximum number of matches of each search. Must be at
///     least the size of the largest catalog. Defaults to `5`.
/// - Returns: the catalog embed calls, the catch-up diagnostics, and the
///   final search result.
/// - Throws: whatever `search(intent:limit:)` throws (not expected in
///   `.retrieval` mode).
public func runCoalescedHotReloadBurst(
    burst: [[HotReloadTool]] = hotReloadRapidBurst,
    query: String = "file",
    limit: Int = 5,
) async throws -> CoalescedBurstResult {
    let hold = FirstEmbedHold()
    let log = DiagnosticLog()
    let searcher = await MetadataSearcher(
        items: [HotReloadTool](),
        mode: .retrieval,
        embedder: HeldFirstEmbedder(base: DeterministicEmbedder(), hold: hold),
        onDiagnostic: { log.record($0) },
    )

    var updates: [Task<Void, Never>] = []
    for (position, items) in burst.enumerated() {
        updates.append(Task { await searcher.update(items: items) })
        if position == 0 {
            await hold.waitUntilHeld()
        } else {
            try await waitUntilSearchable(Set(items.map(\.id)), in: searcher, query: query, limit: limit)
        }
    }
    await hold.release()
    for update in updates {
        await update.value
    }

    let catalogEmbedBatches = await hold.batches
    let searchResults = try await searcher.search(intent: query, limit: limit)
    return CoalescedBurstResult(
        updateCount: burst.count,
        catalogEmbedBatches: catalogEmbedBatches,
        embedCatchUps: log.diagnostics(since: 0).filter(\.isEmbedCatchUp),
        searchResultIds: searchResults.map(\.id),
    )
}

/// Waits until a keyword search of `searcher` finds exactly `ids`.
///
/// - Parameters:
///   - ids: the ids that the search must find.
///   - searcher: the searcher to search.
///   - query: the query that every item matches.
///   - limit: the maximum number of matches of each search.
/// - Throws: whatever `search(intent:limit:)` throws.
private func waitUntilSearchable(
    _ ids: Set<String>,
    in searcher: MetadataSearcher<HotReloadTool>,
    query: String,
    limit: Int,
) async throws {
    while try await Set(searcher.search(intent: query, limit: limit).map(\.id)) != ids {
        await Task.yield()
    }
}

private extension MetadataDiagnostic {
    /// Whether this diagnostic is an `.embedCatchUp`, the one kind the coalescing demo reports.
    var isEmbedCatchUp: Bool {
        guard case .embedCatchUp = self else { return false }
        return true
    }
}

// MARK: - Held embedder

/// Holds the first embed call until `release()`, and records the texts of each call.
///
/// An actor, so each continuation is resumed from one place with no data race.
private actor FirstEmbedHold {
    /// Whether the first embed call has started.
    private var isHeld = false

    /// Whether `release()` has run.
    private var isReleased = false

    /// The waiter of `waitUntilHeld()`, when the first call has not started yet.
    private var heldWaiter: CheckedContinuation<Void, Never>?

    /// The first embed call, while it is held.
    private var heldCall: CheckedContinuation<Void, Never>?

    /// The texts of each embed call, in call order.
    private(set) var batches: [[String]] = []

    /// Records the texts of one embed call, and holds that call when it is the first.
    ///
    /// - Parameter texts: the texts that the call embeds.
    func enter(with texts: [String]) async {
        batches.append(texts)
        guard !isHeld, !isReleased else { return }
        isHeld = true
        heldWaiter?.resume()
        heldWaiter = nil
        await withCheckedContinuation { heldCall = $0 }
    }

    /// Returns when the first embed call is held.
    func waitUntilHeld() async {
        guard !isHeld else { return }
        await withCheckedContinuation { heldWaiter = $0 }
    }

    /// Lets the held call, and every later call, run.
    func release() {
        isReleased = true
        heldCall?.resume()
        heldCall = nil
    }
}

/// A `DeterministicEmbedder` whose first embed call `hold` holds.
private struct HeldFirstEmbedder: TextEmbedding {
    /// The embedder that computes the vectors.
    let base: DeterministicEmbedder

    /// The hold that records and holds the calls.
    let hold: FirstEmbedHold

    /// The length of each vector, the same as `base`.
    var dimension: Int {
        base.dimension
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        await hold.enter(with: texts)
        return try await base.embed(texts)
    }
}
