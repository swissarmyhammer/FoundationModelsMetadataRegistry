import Foundation
import Testing

@testable import BigCatalogCore
@testable import CatalogSearchCore
import ExamplesSupport
@testable import HotReloadCore
@testable import SemanticSearchCore

/// Smoke tests for the `Examples/` executable targets (plan.md §13):
/// `CatalogSearch` and `SemanticSearch` each factor their entry logic into a
/// callable function, living in a plain library target (`CatalogSearchCore`,
/// `SemanticSearchCore`) their thin `main.swift` calls into. These tests
/// import those library targets directly and assert on real output -- no
/// `swift run` subprocess spawning -- covering every GPU-free path.
/// `SemanticSearchCore`'s default (real-embedder) path resolves a live
/// Router over the network/GPU and is exercised only by `swift run
/// SemanticSearch` locally, never here.
@Suite("Examples smoke tests")
struct ExamplesSmokeTests {
    // MARK: - CatalogSearch (M1, keyword-only, GPU-free)

    @Test("CatalogSearch ranks the literal keyword match first, with real per-signal scores")
    func catalogSearchRanksLiteralKeywordMatchFirst() async throws {
        let matches = try await CatalogSearchCore.runCatalogSearch(query: "commit changes to git")

        let first = try #require(matches.first)
        #expect(first.id == "commit")
        let signals = try #require(first.signals)
        #expect(signals.bm25 > 0.0)
        // No embedder is configured in this example -- cosine never ranks
        // anything (plan.md §5 absent-signal rule).
        #expect(signals.cosine == 0.0)
    }

    @Test("CatalogSearch's formatter renders rank, id, score, and every signal")
    func catalogSearchFormatsMatches() async throws {
        let matches = try await CatalogSearchCore.runCatalogSearch(query: "commit changes to git")
        let formatted = ExamplesSupport.formattedMatches(matches: matches)

        #expect(formatted.contains("1. commit"))
        #expect(formatted.contains("bm25="))
        #expect(formatted.contains("trigram="))
        #expect(formatted.contains("cosine="))
    }

    // MARK: - SemanticSearch --no-embedder (M2 degradation, GPU-free)

    @Test("SemanticSearch --no-embedder degrades to keyword-only and reports embeddingUnavailable")
    func semanticSearchNoEmbedderReportsDegradation() async throws {
        let recorder = DiagnosticRecorder()
        let matches = try await SemanticSearchCore.runSemanticSearch(
            query: SemanticSearchCore.query,
            embedder: nil,
            onDiagnostic: { recorder.record($0) }
        )

        #expect(recorder.diagnostics.contains(.embeddingUnavailable))
        // "save my work" shares no keyword or character trigram with
        // `commit`'s rendered block -- without an embedder, keyword-only
        // retrieval must never surface it. This is exactly the degradation
        // `--no-embedder` demonstrates (mirrors `EmbeddingTests`'s
        // `cosineSignalRanksASemanticMatchAboveWhatKeywordSignalsAloneFind`).
        #expect(!matches.contains { $0.id == "commit" })
        // The degradation this example demonstrates is "keyword-only ranks
        // the wrong thing," not "keyword-only finds nothing at all" --
        // `status`'s block shares the "work" trigrams with the query (via
        // "working"), so keyword-only retrieval still returns a real
        // (semantically wrong) ranking.
        #expect(!matches.isEmpty)
        #expect(matches.contains { $0.id == "status" })
    }

    @Test("SemanticSearch --no-embedder's formatter still renders every signal")
    func semanticSearchNoEmbedderFormatsMatches() async throws {
        let matches = try await SemanticSearchCore.runSemanticSearch(
            query: SemanticSearchCore.query,
            embedder: nil,
            onDiagnostic: { _ in }
        )
        let formatted = ExamplesSupport.formattedMatches(matches: matches)

        #expect(!matches.isEmpty)
        #expect(formatted.contains("bm25="))
        #expect(formatted.contains("trigram="))
        #expect(formatted.contains("cosine="))
    }

