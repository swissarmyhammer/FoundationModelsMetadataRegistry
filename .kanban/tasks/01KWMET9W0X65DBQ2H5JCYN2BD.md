---
depends_on:
- 01KWMED1XXMRMQ4JFB92YPCTGD
position_column: todo
position_ordinal: 8d80
title: 'Move AgentSession upstream: Multitool imports it from this package (cross-repo)'
---
## What
**Cross-repo task — all changes land in `../FoundationModelsMultitool`; commits go to that repo, not this board's workspace.** First half of plan.md M5, independently shippable:
- Add `.package(path: "../FoundationModelsMetadataRegistry")` to `../FoundationModelsMultitool/Package.swift`
- Delete Multitool's local `AgentSession.swift` (protocol + default `respond(to:generating:)` + `RoutedAgentSession`) and replace with `@_exported import` (or plain re-export) of this package's identical seam
- No behavior change — the seam here was lifted verbatim, so Multitool's existing tests are the regression harness

## Acceptance Criteria
- [ ] No local `AgentSession`/`RoutedAgentSession` definition remains in Multitool sources
- [ ] `swift build` and `swift test` pass unchanged in `../FoundationModelsMultitool`
- [ ] Multitool's `Librarian` still compiles against the imported seam without edits beyond the import

## Tests
- [ ] Existing `../FoundationModelsMultitool/Tests/` suite — run `swift test` there, exit 0, no test edits required

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.