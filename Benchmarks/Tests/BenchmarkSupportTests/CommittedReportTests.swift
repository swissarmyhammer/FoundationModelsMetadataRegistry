import Foundation
import Testing

@testable import BenchmarkSupport

/// The newest report in `Benchmarks/Results`: the committed result of a real
/// run of the `RankingBenchmark` executable.
///
/// Each run writes its report to a folder named with its date
/// (`YYYY-MM-DD`), so the newest folder sorts last by name.
@Suite("Committed report")
struct CommittedReportTests {
  /// The errors of the search for the newest committed report.
  enum CommittedReportError: Error {
    /// `Benchmarks/Results` holds no folder with a report.
    case noReport(in: URL)
  }

  /// The `Benchmarks/Results` folder of this checkout, found from the path
  /// of this source file.
  static let resultsDirectory = URL(filePath: #filePath)
    .deletingLastPathComponent()  // BenchmarkSupportTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // Benchmarks
    .appending(path: "Results", directoryHint: .isDirectory)

  /// Finds the `report.json` of the newest run folder in
  /// `resultsDirectory`.
  ///
  /// - Returns: the URL of the newest report.
  /// - Throws: `CommittedReportError.noReport` when no run folder holds a
  ///   report, or the error of the file system when the folder cannot be
  ///   read.
  static func newestReportURL() throws -> URL {
    let runDirectories = try FileManager.default.contentsOfDirectory(
      at: resultsDirectory, includingPropertiesForKeys: nil)
    let reports = runDirectories
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
      .map { $0.appending(path: BenchmarkReport.jsonFileName) }
      .filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    guard let newest = reports.last else {
      throw CommittedReportError.noReport(in: resultsDirectory)
    }
    return newest
  }

  /// Decodes the newest committed report.
  ///
  /// - Returns: the report.
  /// - Throws: the error of `newestReportURL()`, the error of the file
  ///   system, or a `DecodingError` when the file is not a report.
  static func newestReport() throws -> BenchmarkReport {
    try BenchmarkReport.decoded(from: Data(contentsOf: newestReportURL()))
  }

  /// Tells if `row` holds metrics or a reason why it did not run.
  ///
  /// - Parameter row: the row of one configuration.
  /// - Returns: `true` when the row has the metrics of at least one kind of
  ///   intent, or a reason that is not empty.
  static func hasMetricsOrReason(_ row: BenchmarkReport.Row) -> Bool {
    switch row.status {
    case .measured(let measurement):
      !measurement.kinds.isEmpty
    case .unavailable(let reason):
      !reason.isEmpty
    }
  }

  /// The newest report has one row for each configuration name, in the
  /// order of a run.
  @Test("the newest report has one row for each configuration")
  func newestReportHasOneRowForEachConfiguration() throws {
    let names = try Self.newestReport().rows.map(\.name)
    #expect(names == BenchmarkConfiguration.allNames)
  }

  /// Each row of the newest report has metrics, or a reason why the
  /// configuration did not run.
  @Test("each row of the newest report has metrics or a reason")
  func eachRowOfTheNewestReportHasMetricsOrAReason() throws {
    let rows = try Self.newestReport().rows
    #expect(rows.allSatisfy(Self.hasMetricsOrReason))
  }
}
