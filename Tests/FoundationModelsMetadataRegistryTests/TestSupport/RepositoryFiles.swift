import Foundation

/// Reads files out of the repository's own working tree, for the suites that
/// assert on what the repository *says* rather than on what its code does —
/// the manifest and the README.
///
/// The root is resolved from `#filePath`, never from the working directory: a
/// test process inherits whatever directory its runner started in, and
/// `swift test` and an IDE do not agree on that.
enum RepositoryFiles {
    /// The repository root, resolved relative to this source file's own path
    /// (`#filePath` is
    /// `Tests/FoundationModelsMetadataRegistryTests/TestSupport/RepositoryFiles.swift`,
    /// three directories below the root).
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // TestSupport/
        .deletingLastPathComponent()  // Tests/FoundationModelsMetadataRegistryTests/
        .deletingLastPathComponent()  // Tests/
        .deletingLastPathComponent()  // repository root

    /// Reads one of the repository's files as text.
    ///
    /// - Parameter path: the file's path, relative to the repository root.
    /// - Returns: the whole text of the file.
    /// - Throws: an error when the file cannot be read.
    static func text(at path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
