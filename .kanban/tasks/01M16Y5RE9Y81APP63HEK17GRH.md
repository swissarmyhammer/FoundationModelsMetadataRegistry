---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m19bsbshj9fhvjf9rw32stb8
  text: |-
    Research done. Current state of each named file, verified against the code:

    **`Package.swift`** — three stale spots remain (line numbers have shifted from the card's):
    - `packageName`'s doc comment: "following the pattern established by the sibling FoundationModelsRouter and CodeContextKit packages."
    - `foundationModelsRankerPackage`'s doc comment: lists `RoutedEmbedderAdapter` among Ranker's exports (deleted upstream); says "for the same CI reason as `routerDependencyName` above" (that constant no longer exists, so the cross-reference dangles); claims "FoundationModelsRanker itself depends on FoundationModelsRouter `main`, so SwiftPM unifies it with the existing pin" (false — Ranker at `35447e4` declares `dependencies: []`).
    - `platforms:`: "floor inherited from FoundationModelsRouter".
    - `exampleCoreTarget`'s doc comment narrates the removal ("Router-free", "once resolved ... through a live `Router`", "no core needs a Router product") rather than describing the shape as it now is.
    - The manifest header (`let package = Package(`) already says "over the FoundationModelsRanker sibling" and already describes the GPU-free examples — correct as written.

    **`Sources/.../FoundationModelsRankerReexport.swift`** — already correct. Its list is `HybridRanker`, `RankedDocument`, `SignalWeights`, `CosineScoring`, `Hit`, `Signals`, the BM25/trigram/tokenizer primitives, `TextEmbedding`, `SelectionTier`, `SelectionConfig`, `SelectionSessionSource`, `SelectionCatalog`, `SelectionMatch`, `Selection`, `RankDiagnostic`, `AgentSession`, and the selection-unavailable error. Every one of those is a `public` declaration in the Ranker checkout at `35447e4`. Neither `RoutedEmbedderAdapter` nor `RoutedAgentSession` appears. No change needed.

    Ranker's full public surface at `35447e4`: `BM25`, `BM25Corpus`, `CosineScoring`, `Hit`, `Signals`, `HybridRanker`, `SignalWeights`, `RankedDocument`, `RRF`, `SearchCorpus`, `StreamingSearchCorpus`, `Searcher`, `SelectionTierUnavailable`, `Searchable`, `SearchItem`, `TextEmbedding`, `Tokenizer`, `Trigram`, `AgentSession`, `RankDiagnostic`, `Selection`, `SelectionCatalog`, `SelectionConfig`, `SelectionSessionSource`, `SelectionMatch`, `SelectionTier`, `SelectionSchemaShapeError`.

    **`plan.md`** — stale in §1, §2, §3, §5, §6, §9, §10, §12, §13, §14 (M7/M8) and §15. §11 "Resolved decisions" is a numbered list ending at 13, and is the file's own home for a recorded decision, so the dated note goes there and the affected sections point at it.

    **`README.md`** — no Router/MLX/Hugging Face mention. The usage example type-checks against the current API: `MetadataSearcher` is a `public actor`, `init(items:mode:weights:selection:onDiagnostic:)` is sync and non-throwing, `search(intent:limit:)` is `async throws -> [Match<Item>]`, and `Match` has `id` and `score`. One prose claim still to verify empirically: "`commit` gets the first rank although its block does not contain the query's words" — the `commit` block reads "Record staged **changes** as a new snapshot..." and the query is "commit **changes** to git", so the block does share a query word.

    **Test precedent:** `CIWorkflowTests.swift` and `PackageManifestTests.swift` both resolve the repository root from `#filePath` by stripping two path components. New tests follow that pattern.
  timestamp: 2026-08-30T12:54:52.465490+00:00
- actor: claude-code
  id: 01m19c907p5fz9apvgrskg4vgw
  text: |-
    Implementation landed. TDD notes, including where the red-green cycle was and was not available:

    **Genuine RED → GREEN (the manifest test).** Wrote `spellsNoRemovedRouterName()` first and ran it. It failed for exactly the right reason: `["Package.swift: FoundationModelsRouter, RoutedEmbedderAdapter"]`. `Sources/` was already clean, which independently confirms `FoundationModelsRankerReexport.swift` needed no edit. Then fixed `Package.swift` and it went green.

    **Passed on first run (the README tests), so each was proven able to fail by perturbation.** The README's ranking claim was already true, so there was no failing state to observe. Rather than accept two assertions I had never seen fail, I perturbed each and re-ran:
    - `topRankedID` set to `"stash"` → failed, and reported the real ranking: `["commit", "push", "stash"]`. Restored.
    - One fixture block edited to `"...history, drifted."` → the drift guard failed naming that exact line. Restored.

    **A false claim found in `README.md`, and corrected.** The README said `commit` ranks first "although its block does not contain the query's words". That is not true: the `commit` block is "Record staged **changes** as a new snapshot..." and the query is "commit **changes** to git", so the block does share a query word. The true statement is that the block never says `commit` — the id field, weighted ×5, carries that term. Verified in the Ranker checkout: `BM25.primaryFieldWeight = 5.0`, `BM25.bodyFieldWeight = 1.0`, so the README's "(id field ×5, block ×1)" was already correct. Reworded that one sentence only.

    **A duplication trap avoided.** `ReadmeExampleTests` needs the repository root, and `PackageManifestTests` already had the `#filePath` walk — a third copy would have been a real near-duplicate (`CIWorkflowTests` holds the second). Extracted `TestSupport/RepositoryFiles.swift` and pointed the new code and the file I was already changing at it. `CIWorkflowTests` is untouched: the duplication rule says the fix goes in the changed code, never in the untouched counterpart.

    **A name collision avoided.** `ExamplesSupport` exports its own `GitCommand`, and the test target depends on it. A file-scope `GitCommand` in the new test file would have shadowed it for every other test file in the target — the local module wins. The README's type is nested inside the suite instead, and the doc comment says why.

    **`Package.swift` — every stale statement, and what replaced it:**
    - "the sibling FoundationModelsRouter and CodeContextKit packages" → "the sibling FoundationModelsRanker package's manifest", which I verified carries the identical constant-extraction convention.
    - `RoutedEmbedderAdapter` dropped from Ranker's export list; the selection tier added, matching the re-export file.
    - The dangling "same CI reason as `routerDependencyName` above" replaced with the actual reason, stated without reference to a deleted constant: a `../FoundationModelsRanker` path resolves only beside a checked-out sibling.
    - "FoundationModelsRanker itself depends on FoundationModelsRouter `main`" (false) → "declares `dependencies: []`, so this single entry is also the whole resolved graph", verified at `35447e4`.
    - "floor inherited from FoundationModelsRouter" → Ranker declares the same `.macOS("27.0")` floor, verified in its manifest.
    - `exampleCoreTarget`'s comment narrated the removal ("Router-free", "once resolved ... through a live `Router`"). Rewritten to describe the shape as it stands, with no reference to what it used to be.

    **`plan.md`** — history untouched. Added decision #14 (dated 2026-08-30) recording what was removed and why, plus the two API changes Ranker's Router-free release brought (`SelectionConfig`'s one-argument factory and `sessionSource`; `idEnumSchema(ids:) throws -> String` for `idEnumGrammar(ids:) -> Grammar`). Every section a reader could be misled by now carries a dated superseded marker pointing at it: the top status blockquote, §10, §12, §13, §14/M7 and §15. The markers use the file's own `*(Superseded ...)*` idiom.

    **Not changed, deliberately:** the existing `#expect` messages in `PackageManifestTests`. Reformatting user-facing output the card did not ask to change is what the `public-output-contract` rule forbids.

    Verification: `swift build` clean, `swift build --build-tests` reports zero warnings and zero errors, `swift test` is 113 tests in 11 suites passed (was 110 in 10 — three added). `Package.swift`, `Sources/` and `Examples/` now contain no occurrence of Router, Routed, MLX or Hugging Face at all. `stash@{0}` untouched.
  timestamp: 2026-08-30T13:03:24.918479+00:00
- actor: claude-code
  id: 01m19c9f3eraakyfx96nmap1wr
  text: |-
    ### implement — changed
    - evidence: 6 files — Package.swift, README.md, plan.md, Tests/FoundationModelsMetadataRegistryTests/PackageManifestTests.swift, Tests/FoundationModelsMetadataRegistryTests/ReadmeExampleTests.swift (new), Tests/FoundationModelsMetadataRegistryTests/TestSupport/RepositoryFiles.swift (new). `swift test` 113 passed / 0 failed in 11 suites (was 110 in 10). `swift build --build-tests` 0 warnings, 0 errors. `Sources/FoundationModelsMetadataRegistry/FoundationModelsRankerReexport.swift` needed no change — its list already matches Ranker's public surface at `35447e4`, which the new manifest test independently confirms.
    - next: ready for `/review`. Not committed.
  timestamp: 2026-08-30T13:03:40.142383+00:00
- actor: claude-code
  id: 01m19csf7pmwag6p99gd4ngk9g
  text: |-
    ### review — findings
    - evidence: engine `review sha HEAD~1..HEAD` returned 0 findings over 4 files (7 attempted, 0 failed). The engine matched no validator to `README.md` or `plan.md`, so both were audited by hand for truth against the current code. 1 finding — plan.md:26 (contradicted by plan.md:170).
    - next: add §5 to decision #14's supersedes list at plan.md:395, or mark plan.md:170 the way the other six places are marked. Then re-run `/review ^ek17grh`.
  timestamp: 2026-08-30T13:12:24.566830+00:00
- actor: claude-code
  id: 01m19ct959a4wgtqc98jr6692e
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 6 files: Package.swift, README.md, plan.md, Tests/.../PackageManifestTests.swift, Tests/.../ReadmeExampleTests.swift (new), Tests/.../TestSupport/RepositoryFiles.swift (new)
    - test: green — swift test 113 passed, 0 failed, 11 suites (up from 110 in 10); swift build --build-tests 0 warnings, 0 errors
    - commit: 62a4f75 docs: correct Router-era claims left after the removal
    - review: findings — 1 open. The engine matched no validator to README.md or plan.md and reported both as not reviewed, so the reviewer audited those two by hand. That was the right call: they are the substance of this card.

    ### Verified true (reviewer checked each against the code)
    - Ranker at 35447e4 declares `dependencies: []` and `.macOS("27.0")`, so the corrected manifest claims hold.
    - Package.swift declares exactly one dependency.
    - BM25.primaryFieldWeight is 5.0 and bodyFieldWeight is 1.0, matching the README's "id field x5, block x1".
    - The `commit` block really never contains the word "commit"; ReadmeExampleTests pins the ranking with a drift guard that re-reads the README.
    - No Router string survives in Package.swift, Sources/, or README.md.

    ### The finding
    plan.md:26 — decision #14's header promises "Every section below that describes a Router-backed path is history, and says so." Section 5 does not. Its older undated "Superseded as shipped" marker at plan.md:170 still reads "`Signals`/`TextEmbedding`/`RoutedEmbedderAdapter` remain visible to this package's consumers unchanged."

    `RoutedEmbedderAdapter` is deleted upstream, so that is a present-tense claim about today's public surface, and it is false. Decision #14's own supersedes list at plan.md:395 names §10, §1, §6, §12, §13 and §14/M7 — §5 is absent.

    This is not retained history. It is a superseding marker that itself asserts a deleted type is currently exported.
  timestamp: 2026-08-30T13:12:51.113639+00:00
- actor: claude-code
  id: 01m19ddrm5k6ah4ebcj6jgc9q8
  text: |-
    Finding fixed, and the cause removed from the whole of `plan.md`.

    **The finding itself, both shapes.** The finding offered two shapes and said to prefer the file's idiom. The file's idiom turned out to be both: §10, §12 and §13 carry a dated head blockquote, §14/M7 and §15 carry a dated inline parenthetical, and §1 and §6 were covered only by decision #14's supersedes list. So §5 got both. It now opens with a dated head blockquote in the §10/§12/§13 shape, and §5 is named in decision #14's supersedes list.

    The §5 blockquote does not rewrite the old sentence — the history stays. It states the true present tense beside it: `RoutedEmbedderAdapter` is deleted upstream, the cosine seam has no production conformer in this package, and what the re-export keeps visible to consumers unchanged is `RRF`/`BM25`/`Trigram`/`Tokenizer`/`Hit`/`Signals`/`TextEmbedding` alone. §5 names `RoutedEmbedderAdapter` three times, not once — the cosine-seam production wiring, the "port, don't depend" file list, and the re-export list the finding quoted — and the blockquote names all three.

    **The sweep found seven more of the same class.** Each was an unmarked present-tense claim naming something retired, and each now carries its own dated marker in the file's own idiom:

    - The summary paragraph above the status note ("Models and embedders come from `../FoundationModelsRouter`"). It sits *above* the note, and the note's promise said "Every section **below**", so nothing covered it. The promise now reads "The summary above and every section below ... is history, and says so where it stands."
    - §1's seams bullet — "production conformers wrap Router (`RoutedSession`, `RoutedEmbedder`)".
    - §2's prior-art table — credits `RoutedAgentSession` and `RoutedEmbedderAdapter` as shipped contributions.
    - §3's architecture diagram — the two substrate lines, `AgentSession seam → RoutedSession` and `TextEmbedding seam → RoutedEmbedder`.
    - §6 — `idEnumGrammar(ids:)`, the two-argument `SelectionConfig.model` with a `Grammar` parameter, `RoutedAgentSession`, and `LiveRouterSupport.buildSelectionConfig`.
    - §8 item 4 — `idEnumGrammar(ids:)` "is a pure function of the ids". It is now `idEnumSchema(ids:) throws -> String`.
    - §9's Multitool bullet — "`AgentSession` + `RoutedAgentSession` have **moved here (shipped, §6)**".
    - §11 decision 8 — "production conformers wrap Router".
    - §11 decision 12 — the `@Sendable (String, Grammar) -> any AgentSession` signature and `RoutedAgentSession` as the production wiring.
    - §14/M2 — its existing marker read "*(likewise now supplied by `FoundationModelsRanker`, §5)*", which asserted Ranker supplies `RoutedEmbedderAdapter` today. It does not. Reworded to say the seam is supplied and the port went away with nothing replacing it.
    - §14/M5 — "`AgentSession`/`RoutedAgentSession` already ship here, waiting to be imported".
    - §14/M8 — "the Router-backed ones run locally on the M7 tiny-model setup".

    **§10's marker was itself wrong.** It ended "The rest of this section is current", and the rest of that section includes the naming note's "our shipped `AgentSession` / `RoutedAgentSession`". A marker that certifies a falsehood as current is worse than no marker. The blockquote now names `RoutedAgentSession` alongside `RoutedEmbedderAdapter` before it says the rest is current, so the sentence is true.

    **Decision #14's supersedes list and its API paragraph both widened.** The list now names the summary, §2, §3, §5, §6, §8, §9, §12, §13, decision #8, decision #12 and §14's M2, M5, M7 and M8, and says each carries its own dated marker. The API paragraph said "§6/§12's signatures predate them"; decision #12 carries the same stale signature, so it now reads "the signatures in §6, §12 and decision #12".

    **Deliberately left alone.** The `### Sources` bibliography still cites `../FoundationModelsRouter/plan.md`. That is provenance — a source this plan drew on, which remains true — not a claim about the package's current dependencies. Retained history that is clearly history is not the target.

    **The header promise is true now.** Every place in the file that names the Router dependency, `RoutedSession`/`RoutedEmbedder`, `RoutedEmbedderAdapter`/`RoutedAgentSession`, `Grammar`/`idEnumGrammar`, `LiveRouterSupport` or the `IntegrationTests/` package says, where it stands, that the name is history — checked by hand against the 18 dated markers, and mechanized by the new test.
  timestamp: 2026-08-30T13:23:29.541948+00:00
- actor: claude-code
  id: 01m19debyyg3ze05wgsrw78ntm
  text: |-
    The test that guards this class of drift, and the TDD cycle behind it.

    The card asked whether a test can guard this, as `ReadmeExampleTests` guards the README. One can, and it is `Tests/FoundationModelsMetadataRegistryTests/PlanDocumentTests.swift`.

    **What it asserts, and why not the obvious thing.** The obvious test — "`plan.md` spells none of the retired names" — is the wrong test and would have to be deleted. `plan.md` is a design record; the retired names *must* stay in it, because the history is the point. The invariant that is actually true is weaker and is the one the finding turns on: a section that names something retired must also say the name is history. So the suite splits `plan.md` at its `## ` headings and asserts that any section spelling `Router`, `Routed`, `Grammar` or `IntegrationTests` also spells `decision #14`.

    **Genuine RED, and it caught the finding.** The test was written before any edit to `plan.md` and run. It failed, naming eight sections: §1, §2, §3, §5, §6, §8, §9 and §11 — which is exactly the hand inventory, §5 included. That is the finding, found mechanically. After the edits it passes.

    **What the test does not catch, stated honestly in its own doc comment.** Section granularity means one marker clears the whole section it sits in. A stale sentence inside an already-marked section still passes — §14/M2, M5 and M8 were all inside a §14 that already carried M7's marker, so the test would not have found them, and they were found by hand and fixed by hand. Finer granularity was considered and rejected: paragraph or list-item splitting of a markdown file with multi-line list items, fenced code blocks and box-drawing diagrams is brittle enough that the test would fail on formatting rather than on truth. The suite says so where a reader will see it.

    **Rules preloaded before writing it** — `dump validators` over `PackageManifestTests.swift` and `plan.md` returned code-hygiene, code-security, completeness, duplication, reuse, swift and test-integrity. Three of them changed the code as written:

    - `duplication`: `sectionsMissingTheSupersededMarker()` first had the same `compactMap` / `filter` / `guard` / `joined` shape as `PackageManifestTests.filesSpellingARemovedRouterName()`. Rewritten as a `for ... where` loop, which is also the form the swift `idioms` rule prefers. The repository-root walk was not re-derived at all — `RepositoryFiles` already exists for exactly this, so a fourth copy never happened.
    - `naming-clarity`: the accumulator was `found`, a name for a type rather than a role. It is `collected`.
    - `missing-docs-swift`: nothing in the file is `public`, so swiftlint requires no doc comment on it, but the suite, every constant and both helpers carry one anyway, matching the density of the suites beside it.

    **A stale doc comment fixed on the way.** `TestSupport/RepositoryFiles.swift` said it served "the manifest and the README". There are three callers now. It says "the manifest, the README, and the plan". Leaving that would have been the same defect this card is about, in the test support.

    **Verification:** `swift test` is 114 passed / 0 failed in 12 suites, up from 113 in 11. `swift build --build-tests` reports zero warnings and zero errors. `git status` shows only `plan.md`, `RepositoryFiles.swift`, the new `PlanDocumentTests.swift` and the card's own `.kanban` files. Nothing committed. `stash@{0}` untouched.
  timestamp: 2026-08-30T13:23:49.342587+00:00
- actor: claude-code
  id: 01m19degaytd0kv3gttf8cpg2k
  text: |-
    ### implement — changed
    - evidence: 3 files — plan.md, Tests/FoundationModelsMetadataRegistryTests/PlanDocumentTests.swift (new), Tests/FoundationModelsMetadataRegistryTests/TestSupport/RepositoryFiles.swift. `swift test` 114 passed / 0 failed in 12 suites (was 113 in 11). `swift build --build-tests` 0 warnings, 0 errors. The open finding is checked; 0 findings remain open. Not committed; `stash@{0}` untouched.
    - next: ready for `/review`.
  timestamp: 2026-08-30T13:23:53.822329+00:00
depends_on:
- 01M16Y5CNB3P7E5ESF43AEAKQ4
position_column: doing
position_ordinal: '80'
title: Update the docs that describe the Router dependency
---
## What

Many doc comments and design notes still say this package is built over FoundationModelsRouter. After the dependency is gone, those statements are wrong. Correct them.

Files to change:
- `Package.swift` — rewrite the manifest header comment (lines 173-185), which says "A single library target over the FoundationModelsRouter sibling" and describes the live-Router examples. Rewrite the `foundationModelsRankerPackage` comment (lines 26-37), which explains the Router pin unification that no longer applies. Rewrite every remaining target comment that names Router, MLX, or a gated real-model path.
- `Sources/FoundationModelsMetadataRegistry/FoundationModelsRankerReexport.swift` — the comment lists `RoutedEmbedderAdapter` and `RoutedAgentSession` (lines 6, 9) among the re-exported types. Both are deleted. Correct the list.
- `plan.md` — §10 and §13 describe the Router dependency and the live-Router examples. Add a note that records the decision and the new state. Do not rewrite the history; record what changed and why.
- `README.md` — check it. A grep for Router, MLX, and Hugging Face currently finds nothing, so it may need no change. Confirm the usage example still compiles against the current API.

## Acceptance Criteria

- [x] No comment in `Package.swift` or `Sources/` claims this package depends on FoundationModelsRouter.
- [x] `FoundationModelsRankerReexport.swift`'s type list matches what FoundationModelsRanker actually exports.
- [x] `plan.md` records the Router removal decision.
- [x] The `README.md` usage example compiles.

## Tests

- [x] Add a test in `Tests/FoundationModelsMetadataRegistryTests/PackageManifestTests.swift` that asserts `Package.swift` and every file in `Sources/` contain no `FoundationModelsRouter`, `RoutedEmbedderAdapter`, or `RoutedAgentSession` string.
- [x] Extract the `README.md` usage example into a test in `Tests/FoundationModelsMetadataRegistryTests/ReadmeExampleTests.swift` and assert it produces the ranked output the README shows.
- [x] Run `swift test`. All tests pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-08-30 08:05)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 4 file(s) reviewed, 6 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 2 file(s) not reviewed — no validator matched:
> - `README.md` — no validator matches this file
> - `plan.md` — no validator matches this file

