import Foundation
import Testing

/// Pins `Package.swift` to a Router-free, GPU-free shape: no target of this
/// package may name an MLX or Hugging Face product.
///
/// Those products exist to resolve a live `Router` + `LiveModelLoader`, and no
/// code in this repository needs one any more: the Router-backed real-model
/// suite that did is gone, and the nested `IntegrationTests/` package that
/// stands in its place drives Apple Intelligence through
/// `LanguageModelSession`, over one path dependency on this package and nothing
/// else. Naming one here links MLX and Hugging Face into every `Examples/`
/// demo — and, through the test target, into a plain
/// `swift build --build-tests` — for a capability nothing exercises.
///
/// A later edit that re-adds one of those products to a target fails this
/// suite. A target that genuinely needs one belongs in a separate package
/// that declares the dependency in its own manifest, never here.
///
/// The suite pins the `dependencies:` list itself for the same reason. The
/// library is built over FoundationModelsRanker alone, so the manifest
/// declares that one package and no other. A later edit that adds one of the
/// live-Router packages back fails this suite too.
///
/// Last, the suite pins the *prose*: `Package.swift` and the files under
/// `Sources/` may not so much as spell `FoundationModelsRouter`,
/// `RoutedEmbedderAdapter`, or `RoutedAgentSession`. A comment describing a
/// dependency the package does not have, or a type that no longer exists,
/// misleads a reader exactly as a stale API doc does, and nothing else in
/// the build catches it.
@Suite("Package manifest")
struct PackageManifestTests {
    /// The products that pull the live-Router path into a target: MLX's
    /// Hugging Face hub and LM-common products, and the Hugging Face
    /// hub/transformers products.
    private static let liveRouterProductNames: Set<String> = [
        "MLXHuggingFace",
        "MLXLMCommon",
        "HuggingFace",
        "Tokenizers",
    ]

    /// The packages the manifest declared while this library resolved a live
    /// `Router`, and must not declare again.
    ///
    /// `FoundationModelsRouter` supplied the routing types. `mlx-swift-lm`,
    /// `swift-huggingface`, and `swift-transformers` supplied the live model
    /// loader. `swift-jinja` was pinned only to hold `swift-transformers`
    /// away from a release it cannot compile against, so that pin goes with
    /// the package it protected.
    private static let removedPackageNames: Set<String> = [
        "FoundationModelsRouter",
        "mlx-swift-lm",
        "swift-huggingface",
        "swift-transformers",
        "swift-jinja",
    ]

    /// The one package this library depends on.
    private static let rankerPackageName = "FoundationModelsRanker"

    /// The names the Router removal retired, which no covered file may spell
    /// even in prose.
    ///
    /// `FoundationModelsRouter` is the package this library no longer
    /// depends on. `RoutedEmbedderAdapter` and `RoutedAgentSession` were the
    /// two production conformers that wrapped it — the embedding seam's and
    /// the session seam's — and both are deleted upstream, so a comment that
    /// still offers either one sends a reader after a type that no compiler
    /// will find.
    private static let removedRouterNames = [
        "FoundationModelsRouter",
        "RoutedEmbedderAdapter",
        "RoutedAgentSession",
    ]

    /// The suffix a Git URL ends in, removed to read the package name.
    private static let gitURLSuffix = ".git"

    /// The manifest, relative to the repository root.
    private static let manifestFileName = "Package.swift"

    /// The directory holding the library's own sources, relative to the
    /// repository root.
    private static let sourcesDirectoryName = "Sources"

