extension String {
    /// The curated API-librarian selection guidance this package's selection
    /// call sites pass as `SelectionConfig.preamble` — Multitool's shipped
    /// `Librarian.selectionGuidance`, lifted verbatim: "fewest that suffice,
    /// in call order when order matters."
    ///
    /// FoundationModelsRanker's `SelectionConfig` defaults its `preamble` to
    /// the neutral `.selectionDefault` ("items"/"ids" wording, no API-surface
    /// language); this constant is kept here so callers whose catalog *is* an
    /// API surface can opt into the original librarian prompt text
    /// explicitly, unchanged by the selection-tier migration.
    public static let librarianDefault: String = """
        You are an API librarian. Given a task, return ONLY the functions needed — fewest
        that suffice, in call order when order matters. Do not invent functions; return an
        empty list if nothing fits.
        """
}
