# FoundationModelsMetadataRegistry

[![CI](https://github.com/swissarmyhammer/FoundationModelsMetadataRegistry/actions/workflows/ci.yml/badge.svg)](https://github.com/swissarmyhammer/FoundationModelsMetadataRegistry/actions/workflows/ci.yml)

Hybrid metadata search for Foundation Models sessions: rank-fused BM25 + trigram + cosine
retrieval, with an optional LLM-driven selection tier that returns catalog ids — never
re-typed text. Targets macOS 27+ and Swift 6.1 (Apple's on-device Foundation Models).

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

No embedder, no model, and no session are required for this path — retrieval alone fuses
BM25 (id-field ×5, block ×1) and character-trigram Dice by reciprocal rank fusion, so
`commit` ranks first even though its block never repeats the query's words. Add a
`TextEmbedding` conformer for a cosine signal, or a `SelectionConfig` to let an LLM select
verbatim ids over catalogs too large to fit in one prompt.

## Install

Add the package to `Package.swift`:

```swift
.package(url: "https://github.com/swissarmyhammer/FoundationModelsMetadataRegistry", branch: "main")
```

## Documentation

Five runnable examples cover every tier — keyword-only, semantic (cosine), LLM-driven
selection, a 1,000-item catalog, and hot reload — in [`Examples/`](Examples/). The full
design (architecture, diagnostics, the hot-reload contract) is in [`plan.md`](plan.md).

## License

No license file is included in this repository.
