// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

/// The package, library product, and library target name.
///
/// Repeated identifiers are extracted to named constants so the manifest has
/// a single source of truth, the same convention the sibling
/// FoundationModelsRanker package's manifest follows.
let packageName = "FoundationModelsMetadataRegistry"

/// The name of the FoundationModelsRanker dependency package — the only
/// package this manifest declares.
///
/// The shared search/ranking library this package's ported copies were
/// extracted into (plan.md decision #9). It supplies the retrieval
/// primitives (`BM25`, `BM25Corpus`, `Trigram`, `Tokenizer`, `RRF`, `Hit`,
/// `Signals`), the embedding seam (`TextEmbedding`), and the whole selection
/// tier (`SelectionTier`, `SelectionConfig`, `AgentSession`, and the types
/// they carry) — all re-exported to this package's consumers via
/// `FoundationModelsRankerReexport.swift`.
///
/// Wired as a remote dependency (`main` branch) rather than a local path
/// dependency: a `../FoundationModelsRanker` path resolves only where the
/// sibling repository is already checked out beside this one, so a fresh
/// clone and CI could not build it. FoundationModelsRanker's own manifest
/// declares `dependencies: []`, so this single entry is also the whole
/// resolved graph.
let foundationModelsRankerPackage = "FoundationModelsRanker"

/// The GitHub organization URL base the one swissarmyhammer-family
/// dependency (`foundationModelsRankerPackage`) resolves under — extracted so
/// the org and the package name stay separate names rather than one literal
/// URL.
let swissArmyHammerOrg = "git@github.com:swissarmyhammer/"

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
/// Every core is GPU-free. A core that needs a vector uses
/// `ExamplesSupport`'s `DeterministicEmbedder`, and a core that needs a
/// session uses its scripted `DemoAgentSession`; no core resolves a real
/// model. So no core links a model-loading product, and `swift build` needs
/// no GPU, no network, and no weights on disk.
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
    // Commit to macOS 27 / FoundationModels v2, no pre-27 fallback (plan.md
    // §10). FoundationModelsRanker declares the same floor, so the one
    // dependency imposes no higher one.
    platforms: [
        .macOS("27.0")
    ],
    products: [
        .library(
            name: packageName,
            targets: [packageName]
        ),
    ],
    dependencies: [
        .package(url: "\(swissArmyHammerOrg)\(foundationModelsRankerPackage).git", branch: "main"),
    ],
    targets: [
        .target(
            name: packageName,
            dependencies: [
                .product(name: foundationModelsRankerPackage, package: foundationModelsRankerPackage),
            ],
            path: "Sources/\(packageName)"
        ),
        // This target holds the unit tests, and only the unit tests. The
        // suite that needs a real model lives in the nested
        // `IntegrationTests/` package, which this manifest never names, so a
        // bare `swift test` at the root runs this target and nothing else
        // (the org test contract in swissarmyhammer/workflows' README). CI
        // reaches that package by its own path, through the shared
        // workflow's `integration-package-path` input.
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
