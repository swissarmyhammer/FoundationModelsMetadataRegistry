import FoundationModelsExtras
import os

/// A FoundationModelsExtras `PooledEmbedding` that loads nothing and gives
/// the same vector for each text.
///
/// Each item then has a cosine of 1 to each intent, so the retrieval tier
/// ranks each catalog item. The first call can wait a fixed time
/// first. The first search embeds the catalog, so that wait is in the
/// warm-up search only.
struct ConstantEmbedder: PooledEmbedding {
  /// The vector that each text gets.
  static let vector: [Float] = [1, 0]

  /// The time that the first call waits before it answers.
  let firstCallDelay: Duration

  /// Whether a call already came, under one lock. All copies share it.
  private let calledBefore = OSAllocatedUnfairLock(initialState: false)

  /// Makes an embedder.
  ///
  /// - Parameter firstCallDelay: the time that the first call waits.
  ///   Defaults to zero.
  init(firstCallDelay: Duration = .zero) {
    self.firstCallDelay = firstCallDelay
  }

  /// Gives `vector` for each text, after the first-call wait.
  ///
  /// - Parameter texts: the texts.
  /// - Returns: one copy of `vector` for each text.
  /// - Throws: `CancellationError` when the task is cancelled during the
  ///   wait.
  func embed(texts: [String]) async throws -> [[Float]] {
    let isFirstCall = calledBefore.withLock { called in
      defer { called = true }
      return !called
    }
    if isFirstCall {
      try await Task.sleep(for: firstCallDelay)
    }
    return texts.map { _ in Self.vector }
  }
}
