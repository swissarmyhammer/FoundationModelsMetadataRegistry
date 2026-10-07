import MetricsTestKit
import TelemetryTestSupport
import Testing

@testable import FoundationModelsMetadataRegistry

/// Tests for the metrics of the registry (the OpenTelemetry design of
/// 2026-09-28, part C): one search duration for each search, one rank
/// duration for each call to a ranker, and the catalog size gauge.
///
/// Each test runs inside `TelemetryCapture.run(forbidding:)`, with the query
/// text and the content of each item as forbidden strings. Thus each test
/// also proves rule 4 ("no content") for the metrics that it reads. Each test
/// makes its searchers inside the capture, because the capture binds its
/// metrics factory to the task of the test, and a metric keeps the factory of
/// the time that it was made. No test here bootstraps the logging system or
/// the metrics system.
///
/// The tests never check a duration value. They check only that each timer
/// holds the expected count of values, and that no value is negative, so the
/// tests are stable on a slow machine.
@Suite("Registry metrics")
struct RegistryMetricsTests {
  /// The fixtures of the tracing tests: the catalogs, the query, the
  /// forbidden strings and the scripted selection model.
  typealias Fixtures = RegistryTracingTests
  typealias MetricName = RegistryTelemetry.MetricName
  typealias Dimension = RegistryTelemetry.DimensionKey

  /// The dimensions of one timer value, as a key-to-value map.
  typealias Dimensions = [String: String]

  /// The fixed set of values of each dimension key. A dimension key or a
  /// value outside this map breaks the "no content" rule.
  static let allowedDimensionValues: [String: Set<String>] = [
    Dimension.tier: ["retrieval", "selection", "none"],
    Dimension.outcome: ["success", "error"],
    Dimension.ranker: ["hybrid", "selection"],
  ]

  /// Returns the count of values of each timer named `label`, keyed by the
  /// dimensions of the timer. A timer with no value is left out.
  ///
  /// - Parameters:
  ///   - label: the name of the timers.
  ///   - context: the capture that holds the metrics.
  /// - Returns: the count of values for each dimension set.
  static func valueCounts(ofTimersNamed label: String, in context: TelemetryCapture.Context)
    -> [Dimensions: Int]
  {
    let timers = context.metricsFactory.timers.filter { $0.label == label && !$0.values.isEmpty }
    return Dictionary(
      timers.map { (Dimensions(uniqueKeysWithValues: $0.dimensions), $0.values.count) },
      uniquingKeysWith: +,
    )
  }

