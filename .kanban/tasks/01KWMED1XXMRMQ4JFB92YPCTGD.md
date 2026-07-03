---
depends_on:
- 01KWMEB1EMNP2HMR8TJ3TRGW15
position_column: todo
position_ordinal: '8580'
title: Lift AgentSession seam + RoutedAgentSession from Multitool
---
## What
Lift the session seam as-is from `../FoundationModelsMultitool/Sources/.../AgentSession.swift` into `Sources/FoundationModelsMetadataRegistry/Session/AgentSession.swift` (plan.md §6; Multitool later imports it from here, task "Migrate Multitool Librarian"):
- `protocol AgentSession: Sendable` with `respond(to:) async throws -> String` and `fork() async throws -> Self`-style member (match Multitool's shape at `AgentSession.swift:24-44`)
- Default generic `respond<T: Generable>(to:generating:)` decoding via `try T(GeneratedContent(json: raw))` (Multitool `AgentSession.swift:86-89`)
- `RoutedAgentSession` production conformer wrapping `any RoutedSession`, `fork()` forwarding to `session.fork(workingDirectory: nil)` (Multitool `AgentSession.swift:100-120`)
- `ScriptedAgentSession` test fake in the test target: scripted responses, fork counting

## Acceptance Criteria
- [ ] Protocol + default decoding compile and match Multitool's shipped semantics (so the later Multitool migration is a re-export, not a rewrite)
- [ ] `RoutedAgentSession` compiles against Router's `RoutedSession`
- [ ] Fake supports scripted JSON replies and records fork/respond call counts

## Tests
- [ ] `Tests/FoundationModelsMetadataRegistryTests/AgentSessionTests.swift` — default `respond(to:generating:)` decodes a `@Generable` fixture from scripted JSON; malformed JSON throws; fork counting works
- [ ] Run `swift test` — all pass, no GPU

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.