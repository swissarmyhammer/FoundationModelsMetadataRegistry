import FoundationModelsMetadataRegistry
import Testing
import os

/// The first scenario in this package that drives Apple Intelligence: a **cold**
/// `MetadataSearcher` in `.selection` mode answers a plain-language intent, and
/// every id it answers with is one the catalog really holds.
///
/// **The defect this guards.** A selection tier that has never spoken to its
/// model has no cached root session and no prefilled prefix, so its first call
/// is the one that can come back `{"ids":[]}` — the shape
/// `.librarianDefault`'s own "return an empty list if nothing fits" invites.
/// FoundationModelsRanker measured that answer against its neutral
/// `.selectionDefault`; `^nwt7nz4` measured 125 cold runs against
/// `.librarianDefault` here and did not reproduce it, so this suite is a guard
/// rather than a reproduction. An empty result is nonetheless the exact symptom
/// to watch, and the off-topic control below is why asserting against it means
/// something.
///
/// **Why every query builds its own searcher.** `LanguageModelSession.fork()`
/// returns `self` (FoundationModelsRanker's `LanguageModelSessionSupport.swift`),
/// so a searcher reused across the parameterized run is warm from its second
/// call onward: its transcript already carries the assembled prefix and one
/// answered turn. A warm searcher cannot see a cold-session defect at all, and a
/// suite of warm queries would report green whatever the first call does. The
/// searcher is therefore constructed **inside the test body**, once per intent.
/// The synchronous initializer makes that cost nothing but an index rebuild over
/// four one-line entries.
///
/// **Scope.** The under-budget cached-root path only. Six one-line fixture
/// entries assemble a prefix of a few hundred characters against
/// `SelectionConfig.defaultCapacityCharacterLimit` of 32,000, so no query here
/// reaches the over-budget one-off path — see `IntegrationCatalog`'s own note on
/// the budget.
///
/// The package's deployment floor is macOS 27 already, so no redundant
/// `@available` attribute is needed — Swift Testing's `@Suite`/`@Test` macros
/// reject one on the type.
@Suite("Cold selection against the real model")
struct ColdSelectionRealModelTests {
    /// The intents this suite drives, used verbatim from `^nwt7nz4`.
    ///
    /// Each one scored **5/5 across three independent replications** of five
    /// cold runs against `IntegrationCatalog.base`, and the set is two
    /// imperatives beside two interrogatives on purpose: the worry that opened
    /// that measurement was that an imperative would draw the empty answer, and
    /// a set of interrogatives alone could not have shown otherwise.
    ///
    /// These are measured intents, not illustrative ones. An intent added here
    /// without its own cold-run measurement would put an unmeasured claim in a
    /// suite whose whole value is that every claim in it was measured first.
    ///
    /// The measurement's own off-topic control — `Rebuild the transmission on a
    /// diesel truck.` — returned empty on 5 of 5 cold runs, which is what makes
    /// the non-empty assertion below a real one rather than one the tier could
    /// not fail.
    static let measuredIntents: [String] = [
        "Pull me a shot of espresso from ground beans.",
        "Fold a sheet of paper into a crane.",
        "How do I tune my guitar to concert pitch?",
        "How often should I water a potted orchid?",
    ]

    /// Drives one measured intent through a searcher built for it alone, and
    /// holds the two observables that can genuinely change.
    ///
    /// - Parameter intent: one of `measuredIntents`.
    /// - Throws: the availability gate's expectation failure on a machine that
    ///   cannot serve Apple Intelligence, an environment fault the model raised
    ///   after that gate passed, or whatever the selection tier itself threw.
    @Test(
        "a cold selection search answers a measured intent with catalog ids alone",
        arguments: measuredIntents
    )
    func coldSelectionAnswersAMeasuredIntentWithCatalogIdsAlone(intent: String) async throws {
        try ModelAvailability.requireAvailable()

        // Bound once: the same value seeds the searcher, caps the result, and
        // names the ids the answer is checked against, so no two of those three
        // can drift apart. Pointing it at an empty catalog is also how the
        // non-empty assertion below was proved able to fail.
        let catalog = IntegrationCatalog.base
        let recorded = OSAllocatedUnfairLock<[MetadataDiagnostic]>(initialState: [])
        // Built here, per query. See the suite's note on why a reused searcher
        // would be warm and could not see the defect this scenario guards.
        let searcher = SelectionScenario.makeSearcher(over: catalog, reporting: recorded)

        let matches = try await ModelAvailability.recordingEnvironmentFaults {
            try await searcher.search(intent: intent, limit: catalog.count)
        }

        #expect(
            !matches.isEmpty,
            """
            the cold selection search for "\(intent)" returned nothing, which is the exact \
            symptom this scenario guards: a selection tier that has never spoken to its model \
            answering with the empty list its preamble offers. The same intent returned a \
            catalog id on 15 of 15 cold runs when this suite was written.
            """
        )

        let catalogIds = Set(catalog.map(\.id))
        let strangers = matches.map(\.id).filter { !catalogIds.contains($0) }.sorted().joined(separator: ", ")
        #expect(
            strangers.isEmpty,
            """
            the search for "\(intent)" returned \(strangers), which the catalog does not hold. \
            The selection tier filters an unresolvable id before it returns, so this assertion \
            is a cheap invariant rather than a live risk -- reaching it means that filter broke.
            """
        )

        SelectionScenario.expectNoUnknownSelectedId(among: recorded.withLock { $0 }, answering: intent)
    }
}
