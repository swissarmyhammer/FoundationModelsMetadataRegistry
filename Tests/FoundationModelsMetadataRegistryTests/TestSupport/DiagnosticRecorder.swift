import Foundation

@testable import FoundationModelsMetadataRegistry

/// A thread-safe recorder for `onDiagnostic` callbacks, shared by
/// `CatalogTests`, `RetrievalSearchTests`, and `ExamplesSmokeTests` so every
/// suite asserts on forwarded `MetadataDiagnostic` values without each
/// maintaining its own copy of the same helper.
///
/// Synchronization: `recorded` is only ever read (via `diagnostics`) or
/// mutated (via `record(_:)`) while holding `lock`, which is what makes the
/// `@unchecked Sendable` conformance safe — every access to the shared,
/// non-Sendable-checked array is serialized through the lock.
final class DiagnosticRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [MetadataDiagnostic] = []

    var diagnostics: [MetadataDiagnostic] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ diagnostic: MetadataDiagnostic) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(diagnostic)
    }
}
