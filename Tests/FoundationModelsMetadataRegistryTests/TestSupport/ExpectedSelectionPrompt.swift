/// The prompt text that `SelectionTier` sends to a session, written one time
/// for each test that pins it.
///
/// The text is a literal and not a call into the tier. Thus a change to the
/// prompt that the tier sends makes the tests fail.
enum ExpectedSelectionPrompt {
  /// Gives the request part of each selection prompt: the intent in a
  /// `<request>` block, then the line that asks for the exact ids and names
  /// the ids of the candidates of the prompt as the only choices.
  ///
  /// Each prompt is this text only. The assembled prefix is the instructions
  /// of the session. It is not a part of the prompt.
  ///
  /// - Parameters:
  ///   - intent: the plain-language search intent.
  ///   - ids: the candidate ids of the prompt, in prefix order: the full
  ///     catalog under budget, or one run over budget.
  /// - Returns: the request text for `intent` over `ids`.
  static func request(for intent: String, ids: [String]) -> String {
    "<request>\n\(intent)\n</request>\nAnswer with the exact ids of the chosen candidates. "
      + "Choose only from these ids: \(ids.joined(separator: ", "))."
  }
}
