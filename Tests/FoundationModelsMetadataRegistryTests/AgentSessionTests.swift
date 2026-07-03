import FoundationModels
import Testing

@testable import FoundationModelsMetadataRegistry

/// Tests for the `AgentSession` seam (plan.md §6, §8 "Seams"): the default
/// `respond(to:generating:)` decode over `GeneratedContent(json:)`, and
/// `ScriptedAgentSession`'s scripted-response + fork-counting test double —
/// the same zero-GPU pattern Multitool's `AgentSession` establishes, lifted
/// here so the later Multitool migration re-exports rather than rewrites it.
struct AgentSessionTests {
    /// A minimal `@Generable` fixture — stands in for a real guided-output
    /// shape (e.g. `FoundAPIs`) without pulling one in.
    @Generable
    struct Greeting {
        var text: String
    }

    // MARK: - Default `respond(to:generating:)` decoding

    @Test
    func respondToGeneratingDecodesAGenerableFixtureFromScriptedJSON() async throws {
        let session = ScriptedAgentSession([#"{"text":"hello"}"#])

        let greeting = try await session.respond(to: "hi", generating: Greeting.self)

        #expect(greeting.text == "hello")
    }

    @Test
    func respondToGeneratingThrowsOnMalformedJSON() async throws {
        let session = ScriptedAgentSession(["this is not JSON"])

        await #expect(throws: (any Error).self) {
            _ = try await session.respond(to: "hi", generating: Greeting.self)
        }
    }

    // MARK: - Scripted responses

    @Test
    func respondReturnsEachScriptedResponseInOrder() async throws {
        let session = ScriptedAgentSession(["first", "second"])

        let first = try await session.respond(to: "a")
        let second = try await session.respond(to: "b")

        #expect(first == "first")
        #expect(second == "second")
        #expect(session.receivedPrompts == ["a", "b"])
    }

    @Test
    func respondThrowsOnceScriptedResponsesAreExhausted() async throws {
        let session = ScriptedAgentSession(["only"])

        _ = try await session.respond(to: "a")

        await #expect(throws: (any Error).self) {
            _ = try await session.respond(to: "b")
        }
    }

    // MARK: - Fork counting

    @Test
    func forkCountsEachForkCall() async throws {
        let session = ScriptedAgentSession(["a"])

        _ = try await session.fork()
        _ = try await session.fork()

        #expect(session.forkCount == 2)
    }

    @Test
    func forkedSessionSharesNoStateWithParentBeyondScriptedResponses() async throws {
        // A no-op-by-default `fork()` conformer (matching Multitool's
        // documented default: "returns `self`, unchanged") must not need a
        // real KV cache to satisfy the seam -- `ScriptedAgentSession` never
        // exercises a real fork, only asserts it was *called* the right
        // number of times.
        let session = ScriptedAgentSession(["a", "b"])

        let forked = try await session.fork()

        let reply = try await forked.respond(to: "prompt")
        #expect(reply == "a")
    }
}
