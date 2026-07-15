import Testing

@testable import FoundationModelsMetadataRegistry

/// Tests for the embedding signal (plan.md §5, §8): the `TextEmbedding`
/// seam, cosine joining RRF fusion in `MetadataSearcher.search`, the
/// absent-signal rule for un-embedded items, graceful degradation to
/// keyword-only with `.embeddingUnavailable` when no embedder is
/// configured, and `MetadataIndex.build(items:embedder:previous:onDiagnostic:)`'s
/// hash-keyed incremental re-embedding. `RoutedEmbedderAdapter` compiles
/// (proving it type-checks against FoundationModelsRouter's `RoutedEmbedder`)
/// but is never exercised here — no GPU in unit tests.
struct EmbeddingTests {
    struct FixtureItem: SearchableMetadata {
        let id: String
        let block: String

        func renderBlock() -> String { block }
    }

    // MARK: - Cosine joins fusion

    @Test
    func cosineSignalRanksASemanticMatchAboveWhatKeywordSignalsAloneFind() async throws {
        // "save my work" shares no BM25 token and no character trigram with
        // `commit`'s id or block -- a keyword-only searcher (cosine weighted
        // to zero) must never surface `commit` for it. `FakeEmbedder` maps
        // the query and `commit`'s block to the identical vector, so once
        // cosine joins fusion it must rank `commit` first.
        let commit = FixtureItem(id: "commit", block: "records a snapshot of staged changes to the repository history")
        let status = FixtureItem(id: "status", block: "reports the current state of the working tree")
        let query = "save my work"

        let embedder = FakeEmbedder(
            dimension: 2,
            vectorsByText: [
                query: [1, 0],
                commit.block: [1, 0],
                status.block: [0, 1],
            ]
        )

        let keywordOnly = MetadataSearcher(items: [commit, status], weights: .init(cosine: 0.0))
        let keywordOnlyMatches = try await keywordOnly.search(intent: query, limit: 5)
        #expect(!keywordOnlyMatches.contains { $0.id == "commit" })

        let searcher = await MetadataSearcher(items: [commit, status], embedder: embedder)
        let matches = try await searcher.search(intent: query, limit: 5)

        let first = try #require(matches.first)
        #expect(first.id == "commit")
        let signals = try #require(first.signals)
        #expect(signals.bm25 == 0.0)
        #expect(signals.trigram == 0.0)
        #expect(signals.cosine > 0.0)
    }

    // MARK: - Degradation diagnostic capture

    @Test
    func searchWithNoEmbedderConfiguredEmitsEmbeddingUnavailableDiagnostic() async throws {
        let recorder = DiagnosticRecorder()
        let searcher = MetadataSearcher(
            items: [FixtureItem(id: "commit", block: "records a snapshot")],
            onDiagnostic: { recorder.record($0) }
        )

        _ = try await searcher.search(intent: "commit", limit: 5)

        #expect(recorder.diagnostics.contains(.embeddingUnavailable))
    }

    /// A `TextEmbedding` conformer that violates the documented "one vector
    /// per input" contract by always returning an empty array without
    /// throwing -- exercises `computeCosineScores`'s defense-in-depth
    /// diagnostic for that specific misbehavior, distinct from the
    /// `FakeEmbedder`-throwing path `searchWithNoEmbedderConfigured...`
    /// and friends already cover.
    private struct EmptyResultEmbedder: TextEmbedding {
        let dimension = 2
        func embed(_ texts: [String]) async throws -> [[Float]] { [] }
    }

    @Test
    func searchWithAnEmbedderReturningNoVectorsEmitsEmbeddingUnavailableDiagnostic() async throws {
        let recorder = DiagnosticRecorder()
        let searcher = await MetadataSearcher(
            items: [FixtureItem(id: "commit", block: "records a snapshot")],
            embedder: EmptyResultEmbedder(),
            onDiagnostic: { recorder.record($0) }
        )

        _ = try await searcher.search(intent: "commit", limit: 5)

        #expect(recorder.diagnostics.contains(.embeddingUnavailable))
    }

    @Test
    func searchWithAnEmbedderConfiguredNeverEmitsEmbeddingUnavailable() async throws {
        let recorder = DiagnosticRecorder()
        let item = FixtureItem(id: "commit", block: "records a snapshot")
        let embedder = FakeEmbedder(dimension: 2, vectorsByText: ["commit": [1, 0], item.block: [1, 0]])
        let searcher = await MetadataSearcher(
            items: [item],
            embedder: embedder,
            onDiagnostic: { recorder.record($0) }
        )

        _ = try await searcher.search(intent: "commit", limit: 5)

        #expect(!recorder.diagnostics.contains(.embeddingUnavailable))
    }

    // MARK: - Absent-signal rule

