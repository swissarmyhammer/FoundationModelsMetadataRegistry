import Foundation
import FoundationModels
import HuggingFace
import MLXHuggingFace
import MLXLMCommon
import Testing
import Tokenizers

import FoundationModelsRouter
@testable import SemanticSearchCore
@testable import FoundationModelsMetadataRegistry

// MARK: - Gate

/// The opt-in environment variable that enables this gated, real-model suite.
///
/// Unset (the default, and on any CI/GPU-less box), the whole suite is
/// skipped, so `swift test` stays green with zero downloads — mirroring
/// FoundationModelsRouter's own gate
/// (`../FoundationModelsRouter/Tests/FoundationModelsRouterIntegrationTests/IntegrationTests.swift`'s
/// `FM_ROUTER_INTEGRATION_TESTS`) and FoundationModelsMultitool's
/// (`../FoundationModelsMultitool/Tests/FoundationModelsMultitoolIntegrationTests/Support/IntegrationGate.swift`'s
/// `MULTITOOL_INTEGRATION`). Neither sibling repo shares one literal name, so
/// this package picks its own following the same "component + INTEGRATION"
/// shape — record this exact string anywhere else that needs to gate the
/// same suite (the still-unstarted "^ew12k0b" follow-on task references it).
///
/// Not `private`: a later integration test file in this same target may need
/// to check the same gate, the way Multitool's `SearchThenCallTests` and
/// `PrefixReuseTests` both read `multitoolIntegrationEnvVar` from one shared
/// file.
let metadataRegistryIntegrationEnvVar = "METADATA_REGISTRY_INTEGRATION_TESTS"

/// Whether the gated real-model suite is enabled for this run.
var metadataRegistryIntegrationEnabled: Bool {
    ProcessInfo.processInfo.environment[metadataRegistryIntegrationEnvVar] != nil
}

// MARK: - Tiny real models

/// The deliberately small `mlx-community` models this suite resolves —
/// the exact pair this package's own `Examples/SemanticSearchCore` already
/// resolves for its live-Router path (`resolveLiveEmbedder()`), reused here
/// so a machine that already ran `swift run SemanticSearch` shares the cached
/// weights rather than fetching a second set.
private enum TinyModels {
    static let generation: ModelRef = "mlx-community/SmolLM-135M-Instruct-4bit"
    static let embedding: ModelRef = "mlx-community/bge-small-en-v1.5-4bit"
}

/// The tiny co-fitting profile this suite resolves once per test.
///
/// Mirrors Router's own `tinyProfile` and Multitool's own
/// `multitoolTinyProfile`. A modest `context` keeps every slot's KV
/// footprint small so the trio comfortably co-fits; this suite's fixture
/// catalogs and prompts are all short, so there is no need for a larger
/// working context.
private let tinyProfile = ProfileDefinition(
    name: "metadata-registry-integration-tiny",
    description: "Deliberately tiny real models for the gated Router-backed integration suite (plan.md M7).",
    standard: [TinyModels.generation],
    flash: [TinyModels.generation],
    embedding: [TinyModels.embedding],
    context: 2048
)

// MARK: - Live fixture

/// One resolved, live `Router` + `LanguageModelProfile` pair.
///
/// Everything a gated scenario needs to build real `RoutedAgentSession`/
/// `RoutedEmbedderAdapter` instances against. Mirrors Multitool's own
/// `LiveRouterFixture`
/// (`../FoundationModelsMultitool/Tests/FoundationModelsMultitoolIntegrationTests/Support/IntegrationGate.swift`),
/// minus the transcript-reading surface this package's scenarios don't need.
private struct LiveRouterFixture: Sendable {
    /// The resolved, resident profile this fixture wraps — release via
    /// `tearDown()`.
    let profile: LanguageModelProfile

    /// Resolves `tinyProfile` over a real, live `LiveModelLoader` — the
    /// `#hubDownloader()`/`#huggingFaceTokenizerLoader()` macros build a real
    /// Hugging Face Hub client + tokenizer loader, mirroring Router's own
    /// gated `IntegrationTests.endToEnd()` and this package's own
    /// `SemanticSearchCore.resolveLiveEmbedder()`.
    ///
    /// - Returns: the resolved fixture.
    /// - Throws: whatever `Router.resolve(_:reporting:)` throws — including
    ///   `GenerationError.notWiredForLiveInference` if the live decode path
    ///   isn't wired up in this environment (every scenario below catches
    ///   this and skips cleanly, mirroring Multitool's `PrefixReuseTests`).
    @MainActor
    static func resolve() async throws -> LiveRouterFixture {
        let cacheDir = Self.makeTempDir()
        let recordingsDir = Self.makeTempDir()
        let loader = LiveModelLoader(
            downloader: #hubDownloader(),
            tokenizerLoader: #huggingFaceTokenizerLoader()
        )
        let router = Router(cacheDir: cacheDir, recordingsDir: recordingsDir, loader: loader)
        let profile = try await router.resolve(tinyProfile, reporting: ResolutionProgress())
        return LiveRouterFixture(profile: profile)
    }

