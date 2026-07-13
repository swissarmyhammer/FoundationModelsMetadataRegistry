import Foundation
import Testing

@testable import FoundationModelsMetadataRegistry

/// Tests for hot reload (plan.md §8, M4): `MetadataSearcher.update(items:)`
/// re-renders and rebuilds the tokenized/trigram indexes synchronously,
/// re-embeds only items whose `(id, block-hash)` actually changed, reports
/// the async re-embed's catch-up gap via `.embedCatchUp`, drops the cached
/// selection-tier root session on a real change so the next under-budget
/// search rebuilds it against the new catalog, and is cheap (no re-embed, no
/// root drop, no diagnostics) to call redundantly — driven entirely against
/// the counting `FakeEmbedder` and scripted session fakes already shared by
/// `EmbeddingTests`/`SelectionTests`, plus this file's own gated embedder for
/// deterministically observing the interim keyword-only window.
struct HotReloadTests {
    // MARK: - Fixtures

    struct FixtureItem: SearchableMetadata {
        let id: String
        let block: String
        let summary: String?

        init(id: String, block: String, summary: String? = nil) {
            self.id = id
            self.block = block
            self.summary = summary
        }

        func renderBlock() -> String { block }
        func renderSummaryBlock() -> String { summary ?? block }
    }

    // MARK: - Incremental re-embed counts

    @Test
    func updateReEmbedsOnlyTheItemWhoseBlockActuallyChanged() async throws {
        let a = FixtureItem(id: "a", block: "alpha block")
        let b = FixtureItem(id: "b", block: "bravo block")
        let c = FixtureItem(id: "c", block: "charlie block")
        let embedder = FakeEmbedder(
            dimension: 2,
            vectorsByText: [
                "alpha block": [1, 0],
                "bravo block": [0, 1],
                "charlie block": [1, 1],
                "bravo block CHANGED": [0, -1],
            ]
        )
        let searcher = await MetadataSearcher(items: [a, b, c], embedder: embedder)
        #expect(embedder.embeddedTextCount == 3)

        await searcher.update(items: [a, FixtureItem(id: "b", block: "bravo block CHANGED"), c])

        // Only "b" was re-embedded -- the count grows by exactly 1, not by a
        // full re-embed of all three items.
        #expect(embedder.embeddedTextCount == 4)

        let matches = try await searcher.search(intent: "bravo", limit: 5)
        #expect(matches.first?.id == "b")
    }

    @Test
    func updateWithBrandNewItemsEmbedsOnlyTheNewOnes() async throws {
        let a = FixtureItem(id: "a", block: "alpha block")
        let b = FixtureItem(id: "b", block: "bravo block")
        let embedder = FakeEmbedder(dimension: 2, vectorsByText: ["alpha block": [1, 0], "bravo block": [0, 1]])
        let searcher = await MetadataSearcher(items: [a], embedder: embedder)
        #expect(embedder.embeddedTextCount == 1)

        await searcher.update(items: [a, b])

        #expect(embedder.embeddedTextCount == 2)
    }

    // MARK: - Redundant update is a no-op

    @Test
    func redundantUpdateWithIdenticalItemsPerformsNoReEmbedAndRetainsTheRootSession() async throws {
        let items = [FixtureItem(id: "a", block: "alpha block")]
        let embedder = FakeEmbedder(dimension: 2, vectorsByText: ["alpha block": [1, 0]])
        let root = RootSessionRespondCalledDirectlySession(forkResponses: [
            #"{"ids":["a"]}"#,
            #"{"ids":["a"]}"#,
        ])
        let factoryCallCount = CallCounter()
        let config = SelectionConfig(model: { _ in
            factoryCallCount.increment()
            return root
        })
        let searcher = await MetadataSearcher(items: items, mode: .selection, embedder: embedder, selection: config)
        #expect(embedder.embeddedTextCount == 1)

        _ = try await searcher.search(intent: "task", limit: 5)
        #expect(factoryCallCount.count == 1)

        await searcher.update(items: items)

        _ = try await searcher.search(intent: "task", limit: 5)

        // No new embed call, and the same cached root forked again --
        // `update` with unchanged content never dropped it.
        #expect(embedder.embeddedTextCount == 1)
        #expect(factoryCallCount.count == 1)
        #expect(root.forkCount == 2)
    }

