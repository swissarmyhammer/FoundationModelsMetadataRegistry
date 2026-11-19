// The cost gate of the registry at 100,000 items (D207).
//
// It makes a corpus of 100,000 chunks of 500 to 2,000 characters with
// vectors of 768 dimensions (the dimension of embeddinggemma-300m, from a
// fast stub embedder), builds a persistent searcher over it, and measures:
//
// - a `.retrieval` search with a limit of the catalog size (limit: 300 ms);
// - an update of 20 items with `update(upserting:removing:)`, with no model
//   embed (limit: 100 ms);
// - a start of a new searcher from the stored catalog (limit: 5 s);
// - the resident memory and the size of the stored catalog.
//
// It writes `scale-report.md` and `scale-report.json` to the output folder, and exits
// with a failure when a limit is not met.
//
//     swift run -c release --package-path Benchmarks ScaleBenchmark [output folder]

import Foundation
import FoundationModelsMetadataRegistry

/// The limits of the cost gate, in milliseconds.
enum Limits {
  static let search = 300.0
  static let update = 100.0
  static let start = 5_000.0
}

/// The resident memory of this process, in bytes.
func residentBytes() -> Int {
  var info = mach_task_basic_info()
  var count = mach_msg_type_number_t(
    MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
  let result = withUnsafeMutablePointer(to: &info) {
    $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
      task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
    }
  }
  return result == KERN_SUCCESS ? Int(info.resident_size) : 0
}

/// The time of `body`, in milliseconds.
func milliseconds(_ body: () async throws -> Void) async rethrows -> Double {
  let start = ContinuousClock.now
  try await body()
  let duration = start.duration(to: .now)
  return Double(duration.components.seconds) * 1_000
    + Double(duration.components.attoseconds) / 1e15
}

/// The size of the files of `folder`, in bytes.
func folderBytes(_ folder: URL) -> Int {
  let files =
    (try? FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
  return files.reduce(0) {
    $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
  }
}

/// The median of `values`.
func median(_ values: [Double]) -> Double {
  let sorted = values.sorted()
  return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
}

/// Prints `line` at once.
func log(_ line: String) {
  print(line)
  fflush(stdout)
}

// The child mode: start one searcher from the stored catalog in `folder`,
// in a fresh process, and print the time of the start, the resident memory,
// the count of items with a vector, and the count of texts embedded.
if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--start" {
  let folder = URL(fileURLWithPath: CommandLine.arguments[2])
  let modelID = CommandLine.arguments[3]
  let before = residentBytes()
  let embedder = HashEmbedder()
  var child: MetadataSearcher<ChunkItem>?
  let time = await milliseconds {
    child = await MetadataSearcher<ChunkItem>(
      persistence: CatalogPersistence(folder: folder, embeddingModelID: modelID),
      mode: .retrieval, embedder: embedder, onDiagnostic: { _ in })
  }
  let resident = residentBytes() - before
  var withVector = 0
  let searchTime = try await milliseconds {
    // A query with no word and no trigram ranks each item by cosine only:
    // each item with a vector.
    withVector = try await child!.search(intent: "a", limit: Int.max).count
  }
  print("\(time) \(resident) \(withVector) \(embedder.catalogTexts.value) \(searchTime)")
  exit(EXIT_SUCCESS)
}

let environment = ProcessInfo.processInfo.environment
let itemCount = Int(environment["SCALE_ITEMS"] ?? "") ?? 100_000
let outputFolder = URL(
  fileURLWithPath: CommandLine.arguments.dropFirst().first
    ?? "Benchmarks/Results/\(ISO8601DateFormatter().string(from: Date()).prefix(10))-scale")
let storeFolder = FileManager.default.temporaryDirectory
  .appendingPathComponent("ScaleBenchmark-\(UUID().uuidString)")
let persistence = CatalogPersistence(
  folder: storeFolder, embeddingModelID: "embeddinggemma-300m (stub)")

