import Foundation
import HotReloadCore

// # `update(items:)` bursts (plan.md §13 M8).
//
// An MCP-style add/remove burst against a live `MetadataSearcher`: every
// item is keyword-searchable immediately after each `update(items:)` call,
// embed catch-up progress is reported via `.embedCatchUp`, a burst that
// arrives while an embed is in flight embeds only the newest catalog, and the
// selection tier's cached root + grammar rebuild on a real catalog change
// is shown -- all GPU-free, against a deterministic embedder. Run with
// `swift run HotReload`.
//
// The actual logic lives in `HotReloadCore` so `ExamplesSmokeTests` can
// invoke both paths directly; this file is just the runnable entry point.

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

Report.write("GPU-free hot-reload burst (deterministic embedder):\n")

/// One line per burst step -- what `update(items:)` applied and what the
/// immediate search found -- followed by that step's diagnostics.
let steps = try await runHotReloadBurst()
for (index, step) in steps.enumerated() {
    Report.write(
        "GPU-free step \(index + 1): update(items: \(step.appliedIds)) -> search(\"file\") = \(step.searchResultIds)",
    )
    for diagnostic in step.diagnostics {
        Report.write("  [diagnostic] \(diagnostic)")
    }
}

Report.write("\nCoalesced burst (the first embed is held while the rest of the burst arrives):")
let coalesced = try await runCoalescedHotReloadBurst()
Report.write("  \(coalesced.updateCount) update(items:) calls -> \(coalesced.catalogEmbedBatches.count) embed calls")
for (index, batch) in coalesced.catalogEmbedBatches.enumerated() {
    Report.write("  embed call \(index + 1): \(batch)")
}

for diagnostic in coalesced.embedCatchUps {
    Report.write("  [diagnostic] \(diagnostic)")
}

Report.write("  search(\"file\") after the burst = \(coalesced.searchResultIds)")

Report.write("\nSelection-tier root/grammar rebuild demo (GPU-free, scripted session):")
let rebuild = try await runSelectionRootRebuildDemo()
Report.write(
    "  root session built \(rebuild.initialFactoryCallCount) time(s) for candidates \(rebuild.initialCandidateIds)",
)
Report.write(
    "  after a real catalog change, root session built \(rebuild.rebuiltFactoryCallCount) time(s) total "
        + "for candidates \(rebuild.updatedCandidateIds)",
)
