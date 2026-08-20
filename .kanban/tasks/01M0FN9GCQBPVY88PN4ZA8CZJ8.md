---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0fnbt80hqskegjywhk5wtqy
  text: |-
    ### status — blocked on external push
    - Checked workflows origin/main: still 5f7e9a5, no `integration-package-path` input yet.
    - Messaged the workflows-06 session for status and interface confirmation; subscribed for its idle notice.
    - Read Multitool's model card ^jjyqe1a. Confirmed conversion shape: one `uses:` call with the nested-package input, keep every-run build + metallib colocation + ordering via the shared workflow, rewrite CIWorkflowTests to pin the delegation (the `uses:` line and its inputs) instead of the repo-local `needs: unit` edge, update the ci.yml header comment.
    - Difference from Multitool: this package does not need `integration-no-parallel` — one `.serialized` suite, no turnstile. Decide finally when the input's semantics are visible.
    - next: when the push lands, follow /tdd — rewrite CIWorkflowTests first (red), then rewrite ci.yml (green), verify root swift test + integration build, commit, push, watch the CI run.
  timestamp: 2026-08-20T13:21:59.040146+00:00
- actor: claude-code
  id: 01m0fptrh0zp7wv0x81y6m9g0q
  text: |-
    ### commit — changed
    - evidence: 50c3a83 ci(tests): fold unit and integration into the shared swift-ci.yaml call; pushed to origin/main (4926a63..50c3a83)
    - CI evidence: run https://github.com/swissarmyhammer/FoundationModelsMetadataRegistry/actions/runs/32375511644 — completed/success. Unit job "ci / Build & test": 102 tests in 9 suites green. Integration job "ci / Integration (opt-in, real dependencies)": 4 tests in 1 suite green, real models on GPU.
    - ci.yml is now a single call to the shared swift-ci.yaml with integration-package-path: IntegrationTests and integration-metallib-glob. No repo-local jobs remain.
    - Ported MetalLibraryTestBootstrap.swift (from Multitool, itself from mlx-swift-lm) as the root-cause metallib fix — direct local measurement showed the shared workflow's colocation step (at that time, workflows commit 0580114) did not satisfy mlx-swift's loader for this package, since no in-process bootstrap existed here. workflows commit 20c0a0a has since fixed the shared step too; the bootstrap stays as defense-in-depth's foundation, not a substitute.
    - CIWorkflowTests rewritten (TDD) to pin the delegation shape instead of a repo-local needs: edge.
    - next: none — task complete.
  timestamp: 2026-08-20T13:47:37.376957+00:00
position_column: done
position_ordinal: '9180'
title: Fold the repo-local integration job into the shared swift-ci.yaml call
---
## Goal

Use the shared `swissarmyhammer/workflows/.github/workflows/swift-ci.yaml` for the unit job AND the integration job. Remove the repo-local integration job from `.github/workflows/ci.yml`.

## Blocked until

The workflows-06 session adds the `integration-package-path` input to the shared workflow. Wait for the message that it landed on workflows origin/main. Do not start before that.

## What the new shared input does

- The integration job builds and runs the nested package at the given path.
- The unit job builds the nested package on every run (the compile coupling).
- The metallib colocation step searches the package path.
- The `needs: test` edge stays inside the shared workflow.

## Steps

1. Read the updated shared workflow and its README on origin/main. Confirm the input name and the job names.
2. Replace the two-job `ci.yml` with one call to the shared workflow: `integration-package-path: IntegrationTests`.
3. Update `CIWorkflowTests`: the repo-local `needs: unit` edge goes away. Pin what the new shape gives — for example, pin that the call passes `integration-package-path`, or adopt the check Multitool's conversion (card ^jjyqe1a in the Multitool board) ships.
4. Update the comments in `ci.yml`, `IntegrationTests/Package.swift`, and `plan.md` that describe the repo-local job.
5. Verify: root `swift test` green, integration package builds, then watch the first CI run — the unit job, the every-run nested build, and the integration job must all run.

Multitool's conversion card ^jjyqe1a is the model to mirror.

#test-contract