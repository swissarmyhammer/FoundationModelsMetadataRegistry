---
assignees:
- claude-code
position_column: todo
position_ordinal: '8280'
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