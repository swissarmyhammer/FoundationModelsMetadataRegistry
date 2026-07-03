---
depends_on:
- 01KWMEEA0FQB66C11H0V13TGR4
position_column: todo
position_ordinal: '8980'
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