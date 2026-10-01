// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

/// The package, library product, and library target name.
///
/// Repeated identifiers are extracted to named constants so the manifest has
/// a single source of truth, the same convention the sibling
/// FoundationModelsRanker package's manifest follows.
let packageName = "FoundationModelsMetadataRegistry"

/// The name of the FoundationModelsRanker dependency package — one of the
/// two family packages this manifest declares (plan.md decision #16).
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
/// declares `dependencies: []`, so this entry adds no package to the
/// resolved graph other than itself.
let foundationModelsRankerPackage = "FoundationModelsRanker"

/// The name of the FoundationModelsExtras dependency package, and also the
/// name of its core product, the one product of it that the library and the
/// examples use (plan.md decision #16). The test target also uses its
/// `TelemetryTestSupport` product, for the content-safety test of the
/// OpenTelemetry design of 2026-09-28.
///
/// The core `FoundationModelsExtras` product holds the process-wide model
/// pool (`ModelPool`, `ModelRef`, `PooledEmbedder`, `GenerationQueue`). In one
/// process, each model loads one time only, and the router and the registry
/// share it. Use this core product only. Do not use `Operations`,
/// `OperationsCLI` or `Marketplace`: they compile swift-syntax,
/// swift-argument-parser or libgit2, and the registry must not compile them.
/// The core target compiles Stencil, Yams, ULID.swift and
/// swift-distributed-tracing, and the user accepted that cost on 2026-09-26.
///
/// Wired as a remote dependency (`main` branch), for the same reason as
/// `foundationModelsRankerPackage`.
let foundationModelsExtrasPackage = "FoundationModelsExtras"

/// The name of the swift-distributed-tracing package: the tracing API
/// (`Tracing`) of the OpenTelemetry design of 2026-09-28.
///
/// API only, no backend. A library of the family uses only the telemetry
/// APIs. It does not depend on swift-otel and it does not bootstrap a
/// backend: an executable of the family does that. Until an executable does,
/// `InstrumentationSystem.tracer` is a no-op tracer, so an application that
/// does not trace pays nothing.
///
/// The core `FoundationModelsExtras` product also depends on this package.
/// This manifest declares it too, because the library target links its
/// `Tracing` product directly. The floor is 1.5.0, because the unit tests
/// bind a tracer to a task with `withTracer(_:_:)`, which that release adds.
let swiftDistributedTracingPackage = "swift-distributed-tracing"

/// The name of the swift-log package: the logging API (`Logging`) of the
/// OpenTelemetry design of 2026-09-28.
///
/// API only, no backend: no target of this package calls
/// `LoggingSystem.bootstrap`. Until an executable of the family bootstraps
/// the backend, each logger of the library does nothing. The version floor
/// is the floor that the core `FoundationModelsExtras` target declares.
let swiftLogPackage = "swift-log"

/// The name of the swift-metrics package: the metrics API (`Metrics`) of the
/// OpenTelemetry design of 2026-09-28.
///
/// API only, no backend: no target of this package calls
/// `MetricsSystem.bootstrap`. Until an executable of the family bootstraps
/// the backend, each metric of the library does nothing. The version floor
/// is the floor that the core `FoundationModelsExtras` target declares.
let swiftMetricsPackage = "swift-metrics"

/// The GitHub organization URL base of the telemetry API packages
/// (`swiftDistributedTracingPackage`, `swiftLogPackage` and
/// `swiftMetricsPackage`).
let appleOrg = "https://github.com/apple/"

/// The GitHub organization URL base the swissarmyhammer-family dependencies
/// (`foundationModelsRankerPackage` and `foundationModelsExtrasPackage`)
/// resolve under — extracted so the org and the package name stay separate
/// names rather than one literal URL.
let swissArmyHammerOrg = "git@github.com:swissarmyhammer/"

/// The SwiftPM manifest for FoundationModelsMetadataRegistry.
///
/// A single library target over FoundationModelsRanker, the core
/// FoundationModelsExtras product and the `Tracing`, `Logging` and `Metrics`
/// APIs, and a Swift Testing unit test target. The runnable examples are in
/// the separate `Examples/` package, which this manifest does not name.
let package = Package(
  name: packageName,
  // Commit to macOS 27 / FoundationModels v2, no pre-27 fallback (plan.md
  // §10). FoundationModelsRanker and FoundationModelsExtras declare the same
  // floor, and the three telemetry API packages declare no higher floor, so
  // no dependency imposes a higher one.
  platforms: [
    .macOS("27.0")
  ],
  products: [
    .library(
      name: packageName,
      targets: [packageName],
    )
  ],
  dependencies: [
    .package(url: "\(swissArmyHammerOrg)\(foundationModelsRankerPackage).git", branch: "main"),
    .package(url: "\(swissArmyHammerOrg)\(foundationModelsExtrasPackage).git", branch: "main"),
    .package(url: "\(appleOrg)\(swiftDistributedTracingPackage).git", from: "1.5.0"),
    .package(url: "\(appleOrg)\(swiftLogPackage).git", from: "1.15.1"),
    .package(url: "\(appleOrg)\(swiftMetricsPackage).git", from: "2.11.0"),
  ],
  targets: [
    .target(
      name: packageName,
      dependencies: [
        .product(name: foundationModelsRankerPackage, package: foundationModelsRankerPackage),
        .product(name: foundationModelsExtrasPackage, package: foundationModelsExtrasPackage),
        // The telemetry APIs, and no backend: the spans, the logger
        // and the metrics that `RegistryTelemetry` names.
        .product(name: "Tracing", package: swiftDistributedTracingPackage),
        .product(name: "Logging", package: swiftLogPackage),
        .product(name: "Metrics", package: swiftMetricsPackage),
      ],
      path: "Sources/\(packageName)",
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
        // `RegistryTelemetryTests` binds an in-memory tracer to a
        // task and reads which tracer the library resolves.
        .product(name: "Tracing", package: swiftDistributedTracingPackage),
        .product(name: "InMemoryTracing", package: swiftDistributedTracingPackage),
        // `DiagnosticsTests` reads the level and the metadata of each
        // log record that `MetadataDiagnostic.log(_:)` writes.
        .product(name: "Logging", package: swiftLogPackage),
        // `RegistryMetricsTests` reads each timer and gauge that the
        // registry records into the `TestMetrics` factory of a
        // `TelemetryCapture`.
        .product(name: "MetricsTestKit", package: swiftMetricsPackage),
        // `TelemetryContentSafetyTests` runs each public entry point
        // inside a `TelemetryCapture`, which records an issue for each
        // span, log record or metric that holds content. Only this
        // test target may name this product.
        .product(name: "TelemetryTestSupport", package: foundationModelsExtrasPackage),
      ],
      path: "Tests/\(packageName)Tests",
    ),
  ],
)
