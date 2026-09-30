// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

/// The name of the package under test, of its single library product, and of
/// the directory `..` holds.
///
/// The root manifest exports exactly one product, and that product carries the
/// whole surface this suite drives.
private let productPackageName = "FoundationModelsMetadataRegistry"

/// The name of the FoundationModelsExtras package and of its core product,
/// which holds `PooledEmbedder`, `ModelPool` and `ModelRef`.
///
/// The root package depends on this package, but it does not re-export it. So
/// `PooledEmbedderRealModelTests`, which names `PooledEmbedder`, needs this
/// product directly. The URL is the URL of the root manifest, so SwiftPM
/// resolves one package for both.
private let extrasPackageName = "FoundationModelsExtras"

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
/// and selects over. `PooledEmbedderRealModelTests` also measures a real MLX
/// embedding model, which FoundationModelsExtras loads through
/// `PooledEmbedder`.
///
/// **Why two dependencies are the whole list.** `FoundationModels` is an OS
/// framework, so it needs no package entry. `SelectionConfig`, `AgentSession`,
/// `SelectionTier`, `Tokenizer`, and the retrieval primitives beside them
/// reach this suite through the package under test's own
/// `@_exported import FoundationModelsRanker`
/// (`Sources/FoundationModelsMetadataRegistry/FoundationModelsRankerReexport.swift`),
/// so `.package(path: "..")` gives them. The FoundationModelsRanker package
/// still resolves, as a transitive dependency of `..`; this manifest never
/// names it. `PooledEmbedder` and `ModelRef` come from the core
/// FoundationModelsExtras product (see `extrasPackageName`).
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
        .macOS("27.0"),
    ],
    dependencies: [
        .package(path: ".."),
        .package(url: "git@github.com:swissarmyhammer/\(extrasPackageName).git", branch: "main"),
    ],
    targets: [
        // The real-model suite. Two products: the library under test, and the
        // core FoundationModelsExtras product for `PooledEmbedder`. No Router,
        // and nothing from `Examples/` — the root manifest exports a single
        // library product, and `ExamplesSupport` and the example cores are
        // targets of that package rather than products of it, so they are not
        // reachable here and must not be made so. MLX and Hugging Face
        // resolve as dependencies of FoundationModelsExtras only.
        .testTarget(
            name: "\(productPackageName)IntegrationTests",
            dependencies: [
                .product(name: productPackageName, package: productPackageName),
                .product(name: extrasPackageName, package: extrasPackageName),
            ],
            path: "Tests/\(productPackageName)IntegrationTests",
        ),
    ],
)
