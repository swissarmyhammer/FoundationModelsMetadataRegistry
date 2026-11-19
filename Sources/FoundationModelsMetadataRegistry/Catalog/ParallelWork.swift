import Dispatch
import Foundation

/// Runs CPU work over index ranges on all cores, with
/// `DispatchQueue.concurrentPerform(iterations:execute:)`.
///
/// The work is synchronous: the caller waits for each chunk. The retrieval
/// scorer and the index build of a large catalog use it. A small count runs
/// on the calling thread with no dispatch.
enum ParallelWork {
  /// The smallest count of indices in one chunk.
  static let minimumChunk = 512

  /// The chunks of `0..<count`: about four for each active core, and none
  /// smaller than `minimumChunk`.
  ///
  /// - Parameter count: the count of indices.
  /// - Returns: the chunks, in order, which cover `0..<count`.
  static func chunks(count: Int) -> [Range<Int>] {
    guard count > 0 else { return [] }
    let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
    let chunkCount = max(1, min(cores * 4, count / minimumChunk))
    let size = (count + chunkCount - 1) / chunkCount
    return stride(from: 0, to: count, by: size).map { $0..<min($0 + size, count) }
  }

  /// Calls `body` one time for each chunk of `0..<count`, in parallel.
  ///
  /// - Parameters:
  ///   - count: the count of indices.
  ///   - body: the work for one chunk. It must write only to its own indices.
  static func forEachChunk(count: Int, _ body: @Sendable (Range<Int>) -> Void) {
    let ranges = chunks(count: count)
    guard ranges.count > 1 else {
      ranges.forEach(body)
      return
    }
    DispatchQueue.concurrentPerform(iterations: ranges.count) { body(ranges[$0]) }
  }

  /// Returns `transform(i)` for each `i` in `0..<count`, computed in parallel.
  ///
  /// - Parameters:
  ///   - count: the count of indices.
  ///   - transform: a pure function of the index.
  /// - Returns: the results, in index order.
  static func map<Result: Sendable>(count: Int, _ transform: @Sendable (Int) -> Result) -> [Result]
  {
    let results = UnsafeMutableBufferPointer<Result>.allocate(capacity: count)
    defer { results.deallocate() }
    let output = SendableBuffer(results)
    forEachChunk(count: count) { range in
      for index in range { output.initialize(index, to: transform(index)) }
    }
    return Array(UnsafeMutableBufferPointer(rebasing: results[0..<count]).moveAll())
  }
}

/// A buffer that parallel chunks write to, each at its own indices.
///
/// `@unchecked Sendable`: the chunks of `ParallelWork` never share an index,
/// and the caller reads the buffer only after each chunk returned.
struct SendableBuffer<Element>: @unchecked Sendable {
  /// The buffer.
  let base: UnsafeMutableBufferPointer<Element>

  /// Wraps `base`.
  ///
  /// - Parameter base: the buffer.
  init(_ base: UnsafeMutableBufferPointer<Element>) {
    self.base = base
  }

  /// Initializes the uninitialized element at `index` to `value`.
  ///
  /// - Parameters:
  ///   - index: the index.
  ///   - value: the value.
  func initialize(_ index: Int, to value: Element) {
    (base.baseAddress! + index).initialize(to: value)
  }

  /// The element at `index`. The element must be initialized.
  subscript(index: Int) -> Element {
    get { base[index] }
    nonmutating set { base[index] = newValue }
  }
}

extension UnsafeMutableBufferPointer {
  /// Moves each element out to a new array, and leaves the buffer
  /// uninitialized.
  ///
  /// - Returns: the elements, in order.
  fileprivate func moveAll() -> [Element] {
    [Element](unsafeUninitializedCapacity: count) { target, initialized in
      _ = target.moveInitialize(fromContentsOf: self)
      initialized = count
    }
  }
}
