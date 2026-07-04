# Plan: FoundationModelsMetadataRegistry — hybrid metadata search for FM sessions

A Swift package providing **one generic ability: search over a catalog of metadata** —
Swift values rendered to text blocks (YAML, JSDoc, plain prose) — on behalf of a
Foundation Models session, without the catalog ever entering that session's context.
It is the extraction of a pattern that already exists twice and is about to exist twice
more: the Skills plan's `SkillSearchAgent`, the Multitool's shipped `Librarian`, and the
coming needs of [`../FoundationModelsAgents`](../FoundationModelsAgents/plan.md) and MCP
tool/resource catalogs. Retrieval rides the rank-fusion engine ported in
[`CodeContextKit`](../CodeContextKit/plan.md) (BM25 + trigram + cosine → RRF); selection
rides a **dynamic Router session** (the librarian pattern, lifted from
[`../FoundationModelsMultitool`](../FoundationModelsMultitool/plan.md)). Models and
embedders come from [`../FoundationModelsRouter`](../FoundationModelsRouter/plan.md).
**Primary target: macOS 27+, on-device.**

> **Status: implemented.** The library (M1–M4), the gated Router integration
> suite (M7), and the full `Examples/` suite (M8) are shipped in this repo;
> §14 tracks per-milestone status. M5 (Multitool migration) and M6 (Skills
> adoption) are pending and land in their own repos. Where the implementation
> refined the original design, the sections below describe what shipped and
> mark the superseded idea inline.

---

## 1. Guiding principles

- **Extract, don't invent.** The Multitool `Librarian` (shipped: cached-root +
  fork-per-call prefix reuse, capacity fallback, guided output, `AgentSession` seam) is
  the selection tier; CodeContextKit's `RRF`/`BM25`/`Trigram`/`TextEmbedding` (shipped:
  three ranked signals fused by rank) is the retrieval tier. This package is those two
  proven halves composed behind one generic surface.
- **The rendered block IS the search context.** A domain conforms its metadata to
  `SearchableMetadata` (`id` + `renderBlock()`); the package indexes, retrieves, and
  seeds sessions with those blocks and **never interprets their contents**. YAML for
  skills, TS+JSDoc for tools, frontmatter summaries for agents — all the same to us.
- **Verbatim by construction, not by prompt.** The selection model returns **ids only**;
  the searcher maps ids back to catalog entries and returns the catalog's own blocks.
  No model ever re-types a block it selected. (Upgrades Multitool's prompt-enforced
  "pick, don't paraphrase" to a structural guarantee.)
- **Rank fusion before language models.** Cheap ranked signals (BM25, trigram, cosine)
  retrieve; the LLM only ever *selects among already-retrieved candidates*. On big
  catalogs the LLM never sees more than a page of candidates; on small ones it can hold
  the whole catalog as a cached prefix.
- **Hot reload is load-bearing, not a nicety.** Skills hot-reload from a file watcher;
  **MCP catalogs churn at runtime** (`listChanged` notifications for tools, resources,
  and prompts). `update(items:)` is a first-class operation with defined costs, not an
  afterthought.
- **In-memory index, no database.** Catalogs are metadata, not documents: skills and
  agents are 10¹–10², a fused tool surface is 10² — **we are not expecting 10⁴+
  items**. The entire `MetadataIndex` (tokenized fields, trigram sets, embeddings)
  lives in memory, rebuilt from the caller's items on `update(items:)`; nothing is
  persisted — no SQLite, no vector store. Retrieval is still a first-class product
  (not just an over-budget fallback) because it is free: no session, no tokens.
- **Graceful degradation.** No embedder → keyword-only retrieval (BM25 + trigram). No
  LLM → retrieval-only results. A signal absent for an item contributes nothing to its
  fused score (never zero-filled). Every degradation is reported, never silent.
