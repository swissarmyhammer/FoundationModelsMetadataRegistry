---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m1ac3jejjqzhn1f2mmk2y5qk
  text: |-
    Research done. What I found:

    - `.github/workflows/ci.yml` is a bare `uses:` with no `with:` block. Its header comment (lines 3-18) states four times that this repository has no integration suite and passes no `integration-*` input. All of it must be rewritten.
    - The shared workflow `swissarmyhammer/workflows/.github/workflows/swift-ci.yaml` is available locally at `/Users/wballard/github/swissarmyhammer/workflows`. Its `integration-package-path` input description confirms the card: the input makes the UNIT job build the nested package on every run (`swift build --package-path <path> --build-tests`, workflow line 252, guarded by `if: inputs.integration-package-path != ''`), and the INTEGRATION job build+run it. It "Cannot be combined with integration-gate-env". `integration-metallib-glob` only colocates an mlx-swift `default.metallib`, so it does not apply here.
    - The deleted version of this file (`git show cafac33^:.github/workflows/ci.yml`) passed exactly `integration-package-path: IntegrationTests` plus the MLX metallib glob. The deleted `CIWorkflowTests` (`git show cafac33^:.../CIWorkflowTests.swift`) had a test `namesTheNestedIntegrationPackage()` that pins the exact trimmed line. That is the prevailing shape to restore, minus the metallib test.
    - Complete grep for the stale claim across the repository (files that mention "integration"):
      - MINE: `.github/workflows/ci.yml`, `Package.swift` (lines 154-157), `Tests/.../CIWorkflowTests.swift`.
      - ALSO MINE, and not listed on the card: `IntegrationTests/Package.swift` lines 55-57 say the CI input "is wired in a change of its own, and until it lands the command above is the only thing that compiles this package". This card lands it, so that sentence goes false on this change and I fix it here.
      - BELONGS TO `^3cj12gk`, left alone: `Tests/.../PlanDocumentTests.swift` (`retiredNameStems` contains `"IntegrationTests"`) and `plan.md` lines 16, 24, 29, 369, 464-465, 615-622, 639-644 — exactly the lines that card names.
      - `README.md` makes no claim about the test layout at all.
    - Baseline before any edit: `swift test --filter CIWorkflowTests` passes 3 tests in 1 suite; `swift build --package-path IntegrationTests` succeeds.
  timestamp: 2026-08-30T22:19:41.394417+00:00
