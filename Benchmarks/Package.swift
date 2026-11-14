// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

/// The name of the package under measurement, of its library product, and of
/// the directory `..` holds.
private let registryPackageName = "FoundationModelsMetadataRegistry"

/// The name of the library target that holds the fixture, the metrics and the
/// report.
private let supportTargetName = "BenchmarkSupport"

/// SwiftPM manifest for the ranking benchmarks of the registry.
///
/// **Why this is a package of its own.** The root manifest does not name this
/// package, the same as `Examples/` and `IntegrationTests/`. Thus a bare
/// `swift test` at the root does not build or run it, and CI does not
/// download the models that a benchmark run loads. Use these commands:
///
///     swift build --package-path Benchmarks
///     swift test --package-path Benchmarks
///
/// **What `BenchmarkSupport` holds.** A labeled fixture (a catalog of items in
/// eight domains, and intents with their correct ids), the ranking metrics,
/// and the report that compares configurations. It uses only the public API
/// of the registry, and it loads no model. Its unit tests do not load a model
/// either.
let package = Package(
  name: "Benchmarks",
  // The same floor as the root package. A lower floor does not resolve
  // against it.
  platforms: [
    .macOS("27.0")
  ],
  dependencies: [
    .package(path: "..")
  ],
  targets: [
    .target(
      name: supportTargetName,
      dependencies: [
        .product(name: registryPackageName, package: registryPackageName)
      ],
    ),
    .testTarget(
      name: "\(supportTargetName)Tests",
      dependencies: [
        .target(name: supportTargetName),
        .product(name: registryPackageName, package: registryPackageName),
      ],
    ),
  ],
)
