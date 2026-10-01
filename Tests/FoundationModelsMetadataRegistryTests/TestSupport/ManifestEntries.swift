import Foundation

/// Reads the `.package(url:)` and `.product(name:package:)` entries of the
/// root `Package.swift` as text, with the manifest's own string constants
/// resolved.
///
/// `PackageManifestTests` pins the manifest through this reader. It reads the
/// entries, not the whole text, because a doc comment that names a package is
/// not a dependency on it, and a plain text search cannot tell the two apart.
enum ManifestEntries {
  /// One `.product(name:package:)` entry of the manifest, with each
  /// argument resolved to the string it holds.
  struct ProductEntry {
    /// The name of the product.
    let name: String

    /// The name of the package that supplies the product, or `nil` when
    /// the entry does not name a package.
    let package: String?
  }

  /// One `.product(name:package:)` entry of the manifest, with the target
  /// whose dependency list holds it.
  struct TargetProductEntry {
    /// The name of the target that names the product, or `nil` when the
    /// entry stands before the first target declaration of the manifest
    /// (in a helper function, for example).
    let target: String?

    /// The product entry, with its arguments resolved.
    let product: ProductEntry
  }

  /// One product entry of the manifest, with the place where it starts.
  private struct LocatedProductEntry {
    /// Where the entry starts in the text of the manifest.
    let start: String.Index

    /// The product entry, with its arguments resolved.
    let entry: ProductEntry
  }

  /// One target declaration of the manifest, with the place where it
  /// starts.
  private struct TargetDeclaration {
    /// Where the declaration starts in the text of the manifest.
    let start: String.Index

    /// The name of the target, with the manifest's constants resolved.
    let name: String
  }

  /// The manifest, relative to the repository root.
  static let manifestFileName = "Package.swift"

  /// The suffix a Git URL ends in, removed to read the package name.
  private static let gitURLSuffix = ".git"

  /// The character that starts and ends a string literal in the manifest.
  private static let quoteCharacter: Character = "\""

  /// The pattern of one argument of a manifest entry: a string literal
  /// with its quotes, or the name of a manifest constant. It captures the
  /// argument as one group.
  private static let argumentPattern = #"("[^"]*"|[A-Za-z_][A-Za-z0-9_]*)"#

  /// The capture group of a pattern that holds the first part of a match:
  /// the URL of a package entry, the name of a product entry, the name of
  /// a constant, or the name in an interpolation.
  private static let firstCaptureIndex = 1

  /// The capture group of a pattern that holds the second part of a match:
  /// the package of a product entry, or the value of a constant.
  private static let secondCaptureIndex = 2

