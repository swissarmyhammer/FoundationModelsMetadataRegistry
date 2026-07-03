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

/// The SwiftPM manifest for FoundationModelsMetadataRegistry (plan.md §10).
///
/// A single library target over the FoundationModelsRouter sibling, plus a
/// Swift Testing unit test target. `Examples/` executable targets (§13) are
/// added by later tasks and are demos only, never a dependency of the
/// library.
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
        .package(path: "../\(routerDependencyName)")
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
            dependencies: [.target(name: packageName)],
            path: "Tests/\(packageName)Tests"
        ),
    ]
)
