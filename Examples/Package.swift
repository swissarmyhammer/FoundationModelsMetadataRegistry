// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// The runnable examples of FoundationModelsMetadataRegistry.
//
// This is a separate package, and the root manifest does not name it. The
// examples depend on the library and on FoundationModelsExtras only. The
// examples that embed use `exampleEmbedder` of ExamplesSupport, a
// `PooledEmbedder` of FoundationModelsExtras, which loads an MLX embedding
// model from the Hugging Face hub through `ModelPool.shared`. The examples
// that select use `exampleSelectionModel` of ExamplesSupport, a `PooledModel`
// of FoundationModelsExtras, which loads an MLX language model in the same way.
//
//     swift run --package-path Examples CatalogSearch
//     swift run --package-path Examples SemanticSearch
//     swift run --package-path Examples Librarian
//     swift run --package-path Examples BigCatalog
//     swift run --package-path Examples HotReload

let registryPackage = "FoundationModelsMetadataRegistry"
let extrasPackage = "FoundationModelsExtras"

/// The name of the library target that the examples share.
let examplesSupportName = "ExamplesSupport"

/// The names of the example executables. Each one is a target in `<name>/`.
let exampleNames = ["CatalogSearch", "SemanticSearch", "Librarian", "BigCatalog", "HotReload"]

let package = Package(
    name: "Examples",
    // The same floor as the root package.
    platforms: [
        .macOS("27.0"),
    ],
    dependencies: [
        .package(path: ".."),
        // The model pool (`ModelPool`, `ModelRef`, `PooledEmbedder`,
        // `PooledModel`). The same URL as in the root manifest, so the two
        // resolve as one package.
        .package(url: "git@github.com:swissarmyhammer/\(extrasPackage).git", branch: "main"),
    ],
    targets: [
        // The catalog item type, the git-command catalog, the match
        // formatter, the report writer, and the two models that the
        // examples share.
        .target(
            name: examplesSupportName,
            dependencies: [
                .product(name: registryPackage, package: registryPackage),
                .product(name: extrasPackage, package: extrasPackage),
            ],
            path: examplesSupportName,
        ),
    ] + exampleNames.map { name in
        .executableTarget(
            name: name,
            dependencies: [
                .product(name: registryPackage, package: registryPackage),
                .product(name: extrasPackage, package: extrasPackage),
                .target(name: examplesSupportName),
            ],
            path: name,
        )
    },
)
