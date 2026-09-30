// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// The runnable examples of FoundationModelsMetadataRegistry.
//
// This is a separate package, and the root manifest does not name it. The
// examples that embed load a real MLX embedding model through the
// `LiveModelLoader` of FoundationModelsRouter, and the library must not
// depend on the router or on MLX. Thus they are dependencies of this package
// only.
//
//     swift run --package-path Examples CatalogSearch
//     swift run --package-path Examples SemanticSearch
//     swift run --package-path Examples Librarian
//     swift run --package-path Examples BigCatalog
//     swift run --package-path Examples HotReload

let registryPackage = "FoundationModelsMetadataRegistry"
let extrasPackage = "FoundationModelsExtras"
let routerPackage = "FoundationModelsRouter"
let mlxPackage = "mlx-swift-lm"
let huggingFacePackage = "swift-huggingface"
let transformersPackage = "swift-transformers"

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
        // The model pool (`ModelPool`, `ModelRef`). The same URL as in the
        // root manifest, so the two resolve as one package.
        .package(url: "git@github.com:swissarmyhammer/\(extrasPackage).git", branch: "main"),
        // `LiveModelLoader`, which loads MLX models from the Hugging Face hub.
        .package(url: "git@github.com:swissarmyhammer/\(routerPackage).git", branch: "main"),
        // The packages of the `#hubDownloader()` and
        // `#huggingFaceTokenizerLoader()` macros. The same pins as
        // FoundationModelsRouter.
        .package(url: "https://github.com/swissarmyhammer/\(mlxPackage)", branch: "stable"),
        .package(url: "https://github.com/huggingface/\(huggingFacePackage)", from: "0.9.0"),
        .package(url: "https://github.com/huggingface/\(transformersPackage)", from: "1.3.0"),
    ],
    targets: [
        // The catalog item type, the git-command catalog, the match
        // formatter, the embedding model and its loader, and the selection
        // configuration on the on-device model that the examples share.
        .target(
            name: examplesSupportName,
            dependencies: [
                .product(name: registryPackage, package: registryPackage),
                .product(name: extrasPackage, package: extrasPackage),
                .product(name: routerPackage, package: routerPackage),
                .product(name: "MLXLMCommon", package: mlxPackage),
                .product(name: "MLXHuggingFace", package: mlxPackage),
                .product(name: "HuggingFace", package: huggingFacePackage),
                .product(name: "Tokenizers", package: transformersPackage),
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
