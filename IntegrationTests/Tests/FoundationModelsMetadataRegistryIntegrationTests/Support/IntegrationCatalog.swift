import FoundationModelsMetadataRegistry

/// One fixture entry: a stable id and the one-line block that IS its search
/// surface.
///
/// The minimum a catalog needs to satisfy `SearchableMetadata`. Nothing here
/// parses the block, so a plain stored string is the whole of it, and
/// `renderSummaryBlock()` keeps its protocol default: these blocks are already
/// a single line, so there is no shorter summary to offer.
struct IntegrationItem: SearchableMetadata {
    /// This entry's id — the value a scenario reads back out of a `Match` or a
    /// `Selection`, and the heading the selection tier writes above `block` in
    /// its assembled prefix.
    let id: String

    /// The one-line description this entry is retrieved and selected by.
    let block: String

    /// Renders this entry to its search surface, which is `block` verbatim.
    ///
    /// - Returns: `block`.
    func renderBlock() -> String { block }
}

/// The fixture every real-model scenario in this package ranks and selects
/// over.
///
/// **Three groups, and why the split is the fixture's whole design.** A
/// scenario proves something by reading the ids the model returned. That
/// reading is only sound while each group owns its vocabulary outright, so the
/// groups are written to share no term at all — not the subject matter, and not
/// the ordinary function words either, because `Tokenizer.tokenize(text:)`
/// removes no stop words. `IntegrationCatalogTests` measures that property, so
/// a later reword cannot quietly take it away.
///
/// - `base` is the catalog a scenario starts from.
/// - `addOnly` is reserved: it is in no starting catalog, so a scenario that
///   adds it can read its id back as proof that `update(items:)` made a new id
///   selectable.
/// - `removeOnly` is the mirror: a scenario starts with it beside `base` and
///   drops it, so the absence of its id is proof that the removal reached the
///   selection tier. Compose that starting catalog as `base + [removeOnly]`.
///
/// **The budget.** Six one-line entries assemble a prefix of a few hundred
/// characters, far under `SelectionConfig.defaultCapacityCharacterLimit`, so
/// every scenario stays on the under-budget cached-root-plus-fork path and none
/// of them measures the over-budget one-off path by accident. Keep it that way:
/// a fixture that grew past the limit would silently change what these
/// scenarios measure.
enum IntegrationCatalog {
    /// The catalog every scenario starts from: four entries whose subjects are
    /// as far apart as their wording.
    static let base: [IntegrationItem] = [
        IntegrationItem(
            id: "brewEspresso",
            block: "Pulls one espresso shot from finely ground arabica beans."
        ),
        IntegrationItem(
            id: "tuneGuitar",
            block: "Adjusts each guitar string until its pitch matches concert tuning."
        ),
        IntegrationItem(
            id: "waterOrchid",
            block: "Waters a potted orchid and mists its aerial roots."
        ),
        IntegrationItem(
            id: "foldOrigami",
            block: "Folds a square sheet of paper into an origami crane."
        ),
    ]

    /// The entry reserved for the add half of a hot-reload scenario: absent
    /// from every starting catalog, so its id can only come back after an
    /// `update(items:)` that put it in.
    static let addOnly = IntegrationItem(
        id: "sharpenSkates",
        block: "Hones dull hockey skate blades on the whetstone."
    )

    /// The entry reserved for the remove half of a hot-reload scenario: present
    /// in the starting catalog `base + [removeOnly]`, so its absence after an
    /// `update(items:)` that dropped it is the measurement.
    static let removeOnly = IntegrationItem(
        id: "dyeWool",
        block: "Steeps raw fleece yarn inside this indigo vat."
    )

    /// The three groups, each under the name a failure reports it by.
    ///
    /// The disjointness this fixture rests on is a property of the whole set
    /// rather than of any one group, so the groups are listed once here and
    /// compared pairwise from that list.
    static let groups: [(name: String, items: [IntegrationItem])] = [
        (name: "base", items: base),
        (name: "add-only", items: [addOnly]),
        (name: "remove-only", items: [removeOnly]),
    ]

    /// The set of distinct terms `items` are retrieved by.
    ///
    /// Tokenized with the same `Tokenizer` the retrieval tier indexes with, so
    /// the measurement is over the terms that really carry a match rather than
    /// over the raw words.
    ///
    /// - Parameter items: the entries to tokenize.
    /// - Returns: every term in those entries' blocks, deduplicated.
    static func vocabulary(of items: [IntegrationItem]) -> Set<String> {
        Set(items.flatMap { Tokenizer.tokenize(text: $0.renderBlock()) })
    }
}
