import Foundation
import Testing

@testable import BenchmarkSupport

/// The command line arguments of the `RankingBenchmark` executable.
@Suite("Argument parsing")
struct ArgumentParsingTests {
  /// The output folder that the tests give.
  static let outputPath = "/tmp/ranking-benchmark"

  /// The arguments with only the required `--output`.
  static let outputOnly = ["--output", outputPath]

  /// The seven configuration names, in the order of a run.
  @Test("the configuration names are the seven configurations of the benchmark")
  func configurationNamesAreTheSevenConfigurationsOfTheBenchmark() {
    #expect(
      BenchmarkConfiguration.allNames == [
        "retrieval-keyword", "retrieval-semantic", "selection-qwen3-4b", "selection-apple",
        "decision-qwen3-4b", "decision-decider-4b", "decision-h2o-lightning-4b",
      ])
  }

  /// Each argument goes to its value.
  @Test("each argument is parsed")
  func eachArgumentIsParsed() throws {
    let arguments = try BenchmarkArguments.parse([
      "--output", Self.outputPath,
      "--configurations", "decision-qwen3-4b,retrieval-keyword",
      "--repeats", "7",
    ])
    #expect(
      arguments
        == BenchmarkArguments(
          outputDirectory: URL(filePath: Self.outputPath, directoryHint: .isDirectory),
          configurations: [.decisionQwen, .retrievalKeyword],
          repeats: 7,
        ))
  }

  /// With no `--configurations`, the run uses each configuration.
  @Test("the default configurations are all the configurations")
  func defaultConfigurationsAreAllTheConfigurations() throws {
    let arguments = try BenchmarkArguments.parse(Self.outputOnly)
    #expect(arguments.configurations.map(\.rawValue) == BenchmarkConfiguration.allNames)
  }

  /// With no `--repeats`, the run searches each intent three times.
  @Test("the default repeat count is three")
  func defaultRepeatCountIsThree() throws {
    let defaultRepeats = 3
    #expect(try BenchmarkArguments.parse(Self.outputOnly).repeats == defaultRepeats)
  }

  /// A configuration name that the benchmark does not know is an error.
  @Test("an unknown configuration name is an error")
  func unknownConfigurationNameIsAnError() {
    #expect(throws: BenchmarkArgumentError.unknownConfiguration("retrieval-magic")) {
      try BenchmarkArguments.parse(Self.outputOnly + ["--configurations", "retrieval-magic"])
    }
  }

  /// `--output` is required.
  @Test("a missing output folder is an error")
  func missingOutputFolderIsAnError() {
    #expect(throws: BenchmarkArgumentError.missingOutput) {
      try BenchmarkArguments.parse(["--repeats", "2"])
    }
  }

  /// A flag at the end with no value is an error.
  @Test("a flag with no value is an error")
  func flagWithNoValueIsAnError() {
    #expect(throws: BenchmarkArgumentError.missingValue(flag: "--repeats")) {
      try BenchmarkArguments.parse(Self.outputOnly + ["--repeats"])
    }
  }

  /// A repeat count that is not a positive integer is an error.
  @Test("a repeat count that is not positive is an error", arguments: ["0", "-1", "three"])
  func repeatCountThatIsNotPositiveIsAnError(value: String) {
    #expect(throws: BenchmarkArgumentError.invalidRepeats(value)) {
      try BenchmarkArguments.parse(Self.outputOnly + ["--repeats", value])
    }
  }

  /// An argument that the benchmark does not know is an error.
  @Test("an unknown argument is an error")
  func unknownArgumentIsAnError() {
    #expect(throws: BenchmarkArgumentError.unknownArgument("--verbose")) {
      try BenchmarkArguments.parse(Self.outputOnly + ["--verbose"])
    }
  }
}
