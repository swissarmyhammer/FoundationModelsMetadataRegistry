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
    /// it requires reasoning about task decomposition (plan.md §6). The
    /// selection tier lands in a later task — until then, requesting this
    /// mode throws `SelectionTierUnavailable`.
    case selection

    /// Selection when a model is configured, retrieval otherwise (plan.md
    /// §7's default). No selection tier is wired up yet, so `.auto` always
    /// falls back to `.retrieval` for now; once a selection tier lands,
    /// `.auto` starts choosing between the two the way plan.md describes.
    case auto
}