    // MARK: - BigCatalog (M8, retrieval timing over a ~10^3-entry catalog, GPU-free)

    @Test("BigCatalog's retrieval-timing path finds the deterministic needle across a ~10^3-entry synthetic catalog")
    func bigCatalogRetrievalFindsTheNeedleAndReportsTiming() async throws {
        let result = try await BigCatalogCore.runBigCatalogRetrieval(query: BigCatalogCore.bigCatalogNeedleQuery)

        #expect(result.catalogCount == 1_000)
        let first = try #require(result.matches.first)
        #expect(first.id == BigCatalogCore.bigCatalogNeedleId)
        // A real timing, not a placeholder -- never negative, and this
        // "in-memory retrieval" story runs GPU-free (no session, no
        // network), so it settles in well under a second even over a
        // ~10^3-entry catalog.
        #expect(result.elapsed >= 0)
        #expect(result.elapsed < 5.0)
    }

    @Test("BigCatalog's formatter still renders every signal over the ~10^3-entry catalog")
    func bigCatalogFormatsMatches() async throws {
        let result = try await BigCatalogCore.runBigCatalogRetrieval(query: BigCatalogCore.bigCatalogNeedleQuery)
        let formatted = ExamplesSupport.formattedMatches(matches: result.matches)

        #expect(formatted.contains("bm25="))
        #expect(formatted.contains("trigram="))
        #expect(formatted.contains("cosine="))
    }

    // MARK: - HotReload (M8, update(items:) burst + index rebuild, GPU-free)

    @Test("HotReload's burst stays keyword-searchable immediately and embeds only net-new items each step")
    func hotReloadBurstStaysSearchableAndEmbedsOnlyNetNewItemsEachStep() async throws {
        let steps = try await HotReloadCore.runHotReloadBurst()

        #expect(steps.count == 4)

        // Step 1: toolA alone -- brand new, so it must catch up its embedding.
        #expect(steps[0].appliedIds == ["toolA"])
        #expect(steps[0].diagnostics.contains(.embedCatchUp(pending: 1, total: 1)))
        #expect(Set(steps[0].searchResultIds) == Set(["toolA"]))

        // Step 2: toolB joins -- only the net-new item catches up.
        #expect(steps[1].appliedIds == ["toolA", "toolB"])
        #expect(steps[1].diagnostics.contains(.embedCatchUp(pending: 1, total: 2)))
        #expect(Set(steps[1].searchResultIds) == Set(["toolA", "toolB"]))

        // Step 3: a redundant forward of identical content -- a genuine
        // no-op, no diagnostics at all, but still immediately searchable.
        #expect(steps[2].appliedIds == ["toolA", "toolB"])
        #expect(steps[2].diagnostics.isEmpty)
        #expect(Set(steps[2].searchResultIds) == Set(["toolA", "toolB"]))

        // Step 4: an MCP-style remove-and-add -- toolA drops out, toolC is
        // the only net-new item to catch up.
        #expect(steps[3].appliedIds == ["toolB", "toolC"])
        #expect(steps[3].diagnostics.contains(.embedCatchUp(pending: 1, total: 2)))
        #expect(Set(steps[3].searchResultIds) == Set(["toolB", "toolC"]))
    }

    @Test("HotReload's selection tier drops its cached root and rebuilds against the new catalog on a real change")
    func hotReloadSelectionRootRebuildsAfterARealCatalogChange() async throws {
        let result = try await HotReloadCore.runSelectionRootRebuildDemo()

        // The root session is built once for the initial (single-item)
        // catalog, then rebuilt exactly once more after the real catalog
        // change -- never reused as-is, and never rebuilt redundantly.
        #expect(result.initialFactoryCallCount == 1)
        #expect(result.rebuiltFactoryCallCount == 2)
        #expect(result.initialCandidateIds == ["toolA"])
        #expect(result.updatedCandidateIds == ["toolA", "toolB"])
    }
}
