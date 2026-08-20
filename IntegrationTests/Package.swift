// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

/// The name of the package under test, and the directory `..` holds.
private let productPackageName = "FoundationModelsMetadataRegistry"

/// The name of the FoundationModelsRouter dependency package.
private let routerDependencyName = "FoundationModelsRouter"

/// The MLX-backed model package a live `LiveModelLoader` is built over.
private let mlxPackage = "mlx-swift-lm"

/// The Hugging Face Hub client package.
private let huggingFacePackage = "swift-huggingface"

/// The Swift Transformers tokenizer package.
private let transformersPackage = "swift-transformers"

/// SwiftPM manifest for the real-model integration suite.
///
/// **Why this is a package of its own.** The org test contract
/// (swissarmyhammer/workflows' README) says: `swift test` at the root runs
/// all the unit tests, and only the unit tests, and an environment variable
/// must not select the tests. SwiftPM has no manifest-level way to hold a
/// target out of the default run, so a target in the root package always
/// runs on a bare `swift test`. A package that the root manifest never
/// names is invisible to the root's `swift test`, so the split is a
/// property of the build graph. The suite's predecessor read the
/// `METADATA_REGISTRY_INTEGRATION_TESTS` opt-in environment variable
/// instead, which made a green run that measured nothing look the same as
/// a green run that measured everything. Nothing here reads the
/// environment, and nothing may start doing so. (The `Examples/`
/// executables keep that variable as their own real-model opt-in — an
/// example program is not a test.)
///
/// The two commands are:
///
///     swift test                                     # unit tests
///     swift test --package-path IntegrationTests     # this suite
///
/// **The compile coupling this package owes CI.** While the suite was a
/// target of the root manifest, a broken integration test broke a plain
/// `swift build --build-tests` at the root, so it could never rot unnoticed
/// between real-model runs. A separate package ends that coupling: the root
/// build no longer compiles these files at all. `.github/workflows/ci.yml`
/// restores it by delegating to the shared `swift-ci.yaml` workflow with
/// `integration-package-path: IntegrationTests` — that input makes the
/// shared workflow's unit job build this package on **every** run, before
/// the expensive integration-test step runs at all. A build of this package
/// is cheap; only the run is expensive.
///
/// **Why the dependency list below repeats the root manifest's.** A SwiftPM
/// manifest cannot import code from another manifest, and a package may only
/// name the products of packages it declares itself. The declarations are
/// therefore restated here rather than shared, and each URL and requirement
/// matches `../Package.swift` exactly — a mismatch is a resolution conflict,
/// not a second opinion. `../Package.swift` carries the reasoning behind
/// each one; this manifest carries only what SwiftPM needs to resolve them.
let package = Package(
    name: "FoundationModelsMetadataRegistryIntegrationTests",
    // Commit to macOS 27 / FoundationModels v2, exactly as `../Package.swift`
    // does; a lower floor here would not resolve against it.
    platforms: [
        .macOS("27.0")
    ],
    dependencies: [
        .package(path: ".."),
        .package(url: "git@github.com:swissarmyhammer/\(routerDependencyName).git", branch: "main"),
        .package(url: "git@github.com:swissarmyhammer/\(mlxPackage).git", branch: "stable"),
        .package(url: "https://github.com/huggingface/\(huggingFacePackage)", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/\(transformersPackage)", from: "1.3.0"),
    ],
    targets: [
        // The gated Router-backed suite (plan.md M7), now ungated: four
        // scenarios that resolve a real profile through `Router` and
        // generate on the GPU, so this is the target CI runs in a job of
        // its own.
        //
        // `SemanticSearchCore` is the library half of the SemanticSearch
        // example. The embed + RRF quality scenario drives its
        // `runSemanticSearch(query:embedder:onDiagnostic:)` over the
        // `gitCommands` fixture catalog, so it measures the search a host
        // of that example really gets.
        //
        // The MLX and Hugging Face products are the live-inference wiring:
        // `MLXHuggingFace` for the `#hubDownloader()` /
        // `#huggingFaceTokenizerLoader()` macros a real `LiveModelLoader`
        // is built from, `MLXLMCommon` for `ModelRef`/profile plumbing, and
        // `HuggingFace` and `Tokenizers` for what those macros expand into.
        .testTarget(
            name: "FoundationModelsMetadataRegistryIntegrationTests",
            dependencies: [
                .product(name: productPackageName, package: productPackageName),
                .product(name: "SemanticSearchCore", package: productPackageName),
                .product(name: routerDependencyName, package: routerDependencyName),
                .product(name: "MLXHuggingFace", package: mlxPackage),
                .product(name: "MLXLMCommon", package: mlxPackage),
                .product(name: "HuggingFace", package: huggingFacePackage),
                .product(name: "Tokenizers", package: transformersPackage),
            ],
            path: "Tests/FoundationModelsMetadataRegistryIntegrationTests"
        )
    ]
)
