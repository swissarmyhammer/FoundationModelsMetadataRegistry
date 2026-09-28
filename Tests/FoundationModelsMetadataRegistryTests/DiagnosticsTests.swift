@testable import FoundationModelsMetadataRegistry
import Logging
import TelemetryTestSupport
import Testing

/// Tests for `MetadataDiagnostic.init(_:)`, which maps each case of
/// FoundationModelsRanker's `RankDiagnostic` to the case of
/// `MetadataDiagnostic` that has the same name, and for
/// `MetadataDiagnostic.log(_:)`, which writes each case to the swift-log
/// logger of the package.
///
/// The `log(_:)` tests read the log records through `TelemetryCapture` of
/// FoundationModelsExtras. No test here bootstraps the logging system: the
/// capture does that one time for the process.
struct DiagnosticsTests {
    // MARK: - Fixtures

    /// The number of candidates that the retrieval cut examined.
    static let considered = 40

    /// The number of candidates that the retrieval cut kept. This value is
    /// different from `considered`, so a mapping that swaps the two values
    /// makes the test fail.
    static let kept = 12

    /// The id that the selection model returned and the catalog does not hold.
    static let unknownId = "x"

    /// The catalog id that `log(_:)` writes for `.duplicateId`.
    static let duplicateId = "diagnostics-tests-duplicate-id"

    /// The id that `log(_:)` writes for `.unknownSelectedId`.
    static let loggedUnknownId = "diagnostics-tests-unknown-id"

    /// The number of catalog items that have no embedding yet. This value is
    /// different from `total`, so a message that swaps the two values makes
    /// the test fail.
    static let pending = 7

    /// The number of catalog items in the catalog that is catching up.
    static let total = 31

    /// The label of the logger that `log(_:)` writes to.
    static let loggerLabel = "FoundationModelsMetadataRegistry.MetadataDiagnostic"

    /// Each `RankDiagnostic` case, with the `MetadataDiagnostic` that
    /// `init(_:)` must make from it.
    static let mappings: [(RankDiagnostic, MetadataDiagnostic)] = [
        (.retrievalCut(considered: considered, kept: kept), .retrievalCut(considered: considered, kept: kept)),
        (.embeddingUnavailable, .embeddingUnavailable),
        (.unknownSelectedId(id: unknownId), .unknownSelectedId(id: unknownId)),
    ]

    /// One diagnostic, with what the log record of `log(_:)` for it must
    /// hold.
    struct ExpectedRecord {
        /// The diagnostic to log.
        let diagnostic: MetadataDiagnostic

        /// A text that the message of the record must hold.
        let messageText: String

        /// The metadata values of the record other than the case name.
        let values: Logger.Metadata

        /// The full metadata of the record: ``values``, and the name of the
        /// case of ``diagnostic`` under the case-name key.
        var metadata: Logger.Metadata {
            let caseName = CaseName(of: diagnostic).rawValue
            return values.merging([RegistryTelemetry.MetadataKey.diagnosticCase: .string(caseName)]) { $1 }
        }
    }

    /// One log record of a telemetry capture.
    struct CapturedRecord {
        /// The level of the record.
        let level: Logger.Level

        /// The message of the record.
        let message: String

        /// The metadata of the record.
        let metadata: Logger.Metadata
    }

    /// One value of each `MetadataDiagnostic` case, in the order of
    /// `CaseName.allCases`, with what its log record must hold.
    static let loggedMessages: [ExpectedRecord] = [
        ExpectedRecord(
            diagnostic: .duplicateId(id: duplicateId),
            messageText: "duplicate id \"\(duplicateId)\"",
            values: [RegistryTelemetry.MetadataKey.catalogId: .string(duplicateId)],
        ),
        ExpectedRecord(diagnostic: .embeddingUnavailable, messageText: "results are keyword-only", values: [:]),
        ExpectedRecord(
            diagnostic: .unknownSelectedId(id: loggedUnknownId),
            messageText: "unknown id \"\(loggedUnknownId)\"",
            values: [RegistryTelemetry.MetadataKey.catalogId: .string(loggedUnknownId)],
        ),
        ExpectedRecord(
            diagnostic: .retrievalCut(considered: considered, kept: kept),
            messageText: "from \(considered) to \(kept)",
            values: [
                RegistryTelemetry.MetadataKey.retrievalConsidered: .stringConvertible(considered),
                RegistryTelemetry.MetadataKey.retrievalKept: .stringConvertible(kept),
            ],
        ),
        ExpectedRecord(
            diagnostic: .embedCatchUp(pending: pending, total: total),
            messageText: "\(pending)/\(total) item(s) pending",
            values: [
                RegistryTelemetry.MetadataKey.embedPendingCount: .stringConvertible(pending),
                RegistryTelemetry.MetadataKey.catalogSize: .stringConvertible(total),
            ],
        ),
    ]

