---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m1ab501mn1aam6ehjjfs0sjk
  text: |-
    Research done. What I found:

    **Reachability confirmed.** `git show cafac33^:IntegrationTests/Package.swift` declared `.package(path: "..")` plus four Router/MLX/HuggingFace packages. The new manifest keeps only `.package(path: "..")` and one test target on `.product(name: "FoundationModelsMetadataRegistry", package: "FoundationModelsMetadataRegistry")`. FoundationModelsRanker resolves transitively, and `@_exported import FoundationModelsRanker` in `Sources/FoundationModelsMetadataRegistry/FoundationModelsRankerReexport.swift` carries `SelectionConfig`, `AgentSession`, `SelectionTier` and `Tokenizer` across.

    **`.gitignore` already covers the nested package.** It holds `.build/` and `Package.resolved` with no leading slash, so both match at any depth. No change needed.

    **Root guard tests stay green, and neither is mine to touch.**
    - `CIWorkflowTests` asserts `ci.yml` passes NO `integration-*` input. Wiring CI is card ^f10jvv9, so `ci.yml` is untouched here.
    - `PlanDocumentTests` asserts `plan.md` never says "IntegrationTests". `plan.md` is untouched here; card ^3cj12gk reconciles it.

    **FoundationModels API, read off the macOS 27 `.swiftinterface`:**
    - `SystemLanguageModel` is `final public class ... : Sendable`, not MainActor-isolated. `availability` and `isAvailable` are plain properties, so a static non-async function reads them.
    - `Availability` is `@frozen`, `Equatable`, `Sendable` — `available` / `unavailable(UnavailableReason)`. No `@unknown default` needed.
    - `Availability.UnavailableReason` is NOT frozen: `deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady`. A switch over it needs `@unknown default`, exactly as the card says.

    **A stale premise in the card, found on the SDK.** `LanguageModelSession.GenerationError` is `@available(macOS, introduced: 26.0, deprecated: 27.0)`, and every one of the four cases the card names carries its own "Use X instead" deprecation. On the macOS 27 floor this package declares, the replacements are:
    - `LanguageModelError` (macOS 27) — `rateLimited`, `guardrailViolation`, `unsupportedLanguageOrLocale`, plus `timeout`, `contextSizeExceeded`, `refusal` and three `unsupported*` cases.
    - `SystemLanguageModel.Error` (macOS 27) — `assetsUnavailable`.
    - `LanguageModelSession.Error` (macOS 27) — `concurrentRequests`, `transcriptMutationWhileResponding`.

    So a helper that catches `LanguageModelSession.GenerationError` alone would very likely catch nothing on this machine, and naming that type may also raise a deprecation warning, which the zero-warning bar forbids. Plan: `recordingEnvironmentFaults(_:)` catches the card's named type AND the three macOS 27 types, so the acceptance criterion holds literally and the helper also catches what this OS really throws. I will measure the deprecation warning and report back before settling it.

    **One failure, not two.** `Issue.record(...)` followed by `throw` gives Swift Testing two issues (the recorded one, then `errorCaught`). `try #require(condition, comment)` is Swift Testing's own record-then-throw primitive and yields exactly one. Both helpers use it, so the "exactly one failure naming a reason" check can pass.

    **Fixture vocabulary.** `Tokenizer.tokenize(text:)` does no stop-word removal, so a strict token intersection across the three groups also catches "a", "the", "and". The fixture blocks are therefore written with disjoint function words as well as disjoint subject matter — no stop-word list to hand-maintain.
  timestamp: 2026-08-30T22:02:59.508354+00:00
