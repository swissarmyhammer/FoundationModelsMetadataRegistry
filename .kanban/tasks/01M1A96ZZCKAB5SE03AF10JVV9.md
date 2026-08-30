---
assignees:
- claude-code
depends_on:
- 01M1A8MDQ9NTZX4A0N8JZBA4XN
position_column: todo
position_ordinal: '8480'
title: Wire integration-package-path into CI early, so the nested package builds on every run
---
## What

Point CI at the nested package **as soon as it exists**, before the real-model tests are written. Split out of the original CI card because the ordering matters.

The deleted manifest states the reason itself (`git show cafac33^:IntegrationTests/Package.swift:47-52`): `integration-package-path` makes the shared workflow's **unit** job build the nested package on every run, before the expensive integration step. If this lands only after both test cards, those tests get written with no CI build check behind them.

Files to change:
- `.github/workflows/ci.yml` — add a `with:` block passing `integration-package-path: IntegrationTests`. The file currently has a bare `uses:` with no inputs. Rewrite the header comment, which says this repository has no integration suite. Do **not** pass `integration-gate-env` — that input is LEGACY. Do **not** pass `integration-metallib-glob` — that existed for MLX's Metal library, and there is no MLX in this graph.
- `Tests/FoundationModelsMetadataRegistryTests/CIWorkflowTests.swift` — **the trap.** `passesNoIntegrationInput()` asserts `ci.yml` contains no line beginning `integration-`. It will fail the moment the input lands, and it is right to: it was written when the suite was deleted. Replace it with a test asserting `integration-package-path: IntegrationTests` IS present. Keep `callsTheSharedWorkflow()` and `declaresNoRepoLocalJobs()`. Rewrite the suite doc comment.
- `Package.swift` — lines 154-157 say "This repository has no integration suite at all, so a bare `swift test` at the root runs every test it has". That becomes false. Rewrite it. Nothing enforces this comment (`PackageManifestTests.spellsNoRemovedRouterName` bans only the three Router names, `PackageManifestTests.swift:68-72`), so it will rot silently if missed.

At this point the integration job will run and find only the placeholder test from `^jzba4xn`. That is the intended intermediate state.

## Acceptance Criteria

- [ ] `ci.yml` passes `integration-package-path: IntegrationTests` and no other `integration-*` input.
- [ ] `CIWorkflowTests` asserts the input is present; no test anywhere asserts its absence.
- [ ] `Package.swift:154-157` no longer claims this repository has no integration suite.
- [ ] On the next push, the `Integration` job reports a conclusion other than `skipped`.

## Tests

- [ ] Run `swift test` at the root. All tests pass, including the rewritten `CIWorkflowTests`.
- [ ] Run `swift build --package-path IntegrationTests`. It succeeds.
- [ ] After pushing, read the run for the new HEAD: `gh run view <id> --json jobs --jq '.jobs[] | "\(.name): \(.conclusion)"'`. Assert the `Integration` job is not `skipped`.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.