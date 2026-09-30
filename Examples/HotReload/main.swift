import ExamplesSupport
import Foundation
import FoundationModels
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
// 3. Selection after a change. In `.selection` mode, the searcher caches a
//    root session for the catalog. A real change to the catalog discards
//    that session, and the next search makes a new one for the new catalog.
//
// Parts 1 and 2 embed with one `PooledEmbedder` of FoundationModelsExtras for
// Qwen3 Embedding 0.6B, 4-bit, from the Hugging Face hub. The first embed
// loads the model through `ModelPool.shared`, and the first run downloads
// the weights. The two searchers share that one loaded model. Part 3 uses
// the on-device Apple Intelligence model.
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

/// The embedding model of parts 1 and 2. It loads nothing until its first embed.
let embedder = PooledEmbedder(ref: "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ")

/// The report that this command writes: its whole output, one line at a time.
///
/// The report is the product of this command, not a debug log, so it goes to
/// standard output through one explicit writer.
enum Report {
    /// Writes `line` and a line break to standard output.
    ///
    /// - Parameter line: the text of the line.
    static func write(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}

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
    embedder: embedder,
    onDiagnostic: { burstLog.record($0) },
)
for (index, items) in burst.enumerated() {
    let before = burstLog.count
    await burstSearcher.update(items: items)
    let found = try await burstSearcher.search(intent: query, limit: searchLimit).map(\.id)
    Report.write("step \(index + 1): update(items: \(items.map(\.id))) -> search(\"\(query)\") = \(found)")
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

let coalesced = try await runCoalescedBurst(rapidBurst, embeddingWith: embedder, query: query, limit: searchLimit)
Report.write("  \(rapidBurst.count) update(items:) calls -> \(coalesced.embedBatches.count) embed calls")
for (index, batch) in coalesced.embedBatches.enumerated() {
    Report.write("  embed call \(index + 1): \(batch)")
}
for diagnostic in coalesced.embedCatchUps {
    Report.write("  [diagnostic] \(diagnostic)")
}
Report.write("  search(\"\(query)\") after the burst = \(coalesced.searchResultIds)")

// MARK: - 3. Selection after a change

Report.write("\nSelection root session after a catalog change (on-device model):")
requireSystemLanguageModel()

/// Counts each root session that the searcher makes. Each one is a real
/// session of the on-device Apple Intelligence model.
let sessionCount = CallCounter()
let selectionConfig = SelectionConfig(model: { instructions in
    sessionCount.increment()
    return LanguageModelSession(model: .default, instructions: instructions)
})
let selector = MetadataSearcher(items: [toolA], mode: .selection, selection: selectionConfig)

_ = try await selector.search(intent: "read a file", limit: searchLimit)
Report.write("  root session built \(sessionCount.count) time(s) for candidates [\"toolA\"]")

await selector.update(items: [toolA, toolB])
_ = try await selector.search(intent: "read a file", limit: searchLimit)
Report.write(
    "  after a real catalog change, root session built \(sessionCount.count) time(s) total "
        + "for candidates [\"toolA\", \"toolB\"]",
)

// MARK: - Helpers

/// A thread-safe call counter.
///
/// The session factory is synchronous, so an actor cannot count its calls.
final class CallCounter: Sendable {
    /// The lock that holds the count.
    private let value = OSAllocatedUnfairLock<Int>(initialState: 0)

    /// The number of calls counted so far.
    var count: Int {
        value.withLock { $0 }
    }

    /// Counts one more call.
    func increment() {
        value.withLock { $0 += 1 }
    }
}

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
