---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3mr2q7hmkg0asxwt13qx4kb
  text: |-
    Research (2026-09-28):
    - The two Extras items are NOT pushed. In /Users/wballard/github/swissarmyhammer/FoundationModelsExtras, local `main` is 2 commits ahead of `origin/main`: a61bbb0 (^65xmgkv, swift-log and swift-metrics in the core target) and 9b97617 (^z6jqd9g, the `TelemetryTestSupport` product). `git ls-remote origin main` gives 4a733cd, which has neither. On the Extras board, ^65xmgkv is in `done` and ^z6jqd9g is in `doing`. Thus `swift package update FoundationModelsExtras` cannot get them, and this task does not run it.
    - The version floors that ^65xmgkv uses: swift-log `from: "1.15.1"`, swift-metrics `from: "2.11.0"`. Extras declares swift-distributed-tracing `from: "1.4.1"`; the checkout here is 1.5.0.
    - `ManifestEntries` reads product entries without their target. The new per-target rule for Extras products needs the owner target of each `.product(...)` entry. A target declaration is `.target(`/`.testTarget(`/`.executableTarget(` with `name: X,` (a comma after the name). A dependency reference `.target(name: X)` has `)` after the name, so the two are different.
    - Periphery reports a declaration that nothing references. The empty nested enums of `RegistryTelemetry` need `// periphery:ignore` (with the reason on the line above) until tasks A, B and C add names.
    - swift-distributed-tracing 1.5.0 has `withTracer(_:_:)` (task-local tracer), and `InMemoryTracer` is a struct in the `InMemoryTracing` product. A test of `tracer(explicit:)` can use them without a global bootstrap.
  timestamp: 2026-09-28T19:32:44.401425+00:00
- actor: claude-code
  id: 01m3mrz1j97xe6mk6wyev8c0cz
  text: |-
    Implementation (the parts that do not need the Extras telemetry items):
    - `Package.swift`: declares swift-distributed-tracing (`from: "1.5.0"`), swift-log (`from: "1.15.1"`) and swift-metrics (`from: "2.11.0"`), with package-name constants and "API only, no backend" doc comments. The library target links `Tracing`, `Logging` and `Metrics`. The test target links `Tracing` and `InMemoryTracing` for `RegistryTelemetryTests`. The swift-log and swift-metrics floors are the floors of ^65xmgkv. The swift-distributed-tracing floor is 1.5.0 (Extras declares 1.4.1), because the tests use `withTracer(_:_:)`, which 1.5.0 adds.
    - `TestSupport/ManifestEntries.swift`: new `targetProductEntries()` gives each `.product(...)` entry with its owner target. It shares one located-entry reader with `productEntries()`.
    - `PackageManifestTests.swift`: five allowed packages; new `linksTheTelemetryAPIs()`; `namesOnlyTheCoreExtrasProduct()` is per target (the test target may also name `TelemetryTestSupport`, and the library target must name the core product); new `namesNoSwiftOTelProduct()`; `dependsOnTheRankerAndExtrasAlone()` is renamed `dependsOnTheAllowedPackagesAlone()`; the suite doc comment is updated.
    - `Sources/.../Telemetry/RegistryTelemetry.swift`: `namePrefix`, `loggerLabel` (`FoundationModelsMetadataRegistry.MetadataDiagnostic`), empty `SpanName`, `AttributeKey`, `MetricName`, `MetadataKey` (each with `// periphery:ignore` and the reason on the line above), `tracer(explicit:)`, and the "no content" rule in the doc comment.
    - `RegistryTelemetryTests.swift`: tests for the explicit tracer and for the task-local tracer (resolve late).
    - `TelemetryContentSafetyTests.swift`: holds the prefix test only (`registryNames` lists each name; tasks A, B and C add their names to that list).

    TDD evidence: the new manifest tests failed first (missing packages and products); a stub `RegistryTelemetry` made the 3 telemetry tests fail; then all passed. Mutation check: a `TelemetryTestSupport` entry in the library target and an `OTel` entry in `ExamplesSupport` each made the matching test fail with the right target name; a `TelemetryTestSupport` entry in the test target passed. The mutations are removed.

    `swift test`: 166 tests in 19 suites passed. The only warnings are the "failed loading cached manifest ... disk I/O error" warnings of the SwiftPM manifest cache of this machine (30 lines). They were there before this change, and they come from no source file.
  timestamp: 2026-09-28T19:48:12.489501+00:00
