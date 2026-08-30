// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

/// The name of the package under test, of its single library product, and of
/// the directory `..` holds.
///
/// The root manifest exports exactly one product, and that product carries the
/// whole surface this suite drives.
private let productPackageName = "FoundationModelsMetadataRegistry"

/// SwiftPM manifest for the real-model integration suite.
///
/// **Why this is a package of its own.** The org test contract
/// (swissarmyhammer/workflows' README) says: `swift test` at the root runs all
/// the unit tests, and only the unit tests, and an environment variable must
/// not select the tests. SwiftPM has no manifest-level way to hold a target
/// out of the default run, so a target in the root package always runs on a
/// bare `swift test`. A package that the root manifest never names is
/// invisible to the root's `swift test`, so the split is a property of the
/// build graph rather than a convention. Nothing here reads the environment,
/// and nothing may start doing so. (The `Examples/` executables keep
/// `METADATA_REGISTRY_INTEGRATION_TESTS` as their own real-model opt-in — an
/// example program is not a test.)
///
/// The two commands are:
///
///     swift test                                     # unit tests
///     swift test --package-path IntegrationTests     # this suite
///
/// **What this suite measures.** Apple Intelligence, driven through
/// `LanguageModelSession(model: .default)`. `Support/ModelAvailability.swift`
/// stops a run loudly when the machine cannot serve that model, and
/// `Support/IntegrationCatalog.swift` holds the fixture every scenario ranks
/// and selects over.
///
/// **Why one dependency is the whole list.** `FoundationModels` is an OS
/// framework, so it needs no package entry. Everything else this suite names —
/// `SelectionConfig`, `AgentSession`, `SelectionTier`, `Tokenizer`, and the
/// retrieval primitives beside them — reaches it through the package under
/// test's own `@_exported import FoundationModelsRanker`
/// (`Sources/FoundationModelsMetadataRegistry/FoundationModelsRankerReexport.swift`),
/// so `.package(path: "..")` and the one product below are sufficient. The
/// FoundationModelsRanker package still resolves, as a transitive dependency
/// of `..`; this manifest simply never names it.
///
/// **The compile coupling this package owes CI.** The root build does not
/// compile these files at all, so a broken integration test cannot break a
/// plain `swift build --build-tests` at the root. `.github/workflows/ci.yml`
/// restores that coupling by passing `integration-package-path:
/// IntegrationTests` to the shared `swift-ci.yaml` workflow: that input makes
/// the shared workflow's unit job build this package on **every** run, before
/// the expensive integration-test step runs at all. A build of this package is
/// cheap; only the run is expensive. `CIWorkflowTests` pins that input from
/// the root package, so the coupling cannot be dropped unnoticed.
let package = Package(
    name: "FoundationModelsMetadataRegistryIntegrationTests",
    // Commit to macOS 27 / FoundationModels v2, exactly as `../Package.swift`
    // does; a lower floor here would not resolve against it.
    platforms: [
        .macOS("27.0")
    ],
    dependencies: [
        .package(path: ".."),
    ],
    targets: [
        // The real-model suite. One dependency, one product: no Router, no
        // MLX, no Hugging Face, and nothing from `Examples/` — the root
        // manifest exports a single library product, and `ExamplesSupport` and
        // the example cores are targets of that package rather than products
        // of it, so they are not reachable here and must not be made so.
        .testTarget(
            name: "\(productPackageName)IntegrationTests",
            dependencies: [
                .product(name: productPackageName, package: productPackageName),
            ],
            path: "Tests/\(productPackageName)IntegrationTests"
        )
    ]
)
