import Testing

@testable import FoundationModelsMetadataRegistry

/// Overlapping/bursty `MetadataSearcher.update(items:)` calls (plan.md §8):
/// two concurrent updates racing on the same id, and an MCP-style add/remove
/// burst forwarded without coalescing (the searcher coalesces it itself — see
/// `HotReloadCoalescingTests`). Split out of `HotReloadTests` to keep
/// each file within the project's line-length conventions; shares its
/// `FixtureItem` fixture via `HotReloadTests`.
extension HotReloadTests {
  // MARK: - Overlapping update(items:) calls on the same id

  /// Bounded because the gate below has no timeout of its own: an update
  /// that never reaches the embedder never signals the gate, and this test
  /// must then fail rather than wait forever.
  @Test(.timeLimit(.minutes(1)))
  func overlappingUpdatesToTheSameIdNeverLetAnEarlierSlowerEmbedOverwriteALaterFasterOne()
    async throws
  {
    let itemV1 = FixtureItem(id: "x", block: "version one text")
    let itemV2 = FixtureItem(id: "x", block: "version two text")
    let gate = EmbedGate()
    // Only the first update's text is gated -- the embed of the second
    // update's text resolves at once when the reload loop reaches it.
    let embedder = GatedEmbedder(
      vectorsByText: ["version one text": [1, 0], "version two text": [0, 1]],
      gate: gate,
      gatedTexts: ["version one text"],
    )
    // Empty initial catalog so construction itself never touches the gate.
    let searcher = MetadataSearcher(items: [FixtureItem](), embedder: embedder)

    let updateATask = Task { await searcher.update(items: [itemV1]) }
    await gate.waitForStart()

    // While A is suspended re-embedding "version one text", B replaces
    // the same id with different content -- actor reentrancy across A's
    // suspended `await embedder.embed(_:)`. B joins the reload loop in
    // flight and waits for it, so it runs in a task of its own; the wait
    // below returns when B's keyword index is live.
    let updateBTask = Task { await searcher.update(items: [itemV2]) }
    await Self.waitUntilIndex(of: searcher) { $0.block(forID: itemV2.id) == itemV2.block }

    // Release A last, so its stale vector arrives after B has already
    // replaced "x" with "version two text".
    await gate.release()
    await updateATask.value
    await updateBTask.value

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
      vectorsByText: [
        toolA.block: [1, 0],
        toolB.block: [0, 1],
        toolC.block: [1, 1],
      ],
    )
    let searcher = MetadataSearcher(items: [FixtureItem](), embedder: embedder)

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
