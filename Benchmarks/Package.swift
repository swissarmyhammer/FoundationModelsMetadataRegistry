// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

/// The name of the package under measurement, of its library product, and of
/// the directory `..` holds.
private let registryPackageName = "FoundationModelsMetadataRegistry"

/// The name of the library target that holds the fixture, the metrics, the
/// report, the runner and the argument parser.
private let supportTargetName = "BenchmarkSupport"

/// The name of the executable target that runs the real configurations.
private let runnerTargetName = "RankingBenchmark"

/// The name of the executable target that runs the cost gate at 100,000
/// items.
private let scaleRunnerTargetName = "ScaleBenchmark"

/// The name of the FoundationModelsExtras package, and of its core product:
/// `ModelPool`, `HubModelLoader`, `PooledEmbedder`, `PooledModel` and the
/// `PooledEmbedding` protocol.
private let extrasPackageName = "FoundationModelsExtras"

/// The name of the product of FoundationModelsExtras that loads GGUF files:
/// `LlamaCppModelLoader`.
private let extrasLlamaCppProductName = "FoundationModelsExtrasLlamaCpp"

/// The name of the FoundationModelsDecision package, and of its core product:
/// `DecisionModel`, `Question` and `DeciderPromptFormat`.
private let decisionPackageName = "FoundationModelsDecision"

/// The name of the product of FoundationModelsDecision that runs a decision
/// model from a `ModelPool`: `PooledDecisionModel`.
private let decisionPooledProductName = "FoundationModelsDecisionPooled"

/// The GitHub organization URL base of the swissarmyhammer packages. The same
/// SSH form as the root manifest.
private let swissArmyHammerOrg = "git@github.com:swissarmyhammer/"

/// SwiftPM manifest for the ranking benchmarks of the registry.
///
/// **Why this is a package of its own.** The root manifest does not name this
/// package, the same as `Examples/` and `IntegrationTests/`. Thus a bare
/// `swift test` at the root does not build or run it, and CI does not
/// download the models that a benchmark run loads. Use these commands:
///
///     swift build --package-path Benchmarks
///     swift test --package-path Benchmarks
///
/// **What `BenchmarkSupport` holds.** A labeled fixture (a catalog of items in
/// eight domains, and intents with their correct ids), the ranking metrics,
/// the report that compares configurations, the runner that searches with
/// each configuration, and the parser of the command line arguments. It uses
/// only the public API of the registry, and it loads no model. It links no
/// model runtime product: not `FoundationModelsExtrasLlamaCpp` and not
/// `FoundationModelsDecisionPooled`. Its unit tests do not load a model
/// either: they use stub models.
///
/// **What `RankingBenchmark` holds.** The real configurations, which load
/// models from Hugging Face, and the `main` that runs them. Only this target
/// links the model runtime products. Run it with:
///
///     swift run --package-path Benchmarks RankingBenchmark --output <dir>
let package = Package(
  name: "Benchmarks",
  // The same floor as the root package. A lower floor does not resolve
  // against it.
  platforms: [
    .macOS("27.0")
  ],
  dependencies: [
    .package(path: ".."),
    .package(url: "\(swissArmyHammerOrg)\(extrasPackageName).git", branch: "main"),
    .package(url: "\(swissArmyHammerOrg)\(decisionPackageName).git", branch: "main"),
  ],
  targets: [
    .target(
      name: supportTargetName,
      dependencies: [
        .product(name: registryPackageName, package: registryPackageName)
      ],
    ),
    .executableTarget(
      name: runnerTargetName,
      dependencies: [
        .target(name: supportTargetName),
        .product(name: registryPackageName, package: registryPackageName),
        // `PooledEmbedder`, `PooledModel`, `ModelPool` and `HubModelLoader`.
        .product(name: extrasPackageName, package: extrasPackageName),
        // `LlamaCppModelLoader`, for the GGUF configuration.
        .product(name: extrasLlamaCppProductName, package: extrasPackageName),
        // `DeciderPromptFormat`.
        .product(name: decisionPackageName, package: decisionPackageName),
        // `PooledDecisionModel`.
        .product(name: decisionPooledProductName, package: decisionPackageName),
      ],
      // A target that imports `FoundationModelsExtrasLlamaCpp` must set
      // C++ interoperability, because the llama.cpp modules need it.
      swiftSettings: [.interoperabilityMode(.Cxx)],
    ),
    // The cost gate of a catalog of 100,000 items (D207): the time of a
    // `.retrieval` search, of an update of 20 items and of a start from the
    // stored catalog, and the memory. It links the registry only and loads
    // no model: its embedder is a fast deterministic stub.
    //
    //     swift run -c release --package-path Benchmarks ScaleBenchmark
    .executableTarget(
      name: scaleRunnerTargetName,
      dependencies: [
        .product(name: registryPackageName, package: registryPackageName),
        .product(name: extrasPackageName, package: extrasPackageName),
      ],
    ),
    .testTarget(
      name: "\(supportTargetName)Tests",
      dependencies: [
        .target(name: supportTargetName),
        .product(name: registryPackageName, package: registryPackageName),
        // `LabelDecisionModel` is a stub `DecisionModel`. The core product
        // has no package dependency.
        .product(name: decisionPackageName, package: decisionPackageName),
        // `ConstantEmbedder` is a stub `PooledEmbedding`. The registry
        // product already links this core product, so it adds nothing to
        // the build.
        .product(name: extrasPackageName, package: extrasPackageName),
      ],
    ),
  ],
)
