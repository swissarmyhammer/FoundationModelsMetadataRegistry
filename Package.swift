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
/// Wired as a remote dependency (`main` branch) the same way
/// `../FoundationModelsMultitool/Package.swift` does, rather than a local
/// path dependency, so this package's CI can use the family's shared
/// `swift-ci.yaml` reusable workflow (which only checks out the calling
/// repo). Router supplies `RoutedLLM`/`RoutedSession` (selection),
/// `RoutedEmbedder` (cosine), and `Grammar` (xgrammar id enums) to the
/// production conformers (plan.md §10); the core — catalog, signals, RRF,
/// both seams — compiles and unit-tests without exercising Router at runtime
/// (fakes conform to the seams).
let routerDependencyName = "FoundationModelsRouter"

/// The name of the FoundationModelsRanker dependency package.
///
/// The shared search/ranking primitives library this package's ported
/// copies were extracted into (plan.md decision #9). Supplies `BM25`,
/// `BM25Corpus`, `Trigram`, `Tokenizer`, `RRF`, `Hit`, `Signals`,
/// `TextEmbedding`, and `RoutedEmbedderAdapter`, re-exported to this
/// package's consumers via `FoundationModelsRankerReexport.swift`. Wired as a remote
/// dependency (`main` branch) rather than a local path dependency, for the
/// same CI reason as `routerDependencyName` above. FoundationModelsRanker itself depends
/// on FoundationModelsRouter `main`, so SwiftPM unifies it with the
/// existing pin.
let foundationModelsRankerPackage = "FoundationModelsRanker"

/// The `mlx-swift-lm` fork's package name.
///
/// The same remote dependency FoundationModelsRouter itself declares;
/// re-declared here with the identical URL/branch so SwiftPM's dependency
/// resolution unifies the two into a single resolved checkout, never a
/// duplicate.
///
/// No target of this package names an MLX product any more: the live-Router
/// path the `Examples/` demos once carried is gone, and the nested
/// `IntegrationTests/` package declares its own MLX dependency for the
/// real-model suite. Only the `dependencies:` entry below survives, and a
/// later change removes it.
let mlxPackage = "mlx-swift-lm"

/// The Hugging Face Hub client package name.
///
/// Supplied `LiveModelLoader`'s `Downloader` while the `Examples/` demos
/// resolved a live `Router`. No target of this package names its `HuggingFace`
/// product any more — the real-model suite in the nested `IntegrationTests/`
/// package declares its own — so only the `dependencies:` entry below
/// survives, and a later change removes it.
let huggingFacePackage = "swift-huggingface"

/// The Hugging Face Transformers package name.
///
/// Its `Tokenizers` product supplied `LiveModelLoader`'s `TokenizerLoader`
/// alongside `huggingFacePackage`'s `Downloader`, on the same removed
/// live-Router path. No target of this package names it any more; only the
/// `dependencies:` entry below survives, and a later change removes it —
/// though it also anchors the swift-jinja pin the test target keeps alive.
let transformersPackage = "swift-transformers"

/// The GitHub organization URL base the swissarmyhammer-family dependencies
/// (`routerDependencyName`, `foundationModelsRankerPackage`, `mlxPackage`)
/// resolve under — extracted so the org lives in one place instead of three
/// dependency entries that could silently drift.
let swissArmyHammerOrg = "git@github.com:swissarmyhammer/"

/// The GitHub organization URL base the Hugging Face dependencies
/// (`huggingFacePackage`, `transformersPackage`, swift-jinja) resolve
/// under — extracted for the same single-source-of-truth reason as
/// `swissArmyHammerOrg`.
let huggingFaceOrg = "https://github.com/huggingface/"

/// The name of the shared `Examples/ExamplesSupport` library target.
///
/// Referenced by `exampleDependencies(on:)` — which every `Examples/` target's
/// dependency list goes through — by the test target, and by the target's own
/// declaration; extracted here so all three share one source of truth rather
/// than three string literals that could silently drift.
let examplesSupportName = "ExamplesSupport"

/// The dependency list every `Examples/` target carries: the one library
/// target it is written against, plus `ExamplesSupport` for the shared
/// fixtures, the deterministic embedder, and the match formatter.
///
/// Both helpers below spelled this same two-entry list out, differing only in
/// the library they name — a `*Core` target depends on the main library, and
/// an executable depends on its own `*Core` — so it lives here instead, and
/// the rule that an `Examples/` target reaches for nothing else has one home.
///
/// - Parameter libraryName: the library target this `Examples/` target is
///   written against.
/// - Returns: the dependency list.
func exampleDependencies(on libraryName: String) -> [Target.Dependency] {
    [
        .target(name: libraryName),
        .target(name: examplesSupportName),
    ]
}

