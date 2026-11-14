import FoundationModelsMetadataRegistry

/// Runs search configurations over the labeled intents, and measures them.
public enum BenchmarkRunner {
  /// The intent of the warm-up search. It is not a labeled intent, so the
  /// metrics do not read it.
  static let warmUpIntent = "warm up the models and the catalog embedding"

  /// The result of one timed search.
  struct TimedSearch {
    /// The ranked ids of the search, or the error that it threw.
    let result: Result<[String], any Error>

    /// The time that the search took.
    let duration: Duration

    /// The ranked ids, or no id when the search threw.
    var rankedIDs: [String] {
      (try? result.get()) ?? []
    }

    /// Tells if the search threw.
    var isFailure: Bool {
      if case .failure = result { true } else { false }
    }
  }

  /// Runs each configuration over `intents`, one configuration after the
  /// other, and gives one report row for each configuration, in order.
  ///
  /// For each configuration that can run, the runner makes one searcher over
  /// `catalog`. It does one warm-up search first, which loads the models and
  /// embeds the catalog, and records its time apart. Then it searches for
  /// each intent `repeats` times, and records the ranked ids and the time of
  /// each search. Each search uses `BenchmarkConfiguration.limit`. A search
  /// that throws counts as an empty result and as one error, and the run
  /// continues. A configuration that gives an unavailable reason gets a row
  /// with that reason, and the runner makes no searcher for it.
  ///
  /// Each search is one outcome, so the metrics of a kind are the means over
  /// all repeats.
  ///
  /// - Precondition: `intents` is not empty, and `repeats` is at least 1.
  /// - Parameters:
  ///   - configurations: the configurations to run.
  ///   - intents: the labeled intents to search for.
  ///   - catalog: the items that each searcher searches.
  ///   - repeats: how many times to search for each intent.
  /// - Returns: the report, whose recall cutoff is the search limit.
  public static func run(
    _ configurations: [BenchmarkConfiguration],
    intents: [LabeledIntent],
    catalog: [BenchmarkItem],
    repeats: Int,
  ) async -> BenchmarkReport {
    precondition(!intents.isEmpty, "a benchmark run needs at least one intent")
    precondition(repeats > 0, "a benchmark run needs at least one repeat")
    let rows = await configurations.sequentialMap { configuration in
      await row(of: configuration, intents: intents, catalog: catalog, repeats: repeats)
    }
    return BenchmarkReport(recallCutoff: BenchmarkConfiguration.limit, rows: rows)
  }

  /// Runs one configuration.
  ///
  /// - Parameters:
  ///   - configuration: the configuration to run.
  ///   - intents: the labeled intents to search for. The list is not empty.
  ///   - catalog: the items that the searcher searches.
  ///   - repeats: how many times to search for each intent. It is at least 1.
  /// - Returns: the row of the configuration.
  static func row(
    of configuration: BenchmarkConfiguration,
    intents: [LabeledIntent],
    catalog: [BenchmarkItem],
    repeats: Int,
  ) async -> BenchmarkReport.Row {
    if let reason = configuration.unavailableReason() {
      return BenchmarkReport.Row(name: configuration.name, status: .unavailable(reason: reason))
    }
    let searcher = configuration.makeSearcher(catalog)
    let warmUp = await timedSearch(searcher, intent: warmUpIntent)
    let repeatedIntents = Array(repeating: intents, count: repeats).joined()
    let searches = await repeatedIntents.sequentialMap { intent in
      (intent: intent, search: await timedSearch(searcher, intent: intent.text))
    }
    let errorCount = ([warmUp] + searches.map(\.search)).filter(\.isFailure).count
    let measurement = BenchmarkReport.Measurement(
      outcomes: searches.map { intent, search in
        IntentOutcome(intent: intent, rankedIDs: search.rankedIDs, latency: search.duration)
      },
      firstSearch: warmUp.duration,
      errorCount: errorCount,
      recallCutoff: BenchmarkConfiguration.limit,
    )
    guard let measurement else {
      preconditionFailure("a run with intents and repeats has at least one outcome")
    }
    return BenchmarkReport.Row(name: configuration.name, status: .measured(measurement))
  }

  /// Searches for `intent` with `BenchmarkConfiguration.limit`, and measures
  /// the time of the search.
  ///
  /// - Parameters:
  ///   - searcher: the searcher to search with.
  ///   - intent: the text to search for.
  /// - Returns: the ranked ids or the error, and the time of the search.
  static func timedSearch(_ searcher: MetadataSearcher<BenchmarkItem>, intent: String) async
    -> TimedSearch
  {
    let clock = ContinuousClock()
    let start = clock.now
    let result: Result<[String], any Error>
    do {
      result = .success(
        try await searcher.search(intent: intent, limit: BenchmarkConfiguration.limit).map(\.id))
    } catch {
      result = .failure(error)
    }
    return TimedSearch(result: result, duration: start.duration(to: clock.now))
  }
}

extension Sequence {
  /// Transforms each element with an asynchronous function, one element
  /// after the other, in order.
  ///
  /// The benchmark measures the time of each search, so the searches must
  /// not run at the same time.
  ///
  /// - Parameter transform: the function to apply to each element.
  /// - Returns: the transformed elements, in the order of this sequence.
  func sequentialMap<Transformed>(
    _ transform: (Element) async -> Transformed
  ) async -> [Transformed] {
    var transformed: [Transformed] = []
    for element in self {
      transformed.append(await transform(element))
    }
    return transformed
  }
}
