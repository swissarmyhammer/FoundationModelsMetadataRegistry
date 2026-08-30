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

The first real-model test, and the highest-value card on the board: the only thing that would catch the class of defect FoundationModelsRanker hit in `d333d07`.

File to create:
- `IntegrationTests/Tests/FoundationModelsMetadataRegistryIntegrationTests/ColdSelectionRealModelTests.swift`

Use **only the intents `^nwt7nz4` measured at 5/5**. Do not invent new ones here.

Build a `MetadataSearcher` in `.selection` mode over `IntegrationCatalog`'s base group:

```swift
SelectionConfig(
    model: { instructions in
        LanguageModelSession(model: .default, instructions: instructions)
    },
    preamble: .librarianDefault
)
```

Collect diagnostics through `onDiagnostic:`. Wrap the model call in `ModelAvailability.recordingEnvironmentFaults(_:)` so a `GenerationError` reads as an environment fault, not a product defect.

### A FRESH searcher per query — the whole point

Construct the searcher **inside the test body**, per query. Not one searcher reused across a parameterized run.

Ranker measured this exact defect: on a cold session the model returned `{"ids":[]}` for some queries, 0 of 5 runs succeeding, while the same query on a warm session succeeded every time. A suite that reuses one searcher **cannot see it**, because `LanguageModelSession.fork()` returns `self` (`LanguageModelSessionSupport.swift:100-102`), so the session is warm from call two onward.

### What actually gets asserted

**Membership is a tautology — do not make it the headline.** `SelectionTier` already filters every unresolvable id before returning and reports it via `.unknownSelectedId` (`SelectionTier.swift:286-289`), so `search(intent:limit:)` *cannot* return a non-catalog id. Keep the membership check as a cheap invariant, but the two observables that can genuinely change are:

1. the result is **non-empty**, and
2. **no `.unknownSelectedId` fired**.

Those are the criteria.

### Scope

Under-budget cached-root path only. No over-budget case: those mechanics are at 97% line coverage via fakes, and the model-behavior half belongs to Ranker.

## Acceptance Criteria

- [ ] A new `MetadataSearcher` is constructed for every query, inside the test body.
- [ ] Every intent used comes from `^nwt7nz4`'s 5/5 list, and at least one is an imperative.
- [ ] Each on-topic query returns a **non-empty** result — empty is the exact symptom of the guarded defect.
- [ ] No `.unknownSelectedId` diagnostic is recorded for any query.
- [ ] Model calls are wrapped in `recordingEnvironmentFaults(_:)`, and the test calls `try ModelAvailability.requireAvailable()` first.

## Tests

- [ ] `ColdSelectionRealModelTests.swift` — a parameterized `@Test(arguments:)` over the chosen intents.
- [ ] Run `swift test --package-path IntegrationTests` three times. All queries non-empty every run. Record the rate in a comment; a query not stable across three runs is replaced from `^nwt7nz4`'s list, never retried in a loop.
- [ ] Prove the non-empty assertion can fail: temporarily point the searcher at an empty catalog, confirm failure, revert. This mutates the product input, not the expectation.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.