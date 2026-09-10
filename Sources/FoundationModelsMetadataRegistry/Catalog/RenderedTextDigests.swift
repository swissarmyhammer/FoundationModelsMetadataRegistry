import CryptoKit
import Foundation

/// The SHA-256 digests of the three texts one catalog entry renders: its
/// verbatim block, its indexed text, and its embedded text.
///
/// Two jobs read these digests, and they read different ones (plan.md §8):
///
/// - `embeddedText` keys embedding reuse. Two builds' entries for the same
///   `id` with equal `embeddedText` digests were embedded from the same text,
///   so a stored embedding is still valid and re-embedding would be wasted
///   work — and a change to any *other* text never invalidates a vector.
/// - The whole value keys content identity, which is
///   `MetadataIndex.hasIdenticalContent(to:)`'s question and, through it,
///   `MetadataSearcher.update(items:)`'s redundant-update guard. A changed
///   block alone must be a content change: the block is what a `Match`
///   carries back, so serving the old one would be serving stale text.
///
/// Texts that are equal are digested one time. A domain that overrides
/// neither `SearchableMetadata.renderIndexedText(from:)` nor
/// `renderEmbeddedText(from:)` renders one text for all three jobs, and pays
/// exactly the one hash it paid when an entry had a block hash alone.
struct RenderedTextDigests: Sendable, Equatable {
    /// The digest of the entry's verbatim `renderBlock()` text.
    let block: Data

    /// The digest of the entry's `renderIndexedText(from:)` text.
    let indexedText: Data

    /// The digest of the entry's `renderEmbeddedText(from:)` text.
    let embeddedText: Data

    /// Digests one entry's three rendered texts, hashing each distinct text
    /// exactly once.
    ///
    /// - Parameters:
    ///   - block: the entry's verbatim rendered block.
    ///   - indexedText: the text the entry's keyword signals tokenize.
    ///   - embeddedText: the text the entry's embedding is computed from.
    init(block: String, indexedText: String, embeddedText: String) {
        let blockDigest = Self.digest(of: block)
        let indexedTextDigest = indexedText == block ? blockDigest : Self.digest(of: indexedText)
        self.block = blockDigest
        self.indexedText = indexedTextDigest
        if embeddedText == block {
            self.embeddedText = blockDigest
        } else if embeddedText == indexedText {
            self.embeddedText = indexedTextDigest
        } else {
            self.embeddedText = Self.digest(of: embeddedText)
        }
    }

    /// The SHA-256 digest of `text`'s UTF-8 bytes.
    ///
    /// - Parameter text: the text to digest.
    /// - Returns: the digest's bytes.
    private static func digest(of text: String) -> Data {
        Data(SHA256.hash(data: Data(text.utf8)))
    }
}