- actor: claude-code
  id: 01m3mrz6mpq5j9khdddxmbqx6x
  text: |-
    BLOCKER: the missing Extras item is ^z6jqd9g (01M3MN8N9P4RPET2V5JZ6JQD9G), the `TelemetryTestSupport` product with `TelemetryCapture`. On 2026-09-28, `git ls-remote origin main` of FoundationModelsExtras gives 4a733cd. That commit has neither ^65xmgkv (local commit a61bbb0) nor ^z6jqd9g (local commit 9b97617). Both commits are only on the local `main` of /Users/wballard/github/swissarmyhammer/FoundationModelsExtras, and ^z6jqd9g is still in `doing` on the Extras board. Thus `swift package update FoundationModelsExtras` cannot get them, and this task did not run it.

    Open work, blocked until ^z6jqd9g (and ^65xmgkv) are pushed to `origin/main`:
    1. Run `swift package update FoundationModelsExtras`.
    2. Add `.product(name: "TelemetryTestSupport", package: foundationModelsExtrasPackage)` to the test target of `Package.swift`. `PackageManifestTests` already permits it there.
    3. Add the content-safety test to `TelemetryContentSafetyTests.swift` with `TelemetryCapture.run(forbidding:)` over the entry points that the card lists.
    No local copy or stand-in of `TelemetryCapture` was written.
  timestamp: 2026-09-28T19:48:17.686957+00:00
- actor: claude-code
  id: 01m3mrzbp6b09mt30j3bz31mrq
  text: |-
    ### implement — stuck
    - evidence: 6 files — Package.swift, Sources/FoundationModelsMetadataRegistry/Telemetry/RegistryTelemetry.swift (new), Tests/FoundationModelsMetadataRegistryTests/PackageManifestTests.swift, Tests/FoundationModelsMetadataRegistryTests/TestSupport/ManifestEntries.swift, Tests/FoundationModelsMetadataRegistryTests/RegistryTelemetryTests.swift (new), Tests/FoundationModelsMetadataRegistryTests/TelemetryContentSafetyTests.swift (new, prefix test only). `swift test`: 166 tests in 19 suites passed, no new warnings. Missing dependency: ^z6jqd9g (`TelemetryTestSupport` / `TelemetryCapture`) is not on `origin/main` of FoundationModelsExtras (4a733cd).
    - next: when ^z6jqd9g and ^65xmgkv are on `origin/main` of FoundationModelsExtras, run `swift package update FoundationModelsExtras`, add `TelemetryTestSupport` to the test target, and write the content-safety test. Then review.
  timestamp: 2026-09-28T19:48:22.854061+00:00
- actor: claude-code
  id: 01m3ms01ctxpw3v33f6y12ek1t
  text: |-
    ### finish iteration 1 — stuck
    - implement: stuck — 6 files changed; swift test 166 passed in 19 suites. FoundationModelsExtras ^65xmgkv (a61bbb0) and ^z6jqd9g (9b97617) are not on Extras origin/main (4a733cd). TelemetryTestSupport / TelemetryCapture is not available.
    - test: not run
    - commit: not run — the changes stay uncommitted in the working tree
    - review: not run
    - next: push the two Extras commits, then run `swift package update FoundationModelsExtras`, add TelemetryTestSupport to the test target, and write the TelemetryCapture content-safety test.
  timestamp: 2026-09-28T19:48:45.082534+00:00
- actor: claude-code
  id: 01m3mtwe03asv3kxdexkqbx51s
  text: |-
    ### Facts from swissarmyhammer-05 about FoundationModelsExtras (2026-09-28)
    Extras OTel A-D are done locally but are not on Extras origin/main yet. Do not continue this task until they are on origin/main.
    1. TelemetryCapture (TelemetryTestSupport) uses task-local withTracer and withMetricsFactory. It bootstraps logging one time only. A test process that uses it must NOT call LoggingSystem.bootstrap itself.
    2. A logger or metric that is made before the first capture does not go to the capture. A `static let` logger or metric that a test uses before the capture starts is lost. Make loggers and metrics per call or per instance, or make sure that the capture starts first.
    3. TracedCall.run gets the trace id and the span id from the traceparent that the tracer injects. InMemoryTracer does not inject, so its records have no ids. A test that checks the ids needs a tracer that injects.
  timestamp: 2026-09-28T20:21:44.067535+00:00
