---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m1adrsh427mx83c3549xqdgm
  text: |-
    Picked up. Research notes before writing the test:

    - The four intents and both facts the card carries were read off `^nwt7nz4`'s measurement comment, not re-derived. `.embeddingUnavailable` on every selection search (55 of 55) and `.unknownSelectedId` in 0 of 125 runs are that card's numbers.
    - `MetadataSearcher.init(items:mode:weights:selection:onDiagnostic:)` is the SYNCHRONOUS initializer (the `embedder:` overload is the `async` one), so a fresh searcher costs nothing to build inside the test body. That is what keeps every query cold: `LanguageModelSession.fork()` returns `self` (`.build/checkouts/FoundationModelsRanker/Sources/FoundationModelsRanker/Selection/LanguageModelSessionSupport.swift`), so one reused searcher is warm from call two.
    - `SelectionConfig(model:preamble:capacityCharacterLimit:candidateLimit:)` takes `@escaping @Sendable (String) -> any AgentSession` and builds a `.factory` session source. `preamble:` defaults to Ranker's neutral `.selectionDefault`, so `.librarianDefault` has to be stated.
    - The integration package can reach no test-support type of the root package: a test target is not a product, and `IntegrationTests/Package.swift` depends on the one library product alone. So the root suite's `DiagnosticRecorder` (`Tests/FoundationModelsMetadataRegistryTests/TestSupport/DiagnosticRecorder.swift`, an `@unchecked Sendable` class over an `NSLock`) is unreachable here.
      - Rather than copy it, the test collects diagnostics in an `OSAllocatedUnfairLock<[MetadataDiagnostic]>`. It is `Sendable` and `Copyable`, so an `@escaping @Sendable` closure can capture it and no `@unchecked Sendable` conformance is needed. `Synchronization.Mutex` was rejected: it is `~Copyable`, so an escaping closure cannot capture it at all.
    - `limit:` is `IntegrationCatalog.base.count` — the catalog's own size rather than a literal.
    - Assertion set is exactly what the card names: non-empty, every returned id in the catalog, and no `.unknownSelectedId`. The measurement recorded which id each intent reaches, but the card does not ask for that assertion and adding it would widen what the test claims beyond what it was written to guard.
  timestamp: 2026-08-30T22:48:45.348054+00:00