- **Seams for testability.** `AgentSession` (session) and `TextEmbedding` (vectors) are
  narrow protocols; production conformers wrap Router (`RoutedSession`,
  `RoutedEmbedder`); unit tests run scripted fakes with zero GPU.

## 2. Prior art in-tree — what each contributes

| Where | Status | Contributes |
|---|---|---|
| Multitool `Librarian` + `AgentSession` | **shipped** | selection tier: cached root session seeded with the full surface, `fork()` per call for KV-prefix reuse, capacity budget (chars ≈ tokens×4), guided `@Generable` output, diagnostics-callback pattern (`onPrefilterCut`), session seam + `RoutedAgentSession` |
| CodeContextKit `Search/` + `Embedding/` | **shipped** | retrieval tier: `BM25` (field-weighted), `Trigram` Dice, cosine, `RRF.fuse`/`normalize` (k=60, 0-based ranks, absent-signal graceful), `Hit`/`Signals` explainability, `TextEmbedding` seam + `RoutedEmbedderAdapter` |
| Skills `SkillSearchAgent` (plan §7) | planned | the reload requirement (registry re-injection), visibility pre-filtering as the caller's job, `search skill` as the consuming op |
| Agents plan | opted out (small catalogs, descriptions baked into `AgentsTool`) | a future opt-in consumer when agent catalogs outgrow the baked-in surface — this plan must not contradict theirs |
| FoundationModelsMCP | planned | the churn case: tool catalogs hot-load (`listChanged`) — hundreds of entries appearing mid-session |

Multitool's `lexicallyFilter` (substring keep/drop) is the one piece deliberately **not**
lifted — it is superseded by real ranked retrieval (§5).

## 3. Architecture

```
┌ MetadataSearcher<Item> (actor) ────────────────────────────────────────────┐
│   search(intent, limit) → [Match<Item>]        update(items:) — hot reload │
│   mode: .retrieval | .selection | .auto (budget decides)                   │
├ Selection tier (LLM — the "dynamic session") ──────────────────────────────┤
│   under budget: cached root seeded with ALL blocks, fork() per call        │
│   over budget:  retrieval top-M candidates → one-off session               │
│   output: ids only, xgrammar-constrained to the candidate id enum          │
├ Retrieval tier (ranked signals → rank fusion) ─────────────────────────────┤
│   BM25 (id ×5, block ×1) · char-trigram Dice · cosine (TextEmbedding)      │
│   → RRF.fuse (k = 60) → normalize [0,1] → [Hit(id, score, signals)]        │
├ Catalog ───────────────────────────────────────────────────────────────────┤
│   SearchableMetadata: id + renderBlock()   (domain renders; we never parse)│
│   MetadataIndex: entries, tokenized fields, trigram sets, embeddings       │
└────────────────────────────────────────────────────────────────────────────┘
     Session substrate:  AgentSession seam → RoutedSession   (Router)
     Vector substrate:   TextEmbedding seam → RoutedEmbedder (Router .embedding)
```

## 4. The catalog contract

```swift
public protocol SearchableMetadata: Sendable {
  var id: String { get }              // stable, unique within one catalog
  func renderBlock() -> String        // the text that IS this item's search surface
}

public struct Match<Item: SearchableMetadata>: Sendable {
  public let id: String
  public let block: String            // VERBATIM from the catalog, never model output
  public let score: Double            // fused, [0,1] (1.0 for pure-selection results)
  public let signals: Signals?        // bm25/trigram/cosine — nil in pure-selection mode
  public let item: Item
}
```

- **`id` is the join key** across every tier: BM25 field, trigram target, selection-enum
  member, verbatim-lookup key. Domains already have one (skill directory name, tool
  `path`, agent `name`, MCP tool name / resource URI).
- **Two-field indexing, mirroring CodeContextKit**: the `id` is indexed as its own field
  at weight ×5 (the `symbol_path` treatment), the block at ×1 — so `"deploy"` finds the
  `deploy` skill lexically even when its description never says the word.
