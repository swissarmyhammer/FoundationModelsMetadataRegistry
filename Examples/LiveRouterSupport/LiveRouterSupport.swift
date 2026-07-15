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

/// Resolves a real, live-Router-backed model and builds a `SelectionConfig`
/// whose session factory vends guided sessions constrained to the `Grammar`
/// the selection tier hands it per call (the whole catalog's id enum under
/// budget, this round's top-M candidates over budget — the tier derives it
/// via `SelectionTier.idEnumGrammar(ids:)`, maxItems-capped against runaway
/// generation, task ^678h0ex) -- the shared "resolve a profile, build a
/// `SelectionConfig` with an identical model factory" pattern
/// `LibrarianCore` and `BigCatalogCore` each need for their gated
/// real-model `.selection`-tier path, differing only in the profile
/// parameters and (for `BigCatalogCore`) an over-budget
/// `capacityCharacterLimit`.
///
/// - Parameters:
///   - demoLabel: a short label identifying the calling demo, forwarded to
///     `resolveLiveProfile(demoLabel:name:description:)`.
///   - name: the resolved profile's name.
///   - description: the resolved profile's description.
///   - capacityCharacterLimit: the assembled prefix's character budget, or
///     `nil` to use `SelectionConfig.defaultCapacityCharacterLimit`.
/// - Returns: a `SelectionConfig` ready to drive a `.selection`-mode search.
/// - Throws: whatever `resolveLiveProfile(demoLabel:name:description:)`
///   throws.
public func buildSelectionConfig(
    demoLabel: String,
    name: String,
    description: String,
    capacityCharacterLimit: Int? = nil
) async throws -> SelectionConfig {
    let profile = try await resolveLiveProfile(demoLabel: demoLabel, name: name, description: description)
    return SelectionConfig(
        model: { instructions, grammar in
            RoutedAgentSession(session: profile.standard.makeGuidedSession(grammar: grammar, instructions: instructions))
        },
        // Both demos select over API-surface-shaped catalogs; keep the
        // original librarian prompt text rather than silently switching to
        // FoundationModelsRanker's neutral `.selectionDefault`.
        preamble: .librarianDefault,
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
