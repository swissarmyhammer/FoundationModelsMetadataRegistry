import FoundationModelsDecision

extension Signals {
  /// The `Signals` of an item that the retrieval tier does not rank: `0.0`
  /// for each signal.
  ///
  /// This is the value that `HybridRanker` gives an item that no signal
  /// ranks, and `Match.signals.cosine` holds `0.0` for an item with no
  /// cosine score (see `MetadataSearcher`).
  static let unranked = Signals(bm25: 0, trigram: 0, cosine: 0)
}

/// The `.decision` search tier of `MetadataSearcher`. A
/// FoundationModelsDecision `DecisionModel` gives the probability of "yes"
/// for one yes-or-no question about each item of the whole catalog. The
/// retrieval tier gives only the signals of each match and the order of
/// equal scores.
extension MetadataSearcher {
  /// One catalog item that the decision tier asks the model about.
  private struct DecisionCandidate {
    /// The id of the item.
    let id: String

    /// The block of the item, from the index snapshot.
    let block: String

    /// The item, from the index snapshot.
    let item: Item

    /// The retrieval signals of the item, or `Signals.unranked` when the
    /// retrieval tier does not rank it.
    let signals: Signals

    /// The position of the item among equal P(yes): its retrieval position
    /// when the retrieval tier ranks it, else the count of retrieval
    /// matches plus its catalog position.
    let tieBreakRank: Int
  }

  /// Answers one `.decision`/`.auto` search with the decision tier.
  ///
  /// 1. The retrieval tier ranks the whole `index` snapshot (BM25, trigram
  ///    and cosine), with the catalog size as its limit. The tier uses this
  ///    result only to attach the `Signals` of each match and to order
  ///    equal scores.
  /// 2. One `DecisionSession` on `config.model`, whose state is
  ///    `.text(intent)`, answers one question for EACH catalog item, made
  ///    with `config.question`, in catalog order. An item that the
  ///    retrieval tier does not find also gets a question. The session gets
  ///    the questions in batches of at most `config.batchSize`. Because all
  ///    batches go to one session whose state is the intent, a local model
  ///    reads the intent one time and reuses it for each question.
  /// 3. The score of each item is its P(yes). The tier removes each item
  ///    whose score is below `config.minimumProbability`, sorts the
  ///    remaining items by score, and returns at most `limit` of them. For
  ///    equal scores, the retrieval order comes first, and then the catalog
  ///    order of the items that the retrieval tier does not rank. Thus an
  ///    intent that no item satisfies gives an empty result.
  ///
  /// The tier takes the `index` snapshot before its first suspension, and
  /// each `Match` takes its block and its `item` from that snapshot. A
  /// concurrent `update(items:)` during the model call thus cannot mix the
  /// items of two catalogs. Each `Match` keeps the retrieval `Signals` of
  /// its item, or `Signals.unranked` when the retrieval tier does not rank
  /// it.
  ///
  /// `limit <= 0` or an empty catalog gives an empty result, and asks the
  /// model nothing.
  ///
  /// The answer has the `decision` tier. Its signals are the retrieval
  /// signals, then `decision`. The retrieval step keeps its own `hybrid`
  /// rank span. The calls to the model run in one more
  /// `RegistryTelemetry.SpanName.rank` span, with the `decision` ranker and
  /// the catalog size as `rank.candidate_count`, and record one
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
  /// - Returns: the matches, with the `decision` tier and the signals that
  ///   ranked them.
  /// - Throws: what the decision session throws, or
  ///   `DecisionError.invalidResponse` when `config.question` makes a
  ///   question whose answer is not binary.
  func decisionSearch(_ config: DecisionConfig, intent: String, limit: Int) async throws
    -> TierAnswer
  {
    let snapshot = index
    guard limit > 0, !snapshot.ids.isEmpty else {
      return TierAnswer(tier: .decision, signals: [], matches: [])
    }
    let retrieval = await retrievalSearch(intent: intent, limit: snapshot.count, over: snapshot)
    let candidates = Self.candidates(in: snapshot, retrievalMatches: retrieval.matches)

    let probabilities = try await Self.probabilities(
      of: candidates, intent: intent, config: config)
    let matches = Self.ranked(
      candidates,
      by: probabilities,
      minimumProbability: config.minimumProbability,
      limit: limit,
    )
    return TierAnswer(tier: .decision, signals: retrieval.signals + [.decision], matches: matches)
  }

