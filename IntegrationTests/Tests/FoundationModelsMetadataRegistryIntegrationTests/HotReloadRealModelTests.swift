import FoundationModelsMetadataRegistry
import Testing
import os

/// The second scenario in this package that drives Apple Intelligence, and the
/// one that covers a seam FoundationModelsRanker's own suite cannot reach:
/// `MetadataSearcher.update(items:)` rebuilding the selection tier over a
/// changed catalog, with a real model then selecting from the rebuilt one.
///
/// **Why this seam is ours.** Ranker's four real-model tests drive its own
/// `Searcher` facade and its own neutral `.selectionDefault` preamble, and that
/// facade has no hot reload — none of them calls `update(items:)`. The rebuild
/// measured here is this package's, over this package's `MetadataIndex`
/// conformance to `SelectionCatalog`, with this package's `.librarianDefault`.
///
/// **The defect this guards.** `update(items:)` rebuilds the whole selection
/// tier on a content change, and that rebuild is what drops the tier's cached
/// root session and re-assembles its prefix from the new catalog. A rebuild
/// that failed to happen would leave the previous root answering: a newly
/// added id would stay unreachable, and — the half that matters — a deleted id
/// would keep coming back from a prefix that still lists it. `MetadataSearcher`'s
/// own unit suite can assert that the index changed; only a real model reading
/// a re-assembled prefix can show that the model no longer sees the old
/// catalog.
///
/// **The remove half is the load-bearing one.** The add half can be satisfied
/// by a tier that merely widened its id set. Only the remove half proves a
/// stale cached root stopped answering, so it is the assertion this suite is
/// written around.
///
/// **Scope.** The under-budget cached-root path only. Five one-line fixture
/// entries assemble a prefix of a few hundred characters against
/// `SelectionConfig.defaultCapacityCharacterLimit` of 32,000, so no query here
/// reaches the over-budget one-off path — see `IntegrationCatalog`'s own note
/// on the budget. No embed catch-up and no cosine assertion either: this
/// package ships no real embedder, so `update(items:)` returns straight after
/// the tier rebuild, and FoundationModels exposes no embedding API to wire one
/// from.
///
/// The package's deployment floor is macOS 27 already, so no redundant
/// `@available` attribute is needed — Swift Testing's `@Suite`/`@Test` macros
/// reject one on the type.
@Suite("Hot reload against the real model")
struct HotReloadRealModelTests {
    /// The catalog the searcher is built over: `IntegrationCatalog.base`
    /// beside the entry the reload drops.
    ///
    /// `IntegrationCatalog` reserves `removeOnly` for exactly this and names
    /// this composition itself, so the id whose disappearance is the
    /// measurement can appear in no other scenario's starting catalog.
    static let startingCatalog: [IntegrationItem] = IntegrationCatalog.base + [IntegrationCatalog.removeOnly]

    /// The catalog `update(items:)` reloads to: `IntegrationCatalog.base`
    /// beside the entry the reload adds, with `removeOnly` gone.
    ///
    /// One reload therefore carries both halves at once — an id arrives and an
    /// id leaves — so each half measures the same single rebuild rather than a
    /// rebuild of its own.
    static let reloadedCatalog: [IntegrationItem] = IntegrationCatalog.base + [IntegrationCatalog.addOnly]

    /// The intent that reads the added id back, used verbatim from `^nwt7nz4`.
    ///
    /// It returned `sharpenSkates` on 5 of 5 runs against `reloadedCatalog`
    /// when this suite was written. This is a measured intent, not an
    /// illustrative one: an intent substituted here without its own
    /// measurement would put an unmeasured claim in a suite whose whole value
    /// is that every claim in it was measured first.
    static let addIntent = "Sharpen my dull hockey skate blades."

    /// The intent that reads the removed id back, used verbatim from
    /// `^nwt7nz4`.
    ///
    /// `^nwt7nz4` measured this one from both sides, and the pair is what
    /// makes the remove half load-bearing rather than vacuous: against
    /// `startingCatalog` it found `dyeWool` on 5 of 5 runs, and against
    /// `reloadedCatalog` it returned nothing on 5 of 5 runs. The same words
    /// that reliably reach the entry while it is present reliably reach
    /// nothing once it is gone, so an assertion that the entry did not come
    /// back is one the tier can genuinely fail.
    static let removeIntent = "Dye this fleece yarn with indigo."

