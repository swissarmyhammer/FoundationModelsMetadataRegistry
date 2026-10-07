import Testing

@testable import FoundationModelsMetadataRegistry

/// Tests for the under-budget path of the selection tier (plan.md §6, M3).
///
/// Each search makes one new `LanguageModelSession` on the model of the
/// `SelectionConfig`. The assembled prefix is the instructions of that
/// session, and nothing stays from one search to the next. The tests check
/// these items:
///
/// - `renderSummaryBlock()` goes into the prefix, and a `Match` carries
///   `renderBlock()` verbatim.
/// - The tier decodes ids only and finds each block by its id.
/// - The tier removes an unknown id and reports a diagnostic.
///
/// Each test uses a `ScriptedLanguageModel` (`TestSupport`), so no test
/// loads a real model and no test uses a GPU. `OverBudgetTests` covers the
/// over-budget path and the resolution of `.auto`.
struct SelectionTests {
  // MARK: - Fixtures

  /// A catalog item with an optional summary that is not its block.
  struct FixtureItem: SearchableMetadata {
    /// The id of the item.
    let id: String

    /// The full block of the item. A `Match` carries this text.
    let block: String

    /// The summary of the item, or `nil` to use `block` as the summary.
    let summary: String?

    /// Makes an item.
    ///
    /// - Parameters:
    ///   - id: the id of the item.
    ///   - block: the full block of the item.
    ///   - summary: the summary of the item. Defaults to `nil`.
    init(id: String, block: String, summary: String? = nil) {
      self.id = id
      self.block = block
      self.summary = summary
    }

    /// Gives the full block, verbatim.
    ///
    /// - Returns: `block`.
    func renderBlock() -> String {
      block
    }

    /// Gives the summary, or the block when the item has no summary.
    ///
    /// - Returns: `summary`, or `block` when `summary` is `nil`.
    func renderSummaryBlock() -> String {
      summary ?? block
    }
  }

  /// The catalog of most tests in this suite.
  static let catalog: [FixtureItem] = [
    FixtureItem(id: "deploy", block: "ships containers to a kubernetes cluster"),
    FixtureItem(id: "rollback", block: "reverts the last release"),
  ]

  // MARK: - One new session for each search

