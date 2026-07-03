import Foundation

@testable import FoundationModelsMetadataRegistry

/// A deterministic `TextEmbedding` test double, shared by `EmbeddingTests`.
///
/// Returns a caller-supplied vector for each registered text, falling back
/// to an all-zero vector (which naturally contributes nothing to cosine —
/// see `MetadataSearcher`'s cosine-similarity zero-norm guard) for any text
/// not explicitly registered. `embeddedTextCount` tracks the total number of
/// texts passed to `embed(_:)` across every call so far — not the number of
/// `embed(_:)` invocations — which is what "embed count proportional to
/// changed blocks" means for a batched embedder (plan.md §8).
struct FakeEmbedder: TextEmbedding {
    let dimension: Int

    /// Exact-text -> vector lookup table. A text absent from this table
    /// embeds to an all-zero vector.
    private let vectorsByText: [String: [Float]]

    /// When set, every call to `embed(_:)` throws this error instead of
    /// producing vectors -- lets a test simulate a transient embed failure
    /// (e.g. to exercise `MetadataIndex.build`'s graceful-skip path, leaving
    /// the affected items with whatever embedding they already had).
    private let failure: (any Error)?

    private let counter: EmbedCallCounter

    /// Creates a fake embedder returning `vectorsByText`'s registered
    /// vectors verbatim.
    ///
    /// - Parameters:
    ///   - dimension: the length of every embedding vector this embedder
    ///     produces.
    ///   - vectorsByText: exact-text -> vector lookup table; a text absent
    ///     from this table embeds to an all-zero vector. Defaults to empty.
    ///   - failure: when non-nil, `embed(_:)` throws this error instead of
    ///     computing vectors. Defaults to `nil`.
    ///   - counter: the call counter to record every `embed(_:)` call's text
    ///     count into. Defaults to a fresh, unshared counter.
    init(
        dimension: Int,
        vectorsByText: [String: [Float]] = [:],
        failure: (any Error)? = nil,
        counter: EmbedCallCounter = EmbedCallCounter()
    ) {
        self.dimension = dimension
        self.vectorsByText = vectorsByText
        self.failure = failure
        self.counter = counter
    }

    /// The total number of texts passed to `embed(_:)` across every call so
    /// far.
    var embeddedTextCount: Int { counter.count }

    func embed(_ texts: [String]) async throws -> [[Float]] {
        counter.increment(by: texts.count)
        if let failure {
            throw failure
        }
        return texts.map { vectorsByText[$0] ?? [Float](repeating: 0, count: dimension) }
    }
}

/// A thread-safe call counter for `FakeEmbedder`, following the same
/// lock-guarded `@unchecked Sendable` pattern as `CatalogTests.CallCounter`.
final class EmbedCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func increment(by amount: Int) {
        lock.lock()
        defer { lock.unlock() }
        value += amount
    }
}
