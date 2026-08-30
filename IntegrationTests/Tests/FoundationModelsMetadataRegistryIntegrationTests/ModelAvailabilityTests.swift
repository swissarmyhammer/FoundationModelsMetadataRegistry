import FoundationModels
import Testing

// MARK: - Selection

/// No environment variable selects this suite. The org test contract
/// (swissarmyhammer/workflows' README) says an environment variable must not
/// select tests. This suite runs when its own package runs:
/// `swift test --package-path IntegrationTests` from the repository root. The
/// root package does not name this package, so a bare `swift test` at the root
/// runs the unit tests only.

/// The precondition every real-model scenario in this package opens with.
///
/// This is the placeholder suite the package ships with: it holds the one
/// scenario that measures the precondition itself, so a machine that cannot
/// serve Apple Intelligence fails here, loudly and once, rather than deeper
/// down inside a scenario whose own failure would hide the cause. The scenarios
/// that drive the model arrive in their own changes and open with the same
/// call.
///
/// The package's deployment floor is macOS 27 already, so no redundant
/// `@available` attribute is needed — Swift Testing's `@Suite`/`@Test` macros
/// reject one on the type.
@Suite("Model availability")
struct ModelAvailabilityTests {
    /// Pins both halves of the precondition on this machine: the shared
    /// `requireAvailable()` gate passes, and the model really does report
    /// itself available.
    ///
    /// The second assertion is not a restatement of the first. `requireAvailable()`
    /// throws on the unavailable path, so a broken gate that never threw would
    /// leave this test green on its own; asserting `isAvailable` directly is
    /// what makes the green mean "Apple Intelligence is serving here".
    @Test("the availability gate passes on a machine that serves Apple Intelligence")
    func availabilityGatePassesWhereTheModelIsAvailable() throws {
        try ModelAvailability.requireAvailable()

        #expect(SystemLanguageModel.default.isAvailable)
    }
}
