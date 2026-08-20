import os

/// A thread-safe call counter — used to assert a closure ran an exact number
/// of times without needing a bespoke lock-boxed fixture per test.
///
/// A copy of the unit test target's own `CallCounter`
/// (`Tests/FoundationModelsMetadataRegistryTests/TestSupport/SelectionFixtures.swift`).
/// This package cannot import a test target of the root package, so the
/// ~10 lines live here too.
final class CallCounter: Sendable {
    /// This counter's current count.
    private let countBox = OSAllocatedUnfairLock<Int>(initialState: 0)

    /// This counter's current count.
    var count: Int {
        countBox.withLock { $0 }
    }

    /// Adds one to the count.
    func increment() {
        countBox.withLock { $0 += 1 }
    }
}
