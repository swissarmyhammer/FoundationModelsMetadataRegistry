---
depends_on:
- 01M7SZZ684NY2DAYZ1165Y0TKC
position_column: done
position_ordinal: c480
title: Persistence of the catalog and its vectors in a folder
---
D207, brief `mdr-brief.md` item 1.

## Change
- `CatalogPersistence(folder: URL, embeddingModelID: String)`. A new async initializer of `MetadataSearcher` and of `SharedCatalogEmbedding` takes it, with `Item: Codable`.
- At its start, the searcher loads the stored catalog and vectors, with no embed and no call to the caller. Pending entries are embedded in the background by the reload embed loop.
- The files: one snapshot (all entries, vocabularies, features and vectors) and one journal of the changes after it, each with a generation. Each journal record has a length and a checksum; a torn tail is dropped (the last good state). A snapshot is written to a temporary file and renamed. A new snapshot replaces the journal when the journal is large.
- Saves run on a background queue in order, after each update and each embed chunk, off the path of the caller. `waitForSaves()` returns when each save requested so far is on disk.
- A catalog of an old format, of a different model id, or that is damaged, is dropped; the searcher starts empty.

## Acceptance
- Tests: save then a new searcher over the same folder gives the same matches with no catalog embed; a different model id drops the catalog; a damaged file and an old format are dropped; a torn journal record leaves the last good state; the shared embed with persistence; the searcher without persistence does not change.