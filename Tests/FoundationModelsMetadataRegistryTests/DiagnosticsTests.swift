import Foundation
@testable import FoundationModelsMetadataRegistry
import OSLog
import Testing

/// Tests for `MetadataDiagnostic.init(_:)`, which maps each case of
/// FoundationModelsRanker's `RankDiagnostic` to the case of
/// `MetadataDiagnostic` that has the same name, and for
/// `MetadataDiagnostic.log(_:)`, which writes each case to the `os.Logger` of
/// the package.
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

    /// The catalog id that `log(_:)` writes for `.duplicateId`. The value is
    /// unique in the test suite, so no other test writes a log entry that
    /// holds it.
    static let duplicateId = "diagnostics-tests-duplicate-id"

    /// The id that `log(_:)` writes for `.unknownSelectedId`. The value is
    /// unique in the test suite, so no other test writes a log entry that
    /// holds it.
    static let loggedUnknownId = "diagnostics-tests-unknown-id"

    /// The number of catalog items that have no embedding yet. This value is
    /// different from `total`, so a message that swaps the two values makes
    /// the test fail.
    static let pending = 7

    /// The number of catalog items in the catalog that is catching up.
    static let total = 31

    /// The subsystem of the `os.Logger` that `log(_:)` writes to.
    static let logSubsystem = "FoundationModelsMetadataRegistry"

    /// The category of the `os.Logger` that `log(_:)` writes to.
    static let logCategory = "MetadataDiagnostic"

    /// Each `RankDiagnostic` case, with the `MetadataDiagnostic` that
    /// `init(_:)` must make from it.
    static let mappings: [(RankDiagnostic, MetadataDiagnostic)] = [
        (.retrievalCut(considered: considered, kept: kept), .retrievalCut(considered: considered, kept: kept)),
        (.embeddingUnavailable, .embeddingUnavailable),
        (.unknownSelectedId(id: unknownId), .unknownSelectedId(id: unknownId)),
    ]

    /// One value of each `MetadataDiagnostic` case, in the order of
    /// `CaseName.allCases`, with a text that the log entry for that value
    /// must hold.
    static let loggedMessages: [(MetadataDiagnostic, String)] = [
        (.duplicateId(id: duplicateId), "duplicate id \"\(duplicateId)\""),
        (.embeddingUnavailable, "results are keyword-only"),
        (.unknownSelectedId(id: loggedUnknownId), "unknown id \"\(loggedUnknownId)\""),
        (.retrievalCut(considered: considered, kept: kept), "from \(considered) to \(kept)"),
        (.embedCatchUp(pending: pending, total: total), "\(pending)/\(total) item(s) pending"),
    ]

    /// The name of each `MetadataDiagnostic` case, in the order of the
    /// declaration.
    enum CaseName: CaseIterable {
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

    /// Reads the messages that the `os.Logger` of the package wrote in this
    /// process at `start` or later.
    ///
    /// - Parameter start: the earliest time of an entry to read.
    /// - Returns: the composed message of each entry, oldest first.
    static func messagesInLogStore(since start: Date) throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let predicate = NSPredicate(format: "subsystem == %@ AND category == %@", logSubsystem, logCategory)
        let entries = try store.getEntries(at: store.position(date: start), matching: predicate)
        return entries.compactMap { ($0 as? OSLogEntryLog)?.composedMessage }
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
        #expect(Self.loggedMessages.map { CaseName(of: $0.0) } == CaseName.allCases)
    }

    /// `log(_:)` writes each case to the `os.Logger` of the package, and the
    /// entry holds the associated values of the case. The test reads the
    /// `OSLogStore` one time for all the cases, because each read takes some
    /// seconds, and parallel reads in one process are not stable.
    @Test
    func logWritesEachCaseToTheLogStore() throws {
        let start = Date()
        for (diagnostic, _) in Self.loggedMessages {
            MetadataDiagnostic.log(diagnostic)
        }

        let messages = try Self.messagesInLogStore(since: start)

        for (diagnostic, expectedText) in Self.loggedMessages {
            #expect(messages.contains { $0.contains(expectedText) }, "no log entry for \(diagnostic)")
        }
    }
}