log("items: \(itemCount)")
var generator = SplitMix64(state: 42)
let items = ScaleCorpus.items(count: itemCount, seed: 42)
let averageLength = items.reduce(0) { $0 + $1.text.count } / max(1, items.count)
log("average text length: \(averageLength) characters")
let memoryBefore = residentBytes()

// MARK: - Build

var searcher: MetadataSearcher<ChunkItem>? = await MetadataSearcher<ChunkItem>(
  persistence: persistence, mode: .retrieval, embedder: HashEmbedder(), onDiagnostic: { _ in })
let buildMilliseconds = await milliseconds { await searcher!.update(items: items) }
log(String(format: "build, embed and merge of the catalog: %.0f ms", buildMilliseconds))
let firstSaveMilliseconds = await milliseconds { await searcher!.waitForSaves() }
log(String(format: "first snapshot (after the build): %.0f ms more", firstSaveMilliseconds))
let memoryAfterBuild = residentBytes()
log("resident memory after the build: \((memoryAfterBuild - memoryBefore) >> 20) MiB")
log("stored catalog: \(folderBytes(storeFolder) >> 20) MiB")

// MARK: - Search

var searchTimes: [(query: String, milliseconds: Double, matches: Int)] = []
for query in ScaleCorpus.queries(using: &generator) {
  var count = 0
  let time = try await milliseconds {
    count = try await searcher!.search(intent: query, limit: itemCount).count
  }
  searchTimes.append((query, time, count))
  log(String(format: "search %@: %.0f ms, %d matches", query, time, count))
}

// MARK: - Update of 20 items

var updateTimes: [Double] = []
var saveTimes: [Double] = []
for round in 0..<10 {
  // One turn: 19 new chunks of a session, and the changed item of an
  // existing session.
  var upserts = (0..<19).map { index in
    ChunkItem(id: "new-\(round)/\(index)", text: ScaleCorpus.text(using: &generator))
  }
  upserts.append(ChunkItem(id: items[round * 997].id, text: ScaleCorpus.text(using: &generator)))
  let time = await milliseconds { await searcher!.update(upserting: upserts) }
  updateTimes.append(time)
  saveTimes.append(await milliseconds { await searcher!.waitForSaves() })
  log(String(format: "update of 20 items: %.1f ms (save after it: %.0f ms)", time, saveTimes.last!))
}
let removal = (0..<20).map { "new-0/\($0 % 19)" } + [items[1].id]
let removeTime = await milliseconds { await searcher!.update(upserting: [], removing: removal) }
log(String(format: "removal of 20 items: %.1f ms", removeTime))
await searcher!.waitForSaves()
// 10 rounds add 19 new items each; the removal removes 19 of them and one
// item of the corpus.
let expectedCount = itemCount + 10 * 19 - 20
searcher = nil

// MARK: - Start

// The start runs in a fresh process, as an app launch does, so that its
// time and its memory do not include the build of this process.
let child = Process()
child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
child.arguments = ["--start", storeFolder.path, persistence.embeddingModelID]
let pipe = Pipe()
child.standardOutput = pipe
child.standardError = FileHandle.nullDevice
try child.run()
let childOutput = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
child.waitUntilExit()
let fields = childOutput.split(separator: "\n").last.map { $0.split(separator: " ") } ?? []
guard fields.count == 5 else {
  log("error: the start process printed: \(childOutput)")
  try? FileManager.default.removeItem(at: storeFolder)
  exit(EXIT_FAILURE)
}
let startMilliseconds = Double(fields[0]) ?? .infinity
let restoredResident = Int(fields[1]) ?? 0
let restoredCount = Int(fields[2]) ?? 0
let restoredPending = Int(fields[3]) ?? -1
let restoredSearch = Double(fields[4]) ?? 0
log(String(format: "start from the stored catalog: %.0f ms", startMilliseconds))
log("resident memory after the start: \(restoredResident >> 20) MiB")
log(
  "restored items with a vector: \(restoredCount) of \(expectedCount), texts embedded at the start: \(restoredPending)"
)
log(String(format: "first search after the start: %.0f ms", restoredSearch))

