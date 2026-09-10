@testable import BigCatalogCore
import Foundation
@testable import FoundationModelsMetadataRegistry
import Testing

/// `.auto` mode's real resolution, and `BigCatalog`'s over-budget demo
/// (plan.md §6, §13 M8). Split out of `OverBudgetTests` to keep each file
/// within the project's line-length conventions; shares its `catalog`
/// fixture via `OverBudgetTests`.
extension OverBudgetTests {
    // MARK: - `.auto` resolution both ways

    @Test
    func autoModeResolvesToSelectionWhenASessionFactoryIsConfigured() async throws {
        // Scripted to return "echo" -- something plain retrieval for the
        // "alpha" intent would never surface, proving `.auto` actually took
        // the selection path rather than silently falling back.
        let factory = RecordingSessionFactory(responses: [#"{"ids":["echo"]}"#])
        let config = SelectionConfig(model: factory.makeSession)
        let searcher = MetadataSearcher(items: Self.catalog, mode: .auto, selection: config)

        let matches = try await searcher.search(intent: "alpha", limit: 5)

        #expect(matches.map(\.id) == ["echo"])
    }

    @Test
    func autoModeFallsBackToRetrievalWhenNoSessionFactoryIsConfigured() async throws {
        let retrieval = MetadataSearcher(items: Self.catalog, mode: .retrieval)
        let auto = MetadataSearcher(items: Self.catalog, mode: .auto)

        let retrievalMatches = try await retrieval.search(intent: "alpha", limit: 5)
        let autoMatches = try await auto.search(intent: "alpha", limit: 5)

        #expect(autoMatches.map(\.id) == retrievalMatches.map(\.id))
        #expect(!autoMatches.isEmpty)
    }

    // MARK: - `BigCatalog`'s over-budget demo (plan.md §13 M8)

    /// The catalog size
    /// `bigCatalogDemoOverBudgetSelectionFindsTheNeedleWithoutCuttingCandidates()`
    /// drives the demo with: enough entries that their assembled summary
    /// blocks comfortably exceed the demo's own tiny capacity limit, so the
    /// over-budget path really runs. Far smaller than the demo's own ~10^3
    /// default, which `ExamplesSmokeTests` already indexes and times -- this
    /// test measures which ids come back, not the throughput, and a second
    /// ~10^3-entry index running beside that timed test would only slow it
    /// down.
    static let bigCatalogDemoEntryCount = 40

    @Test
    func bigCatalogDemoOverBudgetSelectionFindsTheNeedleWithoutCuttingCandidates() async throws {
        let recorder = DiagnosticRecorder()
        let catalog = BigCatalogCore.makeBigCatalog(count: Self.bigCatalogDemoEntryCount)

        let matches = try await BigCatalogCore.runBigCatalogOverBudgetSelection(
            catalog: catalog,
            query: BigCatalogCore.bigCatalogNeedleQuery,
            onDiagnostic: { recorder.record($0) }
        )

        // The demo's deliberately tiny capacity limit puts this catalog over
        // budget, so the tier splits it into runs and prompts every one of
        // them. The scripted session names the needle in each run, and the
        // tier keeps the first occurrence.
        #expect(matches.map(\.id) == [BigCatalogCore.bigCatalogNeedleId])
        #expect(
            !recorder.diagnostics.contains {
                if case .retrievalCut = $0 {
                    return true
                }
                return false
            }
        )
    }
}
