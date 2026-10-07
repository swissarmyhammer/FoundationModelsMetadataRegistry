import ExamplesSupport
import FoundationModelsExtras
import FoundationModelsMetadataRegistry
import os

// # HotReload: change the catalog of a live searcher.
//
// A tool server, for example an MCP server, can add and remove tools at any
// time. This example sends such changes to a live `MetadataSearcher` with
// `update(items:)`, and shows three behaviors:
//
// 1. A burst of updates. After each update, a keyword search finds the new
//    items at once. The embeddings catch up after the update, and the
//    searcher reports the progress with `.embedCatchUp`. The searcher embeds
//    only the items that are new; an update with the same items does
//    nothing.
// 2. A burst while an embed is in flight. The example holds the first embed
//    call and sends the rest of the burst. The searcher then embeds only the
//    newest catalog, not each catalog between.
// 3. Selection after a change. In `.selection` mode, the searcher keeps a
//    selection tier that holds the prefix of the catalog. A real change to
//    the catalog builds a new tier for the new catalog. Each search sends
//    its prompt to a new session of the model, so the next search sees the
//    new catalog at once.
//
// Parts 1 and 2 embed with `exampleEmbedder` of ExamplesSupport: a
// `PooledEmbedder` of FoundationModelsExtras for Qwen3 Embedding 0.6B, 4-bit,
// from the Hugging Face hub. The first embed loads the model through
// `ModelPool.shared`, and the first run downloads the weights. The two
// searchers share that one loaded model. Part 3 selects with
// `exampleSelectionModel` of ExamplesSupport: a `PooledModel` of
// FoundationModelsExtras for Qwen3 4B, 4-bit, from the Hugging Face hub. The
// first selection prompt loads that model through `ModelPool.shared`, and
// the first run downloads the weights.
//
// Run with `swift run --package-path Examples HotReload`.

/// A tool: an id and a description.
typealias Tool = SearchableFixtureItem

let toolA = Tool(id: "toolA", block: "reads a file from disk")
let toolB = Tool(id: "toolB", block: "writes a file to disk")
let toolC = Tool(id: "toolC", block: "deletes a file from disk")

/// The query of each search. Each tool description contains "file".
let query = "file"

/// The maximum number of matches of each search. This value is larger than
/// the number of tools in the largest catalog, so each search can find all
/// the tools.
let searchLimit = 5

// MARK: - 1. A burst of updates

Report.write("Hot-reload burst:\n")

/// Add a tool, add a second tool, send the same catalog again, then remove
/// one tool and add another.
let burst: [[Tool]] = [
  [toolA],
  [toolA, toolB],
  [toolA, toolB],
  [toolB, toolC],
]

let burstLog = DiagnosticLog()
let burstSearcher = MetadataSearcher(
  items: [Tool](),
  mode: .retrieval,
  embedder: exampleEmbedder,
  onDiagnostic: { burstLog.record($0) },
)
for (index, items) in burst.enumerated() {
  let before = burstLog.count
  await burstSearcher.update(items: items)
  let found = try await burstSearcher.search(intent: query, limit: searchLimit).map(\.id)
  Report.write(
    "step \(index + 1): update(items: \(items.map(\.id))) -> search(\"\(query)\") = \(found)")
  for diagnostic in burstLog.diagnostics(since: before) {
    Report.write("  [diagnostic] \(diagnostic)")
  }
}

// MARK: - 2. A burst while an embed is in flight

Report.write("\nCoalesced burst (the first embed is held while the rest of the burst arrives):")

/// Each catalog differs from the one before it, so a keyword search shows
/// when each update has arrived.
let rapidBurst: [[Tool]] = [
  [toolA],
  [toolA, toolB],
  [toolB],
  [toolB, toolC],
]

let coalesced = try await runCoalescedBurst(
  rapidBurst,
  embeddingWith: exampleEmbedder,
  query: query,
  limit: searchLimit,
)
Report.write(
  "  \(rapidBurst.count) update(items:) calls -> \(coalesced.embedBatches.count) embed calls")
for (index, batch) in coalesced.embedBatches.enumerated() {
  Report.write("  embed call \(index + 1): \(batch)")
}
for diagnostic in coalesced.embedCatchUps {
  Report.write("  [diagnostic] \(diagnostic)")
}
Report.write("  search(\"\(query)\") after the burst = \(coalesced.searchResultIds)")

// MARK: - 3. Selection after a change

Report.write("\nSelection after a catalog change (Qwen3 4B, a new session for each prompt):")

let selector = MetadataSearcher(
  items: [toolA],
  mode: .selection,
  selection: SelectionConfig(model: exampleSelectionModel),
)

/// The intent of each selection search of part 3.
let selectionIntent = "write a file"

let firstSelection = try await selector.search(intent: selectionIntent, limit: searchLimit).map(
  \.id)
Report.write("  candidates [\"toolA\"]: selected \(firstSelection)")

await selector.update(items: [toolA, toolB])
let secondSelection = try await selector.search(intent: selectionIntent, limit: searchLimit).map(
  \.id)
Report.write(
  "  after a real catalog change, candidates [\"toolA\", \"toolB\"]: selected \(secondSelection)")

// MARK: - Helpers

/// A thread-safe log of the diagnostics that a searcher reports.
///
/// The `onDiagnostic` callback is synchronous, so an actor cannot receive it.
final class DiagnosticLog: Sendable {
  /// The diagnostics recorded so far, in the order they arrived.
  private let recorded = OSAllocatedUnfairLock<[MetadataDiagnostic]>(initialState: [])

  /// The number of diagnostics recorded so far.
  var count: Int {
    recorded.withLock { $0.count }
  }

  /// Records one diagnostic.
  ///
  /// - Parameter diagnostic: the diagnostic to record.
  func record(_ diagnostic: MetadataDiagnostic) {
    recorded.withLock { $0.append(diagnostic) }
  }

  /// The diagnostics recorded at or after `index`.
  ///
  /// - Parameter index: a count read before, where the new diagnostics start.
  /// - Returns: each diagnostic recorded at or after `index`.
  func diagnostics(since index: Int) -> [MetadataDiagnostic] {
    recorded.withLock { diagnostics in
      guard index < diagnostics.count else { return [] }
      return Array(diagnostics[index...])
    }
  }
}
