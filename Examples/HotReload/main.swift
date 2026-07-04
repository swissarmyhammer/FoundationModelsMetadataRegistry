import ExamplesSupport
import Foundation
import HotReloadCore

/// # `update(items:)` bursts (plan.md §13 M8).
///
/// An MCP-style add/remove burst against a live `MetadataSearcher`: every
/// item is keyword-searchable immediately after each `update(items:)` call,
/// embed catch-up progress is reported via `.embedCatchUp`, and the
/// selection tier's cached root + grammar rebuild on a real catalog change
/// is shown -- all GPU-free, against a deterministic embedder. Only when
/// `METADATA_REGISTRY_INTEGRATION_TESTS` is set does it also replay the same
/// burst against a real, live-Router-resolved embedder. Run with `swift run
/// HotReload`.
///
/// The actual logic lives in `HotReloadCore` so `ExamplesSmokeTests` can
/// invoke both GPU-free paths directly; this file is just the runnable
/// entry point.

func printBurst(_ steps: [BurstStepResult], label: String) {
    for (index, step) in steps.enumerated() {
        print("\(label) step \(index + 1): update(items: \(step.appliedIds)) -> search(\"file\") = \(step.searchResultIds)")
        for diagnostic in step.diagnostics {
            print("  [diagnostic] \(diagnostic)")
        }
    }
}

print("GPU-free hot-reload burst (deterministic embedder):\n")
let steps = try await runHotReloadBurst()
printBurst(steps, label: "GPU-free")

print("\nSelection-tier root/grammar rebuild demo (GPU-free, scripted session):")
let rebuild = try await runSelectionRootRebuildDemo()
print("  root session built \(rebuild.initialFactoryCallCount) time(s) for candidates \(rebuild.initialCandidateIds)")
print(
    "  after a real catalog change, root session built \(rebuild.rebuiltFactoryCallCount) time(s) total "
        + "for candidates \(rebuild.updatedCandidateIds)"
)

if metadataRegistryIntegrationEnabled {
    print("\n\(metadataRegistryIntegrationEnvVar) is set -- replaying the burst against a real embedder...\n")
    let embedder = try await resolveLiveEmbedder()
    let liveSteps = try await runHotReloadBurst(embedder: embedder)
    printBurst(liveSteps, label: "Live")
} else {
    print("\nSet \(metadataRegistryIntegrationEnvVar) to also replay the burst against a real, live-Router-resolved embedder.")
}
