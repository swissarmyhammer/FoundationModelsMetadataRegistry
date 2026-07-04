import Foundation
import Testing

@testable import CatalogSearchCore
import ExamplesSupport
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
}
