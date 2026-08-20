import Foundation
import Testing

/// Pins `.github/workflows/ci.yml` to the shared CI shape the org test
/// contract (swissarmyhammer/workflows' README) asks for: one call to the
/// shared `swift-ci.yaml`, with `integration-package-path` naming the nested
/// `IntegrationTests/` package so the shared workflow's own unit job builds
/// it on every run, and its integration job builds, colocates the metallib
/// for, and runs it — ordered after the unit job by the shared workflow's
/// own internal `needs: test` edge, not a repo-local one.
///
/// This suite previously pinned a repo-local `needs: unit` edge between two
/// repo-local jobs; that edge doesn't exist on this side any more once both
/// jobs delegate to the shared workflow, so this suite pins delegation
/// instead: the `uses:` line names the shared workflow, and the inputs name
/// this repository's actual nested package and metallib glob. A later edit
/// that points `uses:` somewhere else, or drops `integration-package-path`
/// back to repo-local jobs, fails this suite.
@Suite("CI workflow")
struct CIWorkflowTests {
    @Test("ci.yml calls the shared swift-ci.yaml workflow")
    func callsTheSharedWorkflow() throws {
        let lines = try Self.workflowLines()
        let callsShared = lines.contains { line in
            line.trimmingCharacters(in: .whitespaces)
                == "uses: swissarmyhammer/workflows/.github/workflows/swift-ci.yaml@main"
        }
        #expect(
            callsShared,
            "ci.yml must call swissarmyhammer/workflows/.github/workflows/swift-ci.yaml@main."
        )
    }

    @Test("ci.yml points integration-package-path at the nested IntegrationTests package")
    func namesTheNestedIntegrationPackage() throws {
        let lines = try Self.workflowLines()
        let namesPackage = lines.contains { line in
            line.trimmingCharacters(in: .whitespaces) == "integration-package-path: IntegrationTests"
        }
        #expect(
            namesPackage,
            """
            ci.yml must set integration-package-path: IntegrationTests so the shared workflow \
            builds and runs the nested package, rather than falling back to repo-local jobs.
            """
        )
    }

    @Test("ci.yml sets an integration-metallib-glob so the shared workflow's colocation step runs")
    func setsAMetallibGlob() throws {
        let lines = try Self.workflowLines()
        let setsGlob = lines.contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("integration-metallib-glob:") && trimmed != "integration-metallib-glob:"
        }
        #expect(
            setsGlob,
            """
            ci.yml must set a non-empty integration-metallib-glob. \
            MetalLibraryTestBootstrap.swift is the root-cause fix for GPU-device tests under \
            `swift test`, and this input is defense-in-depth on top of it — see that file's \
            header.
            """
        )
    }

    @Test("ci.yml declares no repo-local test-running jobs")
    func declaresNoRepoLocalJobs() throws {
        let lines = try Self.workflowLines()
        guard let jobsIndex = lines.firstIndex(of: "jobs:") else {
            Issue.record("ci.yml has no top-level \"jobs:\" key.")
            return
        }
        // A job key is two-space-indented, e.g. "  ci:". Only lines after
        // "jobs:" are job keys — "on:"'s own two-space-indented children
        // (push:, pull_request:, ...) match the same shape and would
        // otherwise be miscounted as jobs.
        let jobKeyPattern = try Regex(#"^  [a-zA-Z0-9_-]+:$"#)
        let jobKeys = lines[lines.index(after: jobsIndex)...].filter { $0.wholeMatch(of: jobKeyPattern) != nil }
        #expect(
            jobKeys.count == 1,
            """
            ci.yml must declare exactly one job that delegates to the shared workflow, not \
            repo-local unit/integration jobs; found job keys: \(jobKeys)
            """
        )
    }

    /// Reads `.github/workflows/ci.yml` from the repository root, resolved
    /// relative to this source file's own path (`#filePath` is
    /// `Tests/FoundationModelsMetadataRegistryTests/CIWorkflowTests.swift`,
    /// two directories below the root).
    ///
    /// - Returns: each line of the workflow file.
    /// - Throws: an error when the file cannot be read.
    private static func workflowLines() throws -> [Substring] {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/FoundationModelsMetadataRegistryTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repository root
        let workflow = repoRoot
            .appendingPathComponent(".github/workflows/ci.yml")
        let text = try String(contentsOf: workflow, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
    }
}
