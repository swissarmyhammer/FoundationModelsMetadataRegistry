import Foundation
import Testing

@testable import FoundationModelsMetadataRegistry

/// Tests for the over-budget path of the selection tier (plan.md §6), for the
/// budget boundary, and for the text that each prompt sends.
///
/// The assembled prefix is the preamble, then one `<candidate>` block for
/// each catalog id. Each block holds the id on an `id:` line and the
/// `renderSummaryBlock()` of the item on a `description:` line. Each prompt
/// goes to a new `LanguageModelSession`. The prefix is the instructions of
/// that session, and the prompt is the `<request>` block and the exact-ids
/// line only.
///
/// When the whole prefix is at or under `capacityCharacterLimit`, each search
/// makes one prompt over all ids. When the prefix is longer, the tier divides
/// the catalog ids, in catalog order, into runs whose prefix each fits the
/// budget, and each run gets one prompt. Every id gets to exactly one
/// prompt, the tier cuts nothing, and no `MetadataDiagnostic.retrievalCut`
/// is reported. Nothing is kept from one search to the next.
///
/// Each test uses a `ScriptedLanguageModel` (`TestSupport`) and reads the
/// prompts from its `calls`: no GPU and no real model.
struct OverBudgetTests {
  // MARK: - Fixtures

  /// A catalog item whose summary is not its block.
  struct FixtureItem: SearchableMetadata {
    /// The id of the item.
    let id: String

    /// The full block of the item. A `Match` carries this text.
    let block: String

    /// The summary of the item. The prefix shows this text.
    let summary: String

    /// Gives the full block, verbatim.
    ///
    /// - Returns: `block`.
    func renderBlock() -> String {
      block
    }

    /// Gives the summary.
    ///
    /// - Returns: `summary`.
    func renderSummaryBlock() -> String {
      summary
    }
  }

  /// Five items whose ids are different enough that the `id:` line of one
  /// run's prefix can never be confused with the `id:` line of another id.
  static let catalog: [FixtureItem] = [
    FixtureItem(id: "alpha", block: "alpha handles alpha tasks", summary: "SUMMARY_alpha"),
    FixtureItem(id: "bravo", block: "second unrelated block text", summary: "SUMMARY_bravo"),
    FixtureItem(id: "charlie", block: "third unrelated block text", summary: "SUMMARY_charlie"),
    FixtureItem(id: "delta", block: "fourth unrelated block text", summary: "SUMMARY_delta"),
    FixtureItem(id: "echo", block: "fifth unrelated block text", summary: "SUMMARY_echo"),
  ]

  /// The ids of `catalog`, in catalog order.
  static let catalogIDs = catalog.map(\.id)

  /// A `capacityCharacterLimit` of `1` is smaller than the assembled
  /// preamble alone, so every catalog is over budget and no run can hold
  /// more than the one entry the tier cannot split — one prompt per
  /// catalog id, in catalog order.
  static let forcedOverBudgetLimit = 1

  /// The intent of each search in this suite.
  static let intent = "alpha"

  /// The `limit` of each search in this suite: more than the catalog holds.
  static let searchLimit = 5

  /// The number of searches in a test that compares two searches.
  static let searchCountOfTwo = 2

  /// Makes a model that gives `answer` to each prompt of `searches`
  /// searches, when each search makes at most one prompt for each catalog
  /// id.
  ///
  /// - Parameters:
  ///   - answer: the `Selection` JSON that each prompt answers.
  ///   - searches: the number of searches the model answers. Defaults to
  ///     one search.
  /// - Returns: the model.
  static func modelAnsweringEveryRun(with answer: String, searches: Int = 1)
    -> ScriptedLanguageModel
  {
    ScriptedLanguageModel([String](repeating: answer, count: catalog.count * searches))
  }

  /// The whole prefix that `catalog` assembles with `preamble`.
  ///
  /// - Parameter preamble: the preamble of the prefix.
  /// - Returns: the assembled prefix.
  static func wholePrefix(preamble: String) -> String {
    SelectionTier.assemblePrefix(preamble: preamble, catalog: MetadataIndex(items: catalog))
  }