// MARK: - Report

let searchMax = searchTimes.map(\.milliseconds).max() ?? 0
let updateMax = updateTimes.max() ?? 0
let checks: [(name: String, value: Double, limit: Double)] = [
  ("search, limit = catalog size (max of \(searchTimes.count) queries)", searchMax, Limits.search),
  ("update of 20 items (max of \(updateTimes.count))", updateMax, Limits.update),
  ("start from the stored catalog", startMilliseconds, Limits.start),
]
let passed =
  checks.allSatisfy { $0.value <= $0.limit } && restoredCount == expectedCount
  && restoredPending == 0

var markdown = """
  # Scale benchmark: \(itemCount) items

  Date: \(ISO8601DateFormatter().string(from: Date()))
  Machine: \(ProcessInfo.processInfo.activeProcessorCount) cores, \
  \(ProcessInfo.processInfo.physicalMemory >> 30) GiB
  Corpus: \(itemCount) chunks of 500 to 2,000 characters (average \(averageLength)), \
  vectors of \(HashEmbedder.dimension) dimensions from a stub embedder.

  | Measurement | Value | Limit | Result |
  |---|---:|---:|---|

  """
for check in checks {
  markdown += String(
    format: "| %@ | %.1f ms | %.0f ms | %@ |\n", check.name, check.value, check.limit,
    check.value <= check.limit ? "pass" : "FAIL")
}
markdown += String(
  format: """
    | search, median | %.1f ms | | |
    | update of 20 items, median | %.1f ms | | |
    | removal of 20 items | %.1f ms | | |
    | save after an update of 20 items, median (background) | %.1f ms | | |
    | build, embed and merge of the whole catalog (stub embedder) | %.0f ms | | |
    | first snapshot after the build (background) | %.0f ms | | |
    | first search after the start | %.1f ms | | |
    | resident memory after the start (fresh process) | %d MiB | | |
    | resident memory after the build (build process) | %d MiB | | |
    | stored catalog | %d MiB | | |

    """, median(searchTimes.map(\.milliseconds)), median(updateTimes), removeTime,
  median(saveTimes), buildMilliseconds, firstSaveMilliseconds, restoredSearch,
  restoredResident >> 20, (memoryAfterBuild - memoryBefore) >> 20, folderBytes(storeFolder) >> 20)
markdown += "\n## Searches\n\n| Query | Time | Matches |\n|---|---:|---:|\n"
for search in searchTimes {
  markdown += String(
    format: "| `%@` | %.1f ms | %d |\n", search.query, search.milliseconds, search.matches)
}
markdown += "\nResult: \(passed ? "pass" : "FAIL")\n"

let json: [String: Any] = [
  "items": itemCount,
  "averageTextLength": averageLength,
  "dimension": HashEmbedder.dimension,
  "searchMaxMilliseconds": searchMax,
  "searchMedianMilliseconds": median(searchTimes.map(\.milliseconds)),
  "updateMaxMilliseconds": updateMax,
  "updateMedianMilliseconds": median(updateTimes),
  "removeMilliseconds": removeTime,
  "startMilliseconds": startMilliseconds,
  "buildMilliseconds": buildMilliseconds,
  "residentAfterStartMebibytes": restoredResident >> 20,
  "residentAfterBuildMebibytes": (memoryAfterBuild - memoryBefore) >> 20,
  "storedMebibytes": folderBytes(storeFolder) >> 20,
  "passed": passed,
]
try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)
try markdown.write(
  to: outputFolder.appendingPathComponent("scale-report.md"), atomically: true, encoding: .utf8)
try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
  .write(to: outputFolder.appendingPathComponent("scale-report.json"))
log("\n" + markdown)
try? FileManager.default.removeItem(at: storeFolder)
exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