  /// Reads the package name of every `.package(url:)` entry the manifest
  /// declares, in the order the manifest declares them.
  ///
  /// Each URL is a string literal that interpolates the manifest's own
  /// constants, so the constants are read first and substituted before the
  /// name is taken.
  ///
  /// - Returns: the package name of each declared dependency.
  /// - Throws: an error when the manifest cannot be read, or when a pattern
  ///   does not compile.
  static func packageNames() throws -> [String] {
    let text = try manifestText()
    let constants = try manifestConstants(in: text)
    let urlPattern = try Regex(#"\.package\(\s*url:\s*"([^"]+)""#)
    return try text.matches(of: urlPattern)
      .compactMap { capture(firstCaptureIndex, of: $0) }
      .map { url in try packageName(fromURL: expanded(url, with: constants)) }
  }

  /// Reads every `.product(name:package:)` entry the manifest declares, in
  /// the order the manifest declares them.
  ///
  /// Each argument is a string literal or the name of a manifest constant
  /// — the manifest's own `foundationModelsExtrasPackage`, for example.
  /// Both forms are resolved, so a product that the manifest names through
  /// a constant is read too.
  ///
  /// - Returns: each product entry, with its arguments resolved.
  /// - Throws: an error when the manifest cannot be read, or when a pattern
  ///   does not compile.
  static func productEntries() throws -> [ProductEntry] {
    let text = try manifestText()
    let constants = try manifestConstants(in: text)
    return try locatedProductEntries(in: text, with: constants).map(\.entry)
  }

  /// Reads every `.product(name:package:)` entry the manifest declares,
  /// each with the target whose dependency list holds it, in the order the
  /// manifest declares them.
  ///
  /// An entry belongs to the last target declaration that starts before
  /// it. A target declaration is `.target(`, `.testTarget(` or
  /// `.executableTarget(` with a `name:` argument that a comma follows. A
  /// dependency reference such as `.target(name: packageName)` closes its
  /// parenthesis after the name, so it does not start a declaration.
  ///
  /// - Returns: each product entry, with its arguments resolved, and the
  ///   name of its target.
  /// - Throws: an error when the manifest cannot be read, or when a pattern
  ///   does not compile.
  static func targetProductEntries() throws -> [TargetProductEntry] {
    let text = try manifestText()
    let constants = try manifestConstants(in: text)
    let declarations = try targetDeclarations(in: text, with: constants)
    return try locatedProductEntries(in: text, with: constants).map { located in
      let owner = declarations.last { $0.start < located.start }
      return TargetProductEntry(target: owner?.name, product: located.entry)
    }
  }

  /// Reads every `.product(name:package:)` entry of the manifest, with the
  /// place where each one starts.
  ///
  /// - Parameters:
  ///   - text: the whole text of the manifest.
  ///   - constants: the manifest's string constants.
  /// - Returns: each product entry, with its arguments resolved.
  /// - Throws: an error when a pattern does not compile.
  private static func locatedProductEntries(
    in text: String,
    with constants: [String: String],
  ) throws -> [LocatedProductEntry] {
    let entryPattern = try Regex(
      #"\.product\(\s*name:\s*"# + argumentPattern + #"(?:\s*,\s*package:\s*"# + argumentPattern
        + ")?",
    )
    return try text.matches(of: entryPattern).compactMap { match in
      guard let name = capture(firstCaptureIndex, of: match) else { return nil }
      let package = capture(secondCaptureIndex, of: match)
      let entry = try ProductEntry(
        name: resolved(name, with: constants),
        package: package.map { try resolved($0, with: constants) },
      )
      return LocatedProductEntry(start: match.range.lowerBound, entry: entry)
    }
  }

  /// Reads every target declaration of the manifest, with the place where
  /// each one starts.
  ///
  /// - Parameters:
  ///   - text: the whole text of the manifest.
  ///   - constants: the manifest's string constants.
  /// - Returns: each target declaration, with its name resolved, in the
  ///   order of the manifest.
  /// - Throws: an error when a pattern does not compile.
  private static func targetDeclarations(
    in text: String,
    with constants: [String: String],
  ) throws -> [TargetDeclaration] {
    let declarationPattern = try Regex(
      #"\.(?:target|testTarget|executableTarget)\(\s*name:\s*"# + argumentPattern + #"\s*,"#,
    )
    return try text.matches(of: declarationPattern).compactMap { match in
      guard let name = capture(firstCaptureIndex, of: match) else { return nil }
      return try TargetDeclaration(
        start: match.range.lowerBound, name: resolved(name, with: constants))
    }
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
      guard let name = capture(firstCaptureIndex, of: match),
        let value = capture(secondCaptureIndex, of: match)
      else { continue }
      constants[name] = value
    }
    return constants
  }

  /// Resolves one argument of a manifest entry to the string it holds.
  ///
  /// - Parameters:
  ///   - argument: a string literal with its quotes, or the name of a
  ///     manifest constant.
  ///   - constants: the manifest's string constants.
  /// - Returns: the text of the literal with its interpolations
  ///   substituted, or the value of the constant. A constant that the
  ///   manifest does not declare is returned as written.
  /// - Throws: an error when the interpolation pattern does not compile.
  private static func resolved(
    _ argument: String,
    with constants: [String: String],
  ) throws -> String {
    guard argument.first == quoteCharacter else { return constants[argument] ?? argument }
    return try expanded(String(argument.dropFirst().dropLast()), with: constants)
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
    with constants: [String: String],
  ) throws -> String {
    let interpolationPattern = try Regex(#"\\\(([A-Za-z_][A-Za-z0-9_]*)\)"#)
    var expandedText = ""
    var readFrom = literal.startIndex
    for match in literal.matches(of: interpolationPattern) {
      expandedText += literal[readFrom..<match.range.lowerBound]
      let name = capture(firstCaptureIndex, of: match) ?? ""
      expandedText += constants[name] ?? String(literal[match.range])
      readFrom = match.range.upperBound
    }
    expandedText += literal[readFrom...]
    return expandedText
  }

  /// Reads one capture group of a match.
  ///
  /// - Parameters:
  ///   - index: the number of the capture group.
  ///   - match: a match of a manifest pattern.
  /// - Returns: the text of the capture group, or `nil` when the group
  ///   did not take part in the match.
  private static func capture(_ index: Int, of match: Regex<AnyRegexOutput>.Match) -> String? {
    match[index].substring.map(String.init)
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

  /// Reads `Package.swift` from the repository root.
  ///
  /// - Returns: the whole text of the manifest.
  /// - Throws: an error when the manifest cannot be read.
  private static func manifestText() throws -> String {
    try RepositoryFiles.text(at: manifestFileName)
  }
}
