import Foundation
import Testing

@testable import FoundationModelsMetadataRegistry

/// `.auto` mode's real resolution (plan.md §6). Split out of
/// `OverBudgetTests` to keep each file within the project's line-length
/// conventions; shares its `catalog` fixture via `OverBudgetTests`.
extension OverBudgetTests {
  // MARK: - `.auto` resolution both ways

  @Test
  func autoModeResolvesToSelectionWhenASelectionModelIsConfigured() async throws {
    // Scripted to return "echo" -- something plain retrieval for the
    // "alpha" intent would never surface, proving `.auto` actually took
    // the selection path rather than silently falling back.
    let model = ScriptedLanguageModel([#"{"ids":["echo"]}"#])
    let config = SelectionConfig(model: model)
    let searcher = MetadataSearcher(items: Self.catalog, mode: .auto, selection: config)

    let matches = try await searcher.search(intent: "alpha", limit: 5)

    #expect(matches.map(\.id) == ["echo"])
    #expect(model.calls.count == 1)
  }

  @Test
  func autoModeFallsBackToRetrievalWhenNoSelectionModelIsConfigured() async throws {
    let retrieval = MetadataSearcher(items: Self.catalog, mode: .retrieval)
    let auto = MetadataSearcher(items: Self.catalog, mode: .auto)

    let retrievalMatches = try await retrieval.search(intent: "alpha", limit: 5)
    let autoMatches = try await auto.search(intent: "alpha", limit: 5)

    #expect(autoMatches.map(\.id) == retrievalMatches.map(\.id))
    #expect(!autoMatches.isEmpty)
  }
}
