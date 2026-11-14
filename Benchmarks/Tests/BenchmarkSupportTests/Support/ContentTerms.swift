import FoundationModelsMetadataRegistry

/// The content words of a text, as the fixture tests compare them.
///
/// The fixture rules speak about content words: a paraphrase intent shares
/// no content word with its answer, and a lexical intent shares at least one.
/// `Tokenizer.tokenize(text:)` removes no function word, so this helper
/// removes them. It uses the same `Tokenizer` that the retrieval tier indexes
/// with, so the comparison reads the terms that a keyword match reads.
enum ContentTerms {
  /// The function words that carry no subject. A shared function word does
  /// not make two texts share a subject.
  static let functionWords: Set<String> = [
    "a", "about", "after", "all", "an", "and", "any", "are", "as", "at", "be", "before",
    "between", "but", "by", "can", "do", "does", "each", "every", "for", "from", "get",
    "how", "i", "in", "into", "is", "it", "its", "me", "my", "of", "on", "one", "or",
    "so", "some", "that", "the", "them", "then", "this", "to", "up", "what", "when",
    "which", "who", "with", "you", "your",
  ]

  /// The content terms of `text`.
  ///
  /// - Parameter text: the text to read.
  /// - Returns: the lowercased tokens of `text` that are not function words.
  static func of(_ text: String) -> Set<String> {
    Set(Tokenizer.tokenize(text: text)).subtracting(functionWords)
  }
}
