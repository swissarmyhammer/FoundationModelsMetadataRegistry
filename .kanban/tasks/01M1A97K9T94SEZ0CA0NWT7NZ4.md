---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m1acxsv2n0nda3eesydcgv00
  text: |-
    Picked up. Research notes before the probe run:

    - `IntegrationCatalog.base` is NOT a git/API fixture. It holds four one-line entries: `brewEspresso`, `tuneGuitar`, `waterOrchid`, `foldOrigami`. The card's illustrative intents ("record my staged changes as a new commit") come from FoundationModelsRanker's own catalog and cannot be used here. The candidate intents must speak to this fixture instead, while keeping the card's shape: at least two imperatives, at least two interrogatives, one off-topic control.
    - `SelectionConfig(model:)` takes `@Sendable (String) -> any AgentSession`. `LanguageModelSession` gets its `AgentSession` conformance from FoundationModelsRanker's `Selection/LanguageModelSessionSupport.swift`, so `SelectionConfig(model: { LanguageModelSession(model: .default, instructions: $0) }, preamble: .librarianDefault)` compiles with no shim.
    - The probe cannot import the integration test target (a test target is not a product), so it restates the `IntegrationItem` struct and the four `base` blocks verbatim. The measurement is over exactly the same text.
    - Cold per run is enforced by building a new `MetadataSearcher` for every one of the 5 runs. `LanguageModelSession.fork()` returns `self`, so a reused searcher is warm from call two and would hide the defect being measured.
    - The probe lives in the scratchpad as its own SwiftPM executable package with `.package(path:)` back to this repo. Nothing is written inside the repo.
  timestamp: 2026-08-30T22:34:00.930701+00:00
