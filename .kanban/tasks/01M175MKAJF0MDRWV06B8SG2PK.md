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
position_column: todo
position_ordinal: '8980'
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

## Acceptance Criteria

- [ ] `ExamplesSmokeTests` holds no assertion that can fail because the machine
      is slow.
- [ ] The needle-ranking claim (`first.id == bigCatalogNeedleId`) is kept.
- [ ] The threshold is not simply raised.
- [ ] 10 consecutive `swift test` runs pass.