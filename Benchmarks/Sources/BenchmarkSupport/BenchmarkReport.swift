import Foundation

/// The result of one benchmark run: one row for each search configuration.
///
/// Encode it as JSON to keep it, and render it as a markdown table to read
/// it.
public struct BenchmarkReport: Codable, Equatable, Sendable {
  /// The result of one search configuration.
  public struct Row: Codable, Equatable, Sendable {
    /// The name of the configuration.
    public let name: String

    /// The summary of each kind of intent that the configuration searched
    /// for.
    public let kinds: [KindSummary]

    /// The 50th percentile of the search latencies.
    public let p50: Duration

    /// The 95th percentile of the search latencies.
    public let p95: Duration

    /// The time of the first search, which includes the time to prepare the
    /// index.
    public let firstSearch: Duration

    /// Makes one row from its values.
    ///
    /// - Parameters:
    ///   - name: the name of the configuration.
    ///   - kinds: the summary of each kind of intent.
    ///   - p50: the 50th percentile of the search latencies.
    ///   - p95: the 95th percentile of the search latencies.
    ///   - firstSearch: the time of the first search.
    public init(
      name: String,
      kinds: [KindSummary],
      p50: Duration,
      p95: Duration,
      firstSearch: Duration,
    ) {
      self.name = name
      self.kinds = kinds
      self.p50 = p50
      self.p95 = p95
      self.firstSearch = firstSearch
    }

    /// Makes one row from the outcomes of a configuration.
    ///
    /// - Parameters:
    ///   - name: the name of the configuration.
    ///   - outcomes: the outcome of each search.
    ///   - firstSearch: the time of the first search.
    ///   - recallCutoff: the count of ranked ids that recall reads. Use the
    ///     `recallCutoff` of the report that holds this row.
    /// - Returns: the row, or `nil` when `outcomes` is empty, because an
    ///   empty list has no latency percentile.
    public init?(
      name: String,
      outcomes: [IntentOutcome],
      firstSearch: Duration,
      recallCutoff: Int,
    ) {
      let latencies = outcomes.map(\.latency)
      guard let p50 = RankingMetrics.p50(of: latencies),
        let p95 = RankingMetrics.p95(of: latencies)
      else { return nil }
      self.init(
        name: name,
        kinds: RankingMetrics.summaries(of: outcomes, recallCutoff: recallCutoff),
        p50: p50,
        p95: p95,
        firstSearch: firstSearch,
      )
    }

    /// The metrics of `kind` in this row.
    ///
    /// - Parameter kind: the kind to find.
    /// - Returns: the metrics, or `nil` when the configuration searched for
    ///   no intent of `kind`.
    func metrics(of kind: LabeledIntent.Kind) -> KindMetrics? {
      kinds.first { $0.kind == kind }?.metrics
    }
  }

  /// One column of the markdown table: its header and the cell of each row.
  struct Column {
    /// The header text of the column.
    let header: String

    /// The cell text of the column for one row.
    let cell: (Row) -> String
  }

  /// The count of ranked ids that recall reads, for every row.
  public let recallCutoff: Int

  /// One row for each configuration, in the order of the run.
  public let rows: [Row]

  /// The format of a metric cell: a fraction with two decimals.
  static let metricFormat = "%.2f"

  /// The format of a latency cell: milliseconds with one decimal.
  static let millisecondsFormat = "%.1f"

  /// The text of a cell that has no value.
  static let missingCell = "-"

  /// Makes a report.
  ///
  /// - Parameters:
  ///   - recallCutoff: the count of ranked ids that recall reads. Make each
  ///     row with the same cutoff.
  ///   - rows: one row for each configuration.
  public init(recallCutoff: Int, rows: [Row]) {
    self.recallCutoff = recallCutoff
    self.rows = rows
  }

