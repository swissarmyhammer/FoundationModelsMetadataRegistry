---
comments:
- actor: claude-code
  id: 01kwpt098e4rcd9ek2tmqv1rvt
  text: 'Picked up by /finish scoped-batch loop (task 11 of batch; picking this over ^ew12k0b despite similar readiness since it has the lower ordinal AND establishes the opt-in env-var gating convention that ^ew12k0b''s description explicitly needs to match). Plan: /implement → /test → /commit checkpoint → /review HEAD~1..HEAD.'
  timestamp: 2026-07-04T14:54:57.806431+00:00
- actor: claude-code
  id: 01kwpyx1s09vpnk2z6wyh0jhz3
  text: 'Implementation was interrupted mid-run by a weekly usage-limit reset, but recovered cleanly: work in the tree is complete. Added Tests/FoundationModelsMetadataRegistryTests/Integration/RouterIntegrationTests.swift (4 scenarios: fork-per-call prefix reuse, xgrammar id-enum enforcement, embed+RRF quality smoke, reload-under-churn) gated behind env var METADATA_REGISTRY_INTEGRATION_TESTS (record this name — ^ew12k0b will need to reference the same gate). Wired Package.swift''s test target with Router/MLX/HuggingFace/Tokenizers products needed only by the gated suite. Verified ungated: swift build exit 0, swift test 126/126 passed across 12 suites (up from 122) — confirms the suite is properly skipped by default per the critical acceptance criterion. Did not attempt the gated (real-model) path in this recovery pass. Proceeding to /test → /commit → /review.'
  timestamp: 2026-07-04T16:20:34.720546+00:00
- actor: claude-code
  id: 01kwpz2q6p16qrzx9vaaymrd9p
  text: 'Iteration 1: implement landed green in doing (126 tests passed / 0 failed across 12 suites, gated suite confirmed skipped-by-default). Checkpoint committed at a81a4ca. Env var: METADATA_REGISTRY_INTEGRATION_TESTS (needed by follow-on ^ew12k0b). Proceeding to /review HEAD~1..HEAD.'
  timestamp: 2026-07-04T16:23:40.502167+00:00
- actor: claude-code
  id: 01kwq0as2ks15c4b91ee6bm7pj
  text: |-
    Pulled back from review to doing to address the "## Review Findings (2026-07-04 11:29)" checklist (10 items, all doc-comment first-line/period issues in RouterIntegrationTests.swift).

    Per the orchestrator's explicit request, did a COMPREHENSIVE full-file pass rather than only touching the 10 cited lines (line numbers had drifted from the current file content anyway). Method: audited every single `///` doc comment block top-to-bottom against the house reference pattern in Sources/FoundationModelsMetadataRegistry/Catalog/Match.swift — a doc comment's first paragraph (before any blank `///` line) must be exactly ONE sentence (may still wrap across several physical lines, ending in exactly one period); a paragraph with 2+ sentence-ending periods crammed together without a blank-line separator is the actual violation, not merely "line 1 doesn't independently end in a period" (Match.swift's own `block`/`score` property docs prove multi-line-single-sentence wrapping is correct house style).

    Found and fixed 5 genuine violations (each had 2 sentences run together in paragraph 1 with no blank-line separator):
    1. `metadataRegistryIntegrationEnvVar` doc — split into a one-sentence summary + blank + elaboration (3 sentences were crammed together).
    2. `tinyProfile` doc — same split (2 sentences crammed).
    3. `LiveRouterFixture` struct doc — same split (2 sentences crammed).
    4. `LiveRouterFixture.tearDown()` doc — same split (2 sentences crammed, previously zero blank lines at all in that block).
    5. `embedAndRRFFindsTheRightItemForAParaphrasedQuery()` test doc — same split (2 sentences crammed, previously zero blank lines anywhere in the block).

    All other `///` blocks in the file (env-enabled var, TinyModels enum, `profile` property, `resolve()` method, `makeTempDir()`, `ToolItem` struct, `toolCatalogIds`, the `@Suite` type doc, and all four `@Test` method docs) were already single-sentence-paragraph-1 + blank-line + elaboration and needed no change — confirmed by careful period-counting against each block's text.

    No test logic, assertions, or the `.enabled(if:)` gating mechanism were touched — doc comments only.

    Verified: `swift build` exit 0. `swift test` (ungated, `env -u METADATA_REGISTRY_INTEGRATION_TESTS swift test`): 126 tests passed / 0 failed across 12 suites, and the 4 gated scenarios in "Gated Router-backed integration suite (M7)" show as skipped (confirmed via grep for "skipped").

    Spawned a double-check adversarial review agent to verify the diff is doc-comment-only and that every `///` block in the file now satisfies the one-sentence-paragraph-1 rule; awaiting its verdict before leaving this in doing for `/review`.
  timestamp: 2026-07-04T16:45:33.139042+00:00
- actor: claude-code
  id: 01kwq0hkqbh7dhryg5nbg9xx8m
  text: |-
    Comprehensive doc-comment pass complete. Did a full top-to-bottom audit of every `///` block in Tests/FoundationModelsMetadataRegistryTests/Integration/RouterIntegrationTests.swift (not just the 10 cited lines, whose line numbers had drifted from current file content) against the house style demonstrated in Sources/FoundationModelsMetadataRegistry/Catalog/Match.swift: paragraph 1 of every doc comment must be exactly one sentence (may wrap physical lines) ending in one period, with any elaboration split off after a blank `///` line.

    Fixed 5 genuine violations where two-or-more sentences were crammed into paragraph 1 without a blank-line separator: `metadataRegistryIntegrationEnvVar`, `tinyProfile`, `LiveRouterFixture` (struct doc), `LiveRouterFixture.tearDown()`, and `embedAndRRFFindsTheRightItemForAParaphrasedQuery()`. All other blocks in the file were already compliant and left untouched.

    Doc-comment-only diff — no test logic, assertions, or the `.enabled(if:)` gating mechanism changed. Verified: `swift build` exit 0; `env -u METADATA_REGISTRY_INTEGRATION_TESTS swift test` → 126 tests passed / 0 failed across 12 suites, all 4 gated integration scenarios (plus their parent suite) reported as skipped. Adversarial double-check agent returned PASS with no findings (confirmed diff scope, re-verified all 16 doc blocks satisfy the one-sentence-paragraph-1 rule, re-ran build/test).

    All 10 checklist items under "Review Findings (2026-07-04 11:29)" flipped to [x]. Leaving in doing for /review per the implement skill's rules (implement never moves a task to review itself).
  timestamp: 2026-07-04T16:49:17.035786+00:00
depends_on:
- 01KWMEEA0FQB66C11H0V13TGR4
position_column: done
position_ordinal: 8a80
title: Gated Router-backed integration suite
---
## What
Add the opt-in integration suite per plan.md §15 + M7, following the Router test pattern (`.serialized`, gated behind an env var, tiny real `mlx-community` models — copy the gating convention from `../FoundationModelsRouter/Tests/` and `../FoundationModelsMultitool/Tests/`):
- `Tests/FoundationModelsMetadataRegistryTests/Integration/RouterIntegrationTests.swift`
- Real fork-per-call prefix reuse through `RoutedAgentSession`
- xgrammar id-enum enforcement: the model cannot emit an id outside the candidate enum
- Embed + RRF quality smoke over a fixture catalog via `RoutedEmbedderAdapter` (paraphrase query finds the right item)
- Reload under churn: MCP-style add/remove bursts while searching

## Acceptance Criteria
- [ ] Suite is skipped by default (`swift test` stays green with no GPU/models) and runs with the opt-in env var set
- [ ] All four scenarios pass locally against tiny real models
- [ ] Grammar-enforcement test asserts every returned id is a member of the candidate set across repeated runs

## Tests
- [ ] The suite itself is the test artifact — `.serialized` Swift Testing suite, env-var gated
- [ ] Run `swift test` (ungated) — passes with the suite skipped; run with the env var locally — passes end-to-end

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-07-04 11:29)

