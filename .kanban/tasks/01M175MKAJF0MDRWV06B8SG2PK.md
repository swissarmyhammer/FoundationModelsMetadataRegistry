---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m175sbgst4h9424rx9tyb2kc
  text: |-
    ### orchestrator measurement — not a blocker, but real

    Measured on a quiet machine, after the /finish batch's subagents had stopped:

    - `swift test --filter 'bigCatalogRetrievalFindsTheNeedleAndReportsTiming'` — 5 runs, all passed, 0.236s each. The threshold is 5.0s, so the margin is about 20x.
    - `swift test` (full suite) — 3 runs, all passed, 109 tests in 9 suites, 0.29s to 0.38s each.

    The failures the implementer saw (2 of 4 runs at HEAD, about 6s) happened while four or more subagents were compiling Swift at the same time. The assertion is not wrong about the code; it is sensitive to concurrent CPU load, because it asserts on wall-clock time inside a suite that Swift Testing runs in parallel.

    So this does NOT block the Router-removal batch. Keep the task: a wall-clock assertion in a parallel test suite is genuinely fragile, and it will fail again on a loaded CI runner. Do not fix it by raising the threshold — that hides the fragility instead of removing it.
  timestamp: 2026-08-29T16:31:31.865241+00:00
- actor: claude-code
  id: 01m17basgx4d1mfnr45argg8sf
  text: |-
    ### Research and reproduction

    Confirmed the defect is the only wall-clock assertion in the whole `Tests/` tree. A grep for `elapsed|Date()|ContinuousClock|DispatchTime|timeIntervalSince` across `Tests/` matched two lines only, both of them the pair at `ExamplesSmokeTests.swift:186-187`. So the cause exists at one site, and one edit removes it.

    Read the source of truth: `Examples/BigCatalogCore/BigCatalogCore.swift`. `runBigCatalogRetrieval` opens its clock with `let start = Date()`, builds the searcher, searches, then closes it with `Date().timeIntervalSince(start)`. Both clock reads sit strictly inside the call. That fact is what the fix uses.

    ### RED — the failure reproduced

    Baseline on a quiet machine, 3 runs: all passed, 109 tests in 10 suites, 0.28s to 0.30s.

    Then the same suite under load. 384 busy-loop processes on 32 cores was NOT enough -- 4 runs, all passed, the whole suite in 2.5s to 3.2s. At 1024 busy-loop processes the assertion failed on all 3 runs:

    ```
    ✘ Test run with 109 tests in 10 suites failed after 19.255 seconds with 1 issue.
    ✘ Test "BigCatalog's retrieval-timing path finds the deterministic needle across a ~10^3-entry synthetic catalog"
      recorded an issue at ExamplesSmokeTests.swift:187:9: Expectation failed: result.elapsed < 5.0
    ```

    Only that one assertion failed. Every other test in the suite stayed green under the same load, which shows the defect is the wall-clock claim and nothing else.

    ### Cost of that reproduction — a warning for the next agent

    The first version of the load script spawned `/bin/sh -c 'while :; do :; done'` directly. Its cleanup used `pkill -f sah_spinner.sh`, which never matched those processes, because that command line carries no script name. 997 spinners leaked and the machine reached a load average of 809. The orchestrator killed them. Do not repeat this. If load is ever needed again, give each process a name the cleanup can match, and check `pgrep` after the run.

    ### GREEN — the fix

    The test now measures the call from the outside and bounds the reported timing against that window, instead of against a constant:

    ```swift
    let callStart = Date()
    let result = try await BigCatalogCore.runBigCatalogRetrieval(query: BigCatalogCore.bigCatalogNeedleQuery)
    let callWindow = Date().timeIntervalSince(callStart)
    ...
    #expect(result.elapsed.isFinite)
    #expect(result.elapsed >= 0)
    #expect(result.elapsed <= callWindow)
    ```

    Why this is not a loosened assertion. The old `< 5.0` compared the timing with a number that had nothing to do with the run, so it measured the machine. The new bound compares the timing with the window the call really ran in, so it measures whether the value describes THIS call. `runBigCatalogRetrieval` starts its clock after the window opens and stops it before the window closes, so `elapsed <= callWindow` holds by construction. A busy machine makes both sides larger together, and load cannot fail it. The three claims are independent: a negative value passes the other two, and only `isFinite` names "a real number" directly rather than leaving it to NaN comparison semantics.

    Two validator rules bound this edit, and both are satisfied:

    - `test-integrity/no-test-cheating`, check 3 "Flaky test fixes" and check 4 "A weakened assertion". The threshold is not raised and no claim is dropped. The timing claim is replaced by a stronger one about what the value measures.
    - `code-hygiene/dead-code-swift`, `assignOnlyProperty`. `RetrievalTimingResult.elapsed` keeps a reader in the test, so it does not become an assign-only property.

    Also removed the unnamed `5.0` literal, which `magic-numbers-swift` reports by position. Swift Testing is neither `QuickSpec` nor `XCTestCase`, so the swiftlint `test_parent_classes` carve-out never covered it.

    ### Verification

    10 consecutive `swift test` runs after the fix, all passed, 109 tests in 10 suites, 0.27s to 0.47s. `swift build --build-tests` is clean with no new warnings.

    Acceptance criteria: no assertion in `ExamplesSmokeTests` can now fail because the machine is slow; `first.id == bigCatalogNeedleId` is kept, as are `catalogCount == 1_000` and the needle-ranking claim; the threshold is removed, not raised; 10 consecutive runs pass.

    `Package.swift` and `TestSupport/SelectionFixtures.swift` are untouched, and `stash@{0}` is untouched.
  timestamp: 2026-08-29T18:08:26.141107+00:00
