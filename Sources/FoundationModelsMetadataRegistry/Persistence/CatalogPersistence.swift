import Foundation

/// Where a persistent `MetadataSearcher` keeps its catalog and its vectors,
/// and which embedding model made the vectors (plan.md decision #10).
///
/// Give it to `MetadataSearcher.init(persistence:mode:weights:embedder:selection:decision:onDiagnostic:)`
/// or to `SharedCatalogEmbedding.init(persistence:embedder:onDiagnostic:)`.
/// The items must be `Codable`.
///
/// ```swift
/// let searcher = await MetadataSearcher<TranscriptChunk>(
///     persistence: CatalogPersistence(
///         folder: home.appending(path: "session-search/server"),
///         embeddingModelID: "embeddinggemma-300m"),
///     mode: .retrieval,
///     embedder: embedder)
/// ```
///
/// The searcher reads the folder one time, at its start, and then writes it
/// after each change and each embed chunk, on a background queue. Only one
/// searcher (or one group of searchers that share one
/// `SharedCatalogEmbedding`) may use a folder at a time.
///
/// The stored vectors are valid only for one embedding model. When
/// `embeddingModelID` is not the id that the stored catalog was written
/// with, the searcher drops the stored catalog and starts empty, and the next
/// update of the caller builds it again.
public struct CatalogPersistence: Sendable, Equatable {
  /// The folder of the stored catalog. The searcher makes it when it does
  /// not exist, and keeps no other file in it.
  public let folder: URL

  /// The id of the embedding model of the searcher, for example its
  /// Hugging Face repository id. The stored vectors are kept only for this id.
  public let embeddingModelID: String

  /// Makes a persistence option.
  ///
  /// - Parameters:
  ///   - folder: the folder of the stored catalog.
  ///   - embeddingModelID: the id of the embedding model of the searcher.
  public init(folder: URL, embeddingModelID: String) {
    self.folder = folder
    self.embeddingModelID = embeddingModelID
  }

  /// The file of the snapshot: the whole catalog at one generation.
  var snapshotURL: URL { folder.appendingPathComponent(CatalogFileFormat.snapshotFileName) }

  /// The file of the journal: the changes after the snapshot.
  var journalURL: URL { folder.appendingPathComponent(CatalogFileFormat.journalFileName) }
}