    /// Each diagnostic whose metadata the key-spelling test examines, with
    /// the full metadata of its log record. The keys are written out here,
    /// and not read from ``RegistryTelemetry/MetadataKey``, so a change to
    /// the spelling of a key makes the test fail.
    static let spelledOutMetadata: [(MetadataDiagnostic, Logger.Metadata)] = [
        (
            .embedCatchUp(pending: pending, total: total),
            [
                "diagnostic.case": "embedCatchUp",
                "embed.pending_count": .stringConvertible(pending),
                "catalog.size": .stringConvertible(total),
            ],
        ),
        (
            .duplicateId(id: duplicateId),
            [
                "diagnostic.case": "duplicateId",
                "catalog.id": .string(duplicateId),
            ],
        ),
    ]

    /// The name of each `MetadataDiagnostic` case, in the order of the
    /// declaration. The raw value is the value of the `diagnostic.case`
    /// metadata key.
    enum CaseName: String, CaseIterable {
        case duplicateId
        case embeddingUnavailable
        case unknownSelectedId
        case retrievalCut
        case embedCatchUp

        /// Makes the name of the case of `diagnostic`. The switch has no
        /// `default`, so a new `MetadataDiagnostic` case stops the compile
        /// until this enum holds it.
        ///
        /// - Parameter diagnostic: the diagnostic to name.
        init(of diagnostic: MetadataDiagnostic) {
            switch diagnostic {
            case .duplicateId:
                self = .duplicateId
            case .embeddingUnavailable:
                self = .embeddingUnavailable
            case .unknownSelectedId:
                self = .unknownSelectedId
            case .retrievalCut:
                self = .retrievalCut
            case .embedCatchUp:
                self = .embedCatchUp
            }
        }
    }

    // MARK: - Helpers

    /// Logs each diagnostic of `diagnostics` inside a new telemetry capture.
    ///
    /// - Parameter diagnostics: the diagnostics to log, in order.
    /// - Returns: the log records of the capture, in the order of the calls.
    static func logRecords(of diagnostics: [MetadataDiagnostic]) async throws -> [CapturedRecord] {
        try await TelemetryCapture.run(forbidding: []) { context in
            for diagnostic in diagnostics {
                MetadataDiagnostic.log(diagnostic)
            }
            return context.logRecords.map { entry in
                CapturedRecord(level: entry.level, message: "\(entry.message)", metadata: entry.metadata)
            }
        }
    }

    // MARK: - Tests

    /// `init(_:)` maps each `RankDiagnostic` case to the same-named
    /// `MetadataDiagnostic` case, and keeps each associated value in its
    /// own position.
    @Test(arguments: mappings)
    func mapsEachRankDiagnosticToTheSameNamedCase(rank: RankDiagnostic, expected: MetadataDiagnostic) {
        #expect(MetadataDiagnostic(rank) == expected)
    }

    /// `loggedMessages` holds one value of each `MetadataDiagnostic` case, so
    /// the `log(_:)` test examines each case.
    @Test
    func loggedMessagesHoldEachCaseOneTime() {
        #expect(Self.loggedMessages.map { CaseName(of: $0.diagnostic) } == CaseName.allCases)
    }

    /// `log(_:)` writes through the logger that
    /// `RegistryTelemetry.makeLogger()` makes, and that logger has the label
    /// of the diagnostics. A record of the capture does not hold the label of
    /// its logger, so the test reads the label from that logger.
    @Test
    func registryLoggerHasTheDiagnosticsLabel() {
        #expect(RegistryTelemetry.makeLogger().label == Self.loggerLabel)
    }

    /// `log(_:)` writes one `.notice` record for each case. The message holds
    /// the associated values of the case, and the metadata holds the case
    /// name and each associated value under its own key.
    @Test
    func logWritesEachCaseToTheLogger() async throws {
        let records = try await Self.logRecords(of: Self.loggedMessages.map(\.diagnostic))

        #expect(records.count == Self.loggedMessages.count)
        for (record, expected) in zip(records, Self.loggedMessages) {
            #expect(record.level == .notice, "wrong level for \(expected.diagnostic)")
            #expect(record.message.contains(expected.messageText), "wrong message for \(expected.diagnostic)")
            #expect(record.metadata == expected.metadata, "wrong metadata for \(expected.diagnostic)")
        }
    }

    /// The metadata of a log record holds each value under the key that the
    /// telemetry vocabulary spells, so a backend can query the value without
    /// a parse of the message.
    @Test(arguments: spelledOutMetadata)
    func logPutsEachValueInItsOwnMetadataKey(diagnostic: MetadataDiagnostic, expected: Logger.Metadata) async throws {
        let records = try await Self.logRecords(of: [diagnostic])

        #expect(records.map(\.metadata) == [expected])
    }
}
