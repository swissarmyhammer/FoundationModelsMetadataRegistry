// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

/// The package, library product, and library target name.
///
/// Repeated identifiers are extracted to named constants so the manifest has
/// a single source of truth, following the pattern established by the sibling
/// FoundationModelsRouter and CodeContextKit packages.
let packageName = "FoundationModelsMetadataRegistry"

/// The name of the FoundationModelsRouter dependency package.
///
/// Wired as a sibling path dependency the same way
/// `../CodeContextKit/Package.swift` does. Router supplies
/// `RoutedLLM`/`RoutedSession` (selection), `RoutedEmbedder` (cosine), and
/// `Grammar` (xgrammar id enums) to the production conformers (plan.md §10);
/// the core — catalog, signals, RRF, both seams — compiles and unit-tests
/// without exercising Router at runtime (fakes conform to the seams).
let routerDependencyName = "FoundationModelsRouter"

/// The `mlx-swift-lm` fork's package name — the same remote dependency
/// FoundationModelsRouter itself declares. Re-declared here with the
/// identical URL/branch (so SwiftPM's dependency resolution unifies the two
/// into a single resolved checkout, never a duplicate) so `SemanticSearchCore`
/// can import `MLXHuggingFace`'s `#hubDownloader()` /
/// `#huggingFaceTokenizerLoader()` macros to build a live `Router` — the
/// only place this package touches MLX directly (plan.md §13).
let mlxPackage = "mlx-swift-lm"

/// The Hugging Face Hub client and tokenizer packages `SemanticSearchCore`
/// links to supply `LiveModelLoader`'s `Downloader`/`TokenizerLoader`,
/// mirroring FoundationModelsRouter's own gated integration suite and its
/// `Examples/MultiModelGeneration` demo (`hubProducts` in that package's
/// manifest). Needed only by `SemanticSearchCore`'s live-Router path; the
/// library target never imports these.
let huggingFacePackage = "swift-huggingface"

/// The Hugging Face Transformers package, whose `Tokenizers` product
/// supplies `LiveModelLoader`'s `TokenizerLoader` alongside
/// `huggingFacePackage`'s `Downloader`. Needed only by
/// `SemanticSearchCore`'s live-Router path; the library target never
/// imports it.
let transformersPackage = "swift-transformers"

/// The SwiftPM manifest for FoundationModelsMetadataRegistry (plan.md §10).
///
/// A single library target over the FoundationModelsRouter sibling, a Swift
/// Testing unit test target, and the `Examples/` executable targets (§13):
/// `CatalogSearch` (keyword-only, GPU-free) and `SemanticSearch`
/// (`RoutedEmbedderAdapter` over a live Router, with a `--no-embedder` flag
/// for the GPU-free degraded path) — demos only, never a dependency of the
/// library. Each example's entry logic lives in its own `*Core` library
/// target (`CatalogSearchCore`, `SemanticSearchCore`) rather than directly in
/// `main.swift`, so the test target can `@testable import` and invoke it
/// directly as a plain library dependency, without the special (and, on this
/// toolchain, crash-prone) "testable executable" build path SwiftPM uses
/// when a test target depends on an executable target directly.
let package = Package(
    name: packageName,
    // Commit to macOS 27 / FoundationModels v2; floor inherited from
    // FoundationModelsRouter, no pre-27 fallback (plan.md §10).
    platforms: [
        .macOS("27.0")
    ],
    products: [
        .library(
            name: packageName,
            targets: [packageName]
        )
    ],
    dependencies: [
        .package(path: "../\(routerDependencyName)"),
        .package(url: "https://github.com/swissarmyhammer/\(mlxPackage)", branch: "mlx-foundationmodels"),
        .package(url: "https://github.com/huggingface/\(huggingFacePackage)", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/\(transformersPackage)", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: packageName,
            dependencies: [
                .product(name: routerDependencyName, package: routerDependencyName)
            ],
            path: "Sources/\(packageName)"
        ),
        .testTarget(
            name: "\(packageName)Tests",
            dependencies: [
                .target(name: packageName),
                .target(name: "ExamplesSupport"),
                .target(name: "CatalogSearchCore"),
                .target(name: "SemanticSearchCore"),
            ],
            path: "Tests/\(packageName)Tests"
        ),
        // Fixture type (`GitCommand`), the common fixture prefix
        // (`baseGitCommands`), and the match formatter (`formattedMatches`)
        // shared by both example cores (plan.md §13) — extracted here rather
        // than duplicated so the type and its fixture data/formatting have a
        // single source of truth. Each core still owns its own
        // divergent/additional fixture items locally.
        .target(
            name: "ExamplesSupport",
            dependencies: [.target(name: packageName)],
            path: "Examples/ExamplesSupport"
        ),
        // `CatalogSearch`'s entry logic (plan.md §13 M1): fixture items
        // conformed to `SearchableMetadata`, a keyword-only
        // `MetadataSearcher(mode: .retrieval)` — no embedder, no model — one
        // query, `Match`es with their per-signal `Signals`. A plain library
        // (not the executable itself) so `ExamplesSmokeTests` can invoke it
        // directly.
        .target(
            name: "CatalogSearchCore",
            dependencies: [
                .target(name: packageName),
                .target(name: "ExamplesSupport"),
            ],
            path: "Examples/CatalogSearchCore"
        ),
        // The ~30-line hello world (plan.md §13 M1): a thin runnable entry
        // point over `CatalogSearchCore`. Runs anywhere, GPU-free; `swift
        // build` keeps it compiling in CI.
        .executableTarget(
            name: "CatalogSearch",
            dependencies: [
                .target(name: "CatalogSearchCore"),
                .target(name: "ExamplesSupport"),
            ],
            path: "Examples/CatalogSearch"
        ),
        // `SemanticSearch`'s entry logic (plan.md §13 M2): `CatalogSearch`
        // plus `RoutedEmbedderAdapter` — the cosine signal joins fusion once
        // a live Router resolves a real embedder, so a paraphrased query
        // ranks where keywords alone miss; the `--no-embedder` path
        // demonstrates the graceful keyword-only degradation and its
        // diagnostic, GPU-free. A plain library (not the executable itself)
        // so `ExamplesSmokeTests` can invoke the GPU-free path directly.
        // Links the same MLX + Hugging Face products as
        // FoundationModelsRouter's own `Examples/MultiModelGeneration` to
        // construct a live `Router` + `LiveModelLoader`.
        .target(
            name: "SemanticSearchCore",
            dependencies: [
                .target(name: packageName),
                .target(name: "ExamplesSupport"),
                .product(name: routerDependencyName, package: routerDependencyName),
                .product(name: "MLXHuggingFace", package: mlxPackage),
                .product(name: "MLXLMCommon", package: mlxPackage),
                .product(name: "HuggingFace", package: huggingFacePackage),
                .product(name: "Tokenizers", package: transformersPackage),
            ],
            path: "Examples/SemanticSearchCore"
        ),
        // A thin runnable entry point over `SemanticSearchCore`.
        .executableTarget(
            name: "SemanticSearch",
            dependencies: [
                .target(name: "SemanticSearchCore"),
                .target(name: "ExamplesSupport"),
            ],
            path: "Examples/SemanticSearch"
        ),
    ]
)
