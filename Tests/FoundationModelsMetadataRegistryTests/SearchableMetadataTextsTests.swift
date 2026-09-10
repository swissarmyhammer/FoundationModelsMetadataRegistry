@testable import FoundationModelsMetadataRegistry
import Testing

/// Tests for the three texts one catalog item renders (plan.md §4): the
/// keyword index's `renderIndexedText(from:)`, the embedder's
/// `renderEmbeddedText(from:)`, and the verbatim `renderBlock()` a `Match`
/// carries back.
///
/// Each fixture here overrides exactly one of the two derived texts, so every
/// test reads one signal against a text no other signal was given: the
/// fixture's overridden text must reach its own signal, and the block must
/// reach every other one.
struct SearchableMetadataTextsTests {
    // MARK: - Fixtures

    /// A conformer that overrides `renderIndexedText(from:)` alone, leaving
    /// the embedder and the verbatim block on the default block text.
    struct IndexedTextMetadata: SearchableMetadata {
        let id: String
        let block: String

        /// The text the keyword index tokenizes, in place of `block`.
        let indexedText: String

        func renderBlock() -> String {
            block
        }

        func renderIndexedText(from _: String) -> String {
            indexedText
        }
    }

    /// A conformer that overrides `renderEmbeddedText(from:)` alone, leaving
    /// the keyword index and the verbatim block on the default block text.
    struct EmbeddedTextMetadata: SearchableMetadata {
        let id: String
        let block: String

        /// The text the embedder embeds, in place of `block`.
        let embeddedText: String

        func renderBlock() -> String {
            block
        }

        func renderEmbeddedText(from _: String) -> String {
            embeddedText
        }
    }

    // MARK: - The defaults

    @Test
    func renderIndexedTextDefaultsToTheBlockItIsGiven() {
        let item = EmbeddedTextMetadata(
            id: "commit", block: "records a snapshot", embeddedText: "saves your work",
        )
        #expect(item.renderIndexedText(from: item.renderBlock()) == item.renderBlock())
    }

    @Test
    func renderEmbeddedTextDefaultsToTheBlockItIsGiven() {
        let item = IndexedTextMetadata(
            id: "commit", block: "records a snapshot", indexedText: "kubernetes rollout",
        )
        #expect(item.renderEmbeddedText(from: item.renderBlock()) == item.renderBlock())
    }

    // MARK: - The indexed text reaches the keyword signals alone

    @Test
    func aTermOnlyInTheIndexedTextIsFoundByTheKeywordSignals() async throws {
        let searcher = MetadataSearcher(items: [Self.indexedOverrideItem], weights: .init(cosine: 0.0))

        let matches = try await searcher.search(intent: "kubernetes", limit: 5)

        #expect(matches.first?.id == "deploy")
    }

    @Test
    func aTermOnlyInTheBlockIsNotFoundWhenTheIndexedTextIsOverridden() async throws {
        let searcher = MetadataSearcher(items: [Self.indexedOverrideItem], weights: .init(cosine: 0.0))

        let matches = try await searcher.search(intent: "containers", limit: 5)

        #expect(matches.isEmpty)
    }

    @Test
    func aMatchCarriesTheVerbatimBlockWhenTheIndexedTextIsOverridden() async throws {
        let searcher = MetadataSearcher(items: [Self.indexedOverrideItem], weights: .init(cosine: 0.0))

        let matches = try await searcher.search(intent: "kubernetes", limit: 5)

        #expect(matches.first?.block == Self.indexedOverrideItem.block)
    }

    @Test
    func theEmbedderReceivesTheBlockWhenOnlyTheIndexedTextIsOverridden() async {
        let embedder = FakeEmbedder(dimension: 2)

        _ = await MetadataIndex.build(items: [Self.indexedOverrideItem], embedder: embedder)

        #expect(embedder.embeddedBatches == [[Self.indexedOverrideItem.block]])
    }

    // MARK: - The embedded text reaches the embedder alone

    @Test
    func theEmbedderReceivesTheOverriddenEmbeddedText() async {
        let embedder = FakeEmbedder(dimension: 2)

        _ = await MetadataIndex.build(items: [Self.embeddedOverrideItem], embedder: embedder)

        #expect(embedder.embeddedBatches == [[Self.embeddedOverrideItem.embeddedText]])
    }

