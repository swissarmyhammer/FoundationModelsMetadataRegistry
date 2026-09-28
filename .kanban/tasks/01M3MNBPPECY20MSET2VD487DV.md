---
assignees:
- claude-code
position_column: todo
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
- Do not start this task until both tasks are done and pushed to `main` of FoundationModelsExtras.

Subtasks:
- [ ] In `Package.swift`, declare `swift-distributed-tracing`, `swift-log` and `swift-metrics` (package-name constants and comments in the style of the file: API only, no backend). Add `.product(name: "Tracing", ...)`, `.product(name: "Logging", ...)` and `.product(name: "Metrics", ...)` to the `FoundationModelsMetadataRegistry` target. Add `.product(name: "TelemetryTestSupport", package: "FoundationModelsExtras")` to the `FoundationModelsMetadataRegistryTests` target only.
- [ ] In `PackageManifestTests.swift`, add the three API packages to `allowedPackageNames`. Change `namesOnlyTheCoreExtrasProduct()` so that the library target and the example targets name only the core `FoundationModelsExtras` product, and only the test target may also name `TelemetryTestSupport`. Add a test that no target names a swift-otel product (`OTel`, package `swift-otel`). Update the doc comment of the suite.
- [ ] Make `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/Sources/FoundationModelsMetadataRegistry/Telemetry/RegistryTelemetry.swift`: an `enum RegistryTelemetry` with nested `enum SpanName`, `enum AttributeKey`, `enum MetricName`, `enum MetadataKey` (log metadata keys) and a logger label constant. Put the "no content" rule in the doc comment, as `RouterTracing` does. Add a `static func tracer(explicit: (any Tracer)?) -> any Tracer` that returns `explicit ?? InstrumentationSystem.tracer` (resolve late). Leave the nested enums empty or with only the prefix; tasks A, B and C add the names.
- [ ] Make `/Users/wballard/github/swissarmyhammer/FoundationModelsMetadataRegistry/Tests/FoundationModelsMetadataRegistryTests/TelemetryContentSafetyTests.swift`. Inside `TelemetryCapture.run(forbidding:)`, it drives the public surface with a fixture that holds unique marker strings in the query text and in the item content: `MetadataSearcher.search(intent:limit:)` in `.retrieval` mode with an embedder (use `TestSupport/FakeEmbedder.swift`), `.selection` mode (use `TestSupport/ScriptedAgentSession.swift` / `SelectionFixtures.swift`), `MetadataSearcher.update(items:)`, a searcher built with `MetadataSearcher.init(sharing:mode:weights:selection:onDiagnostic:)` over a `SharedCatalogEmbedding`, and `MetadataDiagnostic.log(_:)` for each case. The forbidden strings are the markers. Tasks A, B and C each add their own checks to this file.

## Acceptance Criteria
- [ ] `Package.swift` declares swift-distributed-tracing, swift-log and swift-metrics, and the library target links `Tracing`, `Logging` and `Metrics`. No target names a swift-otel product.
- [ ] `PackageManifestTests` passes with the new allow-lists, and it fails if a library or example target names `TelemetryTestSupport` or a swift-otel product.
- [ ] `RegistryTelemetry.swift` exists, compiles, and each name in it starts with `FoundationModelsMetadataRegistry.`.
- [ ] `TelemetryContentSafetyTests` runs each public entry point listed above and reports no issue.

## Tests
- [ ] Update `Tests/FoundationModelsMetadataRegistryTests/PackageManifestTests.swift` as above. Add one test for "no swift-otel product".
- [ ] New `Tests/FoundationModelsMetadataRegistryTests/TelemetryContentSafetyTests.swift` as above.
- [ ] Add a test in `TelemetryContentSafetyTests.swift` that each `RegistryTelemetry` name starts with the module prefix.
- [ ] Run `swift test`. All tests pass, with no new warnings.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.
- Do not run `swift format`. #otel #cross-repo #test-contract