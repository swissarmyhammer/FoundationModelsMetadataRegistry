import Foundation

@testable import FoundationModelsMetadataRegistry

// MARK: - `SelectionTier.idEnumSchema(ids:)` assertions (plan.md §6, M3)
//
// `idEnumSchema(ids:)` hands back JSON Schema SOURCE TEXT, so a test decodes
// it before asserting on it. Asserting on the raw text is not an option:
// `JSONSerialization` fixes no key order, so two equal schemas compare
// unequal as strings and any such assertion is flaky by construction.
//
// Five tests across `SelectionTests` and `HotReloadTests` need the same
// three constraints out of the same subschema, so the decode lives here
// once rather than as a repeated `properties` / `ids` / `items` walk.

/// Thrown by `SelectionIDConstraints.init(schemaSource:)` when the decoded
/// text does not carry the `properties.ids` subschema every selection schema
/// has — not expected for `Selection`'s fixed shape, kept as a genuine
/// failure rather than a force unwrap.
struct SelectionSchemaShapeUnexpected: Error, Equatable {}

/// The constraints `SelectionTier.idEnumSchema(ids:)` injects into
/// `Selection`'s generated schema, decoded out of that schema's source text.
///
/// These three are the whole substance of the schema. This package drives
/// the selection tier with no compiled grammar, so nothing forces a valid id
/// out of the decoder: `allowedIDs` is what tells a caller's own grammar
/// which ids exist, and `maxItems` is the cap that stops a runaway repeat of
/// a valid one — the xgrammar pipeline enforces `maxItems` and silently
/// ignores `uniqueItems`.
struct SelectionIDConstraints: Equatable {
    /// The id set `properties.ids.items.enum` limits a selection to.
    let allowedIDs: Set<String>

    /// `properties.ids.uniqueItems` — whether the schema forbids a repeat.
    let uniqueItems: Bool

    /// `properties.ids.maxItems` — the hard cap on a selection's length.
    let maxItems: Int

    /// Decodes the constraints out of a schema's JSON source text.
    ///
    /// - Parameter schemaSource: the text `SelectionTier.idEnumSchema(ids:)`
    ///   returns.
    /// - Throws: `SelectionSchemaShapeUnexpected` if the text is not JSON
    ///   carrying `properties.ids` with an `items.enum`, a `uniqueItems` and
    ///   a `maxItems`.
    init(schemaSource: String) throws {
        guard let data = schemaSource.data(using: .utf8),
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let properties = root["properties"] as? [String: Any],
            let idsSchema = properties["ids"] as? [String: Any],
            let itemsSchema = idsSchema["items"] as? [String: Any],
            let enumValues = itemsSchema["enum"] as? [String],
            let uniqueItems = idsSchema["uniqueItems"] as? Bool,
            let maxItems = idsSchema["maxItems"] as? Int
        else {
            throw SelectionSchemaShapeUnexpected()
        }
        self.allowedIDs = Set(enumValues)
        self.uniqueItems = uniqueItems
        self.maxItems = maxItems
    }
}
