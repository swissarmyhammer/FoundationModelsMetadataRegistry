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
/// The suite pins the `dependencies:` list itself for the same reason. Since
/// plan.md decision #16 (2026-09-26), the library is built over two packages:
/// FoundationModelsRanker and FoundationModelsExtras. The manifest declares
/// these two packages and no other. A later edit that adds one of the
/// live-Router packages back fails this suite too.
///
/// The two entries are not the whole resolved graph. FoundationModelsExtras
/// declares its own dependencies, and SwiftPM resolves all of them. So the
/// suite also pins the products: of the FoundationModelsExtras package, the
/// manifest names the core `FoundationModelsExtras` product only. That
/// product compiles Stencil, Yams, ULID.swift and swift-distributed-tracing,
/// which the user accepted. The other products (`Operations`,
/// `OperationsCLI`, `Marketplace`) compile swift-syntax,
/// swift-argument-parser or libgit2, which the registry must not compile.
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

    /// The package that supplies the retrieval and selection tiers.
    private static let rankerPackageName = "FoundationModelsRanker"

    /// The package that supplies the process-wide model pool (plan.md
    /// decision #16).
    private static let extrasPackageName = "FoundationModelsExtras"

    /// The packages this library depends on, and no other (plan.md decision
    /// #16).
    private static let allowedPackageNames = [rankerPackageName, extrasPackageName]

    /// The one product of the FoundationModelsExtras package that the
    /// manifest may name: the core product, which holds the model pool.
    ///
    /// Its name is the same text as `extrasPackageName`, but it is a product
    /// name, not a package name, so it has its own constant.
    private static let extrasCoreProductName = "FoundationModelsExtras"

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
            """,
        )
    }

    @Test("Package.swift declares none of the removed dependencies")
    func declaresNoRemovedDependency() throws {
        let named = try Set(ManifestEntries.packageNames() + Self.productPackageNames())
        let removed = named.intersection(Self.removedPackageNames).sorted()
        #expect(
            removed.isEmpty,
            """
            Package.swift must declare none of the packages the live-Router path needed — no \
            target names one any more; found: \(removed)
            """,
        )
    }

    /// Reads the manifest, never `Package.resolved`: the resolution file is
    /// in `.gitignore`, so a fresh clone and CI have none to read.
    ///
    /// The two entries are not the whole resolved graph, because
    /// FoundationModelsExtras declares its own dependencies.
    /// `namesOnlyTheCoreExtrasProduct()` pins the part of that graph that
    /// the build compiles.
    @Test("Package.swift depends on FoundationModelsRanker and FoundationModelsExtras and nothing else")
    func dependsOnTheRankerAndExtrasAlone() throws {
        let declared = try ManifestEntries.packageNames()
        #expect(
            declared.sorted() == Self.allowedPackageNames.sorted(),
            """
            Package.swift must declare exactly the dependencies \(Self.allowedPackageNames) \
            (plan.md decision #16); found: \(declared)
            """,
        )
    }

    /// Reads each `.product(name:package:)` entry with its constants
    /// resolved, so an entry that names a product through a manifest
    /// constant is read too.
    @Test("Package.swift names FoundationModelsExtras as the only product of the FoundationModelsExtras package")
    func namesOnlyTheCoreExtrasProduct() throws {
        let extrasProducts = try ManifestEntries.productEntries()
            .filter { $0.package == Self.extrasPackageName }
            .map(\.name)
        #expect(
            Set(extrasProducts) == [Self.extrasCoreProductName],
            """
            Package.swift must name \(Self.extrasCoreProductName) as the only product of the \
            \(Self.extrasPackageName) package — the other products compile swift-syntax, \
            swift-argument-parser or libgit2 (plan.md decision #16); found: \(extrasProducts)
            """,
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
            """,
        )
    }

    /// Reads every product `Package.swift` names in a target's dependency
    /// list.
    ///
    /// - Returns: the set of product names the manifest names, with its
    ///   constants resolved.
    /// - Throws: an error when the manifest cannot be read, or when a pattern
    ///   does not compile.
    private static func declaredProductNames() throws -> Set<String> {
        try Set(ManifestEntries.productEntries().map(\.name))
    }

    /// Reads the package name of every `.product(package:)` entry the
    /// manifest declares.
    ///
    /// A product entry names its package, so it is a second place a removed
    /// dependency could survive: a product entry alone is what marked the
    /// swift-jinja pin as used.
    ///
    /// - Returns: the package name of each product entry that names one,
    ///   with the manifest's constants resolved.
    /// - Throws: an error when the manifest cannot be read, or when a pattern
    ///   does not compile.
    private static func productPackageNames() throws -> [String] {
        try ManifestEntries.productEntries().compactMap(\.package)
    }

    /// Reads each covered file and reports the ones that spell a removed
    /// name.
    ///
    /// This is a plain text read, and deliberately so. `ManifestEntries`
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
        return [RepositoryFiles.root.appendingPathComponent(ManifestEntries.manifestFileName)] + sourceFiles
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
}