/// Builds an `Examples/` executable target: a thin runnable entry point that
/// depends only on its own `*Core` library target plus `ExamplesSupport`,
/// rooted at `Examples/<name>`.
///
/// `CatalogSearch`, `SemanticSearch`, `Librarian`, `BigCatalog`, and
/// `HotReload` each declared this identical shape verbatim, differing only
/// in `name`/`coreName` — extracted here so adding the next example's
/// executable target is one call instead of a fifth copy of the boilerplate.
///
/// - Parameters:
///   - name: the executable target's name, and the `Examples/` subdirectory
///     it lives in.
///   - coreName: the name of the `*Core` library target this executable is a
///     thin entry point over.
/// - Returns: the configured executable target.
func exampleExecutableTarget(name: String, coreName: String) -> Target {
    .executableTarget(
        name: name,
        dependencies: exampleDependencies(on: coreName),
        path: "Examples/\(name)"
    )
}

/// Builds an `Examples/<name>` `*Core` library target: an example's entry
/// logic as a plain library, depending on the main library target plus
/// `ExamplesSupport` and nothing else, rooted at `Examples/<name>`.
///
/// Every core now has the GPU-free, Router-free shape `CatalogSearchCore`
/// always had. The four that once resolved a real embedder or session through
/// a live `Router` do so no longer — the demos run against `ExamplesSupport`'s
/// deterministic embedder and scripted `DemoAgentSession`, and the real-model
/// story lives in the nested `IntegrationTests/` package. So no core links
/// MLX or Hugging Face, and no core needs a Router product.
///
/// `CatalogSearchCore`, `SemanticSearchCore`, `LibrarianCore`,
/// `BigCatalogCore`, and `HotReloadCore` each declared this identical shape
/// verbatim, differing only in `name` — extracted here so adding the next
/// example's `*Core` target is one call instead of a sixth copy of the
/// boilerplate.
///
/// - Parameter name: the `*Core` target's name, and the `Examples/`
///   subdirectory it lives in.
/// - Returns: the configured library target.
func exampleCoreTarget(name: String) -> Target {
    .target(
        name: name,
        dependencies: exampleDependencies(on: packageName),
        path: "Examples/\(name)"
    )
}