- actor: claude-code
  id: 01m3mvajwbkcb21sh6hqjmxey2
  text: |-
    Research (iteration 2, 2026-09-28):
    - Verified: `git ls-remote git@github.com:swissarmyhammer/FoundationModelsExtras.git main` gives 70ad74d. origin/main holds a61bbb0 (^65xmgkv) and 9b97617 (^z6jqd9g), and `Tests/TelemetryTestSupport/{TelemetryCapture,TelemetryLogRouting,TelemetryPlace}.swift`.
    - `swift package update FoundationModelsExtras` ran. The only change to `Package.resolved` is the Extras revision f4bd503 -> 70ad74d. (`Package.resolved` is in `.gitignore`, so git shows no change.) swift-log 1.15.1, swift-metrics 2.11.0 and swift-distributed-tracing 1.5.0 stay at the same versions.
    - `TelemetryCapture.run(forbidding:sourceLocation:_:)` binds a task-local tracer and metrics factory and routes swift-log through a one-time bootstrap. The capture checks span names and attributes, log messages and metadata, and metric names and dimensions.
    - The registry emits no swift-log, span or metric telemetry yet: `MetadataDiagnostic.log(_:)` uses `os.Logger` (a `static let`). Thus the content-safety test passes now, and tasks A, B and C make it bite. A mutation check (a temporary swift-log line that logs the intent) proves that the test can fail.
    - `update(items:)` awaits its reload embed, and `SharedCatalogEmbedding` starts its catalog embed in a `Task {}` (not detached), which inherits the task-local capture. Thus all of this work finishes inside the capture.
  timestamp: 2026-09-28T20:29:27.819563+00:00
- actor: claude-code
  id: 01m3mvzwbab2psw7dkk5c2d8mk
  text: |-
    Implementation (iteration 2):
    - `Package.swift`: the test target links `.product(name: "TelemetryTestSupport", package: foundationModelsExtrasPackage)`, with a comment. The doc comment of `foundationModelsExtrasPackage` no longer says that the core product is "the one product" that the package uses. It now says that the library and the examples use the core product only, and that the test target also uses `TelemetryTestSupport`.
    - `TelemetryContentSafetyTests.swift`: a `MarkedItem` fixture puts a unique marker in its block, indexed text, embedded text and summary block. The query text holds a query marker, and each fixture vector holds a marker component (0.918273). Five new tests each run inside `TelemetryCapture.run(forbidding: Marker.all)`: retrieval with a `FakeEmbedder`, selection with `RecordingSessionFactory`, `update(items:)` then a search, two searchers over one `SharedCatalogEmbedding` (retrieval and selection), and `MetadataDiagnostic.log(_:)` for each of the 5 cases (parameterized). Each searcher is made inside the capture. The searchers use the default `onDiagnostic` (`MetadataDiagnostic.log`). No test calls `LoggingSystem.bootstrap`. Nothing uses Extras OTel E (^wts388b).
    - Lint findings in the changed files, now fixed: swiftlint `orphaned_doc_comment` (4) in `RegistryTelemetry.swift`, because the `//` reason and `// periphery:ignore` stood between each doc comment and its enum. They now stand above the doc comment. Periphery still reads them (no unused and no superfluous report for `RegistryTelemetry`). swiftlint `line_length` (3): two lines in `TelemetryContentSafetyTests.swift` and the `@Test` title of `namesOnlyTheCoreExtrasProduct()` in `PackageManifestTests.swift`. The new title is "Only the test target names an Extras product other than the core product: TelemetryTestSupport".

    TDD evidence: RED — `swift build --build-tests` failed with "unable to resolve module dependency: 'TelemetryTestSupport'" before the test target linked the product. GREEN — the 13 tests of the two suites passed. Mutation check — a temporary `Logging.Logger(label: RegistryTelemetry.loggerLabel).info("MUTATION \(intent)")` in `search(intent:limit:)` made the 4 searcher tests fail with "telemetry carries the forbidden text \"QueryMarker7f3c\"" (5 issues). The mutation is removed, and `MetadataSearcher+Search.swift` has no diff.

    Discovered: periphery reports 4 warnings in files that this task did not change. New task ^0kg6c6h records them. The index store of this toolchain is at `.build/out`, thus periphery needs `--index-store-path .build/out`.
  timestamp: 2026-09-28T20:41:05.642991+00:00
