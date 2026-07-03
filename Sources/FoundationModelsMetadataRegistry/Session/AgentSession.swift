// Lifted as-is from Multitool's
// `Sources/FoundationModelsMultitool/Agent/AgentSession.swift` (plan.md §6,
// §8 "Seams"). No behavior changes; Multitool later re-exports this seam
// from here instead of defining its own copy.

import FoundationModels
import FoundationModelsRouter

/// The minimal seam a selection-tier agent (this package's `Librarian`-style
/// consumers, and Multitool's own `MultiToolAgent`/`Librarian`) drives each
/// turn through: send a prompt, get text back — plus the `fork()` primitive
/// a prefix-cached root session needs.
///
/// `RoutedSession` (Router's own actor protocol) already has exactly this
/// shape — `respond(to:) async throws -> String`, for both a plain session
/// (`RoutedLLM.makeSession(instructions:workingDirectory:)`) and a guided
/// one (`RoutedLLM.makeGuidedSession(_:instructions:workingDirectory:)`),
/// which constrains its output internally but still returns plain text
/// through the same method — plus `fork(workingDirectory:)`, which seeds a
/// child from a *copy* of the parent's prefilled KV cache. `fork()` below
/// mirrors that one-argument-dropped: this package never needs to steer a
/// fork's working directory, so the seam stays minimal.
///
/// Callers depend on this seam — never on `RoutedSession` or `RoutedLLM`
/// directly — so a unit test can drive either against a scripted fake
/// conforming to this protocol, with zero GPU and no Router dependency at
/// all. `RoutedAgentSession` below is the only production conformer,
/// adapting a real `RoutedSession` to it.
public protocol AgentSession: Sendable {
    /// Sends `prompt` to the session and returns its complete text response.
    ///
    /// - Parameter prompt: the prompt to respond to — the running transcript
    ///   for this turn, or a one-shot task prompt, depending on the caller.
    /// - Returns: the session's complete text response.
    /// - Throws: whatever the underlying session throws.
    func respond(to prompt: String) async throws -> String

    /// Forks a child session that continues this one's conversation,
    /// inheriting its accumulated context (prefilled prefix included) and
    /// then diverging independently — `RoutedSession.fork(workingDirectory:)`'s
    /// seam, the primitive a prefix-rooted session forks per call so its
    /// prefix is prefilled once rather than replayed on every call.
    ///
    /// - Returns: the forked child session.
    /// - Throws: whatever the underlying session throws while forking.
    func fork() async throws -> any AgentSession
}

extension AgentSession {
    /// Default `fork()`: returns `self`, unchanged.
    ///
    /// Conformers with no real KV cache to fork from — a scripted test
    /// double standing in for a session whose caller never calls `fork()` —
    /// never need to override this; only `RoutedAgentSession` (wrapping a
    /// real `RoutedSession`, whose `fork()` does real KV-cache work) and a
    /// test double that asserts on fork *call count* provide their own
    /// conformance.
    public func fork() async throws -> any AgentSession { self }

    /// Sends `prompt` to the session and decodes its response as a
    /// `Generable` type — the seam a selection call (e.g. `findAPIs`) uses
    /// to get well-formed structured output back (plan.md: guided
    /// `respond(to: task, generating: Selection.self)`).
    ///
    /// Router's own typed guided shape
    /// (`RoutedLLM.respond<T: Generable>(to:generating:)`) lives on the
    /// *model* handle, not on a `RoutedSession` — it derives `T`'s schema,
    /// constrains a **fresh, one-shot** session to it, and decodes the
    /// result, which would re-prefill the surface prefix on every call and
    /// defeat the whole point of a prefix-rooted session. This default
    /// instead decodes over *this* session's own `respond(to:)` — already
    /// grammar-constrained when the session was vended via
    /// `RoutedLLM.makeGuidedSession(_:instructions:workingDirectory:)`, and
    /// a `fork()` of one inherits that grammar (per `RoutedSession
    /// .fork(workingDirectory:)`'s documentation) — so the constrained
    /// decode happens on a session that already carries the prefilled
    /// prefix.
    ///
    /// - Parameters:
    ///   - prompt: the prompt to respond to.
    ///   - type: the `Generable` type to decode the response into.
    /// - Returns: the decoded value.
    /// - Throws: whatever `respond(to:)` throws, or a decoding error if the
    ///   raw response isn't valid, schema-conforming JSON for `T` — expected
    ///   only if this session's underlying grammar doesn't actually match
    ///   `T`'s schema, a caller error, not a runtime condition a correctly
    ///   configured caller can trigger.
    public func respond<T: Generable>(to prompt: String, generating type: T.Type) async throws -> T {
        let raw = try await respond(to: prompt)
        return try T(GeneratedContent(json: raw))
    }
}

/// Adapts a Router `RoutedSession` to the `AgentSession` seam this package's
/// consumers drive.
///
/// A thin wrapper, not a reimplementation: every call forwards to the
/// wrapped session unchanged. `RoutedSession` is itself an `Actor`-bound
/// protocol (Router's session is a real actor internally), so this struct
/// only ever holds the existential and `await`s across it — it adds no
/// state and no synchronization of its own.
public struct RoutedAgentSession: AgentSession {
    /// The Router session every call forwards to.
    private let session: any RoutedSession

    /// Wraps `session` as an `AgentSession`.
    ///
    /// - Parameter session: the Router session to adapt. Vended by
    ///   `RoutedLLM.makeSession(instructions:workingDirectory:)` (plain) or
    ///   `RoutedLLM.makeGuidedSession(_:instructions:workingDirectory:)`
    ///   (guided) — both satisfy `RoutedSession`, so both adapt identically
    ///   here.
    public init(session: any RoutedSession) {
        self.session = session
    }

    public func respond(to prompt: String) async throws -> String {
        try await session.respond(to: prompt)
    }

    public func fork() async throws -> any AgentSession {
        RoutedAgentSession(session: try await session.fork(workingDirectory: nil))
    }
}
