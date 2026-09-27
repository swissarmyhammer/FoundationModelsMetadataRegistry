---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m3j1p86xmr24x4rdebnjd1h4
  text: |-
    Research: `RenderedTextDigests` is internal. Its only caller is `MetadataIndex.swift:137`. No test used the type directly before. `SearchableMetadataTextsTests.swift` already uses `@testable import`. Two tests go into a new MARK section in that file: (1) block "A", indexed "B", embedded "B" gives embeddedText == indexedText and embeddedText != block; (2) the embedded digest of that value is equal to the indexed digest of the value with embedded "C", and is not equal to its embedded digest. The code under test did not change.

    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsMetadataRegistryTests/SearchableMetadataTextsTests.swift
    - next: test
  timestamp: 2026-09-27T18:22:58.269437+00:00
- actor: claude-code
  id: 01m3j1r6xsvrs1btnf2e00ws9a
  text: |-
    ### test — green
    - evidence: `swift test` — 147 tests in 15 suites passed, 0 failed, 0 skipped, 0 compiler warnings (SwiftPM prints manifest cache "disk I/O error" lines from the local cache directory; they are not from the code). `swiftformat . --lint` — 0/68 files need formatting. `swiftlint --strict` — 0 violations in 68 files.
    - next: commit
  timestamp: 2026-09-27T18:24:02.489380+00:00
position_column: doing
position_ordinal: '80'
title: Add tests for RenderedTextDigests.init(block:indexedText:embeddedText:)
---
Sources/FoundationModelsMetadataRegistry/Catalog/RenderedTextDigests.swift:49-61

Coverage (file): 93.8% (15/16 lines)

Uncovered lines: 56

```swift
init(block: String, indexedText: String, embeddedText: String)
```

This initializer calculates a digest for each of the three rendered texts of an entry. It calculates each different text one time only. The branch where `embeddedText == indexedText` and `embeddedText != block` does not run. In that branch, the initializer uses the digest of `indexedText` again.

Tests to add (in `SearchableMetadataTextsTests.swift` or `CatalogTests.swift`):
- Make a digest with `block: "A"`, `indexedText: "B"`, `embeddedText: "B"`. Make sure that `embeddedText == indexedText` and `embeddedText != block`.
- Compare with a digest made with `block: "A"`, `indexedText: "B"`, `embeddedText: "C"`. Make sure that the `embeddedText` digests are different.
- The type is internal. Use `@testable import` if the tests do not already use it.

Do not change the code under test. #coverage-gap