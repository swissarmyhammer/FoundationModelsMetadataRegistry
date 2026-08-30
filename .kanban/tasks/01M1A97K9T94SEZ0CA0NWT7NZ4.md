---
assignees:
- claude-code
depends_on:
- 01M1A8MDQ9NTZX4A0N8JZBA4XN
position_column: todo
position_ordinal: '8580'
title: Measure librarianDefault on cold sessions and select stable intents
---
## What

Before either test is written, measure which intents actually work. This card produces **data**, not a test.

### Why this must come first

FoundationModelsRanker measured the cold-session defect against `.selectionDefault`, which is `SelectionConfig`'s own default (`SelectionConfig.swift:93`). Both test cards pin `preamble: .librarianDefault` — this package's own, different text — which says:

```
Do not invent functions; return an empty list if nothing fits.
```
(`Sources/FoundationModelsMetadataRegistry/SelectionPreamble.swift:14-15`)

The `@Guide` on the generable output repeats it: "empty if nothing in the candidate set fits the intent" (Ranker's `Selection/Selection.swift:23-26`).

So the plan is about to make "returns at least one match" an acceptance criterion while wiring the preamble that most invites the empty answer that criterion forbids. **Ranker's 0/5-to-5/5 numbers do not transfer** — different preamble, and their own caveat was that the causal story is unproven across four queries and one model version.

Measuring after the tests are written is too late to change the fixture cheaply.

### What to do

Write a throwaway probe (scratchpad, not committed) that, for each candidate intent:
- constructs a **fresh** `MetadataSearcher` in `.selection` mode over `IntegrationCatalog`'s base group, with `preamble: .librarianDefault` and a real `LanguageModelSession(model: .default, instructions:)` factory;
- runs one `search(intent:limit:)`;
- records whether the result was non-empty and whether `.unknownSelectedId` fired.

Run each candidate **5 times, cold each time**. Include a mix of phrasings, with at least two imperatives ("record my staged changes as a new commit") and two interrogatives ("how do I list or delete a branch"), plus one off-topic control that SHOULD return empty.

### What to record

Post a comment on this card with the pass rate per intent, in the shape Ranker used:

```
intent                                        cold pass rate
record my staged changes as a new commit      5/5
...
```

Then pick the intents for `^xmt6fmc` and `^ddaxwaz`: **only those at 5/5**, keeping at least one imperative. If no imperative reaches 5/5, say so plainly — that is itself the finding, and it means `.librarianDefault` behaves differently from `.selectionDefault` and the test cards need rescoping rather than fudging.

Do not tune the preamble to make intents pass. Changing shipped behavior to suit a test is out of scope for this card.

## Acceptance Criteria

- [ ] Every candidate intent measured 5 times on a cold session against `.librarianDefault`.
- [ ] Pass rates recorded as a comment on this card, per intent.
- [ ] The off-topic control returns empty, confirming empty results are reachable and the assertion is meaningful.
- [ ] A named set of 5/5 intents is chosen for the two test cards, including at least one imperative — or a plain statement that none qualified, with the numbers.
- [ ] The probe is deleted, not committed.

## Tests

- [ ] This card ships no test. Its output is the measurement comment and the chosen intent list, which `^xmt6fmc` and `^ddaxwaz` consume.
- [ ] Verify no probe file remains: `git status --porcelain` is clean apart from `.kanban/`.

## Workflow
- Measurement only. No `/tdd` — there is no product change here.