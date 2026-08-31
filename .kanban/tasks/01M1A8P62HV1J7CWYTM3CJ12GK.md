---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m1affj8czm2q8nhhtdaxsvyr
  text: |-
    Research, before editing.

    **The trap reproduces.** Proved it rather than assuming it. `plan.md` §4 and §7 are the only two top-level sections carrying no `decision #14` marker, so §7 is where an unmarked mention lands. Added one TRUE, present-tense sentence there — "the `IntegrationTests/` package drives `.selection` against a real model" — and `PlanDocumentTests` failed: `["## 7. Modes: IntegrationTests"]`. The guard was demanding a history marker on a live directory, exactly as the card says.

    **A second stale claim, outside the two files the card names.** `PackageManifestTests`'s suite doc comment read "no code in this repository needs one any more: the real-model suite that did is gone." The acceptance criterion greps the whole test suite for claims the repository has no integration suite, and that is one. Reworded to name the Router-backed suite as the one that went and the current package as what stands in its place. Nothing else in `Tests/`, `Package.swift`, `README.md` or `.github/` makes such a claim — `Package.swift:154-158` and `ci.yml:3-21` already describe the nested package correctly.

    **Facts verified before asserting them in decision #15**, not carried over from the card:
    - `IntegrationTests/Package.swift` declares `.macOS("27.0")` and one dependency, `.package(path: "..")`. Root `Package.swift` declares the same floor (line 135).
    - `swift test --package-path IntegrationTests` → 5 tests in 4 suites: `ColdSelectionRealModelTests` (one `@Test(arguments:)` over 4 intents), `HotReloadRealModelTests` (2), `ModelAvailabilityTests` (1), `IntegrationCatalogTests` (1).
    - `assemblePrefix` is real and is Ranker's: `SelectionTier.swift:356` and `:373`, two overloads.
    - `MetadataIndex: SelectionCatalog` at `Sources/.../Catalog/MetadataIndex.swift:430`.
    - `.librarianDefault` at `Sources/.../SelectionPreamble.swift:12`, and `SelectionScenario.makeSearcher` passes it explicitly so the suite measures this package's preamble rather than Ranker's `.selectionDefault`.
    - `ci.yml` passes exactly one input, `integration-package-path: IntegrationTests`.
    - 55/55 `.embeddingUnavailable`, 0/125 `.unknownSelectedId`, off-topic control empty 5/5 — all read off the suite's own doc comments, which cite `^nwt7nz4`.
    - `LanguageModelSession.fork()` returns `self`, so there is no fork-per-call prefix reuse left for M7's original list to measure. Stated that in the M7 marker rather than leaving the old list reading as still-pending work.
  timestamp: 2026-08-30T23:18:40.140724+00:00
- actor: claude-code
  id: 01m1affw55ar5n322047qcvt1r
  text: |-
    ### implement — changed
    - files: `Tests/FoundationModelsMetadataRegistryTests/PlanDocumentTests.swift`, `Tests/FoundationModelsMetadataRegistryTests/PackageManifestTests.swift`, `plan.md`
    - TDD: RED — an unmarked, TRUE `IntegrationTests` mention in `plan.md` §7 failed `PlanDocumentTests` with `["## 7. Modes: IntegrationTests"]`. GREEN — `"IntegrationTests"` removed from `retiredNameStems`, doc comment rewritten to say why a live directory may not be a stem. Probe reverted.
    - guard still guards: an unmarked `Router` mention in §7 failed with `["## 7. Modes: Router"]` over the reduced list `["Router", "Routed", "Grammar"]`; reverted.
    - `plan.md`: dated decision #15 added to §11; every one of the eight places the card names reconciled in the file's own marker idiom, no history rewritten — preamble (16, 24, 29) by a `decision #15` blockquote paragraph in the same note; §10 (369) by an `(Extended … decision #15)` paragraph; decision #14's own bullet (464-465) by a `(Superseded … decision #15)` marker inside it; §14 M7 (615-622) and §15 (639-644) each by a `(Reinstated … decision #15)` marker beside the #14 one.
    - `swift test` — 115 tests in 12 suites, passed.
    - `swift test --package-path IntegrationTests` — 5 tests in 4 suites, passed.
    - `swift build --build-tests` on both packages — 0 warnings.
    - not done, by the card: no push. The CI-run criterion is the orchestrator's, post-push.
    - next: `/review`
  timestamp: 2026-08-30T23:18:50.277226+00:00
