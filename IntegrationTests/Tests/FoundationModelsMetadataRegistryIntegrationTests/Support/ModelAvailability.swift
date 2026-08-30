import FoundationModels
import Testing

/// The gate every real-model scenario in this package opens with, and the
/// wrapper each of them puts around its model calls.
///
/// **Why the gate throws instead of skipping.** `SystemLanguageModel.default`
/// answers `availability` on a machine that cannot serve Apple Intelligence at
/// all, and every scenario below that answer would then fail on its own,
/// somewhere deeper, for a reason that reads like a defect in this package.
/// `requireAvailable()` therefore records the real reason and stops the test
/// there. It is deliberately not a Swift Testing `.enabled(if:)` trait: a trait
/// would leave the run green, and a green run that measured nothing is the one
/// outcome this suite exists to rule out.
///
/// **Why an available model is still not a usable one.** Availability answers
/// whether the machine can serve the model, not whether it will serve this
/// request. A rate limit, an asset that is still downloading, an unsupported
/// locale, or a guardrail refusal each arrives *after* the gate passed, as a
/// plain thrown error that reads exactly like a product defect.
/// `recordingEnvironmentFaults(_:)` is the wrapper that tells the two apart, so
/// a scenario's failure names the machine when the machine is at fault.
enum ModelAvailability {
    /// Stops the current test unless Apple Intelligence is available on this
    /// machine.
    ///
    /// `#require` is the whole mechanism: it records the reason as this test's
    /// one failure and throws, so the body never reaches a model call that
    /// would fail a second time and bury the first failure under its own.
    ///
    /// - Throws: Swift Testing's expectation failure, after recording the
    ///   `UnavailableReason` the model reported.
    static func requireAvailable() throws {
        // Read once. Two reads could disagree, and the message would then
        // explain a state the assertion did not measure.
        let availability = SystemLanguageModel.default.availability
        let explanation = Self.explanation(of: availability)

        try #require(
            availability == .available,
            """
            \(explanation) — this suite measures Apple Intelligence and can measure \
            nothing without it, so the run stops here rather than failing further down \
            for a reason that would read like a defect in this package.
            """
        )
    }

    /// Runs `body`, and turns an environment fault raised by the model into one
    /// clearly-worded failure instead of an anonymous thrown error.
    ///
    /// Wrap every model call in this. The errors it catches are conditions of
    /// the machine or the service rather than of this package, and each of them
    /// reaches a test as a bare thrown error that a reader cannot tell from a
    /// product defect. Catching them here is what puts that distinction in the
    /// failure text.
    ///
    /// - Parameter body: the work to run, typically one model call.
    /// - Returns: whatever `body` returned.
    /// - Throws: Swift Testing's expectation failure, after recording an
    ///   environment fault; or whatever else `body` threw, untouched, because
    ///   anything this roster does not name is this package's own failure to
    ///   report as it stands.
    ///
    /// `ColdSelectionRealModelTests` is the first scenario to call this. The
    /// `// periphery:ignore` marker that stood here while the wrapper waited
    /// for that caller is gone with it: the staging contract keeps a marker
    /// only until the change it was written for lands.
    static func recordingEnvironmentFaults<Value>(
        _ body: () async throws -> Value
    ) async throws -> Value {
        do {
            return try await body()
        } catch let fault where Self.isEnvironmentFault(fault) {
            try Self.recordEnvironmentFault(fault)
        }
    }

    /// Whether `error` is a fault of the machine or the service rather than of
    /// this package.
    ///
    /// The roster is every error type FoundationModels raises on this
    /// package's macOS 27 floor for a condition no change to this package could
    /// fix — a rate limit, an asset still downloading, an unsupported locale, a
    /// guardrail refusal, a timeout, and the rest beside them.
    ///
    /// `LanguageModelSession.GenerationError` is the macOS 26 spelling of most
    /// of that set, and it is deliberately absent: the SDK marks it
    /// `@available(macOS, introduced: 26.0, deprecated: 27.0)` and points each
    /// of its cases at `LanguageModelError`, `SystemLanguageModel.Error` or
    /// `LanguageModelSession.Error`, all three of which are named above. Naming
    /// it here would raise `'GenerationError' was deprecated in macOS 27.0` on
    /// every build.
    ///
    /// - Parameter error: the error a model call threw.
    /// - Returns: `true` when the error names an environment fault.
    private static func isEnvironmentFault(_ error: any Error) -> Bool {
        error is LanguageModelError
            || error is SystemLanguageModel.Error
            || error is LanguageModelSession.Error
    }

    /// Records `fault` as this test's one failure, worded so a reader can tell
    /// it from a product defect, and stops the test.
    ///
    /// - Parameter fault: the environment fault the model call threw.
    /// - Returns: never; `#require` throws, and the `throw` below is what makes
    ///   that plain to the compiler.
    /// - Throws: Swift Testing's expectation failure.
    private static func recordEnvironmentFault(_ fault: any Error) throws -> Never {
        let explanation = """
            The model call failed with an environment fault, not a product failure: \
            \(type(of: fault)) — \(fault.localizedDescription). Apple Intelligence \
            answered the availability gate and then declined to serve this request, so \
            this run measures the machine rather than this package. Re-run once the \
            condition clears.
            """

        try #require(Bool(false), "\(explanation)")
        throw fault
    }

    /// Explains `availability` in one clause, for the failure text.
    ///
    /// - Parameter availability: what the model reported.
    /// - Returns: a clause naming the state, and the reason behind it when
    ///   there is one.
    private static func explanation(of availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            return "the system language model reports itself available"
        case .unavailable(let reason):
            return "the system language model is unavailable: \(Self.explanation(of: reason))"
        }
    }

    /// Explains one `UnavailableReason` in the words that tell a reader what to
    /// change on the machine.
    ///
    /// `UnavailableReason` is not frozen, so `@unknown default` is mandatory
    /// here; it names the raw case rather than swallowing it, so a reason added
    /// by a later OS still reaches the failure text.
    ///
    /// - Parameter reason: the reason the model reported.
    /// - Returns: a clause naming that reason.
    private static func explanation(
        of reason: SystemLanguageModel.Availability.UnavailableReason
    ) -> String {
        switch reason {
        case .deviceNotEligible:
            return "this device is not eligible for Apple Intelligence (deviceNotEligible)"
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is switched off in System Settings (appleIntelligenceNotEnabled)"
        case .modelNotReady:
            return "the model assets are not ready yet, so wait for the download to finish (modelNotReady)"
        @unknown default:
            return "a reason this suite does not know about (\(reason))"
        }
    }
}
