@testable import FoundationModelsMetadataRegistry
import Testing

/// Overlapping/bursty `MetadataSearcher.update(items:)` calls (plan.md §8):
/// two concurrent updates racing on the same id, and an MCP-style add/remove
/// burst forwarded without coalescing. Split out of `HotReloadTests` to keep
/// each file within the project's line-length conventions; shares its
/// `FixtureItem` fixture via `HotReloadTests`.
extension HotReloadTests {
    // MARK: - Overlapping update(items:) calls on the same id

    @Test
    func overlappingUpdatesToTheSameIdNeverLetAnEarlierSlowerEmbedOverwriteALaterFasterOne() async throws {
        let itemV1 = FixtureItem(id: "x", block: "version one text")
        let itemV2 = FixtureItem(id: "x", block: "version two text")
        let gate = EmbedGate()
        // Only the first update's text is gated -- the second update's text
        // resolves immediately, so it deterministically finishes (including
        // its own merge) while the first stays suspended, never racing.
        let embedder = GatedEmbedder(
            dimension: 2,
            vectorsByText: ["version one text": [1, 0], "version two text": [0, 1]],
            gate: gate,
            gatedTexts: ["version one text"]
        )
        // Empty initial catalog so construction itself never touches the gate.
        let searcher = await MetadataSearcher(items: [FixtureItem](), embedder: embedder)

        let updateATask = Task { await searcher.update(items: [itemV1]) }
        await gate.waitForStart()

        // While A is suspended re-embedding "version one text", B runs to
        // completion against the same id with different content -- actor
        // reentrancy across A's suspended `await embedder.embed(_:)`.
        await searcher.update(items: [itemV2])

        // Release A last, so its stale vector arrives after B has already
        // committed "version two text"'s embedding.
        await gate.release()
        await updateATask.value

        // The final state must reflect B's content and B's embedding, never
        // A's stale vector paired with B's (different) block hash.
        let matchingV2Query = try await searcher.search(intent: "version two text", limit: 5)
        #expect(matchingV2Query.first?.signals?.cosine != 0.0)

        let matchingV1Query = try await searcher.search(intent: "version one text", limit: 5)
        #expect(matchingV1Query.first?.signals?.cosine == 0.0)
    }

    // MARK: - MCP-style add/remove burst

    @Test
    func mcpStyleAddAndRemoveBurstStaysSearchableAndEmbedsOnlyNetNewItems() async throws {
        let toolA = FixtureItem(id: "toolA", block: "reads a file from disk")
        let toolB = FixtureItem(id: "toolB", block: "writes a file to disk")
        let toolC = FixtureItem(id: "toolC", block: "deletes a file from disk")
        let embedder = FakeEmbedder(
            dimension: 2,
            vectorsByText: [
                toolA.block: [1, 0],
                toolB.block: [0, 1],
                toolC.block: [1, 1]
            ]
        )
        let searcher = await MetadataSearcher(items: [FixtureItem](), embedder: embedder)

        // A server connects mid-session and dumps its tools in without
        // coalescing -- every notification forwarded straight to `update`.
        await searcher.update(items: [toolA])
        await searcher.update(items: [toolA, toolB])
        #expect(embedder.embeddedTextCount == 2)

        let afterFirstBurst = try await searcher.search(intent: "file", limit: 5)
        #expect(Set(afterFirstBurst.map(\.id)) == Set(["toolA", "toolB"]))

        // Redundant forward (no upstream change) followed by a real
        // remove-and-add burst. Captured *after* the search above (whose own
        // query embed call also passes through this shared embedder) so the
        // assertion below isolates this burst's catalog re-embed delta from
        // query-embed noise.
        let countBeforeSecondBurst = embedder.embeddedTextCount
        await searcher.update(items: [toolA, toolB])
        await searcher.update(items: [toolB, toolC])

        // Only "toolC" is net-new -- "toolA" was dropped, never re-embedded
        // again, and "toolB" was untouched.
        #expect(embedder.embeddedTextCount == countBeforeSecondBurst + 1)

        let afterSecondBurst = try await searcher.search(intent: "file", limit: 5)
        #expect(Set(afterSecondBurst.map(\.id)) == Set(["toolB", "toolC"]))
    }
}
