import Testing

@testable import FoundationModelsMetadataRegistry

/// Tests for hot reload (plan.md §8, M4).
///
/// `MetadataSearcher.update(items:)` renders the items again and rebuilds the
/// tokenized and trigram indexes synchronously. It embeds again only the
/// items whose `(id, block-hash)` changed, and it reports the catch-up gap of
/// the async embed with `.embedCatchUp`. Each selection search makes a new
/// session whose instructions are the prefix of the current catalog, so the
/// first search after a content change shows the model the new catalog. A
/// redundant update is cheap: no embed and no diagnostic.
///
/// The tests use the counting `FakeEmbedder`, the `ScriptedLanguageModel`,
/// and the `GatedEmbedder` (`TestSupport`), which holds the interim
/// keyword-only window open.
struct HotReloadTests {
  // MARK: - Fixtures

  /// A catalog item with an optional summary that is not its block.
  struct FixtureItem: SearchableMetadata {
    /// The id of the item.
    let id: String

    /// The full block of the item.
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

  /// The transient embed failure the catch-up tests hand `FakeEmbedder` to
  /// build an index whose items carry real content but no stored
  /// embeddings (plan.md §8 "embed catch-up").
  struct AlwaysFails: Error {}

  /// The `Selection` JSON that each scripted prompt in this suite answers.
  static let selectionOfA = #"{"ids":["a"]}"#

  /// The prefix that `items` assembles with `preamble`.
  ///
  /// - Parameters:
  ///   - preamble: the preamble of the prefix.
  ///   - items: the catalog, in catalog order.
  /// - Returns: the assembled prefix.
  static func prefix(preamble: String, items: [FixtureItem]) -> String {
    SelectionTier.assemblePrefix(preamble: preamble, catalog: MetadataIndex(items: items))
  }

  // MARK: - Incremental re-embed counts

  @Test
  func updateReEmbedsOnlyTheItemWhoseBlockActuallyChanged() async throws {
    let itemA = FixtureItem(id: "a", block: "alpha block")
    let itemB = FixtureItem(id: "b", block: "bravo block")
    let itemC = FixtureItem(id: "c", block: "charlie block")
    let embedder = FakeEmbedder(
      vectorsByText: [
        "alpha block": [1, 0],
        "bravo block": [0, 1],
        "charlie block": [1, 1],
        "bravo block CHANGED": [0, -1],
      ],
    )
    // The index is embedded before the update, so the count below shows
    // the embed of the update alone.
    let index = await MetadataIndex.build(items: [itemA, itemB, itemC], embedder: embedder)
    let searcher = MetadataSearcher(index: index, embedder: embedder)
    #expect(embedder.embeddedTextCount == 3)

    await searcher.update(items: [itemA, FixtureItem(id: "b", block: "bravo block CHANGED"), itemC])

    // Only "b" was re-embedded -- the count grows by exactly 1, not by a
    // full re-embed of all three items.
    #expect(embedder.embeddedTextCount == 4)

    let matches = try await searcher.search(intent: "bravo", limit: 5)
    #expect(matches.first?.id == "b")
  }

  @Test
  func updateWithBrandNewItemsEmbedsOnlyTheNewOnes() async {
    let itemA = FixtureItem(id: "a", block: "alpha block")
    let itemB = FixtureItem(id: "b", block: "bravo block")
    let embedder = FakeEmbedder(vectorsByText: ["alpha block": [1, 0], "bravo block": [0, 1]])
    let index = await MetadataIndex.build(items: [itemA], embedder: embedder)
    let searcher = MetadataSearcher(index: index, embedder: embedder)
    #expect(embedder.embeddedTextCount == 1)

    await searcher.update(items: [itemA, itemB])

    #expect(embedder.embeddedTextCount == 2)
  }

  // MARK: - Redundant update is a no-op

  @Test
  func redundantUpdateWithIdenticalItemsPerformsNoReEmbedAndKeepsTheSamePrefix() async throws {
    let items = [FixtureItem(id: "a", block: "alpha block")]
    let embedder = FakeEmbedder(vectorsByText: ["alpha block": [1, 0]])
    let model = ScriptedLanguageModel([Self.selectionOfA, Self.selectionOfA])
    let config = SelectionConfig(model: model)
    let index = await MetadataIndex.build(items: items, embedder: embedder)
    let searcher = MetadataSearcher(
      index: index, mode: .selection, embedder: embedder, selection: config)
    #expect(embedder.embeddedTextCount == 1)

    _ = try await searcher.search(intent: "task", limit: 5)

    // Captured after the search above rather than assumed, so this
    // assertion isolates `update`'s own re-embed delta whatever else
    // passes through the shared embedder.
    let countBeforeUpdate = embedder.embeddedTextCount
    await searcher.update(items: items)

    // No new embed call from `update` itself: unchanged content never
    // re-embeds the catalog.
    #expect(embedder.embeddedTextCount == countBeforeUpdate)

    _ = try await searcher.search(intent: "task", limit: 5)

    // The search after the update still answers from the same catalog:
    // its prompt gets the same prefix as the prompt before the update.
    let expectedPrefix = Self.prefix(preamble: config.preamble, items: items)
    #expect(model.calls.map(\.instructions) == [expectedPrefix, expectedPrefix])
  }

