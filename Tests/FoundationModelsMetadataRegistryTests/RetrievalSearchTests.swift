import Foundation
import Testing

@testable import FoundationModelsMetadataRegistry

/// Tests for `MetadataSearcher`'s keyword-only `.retrieval` mode (plan.md
/// §3, §5, §7): golden rankings over a fixture catalog, limit handling,
/// empty-query/no-hits behavior, weights configuration, and diagnostic
/// forwarding. No session, no tokens, no embedder are wired up yet — cosine
/// is always absent (plan.md §5 "absent-signal rule").
struct RetrievalSearchTests {
    // MARK: - Fixtures

    struct FixtureItem: SearchableMetadata {
        let id: String
        let block: String

        func renderBlock() -> String { block }
    }

    /// A ~20-item ops-command catalog. None of the blocks below repeat their
    /// own id verbatim, so an id-only match (e.g. "deploy") can only be
    /// found through `MetadataIndex`'s ×5 id-field weighting, never by
    /// coincidence with the block text.
    static let catalog: [FixtureItem] = [
        FixtureItem(id: "deploy", block: "ships containers to a kubernetes cluster"),
        FixtureItem(id: "rollback", block: "reverts the last release"),
        FixtureItem(id: "status", block: "reports current release health"),
        FixtureItem(id: "restart", block: "cycles the running service"),
        FixtureItem(id: "scale", block: "adjusts replica count for a service"),
        FixtureItem(id: "logs", block: "streams recent output from a container"),
        FixtureItem(id: "config", block: "edits application settings"),
        FixtureItem(id: "migrate", block: "applies pending schema changes to storage"),
        FixtureItem(id: "backup", block: "snapshots data to durable storage"),
        FixtureItem(id: "restore", block: "recovers data from a snapshot"),
        FixtureItem(id: "monitor", block: "watches metrics and emits alerts"),
        FixtureItem(id: "alert", block: "notifies on-call about an incident"),
        FixtureItem(id: "provision", block: "creates new infrastructure resources"),
        FixtureItem(id: "teardown", block: "removes infrastructure resources"),
        FixtureItem(id: "healthcheck", block: "probes a service for liveness"),
        FixtureItem(id: "credentials", block: "rotates access keys and passwords"),
        FixtureItem(id: "secrets", block: "manages encrypted configuration values"),
        FixtureItem(id: "network", block: "configures virtual network topology"),
        FixtureItem(id: "firewall", block: "controls inbound and outbound traffic rules"),
        FixtureItem(id: "dns", block: "manages domain name records"),
    ]

    /// A thread-safe recorder for `onDiagnostic` callbacks (mirrors
    /// `CatalogTests.DiagnosticRecorder`).
    final class DiagnosticRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [MetadataDiagnostic] = []

        var diagnostics: [MetadataDiagnostic] {
            lock.lock()
            defer { lock.unlock() }
            return recorded
        }

