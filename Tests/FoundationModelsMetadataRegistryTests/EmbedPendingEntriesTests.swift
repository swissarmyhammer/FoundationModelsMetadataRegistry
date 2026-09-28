@testable import FoundationModelsMetadataRegistry
import Testing

/// Tests for `MetadataIndex.embedPendingEntries(with:source:onDiagnostic:)` and
/// `MetadataIndex.EmbeddedBatch.merged(into:)` (plan.md §8): the one
/// embed-and-merge step that each catalog embed of this package goes through.
/// Every embedder here is a scripted fake behind the `TextEmbedding` seam.
struct EmbedPendingEntriesTests {
    typealias FixtureItem = EmbeddingTests.FixtureItem

    // MARK: - Fixtures

    /// The catalog that each test embeds. No item carries an embedding when
    /// the index is built.
    static let catalog = [
        FixtureItem(id: "commit", block: "records a snapshot of staged changes"),
        FixtureItem(id: "push", block: "uploads local commits to a remote"),
    ]

    /// The width of every vector in `vectorsByText`.
    static let embeddingDimension = 2

    /// The vector of each catalog block.
    static let vectorsByText: [String: [Float]] = [
        catalog[0].block: [1, 0],
        catalog[1].block: [0, 1],
    ]

    /// The error that the failing embedder throws.
    struct EmbedFailure: Error {}

    /// A counting `FakeEmbedder` that maps each block in `catalog`.
    static func countingEmbedder() -> FakeEmbedder {
        FakeEmbedder(dimension: embeddingDimension, vectorsByText: vectorsByText)
    }

    // MARK: - Embed

    @Test
    func embedsThePendingEntriesInOneBatchAndReportsTheCatchUp() async throws {
        let index = MetadataIndex(items: Self.catalog)
        let embedder = Self.countingEmbedder()
        let recorder = DiagnosticRecorder()

        let embedded = await index.embedPendingEntries(with: embedder, source: .reload) { recorder.record($0) }
        let batch = try #require(embedded)
        let merged = batch.merged(into: index)

        #expect(embedder.embeddedBatches == [Self.catalog.map(\.block)])
        #expect(recorder.diagnostics == [.embedCatchUp(pending: Self.catalog.count, total: Self.catalog.count)])
        #expect(merged.pendingEmbeddings().ids.isEmpty)
        for item in Self.catalog {
            #expect(merged.embedding(forID: item.id) == Self.vectorsByText[item.block])
        }
    }

    @Test
    func returnsNilWithNoEmbedderCallAndNoDiagnosticWhenNothingIsPending() async {
        let embedded = await MetadataIndex.build(items: Self.catalog, embedder: Self.countingEmbedder())
        let embedder = Self.countingEmbedder()
        let recorder = DiagnosticRecorder()

        let batch = await embedded.embedPendingEntries(with: embedder, source: .reload) { recorder.record($0) }

        #expect(batch == nil)
        #expect(embedder.embeddedBatches.isEmpty)
        #expect(recorder.diagnostics.isEmpty)
    }

    @Test
    func returnsNilAfterTheCatchUpReportWhenTheEmbedFails() async {
        let index = MetadataIndex(items: Self.catalog)
        let embedder = FakeEmbedder(dimension: Self.embeddingDimension, failure: EmbedFailure())
        let recorder = DiagnosticRecorder()

        let batch = await index.embedPendingEntries(with: embedder, source: .reload) { recorder.record($0) }

        #expect(batch == nil)
        #expect(embedder.embeddedBatches == [Self.catalog.map(\.block)])
        #expect(recorder.diagnostics == [.embedCatchUp(pending: Self.catalog.count, total: Self.catalog.count)])
    }

    // MARK: - Merge

    @Test
    func mergeSkipsAnEntryWhoseEmbeddedTextChangedAfterTheEmbed() async throws {
        let index = MetadataIndex(items: Self.catalog)
        let batch = try #require(await index.embedPendingEntries(with: Self.countingEmbedder(), source: .reload))
        let changed = FixtureItem(id: Self.catalog[0].id, block: "a new text for the same id")
        let live = MetadataIndex(items: [changed, Self.catalog[1]])

        let merged = batch.merged(into: live)

        // The vector of the old text must not land on the new text.
        #expect(merged.embedding(forID: changed.id) == nil)
        #expect(merged.embedding(forID: Self.catalog[1].id) == Self.vectorsByText[Self.catalog[1].block])
    }
}