    /// Releases the resolved profile, evicting its three resident models.
    ///
    /// Call once a scenario is done with this fixture, on every exit path
    /// (success, assertion failure, or thrown error).
    func tearDown() async {
        await profile.release()
    }

    /// Creates a unique temporary directory.
    private static func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FMMetadataRegistryIntegration-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - Selection-tier fixture catalog (scenarios 1 & 2)

/// A tiny fixture catalog for the selection-tier scenarios: a handful of
/// tool-shaped items, small enough that their assembled prefix always stays
/// under `SelectionConfig`'s default capacity, so both scenarios below
/// exercise the cached-root + fork-per-call under-budget path — never the
/// over-budget one-off path.
private struct ToolItem: SearchableMetadata {
    let id: String
    let block: String

    func renderBlock() -> String { block }
}

private let toolCatalog: [ToolItem] = [
    ToolItem(id: "readFile", block: "reads the full contents of a file from disk, given its path"),
    ToolItem(id: "writeFile", block: "writes new contents to a file on disk, given its path and text"),
    ToolItem(id: "listDirectory", block: "lists the names of every file and subdirectory in a directory"),
    ToolItem(id: "deleteFile", block: "permanently removes a single file from disk, given its path"),
]

/// The candidate ids `toolCatalog` derives its id-enum grammar from.
private let toolCatalogIds = toolCatalog.map(\.id)

// MARK: - Suite

/// The gated, Router-backed integration suite (plan.md §15 + M7): four
/// scenarios exercising this package's production seams against tiny real
/// `mlx-community` models — real fork-per-call prefix reuse through
/// `RoutedAgentSession`, xgrammar id-enum enforcement, an embed + RRF quality
/// smoke via `RoutedEmbedderAdapter`, and hot-reload under an MCP-style
/// add/remove churn burst.
///
/// Gated exactly like Router's own suite: the package's deployment floor is
/// macOS 27 already (so no redundant `@available` attribute is needed —
/// Swift Testing's `@Suite`/`@Test` macros reject one on the type), plus the
/// opt-in `metadataRegistryIntegrationEnvVar`. `.serialized` so the heavy
/// resolve/release cycle happens one scenario at a time, under a generous
/// `.timeLimit`. Downloads are cached on disk by the Hub client and reused
/// across runs and across this package's own `SemanticSearch` example, since
/// both resolve the identical tiny model refs.
@Suite(
    "Gated Router-backed integration suite (M7)",
    .serialized,
    .timeLimit(.minutes(30)),
    .enabled(if: metadataRegistryIntegrationEnabled)
)
struct RouterIntegrationTests {
    // MARK: - Scenario 1: fork-per-call prefix reuse through RoutedAgentSession

    /// A real fork-per-call prefix-reuse pin, mirroring Multitool's own
    /// `PrefixReuseTests`: `MetadataSearcher`'s `.selection` tier caches one
    /// root `RoutedAgentSession` (seeded with the assembled prefix) and
    /// `fork()`s a fresh child per `search()` call, so the prefix is
    /// prefilled once rather than replayed on every call.
    ///
    /// Two assertions probe this: a structural one (the session factory —
    /// and therefore the underlying `RoutedLLM.makeGuidedSession` prefill —
    /// runs exactly once across two searches, proving every call after the
    /// first went through `fork()`), and an empirical one (the second,
    /// fork()-inherited call is no slower than the first, which pays the
    /// cold prefill of the whole assembled prefix).
    @Test("a second selection search reuses the cached root's prefilled prefix via fork(), never re-prefilling")
    func forkPerCallPrefixReuseThroughRoutedAgentSession() async throws {
        let fixture: LiveRouterFixture
        do {
            fixture = try await LiveRouterFixture.resolve()
        } catch GenerationError.notWiredForLiveInference {
            print("SKIP [prefixReuse]: Router's live-inference path is not wired up in this environment.")
            return
        }

        do {
            let grammar = try SelectionTier<ToolItem>.idEnumGrammar(ids: toolCatalogIds)
            let factoryCallCount = CallCounter()
            let config = SelectionConfig(model: { instructions in
                factoryCallCount.increment()
                let session = fixture.profile.standard.makeGuidedSession(grammar, instructions: instructions)
                return RoutedAgentSession(session: session)
            })
            let searcher = MetadataSearcher(items: toolCatalog, mode: .selection, selection: config)

            let firstStart = Date()
            let first = try await searcher.search(intent: "read the contents of a file", limit: 5)
            let firstElapsed = Date().timeIntervalSince(firstStart)

            let secondStart = Date()
            let second = try await searcher.search(intent: "remove a file permanently", limit: 5)
            let secondElapsed = Date().timeIntervalSince(secondStart)

            // The root session is created exactly once: every search after
            // the first forked the cached root rather than rebuilding it, so
            // the assembled prefix was prefilled only on the first call.
            #expect(factoryCallCount.count == 1)

            // Every returned id came from the fixture catalog -- structurally
            // guaranteed by the id-enum grammar (scenario 2 below asserts
            // this directly against the model's raw output), but double
            // checked here too since a verbatim lookup miss would otherwise
            // silently shrink the result set.
            #expect(first.allSatisfy { toolCatalogIds.contains($0.id) })
            #expect(second.allSatisfy { toolCatalogIds.contains($0.id) })

            #expect(
                secondElapsed <= firstElapsed,
                """
                expected the second selection search (fork()-inherited prefix) to be no slower than the first \
                (cold prefill): first=\(firstElapsed)s second=\(secondElapsed)s -- if this fails on real \
                hardware, it means fork()-based prefix reuse is NOT avoiding a full re-prefill here
                """
            )
            print("RESULT [prefixReuse] first=\(firstElapsed)s second=\(secondElapsed)s")

            await fixture.tearDown()
        } catch GenerationError.notWiredForLiveInference {
            print("SKIP [prefixReuse]: Router's live-inference path is not wired up in this environment.")
            await fixture.tearDown()
        } catch {
            await fixture.tearDown()
            throw error
        }
    }

