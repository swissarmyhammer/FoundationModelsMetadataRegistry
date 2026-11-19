/// The stored embeddings of one `MetadataIndex`, by slot.
///
/// The vectors of the common dimension go into a contiguous row-major matrix,
/// in blocks of `rowsPerBlock` rows. A block is its own array, so a copy of
/// the index that changes one vector copies one block, not the whole matrix.
/// A vector of another dimension (or an empty vector) goes into a side table.
/// The common dimension is the dimension of the first non-empty vector.
///
/// For each matrix row, the table keeps the squared magnitude, computed with
/// the same sequential `Float` arithmetic as
/// `CosineScoring.cosineSimilarity(_:_:)`. Thus `cosineScore(slot:query:)`
/// gives the same value, bit for bit, as that function.
struct EmbeddingMatrix: Sendable {
  /// The count of matrix rows in one block.
  static let rowsPerBlock = 1024

  /// What a slot holds.
  enum Kind: UInt8, Sendable {
    /// No vector.
    case none

    /// A row of the matrix.
    case row

    /// A vector in the side table.
    case side
  }

  /// The common dimension, or `0` before the first non-empty vector.
  private(set) var dimension = 0

  /// The matrix blocks. Each block holds `rowsPerBlock * dimension` floats.
  private var blocks: [[Float]] = []

  /// What each slot holds.
  private var kinds: [Kind] = []

  /// The squared magnitude of each matrix row, by slot.
  private var magnitudes: [Float] = []

  /// The vectors that are not of the common dimension, by slot.
  private var side: [Int: [Float]] = [:]

  /// The count of slots that hold a vector.
  private(set) var count = 0

  /// Makes an empty table.
  init() {}

  /// Whether `slot` holds a vector.
  ///
  /// - Parameter slot: the slot.
  /// - Returns: whether the slot holds a vector.
  func hasVector(slot: Int) -> Bool {
    slot < kinds.count && kinds[slot] != .none
  }

  /// The vector of `slot`, or `nil`.
  ///
  /// - Parameter slot: the slot.
  /// - Returns: a copy of the vector of the slot, or `nil`.
  func vector(slot: Int) -> [Float]? {
    guard slot < kinds.count else { return nil }
    switch kinds[slot] {
    case .none:
      return nil
    case .side:
      return side[slot]
    case .row:
      let (block, offset) = location(of: slot)
      return Array(blocks[block][offset..<(offset + dimension)])
    }
  }

  /// Stores `vector` in `slot`, or clears the slot when `vector` is `nil`.
  ///
  /// - Parameters:
  ///   - vector: the vector, or `nil`.
  ///   - slot: the slot.
  mutating func set(_ vector: [Float]?, slot: Int) {
    grow(toInclude: slot)
    if kinds[slot] != .none {
      count -= 1
      if kinds[slot] == .side { side[slot] = nil }
      kinds[slot] = .none
    }
    guard let vector else { return }
    count += 1
    if dimension == 0, !vector.isEmpty { dimension = vector.count }
    guard vector.count == dimension, dimension > 0 else {
      side[slot] = vector
      kinds[slot] = .side
      return
    }
    let (block, offset) = location(of: slot)
    while blocks.count <= block {
      blocks.append([Float](repeating: 0, count: Self.rowsPerBlock * dimension))
    }
    blocks[block].withUnsafeMutableBufferPointer { buffer in
      for index in 0..<dimension { buffer[offset + index] = vector[index] }
    }
    magnitudes[slot] = Self.sequentialDot(vector, vector)
    kinds[slot] = .row
  }

  /// The cosine similarity of `query` and the vector of `slot`, or `nil` when
  /// the slot holds no vector.
  ///
  /// The value is the value of `CosineScoring.cosineSimilarity(query, vector)`,
  /// bit for bit: `0.0` for a dimension mismatch, an empty vector or a zero
  /// magnitude.
  ///
  /// - Parameters:
  ///   - slot: the slot.
  ///   - query: the query vector.
  /// - Returns: the cosine score, or `nil`.
  func cosineScore(slot: Int, query: PreparedQueryVector) -> Double? {
    guard slot < kinds.count else { return nil }
    switch kinds[slot] {
    case .none:
      return nil
    case .side:
      return side[slot].map { CosineScoring.cosineSimilarity(query.vector, $0) }
    case .row:
      guard query.vector.count == dimension, !query.vector.isEmpty else { return 0.0 }
      let (block, offset) = location(of: slot)
      let dot = blocks[block].withUnsafeBufferPointer { row in
        query.vector.withUnsafeBufferPointer { queryBuffer in
          var dot: Float = 0.0
          for index in 0..<dimension {
            dot += queryBuffer[index] * row[offset + index]
          }
          return dot
        }
      }
      let targetMagnitudeSquared = magnitudes[slot]
      guard query.magnitudeSquared > 0.0, targetMagnitudeSquared > 0.0 else { return 0.0 }
      return Double(
        dot / (query.magnitudeSquared.squareRoot() * targetMagnitudeSquared.squareRoot()))
    }
  }

  /// The block and the offset of the first float of the row of `slot`.
  private func location(of slot: Int) -> (block: Int, offset: Int) {
    (slot / Self.rowsPerBlock, (slot % Self.rowsPerBlock) * dimension)
  }

  /// Grows the slot arrays so that `slot` is valid.
  private mutating func grow(toInclude slot: Int) {
    guard slot >= kinds.count else { return }
    let added = slot + 1 - kinds.count
    kinds.append(contentsOf: repeatElement(.none, count: added))
    magnitudes.append(contentsOf: repeatElement(0, count: added))
  }

  /// The dot product of `left` and `right`, summed in index order, as
  /// `CosineScoring.cosineSimilarity(_:_:)` sums it.
  ///
  /// - Parameters:
  ///   - left: a vector.
  ///   - right: a vector of the same count.
  /// - Returns: the dot product.
  static func sequentialDot(_ left: [Float], _ right: [Float]) -> Float {
    var total: Float = 0.0
    for index in left.indices { total += left[index] * right[index] }
    return total
  }
}

/// A query vector with its squared magnitude, computed one time for each
/// search.
struct PreparedQueryVector: Sendable {
  /// The query vector.
  let vector: [Float]

  /// The squared magnitude of `vector`, summed in index order.
  let magnitudeSquared: Float

  /// Prepares `vector` for `EmbeddingMatrix.cosineScore(slot:query:)`.
  ///
  /// - Parameter vector: the query vector.
  init(_ vector: [Float]) {
    self.vector = vector
    magnitudeSquared = EmbeddingMatrix.sequentialDot(vector, vector)
  }
}