- actor: claude-code
  id: 01m1abkskb87rhxhwyfhhnfmjz
  text: |-
    ## BLOCKER — one acceptance criterion cannot be met on this platform floor

    > - [ ] `ModelAvailability.recordingEnvironmentFaults(_:)` catches `LanguageModelSession.GenerationError` and records it as an environment fault.

    **The conflict.** The card requires naming `LanguageModelSession.GenerationError`. The SDK marks that type `@available(macOS, introduced: 26.0, deprecated: 27.0)`, and this package's floor is macOS 27, so every reference to it raises a compiler warning. The pipeline requires zero warnings. Both cannot hold.

    **Measured, not assumed.** With the type in the roster, `swift build --package-path IntegrationTests --build-tests` answered:

    ```
    ModelAvailability.swift:93:46: warning: 'GenerationError' was deprecated in macOS 27.0 [#DeprecatedDeclaration]
    ```

    **Every containment route was measured too**, with `xcrun swiftc -target arm64-apple-macos27.0 -swift-version 6 -typecheck` over one probe holding three shapes:

    | the shape | reported |
    |---|---|
    | a bare `error is LanguageModelSession.GenerationError` | `warning: 'GenerationError' was deprecated in macOS 27.0` |
    | the same reference inside a declaration marked `@available(macOS, deprecated: 27.0, ...)` | silent |
    | a non-deprecated declaration calling that deprecated helper | `warning: 'insideDeprecated' was deprecated in macOS 27.0` |

    So the suppression works only inside a deprecated declaration, and the deprecation then cascades to every caller — through `recordingEnvironmentFaults(_:)` and out to each scenario that wraps a model call. There is no way to name a deprecated type from non-deprecated Swift without a warning somewhere.

    **Why the criterion is also stale on the merits.** The SDK points each of the four cases the card names at a macOS 27 replacement:

    | the case the card names | where it lives on macOS 27 |
    |---|---|
    | `assetsUnavailable` | `SystemLanguageModel.Error.assetsUnavailable` |
    | `rateLimited` | `LanguageModelError.rateLimited` |
    | `unsupportedLanguageOrLocale` | `LanguageModelError.unsupportedLanguageOrLocale` |
    | `guardrailViolation` | `LanguageModelError.guardrailViolation` |

    On this floor the framework raises the replacements, so a clause catching only `GenerationError` would very likely catch nothing at all — the criterion as written buys no coverage and costs a warning.

    **What the tree holds right now.** `isEnvironmentFault(_:)` names `LanguageModelError`, `SystemLanguageModel.Error` and `LanguageModelSession.Error`, so all four faults the card names are caught, through their current types, with no warning. That is the state that satisfies every other requirement, and the doc comment on that function records the deprecation and why the type is absent. I did not treat this as mine to settle: a person decides between amending the criterion to the macOS 27 types and accepting a deprecation warning on every build.

    ## Everything else on the card is done and green

    - `swift build --package-path IntegrationTests` succeeds. `swift package show-dependencies` reports exactly `..` plus its own transitive FoundationModelsRanker — no Router, no MLX, no Hugging Face, and no `Examples/` reference anywhere but the manifest prose that says they are excluded.
    - `requireAvailable()` is `throws`, names the `UnavailableReason`, and stops the test. Verified by the inversion the card asks for: with the read temporarily replaced by `.unavailable(.appleIntelligenceNotEnabled)`, the run reported **exactly one** issue —
      `the system language model is unavailable: Apple Intelligence is switched off in System Settings (appleIntelligenceNotEnabled) — this suite measures Apple Intelligence and can measure nothing without it, ...` — and the `#expect(isAvailable)` line below it never ran, so no second failure buried the first. Reverted.
    - `IntegrationCatalog` exposes `base` (4 entries), `addOnly` and `removeOnly`, with `groups` and `vocabulary(of:)` beside them. `IntegrationCatalogTests` tokenizes each group with the retrieval tier's own `Tokenizer` and asserts every pair is disjoint, after first asserting no group tokenized to nothing so the check cannot pass vacuously.
    - `swift test --package-path IntegrationTests`: 2 tests in 2 suites passed, zero warnings.
    - `swift test` at the root: **114 tests in 12 suites passed**, unchanged, and it never reached the nested package.

    Nothing outside `IntegrationTests/` was touched. `.gitignore` already covers `IntegrationTests/.build` and `IntegrationTests/Package.resolved` (`git check-ignore -v` confirms both), so the five new files are the whole change.
  timestamp: 2026-08-30T22:11:04.427890+00:00
- actor: claude-code
  id: 01m1abm0qkwwbkxwaayr59agrc
  text: |-
    ### implement — stuck
    - evidence: 5 new files under `IntegrationTests/`; `swift test --package-path IntegrationTests` → 2 tests in 2 suites passed, 0 warnings; `swift test` at root → 114 tests in 12 suites passed, unchanged; `swift package show-dependencies` → `..` only; deprecation probe via `xcrun swiftc -target arm64-apple-macos27.0 -typecheck` → 2 warnings across 3 shapes.
    - gap: acceptance criterion 3 — `recordingEnvironmentFaults(_:)` does not name `LanguageModelSession.GenerationError`, because that type is deprecated at macOS 27 and naming it warns on every build. See the BLOCKER comment above for the measurements and the two ways out.
    - next: a person decides — amend the criterion to the macOS 27 error types (`LanguageModelError`, `SystemLanguageModel.Error`, `LanguageModelSession.Error`, which the code already names), or accept a `#DeprecatedDeclaration` warning on every build. Every other criterion is met and green.
  timestamp: 2026-08-30T22:11:11.731826+00:00
position_column: doing
position_ordinal: '80'
title: Create the nested IntegrationTests package with a loud availability precondition
---
## What