- actor: claude-code
  id: 01m1adztsd28ta74mcd1z8knmr
  text: |-
    ## The measurement this card owes, and the failure proof

    ### RED first, and the failure was the right one
    The test was written with `let catalog = [IntegrationItem]()` in the searcher's place, which is the card's own mutation: it changes the PRODUCT INPUT, never the expectation. `swift test --package-path IntegrationTests --filter ColdSelection` then failed 4 of 4 cases, each on `!matches.isEmpty` at `ColdSelectionRealModelTests.swift:106:9`, and on NO other assertion. The membership and `.unknownSelectedId` assertions both held over the empty answer, which is what makes the failure legible: the run failed for the symptom the card names, not for a typo. The whole run took 0.011 s, because an empty catalog never reaches the model at all.

    Then `catalog` was pointed at `IntegrationCatalog.base` and the same four cases passed.

    ### The rate, over the shipped code
    `swift test --package-path IntegrationTests`, three consecutive runs after the final edit:

    ```
    run   suites   tests   cases   result   time
    1     3        3       4       pass     3.06 s
    2     3        3       4       pass     2.47 s
    3     3        3       4       pass     2.59 s
    ```

    **12 of 12 query outcomes non-empty. Zero `.unknownSelectedId` in all 12.** Four earlier runs of the same file over `IntegrationCatalog.base` (before the `ModelAvailability` doc edit) were also 4/4, so 28 of 28 cold queries answered non-empty across seven runs in total. No flake, and no retry logic anywhere in the test.

    `swift build --package-path IntegrationTests --build-tests` is clean: zero warnings, zero errors. Root `swift test` is unchanged at 115 tests in 12 suites.

    ### The `// periphery:ignore` on `recordingEnvironmentFaults` is discharged
    `ModelAvailability.recordingEnvironmentFaults(_:)` carried `// periphery:ignore` and a doc line saying "the scenarios that call this arrive in their own changes". This card IS that change: the wrapper now has a caller. The staging contract keeps a marker only until the change it was written for lands, and swiftlint/periphery has no unfulfilled-suppression check that would ask for it back — so it had to come out by hand. The marker and the sentence that justified it were replaced with one naming the caller. That is the only edit outside the new file, and it is caused by this card rather than adjacent to it.

    ### Two implementation notes for the next agent
    - **The diagnostic sink is an `OSAllocatedUnfairLock<[MetadataDiagnostic]>`, not a recorder class.** The root suite's `DiagnosticRecorder` is unreachable here (a test target is not a product), and copying it would have added an `@unchecked Sendable` conformance this package would then have to justify. `Synchronization.Mutex` was tried first and does not work: it is `~Copyable`, so the `@escaping @Sendable` `onDiagnostic` closure cannot capture it. `OSAllocatedUnfairLock` is `Sendable` and `Copyable`, which is why `MetadataSearcher` itself uses it.
    - **`arguments: measuredIntents` resolves unqualified inside the `@Test` attribute** — no `Self.` and no type name needed. Confirmed by the compile.

    The expected id for each intent is deliberately NOT asserted. `^nwt7nz4` recorded which id each intent reaches, but the card's "What actually gets asserted" names three assertions and that is not one of them; adding it would make the test claim more than it was written to guard, and would couple it to a ranking that is not the defect under test.
  timestamp: 2026-08-30T22:52:36.013518+00:00
- actor: claude-code
  id: 01m1ae015jq0tdc984h6hd75f7
  text: |-
    ### implement — changed
    - evidence: 2 files — `IntegrationTests/Tests/FoundationModelsMetadataRegistryIntegrationTests/ColdSelectionRealModelTests.swift` (new), `IntegrationTests/Tests/FoundationModelsMetadataRegistryIntegrationTests/Support/ModelAvailability.swift` (the discharged `// periphery:ignore`). `swift test --package-path IntegrationTests` three times: 3 tests in 3 suites pass each run, the parameterized test 4 of 4 cases each run, 12 of 12 query outcomes non-empty, zero `.unknownSelectedId`. RED proved first with an empty catalog: 4 of 4 cases failed on `!matches.isEmpty` and on nothing else. `swift build --package-path IntegrationTests --build-tests` clean. Root `swift test` unchanged at 115 tests in 12 suites. No commit; `stash@{0}` untouched.
    - next: `/review`. Every acceptance criterion and every test box on the card is ticked.
  timestamp: 2026-08-30T22:52:42.546329+00:00
- actor: claude-code
  id: 01m1ae5ewtz3awep3dmr5gfkba
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit e687da5) — 0 findings, 0 confirmed, 0 refuted, 7 validators attempted, 0 failed, 0 skipped. 2 files reviewed; 6 `.kanban/` files excluded by `.reviewignore`. Zero new findings; all prior checklist items checked.
    - next: none. Task moved to done.
  timestamp: 2026-08-30T22:55:40.442961+00:00
