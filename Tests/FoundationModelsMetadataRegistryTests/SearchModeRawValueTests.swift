import FoundationModelsMetadataRegistry
import Testing

/// The raw value of each `SearchMode` is the name that the span attribute
/// `search.mode` holds. The name is part of the observable surface of the
/// registry, so this suite keeps each name fixed.
@Suite("SearchMode raw value")
struct SearchModeRawValueTests {
    /// Each mode of the searcher, in the order of the declaration.
    static let modes: [SearchMode] = [.retrieval, .selection, .auto]

    /// The telemetry name of each mode of ``modes``, in the same order.
    static let names = ["retrieval", "selection", "auto"]

    @Test("The raw value of each mode is its telemetry name", arguments: zip(modes, names))
    func rawValueIsTheTelemetryName(mode: SearchMode, name: String) {
        #expect(mode.rawValue == name)
    }
}
