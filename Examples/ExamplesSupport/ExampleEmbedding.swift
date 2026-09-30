import Foundation
import FoundationModelsExtras
import FoundationModelsRouter

/// The embedding model that the examples use: Qwen3 Embedding 0.6B, 4-bit,
/// from the Hugging Face hub. The weights are about 0.3 GB. The first run
/// downloads them into the Hugging Face cache; a later run loads them from
/// the cache.
public let exampleEmbeddingModel: ModelRef = "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ"

/// The bytes that the model pool counts for the weights of
/// `exampleEmbeddingModel`. This is a rough upper limit.
public let exampleEmbeddingFootprintBytes: Int64 = 1 << 30

/// Makes the model loader of the examples: the `LiveModelLoader` of
/// FoundationModelsRouter, which downloads models from the Hugging Face hub.
///
/// Give it to a `MetadataSearcher` initializer that takes an
/// `embeddingModel`. The searcher gets the model from `ModelPool.shared`,
/// which calls this loader only when the model is not in memory.
///
/// - Returns: the loader.
public func exampleModelLoader() -> LiveModelLoader {
    LiveModelLoader()
}