- actor: claude-code
  id: 01m1aft6gcgq8yjtcm5bwkksxw
  text: |
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` — 0 findings (7 attempted, 0 confirmed, 0 refuted, 0 failed). Zero new findings, no prior findings sections.
    - scope note: the engine reviewed the two Swift files and reported `plan.md` as "no validator matches this file". The truth of that file is the substance of this card, so its claims were checked by hand against the code.
    - doc-truth audit, decision #15 (plan.md:506, dated 2026-08-30) — every claim true:
      - `IntegrationTests/` package exists; 4 `@Suite` and 5 `@Test` declarations = "five tests in four suites".
      - `ColdSelectionRealModelTests` and `HotReloadRealModelTests` drive the model; `ModelAvailabilityTests` and `IntegrationCatalogTests` hold the availability gate and the fixture catalog — exactly as written.
      - `ci.yml:37` passes `integration-package-path: IntegrationTests`.
      - "no `.serialized` trait on any of its suites" — no match for `serialized` in the package.
      - "FoundationModels exposes no embedding API" — consistent: Ranker's `TextEmbedding` is a caller-supplied protocol seam that imports nothing and ships no embedder.
      - "Ranker's own four real-model tests" — four `*RealModelTests` files exist in Ranker's nested integration package.
    - absence-claim sweep of `Package.swift`, `plan.md`, `README.md`, `.github/` and all of `Tests/`: three residual "no integration suite" statements remain, at plan.md:40, plan.md:485 and plan.md:730. Each is retained history and each carries a dated decision #15 marker immediately after it (plan.md:32, 488, 735). No unmarked misleading claim found. Per the card's note, marked history is not staleness.
    - decision #15 markers stand at plan.md:32 (§1 status), 372 (§10), 488 (§13 M7 bullet), 700 (§14 M7), 735 (§15 closing), plus the entry at 506.
    - `PlanDocumentTests`: `"IntegrationTests"` removed from `retiredNameStems`; `Router`, `Routed`, `Grammar` retained and the enforcement path unchanged, so the kept stems are still guarded.
    - `PackageManifestTests` doc comment now reads true: the Router-backed suite is gone, and the nested package that stands in its place drives Apple Intelligence.
    - next: CI's `Integration` job conclusion is deferred to the orchestrator after the push, per the card.
  timestamp: 2026-08-30T23:24:28.556389+00:00
- actor: claude-code
  id: 01m1afv433yxb3tsvsm8xrysty
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 3 files: Tests/.../PlanDocumentTests.swift, Tests/.../PackageManifestTests.swift, plan.md
    - test: green — swift test 115 tests in 12 suites; swift test --package-path IntegrationTests 5 tests in 4 suites; swift build --build-tests on both packages, 0 warnings. Two mutation probes run and reverted.
    - commit: eed1753 docs(plan): reconcile docs and guard tests with the reinstated integration suite
    - review: clean — 0 findings, 7 validators, task moved to done. This closes the board.

    ### The trap was proven in both directions
    Before the fix, an unmarked and **true** present-tense sentence about the live `IntegrationTests/` directory in plan.md §7 made `PlanDocumentTests` fail — demanding a decision #14 history marker on a directory that exists. After removing the stem, an unmarked `Router` mention still fails, so the kept stems are genuinely still guarded. That is the right pair of probes: one shows the old rule was wrong, the other shows the new rule still bites.

    ### The reviewer checked plan.md by hand
    The engine reported plan.md as "no validator matches this file". Since the truth of that file is this card's whole substance, the reviewer verified decision #15's claims against the code rather than let them pass unreviewed. All true: the nested package exists with 4 @Suite and 5 @Test declarations; ci.yml:37 passes integration-package-path; no `.serialized` trait anywhere in the package; Ranker really has four *RealModelTests files.

    The absence-claim sweep found three surviving "no integration suite" statements at plan.md:40, :485 and :730 — each retained history, each carrying a dated decision #15 marker immediately after it. No reader meets an unmarked false claim.

    ### One file beyond the card's list
    `PackageManifestTests`'s suite doc comment claimed "the real-model suite that did is gone". The card's own acceptance criterion greps the whole test suite for that claim, so fixing it was in scope, not creep.

    ### Still deferred
    CI's `Integration` job conclusion. `/finish` never pushes, so the orchestrator verifies the live run after the user pushes.
  timestamp: 2026-08-30T23:24:58.851012+00:00
depends_on:
- 01M1A8N1QQYFF6376DMXMT6FMC
- 01M1A8NKPNMZJCCMJFHDDAXWAZ
- 01M1A96ZZCKAB5SE03AF10JVV9
position_column: done
position_ordinal: a180
title: Reconcile the docs and guard tests that still say the integration suite is gone
---
## What

The CI input landed in `^f10jvv9`, and both real-model tests landed in `^xmt6fmc` and `^ddaxwaz`. This card closes out the documents and guard tests that still assert the integration suite does not exist.

Files to change:
- `Tests/FoundationModelsMetadataRegistryTests/PlanDocumentTests.swift` — **this test now enforces a falsehood.** `retiredNameStems` includes `"IntegrationTests"` (line 48), and the doc comment at line 35 says it "covers the deleted nested package". The package is no longer deleted. As written, the test forces every `plan.md` section naming `IntegrationTests` to carry a `decision #14` history marker forever — marking a live directory as history. Remove `"IntegrationTests"` from `retiredNameStems` and rewrite the doc comment. Leave the other stems (`Router`, `Routed`, `Grammar`) alone; those types really are gone.
- `plan.md` — decision #14 states the repository has no integration suite and that `ci.yml` passes no inputs. Both are now false. It is **not only decision #14**: the claim also appears at lines 16, 24, 29, 369, 464-465, 615-622 and 639-644. Add a dated decision #15 recording the reinstatement and its narrow scope, and reconcile every one of those places in the file's existing marker idiom. Do not rewrite history; mark it.

