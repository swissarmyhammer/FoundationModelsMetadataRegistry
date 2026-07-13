import Foundation
import FoundationModelsMetadataRegistry
import FoundationModelsRouter
import HuggingFace
import MLXHuggingFace
import MLXLMCommon
import Tokenizers

/// # Shared live-Router profile resolution for gated Examples (plan.md §13).
///
/// `SemanticSearchCore`, `LibrarianCore`, `BigCatalogCore`, and
/// `HotReloadCore` each resolve a real, on-device model profile through a
/// live `Router` + `LiveModelLoader` for their gated (real-model) path --
/// the same tiny `mlx-community` model triple every time, differing only in
/// the recordings-directory label and the profile's `name`/`description`.
/// Factored here rather than each target carrying its own near-identical
/// copy of the `Router`/`LiveModelLoader`/`ProfileDefinition` setup.

/// The tiny, deliberately small `mlx-community` models every gated Examples
/// demo resolves -- cheap enough for a local demo run. Sharing one pair
/// across `SemanticSearch`, `Librarian`, `BigCatalog`, and `HotReload` means
/// a machine that already ran one caches the same weights for the others.
private enum LiveDemoModels {
    static let generation: ModelRef = "mlx-community/SmolLM-135M-Instruct-4bit"
    static let embedding: ModelRef = "mlx-community/bge-small-en-v1.5-4bit"
}

/// Resolves a real, on-device model profile through a live `Router` -- the
/// one path each gated Examples target's real-model story touches the
/// network/GPU through. Mirrors FoundationModelsRouter's own gated
/// integration suite and its `Examples/MultiModelGeneration` demo.
///
/// - Parameters:
///   - demoLabel: a short label identifying the calling demo (e.g.
///     `"Librarian"`), used to scope this run's recordings directory so
///     concurrent demo runs never collide.
///   - name: the resolved profile's name.
///   - description: the resolved profile's description.
/// - Returns: the resolved profile.
/// - Throws: whatever `Router.resolve(profile:reporting:)` throws.
public func resolveLiveProfile(
    demoLabel: String,
    name: String,
    description: String
) async throws -> LanguageModelProfile {
    let recordingsDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(demoLabel)-\(UUID().uuidString)", isDirectory: true)
    let router = Router(
        recordingsDir: recordingsDir,
        loader: LiveModelLoader(
            downloader: #hubDownloader(),
            tokenizerLoader: #huggingFaceTokenizerLoader()
        )
    )
    let profileDefinition = ProfileDefinition(
        name: name,
        description: description,
        standard: [LiveDemoModels.generation],
        flash: [LiveDemoModels.generation],
        embedding: [LiveDemoModels.embedding]
    )
    return try await router.resolve(profile: profileDefinition, reporting: ResolutionProgress())
}

/// Derives an xgrammar JSON Schema constraining a `{"ids": [...]}` selection
/// response to exactly `ids` (plan.md §6 "Ids only, grammar-enforced") --
/// shared by `LibrarianCore` and `BigCatalogCore`, each of which needs to
/// build an id-enum-constrained guided session for their gated real-model
/// path.
///
/// `SelectionTier.idEnumGrammar(ids:)` (the package's own equivalent) is
/// package-internal -- this helper builds an equivalent schema directly by
/// hand, exactly as a real integrator outside the package would, rather
/// than reaching into the package's internals. `MetadataSearcher`'s own
/// `.selection` tier still verifies every returned id against its current
/// candidate set regardless of how the grammar was built
/// (`.unknownSelectedId`), so this hand-built schema only needs to keep the
/// model honest about the response *shape* -- an object with one `ids` array
/// of enum-constrained strings.
///
/// - Parameter ids: the candidate id set to constrain output to.
/// - Returns: the xgrammar-ready `Grammar.jsonSchema(_:)`.
/// - Throws: an encoding error if `ids` can't be serialized to JSON (not
///   expected for a plain array of strings).
public func idEnumGrammar(ids: [String]) throws -> Grammar {
    let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "ids": [
                "type": "array",
                "items": ["type": "string", "enum": ids],
                "uniqueItems": true,
            ] as [String: Any]
        ],
        "required": ["ids"],
    ]
    let data = try JSONSerialization.data(withJSONObject: schema)
    return .jsonSchema(String(decoding: data, as: UTF8.self))
}

/// Resolves a real, live-Router-backed model and builds a `SelectionConfig`
/// whose session factory constrains every guided session to an id-enum
/// grammar over `ids` -- the shared "resolve a profile, derive an id-enum
/// grammar, build a `SelectionConfig` with an identical model factory"
/// pattern `LibrarianCore` and `BigCatalogCore` each need for their gated
/// real-model `.selection`-tier path, differing only in the profile
/// parameters, the candidate id set, and (for `BigCatalogCore`) an
/// over-budget `capacityCharacterLimit`.
///
/// - Parameters:
///   - demoLabel: a short label identifying the calling demo, forwarded to
///     `resolveLiveProfile(demoLabel:name:description:)`.
///   - name: the resolved profile's name.
///   - description: the resolved profile's description.
///   - ids: the candidate id set every guided session is grammar-constrained
///     to.
///   - capacityCharacterLimit: the assembled prefix's character budget, or
///     `nil` to use `SelectionConfig.defaultCapacityCharacterLimit`.
/// - Returns: a `SelectionConfig` ready to drive a `.selection`-mode search.
/// - Throws: whatever `resolveLiveProfile(demoLabel:name:description:)` or
///   `idEnumGrammar(ids:)` throws.
public func buildSelectionConfig(
    demoLabel: String,
    name: String,
    description: String,
    ids: [String],
    capacityCharacterLimit: Int? = nil
) async throws -> SelectionConfig {
    let profile = try await resolveLiveProfile(demoLabel: demoLabel, name: name, description: description)
    let grammar = try idEnumGrammar(ids: ids)
    return SelectionConfig(
        model: { instructions in
            RoutedAgentSession(session: profile.standard.makeGuidedSession(grammar: grammar, instructions: instructions))
        },
        capacityCharacterLimit: capacityCharacterLimit ?? SelectionConfig.defaultCapacityCharacterLimit
    )
}

/// Resolves a real, on-device embedding model through a live `Router` and
/// wraps it as a `TextEmbedding` -- the shared "resolve a profile, adapt its
/// embedding model" pattern `SemanticSearchCore` and `HotReloadCore` each
/// need for their gated real-model path, differing only in the profile
/// parameters.
///
/// - Parameters:
///   - demoLabel: a short label identifying the calling demo, forwarded to
///     `resolveLiveProfile(demoLabel:name:description:)`.
///   - name: the resolved profile's name.
///   - description: the resolved profile's description.
/// - Returns: a `RoutedEmbedderAdapter` wrapping the resolved profile's
///   embedding model.
/// - Throws: whatever `resolveLiveProfile(demoLabel:name:description:)`
///   throws.
public func buildLiveEmbedder(
    demoLabel: String,
    name: String,
    description: String
) async throws -> any TextEmbedding {
    let profile = try await resolveLiveProfile(demoLabel: demoLabel, name: name, description: description)
    return RoutedEmbedderAdapter(routedEmbedder: profile.embedding)
}
