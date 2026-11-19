---
assignees:
- claude-code
depends_on:
- 01M7SZZ2ZQ2H0FRSEJ38VRK7Y7
position_column: done
position_ordinal: c380
title: 'Update of some items: update(upserting:removing:)'
---
D207, brief `mdr-brief.md` item 2.

## Change
- `MetadataSearcher.update(upserting: [Item], removing: some Collection<String>) async`: add, replace and remove items by id. An entry that does not change is not built again. A replaced item keeps its position; a new item goes to the end; a removal drops the id.
- The same hash guard (no change: no work), the same reuse of vectors (keyed by the embedded-text digest), and the same single-flight reload embed loop as `update(items:)`. The selection tier is built again only when the content changed.
- `update(items:)` stays, and it also reuses the entries that did not change.
- One `catalogUpdate` span for each call.

## Acceptance
- Tests: an added, a changed and a removed item; the vectors of the other items stay; the entries that did not change are not built again (the render count of a counting item); an id in both lists; a redundant call is a no-op.