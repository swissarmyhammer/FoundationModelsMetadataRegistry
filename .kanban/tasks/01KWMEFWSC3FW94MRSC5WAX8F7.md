---
depends_on:
- 01KWMET9W0X65DBQ2H5JCYN2BD
- 01KWMEEA0FQB66C11H0V13TGR4
position_column: todo
position_ordinal: 8c80
title: Re-base Multitool Librarian onto MetadataSearcher (cross-repo)
---
## What
**Cross-repo task — all changes land in `../FoundationModelsMultitool`; commits go to that repo, not this board's workspace.** Second half of plan.md M5, per Multitool's own plan ("Planned migration → ../FoundationModelsMetadataRegistry", plan.md:444-456). The AgentSession move (previous task) is already done:
- `Librarian` becomes a thin wrapper over `MetadataSearcher<APISurface.Entry>` (blocks: existing `Entry.block`)
- Delete `lexicallyFilter` — over-budget now goes through ranked retrieval top-M; expose the `.retrievalCut` diagnostic through a callback compatible with the old `onPrefilterCut` surface
- `FoundAPIs` becomes formatting only in `FindAPITool` over verbatim `Match.block`s (ids-only selection underneath)

Behavior deltas Multitool gains: ids-only selection, id-enum grammar, RRF instead of substring filtering.

## Acceptance Criteria
- [ ] Multitool's existing librarian test suite passes against the wrapper (adjusted only where the plan's behavior deltas intentionally change expectations — each such adjustment called out in the commit)
- [ ] No remaining `lexicallyFilter` in Multitool sources
- [ ] `swift build` and `swift test` pass in `../FoundationModelsMultitool`

## Tests
- [ ] Existing `../FoundationModelsMultitool/Tests/` librarian tests are the regression harness — run `swift test` there, exit 0
- [ ] Add a wrapper-level test asserting `FindAPITool` output blocks are verbatim `APISurface.Entry.block` strings

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.