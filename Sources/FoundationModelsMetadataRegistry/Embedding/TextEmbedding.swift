// Ported from CodeContextKit's
// `Sources/CodeContextKit/Embedding/TextEmbedding.swift` (plan.md §5 "Port,
// don't depend"). No behavior changes.

/// A seam for converting text into fixed-length embedding vectors.
///
/// Abstracts over the concrete embedding backend so callers — chiefly
/// `MetadataIndex.build(items:embedder:previous:onDiagnostic:)` (embedding
/// each item's rendered block at index-build/update time) and
/// `MetadataSearcher.search(intent:limit:)` (embedding only the query text,
/// never the catalog, at query time) — depend on this narrow protocol
/// rather than a specific implementation. `RoutedEmbedderAdapter` wraps
/// FoundationModelsRouter's `RoutedEmbedder` for production use; tests
/// substitute a deterministic, GPU-free double.
public protocol TextEmbedding: Sendable {
    /// The length of every embedding vector this embedder produces.
    var dimension: Int { get }

    /// Embeds each input string into a `dimension`-length vector, in order.
    ///
    /// - Parameter texts: The strings to embed.
    /// - Returns: One `dimension`-length vector per input, in the same
    ///   order as `texts`.
    /// - Throws: If the underlying embedding computation fails.
    func embed(_ texts: [String]) async throws -> [[Float]]
}
