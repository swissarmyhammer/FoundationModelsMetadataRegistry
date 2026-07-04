/// Which tier `MetadataSearcher.search(intent:limit:)` answers a query with
/// (plan.md §7).
public enum SearchMode: Sendable {
    /// Signals + RRF only — no session, no tokens. Cheap and fast: the whole
    /// story for an MCP resource picker, a UI typeahead, or Skills' "Spotlight
    /// RAG for large catalogs" idea. Answers in milliseconds with `signals`
    /// attached to every `Match`.
    case retrieval

    /// The LLM selects among candidates (the "librarian" behavior): intent-
    /// level matching that lexical/semantic ranking alone can't do, because
    /// it requires reasoning about task decomposition (plan.md §6).
    /// Requesting this mode without a configured selection tier
    /// (`MetadataSearcher.init(..., selection:)`) throws
    /// `SelectionTierUnavailable`.
    case selection

    /// Selection when a selection tier is configured, retrieval otherwise
    /// (plan.md §7's default).
    case auto
}