/// The SwiftPM manifest for FoundationModelsMetadataRegistry (plan.md §10).
///
/// A single library target over the FoundationModelsRanker sibling, a Swift
/// Testing unit test target, and the `Examples/` executable targets (§13):
/// `CatalogSearch` (keyword-only) and `SemanticSearch` (`ExamplesSupport`'s
/// deterministic embedder joining the cosine signal, with a `--no-embedder`
/// flag for the degraded path) — demos only, never a dependency of the
/// library, and every one of them GPU-free. Each example's entry logic lives
/// in its own `*Core` library target (`CatalogSearchCore`,
/// `SemanticSearchCore`) rather than directly in
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
        ),
        // The real-model integration suite lives in the nested
        // `IntegrationTests/` package, which depends on this package by a
        // path. That suite drives `runSemanticSearch(query:embedder:onDiagnostic:)`
        // over the `gitCommands` fixture catalog, and a package can only
        // import the products of its dependencies — so `SemanticSearchCore`
        // is a product here, not only a target.
        .library(
            name: "SemanticSearchCore",
            targets: ["SemanticSearchCore"]
        ),
    ],
    dependencies: [
        .package(url: "\(swissArmyHammerOrg)\(routerDependencyName).git", branch: "main"),
        .package(url: "\(swissArmyHammerOrg)\(foundationModelsRankerPackage).git", branch: "main"),
        .package(url: "\(swissArmyHammerOrg)\(mlxPackage).git", branch: "stable"),
        .package(url: "\(huggingFaceOrg)\(huggingFacePackage)", from: "0.9.0"),
        .package(url: "\(huggingFaceOrg)\(transformersPackage)", from: "1.3.0"),
        // Pinned below swift-jinja 2.4.0: that release changed `Value.object`
        // to key on `ObjectKey` instead of `String`, which the latest tagged
        // swift-transformers (1.3.3, still HEAD as of this pin) never
        // adopted -- `Sources/Hub/Config.swift` fails to compile against
        // 2.4.0. transformersPackage only constrains jinja to `from: "2.0.0"`,
        // so without this upper bound `swift package update` silently drifts
        // onto the broken release.
        .package(url: "\(huggingFaceOrg)swift-jinja.git", "2.0.0"..<"2.4.0"),
    ],
    targets: [
        .target(
            name: packageName,
            dependencies: [
                .product(name: foundationModelsRankerPackage, package: foundationModelsRankerPackage),
            ],
            path: "Sources/\(packageName)"
        ),
        .testTarget(
            name: "\(packageName)Tests",
            dependencies: [
                .target(name: packageName),
                .target(name: examplesSupportName),
                .target(name: "CatalogSearchCore"),
                .target(name: "SemanticSearchCore"),
                // `BigCatalogCore`/`HotReloadCore`/`LibrarianCore`'s GPU-free
                // paths (plan.md §13 M8) -- retrieval timing over a synthetic
                // ~10^3-entry catalog, `update(items:)` burst/index-rebuild,
                // and the `.selection` tier driven through a scripted
                // `DemoAgentSession` -- all exercised directly by
                // `ExamplesSmokeTests`/`OverBudgetTests`, exactly like
                // `CatalogSearchCore`/`SemanticSearchCore` above.
                .target(name: "BigCatalogCore"),
                .target(name: "HotReloadCore"),
                .target(name: "LibrarianCore"),
                // No target links `Tokenizers` any more, so this entry is now
                // the only thing that marks the root-level swift-jinja pin
                // (the `"2.0.0"..<"2.4.0"` upper bound above, which exists
                // only to keep `swift package update` off the release that
                // breaks swift-transformers) as used, so SwiftPM stops
                // warning that the dependency is unused by any target.
                //
                // This target holds the unit tests, and only the unit tests.
                // The real-model integration suite lives in the nested
                // `IntegrationTests/` package, so a bare `swift test` at the
                // root cannot reach it (the org test contract in
                // swissarmyhammer/workflows' README).
                .product(name: "Jinja", package: "swift-jinja"),
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
            name: examplesSupportName,
            dependencies: [.target(name: packageName)],
            path: "Examples/\(examplesSupportName)"
        ),
        // `CatalogSearch`'s entry logic (plan.md §13 M1): fixture items
        // conformed to `SearchableMetadata`, a keyword-only
        // `MetadataSearcher(mode: .retrieval)` — no embedder, no model — one
        // query, `Match`es with their per-signal `Signals`. A plain library
        // (not the executable itself) so `ExamplesSmokeTests` can invoke it
        // directly.
        exampleCoreTarget(name: "CatalogSearchCore"),
        // The ~30-line hello world (plan.md §13 M1): a thin runnable entry
        // point over `CatalogSearchCore`. Runs anywhere, GPU-free; `swift
        // build` keeps it compiling in CI.
        exampleExecutableTarget(name: "CatalogSearch", coreName: "CatalogSearchCore"),
        // `SemanticSearch`'s entry logic (plan.md §13 M2): `CatalogSearch`
        // plus a third signal — `ExamplesSupport`'s `DeterministicEmbedder`
        // embeds catalog and query, so cosine joins BM25 and trigram in RRF
        // fusion and shows up in each match's per-signal breakdown; the
        // `--no-embedder` path demonstrates the graceful keyword-only
        // degradation and its diagnostic. That embedder hashes text rather
        // than modelling meaning, which is what keeps the whole example free
        // of network and GPU. A plain library (not the executable itself) so
        // `ExamplesSmokeTests` can invoke both paths directly.
        exampleCoreTarget(name: "SemanticSearchCore"),
        // A thin runnable entry point over `SemanticSearchCore`.
        exampleExecutableTarget(name: "SemanticSearch", coreName: "SemanticSearchCore"),
        // `Librarian`'s entry logic (plan.md §13 M8): `.selection` mode
        // end-to-end -- a cached root session seeded with the whole
        // (under-budget) catalog, `fork()`ed per query, ids-only output,
        // verbatim blocks out. The session is `ExamplesSupport`'s scripted
        // `DemoAgentSession`, so the whole path is GPU-free and
        // `ExamplesSmokeTests` invokes it directly.
        exampleCoreTarget(name: "LibrarianCore"),
        // A thin runnable entry point over `LibrarianCore`.
        exampleExecutableTarget(name: "Librarian", coreName: "LibrarianCore"),
        // `BigCatalog`'s entry logic (plan.md §13 M8): the headroom story --
        // a synthetic ~10^3-entry catalog (ids = URIs), in-memory retrieval
        // with printed timings, then a selection query that overflows the
        // assembled-prefix budget -> top-M candidates -> a fresh one-off
        // session, printing the `.retrievalCut` diagnostic. Both paths are
        // GPU-free (the one-off session is `ExamplesSupport`'s scripted
        // `DemoAgentSession`). A plain library (not the executable itself) so
        // `ExamplesSmokeTests`/`OverBudgetTests` can invoke both directly.
        exampleCoreTarget(name: "BigCatalogCore"),
        // A thin runnable entry point over `BigCatalogCore`.
        exampleExecutableTarget(name: "BigCatalog", coreName: "BigCatalogCore"),
        // `HotReload`'s entry logic (plan.md §13 M8): `update(items:)` bursts
        // (MCP-style add/remove) -- immediate keyword searchability, embed
        // catch-up progress via `.embedCatchUp`, and the selection tier's
        // cached root + grammar rebuild on a real catalog change, all
        // GPU-free against `ExamplesSupport`'s deterministic embedder, which
        // is the only embedder this example ever builds. A plain library (not
        // the executable itself) so `ExamplesSmokeTests` can invoke the
        // index-rebuild path directly.
        exampleCoreTarget(name: "HotReloadCore"),
        // A thin runnable entry point over `HotReloadCore`.
        exampleExecutableTarget(name: "HotReload", coreName: "HotReloadCore"),
    ]
)
