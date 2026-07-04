@testable import FoundationModelsMetadataRegistry

/// A continuation-based gate `GatedEmbedder` suspends inside, shared by
/// `HotReloadTests` to deterministically observe `MetadataSearcher.update(
/// items:)`'s "interim" window (plan.md §8): the moment between this call's
/// synchronous keyword-index rebuild (already visible to concurrent
/// `search(intent:limit:)` calls, actor reentrancy across the suspended
/// `await embedder.embed(_:)` below) and the re-embed actually completing.
///
/// An `actor` rather than a lock-boxed class because `CheckedContinuation`
/// must be resumed from exactly one place with no data race — actor
/// isolation gives that for free, unlike `ScriptedAgentSession`'s counters,
/// which only ever read/increment plain values.
actor EmbedGate {
    /// Resumed by `signalStarted()` once `embed(_:)` has actually been
    /// entered — `nil` once `started` is `true` and there's nothing left to
    /// resume.
    private var startContinuation: CheckedContinuation<Void, Never>?

    /// Whether `signalStarted()` has already fired — lets a late
    /// `waitForStart()` caller return immediately instead of awaiting a
    /// continuation that will never be created.
    private var started = false

    /// Resumed by `release()` once the test is done observing the interim
    /// window — `nil` once `released` is `true` and there's nothing left to
    /// resume.
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    /// Whether `release()` has already fired — lets a late `waitForRelease()`
    /// caller return immediately, and every call after the first `release()`
    /// too (a gate only ever blocks once per test).
    private var released = false

    /// Suspends until `signalStarted()` fires, or returns immediately if it
    /// already has — the test's synchronization point for "the update call's
    /// embed call has actually started" (proving the baseline index
    /// reassignment that precedes it already happened).
    func waitForStart() async {
        if started { return }
        await withCheckedContinuation { startContinuation = $0 }
    }

    /// Marks this gate started and resumes any `waitForStart()` waiter —
    /// `GatedEmbedder.embed(_:)` calls this immediately on entry.
    func signalStarted() {
        started = true
        startContinuation?.resume()
        startContinuation = nil
    }

    /// Suspends until `release()` fires, or returns immediately if it
    /// already has — what `GatedEmbedder.embed(_:)` blocks on to hold the
    /// interim window open until the test says otherwise.
    func waitForRelease() async {
        if released { return }
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    /// Releases this gate, resuming any `waitForRelease()` waiter and every
    /// call after — the test's signal that it's done observing the interim
    /// window and the embed call may complete.
    func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

/// A `TextEmbedding` test double that blocks inside `embed(_:)` until a
/// shared `EmbedGate` is released — `HotReloadTests`' tool for
/// deterministically driving `MetadataSearcher.update(items:)`'s async
/// re-embed into its "interim" window and holding it there, instead of
/// racing a real suspension point against a concurrent `search()`/`update()`
/// call.
struct GatedEmbedder: TextEmbedding {
    let dimension: Int

    /// Exact-text -> vector lookup table, same contract as `FakeEmbedder`'s:
    /// a text absent from this table embeds to an all-zero vector.
    let vectorsByText: [String: [Float]]

    /// The gate this embedder signals and blocks on.
    let gate: EmbedGate

    /// Restricts gating to calls whose `texts` include at least one of these
    /// exact strings; every other call resolves immediately without
    /// touching `gate` at all. `nil` (the default) gates every call, same as
    /// this type's original single-round behavior. Lets a test orchestrate
    /// two *overlapping* `update(items:)` calls deterministically: gate only
    /// the first call's text, so the second call's embed resolves
    /// immediately (no continuation to register, no dependency on `gate`
    /// ever being released) while the first stays suspended.
    var gatedTexts: Set<String>?

    init(dimension: Int, vectorsByText: [String: [Float]] = [:], gate: EmbedGate, gatedTexts: Set<String>? = nil) {
        self.dimension = dimension
        self.vectorsByText = vectorsByText
        self.gate = gate
        self.gatedTexts = gatedTexts
    }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        let shouldGate = gatedTexts.map { !$0.isDisjoint(with: texts) } ?? true
        if shouldGate {
            await gate.signalStarted()
            await gate.waitForRelease()
        }
        return texts.map { vectorsByText[$0] ?? [Float](repeating: 0, count: dimension) }
    }
}