- [x] `Tests/FoundationModelsMetadataRegistryTests/Integration/RouterIntegrationTests.swift:15` — The first line of the doc comment is not a complete sentence ending with a period. The rule requires 'The first line is a single-sentence summary ending in a period; any elaboration follows after a blank /// line.'. End the first line with a complete sentence, e.g., `/// The opt-in environment variable that enables this gated, real-model suite.` followed by a blank `///` line before elaboration.
- [x] `Tests/FoundationModelsMetadataRegistryTests/Integration/RouterIntegrationTests.swift:32` — The first line of the doc comment is incomplete and does not end with a period. Restructure to complete the first line as a single sentence ending with a period.
- [x] `Tests/FoundationModelsMetadataRegistryTests/Integration/RouterIntegrationTests.swift:40` — The first line of the doc comment is incomplete and does not end with a period. End the first line as a complete sentence before continuing.
- [x] `Tests/FoundationModelsMetadataRegistryTests/Integration/RouterIntegrationTests.swift:48` — The first line of the doc comment is incomplete and does not end with a period. Complete the first line as a single sentence ending with a period.
- [x] `Tests/FoundationModelsMetadataRegistryTests/Integration/RouterIntegrationTests.swift:87` — The first line of the doc comment is incomplete and does not end with a period. Restructure to have a complete sentence on the first line, then a blank `///` line, then elaboration.
- [x] `Tests/FoundationModelsMetadataRegistryTests/Integration/RouterIntegrationTests.swift:106` — The first line of the doc comment is incomplete and does not end with a period. Complete the first line as a single sentence ending with a period.
- [x] `Tests/FoundationModelsMetadataRegistryTests/Integration/RouterIntegrationTests.swift:125` — The first line of the doc comment is incomplete and does not end with a period. Complete the first line as a single sentence ending with a period.
- [x] `Tests/FoundationModelsMetadataRegistryTests/Integration/RouterIntegrationTests.swift:194` — The first line of the doc comment is incomplete and does not end with a period. Complete the first line as a single sentence ending with a period.
- [x] `Tests/FoundationModelsMetadataRegistryTests/Integration/RouterIntegrationTests.swift:241` — The first line of the doc comment is incomplete and does not end with a period. Complete the first line as a single sentence ending with a period.
- [x] `Tests/FoundationModelsMetadataRegistryTests/Integration/RouterIntegrationTests.swift:281` — The first line of the doc comment is incomplete and does not end with a period. Complete the first line as a single sentence ending with a period.
