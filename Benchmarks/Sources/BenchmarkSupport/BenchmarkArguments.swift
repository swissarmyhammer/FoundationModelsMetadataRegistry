import Foundation

/// The command line arguments of the `RankingBenchmark` executable.
///
///     RankingBenchmark --output <dir> [--configurations <name,...>] [--repeats <n>]
public struct BenchmarkArguments: Equatable, Sendable {
  /// The flag of the output folder. It is required.
  static let outputFlag = "--output"

  /// The flag of the comma-separated configuration names.
  static let configurationsFlag = "--configurations"

  /// The flag of the repeat count.
  static let repeatsFlag = "--repeats"

  /// The separator of the configuration names.
  static let nameSeparator: Character = ","

  /// The repeat count when there is no `--repeats`.
  public static let defaultRepeats = 3

  /// The lowest repeat count that a run accepts.
  static let lowestRepeats = 1

  /// The usage text, for an error message.
  public static let usage = """
    usage: RankingBenchmark \(outputFlag) <dir> \
    [\(configurationsFlag) <name,...>] [\(repeatsFlag) <n>]
    configurations: \(BenchmarkConfiguration.allNames.joined(separator: ", "))
    """

  /// The folder that the report files go to.
  public let outputDirectory: URL

  /// The configurations to run, in order.
  public let configurations: [BenchmarkConfiguration.Name]

  /// How many times to search for each intent.
  public let repeats: Int

  /// Makes the arguments from their values.
  ///
  /// - Parameters:
  ///   - outputDirectory: the folder that the report files go to.
  ///   - configurations: the configurations to run, in order.
  ///   - repeats: how many times to search for each intent.
  public init(
    outputDirectory: URL,
    configurations: [BenchmarkConfiguration.Name],
    repeats: Int,
  ) {
    self.outputDirectory = outputDirectory
    self.configurations = configurations
    self.repeats = repeats
  }

  /// Parses the command line arguments.
  ///
  /// Each flag takes the next argument as its value. When a flag occurs
  /// more than one time, the last value is used. Without
  /// `--configurations`, the run uses all the configurations. Without
  /// `--repeats`, the run uses `defaultRepeats`.
  ///
  /// - Parameter arguments: the arguments after the name of the executable.
  /// - Returns: the parsed arguments.
  /// - Throws: a `BenchmarkArgumentError` that names the first problem.
  public static func parse(_ arguments: [String]) throws(BenchmarkArgumentError)
    -> BenchmarkArguments
  {
    let values = try flagValues(of: arguments)
    guard let output = values[outputFlag] else { throw .missingOutput }
    return BenchmarkArguments(
      outputDirectory: URL(filePath: output, directoryHint: .isDirectory),
      configurations: try values[configurationsFlag].map(configurationNames(in:))
        ?? BenchmarkConfiguration.Name.allCases,
      repeats: try values[repeatsFlag].map(repeatCount(in:)) ?? defaultRepeats,
    )
  }

  /// Reads each flag and its value.
  ///
  /// - Parameter arguments: the arguments after the name of the executable.
  /// - Returns: the last value of each flag.
  /// - Throws: `BenchmarkArgumentError.unknownArgument` for an argument that
  ///   is not a known flag, and `BenchmarkArgumentError.missingValue` for a
  ///   flag with no value after it.
  static func flagValues(of arguments: [String]) throws(BenchmarkArgumentError) -> [String: String]
  {
    let knownFlags: Set = [outputFlag, configurationsFlag, repeatsFlag]
    var values: [String: String] = [:]
    var remaining = arguments[...]
    while let flag = remaining.popFirst() {
      guard knownFlags.contains(flag) else { throw .unknownArgument(flag) }
      guard let value = remaining.popFirst() else { throw .missingValue(flag: flag) }
      values[flag] = value
    }
    return values
  }

  /// Reads the configuration names of `--configurations`.
  ///
  /// - Parameter list: the comma-separated names.
  /// - Returns: the configurations, in the order of `list`.
  /// - Throws: `BenchmarkArgumentError.unknownConfiguration` for a name that
  ///   no configuration has.
  static func configurationNames(in list: String) throws(BenchmarkArgumentError)
    -> [BenchmarkConfiguration.Name]
  {
    try list.split(separator: nameSeparator).map { (name) throws(BenchmarkArgumentError) in
      guard let configuration = BenchmarkConfiguration.Name(rawValue: String(name)) else {
        throw .unknownConfiguration(String(name))
      }
      return configuration
    }
  }

  /// Reads the repeat count of `--repeats`.
  ///
  /// - Parameter text: the value of the flag.
  /// - Returns: the repeat count.
  /// - Throws: `BenchmarkArgumentError.invalidRepeats` when `text` is not an
  ///   integer of at least `lowestRepeats`.
  static func repeatCount(in text: String) throws(BenchmarkArgumentError) -> Int {
    guard let count = Int(text), count >= lowestRepeats else { throw .invalidRepeats(text) }
    return count
  }
}

/// A problem in the command line arguments of the `RankingBenchmark`
/// executable.
public enum BenchmarkArgumentError: Error, Equatable, CustomStringConvertible {
  /// There is no `--output` flag.
  case missingOutput
  /// A flag is the last argument, so it has no value.
  case missingValue(flag: String)
  /// A name in `--configurations` is not the name of a configuration.
  case unknownConfiguration(String)
  /// The value of `--repeats` is not a positive integer.
  case invalidRepeats(String)
  /// An argument is not a known flag.
  case unknownArgument(String)

  /// A message that tells the problem to the user.
  public var description: String {
    switch self {
    case .missingOutput:
      "the output folder is missing: give \(BenchmarkArguments.outputFlag) <dir>"
    case .missingValue(let flag):
      "the flag \(flag) has no value"
    case .unknownConfiguration(let name):
      "unknown configuration: \(name)"
    case .invalidRepeats(let text):
      "the repeat count must be a positive integer, not \(text)"
    case .unknownArgument(let argument):
      "unknown argument: \(argument)"
    }
  }
}
