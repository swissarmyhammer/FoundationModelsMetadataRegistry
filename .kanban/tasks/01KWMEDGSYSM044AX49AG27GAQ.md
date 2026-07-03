---
depends_on:
- 01KWMECA3GC1631WXPX2BJN4DB
- 01KWMED1XXMRMQ4JFB92YPCTGD
position_column: todo
position_ordinal: '8680'
title: 'Selection tier: cached root + fork-per-call, ids-only grammar-constrained output'
---
## What
Implement the under-budget selection path per plan.md §6 (M3), generalizing Multitool's shipped `Librarian` (`../FoundationModelsMultitool/Sources/.../Librarian.swift`), in `Sources/FoundationModelsMetadataRegistry/Selection/`:
- `SelectionConfig` — model (via a session-factory closure over the `AgentSession` seam), `preamble` with `.librarianDefault` (lift Multitool's `selectionGuidance` "fewest that suffice, in call order" verbatim, `Librarian.swift:41-45`), `capacityCharacterLimit` default 32_000, `candidateLimit` default 24
- The selection prefix and the capacity computation use **`renderSummaryBlock()`** (plan.md §4: the summary seeds the selection prefix; retrieval indexes the full `renderBlock()`)
- Under budget (assembled preamble + all summary blocks ≤ limit): build a **cached root session** seeded once with the prefix; each `search()` **forks** a child and asks it
- Guided output `@Generable struct Selection { var ids: [String] }`; id-enum grammar built from the current catalog ids (Router `Grammar.jsonSchema` with an enum constraint — the pattern at Multitool `Librarian.swift:143-149`)
- **Verbatim lookup**: returned ids map through the catalog to `Match`es carrying the full `renderBlock()` text (score 1.0, signals nil); any unknown id from the model is filtered and surfaced as the shared `MetadataDiagnostic.unknownSelectedId` case
- `.selection` mode wired into `MetadataSearcher`

## Acceptance Criteria
- [ ] Root session is created once and forked per search (fork count == search count with a scripted fake)
- [ ] A fixture whose `renderSummaryBlock()` differs from `renderBlock()` shows the summary in the session prefix and the full block in returned `Match`es
- [ ] Selection returns catalog blocks by lookup — model output contains only ids, never blocks
- [ ] Unknown id from a (deliberately misbehaving) fake is filtered with `.unknownSelectedId` emitted, not returned
- [ ] Id-enum grammar contains exactly the catalog's current ids

## Tests
- [ ] `Tests/FoundationModelsMetadataRegistryTests/SelectionTests.swift` — scripted `AgentSession` fakes: fork-per-call counts, summary-vs-full block separation, ids-only decode, verbatim lookup identity, unknown-id filtering + diagnostic capture, grammar id-set contents
- [ ] Run `swift test` — all pass, no GPU

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.