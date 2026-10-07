// Re-exports FoundationModelsRanker, the shared search and ranking library
// that the retrieval tier and the selection tier of this package use
// (plan.md decision #9; §5 retrieval tier and §6 selection tier). The
// re-export gives the consumers of this package these types with no
// `import FoundationModelsRanker` of their own:
//
// - The retrieval pipeline: `HybridRanker`, `RankedDocument`,
//   `SignalWeights`, `CosineScoring`, `Hit`, `Signals`, and the BM25,
//   trigram and tokenizer primitives that they score with.
// - The selection tier: `SelectionTier`, `SelectionConfig`,
//   `SelectionCatalog`, `SelectionMatch`, `Selection`, `RankDiagnostic`
//   and `SelectionTierUnavailable`.
//
// The embedder is a FoundationModelsExtras `PooledEmbedding`, and the
// selection model is a FoundationModels `LanguageModel`. This package
// re-exports neither: a consumer imports FoundationModelsExtras or
// FoundationModels to name them.
@_exported import FoundationModelsRanker