  /// Encodes this report as JSON, with sorted keys so that two runs give a
  /// stable diff.
  ///
  /// - Returns: the UTF-8 JSON of this report.
  /// - Throws: an `EncodingError` when a value cannot be encoded.
  public func jsonData() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(self)
  }

  /// Decodes a report from its JSON.
  ///
  /// - Parameter data: the UTF-8 JSON that `jsonData()` wrote.
  /// - Returns: the decoded report.
  /// - Throws: a `DecodingError` when `data` is not a report.
  public static func decoded(from data: Data) throws -> BenchmarkReport {
    try JSONDecoder().decode(BenchmarkReport.self, from: data)
  }

  /// Renders this report as a markdown table: a header line, a separator
  /// line, and one line for each row.
  ///
  /// - Returns: the table, with a newline after each line.
  public func markdownTable() -> String {
    let columns = Self.columns(recallCutoff: recallCutoff)
    let header = Self.tableLine(columns.map(\.header))
    let separator = Self.tableLine(columns.map { _ in "---" })
    let body = rows.map { row in Self.tableLine(columns.map { $0.cell(row) }) }
    return ([header, separator] + body).map { $0 + "\n" }.joined()
  }

  /// The columns of the markdown table.
  ///
  /// - Parameter recallCutoff: the cutoff that the recall headers name.
  /// - Returns: the name column, the metric columns of each kind, and the
  ///   latency columns.
  static func columns(recallCutoff: Int) -> [Column] {
    let nameColumn = Column(header: "Configuration") { escapedCell($0.name) }
    let kindColumns = LabeledIntent.Kind.allCases.flatMap { kind in
      columns(of: kind, recallCutoff: recallCutoff)
    }
    let latencyColumns = [
      Column(header: "p50 ms") { millisecondsCell($0.p50) },
      Column(header: "p95 ms") { millisecondsCell($0.p95) },
      Column(header: "first search ms") { millisecondsCell($0.firstSearch) },
    ]
    return [nameColumn] + kindColumns + latencyColumns
  }

  /// The metric columns of one kind.
  ///
  /// - Parameters:
  ///   - kind: the kind of intent.
  ///   - recallCutoff: the cutoff that the recall header names.
  /// - Returns: hit@1, recall and reciprocal rank for a kind with an answer,
  ///   or the empty rate and the false positives for the off-topic kind.
  static func columns(of kind: LabeledIntent.Kind, recallCutoff: Int) -> [Column] {
    let name = kind.rawValue
    switch kind {
    case .lexical, .paraphrase, .multiStep:
      return [
        answerableColumn(header: "\(name) hit@1", kind: kind, value: \.hitAt1),
        answerableColumn(
          header: "\(name) recall@\(recallCutoff)", kind: kind, value: \.recallAtCutoff),
        answerableColumn(header: "\(name) MRR", kind: kind, value: \.meanReciprocalRank),
      ]
    case .offTopic:
      return [
        offTopicColumn(header: "\(name) empty rate", value: \.emptyRate),
        offTopicColumn(header: "\(name) false positives", value: \.meanFalsePositiveCount),
      ]
    }
  }

  /// A column that shows one metric of a kind with an answer.
  ///
  /// - Parameters:
  ///   - header: the header text.
  ///   - kind: the kind of intent.
  ///   - value: the metric to show.
  /// - Returns: the column. A row with no metrics of `kind` shows `missingCell`.
  static func answerableColumn(
    header: String,
    kind: LabeledIntent.Kind,
    value: KeyPath<AnswerableMetrics, Double>,
  ) -> Column {
    Column(header: header) { row in
      guard case .answerable(let metrics) = row.metrics(of: kind) else { return missingCell }
      return metricCell(metrics[keyPath: value])
    }
  }

  /// A column that shows one metric of the off-topic kind.
  ///
  /// - Parameters:
  ///   - header: the header text.
  ///   - value: the metric to show.
  /// - Returns: the column. A row with no off-topic metrics shows
  ///   `missingCell`.
  static func offTopicColumn(header: String, value: KeyPath<OffTopicMetrics, Double>) -> Column {
    Column(header: header) { row in
      guard case .offTopic(let metrics) = row.metrics(of: .offTopic) else { return missingCell }
      return metricCell(metrics[keyPath: value])
    }
  }

  /// Joins cells into one markdown table line.
  ///
  /// - Parameter cells: the cell texts, which hold no unescaped pipe.
  /// - Returns: the line, with a pipe before, between and after the cells.
  static func tableLine(_ cells: [String]) -> String {
    "| " + cells.joined(separator: " | ") + " |"
  }

  /// Escapes the pipes in `text`, so that a pipe does not end the cell.
  ///
  /// - Parameter text: the cell text.
  /// - Returns: `text` with each `|` written as `\|`.
  static func escapedCell(_ text: String) -> String {
    text.replacingOccurrences(of: "|", with: "\\|")
  }

  /// Formats a metric with two decimals.
  ///
  /// - Parameter value: the metric.
  /// - Returns: the formatted metric.
  static func metricCell(_ value: Double) -> String {
    String(format: metricFormat, value)
  }

  /// Formats a duration in milliseconds with one decimal.
  ///
  /// - Parameter duration: the duration.
  /// - Returns: the formatted milliseconds.
  static func millisecondsCell(_ duration: Duration) -> String {
    String(format: millisecondsFormat, duration / .milliseconds(1))
  }
}