  @Test
  func redundantUpdateNeverEmitsAnyDiagnostic() async {
    let recorder = DiagnosticRecorder()
    let items = [FixtureItem(id: "a", block: "alpha block")]
    let embedder = FakeEmbedder(vectorsByText: ["alpha block": [1, 0]])
    // An embedded catalog: no entry waits for an embed, so the update
    // with the same content has nothing to catch up.
    let index = await MetadataIndex.build(
      items: items, embedder: embedder, onDiagnostic: { recorder.record($0) })
    let searcher = MetadataSearcher(
      index: index, embedder: embedder, onDiagnostic: { recorder.record($0) })

    await searcher.update(items: items)

    #expect(recorder.diagnostics.isEmpty)
  }

  // MARK: - The next prompt shows the new catalog after a real change

  @Test
  func updateWithARealChangeMakesTheNextPromptShowTheNewCatalog() async throws {
    let itemA = FixtureItem(id: "a", block: "alpha block", summary: "SUMMARY_a")
    let itemB = FixtureItem(id: "b", block: "bravo block", summary: "SUMMARY_b")
    let itemC = FixtureItem(id: "c", block: "charlie block", summary: "SUMMARY_c")
    let model = ScriptedLanguageModel([Self.selectionOfA, Self.selectionOfA])
    let config = SelectionConfig(model: model)
    let searcher = MetadataSearcher(items: [itemA, itemC], mode: .selection, selection: config)

    _ = try await searcher.search(intent: "task", limit: 5)
    await searcher.update(items: [itemA, itemB])
    _ = try await searcher.search(intent: "task", limit: 5)

    // The prompt after the update gets the prefix of the new catalog: it
    // holds the added id and not the removed id.
    let instructions = model.calls.map(\.instructions)
    #expect(instructions.count == 2)
    let before = try #require(instructions[0])
    let after = try #require(instructions[1])
    #expect(before == Self.prefix(preamble: config.preamble, items: [itemA, itemC]))
    #expect(after == Self.prefix(preamble: config.preamble, items: [itemA, itemB]))
    #expect(after.contains("id: b\ndescription: SUMMARY_b"))
    #expect(!after.contains("id: c\n"))
    #expect(!after.contains("SUMMARY_c"))
  }

  // MARK: - Embed catch-up diagnostic

  @Test
  func updateReportsEmbedCatchUpWithAccuratePendingAndTotalCounts() async {
    let recorder = DiagnosticRecorder()
    let itemA = FixtureItem(id: "a", block: "alpha block")
    let itemB = FixtureItem(id: "b", block: "bravo block")
    let embedder = FakeEmbedder(vectorsByText: ["alpha block": [1, 0], "bravo block": [0, 1]])
    // "a" is embedded before the update, so only "b" is pending.
    let index = await MetadataIndex.build(
      items: [itemA], embedder: embedder, onDiagnostic: { recorder.record($0) })
    let searcher = MetadataSearcher(
      index: index, embedder: embedder, onDiagnostic: { recorder.record($0) })

    await searcher.update(items: [itemA, itemB])

    #expect(recorder.diagnostics.contains(.embedCatchUp(pending: 1, total: 2)))
  }

  @Test
  func updateWithNoEmbedderConfiguredNeverEmitsEmbedCatchUp() async throws {
    let recorder = DiagnosticRecorder()
    let itemA = FixtureItem(id: "a", block: "alpha block")
    let searcher = MetadataSearcher(items: [FixtureItem](), onDiagnostic: { recorder.record($0) })

    await searcher.update(items: [itemA])

    let matches = try await searcher.search(intent: "alpha", limit: 5)
    #expect(matches.map(\.id) == ["a"])
    #expect(
      !recorder.diagnostics.contains {
        if case .embedCatchUp = $0 {
          return true
        }
        return false
      },
    )
  }

  // MARK: - Interim keyword-only service while re-embedding is in flight