    @Test
    func aTermOnlyInTheEmbeddedTextIsNotFoundByTheKeywordSignals() async throws {
        let searcher = MetadataSearcher(items: [Self.embeddedOverrideItem], weights: .init(cosine: 0.0))

        let matches = try await searcher.search(intent: "kubernetes", limit: 5)

        #expect(matches.isEmpty)
    }

    @Test
    func aMatchCarriesTheVerbatimBlockWhenTheEmbeddedTextIsOverridden() async throws {
        let searcher = MetadataSearcher(items: [Self.embeddedOverrideItem], weights: .init(cosine: 0.0))

        let matches = try await searcher.search(intent: "containers", limit: 5)

        #expect(matches.first?.block == Self.embeddedOverrideItem.block)
    }

    // MARK: - Embedding reuse keys on the embedded text

    @Test
    func changingOnlyTheEmbeddedTextReEmbedsThatEntry() async {
        let sharedBlock = "ships containers to production"
        let first = EmbeddedTextMetadata(id: "deploy", block: sharedBlock, embeddedText: "alpha embedding text")
        let second = EmbeddedTextMetadata(id: "deploy", block: sharedBlock, embeddedText: "bravo embedding text")
        let embedder = FakeEmbedder(
            dimension: 2,
            vectorsByText: ["alpha embedding text": [1, 0], "bravo embedding text": [0, 1]],
        )

        let firstIndex = await MetadataIndex.build(items: [first], embedder: embedder)
        let secondIndex = await MetadataIndex.build(items: [second], embedder: embedder, previous: firstIndex)

        #expect(embedder.embeddedBatches == [["alpha embedding text"], ["bravo embedding text"]])
        #expect(firstIndex.embedding(forID: "deploy") == [1, 0])
        #expect(secondIndex.embedding(forID: "deploy") == [0, 1])
    }

    @Test
    func changingOnlyTheBlockReusesTheStoredEmbedding() async {
        let sharedEmbeddedText = "saves your work"
        let first = EmbeddedTextMetadata(id: "commit", block: "first block", embeddedText: sharedEmbeddedText)
        let second = EmbeddedTextMetadata(id: "commit", block: "second block", embeddedText: sharedEmbeddedText)
        let embedder = FakeEmbedder(dimension: 2, vectorsByText: [sharedEmbeddedText: [1, 0]])

        let firstIndex = await MetadataIndex.build(items: [first], embedder: embedder)
        let secondIndex = await MetadataIndex.build(items: [second], embedder: embedder, previous: firstIndex)

        #expect(embedder.embeddedBatches == [[sharedEmbeddedText]])
        #expect(secondIndex.embedding(forID: "commit") == [1, 0])
    }

    @Test
    func updateWithOnlyTheBlockChangedRefreshesTheVerbatimBlock() async throws {
        // The searcher is built through the embedding initializer, so every
        // entry already carries an embedding and nothing is pending. The
        // changed block is then the only thing that can carry `update`'s
        // redundant-update guard past its early return.
        let sharedEmbeddedText = "saves your work"
        let first = EmbeddedTextMetadata(id: "commit", block: "first block", embeddedText: sharedEmbeddedText)
        let second = EmbeddedTextMetadata(id: "commit", block: "second block", embeddedText: sharedEmbeddedText)
        let embedder = FakeEmbedder(dimension: 2, vectorsByText: [sharedEmbeddedText: [1, 0]])
        let searcher = await MetadataSearcher(items: [first], embedder: embedder)

        await searcher.update(items: [second])
        let matches = try await searcher.search(intent: "block", limit: 5)

        #expect(matches.first?.block == "second block")
    }

    // MARK: - Shared fixture items

    /// An item whose indexed text shares no term and no trigram with its
    /// block, so a query answered from one text can never be answered from
    /// the other.
    private static let indexedOverrideItem = IndexedTextMetadata(
        id: "deploy", block: "ships containers to production", indexedText: "kubernetes rollout",
    )

    /// An item whose embedded text shares no term and no trigram with its
    /// block, for the same reason.
    private static let embeddedOverrideItem = EmbeddedTextMetadata(
        id: "deploy", block: "ships containers to production", embeddedText: "kubernetes rollout",
    )
}
