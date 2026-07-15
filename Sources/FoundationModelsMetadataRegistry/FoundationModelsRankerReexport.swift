// Re-exports FoundationModelsRanker, the shared search/ranking library this
// package's retrieval and selection tiers are built on (plan.md decision #9;
// §5 retrieval-tier and §6 selection-tier migrations): the retrieval pipeline
// (`HybridRanker`, `RankedDocument`, `SignalWeights`, `CosineScoring`, `Hit`,
// `Signals`, and the BM25/trigram/tokenizer primitives they score with), the
// embedding seam (`TextEmbedding`, `RoutedEmbedderAdapter`), and the whole
// selection tier (`SelectionTier`, `SelectionConfig`, `SelectionCatalog`,
// `SelectionMatch`, `Selection`, `RankDiagnostic`, `AgentSession`,
// `RoutedAgentSession`, and the selection-unavailable error) remain visible
// to this package's public API and its consumers unchanged, without every
// consumer needing its own `import FoundationModelsRanker`.
@_exported import FoundationModelsRanker