  /// Checks each metric of the registry in `context`: each dimension key
  /// and value is in ``allowedDimensionValues``, and no timer value is
  /// negative.
  ///
  /// - Parameter context: the capture that holds the metrics.
  static func expectFixedDimensionsAndNoNegativeDuration(in context: TelemetryCapture.Context) {
    let registryTimers = context.metricsFactory.timers.filter {
      $0.label.hasPrefix(RegistryTelemetry.namePrefix)
    }
    for timer in registryTimers {
      #expect(timer.values.allSatisfy { $0 >= 0 }, "a negative duration in \(timer.label)")
      for (key, value) in timer.dimensions {
        #expect(
          allowedDimensionValues[key]?.contains(value) == true, "\(key)=\(value) in \(timer.label)")
      }
    }
  }

  /// Returns each value of the catalog size gauge in `context`, in the
  /// order of the calls.
  ///
  /// - Parameter context: the capture that holds the metrics.
  /// - Returns: the recorded values.
  /// - Throws: when no catalog size gauge was made.
  static func catalogSizes(in context: TelemetryCapture.Context) throws -> [Double] {
    try context.metricsFactory.expectGauge(MetricName.catalogSize).values
  }

  // MARK: - Search and rank durations

  @Test
  func retrievalSearchRecordsOneSearchDurationAndOneHybridRankDuration() async throws {
    try await TelemetryCapture.run(forbidding: Fixtures.forbidden) { context in
      let searcher = MetadataSearcher(
        items: Fixtures.catalog, mode: .retrieval, onDiagnostic: { _ in })
      _ = try await searcher.search(intent: Fixtures.query, limit: Fixtures.searchLimit)

      let searches = Self.valueCounts(ofTimersNamed: MetricName.searchDuration, in: context)
      #expect(searches == [[Dimension.tier: "retrieval", Dimension.outcome: "success"]: 1])
      let ranks = Self.valueCounts(ofTimersNamed: MetricName.rankDuration, in: context)
      #expect(ranks == [[Dimension.ranker: "hybrid"]: 1])
      Self.expectFixedDimensionsAndNoNegativeDuration(in: context)
    }
  }

  @Test
  func retrievalSearchThatRanksNothingRecordsNoRankDuration() async throws {
    try await TelemetryCapture.run(forbidding: Fixtures.forbidden) { context in
      let searcher = MetadataSearcher(
        items: Fixtures.catalog, mode: .retrieval, onDiagnostic: { _ in })
      _ = try await searcher.search(intent: Fixtures.query, limit: 0)

      let searches = Self.valueCounts(ofTimersNamed: MetricName.searchDuration, in: context)
      #expect(searches == [[Dimension.tier: "retrieval", Dimension.outcome: "success"]: 1])
      #expect(Self.valueCounts(ofTimersNamed: MetricName.rankDuration, in: context).isEmpty)
    }
  }

  @Test
  func selectionSearchRecordsTheSelectionTierAndOneSelectionRankDuration() async throws {
    try await TelemetryCapture.run(forbidding: Fixtures.forbidden) { context in
      let searcher = MetadataSearcher(
        items: Fixtures.catalog,
        mode: .selection,
        selection: Fixtures.makeSelectionConfig(),
      )
      _ = try await searcher.search(intent: Fixtures.query, limit: Fixtures.searchLimit)

      let searches = Self.valueCounts(ofTimersNamed: MetricName.searchDuration, in: context)
      #expect(searches == [[Dimension.tier: "selection", Dimension.outcome: "success"]: 1])
      let ranks = Self.valueCounts(ofTimersNamed: MetricName.rankDuration, in: context)
      #expect(ranks == [[Dimension.ranker: "selection"]: 1])
      Self.expectFixedDimensionsAndNoNegativeDuration(in: context)
    }
  }

  @Test
  func autoSearchRecordsTheTierThatAnswered() async throws {
    try await TelemetryCapture.run(forbidding: Fixtures.forbidden) { context in
      let withTier = MetadataSearcher(
        items: Fixtures.catalog,
        mode: .auto,
        selection: Fixtures.makeSelectionConfig(),
      )
      let withoutTier = MetadataSearcher(
        items: Fixtures.catalog, mode: .auto, onDiagnostic: { _ in })
      _ = try await withTier.search(intent: Fixtures.query, limit: Fixtures.searchLimit)
      _ = try await withoutTier.search(intent: Fixtures.query, limit: Fixtures.searchLimit)

      let searches = Self.valueCounts(ofTimersNamed: MetricName.searchDuration, in: context)
      #expect(
        searches == [
          [Dimension.tier: "selection", Dimension.outcome: "success"]: 1,
          [Dimension.tier: "retrieval", Dimension.outcome: "success"]: 1,
        ])
      let ranks = Self.valueCounts(ofTimersNamed: MetricName.rankDuration, in: context)
      #expect(ranks == [[Dimension.ranker: "selection"]: 1, [Dimension.ranker: "hybrid"]: 1])
      Self.expectFixedDimensionsAndNoNegativeDuration(in: context)
    }
  }

  @Test
  func selectionSearchWithNoSelectionTierRecordsNoTierAndAnErrorAndNoRankDuration() async throws {
    try await TelemetryCapture.run(forbidding: Fixtures.forbidden) { context in
      let searcher = MetadataSearcher(items: Fixtures.catalog, mode: .selection)
      await #expect(throws: SelectionTierUnavailable.self) {
        try await searcher.search(intent: Fixtures.query, limit: Fixtures.searchLimit)
      }

      let searches = Self.valueCounts(ofTimersNamed: MetricName.searchDuration, in: context)
      #expect(searches == [[Dimension.tier: "none", Dimension.outcome: "error"]: 1])
      #expect(Self.valueCounts(ofTimersNamed: MetricName.rankDuration, in: context).isEmpty)
      Self.expectFixedDimensionsAndNoNegativeDuration(in: context)
    }
  }

  @Test
  func selectionSearchWhoseSessionThrowsRecordsTheSelectionTierAndAnError() async throws {
    try await TelemetryCapture.run(forbidding: Fixtures.forbidden) { context in
      let searcher = MetadataSearcher(
        items: Fixtures.catalog,
        mode: .selection,
        selection: SelectionConfig(model: ScriptedLanguageModel(answers: [.failure])),
      )
      await #expect(throws: (any Error).self) {
        try await searcher.search(intent: Fixtures.query, limit: Fixtures.searchLimit)
      }

      let searches = Self.valueCounts(ofTimersNamed: MetricName.searchDuration, in: context)
      #expect(searches == [[Dimension.tier: "selection", Dimension.outcome: "error"]: 1])
      let ranks = Self.valueCounts(ofTimersNamed: MetricName.rankDuration, in: context)
      #expect(ranks == [[Dimension.ranker: "selection"]: 1])
      Self.expectFixedDimensionsAndNoNegativeDuration(in: context)
    }
  }
}

/// The catalog size gauge.
extension RegistryMetricsTests {
  // MARK: - Catalog size

  @Test
  func eachInitializerRecordsTheCatalogSizeOneTime() async throws {
    try await TelemetryCapture.run(forbidding: Fixtures.forbidden) { context in
      _ = MetadataSearcher(items: Fixtures.catalog, mode: .retrieval, onDiagnostic: { _ in })
      _ = MetadataSearcher(
        items: Fixtures.catalog, mode: .retrieval, embedder: Fixtures.makeEmbedder())
      _ = MetadataSearcher(index: MetadataIndex(items: Fixtures.catalog), mode: .retrieval)

      let size = Double(Fixtures.catalog.count)
      let sizes = try Self.catalogSizes(in: context)
      #expect(sizes == [size, size, size])
    }
  }

  @Test
  func updateThatChangesTheCatalogRecordsTheNewCatalogSize() async throws {
    try await TelemetryCapture.run(forbidding: Fixtures.forbidden) { context in
      let searcher = MetadataSearcher(
        items: Fixtures.catalog, mode: .retrieval, onDiagnostic: { _ in })
      await searcher.update(items: Fixtures.reloadedCatalog)

      let sizes = try Self.catalogSizes(in: context)
      #expect(sizes == [Double(Fixtures.catalog.count), Double(Fixtures.reloadedCatalog.count)])
    }
  }

  @Test
  func updateWithIdenticalContentRecordsNoCatalogSize() async throws {
    try await TelemetryCapture.run(forbidding: Fixtures.forbidden) { context in
      // An embedded catalog: no entry waits for an embed, so an update
      // with the same content takes the hash-guarded no-op path.
      let searcher = await Fixtures.makeEmbeddedSearcher()
      await searcher.update(items: Fixtures.catalog)

      let sizes = try Self.catalogSizes(in: context)
      #expect(sizes == [Double(Fixtures.catalog.count)])
    }
  }
}
