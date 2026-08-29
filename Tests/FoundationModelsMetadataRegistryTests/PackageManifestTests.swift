import Foundation
import Testing

/// Pins `Package.swift` to a Router-free, GPU-free shape: no target of this
/// package may name an MLX or Hugging Face product.
///
/// Those products exist to resolve a live `Router` + `LiveModelLoader`, and
/// the only code that still needs one is the real-model integration suite in
/// the nested `IntegrationTests/` package, which declares them in its own
/// manifest. Carrying them here instead links MLX and Hugging Face into every
/// `Examples/` demo — and, through the test target, into a plain
/// `swift build --build-tests` — for a capability the unit-tested code never
/// exercises.
///
/// A later edit that re-adds one of those products to a target fails this
/// suite. The right place for it is `IntegrationTests/Package.swift`.
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

    @Test("Package.swift names no MLX or Hugging Face product")
    func namesNoLiveRouterProduct() throws {
        let declared = try Self.declaredProductNames()
        let live = declared.intersection(Self.liveRouterProductNames).sorted()
        #expect(
            live.isEmpty,
            """
            Package.swift must name no MLX or Hugging Face product — they belong to the nested \
            IntegrationTests package, which declares them in its own manifest; found: \(live)
            """
        )
    }

    /// Reads every product `Package.swift` names in a target's dependency
    /// list, resolving the manifest relative to this source file's own path
    /// (`#filePath` is
    /// `Tests/FoundationModelsMetadataRegistryTests/PackageManifestTests.swift`,
    /// two directories below the root).
    ///
    /// Only literal names are read. A `.product(name:)` entry spelled with a
    /// constant — the manifest's own `routerDependencyName`, say — resolves at
    /// manifest-evaluation time and is invisible to a text read, so a
    /// forbidden product smuggled in behind a constant would pass. `swift
    /// build` is the backstop there: nothing in this package imports one.
    ///
    /// - Returns: the set of product names the manifest spells out.
    /// - Throws: an error when the manifest cannot be read, or when the
    ///   pattern does not compile.
    private static func declaredProductNames() throws -> Set<String> {
        let manifest = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/FoundationModelsMetadataRegistryTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repository root
            .appendingPathComponent("Package.swift")
        let text = try String(contentsOf: manifest, encoding: .utf8)
        let productPattern = try Regex(#"\.product\(\s*name:\s*"([^"]+)""#)
        return Set(text.matches(of: productPattern).compactMap { $0[1].substring.map(String.init) })
    }
}
