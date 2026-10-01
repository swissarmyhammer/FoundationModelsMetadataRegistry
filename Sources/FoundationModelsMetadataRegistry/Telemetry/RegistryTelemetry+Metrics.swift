import Metrics

/// The helpers that record the metrics of the registry.
///
/// Each helper makes its metric at the call, and no metric is kept in a
/// `static let`. A metric keeps the metrics factory of the time that it was
/// made, so a kept metric that was made before the host bootstrapped its
/// metrics backend would never reach that backend. Until a host bootstraps a
/// backend, each metric does nothing.
extension RegistryTelemetry {
  /// Records the duration of one `MetadataSearcher.search(intent:limit:)`
  /// call in the ``MetricName/searchDuration`` timer.
  ///
  /// - Parameters:
  ///   - duration: the time that the search took.
  ///   - tier: the tier that answered, or `nil` when no tier answered (the
  ///     ``noTier`` dimension value).
  ///   - outcome: whether the search returned or threw.
  static func recordSearchDuration(_ duration: Duration, tier: Tier?, outcome: Outcome) {
    let dimensions = [
      (DimensionKey.tier, tier?.rawValue ?? noTier),
      (DimensionKey.outcome, outcome.rawValue),
    ]
    Metrics.Timer(label: MetricName.searchDuration, dimensions: dimensions).record(
      duration: duration)
  }

  /// Makes the ``MetricName/rankDuration`` timer of one ranker.
  ///
  /// The caller measures its call to the ranker with the `measure` methods
  /// of the timer, so each call records one value, also a call that throws.
  ///
  /// - Parameter ranker: the ranker that the caller calls.
  /// - Returns: the timer, with the ``DimensionKey/ranker`` dimension.
  static func rankTimer(for ranker: Ranker) -> Metrics.Timer {
    Metrics.Timer(
      label: MetricName.rankDuration, dimensions: [(DimensionKey.ranker, ranker.rawValue)])
  }

  /// Records the count of entries in the catalog index of a searcher in
  /// the ``MetricName/catalogSize`` gauge.
  ///
  /// - Parameter count: the count of entries in the catalog index.
  static func recordCatalogSize(_ count: Int) {
    Gauge(label: MetricName.catalogSize).record(count)
  }
}