### What decision #15 should record

Two real-model tests, not eight. The scope was chosen from a coverage analysis, and the exclusions are as deliberate as the inclusions:

- FoundationModelsRanker's own four real-model tests now cover the `LanguageModelSession` seam, guided generation, and its zero-config `Searcher`. Duplicating them here buys nothing.
- The over-budget path is excluded: its mechanics are at 97% line coverage through fakes, and the model-behaviour half is Ranker's.
- Real embeddings are excluded: FoundationModels exposes no embedding API at all.
- What is left is the seam only this repository can cover — `MetadataSearcher` and `MetadataIndex`'s `SelectionCatalog` conformance feeding Ranker's `assemblePrefix`, under this package's own `.librarianDefault` preamble, plus `update(items:)`, which Ranker's facade has no equivalent for.

Also worth recording: `.librarianDefault` was measured over 125 cold runs and did **not** reproduce the cold-empty behaviour Ranker measured against `.selectionDefault`.

### Pushing is out of scope for this card

`/finish` commits locally and never pushes. Do not push. The orchestrator verifies the live CI run after the batch, when the user pushes.

## Acceptance Criteria

- [ ] `PlanDocumentTests.retiredNameStems` no longer contains `"IntegrationTests"`, and its doc comment matches.
- [ ] No test or document claims this repository has no integration suite. Grep `Package.swift`, `plan.md`, `README.md`, `.github/`, and the whole test suite.
- [ ] `plan.md` carries a dated decision #15, and every one of lines 16, 24, 29, 369, 464-465, 615-622, 639-644 is reconciled in the file's marker idiom.
- [ ] `PlanDocumentTests` passes with the reduced stem list.
- [ ] Deferred to the orchestrator, post-push: CI's `Integration` job reports `success` and its `Run the selected integration tests` step is not `skipped`.

## Tests

- [ ] Run `swift test` at the root. All tests pass, including the amended `PlanDocumentTests` and `CIWorkflowTests`.
- [ ] Run `swift test --package-path IntegrationTests`. All five tests pass.
- [ ] Prove the amended `PlanDocumentTests` still guards the stems it keeps: temporarily add an unmarked `Router` mention to a `plan.md` section, confirm it fails, revert.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.