The engine returned zero findings on the four files it reviewed. `README.md` and `plan.md` carry the substance of this card and no validator matched either one, so their claims were checked by hand against the current code. One claim is not true.

- [x] `plan.md:26` `manual/doc-truth` — the added decision #14 header states "Every section below that describes a Router-backed path is history, and says so", but §5's older undated "Superseded as shipped" marker at `plan.md:170` still says `Signals`/`TextEmbedding`/`RoutedEmbedderAdapter` "remain visible to this package's consumers unchanged". `RoutedEmbedderAdapter` is deleted, so that sentence is a present-tense claim about today's public surface, and it is false. Decision #14's own supersedes list at `plan.md:395` names §10, §1, §6, §12, §13 and §14/M7, but not §5, so no marker corrects it. Add §5 to decision #14's supersedes list, or mark `plan.md:170` the way the other six places are marked.
  - Fixed 2026-08-30 by both shapes the finding names, and the cause was removed from the whole file. §5 now carries its own dated head blockquote that says what the re-export keeps visible to consumers today, and §5 is also named in decision #14's supersedes list. A sweep of the rest of `plan.md` found seven more places making an unmarked present-tense claim naming a retired type; each now carries its own dated marker. `PlanDocumentTests` guards the class of drift.

Claims checked and found true against the current code:

- FoundationModelsRanker declares `dependencies: []` (`.build/checkouts/FoundationModelsRanker/Package.swift:86`), so `Package.swift:28` and `plan.md:399` are both correct.
- `Package.swift:143-145` declares exactly one dependency.
- Ranker declares `.macOS("27.0")` (`.build/checkouts/FoundationModelsRanker/Package.swift:78`), so the re-sourced floor at `Package.swift:131-133` is correct.
- `BM25.primaryFieldWeight` is `5.0` and `BM25.bodyFieldWeight` is `1.0`, so the README's "id field ×5, block ×1" at `README.md:36` is correct.
- `README.md:37-38` is correct: the `commit` item's block never contains the word `commit`, and `ReadmeExampleTests.commitRanksFirstForTheReadmeQuery()` pins that ranking.
- No `FoundationModelsRouter`, `RoutedEmbedderAdapter`, or `RoutedAgentSession` string is in `Package.swift`, `Sources/`, or `README.md`.