- actor: claude-code
  id: 01m1ada9n0jv6a13ch9f1bf16s
  text: |-
    ## Measurement: `.librarianDefault` on cold sessions

    **Method.** A throwaway SwiftPM executable in the scratchpad, `.package(path:)` back to this repo. For each run it builds a **new** `MetadataSearcher` in `.selection` mode, with `preamble: .librarianDefault` and `SelectionConfig(model: { instructions in LanguageModelSession(model: .default, instructions: instructions) })`, then makes exactly one `search(intent:limit: catalog.count)` call and throws the searcher away. A new searcher per run is what keeps every run cold: `LanguageModelSession.fork()` returns `self`, so one reused searcher is warm from call two and hides the defect this card measures. Diagnostics were collected through `onDiagnostic:`. The fixture blocks are `IntegrationCatalog`'s own text, copied verbatim (a test target is not a product, so the probe cannot import it).

    Machine: macOS 27.0 (26A5416b), Swift 6.4, `SystemLanguageModel.default.availability == .available`.

    ### Pass rates — `IntegrationCatalog.base`

    Three independent replications of 5 cold runs each. Every replication gave the same number, so one column carries them all.

    ```
    intent                                          mood            cold pass rate   id returned
    Pull me a shot of espresso from ground beans.   imperative      5/5              brewEspresso
    Fold a sheet of paper into a crane.             imperative      5/5              foldOrigami
    Water the orchid on the windowsill.             imperative      5/5              waterOrchid
    How do I tune my guitar to concert pitch?       interrogative   5/5              tuneGuitar
    How often should I water a potted orchid?       interrogative   5/5              waterOrchid
    How do I make an espresso?                      interrogative   5/5              brewEspresso
    Rebuild the transmission on a diesel truck.     control         0/5 (empty)      —
    ```

    ### Pass rates — the hot-reload fixtures, for `^ddaxwaz`

    The base group alone cannot serve `^ddaxwaz`, which needs an intent only the add-only item answers and an intent the remove-only item would have answered. Those were measured too, on the catalogs that card starts from and ends at.

    ```
    catalog           intent                                 mood            cold pass rate   id returned
    base+removeOnly   Dye this fleece yarn with indigo.      imperative      5/5              dyeWool
    base+addOnly      Sharpen my dull hockey skate blades.   imperative      5/5              sharpenSkates
    base+addOnly      How do I hone a blunt skate blade?     interrogative   5/5              sharpenSkates
    base+addOnly      Dye this fleece yarn with indigo.      imperative      0/5 (empty)      —
    ```

    The last row is the remove half's control: the same intent that reaches `dyeWool` 5/5 while the item is present returns empty 5/5 once it is gone. That makes `^ddaxwaz`'s remove-half assertion load-bearing rather than vacuous — the intent demonstrably can reach the id, so its absence measures the removal.

    ### The finding on imperatives

    **Imperatives are not weaker than interrogatives here. Four imperatives reached 5/5 cold.** `.librarianDefault` did not produce the cold `{"ids":[]}` answer FoundationModelsRanker measured against `.selectionDefault`; no candidate scored below 5/5, and no run needed a warm session to succeed. Across 125 cold runs in total there was not one empty result on an answerable intent, and not one thrown error. The card's worry — that `.librarianDefault`'s "return an empty list if nothing fits" would invite the empty answer — is not what this machine and this model version measured. No preamble was tuned, and no shipped behavior was changed.

    Two caveats the test cards should carry, matching Ranker's own: this is one machine and one model version, and these fixture entries are short single-subject blocks whose vocabularies are disjoint by design, which is an easier selection problem than a real API surface.

    ### Empty results are reachable

    Both controls confirm it. The off-topic control returned empty on 5 of 5 cold runs over `base`, and the removed-item intent returned empty on 5 of 5 over `base+addOnly`. The selection tier is capable of answering empty, so "non-empty" is a real assertion rather than one that cannot fail.

    ### Discovery the two test cards must act on

    **`MetadataDiagnostic.embeddingUnavailable` fires on every single selection search — 55 of 55 runs in the last replication.** This package wires no embedder, and `SelectionTier`'s **under-budget** path still calls `retrievalRanking` once per call to attach real `score`/`signals` (`SelectionTier.swift`, after the `assembledPrefix.count <= config.capacityCharacterLimit` guard). That closure runs `computeCosineScores`, which reports `.embeddingUnavailable` when no embedder is configured.

    So a test in `^xmt6fmc` or `^ddaxwaz` that asserts "no diagnostics were recorded" will fail on every run, for a reason that has nothing to do with the defect being guarded. Both cards already word their criterion correctly — *no `.unknownSelectedId`* — and the assertion must be written exactly that way: filter the recorded diagnostics for `.unknownSelectedId`, never check the collection for emptiness.

    `.unknownSelectedId` never fired in any of the 125 cold runs.

    ### Chosen intents

    Every candidate qualified, so the two cards may draw from the whole list. The named sets:

    **For `^xmt6fmc`** (cold selection over `IntegrationCatalog.base`) — four intents, two imperative and two interrogative:

    - `Pull me a shot of espresso from ground beans.` (imperative) — expects `brewEspresso`
    - `Fold a sheet of paper into a crane.` (imperative) — expects `foldOrigami`
    - `How do I tune my guitar to concert pitch?` (interrogative) — expects `tuneGuitar`
    - `How often should I water a potted orchid?` (interrogative) — expects `waterOrchid`

    Off-topic control, if that card wants one: `Rebuild the transmission on a diesel truck.` returns empty 5/5. It is not part of the non-empty assertion.

    **For `^ddaxwaz`** (hot reload):

    - add half: `Sharpen my dull hockey skate blades.` (imperative) — expects `sharpenSkates` after `update(items:)` adds it
    - remove half: `Dye this fleece yarn with indigo.` (imperative) — returns `dyeWool` while present, empty once removed

    Spare, if either card needs a replacement: `Water the orchid on the windowsill.` (imperative, 5/5), `How do I make an espresso?` (interrogative, 5/5), `How do I hone a blunt skate blade?` (interrogative, 5/5 for `sharpenSkates`).

    ### Probe deleted

    The scratchpad package is removed. `git status --porcelain` reports only `.kanban/` files. `stash@{0}` untouched.
  timestamp: 2026-08-30T22:40:50.336372+00:00
- actor: claude-code
  id: 01m1adazvq3ncd3am1j6xczqcn
  text: |-
    ### implement — changed
    - evidence: no repository files changed. The card's product is data. 125 cold real-model runs measured through a scratchpad probe, now deleted. Every answerable candidate 5/5, both empty-controls 5/5 empty, `.unknownSelectedId` never fired. Chosen sets named for `^xmt6fmc` and `^ddaxwaz` in the measurement comment above. `git status --porcelain` shows only `.kanban/`.
    - next: `/review`, then `^xmt6fmc` and `^ddaxwaz` unblock. Both must assert on `.unknownSelectedId` specifically, never on an empty diagnostic collection — `.embeddingUnavailable` fires on every selection search.
  timestamp: 2026-08-30T22:41:13.079926+00:00
depends_on:
- 01M1A8MDQ9NTZX4A0N8JZBA4XN
position_column: doing
position_ordinal: '80'
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

- [x] Every candidate intent measured 5 times on a cold session against `.librarianDefault`.
- [x] Pass rates recorded as a comment on this card, per intent.
- [x] The off-topic control returns empty, confirming empty results are reachable and the assertion is meaningful.
- [x] A named set of 5/5 intents is chosen for the two test cards, including at least one imperative — or a plain statement that none qualified, with the numbers.
- [x] The probe is deleted, not committed.

## Tests

- [x] This card ships no test. Its output is the measurement comment and the chosen intent list, which `^xmt6fmc` and `^ddaxwaz` consume.
- [x] Verify no probe file remains: `git status --porcelain` is clean apart from `.kanban/`.

## Workflow
- Measurement only. No `/tdd` — there is no product change here.