- Optional `renderSummaryBlock()` (default = `renderBlock()`) lets a domain seed the
  *selection prefix* with something shorter than what retrieval indexes — relevant for
  MCP resources whose full description is large.

## 5. Retrieval tier — signals & rank fusion *(from CodeContextKit)*

Three independent signals per query, each producing a **ranking**, fused by rank —
never by raw score (the scales are incomparable: BM25 unbounded, Dice aggregate can
exceed 1, cosine in [-1,1]):

1. **BM25** over tokenized text, two weighted fields (`id` ×5, block ×1).
2. **Character-trigram Dice** — typo and partial-identifier tolerance
   (`"kuberntes deploy"` still finds `deploy-k8s`).
3. **Cosine** between the query embedding and block embeddings, via the `TextEmbedding`
   seam (production: Router's `.embedding` slot through `RoutedEmbedderAdapter`).

**Fusion is Reciprocal Rank Fusion**, ported intact:

```
score(item) = Σ_signal  weight_signal / (K + rank_signal(item))      K = 60, ranks 0-based
```

- An item **absent from a signal contributes nothing** for that signal — an un-embedded
  item still ranks by BM25 + trigram; a catalog with no embedder degrades to
  keyword-only with a diagnostic, exactly CodeContextKit's graceful-degradation rule.
- Fused scores normalize to [0,1] (divide by the best-possible: rank 0 in every
  weighted signal); each `Hit` carries its raw per-signal `Signals` for explainability
  and threshold-tuning.
- Per-signal `weights` are configuration (default 1.0 each), so a domain can, e.g.,
  damp trigram for prose-heavy resource catalogs.

**Port, don't depend.** `RRF.swift`, `BM25.swift`, `Trigram.swift`, `Tokenizer.swift`,
`Hit.swift`, `TextEmbedding.swift`, `RoutedEmbedderAdapter.swift` are small,
self-contained files (themselves ports of the Rust `swissarmyhammer-search` crate);
CodeContextKit's remaining mass (tree-sitter, LSP, chunking) is dead weight here. Copy
them with attribution. *(If a third copy ever appears, extract a shared
`SwiftRankFusion` micro-package — noted, not done.)*

**Scale.** Everything lives **in memory** — no database, no vector store, no ANN, no
persistence. Expected catalogs are 10¹–10³ items (we are not designing for 10⁴+), so
brute-force scoring — plain per-row dot products for cosine — is exact and effectively
instant; CodeContextKit's own no-vector-DB reasoning holds *a fortiori* at metadata
scale. If a catalog ever outgrows this, the `MetadataIndex` API is the seam:
CodeContextKit's shipped contiguous row-major matrix + vDSP matvec design drops in
behind it unchanged. Embedding is the *slow* path — it happens at `update()` time,
incrementally (§8), never at query time (only the query itself is embedded per search).

## 6. Selection tier — the dynamic session *(from Multitool's Librarian)*

The LLM's job is **selection among candidates, never retrieval**: given an intent and a
set of rendered blocks, return the fewest items that suffice, in call order when order
matters (the librarian's selection guidance, kept verbatim as the default preamble;
domains can override it).

Mechanics, lifted from the shipped `Librarian` and generalized:

- **Under budget** (assembled prefix ≤ `capacityCharacterLimit`, default 32,000 chars ≈
  the 8K-token default context at ~4 chars/token): a **cached root session** is seeded
  once with preamble + every block; each `search()` **forks a child** and asks it — the
  prefix's KV cache is prefilled once and inherited per call (`AgentSession.fork()`,
  Router `KVCache.copy()` underneath). Reload is the only thing that invalidates it.
- **Over budget**: the retrieval tier ranks the catalog and the top-M candidates
  (default 24) seed a **one-off session** — no stable prefix exists, so nothing is
  cached. This *replaces* Multitool's `lexicallyFilter` keep/drop with real ranked
  retrieval; the cut is still reported, as `.retrievalCut(considered:kept:)` on the
  unified diagnostics channel (below).
