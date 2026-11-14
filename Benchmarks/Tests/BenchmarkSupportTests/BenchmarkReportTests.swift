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

  /// A report with one row for each name in `configurationNames`.
  static func makeReport() throws -> BenchmarkReport {
    let rows = try configurationNames.map { name in
      try #require(
        BenchmarkReport.Row(
          name: name,
          outcomes: outcomes,
          firstSearch: firstSearch,
          recallCutoff: recallCutoff,
        ),
      )
    }
    return BenchmarkReport(recallCutoff: recallCutoff, rows: rows)
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

  /// A row gets the p50 and p95 of its outcome latencies.
  @Test("a row holds the latency percentiles of its outcomes")
  func rowHoldsTheLatencyPercentilesOfItsOutcomes() throws {
    let row = try #require(try Self.makeReport().rows.first)
    #expect([row.p50, row.p95] == [Self.latency, Self.latency])
  }

  /// A row with no outcome has no percentile, so it cannot be made.
  @Test("a row with no outcome cannot be made")
  func rowWithNoOutcomeCannotBeMade() {
    let row = BenchmarkReport.Row(
      name: "empty",
      outcomes: [],
      firstSearch: Self.firstSearch,
      recallCutoff: Self.recallCutoff,
    )
    #expect(row == nil)
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
