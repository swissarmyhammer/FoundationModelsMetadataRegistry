---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m251njfh6ch9trs0sg5wxwq1
  text: |-
    Research done. The ranker `main` is now `2f0bd16`; `swift package update` moved the pin from `5ab7b1a` to it. With the new pin, `swift build` gives one deprecation warning (the `retrievalRanking` initializer) and `swift test` does not compile (`candidateLimit` in `HotReloadTests`).

    The blast radius is wider than the three uses on the card, because the tier stopped ranking at all:

    - `SelectionMatch` now carries `score = 1 / rank` (the model's order) and `signals = nil`. `SelectionTests` asserts the old "real fused score and signals" rule in two tests, so those must change too.
    - The `Weights(cosine: 0.0)` argument in several selection tests was there only to stop the selection path from reporting `.embeddingUnavailable`. The selection path embeds nothing now, so the argument and its comment are stale.
    - `HotReloadTests.contentUnchangedEmbedCatchUpMakesMergedEmbeddingsVisibleToOverBudgetCandidateRanking` tests the over-budget candidate ranking. That ranking no longer exists, so the test has no behavior left to hold. The neighbouring test above it already proves the catch-up merge reaches the retrieval tier.
    - `ConfiguredSelectionTier` boxes its index snapshot in an `OSAllocatedUnfairLock` only so `catchUpEmbeddings` can refresh it for the candidate ranking. A merge changes stored vectors and never content, so with the ranking gone the refresh has no effect a caller can see. The snapshot becomes a plain value.
    - `BigCatalogCore` says its over-budget demo always reports `.retrievalCut`. It never will now.

    Decision on the third use: keep this package's `.retrievalCut` case and its mapping. `RankDiagnostic` keeps the case for exactly this reason, and `MetadataDiagnostic.init(_:)` cannot drop the case without becoming failable.

    Decision on the "Also" note: this package keeps `String.librarianDefault` for callers whose catalog is an API surface, not to correct the ranker default. The condition on the card does not hold, so the preamble stays.
  timestamp: 2026-09-10T06:56:46.577331+00:00
- actor: claude-code
  id: 01m2523vgt88h81xd8q0a0acq7
  text: |-
    ### implement — changed
    - evidence: 9 files. `swift build` gives no error and no warning. `swift test` reports 120 tests in 12 suites passed. `swift build --package-path IntegrationTests --build-tests` is clean. `swiftlint lint` reports no violation.
    - what changed:
      - `MetadataSearcher` builds the tier with `SelectionTier(catalog:config:onDiagnostic:)`. `rankEntireCatalog` is gone, and `buildSelectionTierIfConfigured` no longer takes the weights or the embedder. `ConfiguredSelectionTier` holds a plain index snapshot instead of an `OSAllocatedUnfairLock`, and `catchUpEmbeddings` no longer refreshes it. `import os` is gone with the lock.
      - `MetadataDiagnostic.retrievalCut` and its mapping stay, with a doc line that says the ranker never reports it.
      - `Match.score` and `Match.signals` now document the order score (`1 / rank`) and the always-`nil` signals of a selection match.
      - `OverBudgetTests` is written again for the split design: one prompt for each run in catalog order, each prompt naming only its own run's ids, a fresh session for each run of each search, no fork, order scores, an id from another run that still resolves, an id outside the catalog reported as unknown, and no `.retrievalCut`.
      - `SelectionTests` asserts the order score and the absent signals, and drops the `Weights(cosine: 0.0)` that only damped a diagnostic the selection path no longer emits.
      - `HotReloadTests` loses the over-budget candidate-ranking test, which had no behavior left to hold.
      - `BigCatalogCore`, `BigCatalog/main.swift`, `ExamplesSupport` and the `Package.swift` comment describe the split, and `BigCatalogCore.printDiagnostic` is gone because its one case is never reported. `runBigCatalogOverBudgetSelection` now defaults `onDiagnostic` to `MetadataDiagnostic.log(_:)`.
    - next: `/review`
  timestamp: 2026-09-10T07:04:34.586574+00:00
- actor: claude-code
  id: 01m253px3jmw3tn4rjm9v6y20y
  text: |-
    ### review — findings
    - evidence: 3 findings — Sources/FoundationModelsMetadataRegistry/MetadataSearcher+Search.swift:246, Tests/FoundationModelsMetadataRegistryTests/EmbeddingCatchUpTests.swift:29, Tests/FoundationModelsMetadataRegistryTests/EmbeddingCatchUpTests.swift:125
    - next: correct the three findings, then run the review again. The task stays in the review column.
  timestamp: 2026-09-10T07:32:27.378436+00:00
- actor: claude-code
  id: 01m253qa0gt0yv30frxbk5qe67
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 9 files
    - test: green — swift test, 120 passed, 0 failed, 0 skipped
    - commit: 20ec680
    - review: findings — Sources/FoundationModelsMetadataRegistry/MetadataSearcher+Search.swift:246, Tests/FoundationModelsMetadataRegistryTests/EmbeddingCatchUpTests.swift:29, Tests/FoundationModelsMetadataRegistryTests/EmbeddingCatchUpTests.swift:125
  timestamp: 2026-09-10T07:32:40.592048+00:00
- actor: claude-code
  id: 01m253w03r2sxbst1nrzr20bwa
  text: |-
    Worked the three review findings. Each cause was removed from the whole file, not only the named line.

    1. `MetadataSearcher+Search.swift` — `index.count > 0` became `!index.ids.isEmpty`. `index.ids` is the exact set of entries, so no new public API is needed. The file holds no other comparison of a count against zero; the two other count expressions (`vectors.count == ids.count`) compare two counts, which the rule does not read.
    2. `EmbeddingCatchUpTests.swift` — the file now names its numbers: `catchUpEmbeddingDimension` for the vector width (was the literal `2` at two `dimension:` arguments) and `catchUpSearchLimit` for the `limit:` of every search (was the literal `5` at nine calls). The `pending:`/`total:` pair of the `.embedCatchUp` expectations reads `Self.unembeddedItems.count`, which ties the number to the fixture instead of repeating `2`.
    3. `EmbeddingCatchUpTests.swift` — `embeddedBatches.filter { ... }.count == 1` became `embeddedBatches.count(where: { ... }) == 1`. The file holds no other `filter(_:).count`.

    Verification: `swift build` is clean, `swift test` reports 120 tests in 12 suites passed, `swift build --package-path IntegrationTests --build-tests` is clean, and `swiftlint lint` on the two edited files exits 0.

    Note for the next agent: a plain `swiftlint lint` at the repo root now walks `.build`, so it reports many violations in generated `test_entry_point.swift` and in the checked-out FoundationModelsRanker sources. Those are not this package's files. Give swiftlint the source directories, or the files you changed, to get a true answer.
  timestamp: 2026-09-10T07:35:14.296492+00:00
- actor: claude-code
  id: 01m253w3h28zz6xc8jh9p0t0pg
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsMetadataRegistry/MetadataSearcher+Search.swift, Tests/FoundationModelsMetadataRegistryTests/EmbeddingCatchUpTests.swift. `swift build` clean, `swift test` 120 tests in 12 suites passed, `swiftlint lint` on both files exits 0. All 3 review findings are now `- [x]`.
    - next: `/review`
  timestamp: 2026-09-10T07:35:17.794517+00:00
- actor: claude-code
  id: 01m2549ajvaksm6sy1y4q4cnpv
  text: |-
    ### finish iteration 2 — stuck
    - implement: changed — 2 files, all 3 review findings worked
    - test: stuck — swift test 120 passed, 0 failed, 0 skipped, 0 compiler warnings; swiftlint reports 44 `trailing_comma` warnings
    - commit: 1f7f4f8
    - review: not run

    ## Blocker — a rule conflict a person must settle

    SwiftFormat's default `trailingCommas` rule adds a trailing comma to the last item of a
    multi-line array, dictionary or argument list. SwiftLint's default `trailing_comma` rule
    (`mandatory_comma: false`) reports that same comma as a violation. The repository holds no
    `.swiftformat` file and no `.swiftlint.yml` file, so nothing makes the two tools agree.

    Proof, both directions:
    - After a clean `swiftformat` run, `swiftlint` reports 44 `trailing_comma` warnings.
    - After a clean `swiftlint --fix` run, `swiftformat --lint` reports 20 files that need a change.

    No setting inside the code makes both tools pass. A person must pick one side and add the
    matching config file:
    - `.swiftlint.yml` with `trailing_comma: { mandatory_comma: true }`, or the rule disabled; or
    - `.swiftformat` that turns the trailing-comma behavior off.

    Then start this task again.
  timestamp: 2026-09-10T07:42:31.003126+00:00
- actor: claude-code
  id: 01m25kp7k98ybgste0zpzyqqev
  text: |
    ## Blocker settled by the user (2026-09-10)

    The user picked the side: keep the trailing comma that SwiftFormat writes, and make
    SwiftLint agree.

    Action for the next implement step: add `.swiftlint.yml` at the repository root with

    ```yaml
    trailing_comma:
      mandatory_comma: true
    ```

    Do not rewrite the source files. Do not turn the rule off. After the file is added,
    `swiftlint` on this package's sources must report no `trailing_comma` violation, and
    `swiftformat --lint` must report no file that needs a change.

    Note: give swiftlint the source directories, not the repository root, because the root
    walk enters `.build`.
  timestamp: 2026-09-10T12:11:42.569576+00:00
- actor: claude-code
  id: 01m25kt80s2g1243w78ezx6s2g
  text: |-
    Did the action the user picked for the blocker. Added `.swiftlint.yml` at the repository root with `trailing_comma: { mandatory_comma: true }`. No source file lost a comma, the rule stays on, and `swiftlint --fix` did not run.

    SwiftLint reads the new file correctly: the 44 `trailing_comma` warnings in this package's own files are gone.

    Two other violations came out of this package's own files when the trailing-comma noise stopped. Corrected both:

    1. `Examples/LibrarianCore/LibrarianCore.swift` — the `weather` entry of `tripPlanningCatalog` was 124 characters on one line (`line_length`, limit 120). The call now goes on more than one line, with the trailing comma SwiftFormat writes.
    2. `Sources/FoundationModelsMetadataRegistry/Catalog/Diagnostics.swift` and `Sources/FoundationModelsMetadataRegistry/MetadataSearcher+Search.swift` — SwiftFormat reported 7 `hoistPatternLet` changes (`case .retrievalCut(let considered, let kept)` became `case let .retrievalCut(considered, kept)`). Ran SwiftFormat on those two files only. SwiftLint agrees with the hoisted form, so the two tools do not fight here.

    Note on the lint command: give SwiftLint the source directories `Sources Tests Examples IntegrationTests`, not the repository root. `IntegrationTests/.build` holds the FoundationModelsRanker checkout, so the walk still reads dependency files; the violations that stay all come from paths that hold `/.build/`, and none of them is a file of this package.

    Verification, all from the repository root:
    - `swift build` — exit 0, 0 lines with the word warning.
    - `swift test` — 120 tests in 12 suites passed, 0 failed, 0 skipped.
    - `swiftlint lint --quiet Sources Tests Examples IntegrationTests` with the `/.build/` paths removed — 0 violations, of which 0 are `trailing_comma`.
    - `swiftformat Sources Tests Examples --lint` — 0 of 48 files need a change. (SwiftFormat 0.62.1 rejects `--lint Sources ...`, because it reads the next word as a value for the option. Put the paths first.)
  timestamp: 2026-09-10T12:13:54.073234+00:00
- actor: claude-code
  id: 01m25ktbv7sedxfkxrqxz1stg8
  text: |-
    ### implement — changed
    - evidence: 4 files — .swiftlint.yml (new), Examples/LibrarianCore/LibrarianCore.swift, Sources/FoundationModelsMetadataRegistry/Catalog/Diagnostics.swift, Sources/FoundationModelsMetadataRegistry/MetadataSearcher+Search.swift. `swift build` exit 0 with 0 warnings; `swift test` 120 tests in 12 suites passed, 0 failed, 0 skipped; `swiftlint lint --quiet Sources Tests Examples IntegrationTests` 0 violations in this package's own files (0 `trailing_comma`); `swiftformat Sources Tests Examples --lint` 0 of 48 files need a change.
    - next: `/review`
  timestamp: 2026-09-10T12:13:57.991837+00:00
position_column: doing
position_ordinal: '80'
title: 'MetadataSearcher: move to SelectionTier.init(catalog:config:onDiagnostic:) and drop candidateLimit from the tests'
---
## What

The FoundationModelsRanker package changed. `SelectionTier` now sends one prompt that picks. It runs no retrieval before the prompt and no retrieval after the answer. Three uses in this package must change before the ranker dependency moves to that revision.

The ranker commits, on its branch `main`:

- `aac493a` — one prompt that picks. No retrieval steps.
- `dbda1ae` — new words for the default preamble.

## The three uses

1. `Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift` line 332 calls `SelectionTier(catalog:config:onDiagnostic:retrievalRanking:)`. That initializer is deprecated and it ignores the closure. Move the call to `SelectionTier(catalog:config:onDiagnostic:)`. Delete the `rankEntireCatalog` ranking that fills the closure, and the weights and the embedder that only that ranking uses. Correct the doc comments at lines 92, 287, 294, 310, 312, 315, 630 and 633, which tell about the closure and about `candidateLimit`.
2. `Tests/FoundationModelsMetadataRegistryTests/OverBudgetTests.swift` gives `candidateLimit:` to `SelectionConfig` at lines 60, 89 and 106. That parameter does not exist now. `HotReloadTests.swift` does the same. Remove the parameter. Write the over-budget tests again for the new design: the tier divides the catalog into runs, every id gets to one prompt, and no `.retrievalCut` is sent.
3. `Sources/FoundationModelsMetadataRegistry/Catalog/Diagnostics.swift` lines 21, 22, 49 and 76 map `RankDiagnostic.retrievalCut`. The ranker keeps that case, but it never sends it. Keep the mapping, or remove it with this package's own `.retrievalCut` case.

## Also

The ranker changed the words of `String.selectionDefault`. A measurement on the system model and on `mlx-community/Qwen3-4B-4bit` gave 30 of 30 answers with the new words, against 27 of 30 and 0 of 30 with the old words. If this package gives its own preamble only to correct the old default, it can use the default now.

## Where this card came from

The ranker board holds the same record as card `^6kd63xc`. This card is the copy that this package's own board can work.

## Acceptance Criteria

- [x] `MetadataSearcher` builds the tier with `SelectionTier(catalog:config:onDiagnostic:)`.
- [x] No test gives `candidateLimit:` to `SelectionConfig`.
- [x] `swift build` and `swift test` pass against the ranker `main`, with no deprecation warning.

## Review Findings (2026-09-10 02:26)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 52 file(s) reviewed, 3 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `.swift-version` — no validator matches this file

- [x] `Sources/FoundationModelsMetadataRegistry/MetadataSearcher+Search.swift:246` `code-hygiene/idioms-swift` — isEmpty: Prefer isEmpty over comparing count against zero.
- [x] `Tests/FoundationModelsMetadataRegistryTests/EmbeddingCatchUpTests.swift:29` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
- [x] `Tests/FoundationModelsMetadataRegistryTests/EmbeddingCatchUpTests.swift:125` `code-hygiene/idioms-swift` — preferCountWhere: Prefer count(where:) over filter(_:).count.
