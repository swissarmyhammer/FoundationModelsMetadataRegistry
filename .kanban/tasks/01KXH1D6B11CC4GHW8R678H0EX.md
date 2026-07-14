---
comments:
- actor: claude-code
  id: 01kxh9v0d63ftsm0rgw0sqbhx5
  text: 'Picked up by /finish scoped-batch orchestrator. Starting iteration 1: dispatching /implement.'
  timestamp: 2026-07-14T21:51:57.350622+00:00
- actor: claude-code
  id: 01kxha4mvfp402wyvkqfpdb4jb
  text: |-
    Implementation landed (TDD, red then green):

    - `Sources/FoundationModelsMetadataRegistry/Selection/SelectionTier.swift`: `idEnumGrammar(ids:)` now injects `maxItems: ids.count` on the `ids` array schema alongside the existing `enum`/`uniqueItems`, with a comment explaining that Router's `RuntimeJSONSchemaConverter` enforces `minItems`/`maxItems` (mapped to `DynamicGenerationSchema`'s `maximumElements`) but silently ignores `uniqueItems`, so `maxItems` is the constraint that actually stops the runaway. Docstring updated.
    - `Examples/LiveRouterSupport/LiveRouterSupport.swift`: the public hand-built `idEnumGrammar(ids:)` (the "equivalent" the gated Librarian/BigCatalog examples use) had the identical unbounded-array failure mode; added the same `maxItems: ids.count`.
    - `Tests/FoundationModelsMetadataRegistryTests/SelectionTests.swift`: new `idEnumGrammarBoundsIdsWithMaxItemsAtTheCandidateCount` — watched it fail red (`maxItems` was nil) before the fix, green after.

    Discovery/confirmation: `RuntimeJSONSchemaConverter` in the pinned FoundationModelsRouter checkout reads `schema["maxItems"] as? Int` into `maximumElements` (Guided/RuntimeJSONSchemaConverter.swift), and its documented supported subset includes `minItems`/`maxItems`, so the injected bound is genuinely enforced by the compiled grammar. The converter is internal to the Router package, so the unit test asserts on the schema surface the converter consumes (same pattern as the existing `uniqueItems` test); true structural rejection is additionally covered by the gated real-model suite's grammar scenario.

    Full `swift test`: 98 tests in 9 suites, all passing.

    Remaining follow-up (out of scope for this repo): acceptance criterion 3 — re-run FoundationModelsMultitool's PrefixReuseTests on real hardware after bumping that repo's pinned resolution to pick up this fix, confirming the second findAPIs call on an off-topic task no longer runs away to thousands of tokens.
  timestamp: 2026-07-14T21:57:13.199835+00:00
position_column: done
position_ordinal: 8d80
title: Bound SelectionTier.idEnumGrammar's ids array with maxItems to prevent runaway guided-generation on off-topic findAPIs queries
---
## What

Root-caused while investigating FoundationModelsMultitool's task `9hchxj6` (native tool-calling reliability / fork() prefix-reuse regression). `SelectionTier.idEnumGrammar(ids:)` (in this repo, `Sources/FoundationModelsMetadataRegistry/Selection/SelectionTier.swift`) derives the xgrammar JSON Schema constraining the selection tier's guided `Selection { ids: [String] }` output. It injects an `enum` (the current candidate id set) and `uniqueItems: true` into the `ids` array's schema, but never sets `maxItems`.

`FoundationModelsRouter`'s `RuntimeJSONSchemaConverter` (the code that actually compiles the JSON Schema into an xgrammar constraint) supports `minItems`/`maxItems` when present in the schema, but does **not** read or enforce `uniqueItems` at all (confirmed: zero references to `uniqueItems` anywhere in `FoundationModelsRouter`'s `Guided/` sources). So the injected `uniqueItems: true` is silently dropped — it has no effect on the compiled grammar — and with no `maxItems` cap either, the compiled grammar permits an **unbounded-length** array of (possibly repeated) enum-member id strings.

## Evidence

Reproduced deterministically on real M3 Ultra hardware (`mlx-community/Qwen2.5-1.5B-Instruct-4bit`), 2 independent runs, identical result both times: FoundationModelsMultitool's `PrefixReuseTests`' second `findAPIs` call — task "convert 100 USD to EUR" against a ~20-tool registry with no matching tool — generated **6150 tokens** (vs. the first call's 13 tokens for a genuine match), producing a ~104-106x wall-clock slowdown. Added temporary diagnostic instrumentation directly into the local `mlx-swift-lm` `PromptCache`/`Executor` checkout (reverted, never committed) and confirmed prefix-reuse itself worked correctly (95% of tokens served from `PromptCache`, only 73 fresh tokens fed) — the slowdown is caused entirely by the generation call itself running away, not by any caching defect. This is the actual root cause of what looked like a `fork()`/`PromptCache` regression on that task — it isn't one.

## Fix

In `SelectionTier.idEnumGrammar(ids:)`, also inject a `maxItems` bound on `ids` — e.g. `ids.count` (never more selections than there are candidates) or `config.candidateLimit`-scoped for the over-budget path — so the compiled grammar structurally caps how long a degenerate/off-topic selection can run, closing off the runaway-generation failure mode regardless of whether `uniqueItems` support is ever added to `RuntimeJSONSchemaConverter`.

Also consider (separately, lower priority): teach `RuntimeJSONSchemaConverter` (in `FoundationModelsRouter`) to actually enforce `uniqueItems` for arrays, since it's currently a schema property with zero effect — either support it or stop injecting it so the schema doesn't claim a guarantee the grammar doesn't provide.

## Acceptance Criteria
- [ ] `idEnumGrammar(ids:)` (or its equivalent) sets a `maxItems` bound on the `ids` array.
- [ ] A unit test (in `FoundationModelsMetadataRegistryTests`) confirms the compiled grammar structurally rejects an id array longer than the bound.
- [ ] Re-run FoundationModelsMultitool's `PrefixReuseTests` on real hardware with this fix in place (after bumping the pinned resolution there); confirm the second `findAPIs` call for an off-topic/no-match task no longer runs away to thousands of tokens.
- [ ] Full `swift test` in both repos remains green.