- actor: claude-code
  id: 01m3mw00b4p2kqjj71wfcs1xct
  text: |-
    ### implement — changed
    - evidence: this iteration changed 4 files — Package.swift, Tests/FoundationModelsMetadataRegistryTests/TelemetryContentSafetyTests.swift, Tests/FoundationModelsMetadataRegistryTests/PackageManifestTests.swift, Sources/FoundationModelsMetadataRegistry/Telemetry/RegistryTelemetry.swift. `swift test`: 171 tests in 19 suites passed (166 before, plus 5 new), 0 compiler warnings. The only warnings are the known "failed loading/storing cached manifest ... disk I/O error" lines of the SwiftPM manifest cache of this machine. `swiftlint lint --quiet`: 0 findings. `swiftformat . --lint`: 0/76 files need formatting. Package.resolved (gitignored): only the Extras revision changed, f4bd503 -> 70ad74d. The full set of uncommitted files for the task also holds Tests/FoundationModelsMetadataRegistryTests/TestSupport/ManifestEntries.swift and Tests/FoundationModelsMetadataRegistryTests/RegistryTelemetryTests.swift from iteration 1.
    - next: /review. The task stays in `doing`. Nothing is committed.
  timestamp: 2026-09-28T20:41:09.732023+00:00
- actor: claude-code
  id: 01m3mw73m77s8t6q53p8wdjkcd
  text: |-
    ### test — green
    - evidence: `swift test` — 171 tests, 19 suites, 0 fails, 0 skips. `swiftlint` — 0 rule breaks in 76 files. `swiftformat . --lint` — 0 of 76 files need a format change (2 files skipped by config).
    - note: The `swift test` log shows no "failed loading cached manifest" or "disk I/O error" lines this run. The broken global manifest cache at `~/Library/Caches/org.swift.swiftpm/manifests` may still be there. The cache is not touched.
    - next: none. The build is clean.
  timestamp: 2026-09-28T20:45:02.471138+00:00
position_column: doing
position_ordinal: '80'
title: 'OTel D: add the telemetry vocabulary file, the API dependencies and the content-safety test'
---
## What

Part D of the OpenTelemetry design that the user approved on 2026-09-28 (copy: /private/tmp/claude-501/-Users-wballard-github-swissarmyhammer/9f4fa2e8-6833-46c6-bb95-5091ae3613fa/scratchpad/otel-design.md). Do this task before tasks A, B and C of this board. They add their names to the file that this task makes.

Rules from the design:
- A library uses only the APIs: `Tracing` (swift-distributed-tracing), `Logging` (swift-log), `Metrics` (swift-metrics). This package is a library. It must not depend on swift-otel and must not bootstrap a backend.
- Rule 3: one vocabulary file for each package, like `/Users/wballard/github/swissarmyhammer/FoundationModelsRouter/Sources/FoundationModelsRouter/Tracing/RouterTracing.swift`. Each name starts with the module prefix `FoundationModelsMetadataRegistry.`.
- Rule 4 (no content): a span attribute, a log message, a log metadata value and a metric dimension must never hold query text (`intent`), item content (a rendered block or an embedded text) or a vector. Ids, names, counts and sizes are safe.
- Rule 5: a content-safety test that uses the shared helper from FoundationModelsExtras.

Current state (checked 2026-09-28):
- `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/Package.swift` declares only two packages: `FoundationModelsRanker` and `FoundationModelsExtras`. It does NOT declare swift-distributed-tracing. swift-distributed-tracing 1.5.0 is in `.build/checkouts` only because the core `FoundationModelsExtras` product depends on it. swift-log and swift-metrics are not in the graph.
- `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/Tests/FoundationModelsMetadataRegistryTests/PackageManifestTests.swift` pins the manifest: `dependsOnTheRankerAndExtrasAlone()` requires exactly the two packages (`allowedPackageNames`), and `namesOnlyTheCoreExtrasProduct()` requires that `FoundationModelsExtras` is the only product of that package. This task must change both tests, because the approved design supersedes that part of plan.md decision 16.