- actor: claude-code
  id: 01m17bbfp2w9nkvwe3xtsmp7fg
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsMetadataRegistryTests/ExamplesSmokeTests.swift. `swift build --build-tests` clean. RED: 3 of 3 `swift test` runs failed at `ExamplesSmokeTests.swift:187: Expectation failed: result.elapsed < 5.0` under load. GREEN: 10 of 10 consecutive `swift test` runs passed, 109 tests in 10 suites, 0.27s to 0.47s.
    - next: /review
  timestamp: 2026-08-29T18:08:48.834493+00:00
- actor: claude-code
  id: 01m17bhn38gnv356mn2q6368hm
  text: |-
    ### review — clean

    - scope: `review sha HEAD~1..HEAD` (commit 4869039), diffs only
    - evidence: zero new findings. counts: findings 0, confirmed 0, refuted 0, attempted 7, failed 0. All four acceptance criteria are marked complete.
    - tests: `swift test` passed. 109 tests in 10 suites, 0.295 s, exit code 0.
    - judgement on `test-integrity/no-test-cheating`: the change is a correct fix. It is not a hidden decrease of the test strength. The old assertion `elapsed < 5.0` made a claim about the speed of the machine. The new assertions make a claim about the measurement. `runBigCatalogRetrieval` starts its clock as its first statement and stops it before it returns. The default `catalog` argument is calculated at the call site, thus it is in `callWindow` but not in `elapsed`. Therefore `elapsed <= callWindow` is true by construction, and a busy machine increases the two sides together. The three new claims fail if `elapsed` is a fixed placeholder, if it is not a number, or if the clock measures more than the call. The claims `catalogCount == 1_000` and `first.id == bigCatalogNeedleId` do not change, thus the test keeps its full function coverage. The threshold was not increased.
    - next: none. Task is in `done`.
  timestamp: 2026-08-29T18:12:10.984146+00:00
