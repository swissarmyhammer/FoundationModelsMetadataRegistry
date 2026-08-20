# FoundationModelsMetadataRegistry

[![CI](https://github.com/swissarmyhammer/FoundationModelsMetadataRegistry/actions/workflows/ci.yml/badge.svg)](https://github.com/swissarmyhammer/FoundationModelsMetadataRegistry/actions/workflows/ci.yml)

Hybrid metadata search for Foundation Models sessions. The searcher fuses BM25,
character-trigram, and cosine signals with reciprocal rank fusion. An optional
selection tier lets an on-device LLM select catalog ids — never re-typed text.
The package targets macOS 27+ and Swift 6.1 (Apple's on-device Foundation Models).

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
Thus `commit` gets the first rank although its block does not contain the query's
words. Add a `TextEmbedding` conformer to get a cosine signal. Add a
`SelectionConfig` to let an LLM select verbatim ids from catalogs too large for
one prompt.

## Install

Add the package to `Package.swift`:

```swift
.package(url: "https://github.com/swissarmyhammer/FoundationModelsMetadataRegistry", branch: "main")
```

## Documentation

Five runnable examples show each tier — keyword-only, semantic (cosine),
LLM-driven selection, a 1,000-item catalog, and hot reload — in
[`Examples/`](Examples/). The full design (architecture, diagnostics, the
hot-reload contract) is in [`plan.md`](plan.md).

## License

This repository does not contain a license file.
