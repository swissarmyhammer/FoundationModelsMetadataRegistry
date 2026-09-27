import ExamplesSupport
import FoundationModelsMetadataRegistry
@testable import SemanticSearchCore
import Testing

// # Diagnostic printing tests of the examples smoke suite.
//
// These tests are in the `Examples smoke tests` suite, but in this file of
// their own, so that `ExamplesSmokeTests.swift` stays in the file length
// limit. They examine `ExamplesSupport.printExampleDiagnostic` and
// `SemanticSearchCore.printDiagnostic` through what each call writes to
// standard output.

extension ExamplesSmokeTests {
    /// The prefix that `ExamplesSupport.printExampleDiagnostic` writes before
    /// each message it prints. No other code in the test process prints a line
    /// with this prefix.
    private static let diagnosticPrefix = "[diagnostic] "

    /// The message that the `describe` closure of the `printExampleDiagnostic`
    /// test gives. It is not the message of an example, so the printed line
    /// can only come from the call under test.
    private static let specialCaseMessage = "special case message from the smoke test"

    /// A diagnostic for which the `describe` closure of each diagnostic test
    /// gives no message, so the call goes to `MetadataDiagnostic.log(_:)`.
    private static let duplicateIdDiagnostic = MetadataDiagnostic.duplicateId(id: "x")

    /// Runs `body` and returns the lines with `diagnosticPrefix` that it
    /// wrote to standard output.
    ///
    /// Tests run in parallel, and a different test can print into the same
    /// capture. Only the diagnostic printers write lines with the prefix, so
    /// this keeps only those lines.
    ///
    /// - Parameter body: the call whose diagnostic lines to capture.
    /// - Returns: the captured lines that start with `diagnosticPrefix`, in
    ///   the order that `body` wrote them.
    /// - Throws: `StandardOutputCapture.CaptureError` when the capture fails.
    @MainActor
    private static func capturedDiagnosticLines(_ body: () -> Void) async throws -> [String] {
        let output = try await StandardOutputCapture.capture(body)
        return output
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.hasPrefix(diagnosticPrefix) }
    }

    @Test("printExampleDiagnostic gives the diagnostic to describe and prints its message with the diagnostic prefix")
    func printExampleDiagnosticPrintsTheMessageThatDescribeGives() async throws {
        let recorder = DiagnosticRecorder()

        let lines = try await Self.capturedDiagnosticLines {
            ExamplesSupport.printExampleDiagnostic(.embeddingUnavailable) { diagnostic in
                recorder.record(diagnostic)
                return Self.specialCaseMessage
            }
        }

        #expect(recorder.diagnostics == [.embeddingUnavailable])
        #expect(lines == [Self.diagnosticPrefix + Self.specialCaseMessage])
    }

    @Test("printExampleDiagnostic gives the diagnostic to describe and prints nothing when describe gives no message")
    func printExampleDiagnosticPrintsNothingWhenDescribeGivesNoMessage() async throws {
        let recorder = DiagnosticRecorder()

        let lines = try await Self.capturedDiagnosticLines {
            ExamplesSupport.printExampleDiagnostic(Self.duplicateIdDiagnostic) { diagnostic in
                recorder.record(diagnostic)
                return nil
            }
        }

        // `MetadataDiagnostic.log(_:)` writes to os.Logger, not to stdout.
        // `DiagnosticsTests` examines that log. Here, the branch that logs
        // must not print a line with the diagnostic prefix.
        #expect(recorder.diagnostics == [Self.duplicateIdDiagnostic])
        #expect(lines.isEmpty)
    }

    @Test("SemanticSearch's printDiagnostic prints its own message for embeddingUnavailable")
    func semanticSearchPrintDiagnosticPrintsTheEmbeddingUnavailableMessage() async throws {
        let lines = try await Self.capturedDiagnosticLines {
            SemanticSearchCore.printDiagnostic(.embeddingUnavailable)
        }

        #expect(
            lines == [
                Self.diagnosticPrefix
                    + "embeddingUnavailable: no embedder configured; degrading to keyword-only (BM25 + trigram).",
            ],
        )
    }

    @Test("SemanticSearch's printDiagnostic prints nothing to stdout for every other diagnostic")
    func semanticSearchPrintDiagnosticPrintsNothingForOtherDiagnostics() async throws {
        let lines = try await Self.capturedDiagnosticLines {
            SemanticSearchCore.printDiagnostic(Self.duplicateIdDiagnostic)
        }

        // The closure gives no message for `.duplicateId`, so the diagnostic
        // goes to `MetadataDiagnostic.log(_:)` and not to stdout.
        #expect(lines.isEmpty)
    }
}
