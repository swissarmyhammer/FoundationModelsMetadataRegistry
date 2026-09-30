import Foundation
import FoundationModels
import FoundationModelsMetadataRegistry

/// Stops the process with a message when the on-device Apple Intelligence
/// model cannot answer, for example on a Mac where Apple Intelligence is off.
///
/// The selection examples call this first, so that a missing model gives
/// one clear line, not an error from deep in a search.
public func requireSystemLanguageModel() {
    let availability = SystemLanguageModel.default.availability
    guard availability != .available else { return }
    FileHandle.standardError.write(
        Data("This example needs the on-device Apple Intelligence model, which is not available: \(availability)\n".utf8),
    )
    exit(1)
}

/// Makes a selection configuration whose sessions are real sessions of the
/// on-device Apple Intelligence model.
///
/// `LanguageModelSession` conforms to `AgentSession`, so the factory gives
/// the selection tier a new session with the instructions that the tier
/// makes from the catalog.
///
/// - Parameter capacityCharacterLimit: the character limit of the catalog
///   prefix. When the prefix is larger, the searcher divides the catalog
///   into runs and prompts one session for each run. Defaults to
///   `SelectionConfig.defaultCapacityCharacterLimit`.
/// - Returns: the selection configuration.
public func exampleSelectionConfig(
    capacityCharacterLimit: Int = SelectionConfig.defaultCapacityCharacterLimit,
) -> SelectionConfig {
    SelectionConfig(
        model: { instructions in LanguageModelSession(model: .default, instructions: instructions) },
        // The example catalogs are tool catalogs, so use the librarian
        // prompt text.
        preamble: .librarianDefault,
        capacityCharacterLimit: capacityCharacterLimit,
    )
}
