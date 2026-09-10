/// The catalog contract every domain conforms its metadata to (plan.md §4):
/// a stable, unique `id` and a `renderBlock()` that renders the item to the
/// text that IS its search surface. `MetadataIndex` indexes, retrieves, and
/// seeds sessions with that rendered text and **never interprets it** — YAML
/// for skills, TS+JSDoc for tools, frontmatter summaries for agents all look
/// the same to `FoundationModelsMetadataRegistry`.
///
/// Four jobs read an item's text, and each one has a method of its own:
/// `renderBlock()` is what a `Match` carries back verbatim,
/// `renderIndexedText(from:)` what the keyword signals tokenize,
/// `renderEmbeddedText(from:)` what the embedder embeds, and
/// `renderSummaryBlock()` what the selection tier's prefix is seeded with.
/// The last three all default to the block, so a domain that wants one text
/// for everything writes `renderBlock()` alone; a domain that wants the
/// keyword signals or the embedder to read something shorter, or something
/// spelled differently, overrides that one method and leaves the verbatim
/// block whole.
public protocol SearchableMetadata: Sendable {
    /// A stable id, unique within one catalog — the join key across every
    /// tier: the BM25 `id` field, the trigram target, the selection-enum
    /// member, and the verbatim-lookup key back to this item (plan.md §4).
    var id: String { get }

    /// Renders this item to the text that IS its search surface: what a
    /// matched `Match` carries back verbatim, and the text every other
    /// render method here defaults to. The package never parses this text.
    func renderBlock() -> String

    /// Renders the text the keyword signals read: what `MetadataIndex`
    /// tokenizes for BM25 and trigrams as this item's body field.
    ///
    /// Defaults to `block`, so a domain that overrides nothing has one text
    /// for every job, exactly as before this method existed. Override it to
    /// rank on something other than the whole block — a shorter text, or one
    /// spelled for a query rather than for a reader — without touching the
    /// verbatim block a `Match` hands the model.
    ///
    /// - Parameter block: this item's `renderBlock()` output, already
    ///   rendered. Taking it as a parameter is what lets an override derive
    ///   from the block, and lets `MetadataIndex` render the block one time
    ///   for all three texts.
    /// - Returns: the text to tokenize for this item's keyword signals.
    func renderIndexedText(from block: String) -> String

    /// Renders the text the embedder embeds: what `MetadataIndex` sends to
    /// `TextEmbedding.embed(_:)` for this item's stored vector.
    ///
    /// Defaults to `block`, so a domain that overrides nothing has one text
    /// for every job, exactly as before this method existed. Override it to
    /// embed something shorter than the whole block — the embed batch is the
    /// one part of index-build that may call out to a model, so its size is
    /// the caller's to choose — without touching the verbatim block a
    /// `Match` hands the model.
    ///
    /// Embedding reuse keys on this text (plan.md §8): changing it alone
    /// re-embeds the entry, and leaving it alone reuses the stored vector
    /// however the rest of the item changed.
    ///
    /// - Parameter block: this item's `renderBlock()` output, already
    ///   rendered, on the same terms as `renderIndexedText(from:)`.
    /// - Returns: the text to embed for this item.
    func renderEmbeddedText(from block: String) -> String

    /// Renders a (typically shorter) summary of this item, used to seed the
    /// selection tier's cached prefix (plan.md §4, §6) instead of the full
    /// `renderBlock()` — relevant for catalogs (e.g. MCP resources) whose
    /// full description is large. Defaults to `renderBlock()`.
    func renderSummaryBlock() -> String
}

public extension SearchableMetadata {
    /// The default `renderIndexedText(from:)`: the block itself, for domains
    /// that rank on their whole search surface.
    ///
    /// - Parameter block: this item's already-rendered block.
    /// - Returns: `block`, unchanged.
    func renderIndexedText(from block: String) -> String {
        block
    }

    /// The default `renderEmbeddedText(from:)`: the block itself, for domains
    /// that embed their whole search surface.
    ///
    /// - Parameter block: this item's already-rendered block.
    /// - Returns: `block`, unchanged.
    func renderEmbeddedText(from block: String) -> String {
        block
    }

    /// The default `renderSummaryBlock()`: identical to `renderBlock()`, for
    /// domains with no shorter summary to offer.
    func renderSummaryBlock() -> String {
        renderBlock()
    }
}
