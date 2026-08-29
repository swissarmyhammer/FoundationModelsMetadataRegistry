import HotReloadCore

/// # `update(items:)` bursts (plan.md §13 M8).
///
/// An MCP-style add/remove burst against a live `MetadataSearcher`: every
/// item is keyword-searchable immediately after each `update(items:)` call,
/// embed catch-up progress is reported via `.embedCatchUp`, and the
/// selection tier's cached root + grammar rebuild on a real catalog change
/// is shown -- all GPU-free, against a deterministic embedder. Run with
/// `swift run HotReload`.
///
/// The actual logic lives in `HotReloadCore` so `ExamplesSmokeTests` can
/// invoke both paths directly; this file is just the runnable entry point.

print("GPU-free hot-reload burst (deterministic embedder):\n")

// One line per burst step -- what `update(items:)` applied and what the
// immediate search found -- followed by that step's diagnostics.
let steps = try await runHotReloadBurst()
for (index, step) in steps.enumerated() {
    print("GPU-free step \(index + 1): update(items: \(step.appliedIds)) -> search(\"file\") = \(step.searchResultIds)")
    for diagnostic in step.diagnostics {
        print("  [diagnostic] \(diagnostic)")
    }
}

print("\nSelection-tier root/grammar rebuild demo (GPU-free, scripted session):")
let rebuild = try await runSelectionRootRebuildDemo()
print("  root session built \(rebuild.initialFactoryCallCount) time(s) for candidates \(rebuild.initialCandidateIds)")
print(
    "  after a real catalog change, root session built \(rebuild.rebuiltFactoryCallCount) time(s) total "
        + "for candidates \(rebuild.updatedCandidateIds)"
)
