@testable import FoundationModelsMetadataRegistry
import Testing

/// Tests for `MetadataDiagnostic.init(_:)`, which maps each case of
/// FoundationModelsRanker's `RankDiagnostic` to the case of
/// `MetadataDiagnostic` that has the same name.
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

    /// Each `RankDiagnostic` case, with the `MetadataDiagnostic` that
    /// `init(_:)` must make from it.
    static let mappings: [(RankDiagnostic, MetadataDiagnostic)] = [
        (.retrievalCut(considered: considered, kept: kept), .retrievalCut(considered: considered, kept: kept)),
        (.embeddingUnavailable, .embeddingUnavailable),
        (.unknownSelectedId(id: unknownId), .unknownSelectedId(id: unknownId)),
    ]

    // MARK: - Tests

    /// `init(_:)` maps each `RankDiagnostic` case to the same-named
    /// `MetadataDiagnostic` case, and keeps each associated value in its
    /// own position.
    @Test(arguments: mappings)
    func mapsEachRankDiagnosticToTheSameNamedCase(rank: RankDiagnostic, expected: MetadataDiagnostic) {
        #expect(MetadataDiagnostic(rank) == expected)
    }
}
