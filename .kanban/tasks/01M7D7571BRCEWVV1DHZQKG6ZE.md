---
assignees:
- claude-code
position_column: done
position_ordinal: b880
title: Add DecisionConfig, the .decision search mode and the FoundationModelsDecision dependency
---
## What

This is the base of the decision tier experiment. The decision tier ranks the relevance of catalog items with a FoundationModelsDecision `DecisionModel`, in place of a `LanguageModel`. On this branch the decision tier stays beside the selection tier, so that one benchmark can compare the two tiers. A later task deletes the tier that loses.

This task adds the types and the configuration only. It does not add the ranking. The next task adds the ranking.

1. `Package.swift`: add the package `git@github.com:swissarmyhammer/FoundationModelsDecision.git` (`branch: "main"`), with the same URL form as the other family packages. The library target links the core product `FoundationModelsDecision` only. Do NOT link `FoundationModelsDecisionPooled`: it compiles MLX and llama.cpp. The library takes `any DecisionModel`, as it takes `any LanguageModel` for selection. Update the doc comments of the manifest.
2. `Tests/FoundationModelsMetadataRegistryTests/PackageManifestTests.swift`: add `FoundationModelsDecision` to `allowedPackageNames`. Add a test that no target of the root package names `FoundationModelsDecisionPooled`.
3. New file `Sources/FoundationModelsMetadataRegistry/DecisionConfig.swift`:

```swift
import FoundationModelsDecision

public struct DecisionConfig: Sendable {
  public static let defaultCandidateCount = 20
  public static let defaultMinimumProbability = 0.5

  /// The model that gives P(yes) for each candidate.
  public let model: any DecisionModel
  /// How many retrieval candidates the model scores for each search.
  public let candidateCount: Int
  /// A candidate with a lower P(yes) is not a match.
  public let minimumProbability: Double
  /// The yes-or-no question for one candidate block. The state of the
  /// decision session is the intent.
  public let question: @Sendable (_ id: String, _ block: String) -> Question

  public init(
    model: any DecisionModel,
    candidateCount: Int = defaultCandidateCount,
    minimumProbability: Double = defaultMinimumProbability,
    question: @escaping @Sendable (String, String) -> Question = DecisionConfig.relevanceQuestion
  )

  /// "Does this catalog entry do what the request asks? Entry `<id>`: <block>",
  /// with `BinaryCriteria` for yes (the entry does the requested task) and
  /// no (the entry is unrelated, or only shares words with the request).
  public static func relevanceQuestion(id: String, block: String) -> Question
}
```

   `init` clamps `candidateCount` to at least 1 and `minimumProbability` to `0...1`.
4. `Sources/FoundationModelsMetadataRegistry/SearchMode.swift`: add `case decision` (raw value `"decision"`), with a doc comment. Change `.auto`: decision when a decision tier is configured, else selection when a selection tier is configured, else retrieval. Update the doc comment of `.auto`.
5. `Sources/FoundationModelsMetadataRegistry/MetadataSearcher.swift` and `SharedCatalogEmbedding.swift` (the `init(sharing:...)` initializer): add `decision: DecisionConfig? = nil` after `selection:` on each public initializer and on the designated initializer. Store it in `let decisionConfig: DecisionConfig?`. Update the type doc comment.

## Acceptance Criteria
- [ ] `swift build` at the root passes, and the library target links `FoundationModelsDecision` and not `FoundationModelsDecisionPooled`.
- [ ] `DecisionConfig` exists with the API above, and its defaults are 20 candidates and 0.5.
- [ ] `SearchMode.decision.rawValue == "decision"`.
- [ ] Each public `MetadataSearcher` initializer takes `decision:` with the default `nil`. Existing call sites compile without change.

## Tests
- [ ] `Tests/FoundationModelsMetadataRegistryTests/SearchModeRawValueTests.swift`: add `.decision` to `modes`, with the name `"decision"`.
- [ ] New `Tests/FoundationModelsMetadataRegistryTests/DecisionConfigTests.swift`: the defaults; the clamp of `candidateCount` (0 → 1) and of `minimumProbability` (-1 → 0, 2 → 1); `relevanceQuestion` gives a `.binary` question whose instructions hold the id and the block.
- [ ] `PackageManifestTests`: the allowed list holds `FoundationModelsDecision`; the new test fails if a root target names `FoundationModelsDecisionPooled`.
- [ ] Run `swift test` at the root. All tests pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #decision-tier