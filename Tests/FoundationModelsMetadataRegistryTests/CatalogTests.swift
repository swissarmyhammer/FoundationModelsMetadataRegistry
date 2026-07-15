import Foundation
import Testing

@testable import FoundationModelsMetadataRegistry

/// Tests for the catalog contract (plan.md §4): `SearchableMetadata`,
/// `Match`, `MetadataIndex`, and the shared `MetadataDiagnostic` surface.
struct CatalogTests {
    // MARK: - Fixtures

    /// A minimal conformer implementing only the protocol's required
    /// members (`id`, `renderBlock()`), so `renderSummaryBlock()`'s default
    /// implementation is what's under test.
    struct FixtureMetadata: SearchableMetadata {
        let id: String
        let block: String

        func renderBlock() -> String { block }
    }

    /// A conformer that overrides `renderSummaryBlock()` with something
    /// shorter than its full block, proving the default is overridable.
    struct OverridingFixtureMetadata: SearchableMetadata {
        let id: String
        let block: String
        let summary: String

        func renderBlock() -> String { block }
        func renderSummaryBlock() -> String { summary }
    }

    /// A thread-safe call counter used to prove `MetadataIndex` renders a
    /// block exactly once at build time and reuses it thereafter, rather
    /// than re-deriving it on every lookup.
    final class CallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func increment() {
            lock.lock()
            defer { lock.unlock() }
            value += 1
        }
    }

    /// A conformer whose `renderBlock()` increments a shared `CallCounter`
    /// every time it's invoked.
    struct CountingMetadata: SearchableMetadata {
        let id: String
        let block: String
        let counter: CallCounter

        func renderBlock() -> String {
            counter.increment()
            return block
        }
    }

    // MARK: - SearchableMetadata

    @Test
    func renderSummaryBlockDefaultsToRenderBlock() {
        let item = FixtureMetadata(id: "deploy", block: "ships containers to production")
        #expect(item.renderSummaryBlock() == item.renderBlock())
    }

    @Test
    func renderSummaryBlockIsOverridable() {
        let item = OverridingFixtureMetadata(id: "deploy", block: "a very long full description", summary: "short summary")
        #expect(item.renderSummaryBlock() == "short summary")
        #expect(item.renderBlock() == "a very long full description")
    }

    // MARK: - MetadataIndex: tokenized two-field index

    @Test
    func indexWeightsIdFieldFiveTimesBlockField() throws {
        let item = FixtureMetadata(id: "deploy", block: "ships containers to production")
        let index = MetadataIndex(items: [item])

        let weightedTermFrequency = try #require(index.rankedDocument(forID: "deploy")).weightedTermFrequency
        #expect(weightedTermFrequency["deploy"] == BM25.primaryFieldWeight)
        #expect(weightedTermFrequency["ships"] == BM25.bodyFieldWeight)
        #expect(weightedTermFrequency["production"] == BM25.bodyFieldWeight)
    }

    @Test
    func indexSumsWeightsForATokenSharedByIdAndBlockFields() throws {
        // "deploy" appears in both the id field and the block field, so its
        // weighted term frequency must be the *sum* of both field weights,
        // not just one or the other.
        let item = FixtureMetadata(id: "deploy", block: "deploy ships containers to production")
        let index = MetadataIndex(items: [item])

        let weightedTermFrequency = try #require(index.rankedDocument(forID: "deploy")).weightedTermFrequency
        #expect(weightedTermFrequency["deploy"] == BM25.primaryFieldWeight + BM25.bodyFieldWeight)
    }

    @Test
    func indexDocumentLengthIsSumOfIdAndBlockTokenCounts() {
        let item = FixtureMetadata(id: "deploy-k8s", block: "ships containers to production")
        let index = MetadataIndex(items: [item])

        let idTokenCount = Tokenizer.tokenize(text: item.id).count
        let blockTokenCount = Tokenizer.tokenize(text: item.block).count
        #expect(index.rankedDocument(forID: "deploy-k8s")?.documentLength == idTokenCount + blockTokenCount)
    }

    @Test
    func indexBuildsPerEntryTrigramSetsForIdAndBlockFields() {
        let item = FixtureMetadata(id: "deploy-k8s", block: "ships containers to production")
        let index = MetadataIndex(items: [item])

        #expect(
            index.rankedDocument(forID: "deploy-k8s")?.primaryTrigramSet
                == Trigram.canonicalTrigramSet(text: "deploy-k8s")
        )
        #expect(
            index.rankedDocument(forID: "deploy-k8s")?.bodyTrigramSet
                == Trigram.canonicalTrigramSet(text: "ships containers to production")
        )
    }

    @Test
    func indexBuildsFromFixtureCatalog() {
        let items = [
            FixtureMetadata(id: "deploy", block: "ships containers to a kubernetes cluster"),
            FixtureMetadata(id: "rollback", block: "reverts the last release"),
            FixtureMetadata(id: "status", block: "reports current release health"),
        ]
        let index = MetadataIndex(items: items)

        #expect(index.count == 3)
        #expect(index.ids == ["deploy", "rollback", "status"])
        for item in items {
            #expect(index.item(forID: item.id)?.id == item.id)
            #expect(index.block(forID: item.id) == item.block)
        }
    }

    @Test
    func indexLookupOfMissingIdReturnsNil() {
        let index = MetadataIndex(items: [FixtureMetadata(id: "deploy", block: "ships containers")])
        #expect(index.item(forID: "missing") == nil)
        #expect(index.block(forID: "missing") == nil)
        #expect(index.rankedDocument(forID: "missing") == nil)
    }

    // MARK: - Match.block is verbatim, never re-derived

    @Test
    func indexRendersBlockOnceAtBuildAndReusesItOnEveryLookup() {
        let counter = CallCounter()
        let item = CountingMetadata(id: "deploy", block: "ships containers", counter: counter)
        let index = MetadataIndex(items: [item])

        #expect(index.block(forID: "deploy") == "ships containers")
        #expect(index.block(forID: "deploy") == "ships containers")
        #expect(index.item(forID: "deploy")?.id == "deploy")
        #expect(counter.count == 1)
    }

    // MARK: - Duplicate id policy: first wins, dropped, diagnostic emitted

    @Test
    func duplicateIdFirstItemWinsDuplicateDropped() {
        let first = FixtureMetadata(id: "deploy", block: "first block")
        let duplicate = FixtureMetadata(id: "deploy", block: "second block")
        let index = MetadataIndex(items: [first, duplicate])

        #expect(index.count == 1)
        #expect(index.ids == ["deploy"])
        #expect(index.block(forID: "deploy") == "first block")
    }

    @Test
    func duplicateIdEmitsDiagnosticThroughOnDiagnostic() {
        let recorder = DiagnosticRecorder()
        let first = FixtureMetadata(id: "deploy", block: "first block")
        let duplicate = FixtureMetadata(id: "deploy", block: "second block")
        _ = MetadataIndex(items: [first, duplicate], onDiagnostic: { recorder.record($0) })

        #expect(recorder.diagnostics == [.duplicateId(id: "deploy")])
    }

    @Test
    func noDiagnosticEmittedWhenNoDuplicates() {
        let recorder = DiagnosticRecorder()
        _ = MetadataIndex(
            items: [FixtureMetadata(id: "deploy", block: "ships containers")],
            onDiagnostic: { recorder.record($0) }
        )

        #expect(recorder.diagnostics.isEmpty)
    }

    @Test
    func threeWayDuplicateIdEmitsOneDiagnosticPerDroppedDuplicate() {
        let recorder = DiagnosticRecorder()
        let items = [
            FixtureMetadata(id: "deploy", block: "first block"),
            FixtureMetadata(id: "deploy", block: "second block"),
            FixtureMetadata(id: "deploy", block: "third block"),
        ]
        let index = MetadataIndex(items: items, onDiagnostic: { recorder.record($0) })

        #expect(index.count == 1)
        #expect(index.block(forID: "deploy") == "first block")
        #expect(recorder.diagnostics == [.duplicateId(id: "deploy"), .duplicateId(id: "deploy")])
    }

    // MARK: - Empty catalog

    @Test
    func emptyCatalogBuildsAnEmptyIndex() {
        let index = MetadataIndex(items: [FixtureMetadata]())

        #expect(index.count == 0)
        #expect(index.ids.isEmpty)
        #expect(index.item(forID: "anything") == nil)
    }

    // MARK: - Match

    @Test
    func matchCarriesTheIndexsVerbatimBlockByIdentity() throws {
        let item = FixtureMetadata(id: "deploy", block: "ships containers")
        let index = MetadataIndex(items: [item])
        let storedBlock = try #require(index.block(forID: "deploy"))

        let match = Match(id: "deploy", block: storedBlock, score: 1.0, signals: nil, item: item)

        #expect(match.block == storedBlock)
        #expect(match.id == "deploy")
        #expect(match.score == 1.0)
        #expect(match.signals == nil)
        #expect(match.item.id == "deploy")
    }
}