    @Test
    func redundantUpdateNeverEmitsAnyDiagnostic() async throws {
        let recorder = DiagnosticRecorder()
        let items = [FixtureItem(id: "a", block: "alpha block")]
        let embedder = FakeEmbedder(dimension: 2, vectorsByText: ["alpha block": [1, 0]])
        let searcher = await MetadataSearcher(
            items: items,
            embedder: embedder,
            onDiagnostic: { recorder.record($0) }
        )

        await searcher.update(items: items)

        #expect(recorder.diagnostics.isEmpty)
    }

    // MARK: - Root/grammar invalidation on a real change

    @Test
    func updateWithARealChangeDropsTheCachedRootSoTheNextSearchRebuildsItAgainstTheNewCatalog() async throws {
        let itemA = FixtureItem(id: "a", block: "alpha block", summary: "SUMMARY_a")
        let itemB = FixtureItem(id: "b", block: "bravo block", summary: "SUMMARY_b")
        let factory = RecordingSessionFactory(responses: [#"{"ids":["a"]}"#])
        let config = SelectionConfig(model: factory.makeSession)
        let searcher = MetadataSearcher(items: [itemA], mode: .selection, selection: config)

        _ = try await searcher.search(intent: "task", limit: 5)
        #expect(factory.receivedInstructions.count == 1)
        #expect(!factory.receivedInstructions[0].contains("SUMMARY_b"))

        await searcher.update(items: [itemA, itemB])

        _ = try await searcher.search(intent: "task", limit: 5)

        // The root was rebuilt (factory invoked again, not reused), and the
        // rebuilt prefix's candidate id set -- what a real id-enum grammar
        // would be derived from -- reflects the new catalog.
        #expect(factory.receivedInstructions.count == 2)
        #expect(factory.receivedInstructions[1].contains("SUMMARY_a"))
        #expect(factory.receivedInstructions[1].contains("SUMMARY_b"))
    }

    @Test
    func idEnumGrammarAfterAnUpdateReflectsExactlyTheNewCatalogsIds() throws {
        // `SelectionTier.idEnumGrammar(ids:)` is a pure function of the
        // current id set; proving `update(items:)` changes that id set is
        // `updateWithARealChangeDropsTheCachedRoot...`'s job. This test
        // pins down the grammar itself for the *post-update* id set, so a
        // regression in either half is caught independently.
        let updatedIds = ["a", "b", "c"]
        let grammar = try SelectionTier<FixtureItem>.idEnumGrammar(ids: updatedIds)

        guard case .jsonSchema(let source) = grammar else {
            Issue.record("expected a .jsonSchema grammar")
            return
        }
        let data = try #require(source.data(using: .utf8))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try #require(root["properties"] as? [String: Any])
        let idsSchema = try #require(properties["ids"] as? [String: Any])
        let itemsSchema = try #require(idsSchema["items"] as? [String: Any])
        let enumValues = try #require(itemsSchema["enum"] as? [String])

        #expect(Set(enumValues) == Set(updatedIds))
    }

    // MARK: - Embed catch-up diagnostic

    @Test
    func updateReportsEmbedCatchUpWithAccuratePendingAndTotalCounts() async throws {
        let recorder = DiagnosticRecorder()
        let a = FixtureItem(id: "a", block: "alpha block")
        let b = FixtureItem(id: "b", block: "bravo block")
        let embedder = FakeEmbedder(dimension: 2, vectorsByText: ["alpha block": [1, 0], "bravo block": [0, 1]])
        let searcher = await MetadataSearcher(
            items: [a],
            embedder: embedder,
            onDiagnostic: { recorder.record($0) }
        )

        await searcher.update(items: [a, b])

        #expect(recorder.diagnostics.contains(.embedCatchUp(pending: 1, total: 2)))
    }

    @Test
    func updateWithNoEmbedderConfiguredNeverEmitsEmbedCatchUp() async throws {
        let recorder = DiagnosticRecorder()
        let a = FixtureItem(id: "a", block: "alpha block")
        let searcher = MetadataSearcher(items: [FixtureItem](), onDiagnostic: { recorder.record($0) })

        await searcher.update(items: [a])

        let matches = try await searcher.search(intent: "alpha", limit: 5)
        #expect(matches.map(\.id) == ["a"])
        #expect(
            !recorder.diagnostics.contains {
                if case .embedCatchUp = $0 { return true }
                return false
            }
        )
    }

    // MARK: - Interim keyword-only service while re-embedding is in flight

    @Test
    func concurrentSearchDuringUpdateServesKeywordOnlyForTheNotYetEmbeddedItem() async throws {
        let commit = FixtureItem(id: "commit", block: "records a snapshot of staged changes")
        let gate = EmbedGate()
        // "snapshot" (the query text) also maps to `[1, 0]` so the
        // post-catch-up search's own query embed call -- which reuses this
        // same gated embedder, now released -- lines up with `commit`'s
        // freshly stored embedding instead of falling back to an all-zero
        // vector that would trivially score `0.0` regardless of catch-up.
        let embedder = GatedEmbedder(dimension: 2, vectorsByText: [commit.block: [1, 0], "snapshot": [1, 0]], gate: gate)
        // Construct with an empty catalog so init itself never touches the
        // gate -- there's nothing to embed yet.
        let searcher = await MetadataSearcher(items: [FixtureItem](), embedder: embedder)

        let updateTask = Task { await searcher.update(items: [commit]) }

        // Wait until `update`'s embed call has actually started: the
        // synchronous baseline reassignment (tokenized/trigram indexes)
        // that precedes it has therefore already happened, and this call is
        // now suspended on the gate -- the actor is free to interleave a
        // concurrent `search()` while it waits.
        await gate.waitForStart()

        let interimMatches = try await searcher.search(intent: "snapshot", limit: 5)
        let interimMatch = try #require(interimMatches.first)
        #expect(interimMatch.id == "commit")
        #expect(interimMatch.signals?.cosine == 0.0)

        await gate.release()
        await updateTask.value

        let caughtUpMatches = try await searcher.search(intent: "snapshot", limit: 5)
        let caughtUpMatch = try #require(caughtUpMatches.first)
        #expect(caughtUpMatch.signals?.cosine != 0.0)
    }

    // MARK: - Catch-up survives a content-unchanged redundant forward

    @Test
    func updateStillCatchesUpAnEmbeddingThatNeverSucceededEvenWhenContentIsUnchanged() async throws {
        // Simulates a prior build/update whose embed call failed
        // transiently (plan.md §8 "embed catch-up"): "a" is indexed with
        // its real content but carries no stored embedding.
        struct AlwaysFails: Error {}
        let a = FixtureItem(id: "a", block: "alpha block")
        let indexWithoutEmbedding = await MetadataIndex.build(items: [a], embedder: FakeEmbedder(dimension: 2, failure: AlwaysFails()))
        #expect(indexWithoutEmbedding.embedding(forID: "a") == nil)

        let recorder = DiagnosticRecorder()
        let workingEmbedder = FakeEmbedder(dimension: 2, vectorsByText: ["alpha block": [1, 0], "alpha": [1, 0]])
        let searcher = MetadataSearcher(
            index: indexWithoutEmbedding,
            embedder: workingEmbedder,
            onDiagnostic: { recorder.record($0) }
        )

        // Same content as what's already indexed -- e.g. an upstream
        // notification forwarded without coalescing, exactly the pattern
        // the task's hash-guarding is meant to make cheap. It must NOT be
        // treated as a full no-op: the embedding that never succeeded still
        // needs to catch up.
        await searcher.update(items: [a])

        #expect(recorder.diagnostics.contains(.embedCatchUp(pending: 1, total: 1)))
        #expect(workingEmbedder.embeddedTextCount == 1)

        let matches = try await searcher.search(intent: "alpha", limit: 5)
        #expect(matches.first?.signals?.cosine != 0.0)
    }

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
                toolC.block: [1, 1],
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
