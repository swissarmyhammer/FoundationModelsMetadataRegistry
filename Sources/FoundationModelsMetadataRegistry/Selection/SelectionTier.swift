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
/// **Over budget**: `retrievalRanking` ranks the whole catalog for the
/// intent, and the top `config.candidateLimit` candidates (best-first) seed
/// a **fresh, uncached, unforked one-off session** — there is no stable
/// prefix to reuse, since the candidate set differs per intent. The cut is
/// reported via `MetadataDiagnostic.retrievalCut(considered:kept:)` (the
/// `onPrefilterCut` pattern, generalized to ranked retrieval). Unlike the
/// under-budget path, retrieval genuinely ran, so returned `Match`es carry
/// its real fused `score`/`signals` instead of the pure-selection `1.0`/
/// `nil`, and a selected id outside this round's candidates — even a
/// legitimate id from elsewhere in the wider catalog — is filtered and
/// reported via `.unknownSelectedId`, exactly like an id absent from the
/// catalog altogether.
///
/// **Ids only, grammar-enforced** (plan.md §6, decision #4): the guided
/// output is `Selection { ids: [String] }`; `idEnumGrammar(ids:)` derives the
/// xgrammar JSON Schema constraining `ids` to the current candidate id
/// set — the full catalog under budget, the top-M ranked ids over budget —
/// so the model is structurally incapable of inventing one — the same
/// pattern as `Librarian.grammarSchemaSource()`, with an added `enum`
/// constraint injected into the `ids` array's `items` subschema. Returned ids
/// map back through the catalog to verbatim `Match`es; an id outside the
/// current candidate set — structurally unreachable given the grammar, but
/// defended against anyway — is filtered and reported via
/// `MetadataDiagnostic.unknownSelectedId(id:)`.
actor SelectionTier<Item: SearchableMetadata> {
    /// The full catalog index this tier answers `search(intent:limit:)`
    /// calls over.
    private let index: MetadataIndex<Item>

    /// This tier's session factory, preamble, and capacity/candidate budgets.
    private let config: SelectionConfig

    /// `assemblePrefix(preamble:index:)`, precomputed once at `init` since
    /// `index` never changes for this tier's lifetime.
    private let assembledPrefix: String

    /// Called for every diagnostic this tier emits (currently
    /// `.unknownSelectedId` and `.retrievalCut`).
    private let onDiagnostic: @Sendable (MetadataDiagnostic) -> Void

    /// Ranks the whole catalog for one intent, best-first, always returning
    /// exactly as many `Match`es as the catalog has entries — the over-budget
    /// path's source of top-M candidates. `MetadataSearcher` wires this to
    /// its own retrieval tier (`MetadataSearcher.rankEntireCatalog(intent:
    /// index:weights:embedder:onDiagnostic:)`); tests script it directly by
    /// constructing this tier through `MetadataSearcher`, which drives the
    /// real BM25/trigram/cosine computation deterministically over small
    /// fixture catalogs.
    private let retrievalRanking: @Sendable (String) async -> [Match<Item>]

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
    ///   - retrievalRanking: ranks the whole catalog for one intent,
    ///     best-first — the over-budget path's source of top-M candidates.
    init(
        index: MetadataIndex<Item>,
        config: SelectionConfig,
        onDiagnostic: @escaping @Sendable (MetadataDiagnostic) -> Void,
        retrievalRanking: @escaping @Sendable (String) async -> [Match<Item>]
    ) {
        self.index = index
        self.config = config
        self.assembledPrefix = Self.assemblePrefix(preamble: config.preamble, index: index)
        self.onDiagnostic = onDiagnostic
        self.retrievalRanking = retrievalRanking
    }

    /// Answers one `search(intent:limit:)` call for `.selection` mode.
    ///
    /// Under budget: reuses (creating on first use) this tier's cached root
    /// session, seeded with the full assembled prefix, and `fork()`s a fresh
    /// child per call so the prefix's prefilled compute is inherited rather
    /// than replayed. Over budget: ranks the whole catalog and seeds a
    /// one-off session with the top-M candidates (`overBudgetSearch(intent:
    /// limit:)`, plan.md §6) — no caching, no fork.
    ///
    /// - Parameters:
    ///   - intent: the plain-language search intent.
    ///   - limit: the maximum number of matches to return. `limit <= 0`
    ///     yields an empty result without forking or creating a session.
    /// - Returns: the selected items' verbatim `Match`es, at most `limit`.
    /// - Throws: whatever the underlying session's `fork()`/
    ///   `respond(to:generating:)` throws.
    func search(intent: String, limit: Int) async throws -> [Match<Item>] {
        guard limit > 0 else { return [] }
        guard assembledPrefix.count <= config.capacityCharacterLimit else {
            return try await overBudgetSearch(intent: intent, limit: limit)
        }

        let child = try await cachedRootSession().fork()
        let selection = try await child.respond(to: intent, generating: Selection.self)
        return matches(forIDs: selection.ids, limit: limit)
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

    // MARK: - Over budget: retrieval top-M + one-off session

    /// Answers one over-budget `search(intent:limit:)` call (plan.md §6
    /// "Over budget"): ranks the whole catalog through `retrievalRanking`,
    /// takes the top `config.candidateLimit` candidates (best-first —
    /// always `min(config.candidateLimit, considered)` of them, even when
    /// few or none score positively, so the model always has a full
    /// candidate set to pick from), reports the cut via
    /// `.retrievalCut(considered:kept:)`, and seeds a **fresh, uncached,
    /// unforked** one-off session with exactly those candidates'
    /// `renderSummaryBlock()`s — there is no stable prefix here to reuse,
    /// since the candidate set differs per intent.
    ///
    /// - Parameters:
    ///   - intent: the plain-language search intent.
    ///   - limit: the maximum number of matches to return.
    /// - Returns: the selected candidates' verbatim `Match`es, carrying the
    ///   real retrieval `score`/`signals` that ranked them, at most `limit`.
    /// - Throws: whatever the one-off session's `respond(to:generating:)`
    ///   throws.
    private func overBudgetSearch(intent: String, limit: Int) async throws -> [Match<Item>] {
        let ranked = await retrievalRanking(intent)
        let candidates = Array(ranked.prefix(config.candidateLimit))
        onDiagnostic(.retrievalCut(considered: ranked.count, kept: candidates.count))

        // Nothing to seed a session with -- and nothing worth asking a
        // model to choose among -- when the catalog itself is empty.
        guard !candidates.isEmpty else { return [] }

        let candidateIDs = candidates.map(\.id)
        let prefix = Self.assemblePrefix(preamble: config.preamble, ids: candidateIDs, index: index)
        let session = config.model(prefix)
        let selection = try await session.respond(to: intent, generating: Selection.self)
        return matches(
            forIDs: selection.ids,
            limit: limit,
            allowedIDs: Set(candidateIDs),
            retrievalMatches: Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        )
    }

    /// Maps model-selected `ids` back through the catalog to verbatim
    /// `Match`es (plan.md §6 "Verbatim lookup"), filtering any id not
    /// resolvable and reporting it via `.unknownSelectedId` — structurally
    /// unreachable given the id-enum grammar's `uniqueItems` + per-element
    /// enum constraint, but defended against anyway — deduplicating repeats
    /// (first occurrence wins, keeping the model's own call-order intent)
    /// without reporting a diagnostic for them, and truncating to `limit`.
    ///
    /// - Parameters:
    ///   - ids: the model-selected ids, in the order the model returned them.
    ///   - limit: the maximum number of matches to return.
    ///   - allowedIDs: restricts resolution to this id set (the over-budget
    ///     path's current candidates) in addition to the catalog itself; an
    ///     id absent from `allowedIDs` is treated exactly like an id absent
    ///     from the catalog. `nil` (the under-budget default) allows any
    ///     catalog id.
    ///   - retrievalMatches: the retrieval `Match` (real fused `score` and
    ///     `signals`) for each of this round's candidates, keyed by id — the
    ///     over-budget path's ranking result. Empty (the under-budget
    ///     default) yields the pure-selection `1.0`/`nil`.
    /// - Returns: the verbatim `Match`es for every known, allowed, first-seen
    ///   id, at most `limit`.
    private func matches(
        forIDs ids: [String],
        limit: Int,
        allowedIDs: Set<String>? = nil,
        retrievalMatches: [String: Match<Item>] = [:]
    ) -> [Match<Item>] {
        var results: [Match<Item>] = []
        results.reserveCapacity(min(ids.count, limit))
        var seenIDs: Set<String> = []
        for id in ids {
            guard results.count < limit else { break }
            guard seenIDs.insert(id).inserted else { continue }
            guard allowedIDs?.contains(id) ?? true,
                let item = index.item(forID: id),
                let block = index.block(forID: id)
            else {
                onDiagnostic(.unknownSelectedId(id: id))
                continue
            }
            let retrievalMatch = retrievalMatches[id]
            results.append(
                Match(
                    id: id,
                    block: block,
                    score: retrievalMatch?.score ?? 1.0,
                    signals: retrievalMatch?.signals,
                    item: item
                )
            )
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
    static func assemblePrefix(preamble: String, index: MetadataIndex<Item>) -> String {
        assemblePrefix(preamble: preamble, ids: index.ids, index: index)
    }

    /// Assembles an instruction prefix for an arbitrary candidate id
    /// set (plan.md §6): `preamble` followed by a `# Candidates` header and
    /// exactly those ids' **`renderSummaryBlock()`**, in `ids`' order —
    /// `assemblePrefix(preamble:index:)`'s whole-catalog case is
    /// `ids: index.ids`; the over-budget path passes the top-M ranked ids
    /// instead, best-first.
    ///
    /// - Parameters:
    ///   - preamble: the selection guidance to prepend.
    ///   - ids: the candidate ids to render, in the order they should appear.
    ///   - index: the catalog index to look candidate blocks up in.
    /// - Returns: the assembled prefix text.
    static func assemblePrefix(preamble: String, ids: [String], index: MetadataIndex<Item>) -> String {
        let summaryBlocks = ids.compactMap { index.item(forID: $0)?.renderSummaryBlock() }
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
    ///   full catalog's ids under budget, the top-M ranked ids over budget.
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
