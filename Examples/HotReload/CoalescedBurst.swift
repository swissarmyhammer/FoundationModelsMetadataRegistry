import ExamplesSupport
import FoundationModelsMetadataRegistry

// The machinery for part 2 of this example: a burst of updates that arrives
// while the first embed call is held.

/// What `runCoalescedBurst(_:query:limit:)` observed.
struct CoalescedBurstResult {
    /// The texts of each embed call that the searcher made, in call order.
    let embedBatches: [[String]]

    /// The `.embedCatchUp` diagnostics of the burst: one for each real embed call.
    let embedCatchUps: [MetadataDiagnostic]

    /// The ids that a search for the query found after the burst.
    let searchResultIds: [String]
}

/// Sends `burst` to a new `MetadataSearcher` while its first embed call is held.
///
/// The first update starts an embed, which this function holds. Each later
/// update runs in its own task, and this function waits until a keyword
/// search finds exactly the ids of that update before it sends the next, so
/// each later update arrives while the first embed is held. Then it
/// releases the embed and waits for each update to return.
///
/// - Parameters:
///   - burst: the catalogs to send, one `update(items:)` call for each. Two
///     catalogs in a row must not hold the same ids.
///   - query: a query that each item of `burst` matches.
///   - limit: the maximum number of matches of each search. Must be at
///     least the size of the largest catalog.
/// - Returns: the embed calls, the catch-up diagnostics, and the final
///   search result.
/// - Throws: the error of the model load or of `search(intent:limit:)`.
func runCoalescedBurst(_ burst: [[Tool]], query: String, limit: Int) async throws -> CoalescedBurstResult {
    let base = try await PooledTextEmbedding.acquire(
        exampleEmbeddingModel,
        footprintBytes: exampleEmbeddingFootprintBytes,
        loader: exampleModelLoader(),
        from: .shared,
    )
    let hold = FirstEmbedHold()
    let log = DiagnosticLog()
    let searcher = await MetadataSearcher(
        items: [Tool](),
        mode: .retrieval,
        embedder: HeldFirstEmbedder(base: base, hold: hold),
        onDiagnostic: { log.record($0) },
    )

    var updates: [Task<Void, Never>] = []
    for (position, items) in burst.enumerated() {
        updates.append(Task { await searcher.update(items: items) })
        if position == 0 {
            await hold.waitUntilHeld()
        } else {
            let ids = Set(items.map(\.id))
            while try await Set(searcher.search(intent: query, limit: limit).map(\.id)) != ids {
                await Task.yield()
            }
        }
    }
    await hold.release()
    for update in updates {
        await update.value
    }

    return try await CoalescedBurstResult(
        embedBatches: hold.batches,
        embedCatchUps: log.diagnostics(since: 0).filter {
            if case .embedCatchUp = $0 { return true }
            return false
        },
        searchResultIds: searcher.search(intent: query, limit: limit).map(\.id),
    )
}

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

    /// Lets the held call, and each later call, run.
    func release() {
        isReleased = true
        heldCall?.resume()
        heldCall = nil
    }
}

/// An embedder whose first embed call `hold` holds.
private struct HeldFirstEmbedder: TextEmbedding {
    /// The embedder that computes the vectors.
    let base: PooledTextEmbedding

    /// The hold that records and holds the calls.
    let hold: FirstEmbedHold

    func embed(_ texts: [String]) async throws -> [[Float]] {
        await hold.enter(with: texts)
        return try await base.embed(texts)
    }
}