        func record(_ diagnostic: MetadataDiagnostic) {
            lock.lock()
            defer { lock.unlock() }
            recorded.append(diagnostic)
        }
    }

    // MARK: - Golden ranking: id-field weighting

    @Test
    func deployQueryRanksTheDeployItemFirstViaIdFieldWeightingAlone() async throws {
        let searcher = MetadataSearcher(items: Self.catalog)
        let matches = try await searcher.search(intent: "deploy", limit: 5)

        let first = try #require(matches.first)
        #expect(first.id == "deploy")
        #expect(first.item.id == "deploy")
        #expect(first.block == "ships containers to a kubernetes cluster")
    }

    @Test
    func matchScoreIsNormalizedAndSignalsCarryRawBm25AndTrigramWithCosineAbsent() async throws {
        let searcher = MetadataSearcher(items: Self.catalog)
        let matches = try await searcher.search(intent: "deploy", limit: 5)

        let first = try #require(matches.first)
        #expect(first.score >= 0.0 && first.score <= 1.0)
        let signals = try #require(first.signals)
        #expect(signals.bm25 > 0.0)
        #expect(signals.trigram > 0.0)
        #expect(signals.cosine == 0.0)
    }

    // MARK: - Limit handling

    @Test
    func searchTruncatesResultsToLimit() async throws {
        // "release" appears in both `rollback`'s and `status`'s blocks.
        let searcher = MetadataSearcher(items: Self.catalog)
        let unlimited = try await searcher.search(intent: "release", limit: 5)
        #expect(unlimited.count == 2)

        let limited = try await searcher.search(intent: "release", limit: 1)
        #expect(limited.count == 1)
        #expect(limited.first?.id == unlimited.first?.id)
    }

    @Test
    func searchWithZeroLimitReturnsNoMatches() async throws {
        let searcher = MetadataSearcher(items: Self.catalog)
        let matches = try await searcher.search(intent: "deploy", limit: 0)
        #expect(matches.isEmpty)
    }

    @Test
    func searchWithNegativeLimitReturnsNoMatchesRatherThanCrashing() async throws {
        let searcher = MetadataSearcher(items: Self.catalog)
        let matches = try await searcher.search(intent: "deploy", limit: -1)
        #expect(matches.isEmpty)
    }

    // MARK: - Empty query / no hits

    @Test
    func emptyQueryReturnsNoMatches() async throws {
        let searcher = MetadataSearcher(items: Self.catalog)
        let matches = try await searcher.search(intent: "", limit: 5)
        #expect(matches.isEmpty)
    }

    @Test
    func queryWithNoLexicalOrFuzzyOverlapReturnsNoMatches() async throws {
        let searcher = MetadataSearcher(items: Self.catalog)
        let matches = try await searcher.search(intent: "qxjklmzvbwq", limit: 5)
        #expect(matches.isEmpty)
    }

    @Test
    func emptyCatalogReturnsNoMatches() async throws {
        let searcher = MetadataSearcher(items: [FixtureItem]())
        let matches = try await searcher.search(intent: "deploy", limit: 5)
        #expect(matches.isEmpty)
    }

    // MARK: - Weights configuration

    @Test
    func zeroWeightedTrigramSignalIsExcludedFromFusion() async throws {
        // "kubernetess" (typo, extra "s") has no exact BM25 token match
        // anywhere in the catalog, but fuzzily trigram-matches `deploy`'s
        // block text ("... kubernetes cluster"). With default weights it
        // should surface `deploy`; with trigram damped to zero, `deploy`
        // must not appear at all -- the absent-signal rule pushed to the
        // weight-zero case.
        let withTrigram = MetadataSearcher(items: Self.catalog)
        let matchesWithTrigram = try await withTrigram.search(intent: "kubernetess", limit: 5)
        #expect(matchesWithTrigram.contains { $0.id == "deploy" })

        let withoutTrigram = MetadataSearcher(items: Self.catalog, weights: .init(trigram: 0.0))
        let matchesWithoutTrigram = try await withoutTrigram.search(intent: "kubernetess", limit: 5)
        #expect(matchesWithoutTrigram.isEmpty)
    }

    @Test
    func normalizationCeilingIgnoresAZeroWeightSignal() async throws {
        // With trigram damped to zero, `deploy` ranking rank-0 on BM25 alone
        // must normalize to exactly 1.0 -- not divided by a ceiling that
        // still counts trigram's unreachable share.
        let searcher = MetadataSearcher(items: Self.catalog, weights: .init(trigram: 0.0))
        let matches = try await searcher.search(intent: "deploy", limit: 1)

        let first = try #require(matches.first)
        #expect(abs(first.score - 1.0) < 1e-9)
        // The raw trigram signal is still reported for explainability even
        // though a zero weight excludes it from fusion -- it's the fusion
        // and normalization ceiling that ignore it, not `Signals` itself.
        #expect(first.signals?.trigram ?? 0.0 > 0.0)
    }

    // MARK: - Diagnostic forwarding

    @Test
    func searcherForwardsIndexBuildDiagnosticsThroughOnDiagnostic() async throws {
        let recorder = DiagnosticRecorder()
        let duplicated = Self.catalog + [FixtureItem(id: "deploy", block: "a different deploy block")]
        _ = MetadataSearcher(items: duplicated, onDiagnostic: { recorder.record($0) })

        #expect(recorder.diagnostics == [.duplicateId(id: "deploy")])
    }

    @Test
    func noDiagnosticEmittedWhenCatalogHasNoDuplicates() async throws {
        let recorder = DiagnosticRecorder()
        _ = MetadataSearcher(items: Self.catalog, onDiagnostic: { recorder.record($0) })

        #expect(recorder.diagnostics.isEmpty)
    }

    // MARK: - .selection / .auto stubs

    @Test
    func selectionModeThrowsSelectionTierUnavailable() async throws {
        let searcher = MetadataSearcher(items: Self.catalog, mode: .selection)
        await #expect(throws: SelectionTierUnavailable.self) {
            _ = try await searcher.search(intent: "deploy", limit: 5)
        }
    }

    @Test
    func autoModeFallsBackToRetrievalResults() async throws {
        let retrieval = MetadataSearcher(items: Self.catalog, mode: .retrieval)
        let auto = MetadataSearcher(items: Self.catalog, mode: .auto)

        let retrievalMatches = try await retrieval.search(intent: "deploy", limit: 5)
        let autoMatches = try await auto.search(intent: "deploy", limit: 5)

        #expect(autoMatches.map(\.id) == retrievalMatches.map(\.id))
        #expect(autoMatches.map(\.score) == retrievalMatches.map(\.score))
    }

    // MARK: - Tie-break: first-seen catalog order

    /// Two items engineered so BM25 and trigram rank them in *opposite*
    /// order (one is BM25-rank-0/trigram-rank-1, the other the reverse).
    /// Under equal default weights, `RRF.fuse` sums `1/60 + 1/61` for both
    /// -- an exact tie (mirrors `RRFTests.fusionMatchesHandComputedAtDefaultK`)
    /// -- so the only thing that can order them is `retrievalSearch`'s
    /// tie-break. Repeating "twinword" in `crossoverOne`'s block boosts its
    /// weighted BM25 term frequency (a `Set`-backed trigram set is
    /// unaffected by repetition) past `crossoverTwo`'s id-field match,
    /// while `crossoverTwo`'s id *is* "twinword" verbatim, giving it the
    /// stronger trigram match.
    private static let crossoverOne = FixtureItem(
        id: "twin-one",
        block: Array(repeating: "twinword", count: 20).joined(separator: " ") + " filler"
    )
    private static let crossoverTwo = FixtureItem(id: "twinword", block: "distinct filler text only")

    @Test
    func tieBreakFavorsFirstSeenCatalogOrder() async throws {
        let firstOrder = MetadataSearcher(items: [Self.crossoverOne, Self.crossoverTwo])
        let firstMatches = try await firstOrder.search(intent: "twinword", limit: 2)

        #expect(firstMatches.map(\.id) == ["twin-one", "twinword"])
        let firstScores = try #require(firstMatches.count == 2 ? (firstMatches[0].score, firstMatches[1].score) : nil)
        #expect(abs(firstScores.0 - firstScores.1) < 1e-9)

        // Reversing catalog order with everything else unchanged must flip
        // the winner -- proving the tie-break follows first-seen catalog
        // order rather than, say, id string ordering (which would pick
        // "twin-one" either way) or some fixed/accidental array position.
        let secondOrder = MetadataSearcher(items: [Self.crossoverTwo, Self.crossoverOne])
        let secondMatches = try await secondOrder.search(intent: "twinword", limit: 2)

        #expect(secondMatches.map(\.id) == ["twinword", "twin-one"])
        let secondScores = try #require(secondMatches.count == 2 ? (secondMatches[0].score, secondMatches[1].score) : nil)
        #expect(abs(secondScores.0 - secondScores.1) < 1e-9)
    }

    @Test
    func defaultModeIsAuto() async throws {
        let defaulted = MetadataSearcher(items: Self.catalog)
        let auto = MetadataSearcher(items: Self.catalog, mode: .auto)

        let defaultedMatches = try await defaulted.search(intent: "deploy", limit: 5)
        let autoMatches = try await auto.search(intent: "deploy", limit: 5)

        #expect(defaultedMatches.map(\.id) == autoMatches.map(\.id))
    }
}
