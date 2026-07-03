import Foundation
import FoundationModels
import FoundationModelsRouter

/// plan.md §6: the selection tier's dynamic session — generalizes Multitool's
/// shipped `Librarian` (`../FoundationModelsMultitool/Sources/.../Librarian.swift`)
/// over `MetadataSearcher`'s catalog instead of a bespoke `APISurface`.
///
/// Assembles a prefix from `SelectionConfig.preamble` + every catalog item's
/// **`renderSummaryBlock()`** (plan.md §4: the summary seeds the selection
/// prefix; retrieval indexes the full `renderBlock()` instead) once at
/// `init`, since the index never changes for this tier's lifetime — a reload
/// replaces the whole tier rather than mutating one in place (plan.md §8).
///
/// **Under budget** (assembled prefix ≤ `capacityCharacterLimit`): a cached
/// root session is seeded once with the prefix, and each
/// `search(intent:limit:)` `fork()`s a fresh child from it, so the prefix's
/// KV cache is prefilled once and inherited per call — lifted from
/// `Librarian.findAPIs(task:)`'s cached-root + fork-per-call mechanics.
///
/// **Over budget**: the retrieval top-M + one-off session path (plan.md §6)
/// lands in a later task; `search(intent:limit:)` throws
/// `SelectionTierUnavailable` for an over-budget request until then.
///
/// **Ids only, grammar-enforced** (plan.md §6, decision #4): the guided
/// output is `Selection { ids: [String] }`; `idEnumGrammar(ids:)` derives the
/// xgrammar JSON Schema constraining `ids` to the current catalog's own id
/// set, so the model is structurally incapable of inventing one — the same
/// pattern as `Librarian.grammarSchemaSource()`, with an added `enum`
/// constraint injected into the `ids` array's `items` subschema. Returned ids
/// map back through the catalog to verbatim `Match`es (score `1.0`,
/// `signals: nil`); an id absent from the catalog — structurally unreachable
/// given the grammar, but defended against anyway — is filtered and reported
/// via `MetadataDiagnostic.unknownSelectedId(id:)`.
actor SelectionTier<Item: SearchableMetadata> {
    /// The full catalog index this tier answers `search(intent:limit:)`
    /// calls over.
    private let index: MetadataIndex<Item>

    /// This tier's session factory, preamble, and capacity/candidate budgets.
    private let config: SelectionConfig

    /// `assemblePrefix(preamble:index:)`, precomputed once at `init` since
    /// `index` never changes for this tier's lifetime.
    private let assembledPrefix: String

    /// Called for every diagnostic this tier emits (currently only
    /// `.unknownSelectedId`).
    private let onDiagnostic: @Sendable (MetadataDiagnostic) -> Void

    /// This tier's cached root session — `nil` until the first under-budget
    /// `search(intent:limit:)` call creates and caches it.
    private var rootSession: (any AgentSession)?

    /// Creates a selection tier over `index`, using `config`'s session
    /// factory, preamble, and budgets.
    ///
    /// - Parameters:
    ///   - index: the catalog index to answer `search(intent:limit:)` calls
    ///     over.
    ///   - config: this tier's session factory, preamble, and budgets.
    ///   - onDiagnostic: called for every diagnostic this tier emits.
    init(
        index: MetadataIndex<Item>,
        config: SelectionConfig,
        onDiagnostic: @escaping @Sendable (MetadataDiagnostic) -> Void
    ) {
        self.index = index
        self.config = config
        self.assembledPrefix = Self.assemblePrefix(preamble: config.preamble, index: index)
        self.onDiagnostic = onDiagnostic
    }

    /// Answers one `search(intent:limit:)` call for `.selection` mode.
    ///
    /// Under budget: reuses (creating on first use) this tier's cached root
    /// session, seeded with the full assembled prefix, and `fork()`s a fresh
    /// child per call so the prefix's prefilled compute is inherited rather
    /// than replayed. Over budget: throws `SelectionTierUnavailable` — the
    /// retrieval top-M + one-off session path (plan.md §6) is a later task.
    ///
    /// - Parameters:
    ///   - intent: the plain-language search intent.
    ///   - limit: the maximum number of matches to return. `limit <= 0`
    ///     yields an empty result without forking a session.
    /// - Returns: the selected items' verbatim `Match`es, at most `limit`.
    /// - Throws: `SelectionTierUnavailable` when the assembled prefix exceeds
    ///   `config.capacityCharacterLimit`, or whatever the underlying
    ///   session's `fork()`/`respond(to:generating:)` throws.
    func search(intent: String, limit: Int) async throws -> [Match<Item>] {
        guard limit > 0 else { return [] }
        guard assembledPrefix.count <= config.capacityCharacterLimit else {
            throw SelectionTierUnavailable()
        }

        let child = try await cachedRootSession().fork()
        let selection = try await child.respond(to: intent, generating: Selection.self)
        return matches(forIds: selection.ids, limit: limit)
    }

    /// Returns this tier's cached root session, creating and caching it on
    /// first use.
    ///
    /// - Returns: the cached root session, seeded with the full assembled
    ///   prefix.
    private func cachedRootSession() async throws -> any AgentSession {
        if let rootSession { return rootSession }
        let session = config.model(assembledPrefix)
        rootSession = session
        return session
    }

    /// Maps model-selected `ids` back through the catalog to verbatim
    /// `Match`es (plan.md §6 "Verbatim lookup"), filtering any id absent from
    /// the catalog and reporting it via `.unknownSelectedId` — structurally
    /// unreachable given the id-enum grammar's `uniqueItems` + per-element
    /// enum constraint, but defended against anyway — deduplicating repeats
    /// (first occurrence wins, keeping the model's own call-order intent)
    /// without reporting a diagnostic for them, and truncating to `limit`.
    ///
    /// - Parameters:
    ///   - ids: the model-selected ids, in the order the model returned them.
    ///   - limit: the maximum number of matches to return.
    /// - Returns: the verbatim `Match`es for every known, first-seen id, at
    ///   most `limit`.
    private func matches(forIds ids: [String], limit: Int) -> [Match<Item>] {
        var results: [Match<Item>] = []
        results.reserveCapacity(min(ids.count, limit))
        var seenIds: Set<String> = []
        for id in ids {
            guard results.count < limit else { break }
            guard seenIds.insert(id).inserted else { continue }
            guard let item = index.item(forId: id), let block = index.block(forId: id) else {
                onDiagnostic(.unknownSelectedId(id: id))
                continue
            }
            results.append(Match(id: id, block: block, score: 1.0, signals: nil, item: item))
        }
        return results
    }

    // MARK: - Prefix assembly

    /// Assembles this tier's instruction prefix (plan.md §6): `preamble`
    /// followed by a `# Candidates` header and every catalog item's
    /// **`renderSummaryBlock()`**, in catalog order — never `renderBlock()`,
    /// which stays reserved for the verbatim `Match.block` a selected id
    /// looks up afterward (plan.md §4).
    ///
    /// - Parameters:
    ///   - preamble: the selection guidance to prepend.
    ///   - index: the catalog index to assemble a prefix for.
    /// - Returns: the assembled prefix text.
    private static func assemblePrefix(preamble: String, index: MetadataIndex<Item>) -> String {
        let summaryBlocks = index.ids.compactMap { index.item(forId: $0)?.renderSummaryBlock() }
        return "\(preamble)\n\n# Candidates\n\(summaryBlocks.joined(separator: "\n\n"))"
    }

    // MARK: - Guided-generation grammar

    /// Derives the xgrammar JSON Schema constraining `Selection.ids` to
    /// exactly `ids` (plan.md §6 "Ids only, grammar-enforced") — the same
    /// derive-then-wrap pattern as Multitool's own
    /// `Librarian.grammarSchemaSource()` (which wraps the analogous derived
    /// schema in `Grammar.jsonSchema(_:)`), with an `enum` constraint
    /// injected into the `ids` array's `items` subschema so the model is
    /// structurally incapable of inventing an id outside the current
    /// candidate set.
    ///
    /// - Parameter ids: the candidate id set to constrain output to — the
    ///   full catalog's ids under budget, the top-M ranked ids over budget (a
    ///   later task).
    /// - Returns: the xgrammar-ready `Grammar.jsonSchema(_:)`.
    /// - Throws: an encoding error if `Selection.generationSchema` can't be
    ///   encoded to JSON (not expected for a valid `@Generable` type), or
    ///   `SelectionSchemaShapeError` if its encoded shape doesn't have the
    ///   expected `properties.ids.items` subschema to constrain (not expected
    ///   for `Selection`'s fixed shape).
    static func idEnumGrammar(ids: [String]) throws -> Grammar {
        let data = try JSONEncoder().encode(Selection.generationSchema)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            var properties = root["properties"] as? [String: Any],
            var idsSchema = properties["ids"] as? [String: Any],
            var itemsSchema = idsSchema["items"] as? [String: Any]
        else {
            throw SelectionSchemaShapeError()
        }

        itemsSchema["enum"] = ids
        idsSchema["items"] = itemsSchema
        // No duplicate ids in one selection -- pairs with the per-element
        // `enum` constraint above to make the *set* of ids structurally
        // exact, not just each individual element's membership.
        idsSchema["uniqueItems"] = true
        properties["ids"] = idsSchema
        root["properties"] = properties

        let constrained = try JSONSerialization.data(withJSONObject: root)
        return .jsonSchema(String(decoding: constrained, as: UTF8.self))
    }
}

/// Thrown by `SelectionTier.idEnumGrammar(ids:)` if `Selection`'s encoded
/// `GenerationSchema` doesn't have the expected `properties.ids.items`
/// subschema shape to inject an `enum` constraint into — not expected for
/// `Selection`'s fixed shape, kept as a genuine (if practically unreachable)
/// failure mode rather than trapping.
struct SelectionSchemaShapeError: Error, Sendable, Equatable {}
