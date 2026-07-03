/// Configuration for `MetadataSearcher`'s `.selection` tier (plan.md §6): how
/// selection sessions are created, what guidance seeds the assembled prefix,
/// and the capacity/candidate budgets that decide between the cached-root
/// (this task) and one-off (a later task) session paths.
///
/// Mirrors Multitool's own `Librarian` initializer parameters
/// (`capacityCharacterLimit`, `makeSession`), generalized into one value type
/// so `MetadataSearcher` can accept — or omit — a selection configuration
/// without a combinatorial explosion of initializer overloads.
public struct SelectionConfig: Sendable {
    /// A generous default capacity, in characters, approximating
    /// `ProfileDefinition`'s own default 8,192-token context budget at
    /// roughly 4 characters per token — identical to Multitool's own
    /// `Librarian.defaultCapacityCharacterLimit`.
    public static let defaultCapacityCharacterLimit = 32_000

    /// The default number of top-ranked candidates the over-budget path
    /// (plan.md §6, a later task) seeds its one-off session with.
    public static let defaultCandidateLimit = 24

    /// Creates a session seeded with the given instructions text — the seam
    /// `SelectionTier` drives both the cached root session (this task) and
    /// the over-budget one-off session (a later task) through. `@Sendable` so
    /// it can cross `SelectionTier`'s actor isolation boundary; production
    /// wires it to `RoutedLLM.makeGuidedSession(_:instructions:)`, already
    /// constrained to the current id-enum grammar
    /// (`SelectionTier.idEnumGrammar(ids:)`) — the same shape as Multitool's
    /// own `Librarian`'s `makeSession` parameter.
    public var model: @Sendable (String) -> any AgentSession

    /// The selection guidance prepended to every assembled prefix. Defaults
    /// to `.librarianDefault` — Multitool's own `Librarian.selectionGuidance`,
    /// verbatim.
    public var preamble: String

    /// The assembled prefix's character budget (preamble + every candidate's
    /// `renderSummaryBlock()`); at or under this, the cached-root +
    /// fork-per-call path runs. Negative values are clamped to `0`.
    public var capacityCharacterLimit: Int

    /// Over budget, how many top-ranked retrieval candidates seed the one-off
    /// session (plan.md §6; wired up in a later task). Negative values are
    /// clamped to `0`.
    public var candidateLimit: Int

    /// Creates a selection tier configuration.
    ///
    /// - Parameters:
    ///   - model: creates a session seeded with the given instructions text.
    ///   - preamble: the selection guidance prepended to every assembled
    ///     prefix. Defaults to `.librarianDefault`.
    ///   - capacityCharacterLimit: the assembled prefix's character budget.
    ///     Defaults to `defaultCapacityCharacterLimit`.
    ///   - candidateLimit: the over-budget top-M candidate count. Defaults to
    ///     `defaultCandidateLimit`.
    public init(
        model: @escaping @Sendable (String) -> any AgentSession,
        preamble: String = .librarianDefault,
        capacityCharacterLimit: Int = SelectionConfig.defaultCapacityCharacterLimit,
        candidateLimit: Int = SelectionConfig.defaultCandidateLimit
    ) {
        self.model = model
        self.preamble = preamble
        self.capacityCharacterLimit = max(0, capacityCharacterLimit)
        self.candidateLimit = max(0, candidateLimit)
    }
}

extension String {
    /// The curated selection guidance every `SelectionConfig` defaults its
    /// `preamble` to — Multitool's shipped `Librarian.selectionGuidance`
    /// (`Librarian.swift:41-45`), lifted verbatim: "fewest that suffice, in
    /// call order when order matters."
    public static let librarianDefault: String = """
        You are an API librarian. Given a task, return ONLY the functions needed — fewest
        that suffice, in call order when order matters. Do not invent functions; return an
        empty list if nothing fits.
        """
}