- actor: claude-code
  id: 01m17bjhkpej5z87kjz07c3ze8
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 1 file, Tests/FoundationModelsMetadataRegistryTests/ExamplesSmokeTests.swift. The wall-clock constant is replaced by a bound against an externally measured call window: elapsed.isFinite, elapsed >= 0, elapsed <= callWindow.
    - test: green — RED 3/3 runs failed at ExamplesSmokeTests.swift:187 under load while every other test stayed green, which isolated the defect. GREEN 10/10 consecutive swift test runs, 109 tests in 10 suites, 0.27s-0.47s.
    - commit: 4869039 fix(tests): bound BigCatalog retrieval timing against its call window
    - review: clean — 0 findings, 7 validators, task moved to done. The reviewer explicitly judged this against test-integrity/no-test-cheating and confirmed it is a genuine fix, not a loosening: runBigCatalogRetrieval starts its clock as its first statement and stops it before returning, so elapsed is a strict subinterval of callWindow, and the `catalog: [BigCatalogItem] = makeBigCatalog()` default argument is evaluated at the call site, putting the 1000-entry build inside callWindow but outside elapsed. Load inflates both sides together.

    ### WARNING for future agents on this repository
    The first load-generator script written for this task leaked 997 orphaned `/bin/sh -c 'while :; do :; done'` processes. Its cleanup used `pkill -f sah_spinner.sh`, which cannot match a `/bin/sh -c` command line that carries no script name. The machine reached a load average of 809 on 32 cores. The orchestrator killed them with `pkill -9 -f 'while :; do :; done'`.

    Do not generate artificial machine load to reproduce a timing flake. If you must, match the kill pattern to the ACTUAL command line, verify with `pgrep -f <pattern> | wc -l` after cleanup, and never leave the harness on disk.
  timestamp: 2026-08-29T18:12:40.182810+00:00
position_column: done
position_ordinal: '9880'
title: Replace the flaky wall-clock assertion in the BigCatalog retrieval-timing smoke test
---
## What

`Tests/FoundationModelsMetadataRegistryTests/ExamplesSmokeTests.swift`, in
`bigCatalogRetrievalFindsTheNeedleAndReportsTiming()`, asserts
`#expect(result.elapsed < 5.0)` over a ~10^3-entry catalog. That is a
wall-clock assertion in a unit test, so it fails when the machine is busy.

Measured on 2026-08-29 at commit `aa7aa78` (HEAD, with no working-tree
changes): 4 consecutive `swift test` runs of the 106-test suite gave 2 failures
and 2 passes, always the same assertion, with `result.elapsed` between about
5 and 7 seconds. The defect is present before, and independent of, task
`^mjp69rx`.

## Why not simply raise the number

Raising the threshold is the "flaky-test fix" the `test-integrity` validator
names as cheating: it hides the cause instead of removing it. The cause is that
the test measures throughput at all. Remove the timing claim, or move the
timing claim to a place where a slow machine cannot fail the unit suite.

## Options to weigh

- Delete the two timing expectations (`result.elapsed >= 0`,
  `result.elapsed < 5.0`) and keep the needle-ranking claim. The demo already
  prints the real timing for a human to read, and `RetrievalTimingResult`
  carrying a real (non-placeholder) elapsed value is already proved by
  `result.elapsed >= 0` being a real number.
- Or keep a timing claim but make it a claim about correctness, not speed:
  assert the elapsed value is finite and non-negative only.
- Or move the throughput claim to the nested `IntegrationTests/` package, where
  a slow run does not break the red-green loop.

Note that task `^9m7y43t` may delete the `IntegrationTests/` package, so weigh
the third option against that.

## What was done

The second option, made stronger. The test measures the call from the outside
and bounds the reported timing against that window, in place of a constant:

```swift
let callStart = Date()
let result = try await BigCatalogCore.runBigCatalogRetrieval(query: BigCatalogCore.bigCatalogNeedleQuery)
let callWindow = Date().timeIntervalSince(callStart)
...
#expect(result.elapsed.isFinite)
#expect(result.elapsed >= 0)
#expect(result.elapsed <= callWindow)
```

`runBigCatalogRetrieval` starts its clock after this window opens and stops it
before this window closes, so `elapsed <= callWindow` holds by construction. A
busy machine makes both sides larger together. The claim is therefore about
what the value measures, not about how fast the machine is.

## Acceptance Criteria

- [x] `ExamplesSmokeTests` holds no assertion that can fail because the machine
      is slow.
- [x] The needle-ranking claim (`first.id == bigCatalogNeedleId`) is kept.
- [x] The threshold is not simply raised.
- [x] 10 consecutive `swift test` runs pass.