  // MARK: - The prefix is the instructions, the prompt is the request only

  @Test
  func underBudgetPromptIsTheRequestOnlyAndThePrefixIsTheInstructions() async throws {
    let model = ScriptedLanguageModel([#"{"ids":["alpha"]}"#])
    let config = SelectionConfig(model: model)
    let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

    _ = try await searcher.search(intent: Self.intent, limit: Self.searchLimit)

    let call = try #require(model.calls.first)
    #expect(model.calls.count == 1)
    #expect(call.prompt == ExpectedSelectionPrompt.request(for: Self.intent, ids: Self.catalogIDs))
    #expect(call.instructions == Self.wholePrefix(preamble: config.preamble))
  }

  @Test
  func overBudgetPromptOfEachRunIsTheRequestOverTheIdsOfThatRun() async throws {
    let model = Self.modelAnsweringEveryRun(with: #"{"ids":["alpha"]}"#)
    let config = SelectionConfig(model: model, capacityCharacterLimit: Self.forcedOverBudgetLimit)
    let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

    _ = try await searcher.search(intent: Self.intent, limit: Self.searchLimit)

    let expectedPrompts = Self.catalogIDs.map {
      ExpectedSelectionPrompt.request(for: Self.intent, ids: [$0])
    }
    #expect(model.calls.map(\.prompt) == expectedPrompts)
  }

  // MARK: - One prompt per run, every id in exactly one of them

  @Test
  func overBudgetGivesEveryCatalogIdOnePromptInCatalogOrder() async throws {
    let model = Self.modelAnsweringEveryRun(with: #"{"ids":["alpha"]}"#)
    let config = SelectionConfig(model: model, capacityCharacterLimit: Self.forcedOverBudgetLimit)
    let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

    _ = try await searcher.search(intent: Self.intent, limit: Self.searchLimit)

    // The tier splits rather than cuts, so the prompt count is the run
    // count and the runs follow catalog order.
    let instructions = model.calls.map(\.instructions)
    #expect(instructions.count == Self.catalog.count)
    for (instruction, item) in zip(instructions, Self.catalog) {
      let text = try #require(instruction)
      #expect(text.contains("id: \(item.id)\ndescription: \(item.summary)"))
    }
  }

  @Test
  func overBudgetPrefixNamesOnlyItsOwnRunsCandidateIds() async throws {
    let model = Self.modelAnsweringEveryRun(with: #"{"ids":["alpha"]}"#)
    let config = SelectionConfig(model: model, capacityCharacterLimit: Self.forcedOverBudgetLimit)
    let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

    _ = try await searcher.search(intent: Self.intent, limit: Self.searchLimit)

    let instructions = model.calls.map(\.instructions)
    #expect(instructions.count == Self.catalog.count)
    for (instruction, item) in zip(instructions, Self.catalog) {
      let text = try #require(instruction)
      let otherIDs = Self.catalogIDs.filter { $0 != item.id }
      #expect(otherIDs.allSatisfy { !text.contains("id: \($0)\n") })
    }
  }

  // MARK: - Nothing is kept between searches

  @Test
  func overBudgetMakesOnePromptForEveryRunOfEverySearch() async throws {
    let model = Self.modelAnsweringEveryRun(
      with: #"{"ids":["alpha"]}"#, searches: Self.searchCountOfTwo)
    let config = SelectionConfig(model: model, capacityCharacterLimit: Self.forcedOverBudgetLimit)
    let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

    _ = try await searcher.search(intent: Self.intent, limit: Self.searchLimit)
    _ = try await searcher.search(intent: Self.intent, limit: Self.searchLimit)

    // Nothing stays from one search to the next: each search makes one
    // prompt for each of its runs.
    #expect(model.calls.count == Self.catalog.count * Self.searchCountOfTwo)
  }

  // MARK: - Nothing is cut, so `.retrievalCut` is never reported

  @Test
  func overBudgetSearchNeverFiresRetrievalCut() async throws {
    let recorder = DiagnosticRecorder()
    let model = Self.modelAnsweringEveryRun(with: #"{"ids":["alpha"]}"#)
    let config = SelectionConfig(model: model, capacityCharacterLimit: Self.forcedOverBudgetLimit)
    let searcher = MetadataSearcher(
      items: Self.catalog,
      mode: .selection,
      selection: config,
      onDiagnostic: { recorder.record($0) },
    )

    _ = try await searcher.search(intent: Self.intent, limit: Self.searchLimit)

    // The selection path runs no retrieval at all now, so it reports
    // neither a cut nor the `.embeddingUnavailable` a ranking pass with
    // no embedder used to report.
    #expect(recorder.diagnostics.isEmpty)
  }

  @Test
  func underBudgetSearchNeverFiresRetrievalCut() async throws {
    let recorder = DiagnosticRecorder()
    let model = ScriptedLanguageModel([#"{"ids":["alpha"]}"#])
    let config = SelectionConfig(model: model)
    let searcher = MetadataSearcher(
      items: Self.catalog,
      mode: .selection,
      selection: config,
      onDiagnostic: { recorder.record($0) },
    )

    _ = try await searcher.search(intent: Self.intent, limit: Self.searchLimit)

    #expect(recorder.diagnostics.isEmpty)
  }

  @Test
  func overBudgetWithAnEmptyCatalogReturnsNoMatchesWithoutAPrompt() async throws {
    let recorder = DiagnosticRecorder()
    let model = ScriptedLanguageModel([String]())
    let config = SelectionConfig(model: model, capacityCharacterLimit: Self.forcedOverBudgetLimit)
    let searcher = MetadataSearcher(
      items: [FixtureItem](),
      mode: .selection,
      selection: config,
      onDiagnostic: { recorder.record($0) },
    )

    let matches = try await searcher.search(intent: Self.intent, limit: Self.searchLimit)

    // An empty catalog splits into no runs at all, so there is nothing
    // to prompt and nothing to report.
    #expect(matches.isEmpty)
    #expect(model.calls.isEmpty)
    #expect(recorder.diagnostics.isEmpty)
  }

  // MARK: - Verbatim lookup against the whole catalog

  @Test
  func overBudgetIdFromAnotherRunStillResolves() async throws {
    let recorder = DiagnosticRecorder()
    // Every run answers with "alpha" and "charlie", which sit in
    // different runs. The tier looks each answered id up in the whole
    // catalog, so a run's own candidate set never limits what resolves.
    // When the tier still cut candidates, this same answer was reported
    // as `.unknownSelectedId`.
    let model = Self.modelAnsweringEveryRun(with: #"{"ids":["alpha","charlie"]}"#)
    let config = SelectionConfig(model: model, capacityCharacterLimit: Self.forcedOverBudgetLimit)
    let searcher = MetadataSearcher(
      items: Self.catalog,
      mode: .selection,
      selection: config,
      onDiagnostic: { recorder.record($0) },
    )

    let matches = try await searcher.search(intent: Self.intent, limit: Self.searchLimit)

    #expect(matches.map(\.id) == ["alpha", "charlie"])
    #expect(recorder.diagnostics.isEmpty)
  }

  @Test
  func overBudgetIdOutsideTheCatalogIsFilteredAndReportedAsUnknown() async throws {
    let recorder = DiagnosticRecorder()
    let model = Self.modelAnsweringEveryRun(with: #"{"ids":["alpha","not-a-real-id"]}"#)
    let config = SelectionConfig(model: model, capacityCharacterLimit: Self.forcedOverBudgetLimit)
    let searcher = MetadataSearcher(
      items: Self.catalog,
      mode: .selection,
      selection: config,
      onDiagnostic: { recorder.record($0) },
    )

    let matches = try await searcher.search(intent: Self.intent, limit: Self.searchLimit)

    #expect(matches.map(\.id) == ["alpha"])
    #expect(recorder.diagnostics == [.unknownSelectedId(id: "not-a-real-id")])
  }

  // MARK: - The assembled prefix shows the model the candidate ids

  @Test
  func assembledPrefixNamesEachCandidateIdAboveItsSummary() {
    // The prefix must show each id. A prefix of summaries only gives the
    // model no id to copy, and each selection then comes back as
    // `.unknownSelectedId`. The prefix is the only text that shows the
    // model the ids it can answer with.
    let prefix = Self.wholePrefix(preamble: .librarianDefault)

    for item in Self.catalog {
      let entry = "<candidate>\nid: \(item.id)\ndescription: \(item.summary)\n</candidate>"
      #expect(prefix.contains(entry))
    }
  }

  // MARK: - Selection results are scored by the model's order

  @Test
  func selectionResultsAreScoredByTheModelsOrderAndCarryNoSignals() async throws {
    let model = Self.modelAnsweringEveryRun(with: #"{"ids":["charlie","alpha"]}"#)
    let config = SelectionConfig(model: model, capacityCharacterLimit: Self.forcedOverBudgetLimit)
    let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

    let matches = try await searcher.search(intent: Self.intent, limit: Self.searchLimit)

    // No retrieval signal enters a selection: a pick's score is the
    // reciprocal of its rank in the answer (1/1, then 1/2), and there is
    // no per-signal breakdown to carry.
    #expect(matches.map(\.id) == ["charlie", "alpha"])
    #expect(matches.map(\.score) == [1.0, 1.0 / 2.0])
    #expect(matches.allSatisfy { $0.signals == nil })
  }

  // MARK: - Budget boundary

  @Test
  func prefixExactlyAtTheCapacityLimitMakesOnePromptForEachSearch() async throws {
    let expectedPrefix = Self.wholePrefix(preamble: .librarianDefault)
    let model = ScriptedLanguageModel([#"{"ids":["alpha"]}"#, #"{"ids":["alpha"]}"#])
    let config = SelectionConfig(
      model: model,
      preamble: .librarianDefault,
      capacityCharacterLimit: expectedPrefix.count,
    )
    let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

    _ = try await searcher.search(intent: Self.intent, limit: Self.searchLimit)
    _ = try await searcher.search(intent: Self.intent, limit: Self.searchLimit)

    // The boundary itself (`==`) is under budget, as the "at or under"
    // documentation of `capacityCharacterLimit` says: each search makes one
    // prompt, and each prompt gets the whole prefix as its instructions.
    #expect(model.calls.count == Self.searchCountOfTwo)
    #expect(model.calls.map(\.instructions) == [expectedPrefix, expectedPrefix])
  }

  @Test
  func prefixOneCharacterOverTheCapacityLimitSplitsEachSearchTheSameWay() async throws {
    let expectedPrefix = Self.wholePrefix(preamble: .librarianDefault)
    let model = Self.modelAnsweringEveryRun(
      with: #"{"ids":["alpha"]}"#, searches: Self.searchCountOfTwo)
    let config = SelectionConfig(
      model: model,
      preamble: .librarianDefault,
      capacityCharacterLimit: expectedPrefix.count - 1,
    )
    let searcher = MetadataSearcher(items: Self.catalog, mode: .selection, selection: config)

    _ = try await searcher.search(intent: Self.intent, limit: Self.searchLimit)
    let promptsAfterFirstSearch = model.calls.count
    _ = try await searcher.search(intent: Self.intent, limit: Self.searchLimit)

    // One character over the budget is enough to split the catalog. How
    // many runs the split makes depends on the entry sizes of the fixture,
    // so the test checks that the first search makes more than one prompt
    // and that the second search repeats the prompt count of the first.
    #expect(promptsAfterFirstSearch > 1)
    #expect(model.calls.count == promptsAfterFirstSearch * Self.searchCountOfTwo)
  }
}
