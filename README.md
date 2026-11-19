# FoundationModelsMetadataRegistry

[![CI](https://github.com/swissarmyhammer/FoundationModelsMetadataRegistry/actions/workflows/ci.yml/badge.svg)](https://github.com/swissarmyhammer/FoundationModelsMetadataRegistry/actions/workflows/ci.yml)

Hybrid metadata search for Foundation Models sessions. The searcher fuses BM25,
character-trigram, and cosine signals with reciprocal rank fusion. An optional
selection tier lets an on-device LLM select catalog ids — never re-typed text.
The package targets macOS 27+ and Swift 6.4 (Apple's on-device Foundation Models).

```swift
import FoundationModelsMetadataRegistry

struct GitCommand: SearchableMetadata {
    let id: String
    let block: String
    func renderBlock() -> String { block }
}

let commands = [
    GitCommand(id: "commit", block: "Record staged changes as a new snapshot in the repository history."),
    GitCommand(id: "push", block: "Upload local branch history to a remote server."),
    GitCommand(id: "pull", block: "Download and merge remote branch history."),
    GitCommand(id: "branch", block: "List, create, or delete lines of independent development."),
    GitCommand(id: "stash", block: "Temporarily set aside uncommitted edits to switch tasks."),
]

let searcher = MetadataSearcher(items: commands, mode: .retrieval)
let matches = try await searcher.search(intent: "commit changes to git", limit: 3)

for match in matches {
    print("\(match.id)  score=\(match.score)")
}
```

This path does not need an embedder, a model, or a session. Retrieval alone fuses
BM25 (id field ×5, block ×1) and character-trigram Dice by reciprocal rank fusion.
Thus `commit` gets the first rank although its own block never says the word
`commit` — the ×5 id field carries that term. Give an `embedder:` to get a cosine
signal. A `PooledEmbedder` from `FoundationModelsExtras` is a `PooledEmbedding`,
and searchers that name one model share one pooled copy of it:

```swift
import FoundationModelsExtras

let semantic = MetadataSearcher(
    items: commands,
    embedder: PooledEmbedder(ref: "mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ"),
)
```

The initializer is synchronous. It embeds nothing, and `PooledEmbedder(ref:)`
loads nothing. The first search loads the model and embeds the catalog.
Add a `SelectionConfig` to let an LLM select verbatim ids
from catalogs too large for one prompt.

Add a `DecisionConfig` to rank the whole catalog with a decision model. The
model gives the probability of "yes" for one yes-or-no question about each
catalog item, also for an item that the retrieval tier does not find. The
questions go to one decision session in batches of at most `batchSize`. The
matches are the items with a probability of 0.5 or more, sorted by that
probability. `PooledDecisionModel` is in the `FoundationModelsDecisionPooled`
product of the FoundationModelsDecision package. This package does not link
that product, so add it to your own package:

```swift
import FoundationModelsDecisionPooled

let decided = MetadataSearcher(
    items: commands,
    mode: .decision,
    decision: DecisionConfig(model: PooledDecisionModel(ref: "mlx-community/Qwen3-4B-4bit")),
)
```

`DecisionConfig(model:batchSize:minimumProbability:question:)` has the defaults
`batchSize: 64` and `minimumProbability: 0.5`. A `.decision` search without a
`DecisionConfig` throws `DecisionTierUnavailable`.

## Large catalogs, updates and persistence

The searcher supports catalogs of about 100,000 items of up to 2,000 characters.
At that size a `.retrieval` search over the whole catalog takes at most
85 ms, and an update of 20 items 11 ms (see
[`Benchmarks/Results/2026-11-19-scale/`](Benchmarks/Results/2026-11-19-scale/)).
The ranking is the same at each size.

`update(upserting:removing:)` adds, replaces and removes some items by id, and
does not build the other items again. An item that did not change costs nothing,
and an item whose embedded text did not change keeps its vector:

```swift
await searcher.update(upserting: [newItem, changedItem], removing: ["old-id"])
```

`update(items:)` replaces the whole catalog, and keeps each item that did not
change.

Give a `CatalogPersistence` to keep the catalog and its vectors in a folder. The
items must be `Codable`. At its start, the searcher reads the stored catalog with
no embed, and after each change it saves on a background queue:

```swift
struct Chunk: SearchableMetadata, Codable {
    let id: String
    let text: String
    func renderBlock() -> String { text }
}

let stored = await MetadataSearcher<Chunk>(
    persistence: CatalogPersistence(folder: folder, embeddingModelID: "embeddinggemma-300m"),
    mode: .retrieval,
    embedder: embedder,
)
await stored.waitForSaves()  // before the process ends
```

`items()` and `ids()` give the catalog in catalog order, also the stored catalog
right after the start, so the caller can upsert only what changed and remove what
is gone.

A stored catalog of another embedding model id, of an old format, or that is
damaged, is dropped with a `.storedCatalogDropped` diagnostic, and the next
update builds it again. A crash keeps the last state that was written.
`SharedCatalogEmbedding(persistence:embedder:)` gives the same option to
searchers that share one catalog embed.

## Install

Add the package to `Package.swift`:

```swift
.package(url: "https://github.com/swissarmyhammer/FoundationModelsMetadataRegistry", branch: "main")
```

## Documentation

Five runnable examples show each tier — keyword-only, semantic (cosine),
LLM-driven selection, a 1,000-item catalog, and hot reload — in the separate
[`Examples/`](Examples/) package. The examples use two MLX models from the
Hugging Face hub. The semantic and hot-reload examples embed with
`mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ` (about 0.3 GB). The librarian,
1,000-item and hot-reload examples select with `mlx-community/Qwen3-4B-4bit`
(about 2.3 GB). The first run of an example downloads its models into the
Hugging Face cache; a later run loads them from the cache. Run one with:

```sh
swift run --package-path Examples SemanticSearch
```

The separate [`Benchmarks/`](Benchmarks/) package compares the retrieval,
selection and decision tiers on a labeled catalog. A run loads real models, and
the first run downloads them into the Hugging Face cache. Run it with:

```sh
swift run -c release --package-path Benchmarks RankingBenchmark --output <dir>
```

The run writes `report.json` and `report.md` to `<dir>`.

The cost gate at 100,000 items (search, update of 20 items, start from the
stored catalog, memory) needs no model. It exits with a failure when a limit is
not met:

```sh
swift run -c release --package-path Benchmarks ScaleBenchmark <dir>
```

The full design (architecture, diagnostics, the
hot-reload contract) is in [`plan.md`](plan.md).

## License

This repository does not contain a license file.
