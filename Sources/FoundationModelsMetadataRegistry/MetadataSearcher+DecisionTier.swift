import FoundationModelsDecision

/// The `.decision` search tier of `MetadataSearcher`: a two-stage reranker.
/// The retrieval tier gives the candidates, and a FoundationModelsDecision
/// `DecisionModel` gives the probability of "yes" for one yes-or-no question
/// about each candidate.
extension MetadataSearcher {
  /// Answers one `.decision`/`.auto` search with the decision tier.
  ///
  /// 1. The retrieval tier ranks the live `index` and gives the first
  ///    `config.candidateCount` candidates (BM25, trigram and cosine).
  /// 2. One `DecisionSession` on `config.model`, whose state is
  ///    `.text(intent)`, answers one batch of questions: one question for
  ///    each candidate, made with `config.question`. Because the state is
  ///    the intent, a local model reads the intent one time and reuses it
  ///    for each question.
  /// 3. The score of each candidate is its P(yes). The tier removes each
  ///    candidate whose score is below `config.minimumProbability`, sorts
  ///    the remaining candidates by score, and returns at most `limit` of
  ///    them. Thus an intent that no candidate satisfies gives an empty
  ///    result.
  ///
  /// The tier takes the `index` snapshot before its first suspension, and
  /// each `Match` takes its block and its `item` from that snapshot. A
  /// concurrent `update(items:)` during the model call thus cannot mix the
  /// items of two catalogs. Each `Match` keeps the retrieval `Signals` of
  /// its candidate.
  ///
  /// `limit <= 0`, an empty catalog, or an intent that the retrieval tier
  /// finds no candidate for gives an empty result, and asks the model
  /// nothing.
  ///
  /// The answer has the `decision` tier. Its signals are the retrieval
  /// signals that ranked the candidates, then `decision` when the model
  /// ranked them. The retrieval step keeps its own `hybrid` rank span. The
  /// call to the model runs in one more `RegistryTelemetry.SpanName.rank`
  /// span, with the `decision` ranker and the count of questions as the
  /// candidate count, and records one
  /// `RegistryTelemetry.MetricName.rankDuration` value with the `decision`
  /// ranker, also when the model throws. No span, log record or metric
  /// holds the intent, a block or a question (rule 4).
  ///
  /// Internal, not private, because `search(intent:limit:)` lives in its
  /// own file.
  ///
  /// - Parameters:
  ///   - config: the configuration of the decision tier.
  ///   - intent: the search query, which is also the state of the decision
  ///     session.
  ///   - limit: the maximum number of matches to return.
  /// - Returns: the reranked matches, with the `decision` tier and the
  ///   signals that ranked them.
  /// - Throws: what the decision session throws, or
  ///   `DecisionError.invalidResponse` when `config.question` makes a
  ///   question whose answer is not binary.
  func decisionSearch(_ config: DecisionConfig, intent: String, limit: Int) async throws
    -> TierAnswer
  {
    guard limit > 0 else {
      return TierAnswer(tier: .decision, signals: [], matches: [])
    }
    let snapshot = index
    let retrieval = await retrievalSearch(
      intent: intent, limit: config.candidateCount, over: snapshot)
    guard !retrieval.matches.isEmpty else {
      return TierAnswer(tier: .decision, signals: retrieval.signals, matches: [])
    }

    let probabilities = try await Self.probabilities(
      of: retrieval.matches, intent: intent, config: config)
    let matches = Self.reranked(
      retrieval.matches,
      by: probabilities,
      minimumProbability: config.minimumProbability,
      limit: limit,
    )
    return TierAnswer(tier: .decision, signals: retrieval.signals + [.decision], matches: matches)
  }

  /// Asks the decision model for the P(yes) of each candidate, in one batch.
  ///
  /// The call to the model runs in one `RegistryTelemetry.SpanName.rank`
  /// span through `RegistryTelemetry.withTracedRank(_:candidateCount:_:)`
  /// (rule 8, the model can wait for a long time), with the `decision`
  /// ranker and the count of questions as the candidate count.
  ///
  /// - Parameters:
  ///   - candidates: the retrieval candidates, in retrieval order.
  ///   - intent: the search query, which is the state of the session.
  ///   - config: the configuration that gives the model and the question.
  /// - Returns: the P(yes) of each candidate, in the order of `candidates`.
  /// - Throws: what the decision session throws, or
  ///   `DecisionError.invalidResponse` for an answer that is not binary.
  private static func probabilities(
    of candidates: [Match<Item>],
    intent: String,
    config: DecisionConfig,
  ) async throws -> [Double] {
    let session = DecisionSession(model: config.model, state: .text(intent))
    let questions = candidates.map { config.question($0.id, $0.block) }
    let response = try await RegistryTelemetry.withTracedRank(
      .decision, candidateCount: questions.count
    ) {
      try await session.decide(questions)
    }
    return try response.answers.map(Self.probabilityOfYes)
  }

  /// Gives the P(yes) of a binary answer.
  ///
  /// The session makes sure that each answer has the case of its question,
  /// so an answer that is not binary comes from a `config.question` that
  /// made a question that is not binary.
  ///
  /// - Parameter answer: the answer to one candidate question.
  /// - Returns: the probability of "yes".
  /// - Throws: `DecisionError.invalidResponse` when `answer` is not binary.
  private static func probabilityOfYes(_ answer: Answer) throws -> Double {
    guard case .binary(let probability) = answer else {
      throw DecisionError.invalidResponse("The decision tier expects a binary answer.")
    }
    return probability
  }

  /// Reranks the candidates by their P(yes).
  ///
  /// - Parameters:
  ///   - candidates: the retrieval candidates, in retrieval order.
  ///   - probabilities: the P(yes) of each candidate, in the order of
  ///     `candidates`.
  ///   - minimumProbability: a candidate with a lower P(yes) is not a match.
  ///   - limit: the maximum number of matches to return.
  /// - Returns: at most `limit` matches, sorted by descending P(yes), and
  ///   in retrieval order for equal P(yes). The score of each match is its
  ///   P(yes).
  private static func reranked(
    _ candidates: [Match<Item>],
    by probabilities: [Double],
    minimumProbability: Double,
    limit: Int,
  ) -> [Match<Item>] {
    let scored = zip(candidates, probabilities).map { candidate, probability in
      Match(
        id: candidate.id,
        block: candidate.block,
        score: probability,
        signals: candidate.signals,
        item: candidate.item,
      )
    }
    return scored.enumerated()
      .filter { $0.element.score >= minimumProbability }
      // The higher score comes first. For equal scores, the lower
      // retrieval position comes first.
      .sorted { ($0.element.score, $1.offset) > ($1.element.score, $0.offset) }
      .prefix(limit)
      .map(\.element)
  }
}