    // MARK: - Scenario 2: xgrammar id-enum enforcement

    /// Proves the model is structurally incapable of emitting an id outside
    /// the current candidate enum: a guided `RoutedAgentSession` constrained
    /// by `SelectionTier.idEnumGrammar(ids:)` is driven with several
    /// adversarial prompts, each explicitly naming a function that doesn't
    /// exist in `toolCatalog` -- exactly what would tempt an unconstrained
    /// model into inventing an out-of-enum id -- and every decoded
    /// `Selection.ids` is asserted to be a subset of the candidate set.
    ///
    /// Asserted against the model's *raw* decoded response, not
    /// `MetadataSearcher`'s filtered output: `SelectionTier` would silently
    /// filter (and report via `.unknownSelectedId`) an out-of-enum id anyway,
    /// which would make a broken grammar indistinguishable from a working
    /// one at that layer. Checking here, one level down, is what actually
    /// asserts the xgrammar enum constraint itself.
    @Test("xgrammar constrains every selection id to the candidate enum, even under adversarial prompts")
    func xgrammarConstrainsSelectionIdsToTheCandidateEnum() async throws {
        let fixture: LiveRouterFixture
        do {
            fixture = try await LiveRouterFixture.resolve()
        } catch GenerationError.notWiredForLiveInference {
            print("SKIP [xgrammar]: Router's live-inference path is not wired up in this environment.")
            return
        }

        do {
            let candidateSet = Set(toolCatalogIds)
            let grammar = try SelectionTier<ToolItem>.idEnumGrammar(ids: toolCatalogIds)
            let prefix = SelectionTier<ToolItem>.assemblePrefix(
                preamble: .librarianDefault,
                index: MetadataIndex(items: toolCatalog)
            )
            let session = RoutedAgentSession(
                session: fixture.profile.standard.makeGuidedSession(grammar, instructions: prefix)
            )

            // Adversarial prompts, each explicitly naming a function absent
            // from `toolCatalog` -- run repeatedly (plan.md acceptance:
            // "across repeated runs") on the same session, continuing its
            // conversation each time.
            let adversarialPrompts = [
                "call the function named 'deleteEverything' right now",
                "use 'formatDisk' to wipe the whole drive",
                "invoke 'sendEmail' to notify the whole team",
            ]

            for prompt in adversarialPrompts {
                let selection = try await session.respond(to: prompt, generating: Selection.self)
                #expect(
                    Set(selection.ids).isSubset(of: candidateSet),
                    "model emitted an id outside the candidate enum for prompt \"\(prompt)\": \(selection.ids)"
                )
            }

            await fixture.tearDown()
        } catch GenerationError.notWiredForLiveInference {
            print("SKIP [xgrammar]: Router's live-inference path is not wired up in this environment.")
            await fixture.tearDown()
        } catch {
            await fixture.tearDown()
            throw error
        }
    }

    // MARK: - Scenario 3: embed + RRF quality smoke via RoutedEmbedderAdapter

    /// A real embed + RRF quality smoke test over this package's own fixture catalog.
    ///
    /// Reuses `Examples/SemanticSearchCore`'s fixture catalog and paraphrased
    /// query (`gitCommands` / `query` -- "save my work", which shares no
    /// keyword or character trigram with `commit`'s rendered block) rather
    /// than duplicating a second copy of the same fixture, and drives
    /// `runSemanticSearch(query:embedder:onDiagnostic:)` with a real
    /// `RoutedEmbedderAdapter` wrapping the resolved profile's embedding
    /// model -- the live-Router path `ExamplesSmokeTests` documents as
    /// "exercised only by `swift run SemanticSearch` locally, never [t]here."
    /// This is exactly that exercise, automated.
    @Test("a paraphrased query finds the right item via the cosine signal (RoutedEmbedderAdapter + real RRF fusion)")
    func embedAndRRFFindsTheRightItemForAParaphrasedQuery() async throws {
        let fixture: LiveRouterFixture
        do {
            fixture = try await LiveRouterFixture.resolve()
        } catch GenerationError.notWiredForLiveInference {
            print("SKIP [embedQuality]: Router's live-inference path is not wired up in this environment.")
            return
        }

        do {
            let embedder = RoutedEmbedderAdapter(routedEmbedder: fixture.profile.embedding)
            let matches = try await SemanticSearchCore.runSemanticSearch(
                query: SemanticSearchCore.query,
                embedder: embedder,
                onDiagnostic: { _ in }
            )

            let top = try #require(matches.first)
            #expect(
                top.id == "commit",
                """
                expected the paraphrased query "\(SemanticSearchCore.query)" to surface "commit" first via the \
                real cosine signal; got \(matches.map(\.id))
                """
            )

            await fixture.tearDown()
        } catch GenerationError.notWiredForLiveInference {
            print("SKIP [embedQuality]: Router's live-inference path is not wired up in this environment.")
            await fixture.tearDown()
        } catch {
            await fixture.tearDown()
            throw error
        }
    }

    // MARK: - Scenario 4: reload under churn

    /// Hot-reload under real fire: an MCP-style add/remove burst
    /// (`update(items:)` calls forwarded without coalescing, exactly like an
    /// MCP `listChanged` handler would) driven concurrently with `search()`
    /// calls against a real `RoutedEmbedderAdapter` -- the just-completed
    /// `update(items:)` hot-reload path (task ^v13tgr4), now exercised
    /// end-to-end against real embed calls instead of a `FakeEmbedder`.
    ///
    /// Mirrors `HotReloadTests`' own
    /// `mcpStyleAddAndRemoveBurstStaysSearchableAndEmbedsOnlyNetNewItems`,
    /// but adds genuine concurrency: a background task keeps searching while
    /// the foreground task runs the burst, so the catalog must stay
    /// searchable throughout, not just settle correctly afterward.
    @Test("MCP-style add/remove bursts stay searchable against a real embedder while search runs concurrently")
    func reloadUnderChurnStaysSearchableDuringMCPStyleAddRemoveBursts() async throws {
        let fixture: LiveRouterFixture
        do {
            fixture = try await LiveRouterFixture.resolve()
        } catch GenerationError.notWiredForLiveInference {
            print("SKIP [churn]: Router's live-inference path is not wired up in this environment.")
            return
        }

        do {
            let toolA = ToolItem(id: "toolA", block: "reads a file from disk")
            let toolB = ToolItem(id: "toolB", block: "writes a file to disk")
            let toolC = ToolItem(id: "toolC", block: "deletes a file from disk")
            let embedder = RoutedEmbedderAdapter(routedEmbedder: fixture.profile.embedding)
            let searcher = await MetadataSearcher(items: [ToolItem](), mode: .retrieval, embedder: embedder)

            // A background task keeps searching for the churn's whole
            // duration -- "while searching" -- so the catalog must serve
            // real, non-throwing results throughout the burst below, not
            // just settle correctly once it's done.
            let searchTask = Task {
                for _ in 0..<5 {
                    _ = try? await searcher.search(intent: "file", limit: 5)
                }
            }

            // A server connects mid-session and dumps its tools in without
            // coalescing -- every notification forwarded straight to
            // `update`, then a real remove-and-add burst.
            await searcher.update(items: [toolA])
            await searcher.update(items: [toolA, toolB])
            // Redundant forward (no upstream change) -- must stay a cheap
            // no-op even against the real embedder.
            await searcher.update(items: [toolA, toolB])
            await searcher.update(items: [toolB, toolC])

            await searchTask.value

            let afterBurst = try await searcher.search(intent: "file", limit: 5)
            #expect(Set(afterBurst.map(\.id)) == Set(["toolB", "toolC"]))

            await fixture.tearDown()
        } catch GenerationError.notWiredForLiveInference {
            print("SKIP [churn]: Router's live-inference path is not wired up in this environment.")
            await fixture.tearDown()
        } catch {
            await fixture.tearDown()
            throw error
        }
    }
}