    /// A hot reload that adds an id makes that id selectable.
    ///
    /// - Throws: the availability gate's expectation failure on a machine that
    ///   cannot serve Apple Intelligence, an environment fault the model
    ///   raised after that gate passed, or whatever the selection tier itself
    ///   threw.
    @Test("a hot reload makes the added id selectable")
    func aHotReloadMakesTheAddedIdSelectable() async throws {
        let answer = try await Self.searchAfterHotReload(for: Self.addIntent)

        #expect(
            answer.ids.contains(IntegrationCatalog.addOnly.id),
            """
            the search for "\(Self.addIntent)" answered with \(Self.clause(from: answer.ids)), which does \
            not include \(IntegrationCatalog.addOnly.id) — the id `update(items:)` added. The \
            selection tier is still answering from a prefix assembled over the catalog this \
            searcher was initialized with, so the rebuild on `update(items:)`'s content-change \
            branch did not reach it. The same intent returned that id on 5 of 5 runs against the \
            reloaded catalog when this suite was written.
            """
        )

        SelectionScenario.expectNoUnknownSelectedId(among: answer.diagnostics, answering: Self.addIntent)
    }

    /// A hot reload that drops an id makes that id unreachable — the
    /// load-bearing half.
    ///
    /// - Throws: the availability gate's expectation failure on a machine that
    ///   cannot serve Apple Intelligence, an environment fault the model
    ///   raised after that gate passed, or whatever the selection tier itself
    ///   threw.
    @Test("a hot reload makes the removed id unreachable")
    func aHotReloadMakesTheRemovedIdUnreachable() async throws {
        let answer = try await Self.searchAfterHotReload(for: Self.removeIntent)

        #expect(
            !answer.ids.contains(IntegrationCatalog.removeOnly.id),
            """
            the search for "\(Self.removeIntent)" answered with \(IntegrationCatalog.removeOnly.id), which \
            `update(items:)` removed from the catalog. A stale cached root session is still \
            answering from a prefix that lists the deleted entry. This is the exact symptom this \
            suite guards: the same intent found that id on 5 of 5 runs while it was present, and \
            returned nothing on 5 of 5 runs against the reloaded catalog.
            """
        )

        SelectionScenario.expectNoUnknownSelectedId(among: answer.diagnostics, answering: Self.removeIntent)
    }

    /// Drives `intent` through a searcher hot-reloaded from `startingCatalog`
    /// to `reloadedCatalog`.
    ///
    /// This is the whole path under test, and both halves share it. The
    /// searcher is built over the **starting** catalog and only then reloaded,
    /// so `update(items:)` runs against a live searcher — constructing a
    /// second searcher over `reloadedCatalog` instead would exercise the
    /// initializer, which rebuilds nothing and is not the path this suite
    /// measures.
    ///
    /// The searcher answers exactly one query afterwards, so nothing here
    /// depends on whether a reused searcher would be warm.
    ///
    /// - Parameter intent: the plain-language intent to search the reloaded
    ///   catalog for.
    /// - Returns: the ids the search answered with, and every diagnostic the
    ///   searcher reported while building, reloading, and answering.
    /// - Throws: the availability gate's expectation failure on a machine that
    ///   cannot serve Apple Intelligence, an environment fault the model
    ///   raised after that gate passed, or whatever the selection tier itself
    ///   threw.
    private static func searchAfterHotReload(
        for intent: String
    ) async throws -> (ids: [String], diagnostics: [MetadataDiagnostic]) {
        try ModelAvailability.requireAvailable()

        let recorded = OSAllocatedUnfairLock<[MetadataDiagnostic]>(initialState: [])
        let searcher = SelectionScenario.makeSearcher(over: startingCatalog, reporting: recorded)
        await searcher.update(items: reloadedCatalog)

        let matches = try await ModelAvailability.recordingEnvironmentFaults {
            // Bound to the reloaded catalog, so the cap can never be the reason
            // an expected id is missing from the answer.
            try await searcher.search(intent: intent, limit: reloadedCatalog.count)
        }
        return (matches.map(\.id), recorded.withLock { $0 })
    }

    /// Renders `ids` as one comma-separated clause for a failure message.
    ///
    /// - Parameter ids: the ids a search answered with.
    /// - Returns: the ids joined in the order they were returned, or `nothing`
    ///   when the search answered with none — the empty answer is the shape
    ///   worth naming in words rather than leaving as a blank in the text.
    private static func clause(from ids: [String]) -> String {
        ids.isEmpty ? "nothing" : ids.joined(separator: ", ")
    }
}
