import Foundation
import Testing

/// Pins `.github/workflows/ci.yml` to the shared CI shape the org test
/// contract (swissarmyhammer/workflows' README) asks for: one job, which
/// delegates to the shared `swift-ci.yaml` and names the nested
/// `IntegrationTests/` package as the integration suite to build and run.
///
/// The root manifest never names that package, so the root build does not
/// compile it and a broken integration test cannot break a plain
/// `swift build --build-tests`. `integration-package-path` is what restores
/// that coupling: it makes the shared workflow's *unit* job build the nested
/// package on every run, before the expensive integration step, and it makes
/// the integration job run it. It is also the one input this workflow may
/// pass. `integration-gate-env` is LEGACY, and the shared workflow stops the
/// run when it is given beside the package path;
/// `integration-metallib-glob` colocates an mlx-swift `default.metallib`,
/// and no MLX package is in this dependency graph.
///
/// This suite pins all three halves of that shape: the `uses:` line names the
/// shared workflow, one line passes the package path, and no line passes any
/// other `integration-*` input. A later edit that points `uses:` somewhere
/// else, drops the package path back to a suite CI never builds, adds
/// repo-local test jobs, or reaches for a legacy input, fails this suite.
@Suite("CI workflow")
struct CIWorkflowTests {
    /// The name of the shared workflow input that names the nested
    /// integration package, with the colon that separates it from its value.
    private static let integrationPackagePathKey = "integration-package-path:"

    /// The value that input carries: the nested integration package's
    /// directory, relative to the repository root.
    private static let integrationPackagePath = "IntegrationTests"

    /// The prefix every input that switches the shared workflow's integration
    /// job on begins with.
    private static let integrationInputPrefix = "integration-"

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
        let expected = "\(Self.integrationPackagePathKey) \(Self.integrationPackagePath)"
        let namesPackage = lines.contains { line in
            line.trimmingCharacters(in: .whitespaces) == expected
        }
        #expect(
            namesPackage,
            """
            ci.yml must pass "\(expected)" to the shared workflow, so its unit job builds the \
            nested package on every run — the root build never compiles it — and its integration \
            job runs the suite.
            """
        )
    }

    @Test("ci.yml passes the shared workflow no other integration-* input")
    func passesNoOtherIntegrationInput() throws {
        let lines = try Self.workflowLines()
        // Matched case-insensitively: GitHub Actions resolves a `with:` key
        // against the called workflow's `inputs:` without regard to case, so
        // `Integration-Gate-Env:` would reach the shared workflow just as
        // `integration-gate-env:` does. A case-sensitive read would let that
        // spelling through.
        let otherInputs = lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                let key = line.lowercased()
                return key.hasPrefix(Self.integrationInputPrefix)
                    && !key.hasPrefix(Self.integrationPackagePathKey)
            }
        #expect(
            otherInputs.isEmpty,
            """
            ci.yml must pass "\(Self.integrationPackagePathKey)" and no other integration-* \
            input: integration-gate-env is LEGACY and the shared workflow stops the run when it \
            is given beside the package path, and integration-metallib-glob colocates an \
            mlx-swift metallib that nothing in this dependency graph needs; found: \(otherInputs)
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
