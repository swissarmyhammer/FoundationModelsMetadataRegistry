import Testing

/// The fixture's own invariant, measured without a model.
///
/// Every real-model scenario in this package reads a returned id as evidence
/// that the model understood an intent. That reading is only sound while each
/// fixture group owns its vocabulary outright: if the add-only item and the
/// base catalog shared even one term, an on-topic intent would have two
/// defensible answers and a green run would prove nothing about which one the
/// model chose. This suite holds that property, so a later edit to the fixture
/// text cannot quietly take it away.
@Suite("Integration catalog fixture")
struct IntegrationCatalogTests {
    /// Tokenizes every group's blocks and asserts the three vocabularies do
    /// not intersect.
    ///
    /// The non-empty check comes first on purpose: a group that tokenized to
    /// nothing would be disjoint from everything, so without it a fixture
    /// emptied by mistake would read as a pass.
    @Test("the base, add-only and remove-only groups share no vocabulary")
    func fixtureGroupVocabulariesAreDisjoint() {
        let groups = IntegrationCatalog.groups
        let vocabularies = groups.map { IntegrationCatalog.vocabulary(of: $0.items) }

        for index in groups.indices {
            #expect(
                !vocabularies[index].isEmpty,
                """
                the \(groups[index].name) fixture group tokenized to no terms at all, \
                so the disjointness this suite measures would hold vacuously
                """
            )
        }

        for firstIndex in groups.indices {
            for secondIndex in groups.indices where secondIndex > firstIndex {
                let shared = vocabularies[firstIndex]
                    .intersection(vocabularies[secondIndex])
                    .sorted()
                    .joined(separator: ", ")
                #expect(
                    shared.isEmpty,
                    """
                    the \(groups[firstIndex].name) and \(groups[secondIndex].name) fixture groups \
                    share \(shared) — an intent that lands on a shared term has more than one \
                    defensible answer, so reword one group until the two vocabularies are disjoint
                    """
                )
            }
        }
    }
}
