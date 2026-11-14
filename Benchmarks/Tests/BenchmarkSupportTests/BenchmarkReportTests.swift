import Foundation
import Testing

@testable import BenchmarkSupport

/// The benchmark report: its JSON round trip and its markdown table.
@Suite("Benchmark report")
struct BenchmarkReportTests {
  /// The recall cutoff of the report in this suite.
  static let recallCutoff = 5

  /// The latency of each outcome in this suite.
  static let latency = Duration.milliseconds(12)

  /// The duration of the first search of each configuration in this suite.
  static let firstSearch = Duration.milliseconds(340)

  /// One outcome of each kind that a row can summarize.
  static let outcomes = [
    IntentOutcome(
      intent: LabeledIntent(text: "make a branch", relevantIDs: ["gitBranch"], kind: .lexical),
      rankedIDs: ["gitBranch", "gardenPruneBranch"],
      latency: latency,
    ),
    IntentOutcome(
      intent: LabeledIntent(text: "capital of Peru", relevantIDs: [], kind: .offTopic),
      rankedIDs: [],
      latency: latency,
    ),
  ]

  /// The names of the configurations in the report, one row for each.
  static let configurationNames = ["retrieval", "decision | tier"]

  /// The error count of each measured row in this suite.
  static let errorCount = 4

  /// The reason of the unavailable row of `makeReportWithUnavailableRow()`.
  static let unavailableReason = "the model is not ready"