- actor: claude-code
  id: 01m1ae6cz8njsn9f5zcgv6jfgd
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 2 files: IntegrationTests/Tests/.../ColdSelectionRealModelTests.swift (new), .../Support/ModelAvailability.swift (periphery:ignore discharged now that recordingEnvironmentFaults has a caller)
    - test: green — RED first with an empty catalog: all 4 cases failed on `!matches.isEmpty` alone. Then 3 consecutive `swift test --package-path IntegrationTests` runs, 3 tests in 3 suites passing each, **12 of 12 query outcomes non-empty, zero .unknownSelectedId**. swift build --package-path IntegrationTests --build-tests: 0 warnings, 0 errors. Root swift test: 115 tests in 12 suites, unchanged.
    - commit: e687da5 test(integration): add cold MetadataSearcher real-model selection test
    - review: clean — 0 findings, 7 validators, task moved to done

    ### The three things the reviewer verified, not assumed
    1. **The searcher really is per query.** `catalog`, `recorded` and `searcher` are all locals of the test body. The only suite-level state is an immutable `[String]` of intents — no session. Each case's `LanguageModelSession` is built inside a `SelectionConfig` constructed fresh for that case. Nothing warm crosses cases, which is the whole point: `fork()` returns `self`, so a hoisted searcher would be warm from call two and blind to the defect this test guards.
    2. **The non-empty assertion is reachable and ordered first**, so an empty return fails on that line alone.
    3. **The diagnostic filter survives company.** `compactMap` with `guard case .unknownSelectedId` drops every other case, so an `.unknownSelectedId` sitting among 55 `.embeddingUnavailable` entries is still extracted and still fails.

    ### One honest limit on the RED, recorded by the reviewer
    `limit: catalog.count` binds the limit to the same catalog, so the empty-catalog RED also drives `limit: 0`. That proves the assertion is **reachable**, not specifically that a populated catalog with an empty model answer would fail it. The real-path evidence for that is `^nwt7nz4`'s off-topic control returning empty 5/5 over a populated catalog. Not a finding — the binding is deliberate and documented in the file — but worth knowing the proof is two-part.

    ### Design note carried forward
    The diagnostic sink is `OSAllocatedUnfairLock<[MetadataDiagnostic]>`, not the root suite's `DiagnosticRecorder` (unreachable — a test target is not a product) and not `Synchronization.Mutex`, which is `~Copyable` and so cannot be captured by the `@escaping @Sendable` `onDiagnostic` closure.
  timestamp: 2026-08-30T22:56:11.240792+00:00
depends_on:
- 01M1A97K9T94SEZ0CA0NWT7NZ4
position_column: done
position_ordinal: 9f80
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

`^nwt7nz4` found that `MetadataDiagnostic.embeddingUnavailable` fires on **every** selection search — 55 of 55 runs. `SelectionTier`'s under-budget path calls `retrievalRanking` once per call to attach real `score`/`signals`, and that closure reports the missing embedder. An assertion of "no diagnostics were recorded" would fail on every run, for a reason unrelated to the defect this test guards.

Filter for `.unknownSelectedId`. It fired in **zero** of the 125 measured runs.

### What actually gets asserted

Membership is a tautology: `SelectionTier` already filters unresolvable ids before returning and reports them via `.unknownSelectedId` (`SelectionTier.swift:286-289`), so `search()` cannot return a non-catalog id. Keep it as a cheap invariant, but the two observables that can genuinely change are the **non-empty** result and the **absence of `.unknownSelectedId`**.

### Scope

Under-budget cached-root path only. No over-budget case.

## Acceptance Criteria

- [x] A new `MetadataSearcher` is constructed for every query, inside the test body.
- [x] The four measured intents above are used verbatim, including both imperatives.
- [x] Each query returns a **non-empty** result — empty is the exact symptom of the guarded defect.
- [x] The diagnostic assertion filters for `.unknownSelectedId` and does **not** assert the absence of all diagnostics.
- [x] Model calls wrapped in `recordingEnvironmentFaults(_:)`; `try requireAvailable()` first.

## Tests

- [x] `ColdSelectionRealModelTests.swift` — a parameterized `@Test(arguments:)` over the four intents.
- [x] Run `swift test --package-path IntegrationTests` three times. All queries non-empty every run. Record the rate in a comment.
- [x] Prove the non-empty assertion can fail: temporarily point the searcher at an empty catalog, confirm failure, revert. This mutates the product input, not the expectation.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.