  @Test
  func eachSearchMakesOneNewPromptWithTheWholePrefixAsInstructions() async throws {
    let model = ScriptedLanguageModel([#"{"ids":["deploy"]}"#, #"{"ids":["rollback"]}"#])
    let config = SelectionConfig(model: model)
    let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

    let first = try await searcher.search(intent: "first task", limit: 5)
    let second = try await searcher.search(intent: "second task", limit: 5)

    #expect(first.map(\.id) == ["deploy"])
    #expect(second.map(\.id) == ["rollback"])
    // Each search makes one prompt. Nothing is kept between two searches,
    // so each prompt gets the whole prefix again as its instructions.
    let expectedPrefix = SelectionTier.assemblePrefix(
      preamble: config.preamble, catalog: MetadataIndex(items: Self.catalog))
    #expect(model.calls.map(\.instructions) == [expectedPrefix, expectedPrefix])
  }

  // MARK: - Summary vs full block separation

  @Test
  func sessionPrefixUsesSummaryBlockWhileMatchesCarryTheFullRenderedBlock() async throws {
    let item = FixtureItem(
      id: "deploy", block: "the full, long rendered block text", summary: "short summary")
    let model = ScriptedLanguageModel([#"{"ids":["deploy"]}"#])
    let config = SelectionConfig(model: model)
    let searcher = MetadataSearcher(items: [item], mode: .selection, selection: config)

    let matches = try await searcher.search(intent: "task", limit: 5)

    let call = try #require(model.calls.first)
    let instructions = try #require(call.instructions)
    #expect(instructions.contains("id: deploy\ndescription: short summary"))
    #expect(!instructions.contains("the full, long rendered block text"))

    let match = try #require(matches.first)
    #expect(match.block == "the full, long rendered block text")
    // No retrieval signal enters a selection: the tier makes one prompt
    // that picks, and a pick's score is the reciprocal of its rank in
    // the answer -- 1/1 for the only pick here -- with no per-signal
    // breakdown to carry.
    #expect(match.score == 1.0)
    #expect(match.signals == nil)
  }

  // MARK: - Ids-only decode + verbatim lookup identity

  @Test
  func selectionDecodesIdsOnlyAndMatchesCarryVerbatimCatalogBlocks() async throws {
    let model = ScriptedLanguageModel([#"{"ids":["rollback","deploy"]}"#])
    let config = SelectionConfig(model: model)
    let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

    let matches = try await searcher.search(intent: "roll back the last deploy", limit: 5)

    #expect(matches.map(\.id) == ["rollback", "deploy"])
    #expect(
      matches.map(\.block) == [
        "reverts the last release", "ships containers to a kubernetes cluster",
      ])
    // Same order-score rule as
    // `sessionPrefixUsesSummaryBlockWhileMatchesCarryTheFullRenderedBlock`:
    // the reciprocal of each pick's rank in the answer, and no signals.
    #expect(matches.map(\.score) == [1.0, 1.0 / 2.0])
    #expect(matches.allSatisfy { $0.signals == nil })
  }

  @Test
  func selectionResultsAreTruncatedToLimit() async throws {
    let model = ScriptedLanguageModel([#"{"ids":["rollback","deploy"]}"#])
    let config = SelectionConfig(model: model)
    let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

    let matches = try await searcher.search(intent: "roll back the last deploy", limit: 1)

    #expect(matches.map(\.id) == ["rollback"])
  }

  // MARK: - Duplicate id handling: first occurrence wins, no diagnostic

  @Test
  func duplicateIdFromAMisbehavingFakeIsDeduplicatedWithoutADiagnostic() async throws {
    let recorder = DiagnosticRecorder()
    let model = ScriptedLanguageModel([#"{"ids":["deploy","deploy","rollback"]}"#])
    let config = SelectionConfig(model: model)
    let searcher = MetadataSearcher(
      items: Self.catalog,
      mode: .selection,
      selection: config,
      onDiagnostic: { recorder.record($0) },
    )

    let matches = try await searcher.search(intent: "task", limit: 5)

    #expect(matches.map(\.id) == ["deploy", "rollback"])
    #expect(recorder.diagnostics.isEmpty)
  }

  @Test
  func duplicateIdDoesNotConsumeALimitSlotAndCrowdOutALaterLegitimateMatch() async throws {
    // A tight `limit` of 2 against 3 model-returned ids (one a repeat):
    // if the duplicate consumed a slot the way an unfiltered append
    // would, this would truncate to just ["deploy"]. Deduplication must
    // let "rollback" through instead.
    let model = ScriptedLanguageModel([#"{"ids":["deploy","deploy","rollback"]}"#])
    let config = SelectionConfig(model: model)
    let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

    let matches = try await searcher.search(intent: "task", limit: 2)

    #expect(matches.map(\.id) == ["deploy", "rollback"])
  }

  // MARK: - Zero-ids model response ("nothing fits")

  @Test
  func emptyIdsModelResponseReturnsEmptyMatchesWithNoDiagnostic() async throws {
    let recorder = DiagnosticRecorder()
    let model = ScriptedLanguageModel([#"{"ids":[]}"#])
    let config = SelectionConfig(model: model)
    let searcher = MetadataSearcher(
      items: Self.catalog,
      mode: .selection,
      selection: config,
      onDiagnostic: { recorder.record($0) },
    )

    let matches = try await searcher.search(intent: "nothing matches this", limit: 5)

    #expect(matches.isEmpty)
    #expect(recorder.diagnostics.isEmpty)
  }

  // MARK: - Empty catalog

  @Test
  func emptyCatalogSearchReturnsNoMatchesWithoutAPrompt() async throws {
    let model = ScriptedLanguageModel([String]())
    let config = SelectionConfig(model: model)
    let searcher = MetadataSearcher(items: [FixtureItem](), mode: .selection, selection: config)

    let matches = try await searcher.search(intent: "anything", limit: 5)

    #expect(matches.isEmpty)
    #expect(model.calls.isEmpty)
  }

  // MARK: - Unknown id filtering + diagnostic

  @Test
  func unknownIdFromAMisbehavingFakeIsFilteredAndReportedAsADiagnostic() async throws {
    let recorder = DiagnosticRecorder()
    let model = ScriptedLanguageModel([#"{"ids":["deploy","not-a-real-id"]}"#])
    let config = SelectionConfig(model: model)
    let searcher = MetadataSearcher(
      items: Self.catalog,
      mode: .selection,
      selection: config,
      onDiagnostic: { recorder.record($0) },
    )

    let matches = try await searcher.search(intent: "task", limit: 5)

    #expect(matches.map(\.id) == ["deploy"])
    #expect(recorder.diagnostics == [.unknownSelectedId(id: "not-a-real-id")])
  }

  // MARK: - Without a selection config, .selection still throws (unchanged)

  @Test
  func selectionModeWithNoConfigStillThrowsSelectionTierUnavailable() async throws {
    let searcher = MetadataSearcher(items: Self.catalog, mode: .selection)
    await #expect(throws: SelectionTierUnavailable.self) {
      _ = try await searcher.search(intent: "task", limit: 5)
    }
  }
}