    @Test
    func itemsWithoutEmbeddingsContributeNothingToCosineButStillRankViaKeywordSignals() async throws {
        let embeddedItem = FixtureItem(id: "commit", block: "records a snapshot of staged changes")
        let unembeddedItem = FixtureItem(id: "status", block: "reports current release health")
        let query = "save my work"

        // First build: only `embeddedItem` exists, and its embed call
        // succeeds -- it now carries a real, reusable embedding.
        let workingEmbedder = FakeEmbedder(dimension: 2, vectorsByText: [query: [1, 0], embeddedItem.block: [1, 0]])
        let priorIndex = await MetadataIndex.build(items: [embeddedItem], embedder: workingEmbedder)
        #expect(priorIndex.embedding(forID: "commit") != nil)

        // Second build: `unembeddedItem` is new, and this build's embedder
        // fails for the whole batch -- `unembeddedItem` stays `nil`, while
        // `embeddedItem` (unchanged block, hash match, non-nil prior
        // embedding) is reused with no new embed call at all, exactly the
        // hash-keyed incremental-reuse contract.
        struct SampleEmbedFailure: Error {}
        let failingEmbedder = FakeEmbedder(dimension: 2, failure: SampleEmbedFailure())
        let index = await MetadataIndex.build(
            items: [embeddedItem, unembeddedItem],
            embedder: failingEmbedder,
            previous: priorIndex
        )
        #expect(index.embedding(forID: "commit") != nil)
        #expect(index.embedding(forID: "status") == nil)

        let searcher = MetadataSearcher(index: index, embedder: workingEmbedder)

        let cosineMatches = try await searcher.search(intent: query, limit: 5)
        #expect(cosineMatches.first?.id == "commit")

        // A keyword query aimed at the un-embedded item must still surface
        // it through BM25 + trigram, with cosine reported as absent (0.0).
        let keywordMatches = try await searcher.search(intent: "release health", limit: 5)
        let firstKeywordMatch = try #require(keywordMatches.first)
        #expect(firstKeywordMatch.id == "status")
        #expect(firstKeywordMatch.signals?.cosine == 0.0)
    }

    // MARK: - Hash-keyed incremental embed

    @Test
    func incrementalBuildEmbedsOnlyChangedBlocks() async throws {
        let itemsV1 = [
            FixtureItem(id: "a", block: "alpha block"),
            FixtureItem(id: "b", block: "bravo block"),
            FixtureItem(id: "c", block: "charlie block"),
        ]
        let embedder = FakeEmbedder(
            dimension: 2,
            vectorsByText: [
                "alpha block": [1, 0],
                "bravo block": [0, 1],
                "charlie block": [1, 1],
                "bravo block CHANGED": [0, -1],
            ]
        )

        let indexV1 = await MetadataIndex.build(items: itemsV1, embedder: embedder)
        #expect(embedder.embeddedTextCount == 3)

        // Only "b"'s block changes between builds.
        let itemsV2 = [
            FixtureItem(id: "a", block: "alpha block"),
            FixtureItem(id: "b", block: "bravo block CHANGED"),
            FixtureItem(id: "c", block: "charlie block"),
        ]
        let indexV2 = await MetadataIndex.build(items: itemsV2, embedder: embedder, previous: indexV1)

        // Only the one changed block is re-embedded -- the count grows by
        // exactly 1, not by 3 (a full re-embed of every item).
        #expect(embedder.embeddedTextCount == 4)
        #expect(indexV2.embedding(forID: "a") == indexV1.embedding(forID: "a"))
        #expect(indexV2.embedding(forID: "c") == indexV1.embedding(forID: "c"))
        #expect(indexV2.embedding(forID: "b") != indexV1.embedding(forID: "b"))
    }

    @Test
    func incrementalBuildWithNoPreviousIndexEmbedsEveryItem() async throws {
        let items = [
            FixtureItem(id: "a", block: "alpha block"),
            FixtureItem(id: "b", block: "bravo block"),
        ]
        let embedder = FakeEmbedder(dimension: 2, vectorsByText: ["alpha block": [1, 0], "bravo block": [0, 1]])

        let index = await MetadataIndex.build(items: items, embedder: embedder)

        #expect(embedder.embeddedTextCount == 2)
        #expect(index.embedding(forID: "a") == [1, 0])
        #expect(index.embedding(forID: "b") == [0, 1])
    }

    @Test
    func buildWithNoEmbedderLeavesEveryEmbeddingNil() async throws {
        let items = [FixtureItem(id: "a", block: "alpha block")]
        let index = await MetadataIndex.build(items: items, embedder: nil)

        #expect(index.embedding(forID: "a") == nil)
    }

    @Test
    func incrementalBuildEmbedsAnItemThatHadNoEmbeddingOnceAnEmbedderBecomesAvailable() async throws {
        let item = FixtureItem(id: "a", block: "alpha block")

        // Built with no embedder at all: "a"'s embedding is nil.
        let indexWithoutEmbedder = await MetadataIndex.build(items: [item], embedder: nil)
        #expect(indexWithoutEmbedder.embedding(forID: "a") == nil)

        // Rebuilding with an embedder now configured, same unchanged block
        // text, must still embed it -- a hash match must never let a stored
        // `nil` be reused as if it were a valid cached embedding, or the
        // item would stay cosine-blind forever even after an embedder
        // becomes available (plan.md §8 "embed catch-up").
        let embedder = FakeEmbedder(dimension: 2, vectorsByText: ["alpha block": [1, 0]])
        let indexWithEmbedder = await MetadataIndex.build(items: [item], embedder: embedder, previous: indexWithoutEmbedder)

        #expect(indexWithEmbedder.embedding(forID: "a") == [1, 0])
        #expect(embedder.embeddedTextCount == 1)
    }
}
