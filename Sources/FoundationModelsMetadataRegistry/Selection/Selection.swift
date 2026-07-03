import FoundationModels

/// The selection tier's guided-generation output (plan.md §6, decision #4):
/// **ids only, never blocks** — the model picks from the current candidate id
/// enum (`SelectionTier.idEnumGrammar(ids:)` constrains it structurally), and
/// `SelectionTier` maps the returned ids back through the catalog to verbatim
/// `Match`es afterward. This supersedes Multitool's `FoundAPIs` shape (which
/// had the model reproduce each function's fields); here the model is never
/// asked to reproduce a block, only to choose among ids.
@Generable
public struct Selection: Sendable, Equatable {
    /// The selected ids — fewest that suffice, in call order when order
    /// matters (the selection guidance's own phrasing, `SelectionConfig
    /// .librarianDefault`); empty when nothing in the candidate set fits the
    /// intent.
    @Guide(
        description: "the selected ids, fewest that suffice, in call order when order "
            + "matters; empty if nothing in the candidate set fits the intent."
    )
    public var ids: [String]

    /// Creates a selection result.
    ///
    /// Explicit for the same reason as this package's other public struct
    /// initializers (e.g. `Match.init`): a `public` struct's synthesized
    /// memberwise initializer is only `internal`-accessible.
    ///
    /// - Parameter ids: the selected ids.
    public init(ids: [String]) {
        self.ids = ids
    }
}