External dependencies (FoundationModelsExtras board, so not in `depends_on`):
- Extras OTel A, short id 65xmgkv (01M3MN838VZ4QX57C3965XMGKV): "add swift-log and swift-metrics to the core target as API only". Use the same package URLs and version floors as that task. This task adds swift-log and swift-metrics, so it needs that task.
- Extras OTel B, short id z6jqd9g (01M3MN8N9P4RPET2V5JZ6JQD9G): "add a TelemetryTestSupport product with a content-safety helper for spans, logs and metrics". The content-safety test uses its `TelemetryCapture` API.
- Do not start this task until both tasks are done and pushed to `main` of FoundationModelsExtras. (Both are on Extras origin/main since 70ad74d, checked 2026-09-28.)

Subtasks:
- [x] In `Package.swift`, declare `swift-distributed-tracing`, `swift-log` and `swift-metrics` (package-name constants and comments in the style of the file: API only, no backend). Add `.product(name: "Tracing", ...)`, `.product(name: "Logging", ...)` and `.product(name: "Metrics", ...)` to the `FoundationModelsMetadataRegistry` target. Add `.product(name: "TelemetryTestSupport", package: "FoundationModelsExtras")` to the `FoundationModelsMetadataRegistryTests` target only.
- [x] In `PackageManifestTests.swift`, add the three API packages to `allowedPackageNames`. Change `namesOnlyTheCoreExtrasProduct()` so that the library target and the example targets name only the core `FoundationModelsExtras` product, and only the test target may also name `TelemetryTestSupport`. Add a test that no target names a swift-otel product (`OTel`, package `swift-otel`). Update the doc comment of the suite.
- [x] Make `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/Telemetry/RegistryTelemetry.swift`: an `enum RegistryTelemetry` with nested `enum SpanName`, `enum AttributeKey`, `enum MetricName`, `enum MetadataKey` (log metadata keys) and a logger label constant. Put the "no content" rule in the doc comment, as `RouterTracing` does. Add a `static func tracer(explicit: (any Tracer)?) -> any Tracer` that returns `explicit ?? InstrumentationSystem.tracer` (resolve late). Leave the nested enums empty or with only the prefix; tasks A, B and C add the names.
- [x] Make `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/Tests/FoundationModelsMetadataRegistryTests/TelemetryContentSafetyTests.swift`. Inside `TelemetryCapture.run(forbidding:)`, it drives the public surface with a fixture that holds unique marker strings in the query text and in the item content: `MetadataSearcher.search(intent:limit:)` in `.retrieval` mode with an embedder (use `TestSupport/FakeEmbedder.swift`), `.selection` mode (use `TestSupport/ScriptedAgentSession.swift` / `SelectionFixtures.swift`), `MetadataSearcher.update(items:)`, a searcher built with `MetadataSearcher.init(sharing:mode:weights:selection:onDiagnostic:)` over a `SharedCatalogEmbedding`, and `MetadataDiagnostic.log(_:)` for each case. The forbidden strings are the markers. Tasks A, B and C each add their own checks to this file.

## Acceptance Criteria
- [x] `Package.swift` declares swift-distributed-tracing, swift-log and swift-metrics, and the library target links `Tracing`, `Logging` and `Metrics`. No target names a swift-otel product.
- [x] `PackageManifestTests` passes with the new allow-lists, and it fails if a library or example target names `TelemetryTestSupport` or a swift-otel product.
- [x] `RegistryTelemetry.swift` exists, compiles, and each name in it starts with `FoundationModelsMetadataRegistry.`.
- [x] `TelemetryContentSafetyTests` runs each public entry point listed above and reports no issue.

## Tests
- [x] Update `Tests/FoundationModelsMetadataRegistryTests/PackageManifestTests.swift` as above. Add one test for "no swift-otel product".
- [x] New `Tests/FoundationModelsMetadataRegistryTests/TelemetryContentSafetyTests.swift` as above.
- [x] Add a test in `TelemetryContentSafetyTests.swift` that each `RegistryTelemetry` name starts with the module prefix.
- [x] Run `swift test`. All tests pass, with no new warnings.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Do not run `swift format`. #otel #cross-repo #test-contract