- **Ids only, grammar-enforced.** The guided output type is
  `@Generable struct Selection { var ids: [String] }`;
  `SelectionTier.idEnumGrammar(ids:)` derives the xgrammar JSON Schema constraining
  `ids` to an **enum of the candidate ids** (per-element `enum` + `uniqueItems`).
  Router's xgrammar enforcement is real (unlike Apple's built-in enum path, per Skills
  decision #22), so the selector is structurally incapable of inventing an id.
  *As shipped*, the grammar reaches the session through the caller: `SelectionConfig
  .model` is a **session factory** `(instructions) -> any AgentSession`, and the
  production factory bakes the grammar into the guided sessions it vends
  (`RoutedAgentSession(session: llm.makeGuidedSession(grammar, instructions:))` — the
  `LiveRouterSupport.buildSelectionConfig` pattern). Over budget, membership in the
  top-M candidate set is enforced by the verbatim-lookup filter rather than a per-call
  grammar.
- **Verbatim lookup.** Returned ids map back through the catalog to produce `Match`es
  carrying the catalog's own blocks. Unknown ids from the model are impossible by
  grammar; a defensive `allowedIds` filter + `.unknownSelectedId` diagnostic backstops
  it anyway.
- **One diagnostics channel.** Instead of per-event closures (`onPrefilterCut`-style),
  everything reports through `onDiagnostic: (MetadataDiagnostic) -> Void` — cases
  `.duplicateId`, `.embeddingUnavailable`, `.unknownSelectedId`,
  `.retrievalCut(considered:kept:)`, `.embedCatchUp(pending:total:)` — defaulting to an
  `os.Logger` sink (`MetadataDiagnostic.log`).
- The session comes through the **`AgentSession` seam** (`respond(to:)` + `fork()` +
  default `respond(to:generating:)` decoding via `GeneratedContent(json:)`), with
  `RoutedAgentSession` wrapping a session vended by
  `RoutedLLM.makeGuidedSession(_:instructions:)` in production — lifted from Multitool
  and now shipped here, for Multitool to import back (M5).

## 7. Modes

```swift
public enum SearchMode: Sendable {
  case retrieval          // signals + RRF only; no session, no tokens — cheap & fast
  case selection          // LLM selects; retrieval used only when over budget
  case auto               // default: selection when a model is configured, else retrieval
}
```

- **`.retrieval`** is the whole story for many callers: an MCP resource picker, a UI
  typeahead, Skills' "Spotlight RAG for large catalogs" idea — all are this mode. It
  answers in milliseconds with `signals` attached.
- **`.selection`** is the librarian/search-agent behavior: intent-level matching
  ("the warmest city on my trip" → `tripCities` + `weather`) that lexical/semantic
  ranking alone can't do, because it requires reasoning about *task decomposition*.
- Retrieval ordering is passed to the selection prompt as candidate order (best first)
  — the model sees the ranking but decides membership.

## 8. Hot reload — `update(items:)`

Driven by the caller: `SkillsRegistry` reload publication, MCP `listChanged`
notifications, a Multitool rebuild. Semantics:

1. Re-render blocks; rebuild tokenized/trigram indexes (fast, synchronous).
2. **Re-embed incrementally**: only items whose rendered block changed (keyed by
   `(id, block-hash)`) are re-embedded; embedding runs async and retrieval serves
   keyword-only for not-yet-embedded items in the interim (absent-signal rule, §5).
3. Drop the cached root session; the next under-budget `search()` rebuilds it (one
   prefix re-prefill — the accepted reload cost, stated in Skills §7 already).
