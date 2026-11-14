// The entry point of the ranking benchmark.
//
// It parses the arguments, runs each selected configuration over the labeled
// fixture, writes `report.json` and `report.md` to the output folder, and
// writes the markdown table to standard output.

import BenchmarkSupport
import Foundation

let arguments: BenchmarkArguments
do {
  arguments = try BenchmarkArguments.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
  FileHandle.standardError.write(Data("error: \(error)\n\(BenchmarkArguments.usage)\n".utf8))
  exit(EX_USAGE)
}

let report = await BenchmarkRunner.run(
  arguments.configurations.map(Configurations.make),
  intents: BenchmarkIntents.all,
  catalog: BenchmarkCatalog.items,
  repeats: arguments.repeats,
)

do {
  try report.write(toDirectory: arguments.outputDirectory)
} catch {
  FileHandle.standardError.write(Data("error: cannot write the report: \(error)\n".utf8))
  exit(EXIT_FAILURE)
}
FileHandle.standardOutput.write(Data(report.markdownTable().utf8))