- actor: claude-code
  id: 01m1acm6bm7w18cpn23edtzv3t
  text: |-
    Implementation landed, by the TDD cycle.

    RED first: rewrote `CIWorkflowTests` before touching `ci.yml`, and watched it fail — `Expectation failed: namesPackage`, "ci.yml must pass \"integration-package-path: IntegrationTests\"". It failed for the missing input, not for a typo.

    GREEN: added the `with:` block. 4 tests in the suite pass.

    I also proved the second new test can fail, rather than trusting a test that passed the first time it ran. I temporarily added `Integration-Metallib-Glob: "*Cmlx*/default.metallib"` to the `with:` block; `passesNoOtherIntegrationInput()` failed, then passed again once the probe line was removed. That also proves the case-insensitive read still works: a capitalized key is caught, which is the property the deleted test's comment was protecting.

    Two decisions worth recording:

    1. **Two tests replace the one trap test, not one.** The card says to replace `passesNoIntegrationInput()` with a presence test, and acceptance criterion 1 also demands "no other `integration-*` input". A presence test alone cannot see a second input. So the trap test became `namesTheNestedIntegrationPackage()` (pins the exact trimmed line, matching the shape the deleted suite used at `cafac33^`) plus `passesNoOtherIntegrationInput()` (keeps the deleted test's case-insensitive read, now excluding the package path). Each test asserts one behavior. `callsTheSharedWorkflow()` and `declaresNoRepoLocalJobs()` are untouched, as instructed. Root suite goes 114 -> 115 tests, still 12 suites.

    2. **`IntegrationTests/Package.swift` was edited although the card does not list it.** Its doc comment ended "That input is wired in a change of its own, and until it lands the command above is the only thing that compiles this package." This card lands that input, so the sentence went false on this change. It now points at `CIWorkflowTests` as the thing that holds the coupling. The card's own Tests item 3 asks for exactly this sweep.

    Left alone, and reported instead: `Tests/.../PlanDocumentTests.swift` (`retiredNameStems` still contains `"IntegrationTests"`) and `plan.md` lines 16, 24, 29, 369, 464-465, 615-622, 639-644. Both belong to `^3cj12gk`, which names those files and those exact line numbers. `PlanDocumentTests` still passes today, because no `plan.md` section names `IntegrationTests` outside a `decision #14` marker.

    Verification, all local:
    - `swift test` at the root — 115 tests in 12 suites passed. Zero failures.
    - `swift build --build-tests` at the root — no warning, no error.
    - `swift build --package-path IntegrationTests --build-tests` — Build complete.
    - `grep -rn "integration-" Tests/ IntegrationTests/Tests/` — the only hits are in the rewritten `CIWorkflowTests`. No test anywhere asserts the input's absence.

    The fourth acceptance criterion (the `Integration` job reporting a conclusion other than `skipped`) stays unchecked. The card defers it to the orchestrator after the push, and this step neither commits nor pushes.

    ### implement — changed
    - evidence: 4 files — `.github/workflows/ci.yml`, `Tests/FoundationModelsMetadataRegistryTests/CIWorkflowTests.swift`, `Package.swift`, `IntegrationTests/Package.swift`. `swift test` 115 tests / 12 suites, 0 failures; `swift build --build-tests` clean; `swift build --package-path IntegrationTests --build-tests` clean.
    - next: `/review`
  timestamp: 2026-08-30T22:28:46.068896+00:00
depends_on:
- 01M1A8MDQ9NTZX4A0N8JZBA4XN
position_column: doing
position_ordinal: '80'
title: Wire integration-package-path into CI early, so the nested package builds on every run
---
## What

Point CI at the nested package **as soon as it exists**, before the real-model tests are written. Split out of the original CI card because the ordering matters.

The deleted manifest states the reason itself (`git show cafac33^:IntegrationTests/Package.swift:47-52`): `integration-package-path` makes the shared workflow's **unit** job build the nested package on every run, before the expensive integration step. If this lands only after both test cards, those tests get written with no CI build check behind them.

Files to change:
- `.github/workflows/ci.yml` — add a `with:` block passing `integration-package-path: IntegrationTests`. The file currently has a bare `uses:` with no inputs. Rewrite the header comment, which says this repository has no integration suite. Do **not** pass `integration-gate-env` — that input is LEGACY. Do **not** pass `integration-metallib-glob` — that existed for MLX's Metal library, and there is no MLX in this graph.
- `Tests/FoundationModelsMetadataRegistryTests/CIWorkflowTests.swift` — **the trap.** `passesNoIntegrationInput()` asserts `ci.yml` contains no line beginning `integration-`. It will fail the moment the input lands, and it is right to: it was written when the suite was deleted. Replace it with a test asserting `integration-package-path: IntegrationTests` IS present. Keep `callsTheSharedWorkflow()` and `declaresNoRepoLocalJobs()`. Rewrite the suite doc comment.
- `Package.swift` — lines 154-157 say "This repository has no integration suite at all, so a bare `swift test` at the root runs every test it has". That becomes false. Rewrite it. Nothing enforces this comment (`PackageManifestTests.spellsNoRemovedRouterName` bans only the three Router names, `PackageManifestTests.swift:68-72`), so it will rot silently if missed.

At this point the integration job will run and find only the two support tests from `^jzba4xn`. That is the intended intermediate state.

### Pushing is out of scope for this card

`/finish` commits locally and never pushes. Do not push, and do not treat the unverified CI run as a blocker. The orchestrator verifies the live run after the batch, when the user pushes. Everything else on this card is verifiable locally.

## Acceptance Criteria

- [x] `.github/workflows/ci.yml` passes `integration-package-path: IntegrationTests` and no other `integration-*` input.
- [x] `CIWorkflowTests` asserts the input is present, and no test anywhere asserts its absence.
- [x] `Package.swift:154-157` no longer claims this repository has no integration suite.
- [ ] Deferred to the orchestrator, post-push: the `Integration` job reports a conclusion other than `skipped`.

## Tests

- [x] Run `swift test` at the root. All tests pass, including the rewritten `CIWorkflowTests`.
- [x] Run `swift build --package-path IntegrationTests`. It succeeds.
- [x] Grep the whole test suite for any other assertion that `ci.yml` carries no integration input, and for any remaining claim that this repository has no integration suite. Fix what you find, or report it if it belongs to `^3cj12gk`.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.