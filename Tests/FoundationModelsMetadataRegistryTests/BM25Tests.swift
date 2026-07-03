import Foundation
import Testing

@testable import FoundationModelsMetadataRegistry

/// BM25F-lite scoring tests, adapted from CodeContextKit's `RankerTests.swift`
/// "BM25" section (which ports the Rust `swissarmyhammer-search` crate's
/// `score.rs` test suite; see plan.md "Search").
///
/// This domain's two weighted fields are `SearchableMetadata.id` and its
/// rendered `block` (`renderBlock()`), so the CodeContextKit constant
/// `symbolPathFieldWeight` is ported here as `BM25.idFieldWeight` and
/// `bodyFieldWeight` as `BM25.blockFieldWeight` (plan.md "Catalog contract").
struct BM25Tests {
    /// Reference Okapi BM25 term contribution, for hand-comparison against
    /// `BM25Corpus.score`.
    private func referenceTerm(
        n: Double, df: Double, tf: Double, documentLength: Double, averageDocumentLength: Double
    ) -> Double {
        let idf = log(1.0 + (n - df + 0.5) / (df + 0.5))
        let lengthNorm = BM25.k1 * (1.0 - BM25.b + BM25.b * documentLength / averageDocumentLength)
        return idf * tf * (BM25.k1 + 1.0) / (tf + lengthNorm)
    }

    @Test
    func singleTermMatchesHandComputed() {
        // 3-doc corpus, query "foo". doc lens 4, 2, 6 -> avgdl = 4.0.
        // "foo" appears in docs 0 and 1 -> df = 2, N = 3.
        let query = ["foo"]
        let corpus = BM25Corpus(
            queryTokens: query,
            documents: [
                (4, Set(["foo"])),
                (2, Set(["foo"])),
                (6, Set()),
            ]
        )
        let got = corpus.score(weightedTermFrequency: ["foo": 1.0], documentLength: 4, queryTokens: query)
        let want = referenceTerm(n: 3.0, df: 2.0, tf: 1.0, documentLength: 4.0, averageDocumentLength: 4.0)
        #expect(abs(got - want) < 1e-4)
    }

    @Test
    func twoTermMatchesHandComputed() {
        // Query "foo bar". df(foo)=2, df(bar)=1, N=3, avgdl=4.0.
        let query = ["foo", "bar"]
        let corpus = BM25Corpus(
            queryTokens: query,
            documents: [
                (4, Set(["foo", "bar"])),
                (2, Set(["foo"])),
                (6, Set()),
            ]
        )
        let got = corpus.score(
            weightedTermFrequency: ["foo": 1.0, "bar": 1.0], documentLength: 4, queryTokens: query
        )
        let want =
            referenceTerm(n: 3.0, df: 2.0, tf: 1.0, documentLength: 4.0, averageDocumentLength: 4.0)
            + referenceTerm(n: 3.0, df: 1.0, tf: 1.0, documentLength: 4.0, averageDocumentLength: 4.0)
        #expect(abs(got - want) < 1e-4)
    }

    @Test
    func rarerTermScoresHigher() {
        // Same tf/doc_len, but "rare" has df 1 vs "common" df 3.
        let query = ["rare", "common"]
        let corpus = BM25Corpus(
            queryTokens: query,
            documents: [
                (4, Set(["rare", "common"])),
                (4, Set(["common"])),
                (4, Set(["common"])),
            ]
        )
        let rare = corpus.score(weightedTermFrequency: ["rare": 1.0], documentLength: 4, queryTokens: ["rare"])
        let common = corpus.score(
            weightedTermFrequency: ["common": 1.0], documentLength: 4, queryTokens: ["common"]
        )
        #expect(rare > common)
    }

    @Test
    func higherWeightedTermFrequencyScoresHigher() {
        // Identical corpus and doc_len; only the weighted tf differs.
        let query = ["foo"]
        let corpus = BM25Corpus(queryTokens: query, documents: [(4, Set(["foo"])), (4, Set(["foo"]))])
        let high = corpus.score(weightedTermFrequency: ["foo": 3.0], documentLength: 4, queryTokens: query)
        let low = corpus.score(weightedTermFrequency: ["foo": 1.0], documentLength: 4, queryTokens: query)
        #expect(high > low)
    }

    @Test
    func idFieldMatchOutranksBlockOnlyMatchForSameTerm() {
        // Same corpus, same doc length; one doc's weighted tf comes from an
        // `id` occurrence (x5), the other's from a `block`-only occurrence
        // (x1) of the same term. This is the acceptance criterion for
        // BM25.swift's two-field weighting in this domain.
        let query = ["parse"]
        let corpus = BM25Corpus(queryTokens: query, documents: [(4, Set(["parse"])), (4, Set(["parse"]))])
        let idFieldMatch = corpus.score(
            weightedTermFrequency: ["parse": BM25.idFieldWeight],
            documentLength: 4,
            queryTokens: query
        )
        let blockOnlyMatch = corpus.score(
            weightedTermFrequency: ["parse": BM25.blockFieldWeight],
            documentLength: 4,
            queryTokens: query
        )
        #expect(idFieldMatch > blockOnlyMatch)
    }

    @Test
    func repeatedQueryTermNotDoubleCounted() {
        let query = ["foo", "foo"]
        let corpus = BM25Corpus(queryTokens: query, documents: [(4, Set(["foo"])), (4, Set())])
        let got = corpus.score(weightedTermFrequency: ["foo": 1.0], documentLength: 4, queryTokens: query)
        let want = referenceTerm(n: 2.0, df: 1.0, tf: 1.0, documentLength: 4.0, averageDocumentLength: 4.0)
        #expect(abs(got - want) < 1e-4)
    }

    @Test
    func emptyCorpusIsZero() {
        let query = ["foo"]
        let corpus = BM25Corpus(queryTokens: query, documents: [(Int, Set<String>)]())
        #expect(corpus.score(weightedTermFrequency: ["foo": 1.0], documentLength: 0, queryTokens: query) == 0.0)
    }

    @Test
    func fieldWeightConstantsMatchDomainSpec() {
        // plan.md's ×5 id-field / ×1 block weighting.
        #expect(BM25.idFieldWeight == 5.0)
        #expect(BM25.blockFieldWeight == 1.0)
        #expect(BM25.idFieldWeight == BM25.blockFieldWeight * 5.0)
    }
}