Recreate `IntegrationTests/` as a nested SwiftPM package holding the real-model suite. It drives Apple Intelligence through `LanguageModelSession(model: .default)` and needs **no new dependencies** — `FoundationModels` is an OS framework, and `SelectionConfig`/`AgentSession` reach the nested package through `@_exported import FoundationModelsRanker` at `Sources/FoundationModelsMetadataRegistry/FoundationModelsRankerReexport.swift:12`.

Proven by the deleted suite: `git show cafac33^:IntegrationTests/Package.swift` declared no Ranker dependency, and its tests used `SelectionConfig`, `.librarianDefault` and `MetadataSearcher` with only two imports.

Files:
- `IntegrationTests/Package.swift` — `platforms: [.macOS("27.0")]`, one dependency `.package(path: "..")`, one test target on the root's single product.
- `IntegrationTests/Tests/FoundationModelsMetadataRegistryIntegrationTests/Support/ModelAvailability.swift`
- `IntegrationTests/Tests/FoundationModelsMetadataRegistryIntegrationTests/Support/IntegrationCatalog.swift`

The root package exports exactly one product (`Package.swift:137-142`), so this suite cannot reach `ExamplesSupport` or any `Examples/` type. Do not add a product to work around that.

### `requireAvailable()` must THROW, not just record

`SystemLanguageModel.default.availability` is synchronous and non-throwing. `Availability` is `@frozen`; `UnavailableReason` is **not** frozen (`deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady`), so a `switch` over it needs `@unknown default`.

`static func requireAvailable() throws` — record the reason, then throw. A version that only records lets the body continue into `search(...)`, producing two failures where the second hides the first. Do not use `.enabled(if:)`; that silently passes, and the user chose loud failure.

Prefer `try #require(...)` over `Issue.record` followed by a throw: `#require` is the record-then-throw primitive and yields exactly one issue.

### `.available` does not mean usable — catch the environment faults

Four faults fire *after* the availability check and surface as plain thrown errors indistinguishable from a product defect: assets unavailable, rate limited, unsupported language or locale, and guardrail violation.

Add `ModelAvailability.recordingEnvironmentFaults(_:)` — runs a throwing body, catches those, and re-records them as environment faults rather than product failures. Both test cards wrap their model calls in it.

**Corrected 2026-08-30.** This card originally named `LanguageModelSession.GenerationError` as the type to catch. **That was wrong.** The SDK marks it `@available(macOS, introduced: 26.0, deprecated: 27.0)`, and this package's floor is macOS 27, so naming it warns on every build against a zero-warning bar — and the deprecation cascades: a non-deprecated caller of a deprecated-annotated helper warns in turn, measured across three shapes with `xcrun swiftc -target arm64-apple-macos27.0 -typecheck`. The SDK redirects all four cases to macOS 27 replacements: assets-unavailable to `SystemLanguageModel.Error`, and the other three to `LanguageModelError`. A clause catching only `GenerationError` would likely catch nothing on this OS.

Catch the **current** types. Record the deprecation in the doc comment so the next reader does not re-litigate it.

### The fixture shape is load-bearing for both test cards

`^ddaxwaz` needs a reserved item to add and a reserved item to remove. Design all of it here so neither test card amends it.

`Tokenizer.tokenize(text:)` strips no stop words, so write the groups to share no token at all, function words included, rather than maintaining a stop list.

Keep the assembled prefix comfortably under `SelectionConfig.defaultCapacityCharacterLimit` (32,000) so both tests stay on the under-budget cached-root path.

## Acceptance Criteria

- [x] `swift build --package-path IntegrationTests` succeeds, with exactly one dependency, `.package(path: "..")`, and no Router/MLX/Hugging Face/`Examples/` reference.
- [x] `ModelAvailability.requireAvailable()` is `throws`, names the `UnavailableReason`, and stops the test.
- [x] `ModelAvailability.recordingEnvironmentFaults(_:)` catches the four environment faults through the macOS 27 types (`SystemLanguageModel.Error`, `LanguageModelError`) and records them as environment faults, with **zero build warnings**.
- [x] `IntegrationCatalog` exposes three disjoint groups — a **base** catalog, one **add-only** item, one **remove-only** item — sharing no token at all across groups.
- [x] The root `swift test` still runs 114 tests and never reaches this package.

## Tests

- [x] A placeholder test calling `requireAvailable()` and asserting `SystemLanguageModel.default.isAvailable`. `swift test --package-path IntegrationTests` passes.
- [x] Prove the precondition can fail and stops the test: temporarily invert it, confirm exactly one failure naming a reason, revert.
- [x] A vocabulary-disjointness assertion over the three fixture groups, including a non-empty guard so an emptied group cannot pass vacuously. Runs without a model.
- [x] Run `swift test` at the root. 114 tests pass, unchanged.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.