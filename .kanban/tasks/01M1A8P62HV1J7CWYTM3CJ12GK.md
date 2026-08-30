---
assignees:
- claude-code
depends_on:
- 01M1A8N1QQYFF6376DMXMT6FMC
- 01M1A8NKPNMZJCCMJFHDDAXWAZ
- 01M1A96ZZCKAB5SE03AF10JVV9
position_column: todo
position_ordinal: '8380'
title: Reconcile the docs and guard tests that still say the integration suite is gone
---
## What

The CI input landed in `^f10jvv9`. This card closes out the documents and guard tests that still assert the suite does not exist, and verifies the integration job actually runs the real tests.

Files to change:
- `Tests/FoundationModelsMetadataRegistryTests/PlanDocumentTests.swift` — **this test now enforces a falsehood.** `retiredNameStems` includes `"IntegrationTests"` (line 48), and the doc comment at line 35 says it "covers the deleted nested package". The package is no longer deleted. As written, the test forces every `plan.md` section naming `IntegrationTests` to carry a `decision #14` history marker forever — marking a live directory as history. Remove `"IntegrationTests"` from `retiredNameStems` and rewrite the doc comment. Leave the other stems (`Router`, `Routed`, `Grammar`) alone; those types really are gone.
- `plan.md` — decision states the repository has no integration suite and that `ci.yml` passes no inputs. Both are now false. It is **not only decision**: the claim also appears at lines 16, 24, 29, 369, 464-465, 615-622 and 639-644. Add a dated decision recording the reinstatement and its narrow scope — two tests, real Apple Intelligence, no new dependencies — and reconcile every one of those places in the file's existing marker idiom. Do not rewrite history; mark it.

### Verify the job really ran

A green run is not enough. `^f10jvv9` only proved the job stops being `skipped`. Confirm the integration job **executed the real tests**, the way the Ranker session verified their own run 33318330212:

```
gh run view <id> --repo swissarmyhammer/FoundationModelsMetadataRegistry \
  --json jobs --jq '.jobs[] | select(.name|test("Integration")) | .steps[] | "\(.conclusion)\t\(.name)"'
```

`Run the selected integration tests` must report `success`, not `skipped`.

Record the observed per-test durations in a comment. Ranker's four ran at 3.8-6.8s each; a wildly different number here is worth understanding before it becomes normal.

## Acceptance Criteria

- [ ] `PlanDocumentTests.retiredNameStems` no longer contains `"IntegrationTests"`, and its doc comment matches.
- [ ] No test or document claims this repository has no integration suite. Grep `Package.swift`, `plan.md`, `README.md`, `.github/`, and the whole test suite.
- [ ] `plan.md` carries a dated decision, and every one of lines 16, 24, 29, 369, 464-465, 615-622, 639-644 is reconciled in the file's marker idiom.
- [ ] `PlanDocumentTests` passes with the reduced stem list.
- [ ] CI's `Integration` job reports `success` and its `Run the selected integration tests` step is not `skipped`.

## Tests

- [ ] Run `swift test` at the root. All tests pass, including the amended `PlanDocumentTests` and `CIWorkflowTests`.
- [ ] Run `swift test --package-path IntegrationTests`. Both real-model tests pass.
- [ ] After pushing, run the `gh run view` command above and paste its output into a comment on this card.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.