  @Test
  func concurrentSearchDuringUpdateServesKeywordOnlyForTheNotYetEmbeddedItem() async throws {
    let commit = FixtureItem(id: "commit", block: "records a snapshot of staged changes")
    let gate = EmbedGate()
    // "snapshot" (the query text) also maps to `[1, 0]` so the
    // post-catch-up search's own query embed call -- which reuses this
    // same gated embedder, now released -- lines up with `commit`'s
    // freshly stored embedding instead of falling back to an all-zero
    // vector that would trivially score `0.0` regardless of catch-up.
    let embedder = GatedEmbedder(
      vectorsByText: [commit.block: [1, 0], "snapshot": [1, 0]], gate: gate,
    )
    // Construct with an empty catalog so init itself never touches the
    // gate -- there's nothing to embed yet.
    let searcher = MetadataSearcher(items: [FixtureItem](), embedder: embedder)

    let updateTask = Task { await searcher.update(items: [commit]) }

    // Wait until `update`'s embed call has actually started: the
    // synchronous baseline reassignment (tokenized/trigram indexes)
    // that precedes it has therefore already happened, and this call is
    // now suspended on the gate -- the actor is free to interleave a
    // concurrent `search()` while it waits.
    await gate.waitForStart()

    let interimMatches = try await searcher.search(intent: "snapshot", limit: 5)
    let interimMatch = try #require(interimMatches.first)
    #expect(interimMatch.id == "commit")
    #expect(interimMatch.signals?.cosine == 0.0)

    await gate.release()
    await updateTask.value

    let caughtUpMatches = try await searcher.search(intent: "snapshot", limit: 5)
    let caughtUpMatch = try #require(caughtUpMatches.first)
    #expect(caughtUpMatch.signals?.cosine != 0.0)
  }

  // MARK: - Catch-up survives a content-unchanged redundant forward

  @Test
  func updateStillCatchesUpAnEmbeddingThatNeverSucceededEvenWhenContentIsUnchanged() async throws {
    // Simulates a prior build/update whose embed call failed
    // transiently (plan.md §8 "embed catch-up"): "a" is indexed with
    // its real content but carries no stored embedding.
    let itemA = FixtureItem(id: "a", block: "alpha block")
    let indexWithoutEmbedding = await MetadataIndex.build(
      items: [itemA], embedder: FakeEmbedder(failure: AlwaysFails()),
    )
    #expect(indexWithoutEmbedding.embedding(forID: "a") == nil)

    let recorder = DiagnosticRecorder()
    let workingEmbedder = FakeEmbedder(vectorsByText: ["alpha block": [1, 0], "alpha": [1, 0]])
    let searcher = MetadataSearcher(
      index: indexWithoutEmbedding,
      embedder: workingEmbedder,
      onDiagnostic: { recorder.record($0) },
    )

    // Same content as what's already indexed -- e.g. an upstream
    // notification forwarded without coalescing, exactly the pattern
    // the task's hash-guarding is meant to make cheap. It must NOT be
    // treated as a full no-op: the embedding that never succeeded still
    // needs to catch up.
    await searcher.update(items: [itemA])

    #expect(recorder.diagnostics.contains(.embedCatchUp(pending: 1, total: 1)))
    #expect(workingEmbedder.embeddedTextCount == 1)

    let matches = try await searcher.search(intent: "alpha", limit: 5)
    #expect(matches.first?.signals?.cosine != 0.0)
  }

  @Test
  func contentIdenticalEmbedCatchUpKeepsTheSamePrefix() async throws {
    let itemA = FixtureItem(id: "a", block: "alpha block")
    let indexWithoutEmbedding = await MetadataIndex.build(
      items: [itemA],
      embedder: FakeEmbedder(failure: AlwaysFails()),
    )
    let workingEmbedder = FakeEmbedder(vectorsByText: ["alpha block": [1, 0]])
    let model = ScriptedLanguageModel([Self.selectionOfA, Self.selectionOfA])
    let config = SelectionConfig(model: model)
    let searcher = MetadataSearcher(
      index: indexWithoutEmbedding,
      mode: .selection,
      embedder: workingEmbedder,
      selection: config,
    )

    _ = try await searcher.search(intent: "task", limit: 5)

    // Content-identical catch-up: the embedding that never succeeded
    // merges in, but no text of the prefix changes. The search after the
    // update still answers from the same catalog, so its prompt gets the
    // same prefix as the prompt before the update.
    await searcher.update(items: [itemA])

    _ = try await searcher.search(intent: "task", limit: 5)

    let expectedPrefix = Self.prefix(preamble: config.preamble, items: [itemA])
    #expect(model.calls.map(\.instructions) == [expectedPrefix, expectedPrefix])
  }
}
