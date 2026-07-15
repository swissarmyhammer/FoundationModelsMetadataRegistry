import FoundationModelsRouter
import os

@testable import FoundationModelsMetadataRegistry

// MARK: - Selection-tier `AgentSession` fixtures (plan.md §6, M3)
//
// Mirrors Multitool's own `LibrarianFixtures.swift`: `SelectionTests` never
// touches a real Router model — the selection tier's root session is always
// supplied through the internal `AgentSession` seam, the same zero-GPU
// pattern `LibrarianTests` established there and `RetrievalSearchTests`/
// `AgentSessionTests` establish in this package.

/// Thrown by `RootSessionRespondCalledDirectlySession.respond(to:)` if it is
/// ever called directly — the selection tier's contract is that every
/// `search()` call goes through a `fork()` of the prefix-rooted session,
/// never the root itself (`RoutedSession.fork(workingDirectory:)`'s
/// KV-cache-copy seam only pays off if the root is never asked to generate
/// on its own transcript).
struct RootSessionRespondCalledDirectlyError: Error, Equatable {}

/// A selection-root `AgentSession` double: records how many times `fork()`
/// was called and hands back a fresh, independently-scripted
/// `ScriptedAgentSession` each time — but throws if `respond(to:)` is ever
/// invoked on the root itself, asserting the "always via fork()" contract.
///
/// `final class ... Sendable` for the same reason as `ScriptedAgentSession`:
/// `fork()` needs to record a call count visible after the `async` call
/// returns, backed by an `OSAllocatedUnfairLock`.
final class RootSessionRespondCalledDirectlySession: AgentSession, Sendable {
    /// One scripted response per `fork()` call, in fork order — the raw
    /// guided-generation JSON text the resulting fork's `respond(to:)`
    /// returns.
    private let forkResponses: [String]

    /// How many `fork()` calls this root has handled so far.
    private let forkCountBox = OSAllocatedUnfairLock<Int>(initialState: 0)

    /// Creates a root double that hands back one freshly-scripted fork per
    /// `fork()` call, in order.
    ///
    /// - Parameter forkResponses: one canned raw response per expected
    ///   `fork()` call, in call order.
    init(forkResponses: [String]) {
        self.forkResponses = forkResponses
    }

    /// How many `fork()` calls this root has handled so far.
    var forkCount: Int { forkCountBox.withLock { $0 } }

    func respond(to prompt: String) async throws -> String {
        throw RootSessionRespondCalledDirectlyError()
    }

    func fork() async throws -> any AgentSession {
        let index = forkCountBox.withLock { count -> Int in
            let index = count
            count += 1
            return index
        }
        guard index < forkResponses.count else {
            throw ScriptedAgentSessionError(scriptedResponseCount: forkResponses.count)
        }
        return ScriptedAgentSession([forkResponses[index]])
    }
}

/// Records every `(instructions, grammar)` pair a `SelectionConfig.model`
/// factory closure was called with, returning one freshly-scripted
/// `ScriptedAgentSession` (canned with `responses`) per call — lets a test
/// assert on *how many times* a session was created (proving the root
/// session is cached, not rebuilt per `search()` call), on *what prefix
/// text* was actually seeded (e.g. that it carries summary blocks, not full
/// ones), and on *what grammar* the tier derived for the call (e.g. that it
/// enum-constrains ids to the current candidate set and caps `maxItems`).
final class RecordingSessionFactory: Sendable {
    /// The canned responses every created session is scripted with.
    private let responses: [String]

    /// Every `instructions` string `makeSession(instructions:grammar:)` has
    /// been called with, in call order.
    private let receivedInstructionsBox = OSAllocatedUnfairLock<[String]>(initialState: [])

    /// Every `Grammar` `makeSession(instructions:grammar:)` has been called
    /// with, in call order.
    private let receivedGrammarsBox = OSAllocatedUnfairLock<[Grammar]>(initialState: [])

    /// Creates a factory whose every vended session is scripted with
    /// `responses`.
    ///
    /// - Parameter responses: the canned responses every created session
    ///   returns, in call order.
    init(responses: [String]) {
        self.responses = responses
    }

    /// Every `instructions` string this factory has been called with, in
    /// call order.
    var receivedInstructions: [String] { receivedInstructionsBox.withLock { $0 } }

    /// Every `Grammar` this factory has been called with, in call order.
    var receivedGrammars: [Grammar] { receivedGrammarsBox.withLock { $0 } }

    /// Creates and records a new scripted session — `SelectionConfig`'s
    /// `model` factory parameter.
    ///
    /// - Parameters:
    ///   - instructions: the instructions text to record.
    ///   - grammar: the grammar the tier derived for this call, recorded
    ///     alongside the instructions.
    /// - Returns: a freshly-scripted `ScriptedAgentSession`.
    func makeSession(instructions: String, grammar: Grammar) -> any AgentSession {
        receivedInstructionsBox.withLock { $0.append(instructions) }
        receivedGrammarsBox.withLock { $0.append(grammar) }
        return ScriptedAgentSession(responses)
    }
}

/// A thread-safe call counter — used to assert a closure ran an exact number
/// of times without needing a bespoke lock-boxed fixture per test.
final class CallCounter: Sendable {
    /// This counter's current count.
    private let countBox = OSAllocatedUnfairLock<Int>(initialState: 0)

    /// Creates a counter starting at `0`.
    init() {}

    /// Increments the count and returns its new value.
    ///
    /// - Returns: the count after incrementing.
    @discardableResult
    func increment() -> Int {
        countBox.withLock { count -> Int in
            count += 1
            return count
        }
    }

    /// This counter's current count.
    var count: Int { countBox.withLock { $0 } }
}
