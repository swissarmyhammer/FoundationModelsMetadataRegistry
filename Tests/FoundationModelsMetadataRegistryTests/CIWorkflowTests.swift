import Foundation
import Testing

/// Pins `.github/workflows/ci.yml` to the shared CI shape the org test
/// contract (swissarmyhammer/workflows' README) asks for: one job, which
/// delegates to the shared `swift-ci.yaml` and passes it no input at all.
///
/// This repository has unit tests only. The shared workflow gates its
/// integration job on `integration-gate-env`, `integration-filter`,
/// `integration-skip`, or `integration-package-path` being non-empty, so
/// passing none of them is what keeps that job switched off. Every input of
/// the shared workflow is optional, which is what makes the bare `uses:`
/// call valid.
///
/// This suite pins both halves of that shape: the `uses:` line names the
/// shared workflow, and no line passes an `integration-*` input. A later
/// edit that points `uses:` somewhere else, adds repo-local test jobs, or
/// re-introduces an integration input without an integration suite to run,
/// fails this suite.
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

    @Test("ci.yml passes the shared workflow no integration-* input")
    func passesNoIntegrationInput() throws {
        let lines = try Self.workflowLines()
        // Matched case-insensitively: GitHub Actions resolves a `with:` key
        // against the called workflow's `inputs:` without regard to case, so
        // `Integration-Package-Path:` would switch the integration job on
        // just as `integration-package-path:` does. A case-sensitive read
        // would let that spelling through.
        let integrationInputs = lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.lowercased().hasPrefix("integration-") }
        #expect(
            integrationInputs.isEmpty,
            """
            ci.yml must pass no integration-* input. This repository has no integration suite, \
            so the shared workflow's integration job must stay switched off; found: \
            \(integrationInputs)
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
