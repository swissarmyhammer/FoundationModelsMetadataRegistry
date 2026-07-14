// Re-exports FoundationModelsRanker, the shared search/ranking primitives library this
// package's ported copies (`Search/`, `Embedding/`) were extracted into
// (plan.md decision #9), so `RRF`, `BM25`, `BM25Corpus`, `Trigram`,
// `Tokenizer`, `Hit`, `Signals`, `TextEmbedding`, and
// `RoutedEmbedderAdapter` remain visible to this package's public API and
// its consumers unchanged.
//
// FoundationModelsRanker also exports `Selection`, `SelectionConfig`, `AgentSession`,
// `SelectionTierUnavailable`, and `RoutedAgentSession`, which this module
// still declares locally (as `public`) until the selection-tier migration:
// module-local declarations shadow re-exported ones, and this module's own
// public declarations likewise shadow FoundationModelsRanker's for clients, so the blanket
// re-export stays unambiguous. The one exception is `SelectionTier`: the
// local `actor SelectionTier<Item>` is internal, so it shadows FoundationModelsRanker's
// only inside this module — clients resolve `SelectionTier` to FoundationModelsRanker's
// public actor via this re-export until the selection-tier migration
// replaces the internal one.
@_exported import FoundationModelsRanker