4. Rebuild the id-enum grammar with the new id set — `idEnumGrammar(ids:)` is a pure
   function of the ids, so the rebuilt selection tier assembles a fresh prefix and a
   caller whose session factory bakes in the grammar (§6) refreshes that factory
   alongside `update(items:)`.
5. Surface the interim gap: `.embedCatchUp(pending:total:)` diagnostics report how many
   items are still serving keyword-only while embedding catches up.

`update` is cheap to call redundantly (hash-guarded), so callers may forward every
upstream change notification without coalescing. MCP's churn rate is the design target:
a server connecting mid-session dumps hundreds of tools/resources into the catalog and
they must be searchable immediately (keyword tiers) and semantically shortly after
(embed catch-up), with a progress/diagnostic surface for the gap.

## 9. Consumers & migration

- **FoundationModelsSkills** — `SkillSearchAgent` becomes
  `MetadataSearcher<SkillMetadata>` (blocks: YAML-ish id/description/params; visibility
  filtering stays the caller's job — pass the model-visible subset). The `search skill`
  op delegates to it; registry reload forwards to `update(items:)`. *(Skills plan §7 +
  decision #12 to be updated; pulls the Router dependency into Skills — flagged there.)*
- **FoundationModelsMultitool** — `Librarian` becomes a thin wrapper over
  `MetadataSearcher<APISurface.Entry>` (blocks: the existing `Entry.block`); `FoundAPIs`
  becomes formatting in `FindAPITool` over verbatim `Match.block`s; `AgentSession` +
  `RoutedAgentSession` move here and are re-exported/imported. Behavior deltas Multitool
  gains: ids-only selection, id-enum grammar, RRF instead of `lexicallyFilter`.
- **FoundationModelsMCP** — tool catalogs and **resource catalogs** as
  `SearchableMetadata` (id = tool name / resource URI; block = rendered
  name+description+schema/mime summary). Hot-loads on `listChanged`; churn, not
  scale, is the demand it puts on us (§8). Likely first `.retrieval`-mode consumer.
- **FoundationModelsAgents** — no change now (its plan deliberately bakes descriptions
  into `AgentsTool`; catalogs are small). When a deployment's agent catalog outgrows
  that, `MetadataSearcher<AgentListing>` is the opt-in, and their plan's "no separate
  search agent" decision gets revisited *there*, not preempted here.

## 10. Dependencies & packaging

- **Single SwiftPM library target `FoundationModelsMetadataRegistry`**, macOS 27+ (the
  Router floor; same platform commitment as Multitool/Agents, no fallback paths), plus
  the `Examples/` executable targets (§13) — demos only, never a dependency of the
  library.
- **Depends on `FoundationModelsRouter`** for `RoutedLLM`/`RoutedSession` (selection),
  `RoutedEmbedder` (cosine), and `Grammar` (xgrammar id enums). The *core* — catalog,
  signals, RRF, both seams — compiles and unit-tests with no Router at runtime (fakes
  conform to the seams); Router is exercised only by production conformers and the
  gated integration suite.
- **No dependency on** Skills, Multitool, Agents, MCP, or CodeContextKit (consumers
  depend on us; CodeContextKit files are ported, §5).
- **Naming note:** in the sibling plans "Registry" means a *file-backed source of
  truth* (`SkillsRegistry`, `AgentRegistry`). This package holds a **derived index over
  someone else's registry** — hence the central types are `MetadataSearcher` /
  `MetadataIndex`, and only the package keeps the user-chosen `MetadataRegistry` name.

## 11. Resolved decisions

1. **Extraction, two tiers** — selection = Multitool's `Librarian` skeleton
   (cached-root + fork-per-call, capacity budget, diagnostics callbacks); retrieval =
   CodeContextKit's signal + RRF stack. Both lifted, composed, generalized.
2. **Catalog contract → `SearchableMetadata`** (`id` + `renderBlock()`, optional
   `renderSummaryBlock()`); the package never interprets block contents; two-field
   indexing (id ×5, block ×1).
3. **Fusion → RRF**, k = 60, 0-based ranks, absent-signal-contributes-nothing,
   [0,1] normalization, `Hit`/`Signals` explainability — ported unchanged.
4. **Selection output → ids only**, xgrammar-constrained to the candidate id enum;
   blocks returned verbatim from the catalog by lookup. Supersedes the
   reproduce-the-block shape of Multitool's `FoundAPIs` (which becomes formatting).
5. **Over-budget path → retrieval top-M + one-off session**, replacing lexical
   keep/drop filtering; cuts reported as `.retrievalCut(considered:kept:)` diagnostics.
6. **Modes → `.retrieval` / `.selection` / `.auto`**; retrieval is a first-class
   product, not a fallback (free to call: no session, no tokens).
7. **Hot reload → `update(items:)`**: hash-guarded, incremental re-embedding, async
   embed catch-up with keyword-only interim service, root-session + grammar rebuild.
   Required by Skills (file watch) *and* MCP (`listChanged`).
8. **Seams → `AgentSession` + `TextEmbedding`**, production conformers wrap Router;
   both lifted from the shipped implementations (Multitool, CodeContextKit).
9. **Port, don't depend** for the CodeContextKit search files; extract a shared
   micro-package only if a third copy appears.
10. **In-memory index, no DB** — the whole index (tokenized fields, trigram sets,
    embeddings) is rebuilt in memory from the caller's items; nothing is persisted.
    Expected scale is 10¹–10³ items, where brute-force scoring is exact and
    sufficient; the `MetadataIndex` API is the seam to swap in CodeContextKit's
    shipped contiguous-matrix/vDSP design if a catalog ever demands it.
11. **Agents stays opted out** — their baked-in-descriptions decision is respected;
    this package is their future option, not a requirement.
12. *(shipped refinement)* **`SelectionConfig.model` is a session factory** —
    `@Sendable (String) -> any AgentSession`, called with the assembled prefix as
    instructions. The library never constructs Router sessions itself; the caller's
    factory decides the model, the grammar, and the wiring (production:
    `RoutedAgentSession` over `makeGuidedSession(grammar, instructions:)`). This keeps
    the whole selection tier testable against scripted fakes and leaves grammar
    ownership with the party that owns the id set's lifecycle.
13. *(shipped refinement)* **One diagnostics channel, not per-event closures** —
    `onDiagnostic: (MetadataDiagnostic) -> Void` with a typed case per event
    (`.duplicateId`, `.embeddingUnavailable`, `.unknownSelectedId`, `.retrievalCut`,
    `.embedCatchUp`), defaulting to an `os.Logger` sink. New diagnostics add a case,
    not a parameter.

## 12. Public API (as shipped)

```swift
// Domain side — e.g. Skills:
extension SkillMetadata: SearchableMetadata {
  var id: String { skillID }                       // directory name
  func renderBlock() -> String { /* YAML-ish id/description/params */ }
}

// Build a searcher (selection + retrieval, Router-backed). The `model`
// parameter is a session factory (§6, decision #12): the caller vends
// grammar-constrained sessions from the assembled prefix.
let grammar = try SelectionTier.idEnumGrammar(ids: items.map(\.id))
let searcher = await MetadataSearcher(
  items: registry.metadata().filter(\.isModelVisible),   // visibility = caller's job
  mode: .auto,
  weights: Weights(bm25: 1, trigram: 1, cosine: 1),
  embedder: RoutedEmbedderAdapter(routedEmbedder: profile.embedding), // omit → keyword-only
  selection: SelectionConfig(
    model: { instructions in
      RoutedAgentSession(session: profile.standard.makeGuidedSession(grammar, instructions: instructions))
    },
    preamble: .librarianDefault,                          // "fewest that suffice…"
    capacityCharacterLimit: 32_000,
    candidateLimit: 24),
  onDiagnostic: { MetadataDiagnostic.log($0) }            // the default sink
)

// Search — intent in, verbatim blocks out:
let matches = try await searcher.search(intent: "commit my changes", limit: 5)
// matches[0].id == "commit"; .block is the catalog's own rendered text;
// .signals shows why (bm25/trigram/cosine) when retrieval participated.

// Hot reload — file watcher, MCP listChanged, rebuild — all the same call:
registry.onReload { meta in Task { await searcher.update(items: meta) } }

// Retrieval-only (no session, no tokens, sync init) — e.g. an MCP resource picker:
let picker = MetadataSearcher(items: resources, mode: .retrieval)
let hits = try await picker.search(intent: "quarterly revenue spreadsheet", limit: 10)
```

Three initializers ship: `init(items:...)` (sync, keyword-only index),
`init(items:...embedder:...) async` (embeds the catalog up front), and
`init(index:...)` over a prebuilt `MetadataIndex` for precise control.
`.selection` mode without a `SelectionConfig` throws `SelectionTierUnavailable`.

## 13. Examples

Examples are **explicit, runnable deliverables** — each a small executable
target under `Examples/` (`swift run <Name>`), kept compiling in CI (the family
convention, per the MCP plan). Retrieval-only examples run anywhere, GPU-free;
Router-backed ones compile in CI and run locally against tiny `mlx-community`
models (the M7 pattern). Together they are the living documentation of every
capability in this plan.

*As shipped*, each example splits into a thin `<Name>` executable and a
`<Name>Core` library target holding the demo's logic — the cores are exercised
by the main unit-test target, so every example stays correct GPU-free, not just
compiling. Two shared support targets round it out: `ExamplesSupport` (common
fixture catalogs and printing helpers) and `LiveRouterSupport` (live Router
profile resolution, `idEnumGrammar(ids:)` construction, and the
`RoutedAgentSession` session-factory wiring used when an example runs against
real models). The examples:

1. **`CatalogSearch`** — the ~30-line hello world. A handful of fixture items
   conformed to `SearchableMetadata`, a keyword-only
   `MetadataSearcher(mode: .retrieval)` (no embedder, no model), one query,
   printed `Match`es with their per-signal `Signals` — BM25, trigram, RRF, and
   explainability on one screen. Proves the M1 core.
2. **`SemanticSearch`** — `CatalogSearch` plus `RoutedEmbedderAdapter`: the
   cosine signal joins fusion and a paraphrased query ("save my work" →
   `commit`) now ranks where keywords alone miss. Run with `--no-embedder` to
   watch the graceful keyword-only degradation and its diagnostic. ↔ M2.
3. **`Librarian`** — selection mode end-to-end on a Router model: cached root
   session seeded with the catalog, `fork()` per query, ids-only
   xgrammar-constrained selection, verbatim blocks out. Drives intent-level
   queries ("the warmest city on my trip" → `tripCities` + `weather`) that
   ranking alone can't answer. ↔ M3.
4. **`BigCatalog`** — the headroom story: a synthetic catalog an order of
   magnitude past expectation (~10³ entries, ids = URIs), the in-memory index
   answering retrieval in milliseconds with timings printed, then a selection
   query that overflows the budget → top-M candidates → one-off session, with
   the `.retrievalCut` diagnostic shown. ↔ M3 + decision #10.
5. **`HotReload`** — churn under fire: `update(items:)` bursts (MCP-style
   add/remove), items keyword-searchable immediately, cosine catching up
   asynchronously (hash-guarded incremental re-embed, progress surfaced), root
   session + id-enum grammar rebuilt. ↔ M4.

Each example doubles as the acceptance demo for its milestone (`CatalogSearch`
↔ M1, `SemanticSearch` ↔ M2, `Librarian` ↔ M3, `HotReload` ↔ M4,
`BigCatalog` ↔ decision #10).

## 14. Milestones

- ✅ **M1 — Catalog + retrieval core.** `SearchableMetadata`, `MetadataIndex`, ported
  `Tokenizer`/`BM25`/`Trigram`/`RRF`/`Hit`, two-field indexing, keyword-only
  `search(mode: .retrieval)`. Pure unit tests, no Router, no GPU.
- ✅ **M2 — Embedding signal.** `TextEmbedding` seam + `RoutedEmbedderAdapter` port,
  cosine signal, absent-signal degradation, incremental embed keyed by block hash.
  `FakeEmbedder` tests.
- ✅ **M3 — Selection tier.** `AgentSession` seam (lifted), cached-root + fork-per-call,
  capacity budget, ids-only `Selection` decoding, verbatim lookup, id-enum grammar
  construction. Scripted-fake session tests (fork counts, over/under-budget paths,
  grammar id sets).
- ✅ **M4 — Hot reload.** `update(items:)` end-to-end: index rebuild, incremental
  re-embed, root/grammar invalidation, `.retrievalCut`/degradation diagnostics.
- ⬜ **M5 — Multitool migration.** `Librarian` re-based on `MetadataSearcher`;
  `AgentSession` moves here; `FoundAPIs` becomes `FindAPITool` formatting; Multitool's
  existing librarian tests keep passing against the wrapper. *(Lands in the Multitool
  repo — `AgentSession`/`RoutedAgentSession` already ship here, waiting to be
  imported.)*
- ⬜ **M6 — Skills adoption.** `MetadataSearcher<SkillMetadata>` behind the `search skill`
  op *(lands with Skills M4; updates Skills plan §7 + decision #12)*.
- ✅ **M7 — Gated integration.** Router-backed suite (tiny `mlx-community` models, the
  Router test pattern): real fork-per-call prefix reuse, xgrammar id-enum enforcement,
  embed + RRF quality smoke over a fixture catalog, reload under churn (MCP-style
  add/remove bursts). Shipped as `Tests/.../Integration/RouterIntegrationTests.swift`.
- ✅ **M8 — Examples.** The `Examples/` suite (§13): `CatalogSearch`,
  `SemanticSearch`, `Librarian`, `BigCatalog`, `HotReload` — each a runnable
  executable target (`swift run <Name>`) over a unit-tested `<Name>Core`, compiled
  in CI; the Router-backed ones run locally on the M7 tiny-model setup.
  `CatalogSearch` and `Librarian` double as the human-facing E2E.

## 15. Testing

Unit tier is GPU-free by construction: signals and RRF are pure functions over injected
corpora (table-driven, plus golden rankings for a fixture catalog); the selection tier
runs against scripted `AgentSession` fakes (assert fork-per-call, one-off-over-budget,
id-enum membership, verbatim lookup); reload asserts hash-guarded re-embeds and cache
invalidation with a counting `FakeEmbedder`. The gated integration suite (M7) follows
the Router pattern: `.serialized`, opt-in env var, tiny real models.

---

### Sources
- FoundationModelsMultitool — `Librarian`/`AgentSession`/`APISurface` (shipped selection tier) — ../FoundationModelsMultitool
- CodeContextKit — `Search/` + `Embedding/` (shipped retrieval tier; Rust `swissarmyhammer-search` port) — ../CodeContextKit
- FoundationModelsSkills plan §7 (SkillSearchAgent, consumer) — ../FoundationModelsSkills/plan.md
- FoundationModelsAgents plan (deliberate non-consumer, for now) — ../FoundationModelsAgents/plan.md
- FoundationModelsRouter plan (models, embedder, xgrammar, fork/KV) — ../FoundationModelsRouter/plan.md
- Reciprocal Rank Fusion — Cormack, Clarke & Buettcher, SIGIR 2009 (the K=60 constant)
- MCP specification — tools/resources/prompts list + `listChanged` notifications — https://modelcontextprotocol.io/specification
