import Foundation
import FoundationModelsMetadataRegistry

// MARK: - GPU-free scripted selection session

/// A GPU-free, scripted `AgentSession` test double for the selection-tier
/// demos -- `ScriptedAgentSession`-style (the test suite's own hand-scripted
/// double), but public and demo-shaped: it always answers with the ids-only
/// JSON body naming `selectedIds`, whatever it is prompted with.
///
/// `Librarian` and `BigCatalog` both drive the `.selection` tier, which needs
/// a session that returns a well-formed id list. What those demos actually
/// show is the tier's own machinery -- a cached root session forked per query
/// for `Librarian`, the over-budget top-M cut for `BigCatalog` -- and both
/// stories read the same whether a real model or a script names the ids. So
/// the demos script them, and touch no network, no model, and no GPU.
///
/// The default `AgentSession.fork()` (return `self`) is exactly right here:
/// this double holds no prefilled KV cache and no per-call state, so a fork
/// answers identically to its parent.
public struct DemoAgentSession: AgentSession {
    /// The catalog ids this session always selects, in the order it names
    /// them.
    public let selectedIds: [String]

    /// Creates a scripted session that always selects `selectedIds`.
    ///
    /// - Parameter selectedIds: the catalog ids to name in every response,
    ///   in the order to name them.
    public init(selectedIds: [String]) {
        self.selectedIds = selectedIds
    }

    /// Answers with the ids-only JSON body naming `selectedIds`, ignoring
    /// the prompt -- this double is scripted, not a model.
    ///
    /// - Parameter prompt: the prompt to respond to. Ignored.
    /// - Returns: the selection tier's ids-only response shape, e.g.
    ///   `{"ids":["tripCities","weather"]}`.
    /// - Throws: an encoding error if `selectedIds` cannot be encoded, which
    ///   `JSONEncoder` never does for an array of `String`.
    public func respond(to prompt: String) async throws -> String {
        let encoded = try JSONEncoder().encode(SelectedIds(ids: selectedIds))
        return String(decoding: encoded, as: UTF8.self)
    }

    /// The wire shape the selection tier decodes: an ids-only object.
    ///
    /// Encoded rather than string-interpolated so every id is escaped the way
    /// JSON requires -- `BigCatalog`'s ids are URIs, not bare identifiers.
    private struct SelectedIds: Encodable {
        /// The selected catalog ids, in selection order.
        let ids: [String]
    }
}

// MARK: - GPU-free selection configuration

/// Builds a GPU-free `SelectionConfig`: every session the tier asks for is a
/// fresh `DemoAgentSession` scripted with `selectedIds`.
///
/// `Librarian` (under budget, cached root) and `BigCatalog` (over budget,
/// one-off session) each need exactly this configuration, differing only in
/// the scripted ids and the capacity budget -- shared here so the two demos
/// have one source of truth rather than two near-identical copies.
///
/// The session factory ignores its argument. The instructions text would
/// seed a real model's prefix; a scripted session needs none of it, and the
/// tier's own behavior -- which is what both demos exist to show -- is
/// unchanged either way.
///
/// - Parameters:
///   - selectedIds: the catalog ids every vended session names, in the order
///     to name them.
///   - capacityCharacterLimit: the assembled prefix's character budget, which
///     decides between the cached-root and one-off paths. Defaults to
///     `SelectionConfig.defaultCapacityCharacterLimit`.
/// - Returns: the GPU-free selection configuration.
public func demoSelectionConfig(
    selectedIds: [String],
    capacityCharacterLimit: Int = SelectionConfig.defaultCapacityCharacterLimit
) -> SelectionConfig {
    SelectionConfig(
        model: { _ in DemoAgentSession(selectedIds: selectedIds) },
        // Both demos select over API-surface-shaped catalogs; keep the
        // original librarian prompt text rather than silently switching to
        // FoundationModelsRanker's neutral `.selectionDefault`.
        preamble: .librarianDefault,
        capacityCharacterLimit: capacityCharacterLimit
    )
}
