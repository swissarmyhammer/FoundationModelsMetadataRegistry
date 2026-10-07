import Foundation
import FoundationModelsExtras

@testable import FoundationModelsMetadataRegistry

/// A deterministic `PooledEmbedding` test double, shared by `EmbeddingTests`
/// and `HotReloadTests`.
///
/// Returns a caller-supplied vector for each registered text, falling back
/// to an all-zero vector of the same length (see `VectorTable`) for any text
/// not explicitly registered. `embeddedTextCount` tracks the total number of
/// texts passed to `embed(texts:)` across every call so far — not the number
/// of `embed(texts:)` invocations — which is what "embed count proportional
/// to changed blocks" means for a batched embedder (plan.md §8).
/// `embeddedBatches` records the texts of every `embed(texts:)` call, in call
/// order, for a test that asserts on *which* texts each call carried — the
/// catalog blocks of a catch-up batch against the one query text of a
/// search.
struct FakeEmbedder: PooledEmbedding {
  /// Exact-text -> vector lookup table. A text absent from this table
  /// embeds to an all-zero vector.
  private let table: VectorTable

  /// When set, every call to `embed(texts:)` throws this error instead of
  /// producing vectors -- lets a test simulate a transient embed failure
  /// (e.g. to exercise `MetadataIndex.build`'s graceful-skip path, leaving
  /// the affected items with whatever embedding they already had).
  private let failure: (any Error)?

  /// Records the texts of every `embed(texts:)` call.
  private let counter: EmbedCallCounter

  /// Creates a fake embedder returning `vectorsByText`'s registered
  /// vectors verbatim.
  ///
  /// - Parameters:
  ///   - vectorsByText: exact-text -> vector lookup table; a text absent
  ///     from this table embeds to an all-zero vector of the same length.
  ///     Defaults to empty.
  ///   - failure: when non-nil, `embed(texts:)` throws this error instead of
  ///     computing vectors. Defaults to `nil`.
  ///   - counter: the call counter to record every `embed(texts:)` call's
  ///     texts into. Defaults to a fresh, unshared counter.
  init(
    vectorsByText: [String: [Float]] = [:],
    failure: (any Error)? = nil,
    counter: EmbedCallCounter = EmbedCallCounter(),
  ) {
    table = VectorTable(vectorsByText: vectorsByText)
    self.failure = failure
    self.counter = counter
  }

  /// The total number of texts passed to `embed(texts:)` across every call
  /// so far.
  var embeddedTextCount: Int {
    counter.count
  }

  /// The texts of every `embed(texts:)` call so far, in call order.
  var embeddedBatches: [[String]] {
    counter.batches
  }

  /// Records `texts`, then gives the table vector of each text, or throws
  /// the scripted failure.
  ///
  /// - Parameter texts: the texts to embed.
  /// - Returns: one vector for each text, in order.
  /// - Throws: `failure`, when it is set.
  func embed(texts: [String]) async throws -> [[Float]] {
    counter.record(texts)
    if let failure {
      throw failure
    }
    return table.vectors(for: texts)
  }
}

/// A thread-safe record of every `embed(texts:)` call, shared by
/// `FakeEmbedder` and `GatedEmbedder`, following the same lock-guarded
/// `@unchecked Sendable` pattern as `CatalogTests.CallCounter`.
///
/// Synchronization: `recorded` is only ever read (via `count` and
/// `batches`) or mutated (via `record(_:)`) while holding `lock`, so every
/// access to `recorded` holds `lock`.
final class EmbedCallCounter: @unchecked Sendable {
  /// The lock that guards `recorded`.
  private let lock = NSLock()

  /// The texts of every recorded `embed(texts:)` call, in call order.
  private var recorded: [[String]] = []

  /// The total number of texts across every recorded call.
  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return recorded.reduce(0) { $0 + $1.count }
  }

  /// The texts of every recorded call, in call order.
  var batches: [[String]] {
    lock.lock()
    defer { lock.unlock() }
    return recorded
  }

  /// Records the texts of one `embed(texts:)` call.
  ///
  /// - Parameter texts: the texts that call was asked to embed.
  func record(_ texts: [String]) {
    lock.lock()
    defer { lock.unlock() }
    recorded.append(texts)
  }
}
