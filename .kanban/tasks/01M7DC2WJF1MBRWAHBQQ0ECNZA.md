---
assignees:
- claude-code
position_column: done
position_ordinal: be80
title: 'Adopt FoundationModelsRanker ddb39a1: nil cosine means no embedding, zero and negative cosine scores rank'
---
## What

FoundationModelsRanker `main` moved to `ddb39a1` ("feat!: rank zero and negative cosine scores; nil cosine means no embedding"). This repository resolves the Ranker by `branch: "main"`, so a fresh resolve (CI, a new worktree) gets `ddb39a1`. With `ddb39a1`, two unit tests fail:
- `EmbeddingTests.cosineSignalRanksASemanticMatchAboveWhatKeywordSignalsAloneFind`
- `SharedCatalogEmbeddingTests.twoConcurrentFirstSearchesOnTwoSharingSearchersEmbedTheCatalogOneTime`

The local main tree is on `6156346`, where all tests pass. The decision tier worktrees pin `6156346` in the local `Package.resolved` (which git ignores).

1. Read the `ddb39a1` change in `/Users/wballard/github/swissarmyhammer/FoundationModelsRanker` (`git show ddb39a1`): the new meaning of a nil cosine and of a zero or negative cosine score.
2. Find the cause of each failure. Change the registry code where it gives a cosine value or an "absent" value to the Ranker (for example `Signals.cosine`, the absent-signal rule of plan.md §5, `MetadataIndex+Embedding.swift`, `MetadataSearcher+RetrievalTier.swift`), or change the test when the test pins the old meaning. No backward compatibility (ARCHITECTURE.md).
3. Update the doc comments that state "every `Match.signals.cosine` is `0.0`" when no embedding is present, if the meaning is now `nil`.

## Acceptance Criteria
- [ ] With FoundationModelsRanker resolved to `ddb39a1` or later, `swift test` at the root passes.
- [ ] No doc comment states the old cosine meaning.

## Tests
- [ ] The two tests above pass (changed only if they pin the old meaning, with the reason in the commit message).
- [ ] Run `swift package update FoundationModelsRanker` then `swift test`. All tests pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.