    @Test("Package.swift names no MLX or Hugging Face product")
    func namesNoLiveRouterProduct() throws {
        let declared = try Self.declaredProductNames()
        let live = declared.intersection(Self.liveRouterProductNames).sorted()
        #expect(
            live.isEmpty,
            """
            Package.swift must name no MLX or Hugging Face product — nothing in this repository \
            resolves a live Router any more; found: \(live)
            """
        )
    }

    @Test("Package.swift declares none of the removed dependencies")
    func declaresNoRemovedDependency() throws {
        let named = Set(try Self.declaredPackageNames() + Self.productPackageNames())
        let removed = named.intersection(Self.removedPackageNames).sorted()
        #expect(
            removed.isEmpty,
            """
            Package.swift must declare none of the packages the live-Router path needed — no \
            target names one any more; found: \(removed)
            """
        )
    }

    /// Reads the manifest, never `Package.resolved`: the resolution file is
    /// in `.gitignore`, so a fresh clone and CI have none to read.
    /// FoundationModelsRanker's own manifest declares `dependencies: []`, so
    /// the one entry here is also the whole resolved graph.
    @Test("Package.swift depends on FoundationModelsRanker and nothing else")
    func dependsOnTheRankerAlone() throws {
        let declared = try Self.declaredPackageNames()
        #expect(
            declared == [Self.rankerPackageName],
            """
            Package.swift must declare exactly one dependency, \(Self.rankerPackageName); \
            found: \(declared)
            """
        )
    }

    @Test("Package.swift and Sources/ spell none of the removed Router names")
    func spellsNoRemovedRouterName() throws {
        let offenders = try Self.filesSpellingARemovedRouterName()
        #expect(
            offenders.isEmpty,
            """
            Package.swift and every file under Sources/ must spell none of \
            \(Self.removedRouterNames) — this package does not depend on that package, and \
            those two types no longer exist; found: \(offenders)
            """
        )
    }

    /// Reads every product `Package.swift` names in a target's dependency
    /// list.
    ///
    /// Only literal names are read. A `.product(name:)` entry spelled with a
    /// constant — the manifest's own `foundationModelsRankerPackage`, say —
    /// resolves at manifest-evaluation time and is invisible to a text read,
    /// so a forbidden product smuggled in behind a constant would pass.
    /// `swift build` is the backstop there: nothing in this package imports
    /// one.
    ///
    /// - Returns: the set of product names the manifest spells out.
    /// - Throws: an error when the manifest cannot be read, or when the
    ///   pattern does not compile.
    private static func declaredProductNames() throws -> Set<String> {
        let text = try manifestText()
        let productPattern = try Regex(#"\.product\(\s*name:\s*"([^"]+)""#)
        return Set(firstCaptures(of: productPattern, in: text))
    }

    /// Reads the package name of every `.package(url:)` entry the manifest
    /// declares, in the order the manifest declares them.
    ///
    /// Each URL is a string literal that interpolates the manifest's own
    /// constants, so the constants are read first and substituted before the
    /// name is taken. Reading the entries is what keeps prose out of the
    /// answer: a doc comment that names a package is not a dependency on it,
    /// and a plain text search cannot tell the two apart.
    ///
    /// - Returns: the package name of each declared dependency.
    /// - Throws: an error when the manifest cannot be read, or when a pattern
    ///   does not compile.
    private static func declaredPackageNames() throws -> [String] {
        let text = try manifestText()
        let constants = try manifestConstants(in: text)
        let urlPattern = try Regex(#"\.package\(\s*url:\s*"([^"]+)""#)
        return try firstCaptures(of: urlPattern, in: text)
            .map { url in packageName(fromURL: try expanded(url, with: constants)) }
    }

    /// Reads the package name of every `.product(package:)` entry the
    /// manifest spells out as a literal.
    ///
    /// A product entry names its package, so it is a second place a removed
    /// dependency could survive: a product entry alone is what marked the
    /// swift-jinja pin as used.
    ///
    /// - Returns: the package name of each literal product entry.
    /// - Throws: an error when the manifest cannot be read, or when the
    ///   pattern does not compile.
    private static func productPackageNames() throws -> [String] {
        let text = try manifestText()
        let packagePattern = try Regex(#"\.product\([^)]*package:\s*"([^"]+)""#)
        return firstCaptures(of: packagePattern, in: text)
    }

    /// Reads the string constants the manifest declares.
    ///
    /// - Parameter text: the whole text of the manifest.
    /// - Returns: each constant name mapped to the string it holds.
    /// - Throws: an error when the pattern does not compile.
    private static func manifestConstants(in text: String) throws -> [String: String] {
        let constantPattern = try Regex(#"\blet\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]*)""#)
        var constants: [String: String] = [:]
        for match in text.matches(of: constantPattern) {
            guard let name = match[1].substring.map(String.init),
                let value = match[2].substring.map(String.init)
            else { continue }
            constants[name] = value
        }
        return constants
    }

    /// Substitutes the manifest's own constants into one of its string
    /// literals.
    ///
    /// A name the manifest does not declare is left as written, so an
    /// unresolved interpolation shows up in the answer instead of vanishing
    /// from it.
    ///
    /// - Parameters:
    ///   - literal: the text of a string literal, interpolations included.
    ///   - constants: the manifest's string constants.
    /// - Returns: the literal with every interpolation substituted.
    /// - Throws: an error when the pattern does not compile.
    private static func expanded(
        _ literal: String,
        with constants: [String: String]
    ) throws -> String {
        let interpolationPattern = try Regex(#"\\\(([A-Za-z_][A-Za-z0-9_]*)\)"#)
        var expandedText = ""
        var readFrom = literal.startIndex
        for match in literal.matches(of: interpolationPattern) {
            expandedText += literal[readFrom..<match.range.lowerBound]
            let name = match[1].substring.map(String.init) ?? ""
            expandedText += constants[name] ?? String(literal[match.range])
            readFrom = match.range.upperBound
        }
        expandedText += literal[readFrom...]
        return expandedText
    }

    /// Reads the package name a dependency URL ends in.
    ///
    /// - Parameter url: a dependency URL, in either the SSH or the HTTPS
    ///   form.
    /// - Returns: the last path component, without its `.git` suffix.
    private static func packageName(fromURL url: String) -> String {
        let components = url.split(whereSeparator: { $0 == "/" || $0 == ":" })
        let lastComponent = components.last.map(String.init) ?? url
        guard lastComponent.hasSuffix(gitURLSuffix) else { return lastComponent }
        return String(lastComponent.dropLast(gitURLSuffix.count))
    }

    /// Reads the first capture group of every match of a pattern.
    ///
    /// - Parameters:
    ///   - pattern: the pattern to match.
    ///   - text: the text to read.
    /// - Returns: the first capture of each match, in match order.
    private static func firstCaptures(
        of pattern: Regex<AnyRegexOutput>,
        in text: String
    ) -> [String] {
        text.matches(of: pattern).compactMap { $0[1].substring.map(String.init) }
    }

    /// Reads each covered file and reports the ones that spell a removed
    /// name.
    ///
    /// This is a plain text read, and deliberately so. `declaredPackageNames()`
    /// reads the manifest's entries precisely because a doc comment naming a
    /// package is not a dependency on it; here the prose *is* the subject, so
    /// the comment naming it is exactly what must be caught.
    ///
    /// - Returns: `"<repository-relative path>: <names>"` for each offending
    ///   file, sorted by path.
    /// - Throws: an error when `Sources/` cannot be listed, or when a covered
    ///   file cannot be read.
    private static func filesSpellingARemovedRouterName() throws -> [String] {
        try coveredFiles()
            .compactMap { file in
                let text = try String(contentsOf: file, encoding: .utf8)
                let spelled = removedRouterNames.filter { text.contains($0) }
                guard !spelled.isEmpty else { return nil }
                return "\(repositoryRelativePath(of: file)): \(spelled.joined(separator: ", "))"
            }
            .sorted()
    }

    /// Lists the files the removed-name ban covers: the manifest, plus every
    /// regular file under `Sources/` at any depth.
    ///
    /// Directories are dropped rather than read; `Sources/` is nested, so the
    /// listing contains both.
    ///
    /// - Returns: the covered files.
    /// - Throws: an error when `Sources/` cannot be listed.
    private static func coveredFiles() throws -> [URL] {
        let fileManager = FileManager.default
        let sources = RepositoryFiles.root.appendingPathComponent(sourcesDirectoryName)
        let sourceFiles = try fileManager.subpathsOfDirectory(atPath: sources.path)
            .map { sources.appendingPathComponent($0) }
            .filter { file in
                var isDirectory: ObjCBool = false
                let exists = fileManager.fileExists(atPath: file.path, isDirectory: &isDirectory)
                return exists && !isDirectory.boolValue
            }
        return [RepositoryFiles.root.appendingPathComponent(manifestFileName)] + sourceFiles
    }

    /// Names a covered file the way the repository does, so a failure message
    /// points at a path a reader can open.
    ///
    /// - Parameter file: a file at or below the repository root.
    /// - Returns: the path relative to the repository root, or the absolute
    ///   path when the file lies outside it.
    private static func repositoryRelativePath(of file: URL) -> String {
        let rootPrefix = RepositoryFiles.root.path + "/"
        guard file.path.hasPrefix(rootPrefix) else { return file.path }
        return String(file.path.dropFirst(rootPrefix.count))
    }

    /// Reads `Package.swift` from the repository root.
    ///
    /// - Returns: the whole text of the manifest.
    /// - Throws: an error when the manifest cannot be read.
    private static func manifestText() throws -> String {
        try RepositoryFiles.text(at: manifestFileName)
    }
}
