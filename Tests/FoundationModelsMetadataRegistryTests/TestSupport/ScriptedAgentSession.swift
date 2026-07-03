import os

@testable import FoundationModelsMetadataRegistry

/// Thrown by `ScriptedAgentSession.respond(to:)` when it receives more calls
/// than it was scripted with — a test bug (an under-scripted fixture), never
/// a condition a correctly scripted fixture should trigger in production
/// code driven through the `AgentSession` seam.
struct ScriptedAgentSessionError: Error, Equatable, CustomStringConvertible {
    /// How many scripted responses `respond(to:)` had queued.
    let scriptedResponseCount: Int

    var description: String {
        "ScriptedAgentSession received more calls than its \(scriptedResponseCount) scripted response(s)."
    }
}

/// A scripted `AgentSession` test double: returns its canned `responses` in
/// order, one per call, regardless of the prompt, and counts `fork()`
/// calls — this test target's zero-GPU stand-in for a real Router session,
/// the same pattern Multitool's `ScriptedAgentSession` establishes (lifted
/// alongside the seam itself, plan.md §6/§8).
///
/// `final class ... Sendable` (not a `struct`) because `respond(to:)` needs
/// to record every prompt it received and advance a call index across
/// `await` boundaries, and `fork()` needs to record a call count visible
/// after the `async` call returns; state lives behind an
/// `OSAllocatedUnfairLock`.
final class ScriptedAgentSession: AgentSession, Sendable {
    /// The mutable state guarded by `stateBox`.
    private struct State {
        /// How many calls `respond(to:)` has handled so far — the index into
        /// `responses` the next call consumes.
        var callCount = 0
        /// Every prompt `respond(to:)` has received, in call order.
        var receivedPrompts: [String] = []
        /// How many times `fork()` has been called.
        var forkCount = 0
    }

    /// The canned responses returned in order, one per call.
    private let responses: [String]

    /// This session's call state.
    private let stateBox: OSAllocatedUnfairLock<State>

    /// Creates a scripted session that returns `responses` in order, one per
    /// `respond(to:)` call.
    ///
    /// - Parameter responses: the canned responses to return, in call order.
    init(_ responses: [String]) {
        self.responses = responses
        self.stateBox = OSAllocatedUnfairLock(initialState: State())
    }

    /// Every prompt this session received, in call order — lets a test
    /// assert on what a caller fed back as the next turn's prompt.
    var receivedPrompts: [String] { stateBox.withLock { $0.receivedPrompts } }

    /// How many calls this session has handled so far.
    var callCount: Int { stateBox.withLock { $0.callCount } }

    /// How many times `fork()` has been called on this session.
    var forkCount: Int { stateBox.withLock { $0.forkCount } }

    func respond(to prompt: String) async throws -> String {
        let index = stateBox.withLock { state -> Int in
            state.receivedPrompts.append(prompt)
            let index = state.callCount
            state.callCount += 1
            return index
        }
        guard index < responses.count else {
            throw ScriptedAgentSessionError(scriptedResponseCount: responses.count)
        }
        return responses[index]
    }

    func fork() async throws -> any AgentSession {
        stateBox.withLock { $0.forkCount += 1 }
        return self
    }
}
