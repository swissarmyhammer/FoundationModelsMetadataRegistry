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
depends_on:
- 01KWMEEA0FQB66C11H0V13TGR4
position_column: doing
position_ordinal: '80'
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