  /// The measurement of `outcomes`.
  static func makeMeasurement() throws -> BenchmarkReport.Measurement {
    try #require(
      BenchmarkReport.Measurement(
        outcomes: outcomes,
        firstSearch: firstSearch,
        errorCount: errorCount,
        recallCutoff: recallCutoff,
      ),
    )
  }

  /// A report with one measured row for each name in `configurationNames`.
  static func makeReport() throws -> BenchmarkReport {
    let measurement = try makeMeasurement()
    let rows = configurationNames.map { name in
      BenchmarkReport.Row(name: name, status: .measured(measurement))
    }
    return BenchmarkReport(recallCutoff: recallCutoff, rows: rows)
  }

  /// A report with one measured row and one unavailable row.
  static func makeReportWithUnavailableRow() throws -> BenchmarkReport {
    BenchmarkReport(
      recallCutoff: recallCutoff,
      rows: [
        BenchmarkReport.Row(name: "measured", status: .measured(try makeMeasurement())),
        BenchmarkReport.Row(name: "unavailable", status: .unavailable(reason: unavailableReason)),
      ],
    )
  }

  /// The JSON encoding decodes to an equal report.
  @Test("the JSON encoding round trips")
  func jsonEncodingRoundTrips() throws {
    let report = try Self.makeReport()
    let decoded = try BenchmarkReport.decoded(from: report.jsonData())
    #expect(decoded == report)
  }

  /// The table holds one header line, one separator line, and one line for
  /// each configuration.
  @Test("the markdown table has one row for each configuration")
  func markdownTableHasOneRowForEachConfiguration() throws {
    let headerLineCount = 2
    let lines = try Self.makeReport().markdownTable().split(separator: "\n")
    #expect(lines.count == headerLineCount + Self.configurationNames.count)
  }

  /// Each table line has the same count of cells as the header, also when a
  /// configuration name holds a pipe.
  @Test("each line of the markdown table has the same count of cells as the header")
  func eachLineOfTheMarkdownTableHasTheSameCountOfCellsAsTheHeader() throws {
    let lines = try Self.makeReport().markdownTable().split(separator: "\n")
    let cellCounts = Set(lines.map(BenchmarkReportTests.unescapedPipeCount(in:)))
    #expect(cellCounts.count == 1)
  }

  /// A measurement gets the p50 and p95 of its outcome latencies.
  @Test("a measurement holds the latency percentiles of its outcomes")
  func measurementHoldsTheLatencyPercentilesOfItsOutcomes() throws {
    let measurement = try Self.makeMeasurement()
    #expect([measurement.p50, measurement.p95] == [Self.latency, Self.latency])
  }

  /// A measurement with no outcome has no percentile, so it cannot be made.
  @Test("a measurement with no outcome cannot be made")
  func measurementWithNoOutcomeCannotBeMade() {
    let measurement = BenchmarkReport.Measurement(
      outcomes: [],
      firstSearch: Self.firstSearch,
      errorCount: 0,
      recallCutoff: Self.recallCutoff,
    )
    #expect(measurement == nil)
  }

  /// The JSON encoding of an unavailable row decodes to an equal report.
  @Test("the JSON encoding of an unavailable row round trips")
  func jsonEncodingOfAnUnavailableRowRoundTrips() throws {
    let report = try Self.makeReportWithUnavailableRow()
    let decoded = try BenchmarkReport.decoded(from: report.jsonData())
    #expect(decoded == report)
  }

  /// The table line of a measured row shows its error count.
  @Test("the markdown table shows the error count of a measured row")
  func markdownTableShowsTheErrorCountOfAMeasuredRow() throws {
    let measuredLine = try #require(
      try Self.makeReportWithUnavailableRow().markdownTable().split(separator: "\n").dropFirst(2)
        .first)
    #expect(measuredLine.contains("| \(Self.errorCount) |"))
  }

  /// The table line of an unavailable row shows its reason.
  @Test("the markdown table shows the reason of an unavailable row")
  func markdownTableShowsTheReasonOfAnUnavailableRow() throws {
    let unavailableLine = try #require(
      try Self.makeReportWithUnavailableRow().markdownTable().split(separator: "\n").last)
    #expect(unavailableLine.contains(Self.unavailableReason))
  }

  /// An unavailable row has a line with the same count of cells as the
  /// header.
  @Test("an unavailable row has the same count of cells as the header")
  func unavailableRowHasTheSameCountOfCellsAsTheHeader() throws {
    let lines = try Self.makeReportWithUnavailableRow().markdownTable().split(separator: "\n")
    let cellCounts = Set(lines.map(BenchmarkReportTests.unescapedPipeCount(in:)))
    #expect(cellCounts.count == 1)
  }

  /// A new folder in the temporary folder, with a nested folder in it.
  /// Neither folder exists yet.
  ///
  /// - Returns: the outer folder, to remove, and the nested folder, to write
  ///   to.
  static func makeNestedDirectory() -> (outer: URL, nested: URL) {
    let outer = FileManager.default.temporaryDirectory
      .appending(path: "BenchmarkReportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    return (outer, outer.appending(path: "nested", directoryHint: .isDirectory))
  }

  /// Writing a report to a folder that does not exist makes the folder, and
  /// a JSON file that decodes to the report.
  @Test("writing a report makes a JSON file of the report")
  func writingAReportMakesAJSONFileOfTheReport() throws {
    let directories = Self.makeNestedDirectory()
    defer { try? FileManager.default.removeItem(at: directories.outer) }
    let report = try Self.makeReport()

    try report.write(toDirectory: directories.nested)

    let json = try Data(
      contentsOf: directories.nested.appending(path: BenchmarkReport.jsonFileName))
    #expect(try BenchmarkReport.decoded(from: json) == report)
  }

  /// Writing a report to a folder that does not exist makes the folder, and
  /// a markdown file that holds the table of the report.
  @Test("writing a report makes a markdown file of the table")
  func writingAReportMakesAMarkdownFileOfTheTable() throws {
    let directories = Self.makeNestedDirectory()
    defer { try? FileManager.default.removeItem(at: directories.outer) }
    let report = try Self.makeReport()

    try report.write(toDirectory: directories.nested)

    let markdown = try String(
      contentsOf: directories.nested.appending(path: BenchmarkReport.markdownFileName),
      encoding: .utf8,
    )
    #expect(markdown == report.markdownTable())
  }

  /// Counts the pipes in `line` that a backslash does not escape.
  ///
  /// - Parameter line: one line of a markdown table.
  /// - Returns: the count of the pipes that separate cells.
  static func unescapedPipeCount(in line: Substring) -> Int {
    zip(line, [" "] + line).filter { character, previous in
      character == "|" && previous != "\\"
    }.count
  }
}
