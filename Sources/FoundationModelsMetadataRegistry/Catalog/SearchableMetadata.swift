/// The catalog contract every domain conforms its metadata to (plan.md §4):
/// a stable, unique `id` and a `renderBlock()` that renders the item to the
/// text that IS its search surface. `MetadataIndex` indexes, retrieves, and
/// seeds sessions with that rendered text and **never interprets it** — YAML
/// for skills, TS+JSDoc for tools, frontmatter summaries for agents all look
/// the same to `FoundationModelsMetadataRegistry`.
public protocol SearchableMetadata: Sendable {
    /// A stable id, unique within one catalog — the join key across every
    /// tier: the BM25 `id` field, the trigram target, the selection-enum
    /// member, and the verbatim-lookup key back to this item (plan.md §4).
    var id: String { get }

    /// Renders this item to the text that IS its search surface: what
    /// `MetadataIndex` tokenizes, trigrams, and embeds, and what a matched
    /// `Match` carries back verbatim. The package never parses this text.
    func renderBlock() -> String

    /// Renders a (typically shorter) summary of this item, used to seed the
    /// selection tier's cached prefix (plan.md §4, §6) instead of the full
    /// `renderBlock()` — relevant for catalogs (e.g. MCP resources) whose
    /// full description is large. Defaults to `renderBlock()`.
    func renderSummaryBlock() -> String
}

extension SearchableMetadata {
    /// The default `renderSummaryBlock()`: identical to `renderBlock()`, for
    /// domains with no shorter summary to offer.
    public func renderSummaryBlock() -> String { renderBlock() }
}
