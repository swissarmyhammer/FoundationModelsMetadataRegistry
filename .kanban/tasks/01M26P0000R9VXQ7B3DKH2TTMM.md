---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m26t86h9sdx87ta9jq16vd7s
  text: |-
    Research and a design decision the reviewer must rule on.

    What the code does today:
    - `MetadataIndex.buildEntry(item:)` renders the block one time and uses that
      one text for the `RankedDocument` body field, for the embed batch, and for
      the `Match.block` lookup.
    - `Entry.blockHash` keys embedding reuse (`incrementalBaseline`,
      `mergingEmbeddings`) AND content identity (`hasIdenticalContent`, which is
      `MetadataSearcher.update(items:)`'s redundant-update guard).

    The card asks for `renderIndexedText()` and `renderEmbeddedText()` with no
    argument, and it also asks that two texts of one entry that are equal cost
    one render and one hash. In Swift these two cannot both hold: a protocol
    extension default that returns `renderBlock()` renders the block a second
    time, and the index cannot see that the default ran. The card's cost point
    is not only prose — the test
    `CatalogTests.indexRendersBlockOnceAtBuildAndReusesItOnEveryLookup` counts
    `renderBlock()` calls at build time and holds the count at 1. No-argument
    methods make that count 3, and weakening that assertion is not permitted.

    The resolution: the two methods take the already-rendered block, and each
    default returns it.

        func renderIndexedText(from block: String) -> String   // default: block
        func renderEmbeddedText(from block: String) -> String   // default: block

    A consumer overrides one method and ignores the parameter to supply its own
    text, or reads the parameter to derive from the block. The default is
    `renderBlock()`'s output, so a consumer that overrides nothing behaves
    exactly as before, at one render and one hash. This is the one place the
    diff differs from the card's literal spelling; every other item is as the
    card states.

    Two more points settled:
    - `blockHash` became `Entry.digests`, a `RenderedTextDigests` value holding
      the SHA-256 of each of the three texts. `digests.embeddedText` alone keys
      embedding reuse and the merge hash check, so changing the embedded text
      re-embeds and changing any other text reuses the stored vector.
    - `hasIdenticalContent(to:)` compares the whole `digests` value, not the
      embedded-text digest alone. A changed block is what a `Match` hands back
      and a changed indexed text is what the keyword signals score, so an
      update carrying either must not be read as redundant.
  timestamp: 2026-09-10T23:25:37.193915+00:00
- actor: claude-code
  id: 01m26t93h3bxb3j7aycgzr2nqe
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsMetadataRegistry/Catalog/SearchableMetadata.swift, Sources/FoundationModelsMetadataRegistry/Catalog/RenderedTextDigests.swift (new), Sources/FoundationModelsMetadataRegistry/Catalog/MetadataIndex.swift, Sources/FoundationModelsMetadataRegistry/Catalog/MetadataIndex+Embedding.swift, Tests/FoundationModelsMetadataRegistryTests/SearchableMetadataTextsTests.swift (new, 12 tests). `swift test`: 132 tests in 13 suites, no failure, no warning. `swift test --package-path IntegrationTests`: 5 tests in 4 suites, passed. swiftformat --lint: 0 of 59 files need formatting. swiftlint: no violation.
    - open point for the reviewer: the two new methods take the already-rendered block (`renderIndexedText(from:)`, `renderEmbeddedText(from:)`) instead of the card's no-argument spelling. The comment above states why the no-argument form cannot hold the card's one-render point, and which existing test measures it.
    - next: /review
  timestamp: 2026-09-10T23:26:06.883601+00:00
- actor: claude-code
  id: 01m26tjfxqz2zd9s5p4zmzfewh
  text: |-
    ### review — findings
    - evidence: 2 findings (2 confirmed, 0 refuted) — Sources/FoundationModelsMetadataRegistry/Catalog/RenderedTextDigests.swift:25, Sources/FoundationModelsMetadataRegistry/Catalog/RenderedTextDigests.swift:28
    - scope: review sha HEAD~1..HEAD
    - next: correct the assign-only properties in RenderedTextDigests.swift, then review again.
  timestamp: 2026-09-10T23:31:14.487925+00:00
- actor: claude-code
  id: 01m26tjssbfjqaspm4trqfg0e6
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 5 files (SearchableMetadata.swift, RenderedTextDigests.swift, MetadataIndex.swift, MetadataIndex+Embedding.swift, SearchableMetadataTextsTests.swift)
    - test: green — swift test 132 tests in 13 suites, swiftformat 0/59, swiftlint 0 violations
    - commit: a33ecaf
    - review: findings — Sources/FoundationModelsMetadataRegistry/Catalog/RenderedTextDigests.swift:25, Sources/FoundationModelsMetadataRegistry/Catalog/RenderedTextDigests.swift:28
  timestamp: 2026-09-10T23:31:24.587083+00:00
- actor: claude-code
  id: 01m26trp2q8yqaf6kaz8yfx65s
  text: |
    Both findings come from one cause: `RenderedTextDigests` declares `Equatable`
    and writes no `==`, so the only readers of `block` and `indexedText` are the
    synthesized `==` that `MetadataIndex.hasIdenticalContent(to:)` calls on whole
    values. Periphery cannot see a synthesized body, so it hints
    `assignOnlyProperty`. The `code-hygiene/dead-code-swift` rule names this exact
    case and gives the correction: keep the property and write
    `// periphery:ignore` above it, with the reason on its own comment line.
    Deleting the properties is forbidden by the rule and would make `a == b` true
    for two entries whose block or indexed text differ.

    One point the rule text does not cover: the marker cannot stand between the
    doc comment and the declaration. SwiftLint then reports
    `orphaned_doc_comment` (measured: 2 violations on this file). The reason lines
    and the marker therefore stand above the doc comment, and both tools are
    clean.

    Verification after the change: `review file` on
    `Sources/FoundationModelsMetadataRegistry/Catalog/RenderedTextDigests.swift`
    with the `code-hygiene` validator reports 0 findings, 7 checks attempted, 0
    failed.
  timestamp: 2026-09-10T23:34:37.399064+00:00
- actor: claude-code
  id: 01m26trsehqkf1wtmkwge4yg4z
  text: |
    ### implement — changed
    - evidence: 1 file — Sources/FoundationModelsMetadataRegistry/Catalog/RenderedTextDigests.swift. Both review findings are now `- [x]`. `swift test`: 132 tests in 13 suites, no failure, no warning. `swift test --package-path IntegrationTests`: 5 tests in 4 suites, passed. swiftformat --lint: 0 of 59 files need formatting. swiftlint: 0 violations in 59 files.
    - next: /review
  timestamp: 2026-09-10T23:34:40.849099+00:00
position_column: doing
position_ordinal: '80'
title: 'SearchableMetadata: give the keyword index and the embedder their own texts, apart from the verbatim block'
---
## What

`SearchableMetadata` has two methods, and `renderBlock()` does three jobs at
once:

| job | who reads it | where |
|---|---|---|
| the text BM25 and the trigram index tokenize | `MetadataIndex.buildEntry(item:)` | `Catalog/MetadataIndex.swift` |
| the text the embedder embeds | `MetadataIndex.pendingEmbeddings()` | `Catalog/MetadataIndex+Embedding.swift` |
| the text a `Match` carries back verbatim | `MetadataSearcher.matches(fromHits:in:)` | `MetadataSearcher+Search.swift` |

`renderSummaryBlock()` covers a fourth job, the selection prefix, and a
consumer can override it alone. There is no way to change any one of the
first three without changing the other two.

A consumer that wants a shorter text for ranking must therefore also
shorten the text the model is handed. That is not a trade a consumer can
make: the verbatim block is what the model reads to write the call.

## The measurement that raises it

`FoundationModelsMultitool` measured the three settings on card `^kvefc5z`,
over a nine-entry tool surface, with the selection tier switched off so the
retrieval tier answered alone. Two query groups: ten queries a coding agent
really sent, and fifteen written from a task description alone, with no tool
name in the context that wrote them. The numbers below repeat to the digit,
because nothing on the path samples.

  setting                 group          rank 1   top 3   mean best
  block/block             agentSurface     9/10   10/10        1.10
  block/block             heldOut         10/15   13/15        1.87
  description/description agentSurface      9/10   10/10       1.10
  description/description heldOut           8/15   14/15       1.80
  block/description       agentSurface     10/10   10/10       1.00
  block/description       heldOut           6/15   12/15       2.13

Two readings come out of it:

1. **The halves want different texts.** Giving the embedder the description
   while the keyword index keeps the block moved the ranking in both
   directions — better on one group, worse on the other. That is a real
   effect and a consumer cannot reach it at all today.
2. **The short text is also the cheap text.** The nine blocks are 18,720
   characters; the nine descriptions are 9,057. The embedder reads every
   block one time at the first search, so the batch is about twice the size
   it must be if the description ranks as well.

That consumer chose to keep the full block, because the only lever it has
would strip the signature from the text the model is handed. The choice is
recorded in its `APISurface+SearchableMetadata.swift`. It is a choice made
against the seams that exist, not against the seams it wants.

## What to do

Give the protocol a text for each job, each one defaulting to
`renderBlock()`, so no consumer of today changes at all:

- `renderIndexedText()` — what BM25 and the trigram index tokenize.
- `renderEmbeddedText()` — what the embedder embeds.
- `renderBlock()` — unchanged: what a `Match` carries back verbatim.
- `renderSummaryBlock()` — unchanged: the selection prefix.

Points to settle while doing it:

- `Entry.blockHash` keys embedding reuse. It must hash the embedded text,
  not the block, or a consumer that changes only the embedded text keeps a
  stale vector.
- `MetadataIndex.block(forID:)` and `Match.block` must keep answering the
  verbatim block. Nothing about the splice may move.
- Two texts of one entry that are equal must cost one render and one hash,
  as they do today for every consumer that overrides nothing.

## Acceptance Criteria

- [x] The protocol carries the two new methods, each defaulting to
      `renderBlock()`.
- [x] A consumer that overrides neither gets exactly the behavior of today,
      held by a test.
- [x] A consumer that overrides one gets that text in that signal alone,
      held by a test for each signal.
- [x] Embedding reuse keys on the embedded text, held by a test that changes
      only the embedded text and sees a re-embed.
- [x] `Match.block` still answers the verbatim block, held by a test.

## Tests

- [x] `swift test`: no failure, no warning.
- [x] `swift test --package-path IntegrationTests`: passes.

#catalog #search-tools #metadata

## Review Findings (2026-09-10 19:29)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 5 file(s) reviewed, 9 not reviewed.

> 8 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 8 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `.swiftlint.yml` — no validator matches this file

- [x] `Sources/FoundationModelsMetadataRegistry/Catalog/RenderedTextDigests.swift:25` `code-hygiene/dead-code-swift` — var.instance `block` is assignOnlyProperty.
- [x] `Sources/FoundationModelsMetadataRegistry/Catalog/RenderedTextDigests.swift:28` `code-hygiene/dead-code-swift` — var.instance `indexedText` is assignOnlyProperty.
