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

/// The `mlx-swift-lm` fork's package name.
///
/// The same remote dependency FoundationModelsRouter itself declares;
/// re-declared here with the identical URL/branch so SwiftPM's dependency
/// resolution unifies the two into a single resolved checkout, never a
/// duplicate, so `SemanticSearchCore` can import `MLXHuggingFace`'s
/// `#hubDownloader()` / `#huggingFaceTokenizerLoader()` macros to build a
/// live `Router` — the only place this package touches MLX directly
/// (plan.md §13).
let mlxPackage = "mlx-swift-lm"

/// The Hugging Face Hub client package name.
///
/// `SemanticSearchCore` links this to supply `LiveModelLoader`'s
/// `Downloader`, mirroring FoundationModelsRouter's own gated integration
/// suite and its `Examples/MultiModelGeneration` demo (`hubProducts` in that
/// package's manifest). Needed only by `SemanticSearchCore`'s live-Router
/// path; the library target never imports it.
let huggingFacePackage = "swift-huggingface"

/// The Hugging Face Transformers package name.
///
/// Its `Tokenizers` product supplies `LiveModelLoader`'s `TokenizerLoader`
/// alongside `huggingFacePackage`'s `Downloader`. Needed only by
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
                // `BigCatalogCore`/`HotReloadCore`'s GPU-free paths (plan.md §13
                // M8) -- retrieval timing over a synthetic ~10^3-entry catalog,
                // and `update(items:)` burst/index-rebuild -- both exercised
                // directly by `ExamplesSmokeTests`, exactly like
                // `CatalogSearchCore`/`SemanticSearchCore` above. `LibrarianCore`
                // isn't linked here: its only GPU-free behavior is the catalog
                // print `swift run Librarian` exercises directly; nothing in it
                // needs a dedicated unit test.
                .target(name: "BigCatalogCore"),
                .target(name: "HotReloadCore"),
                // The gated `Integration/RouterIntegrationTests.swift` suite (plan.md
                // M7) builds a real, live `Router` + `LiveModelLoader` directly —
                // mirroring FoundationModelsRouter's own gated
                // `FoundationModelsRouterIntegrationTests` target and Multitool's
                // `FoundationModelsMultitoolIntegrationTests` — so this test target
                // needs the same product dependencies those targets link, even though
                // every other test file here never imports them.
                .product(name: routerDependencyName, package: routerDependencyName),
                .product(name: "MLXHuggingFace", package: mlxPackage),
                .product(name: "MLXLMCommon", package: mlxPackage),
                .product(name: "HuggingFace", package: huggingFacePackage),
                .product(name: "Tokenizers", package: transformersPackage),
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
        // Shared live-Router profile resolution (plan.md §13 M8):
        // `SemanticSearchCore`, `LibrarianCore`, `BigCatalogCore`, and
        // `HotReloadCore` each resolve the identical tiny `mlx-community`
        // model triple through a live `Router` + `LiveModelLoader` for their
        // gated (real-model) path — extracted here rather than each target
        // carrying its own near-identical copy. Deliberately its own target
        // (not folded into `ExamplesSupport`) so `CatalogSearchCore`/
        // `CatalogSearch` — which stay GPU-free and never need Router/MLX at
        // all — don't gain these dependencies transitively through
        // `ExamplesSupport`.
        .target(
            name: "LiveRouterSupport",
            dependencies: [
                .product(name: routerDependencyName, package: routerDependencyName),
                .product(name: "MLXHuggingFace", package: mlxPackage),
                .product(name: "MLXLMCommon", package: mlxPackage),
                .product(name: "HuggingFace", package: huggingFacePackage),
                .product(name: "Tokenizers", package: transformersPackage),
            ],
            path: "Examples/LiveRouterSupport"
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
                .target(name: "LiveRouterSupport"),
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
        // `Librarian`'s entry logic (plan.md §13 M8): `.selection` mode
        // end-to-end on a Router model -- a cached root session seeded with
        // the whole (under-budget) catalog, `fork()`ed per query, ids-only
        // xgrammar-constrained output, verbatim blocks out. The model run is
        // gated behind `METADATA_REGISTRY_INTEGRATION_TESTS` (the same
        // opt-in env var as the gated integration suite); without it, the
        // example prints its catalog and exits 0. Links the same MLX +
        // Hugging Face products as `SemanticSearchCore` to construct a live
        // `Router` + `LiveModelLoader`.
        .target(
            name: "LibrarianCore",
            dependencies: [
                .target(name: packageName),
                .target(name: "ExamplesSupport"),
                .target(name: "LiveRouterSupport"),
                .product(name: routerDependencyName, package: routerDependencyName),
                .product(name: "MLXHuggingFace", package: mlxPackage),
                .product(name: "MLXLMCommon", package: mlxPackage),
                .product(name: "HuggingFace", package: huggingFacePackage),
                .product(name: "Tokenizers", package: transformersPackage),
            ],
            path: "Examples/LibrarianCore"
        ),
        // A thin runnable entry point over `LibrarianCore`.
        .executableTarget(
            name: "Librarian",
            dependencies: [
                .target(name: "LibrarianCore"),
                .target(name: "ExamplesSupport"),
            ],
            path: "Examples/Librarian"
        ),
        // `BigCatalog`'s entry logic (plan.md §13 M8): the headroom story --
        // a synthetic ~10^3-entry catalog (ids = URIs), in-memory retrieval
        // with printed timings, GPU-free. Only when
        // `METADATA_REGISTRY_INTEGRATION_TESTS` is set does it also run a
        // selection query that overflows the assembled-prefix budget -> top-M
        // candidates -> a fresh one-off session, printing the `.retrievalCut`
        // diagnostic. A plain library (not the executable itself) so
        // `ExamplesSmokeTests` can invoke the GPU-free retrieval-timing path
        // directly.
        .target(
            name: "BigCatalogCore",
            dependencies: [
                .target(name: packageName),
                .target(name: "ExamplesSupport"),
                .target(name: "LiveRouterSupport"),
                .product(name: routerDependencyName, package: routerDependencyName),
                .product(name: "MLXHuggingFace", package: mlxPackage),
                .product(name: "MLXLMCommon", package: mlxPackage),
                .product(name: "HuggingFace", package: huggingFacePackage),
                .product(name: "Tokenizers", package: transformersPackage),
            ],
            path: "Examples/BigCatalogCore"
        ),
        // A thin runnable entry point over `BigCatalogCore`.
        .executableTarget(
            name: "BigCatalog",
            dependencies: [
                .target(name: "BigCatalogCore"),
                .target(name: "ExamplesSupport"),
            ],
            path: "Examples/BigCatalog"
        ),
        // `HotReload`'s entry logic (plan.md §13 M8): `update(items:)` bursts
        // (MCP-style add/remove) -- immediate keyword searchability, embed
        // catch-up progress via `.embedCatchUp`, and the selection tier's
        // cached root + grammar rebuild on a real catalog change, all
        // GPU-free against a deterministic embedder. Only when
        // `METADATA_REGISTRY_INTEGRATION_TESTS` is set does it also run the
        // same burst against a real, live-Router-resolved embedder. A plain
        // library (not the executable itself) so `ExamplesSmokeTests` can
        // invoke the GPU-free index-rebuild path directly.
        .target(
            name: "HotReloadCore",
            dependencies: [
                .target(name: packageName),
                .target(name: "ExamplesSupport"),
                .target(name: "LiveRouterSupport"),
                .product(name: routerDependencyName, package: routerDependencyName),
                .product(name: "MLXHuggingFace", package: mlxPackage),
                .product(name: "MLXLMCommon", package: mlxPackage),
                .product(name: "HuggingFace", package: huggingFacePackage),
                .product(name: "Tokenizers", package: transformersPackage),
            ],
            path: "Examples/HotReloadCore"
        ),
        // A thin runnable entry point over `HotReloadCore`.
        .executableTarget(
            name: "HotReload",
            dependencies: [
                .target(name: "HotReloadCore"),
                .target(name: "ExamplesSupport"),
            ],
            path: "Examples/HotReload"
        ),
    ]
)