  /// Makes one candidate for each item of the snapshot, in catalog order.
  ///
  /// - Parameters:
  ///   - snapshot: the index snapshot of the search.
  ///   - retrievalMatches: the retrieval matches over `snapshot`, in
  ///     retrieval order.
  /// - Returns: one candidate for each item of `snapshot`, in catalog
  ///   order, with its retrieval signals and its tie-break rank.
  private static func candidates(
    in snapshot: MetadataIndex<Item>,
    retrievalMatches: [Match<Item>],
  ) -> [DecisionCandidate] {
    let rankedByID = Dictionary(
      uniqueKeysWithValues: retrievalMatches.enumerated().map { position, match in
        (match.id, (position: position, signals: match.signals))
      })
    return snapshot.ids.enumerated().compactMap { catalogPosition, id in
      guard let item = snapshot.item(forID: id), let block = snapshot.block(forID: id) else {
        return nil
      }
      let ranked = rankedByID[id]
      return DecisionCandidate(
        id: id,
        block: block,
        item: item,
        signals: ranked?.signals ?? .unranked,
        tieBreakRank: ranked?.position ?? retrievalMatches.count + catalogPosition,
      )
    }
  }

  /// Asks the decision model for the P(yes) of each candidate, in batches
  /// of at most `config.batchSize` questions, in one session.
  ///
  /// The calls to the model run in one `RegistryTelemetry.SpanName.rank`
  /// span through `RegistryTelemetry.withTracedRank(_:rankedCount:_:)`
  /// (rule 8, the model can wait for a long time), with the `decision`
  /// ranker and the count of questions (the catalog size) as
  /// `rank.candidate_count`.
  ///
  /// - Parameters:
  ///   - candidates: the candidates, in catalog order.
  ///   - intent: the search query, which is the state of the session.
  ///   - config: the configuration that gives the model, the batch size and
  ///     the question.
  /// - Returns: the P(yes) of each candidate, in the order of `candidates`.
  /// - Throws: what the decision session throws, or
  ///   `DecisionError.invalidResponse` for an answer that is not binary.
  private static func probabilities(
    of candidates: [DecisionCandidate],
    intent: String,
    config: DecisionConfig,
  ) async throws -> [Double] {
    let session = DecisionSession(model: config.model, state: .text(intent))
    let questions = candidates.map { config.question($0.id, $0.block) }
    let batches = stride(from: 0, to: questions.count, by: config.batchSize).map { start in
      Array(questions[start..<min(start + config.batchSize, questions.count)])
    }
    return try await RegistryTelemetry.withTracedRank(.decision, rankedCount: questions.count) {
      try await probabilities(answering: batches, in: session)
    }
  }

  /// Asks each batch of questions in `session`, one batch after the other.
  ///
  /// - Parameters:
  ///   - batches: the batches of questions, in order.
  ///   - session: the decision session that answers each batch.
  /// - Returns: the P(yes) of each question, in the order of the batches
  ///   and of the questions in each batch.
  /// - Throws: what the decision session throws, or
  ///   `DecisionError.invalidResponse` for an answer that is not binary.
  private static func probabilities(
    answering batches: [[Question]],
    in session: DecisionSession,
  ) async throws -> [Double] {
    var probabilities: [Double] = []
    for batch in batches {
      let response = try await session.decide(batch)
      probabilities += try response.answers.map(probabilityOfYes)
    }
    return probabilities
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

  /// Ranks the candidates by their P(yes).
  ///
  /// - Parameters:
  ///   - candidates: the candidates, in catalog order.
  ///   - probabilities: the P(yes) of each candidate, in the order of
  ///     `candidates`.
  ///   - minimumProbability: a candidate with a lower P(yes) is not a match.
  ///   - limit: the maximum number of matches to return.
  /// - Returns: at most `limit` matches, sorted by descending P(yes), and
  ///   by ascending tie-break rank for equal P(yes). The score of each
  ///   match is its P(yes).
  private static func ranked(
    _ candidates: [DecisionCandidate],
    by probabilities: [Double],
    minimumProbability: Double,
    limit: Int,
  ) -> [Match<Item>] {
    zip(candidates, probabilities)
      .filter { _, probability in probability >= minimumProbability }
      // The higher score comes first. For equal scores, the lower
      // tie-break rank comes first.
      .sorted { left, right in
        (left.1, right.0.tieBreakRank) > (right.1, left.0.tieBreakRank)
      }
      .prefix(limit)
      .map { candidate, probability in
        Match(
          id: candidate.id,
          block: candidate.block,
          score: probability,
          signals: candidate.signals,
          item: candidate.item,
        )
      }
  }
}
