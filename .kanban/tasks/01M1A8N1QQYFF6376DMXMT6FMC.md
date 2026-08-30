---
assignees:
- claude-code
depends_on:
- 01M1A97K9T94SEZ0CA0NWT7NZ4
position_column: todo
position_ordinal: '8180'
title: 'Real-model test: a cold MetadataSearcher returns only catalog ids'
---
## What

The first real-model test, and the highest-value card on the board.

File to create:
- `IntegrationTests/Tests/FoundationModelsMetadataRegistryIntegrationTests/ColdSelectionRealModelTests.swift`

Build a `MetadataSearcher` in `.selection` mode over `IntegrationCatalog.base`:

```swift
SelectionConfig(
    model: { instructions in
        LanguageModelSession(model: .default, instructions: instructions)
    },
    preamble: .librarianDefault
)
```

Wrap the model call in `ModelAvailability.recordingEnvironmentFaults(_:)`; call `try ModelAvailability.requireAvailable()` first.

### Use these intents — measured, do not invent new ones

`^nwt7nz4` measured 125 cold runs against `.librarianDefault`. These scored **5/5 across three independent replications**:

- `Pull me a shot of espresso from ground beans.` — imperative
- `Fold a sheet of paper into a crane.` — imperative
- `How do I tune my guitar to concert pitch?`
- `How often should I water a potted orchid?`

The off-topic control returned empty 5/5, so an empty result is reachable and the non-empty assertion is meaningful.

**Measurement result worth knowing:** `.librarianDefault` did **not** reproduce the cold-empty behaviour FoundationModelsRanker measured against `.selectionDefault`. Imperatives were not weaker here — all three scored 5/5. The fresh-searcher-per-query design below still stands, because it is what makes the test capable of catching that defect if it ever appears.

### A FRESH searcher per query

Construct the searcher **inside the test body**, per query. Not one reused across a parameterized run. `LanguageModelSession.fork()` returns `self` (`LanguageModelSessionSupport.swift:100-102`), so a reused searcher is warm from call two onward and cannot see a cold-session defect.

### Assert `.unknownSelectedId` specifically — never "no diagnostics"

`^nwt7nz4` found that `MetadataDiagnostic.embeddingUnavailable` fires on **every** selection search — 55 of 55 runs. `SelectionTier`'s under-budget path calls `retrievalRanking` once per call to attach real `score`/`signals`, and that closure reports the missing embedder. An assertion of "no diagnostics were recorded" would fail on every run for a reason unrelated to the defect this test guards.

Filter for `.unknownSelectedId`. It fired in **zero** of the 125 measured runs.

### What actually gets asserted

Membership is a tautology: `SelectionTier` already filters unresolvable ids before returning and reports them via `.unknownSelectedId` (`SelectionTier.swift:286-289`), so `search()` cannot return a non-catalog id. Keep it as a cheap invariant, but the two observables that can genuinely change are the **non-empty** result and the **absence of `.unknownSelectedId`**.

### Scope

Under-budget cached-root path only. No over-budget case.

## Acceptance Criteria

- [ ] A new `MetadataSearcher` is constructed for every query, inside the test body.
- [ ] The four measured intents above are used verbatim, including both imperatives.
- [ ] Each query returns a **non-empty** result — empty is the exact symptom of the guarded defect.
- [ ] The diagnostic assertion filters for `.unknownSelectedId` and does **not** assert the absence of all diagnostics.
- [ ] Model calls wrapped in `recordingEnvironmentFaults(_:)`; `try requireAvailable()` first.

## Tests

- [ ] `ColdSelectionRealModelTests.swift` — a parameterized `@Test(arguments:)` over the four intents.
- [ ] Run `swift test --package-path IntegrationTests` three times. All queries non-empty every run. Record the rate in a comment.
- [ ] Prove the non-empty assertion can fail: temporarily point the searcher at an empty catalog, confirm failure, revert. This mutates the product input, not the expectation.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.