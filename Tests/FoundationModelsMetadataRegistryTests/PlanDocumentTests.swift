import Foundation
import Testing

/// Pins `plan.md` to the rule its own dated status note promises: every part
/// of the document that still names a Router-era symbol says, in that same
/// part, that the symbol is history.
///
/// `plan.md` is a design record, so the retired names must stay in it — the
/// history is the point, and deleting it would lose why the package took the
/// shape it has. What must not stay is an *unmarked* present-tense claim: a
/// sentence that reads as a statement about the package as it is today while
/// naming a type that went away with the `FoundationModelsRouter` dependency.
/// A reader cannot tell retained history from a stale claim by the name
/// alone; the dated marker beside it is the only thing that tells them apart.
///
/// The suite mechanizes that at section granularity. Each `## ` section is
/// read whole: a section that spells a retired name must also spell the
/// marker, and a section that spells none needs no marker. Section
/// granularity is the honest limit of this check — one marker clears the
/// whole section it sits in, so a stale sentence in an already-marked section
/// still passes. It catches the drift that has actually happened, which is a
/// section that carries a retired name and no marker at all.
@Suite("Plan document")
struct PlanDocumentTests {
    /// The plan, relative to the repository root.
    private static let planFileName = "plan.md"

    /// The stems of the names the Router removal retired.
    ///
    /// Stems rather than whole identifiers, so one entry covers a family:
    /// `Router` covers the package name, every "Router-backed" reading, and
    /// the `LiveRouterSupport` target; `Routed` covers `RoutedSession`,
    /// `RoutedEmbedder`, `RoutedEmbedderAdapter`, and `RoutedAgentSession`;
    /// `Grammar` covers the deleted Router type and the `idEnumGrammar(ids:)`
    /// that returned it. Matching is case-sensitive, so the ordinary
    /// lower-case word "grammar" — which the plan still uses correctly — does
    /// not match.
    ///
    /// Every stem here names something that is *gone*. `IntegrationTests`
    /// was a stem while the nested package was deleted; the package is back
    /// (decision #15), so the stem is not. A live directory must be free to
    /// be named in the present tense, and holding it here would have forced
    /// every section that names it to call it history — the one reading that
    /// is now false.
    ///
    /// This is deliberately a wider net than the whole identifiers
    /// `PackageManifestTests` bans outright, and it asks for something
    /// weaker. There the name may not appear at all; here it may, as often
    /// as the history needs, so long as the section it appears in says the
    /// name is history.
    private static let retiredNameStems = [
        "Router",
        "Routed",
        "Grammar",
    ]

    /// The text a section carries to mark its Router-era statements as
    /// history: a reference to the resolved decision that retired them, which
    /// every dated marker in `plan.md` spells.
    private static let supersededMarker = "decision #14"

    /// The prefix that opens a top-level section of the plan.
    ///
    /// Deeper headings (`### `) do not match it, so a subsection is read as
    /// part of the section that holds it.
    private static let sectionHeadingPrefix = "## "

    /// What a failure calls the text above the first section heading.
    private static let preambleHeading = "(preamble)"

    /// The line separator the plan is split on.
    private static let lineSeparator: Character = "\n"

    @Test("Every plan.md section that names a retired Router name marks it superseded")
    func marksEveryRetiredRouterNameAsSuperseded() throws {
        let offenders = try Self.sectionsMissingTheSupersededMarker()
        #expect(
            offenders.isEmpty,
            """
            Every section of plan.md that names one of \(Self.retiredNameStems) must also carry \
            the dated "\(Self.supersededMarker)" marker, so a reader takes the name as history \
            and not as a claim about the package today; found: \(offenders)
            """
        )
    }

    /// Reads the plan and reports each section that names something retired
    /// without marking it.
    ///
    /// - Returns: `"<heading>: <stems>"` for each offending section, in
    ///   document order.
    /// - Throws: an error when the plan cannot be read.
    private static func sectionsMissingTheSupersededMarker() throws -> [String] {
        let plan = try RepositoryFiles.text(at: planFileName)
        var offenders: [String] = []
        for section in sections(in: plan) where !section.body.contains(supersededMarker) {
            let named = retiredNameStems.filter { section.body.contains($0) }
            guard !named.isEmpty else { continue }
            offenders.append("\(section.heading): \(named.joined(separator: ", "))")
        }
        return offenders
    }

    /// Splits the plan into its top-level sections.
    ///
    /// The text above the first `## ` heading is a section of its own: it
    /// carries the plan's summary paragraph *and* the status note that marks
    /// that paragraph, so the two must be weighed together.
    ///
    /// - Parameter text: the whole text of the plan.
    /// - Returns: each section's heading and its whole body, the heading line
    ///   included, in document order.
    private static func sections(in text: String) -> [(heading: String, body: String)] {
        var collected: [(heading: String, body: String)] = []
        var heading = preambleHeading
        var body = ""
        for line in text.split(separator: lineSeparator, omittingEmptySubsequences: false) {
            if line.hasPrefix(sectionHeadingPrefix) {
                collected.append((heading, body))
                heading = String(line)
                body = ""
            }
            body.append(contentsOf: line)
            body.append(lineSeparator)
        }
        collected.append((heading, body))
        return collected
    }
}
