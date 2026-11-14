import Foundation

/// The result of one benchmark run: one row for each search configuration.
///
/// Encode it as JSON to keep it, and render it as a markdown table to read
/// it.
public struct BenchmarkReport: Codable, Equatable, Sendable {
  /// The result of one search configuration.
  public struct Row: Codable, Equatable, Sendable {
    /// What the run of a configuration gave: a measurement, or the reason
    /// that the configuration did not run.
    public enum Status: Codable, Equatable, Sendable {
      /// The configuration ran, and this is its measurement.
      case measured(Measurement)
      /// The configuration did not run, for example because its model is
      /// not available on this computer.
      case unavailable(reason: String)
    }

    /// The name of the configuration.
    public let name: String

    /// What the run of the configuration gave.
    public let status: Status

    /// Makes one row.
    ///
    /// - Parameters:
    ///   - name: the name of the configuration.
    ///   - status: what the run of the configuration gave.
    public init(name: String, status: Status) {
      self.name = name
      self.status = status
    }

    /// The measurement of this row, or `nil` when the configuration did not
    /// run.
    var measurement: Measurement? {
      if case .measured(let measurement) = status { measurement } else { nil }
    }

    /// The reason that the configuration did not run, or `nil` when it ran.
    var unavailableReason: String? {
      if case .unavailable(let reason) = status { reason } else { nil }
    }
  }

  /// The measurement of one configuration that ran.
  public struct Measurement: Codable, Equatable, Sendable {
    /// The summary of each kind of intent that the configuration searched
    /// for.
    public let kinds: [KindSummary]

    /// The 50th percentile of the search latencies. The warm-up search is
    /// not in it.
    public let p50: Duration

    /// The 95th percentile of the search latencies. The warm-up search is
    /// not in it.
    public let p95: Duration

    /// The time of the warm-up search, which is the first search. It
    /// includes the time to load the models and to embed the catalog.
    public let firstSearch: Duration

    /// The count of the searches that threw an error, the warm-up search
    /// included. A search that threw counts as an empty result in the
    /// metrics.
    public let errorCount: Int

    /// Makes one measurement from its values.
    ///
    /// - Parameters:
    ///   - kinds: the summary of each kind of intent.
    ///   - p50: the 50th percentile of the search latencies.
    ///   - p95: the 95th percentile of the search latencies.
    ///   - firstSearch: the time of the warm-up search.
    ///   - errorCount: the count of the searches that threw an error.
    public init(
      kinds: [KindSummary],
      p50: Duration,
      p95: Duration,
      firstSearch: Duration,
      errorCount: Int,
    ) {
      self.kinds = kinds
      self.p50 = p50
      self.p95 = p95
      self.firstSearch = firstSearch
      self.errorCount = errorCount
    }

    /// Makes one measurement from the outcomes of a configuration.
    ///
    /// - Parameters:
    ///   - outcomes: the outcome of each search, without the warm-up search.
    ///   - firstSearch: the time of the warm-up search.
    ///   - errorCount: the count of the searches that threw an error.
    ///   - recallCutoff: the count of ranked ids that recall reads. Use the
    ///     `recallCutoff` of the report that holds this measurement.
    /// - Returns: the measurement, or `nil` when `outcomes` is empty,
    ///   because an empty list has no latency percentile.
    public init?(
      outcomes: [IntentOutcome],
      firstSearch: Duration,
      errorCount: Int,
      recallCutoff: Int,
    ) {
      let latencies = outcomes.map(\.latency)
      guard let p50 = RankingMetrics.p50(of: latencies),
        let p95 = RankingMetrics.p95(of: latencies)
      else { return nil }
      self.init(
        kinds: RankingMetrics.summaries(of: outcomes, recallCutoff: recallCutoff),
        p50: p50,
        p95: p95,
        firstSearch: firstSearch,
        errorCount: errorCount,
      )
    }

    /// The metrics of `kind` in this measurement.
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

  /// The name of the file that `write(toDirectory:)` writes the JSON to.
  public static let jsonFileName = "report.json"

  /// The name of the file that `write(toDirectory:)` writes the markdown
  /// table to.
  public static let markdownFileName = "report.md"

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

  /// Writes the JSON of this report to `jsonFileName`, and its markdown
  /// table to `markdownFileName`, in `directory`. Makes `directory` and its
  /// parent folders when they do not exist, and replaces the files when they
  /// exist.
  ///
  /// - Parameter directory: the folder to write to.
  /// - Throws: an `EncodingError` when a value cannot be encoded, or the
  ///   error of the file system when a folder or a file cannot be written.
  public func write(toDirectory directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try jsonData().write(to: directory.appending(path: Self.jsonFileName), options: .atomic)
    try Data(markdownTable().utf8).write(
      to: directory.appending(path: Self.markdownFileName), options: .atomic)
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
  /// - Returns: the name column, the metric columns of each kind, the
  ///   latency and error columns, and the column of the unavailable reason.
  static func columns(recallCutoff: Int) -> [Column] {
    let nameColumn = Column(header: "Configuration") { escapedCell($0.name) }
    let kindColumns = LabeledIntent.Kind.allCases.flatMap { kind in
      columns(of: kind, recallCutoff: recallCutoff)
    }
    let measurementColumns = [
      measurementColumn(header: "p50 ms") { millisecondsCell($0.p50) },
      measurementColumn(header: "p95 ms") { millisecondsCell($0.p95) },
      measurementColumn(header: "first search ms") { millisecondsCell($0.firstSearch) },
      measurementColumn(header: "errors") { String($0.errorCount) },
    ]
    let reasonColumn = Column(header: "unavailable reason") { row in
      row.unavailableReason.map(escapedCell) ?? missingCell
    }
    return [nameColumn] + kindColumns + measurementColumns + [reasonColumn]
  }

  /// A column that shows one value of the measurement of a row.
  ///
  /// - Parameters:
  ///   - header: the header text.
  ///   - cell: the cell text of one measurement.
  /// - Returns: the column. A row with no measurement shows `missingCell`.
  static func measurementColumn(
    header: String,
    cell: @escaping (Measurement) -> String,
  ) -> Column {
    Column(header: header) { row in row.measurement.map(cell) ?? missingCell }
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
      guard case .answerable(let metrics) = row.measurement?.metrics(of: kind) else {
        return missingCell
      }
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
      guard case .offTopic(let metrics) = row.measurement?.metrics(of: .offTopic) else {
        return missingCell
      }
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
