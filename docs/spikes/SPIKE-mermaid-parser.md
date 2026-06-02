---
status: Complete
question: |
  What is the smallest line-oriented mermaid extractor that gives FC07
  enough signal to reconcile node-set, edges, and class assignments
  against the parsed issues table, and how strict should the v1 notice
  be across each reconciliation dimension?
timebox: "1 session"
---

# SPIKE: mermaid-parser feasibility for table-diagram reconciliation

## Status

Complete

## Question

FC07 reconciles a plan or roadmap's Implementation Issues table against
its Dependency Graph mermaid block across three dimensions: the node
set, the edge set, and the class assignments versus row Status. The
spike answers two coupled questions:

1. What is the minimum mermaid subset the extractor must parse so FC07
   can build the node, edge, and class views it needs? The extractor
   is stdlib-only -- no full mermaid grammar, no new dependency.
2. How strict should v1 be on each reconciliation dimension, given
   that FC07 ships as a notice (not an error) and must not redden CI
   on the present committed-diagram corpus?

## Context

This spike is the explicit upstream of #119, the FC07 implementation
increment, on the shirabe `roadmap-plan-standardization` milestone
(#6). It exists for three reasons:

- **The design (Decision 3) stages reconciliation behind a feasibility
  spike** to size the grammar problem before any code lands. The
  design rejected pulling in a full mermaid parser and committed to a
  line-oriented stdlib-only extractor over the narrow subset the
  committed docs use. The spike confirms that the subset is
  enumerable and that the corpus has no construct that forces a
  general grammar.

- **#112 produces the parsed `Table`** FC07 reuses on the table side.
  The reconciliation check has only one new parser to build (the
  mermaid extractor); everything table-shaped is settled. The spike
  bounds that one new parser.

- **#119's scope grew during milestone implementation** to fold in
  class-assignment reconciliation against table Status. PR #147
  hand-fixed a class-versus-Status drift in
  `docs/plans/PLAN-roadmap-plan-standardization.md` (closed issues
  still classed `blocked`) that no automated check caught. The spike
  must therefore enumerate the `class IXXX done|ready|blocked`
  statement shapes the extractor sees, since FC07 reads them as a
  third reconciliation view.

The strictness recommendation matters because FC07 ships notice-level
via `IsNotice` (the SCHEMA precedent in `crates/shirabe-validate`).
A notice that fires noisily on the present corpus erodes signal; a
notice that fires too rarely defeats the point of staging.

## Approach

1. Read every fenced ```mermaid block under `docs/plans/*.md` and
   `docs/roadmaps/*.md` on `origin/main` -- five committed diagrams.
2. Enumerate every distinct syntactic construct each block uses:
   fence handling, header line, node declarations, edges, classDefs,
   class assignments, and any other line that an extractor would need
   to either parse or skip.
3. Cross-walk the enumeration against `references/dependency-diagram.md`
   (the canonical convention) and `references/issues-table.md` (the
   Status / strikethrough-on-done rules FC07's class reconciliation
   binds against).
4. Derive the minimum subset the v1 extractor must parse, the cases
   it must tolerate without panic, and the per-dimension strictness
   recommendation. Cite a committed example for every observation.

The five diagrams surveyed:

- `docs/plans/PLAN-roadmap-plan-standardization.md` (lines 87-121)
- `docs/plans/PLAN-shirabe-cli-rust-rewrite.md` (lines 273-289)
- `docs/plans/PLAN-work-on-friction-fixes.md` (lines 83-109)
- `docs/roadmaps/ROADMAP-koto-adoption.md` (lines 180-228)
- `docs/roadmaps/ROADMAP-strategic-pipeline.md` (lines 437-439)

## Syntax enumeration

### Fenced-block conventions

- Opening fence is exactly ```` ```mermaid ```` on its own line; no
  attribute extensions appear in the corpus. Example:
  `docs/plans/PLAN-roadmap-plan-standardization.md:87`.
- Closing fence is exactly ```` ``` ```` on its own line. The closing
  fence may be followed by trailing content immediately (the legend
  line on the next line) but the closing fence itself is bare.
- Every PLAN and ROADMAP doc surveyed has either zero or one mermaid
  block. None has two. The extractor still has to pick a policy for
  "more than one" because nothing in the format guarantees uniqueness
  (see Edge cases).
- The empty-diagram shape exists: `docs/roadmaps/ROADMAP-strategic-pipeline.md:437-439`
  is ```` ```mermaid\ngraph TD\n``` ```` -- a header with no body.

### Header line

- Two header shapes appear: `graph TD` (four diagrams) and `graph LR`
  (one diagram, `ROADMAP-koto-adoption.md:181`). No `flowchart` form
  is used. The dependency-diagram reference forbids `flowchart`
  outright.
- The header is always on the line immediately after the opening
  fence with no blank line between. Leading indentation is zero in
  every case.

### Node declarations

- Canonical shape: `<id>["<label>"]`. Examples:
  - `I111["#111: shared references"]`
    (`PLAN-roadmap-plan-standardization.md:89`)
  - `O1["Outline 1: Cargo workspace skeleton"]`
    (`PLAN-shirabe-cli-rust-rewrite.md:275`)
  - `K65["koto#65: variables"]`
    (`ROADMAP-koto-adoption.md:195`)
- Node IDs in the surveyed corpus follow the regex `^[A-Z]+[0-9]+$`:
  `I<n>` for issue-keyed plans, `O<n>` for the Rust rewrite outline
  scheme, and `K<n>` for koto cross-repo references in the roadmap.
  The dependency-diagram reference prescribes `I<issue-number>` for
  plan diagrams; the `O<n>` and `K<n>` forms are corpus deviations
  the extractor still has to read.
- Labels are always quoted in `["..."]`. No bare-label form
  (`I111[shared references]`) appears. No alternate shape brackets
  (`{...}`, `(...)`, `>...]`) appear.
- Label content contains `#` (`I111["#111: shared references"]`),
  colons (`I117["#117: lifecycle CI + terminal wiring"]`), commas
  (none observed but trivially possible), parentheses, and ASCII
  punctuation. No escaped quote (`\"`) appears, but the extractor
  must not assume the absence.
- Indentation of node-decl lines varies: four spaces in
  `PLAN-roadmap-plan-standardization.md`, two spaces in
  `PLAN-work-on-friction-fixes.md`, four spaces in
  `PLAN-shirabe-cli-rust-rewrite.md`. The extractor must tolerate
  any leading whitespace.

### Edge declarations

- Only `-->` appears. No `---`, `==>`, `-.->`, `--text-->`, or other
  arrow variants are used in the corpus.
- Single-edge form: `I111 --> I112`
  (`PLAN-roadmap-plan-standardization.md:99`).
- Chained-edge form on one line: `O1 --> O2 --> O3 --> O4 --> O5`
  (`PLAN-shirabe-cli-rust-rewrite.md:281`). This is a single line
  declaring four edges. The extractor must split chains, not just
  match the first `-->`.
- No edge carries a label or a class assignment. The inline
  `I488:::ready --> I489:::blocked` form named in the reference as
  forbidden does not appear in the corpus.
- Edges are always after every node declaration, separated from them
  by a blank line in the four well-formed diagrams. The
  empty-diagram case has no edges.

### Class statements

The `class <id-list> <name>` directive appears in three forms in the
corpus:

- Single-key: `class I111 ready`
  (`PLAN-roadmap-plan-standardization.md:119`),
  `class I51 done` (`ROADMAP-koto-adoption.md:224`).
- Multi-key comma-separated, no spaces:
  `class I112,I113,I114,I115,I116,I117,I118,I119 blocked`
  (`PLAN-roadmap-plan-standardization.md:120`),
  `class I79,I80,I81,I82,I83,I85 needsDesign`
  (`PLAN-work-on-friction-fixes.md:106`).
- Multi-key for non-status classes:
  `class K65,K87,K104,K105,K106,K107 koto`
  (`ROADMAP-koto-adoption.md:227`),
  `class O2,O4 testable`
  (`PLAN-shirabe-cli-rust-rewrite.md:287`).

No `class IXXX,IYYY name1 name2` form (multiple classes per
statement) appears. No whitespace inside the comma-separated id list
appears. The extractor should accept whitespace inside the list as
tolerance (the reference does not forbid it), but every committed
diagram uses the no-whitespace form.

The class names observed across the corpus split into four groups:

- **Status-bearing for issue nodes**: `done`, `ready`, `blocked`,
  `needsDesign`, `needsPrd`, `needsSpike`, `needsDecision`,
  `tracksDesign`, `tracksPlan` (the nine reference palette names).
- **External-node group**: `koto` (custom class in
  `ROADMAP-koto-adoption.md` for cross-repo K-prefix nodes).
- **Complexity-bearing**: `simple`, `testable`, `critical`
  (`PLAN-shirabe-cli-rust-rewrite.md`). These map to the
  Complexity column, not the Status column. FC07 must not try to
  reconcile these against Status.
- **Unobserved-but-reference-defined**: none missing.

### classDef definitions

The `classDef <name> <styles>` form appears once per palette entry
per diagram. The full reference palette appears in two plans:
`PLAN-roadmap-plan-standardization.md:109-117` and
`PLAN-work-on-friction-fixes.md:96-104`. Three diagrams use
partial-or-custom palettes:

- `ROADMAP-koto-adoption.md:219-222` defines four classes
  (`done`, `ready`, `blocked`, `koto`) -- the reference palette
  minus the needs/tracks classes plus a custom `koto` class.
- `PLAN-shirabe-cli-rust-rewrite.md:283-285` defines three classes
  (`simple`, `testable`, `critical`) and no Status classes -- the
  diagram tracks Complexity, not Status.
- `PLAN-roadmap-plan-standardization.md:109-117` defines all nine
  reference-palette classes.

Style content varies in length:

- `classDef done fill:#c8e6c9` -- single style.
- `classDef tracksDesign fill:#FFE0B2,stroke:#F57C00,color:#000` --
  multi-style comma-separated.

FC07 does not need to parse styles; it needs the set of defined class
names so it can detect a class statement that names an undefined
class.

### Comments

No `%% ...` mermaid comment line appears in any of the five surveyed
diagrams. The extractor should treat a leading `%%` as a comment line
to skip (cheap, defensive) but the corpus does not require it.

### Subgraphs

No `subgraph` block appears in any of the five surveyed diagrams,
despite the dependency-diagram reference allowing them. The
extractor's v1 does not need to parse `subgraph`/`end` pairs, but it
must tolerate them by ignoring the structural markers and continuing
to read node and edge declarations from within (a subgraph block
is otherwise a normal group of declarations).

## Extractor scope recommendation

### In scope for v1

The extractor is a single function `extract_diagram(lines: &[&str]) ->
Diagram` returning four parallel views:

1. **Node set**: every distinct id observed in a `<id>["<label>"]`
   declaration. Labels are kept for use in messages but not parsed
   further. Match pattern (informally): a line whose first
   non-whitespace token is `[A-Za-z_][A-Za-z0-9_]*` followed
   immediately by `["` and terminated by `"]`.
2. **Edge set**: every pair `(src, dst)` derived from `<id> --> <id>`
   forms, including chained forms expanded into adjacent pairs.
   Edges are directional.
3. **Class statements**: every `class <id-list> <name>` line, parsed
   as the cross product (id, name) for each id in the
   comma-separated list. Tolerates whitespace inside the list.
4. **classDef set**: every `classDef <name> <styles...>` -- only the
   name is captured.

The extractor reads from the line after the opening fence (which
must contain `graph TD` or `graph LR`) up to the matching closing
fence. The header line is consumed and verified to start with `graph
`; if not, the diagram is treated as empty and the extractor returns
a clean `Diagram` with zero entries plus a single notice
("[FC07] expected `graph TD` or `graph LR` header") that
FC07 surfaces as a configuration issue rather than a reconciliation
mismatch.

### Out of scope for v1, with justification

- **Style parsing in `classDef`.** Captured as opaque text after the
  class name. FC07 only needs the set of declared class names; the
  fill/stroke colors are presentation, not contract.
- **`subgraph`/`end` markers.** No corpus diagram uses them.
  The extractor skips lines that match `^\s*subgraph\b` or
  `^\s*end\b` so a future diagram does not regress.
- **Inline class syntax (`I488:::ready --> I489:::blocked`).** The
  dependency-diagram reference forbids this form and the corpus
  honors the ban. Not supported; FC07 emits a notice if encountered.
- **Edge labels (`A --|text|--> B`, `A -- text --> B`).** No corpus
  diagram uses them. Not parsed; an unrecognized edge line is
  ignored with no panic (see Edge cases).
- **Arrow variants other than `-->`.** No corpus diagram uses them.
- **`flowchart` header.** Forbidden by the reference. The extractor
  produces a single notice if encountered, treats the block as
  empty.
- **Comments (`%% ...`).** Skipped if encountered; the corpus does
  not use them.

The scope above is stdlib-only: line splitting, simple substring and
prefix matching, and one or two narrow byte-level scans per line.
No regex engine is required (the v1 patterns are simple enough for
hand-coded matching), but the existing `regex` dependency already in
the `shirabe-validate` crate (used by `features.rs`) is available if
the implementer prefers it.

## Reconciliation strictness recommendation

FC07 reconciles three views: node set, edge set, and class
assignments. All three ship at notice level for v1. The recommended
strictness varies per dimension.

### Node-set bijection

**Recommendation: strict bijection with one tolerated exception.**

- Every entity-row key in the table that maps to an `I<n>` node id
  must appear as a node in the diagram. A table key with no diagram
  node fires a notice naming the missing key.
- Every diagram node whose id matches `^I[0-9]+$` (the canonical
  issue-keyed form) must appear as a table key. A diagram node with
  no table key fires a notice naming the orphan node.
- **Tolerated exception**: a diagram node whose id does NOT match
  `^I[0-9]+$` is treated as a non-reconciling node and is excluded
  from the bijection check. This tolerates the two corpus shapes
  that exist today:
  - The `O<n>` outline ids in `PLAN-shirabe-cli-rust-rewrite.md`
    (a one-off scheme where outline ids do not map to issue
    numbers).
  - The `K<n>` cross-repo-reference ids in
    `ROADMAP-koto-adoption.md` (external nodes pointing at
    `tsukumogami/koto` issues; these have no table row by design).

The cross-repo `owner/repo#N` literal form does not appear as a
diagram node id in the surveyed corpus -- cross-repo references are
encoded in body prose and the diagram uses a local mnemonic id
(`K<n>`) with a label like `"koto#65: variables"`. FC07 does not
need to recognize `owner/repo#N` as a node id form for v1.

A reconciliation diff with `O<n>` ids is a documented corpus
inconsistency the milestone does not aim to fix; the tolerance
keeps FC07 from issuing notices on a known historical pattern. If
the corpus is later migrated to issue-keyed node ids, the tolerance
becomes dead code and can be removed in the promote-to-error
change.

### Edge agreement

**Recommendation: symmetric over the reconciling node subset.**

- For every pair of issue-keyed nodes `I<a>` and `I<b>` where the
  table row for `#a` lists `#b` in its Dependencies cell, the
  diagram must contain the edge `I<b> --> I<a>` (the convention is
  blocker on the left, dependent on the right -- the existing
  corpus is consistent on this). A Dependencies entry with no
  matching edge fires a notice naming the dependency.
- For every edge `I<b> --> I<a>` where both endpoints are
  reconciling (issue-keyed) nodes, the table row for `#a` must
  list `#b` in its Dependencies cell. An edge with no Dependencies
  entry fires a notice naming the edge.
- Edges involving a non-reconciling node id (any endpoint that
  does not match `^I[0-9]+$`) are excluded from both directions of
  the check. This is the same tolerance the node-set check applies
  and for the same reason.

The reference does not formally state which side of `-->` is the
blocker, but the corpus is consistent: `I111 --> I112` reads as "I111
unblocks I112", matching the canonical "Dependencies of #112 include
#111" reading. v1 binds to this convention. If a diagram reverses
arrows for a node pair, both checks fire.

### Class-assignment agreement with table Status

**Recommendation: enforce the four-case truth table over the
reconciling node subset; ignore non-Status classes.**

Per `references/issues-table.md`, the plan profile carries no
explicit Status column -- it uses strikethrough on the entity row,
description row, and child reference row together as the done marker.
FC07 reads "row is done" as "the entity row is wrapped in `~~...~~`"
and "row is open" as the negation. The roadmap profile carries an
explicit Status column.

For each diagram node `I<n>` that has a class assignment in the
reconciling-class set (`done`, `ready`, `blocked`, plus the
`needsDesign`/`needsPrd`/`needsSpike`/`needsDecision`/`tracksDesign`/`tracksPlan`
group when applicable), FC07 checks:

| Declared class | Expected condition on the table row |
|----------------|-------------------------------------|
| `done` | The row is in a terminal state: strikethrough applied (plan profile) OR Status is `Done`/`Closed` (roadmap profile). |
| `ready` | The row is open AND every dependency named in the Dependencies cell resolves to a row that is itself in a terminal state. |
| `blocked` | The row is open AND at least one dependency named in the Dependencies cell resolves to a row that is open (not in a terminal state). |
| `needsDesign`/`needsPrd`/`needsSpike`/`needsDecision`/`tracksDesign`/`tracksPlan` | Out of scope for v1 class-vs-Status. FC07 records the class but does not check it against Status -- these classes encode pipeline-position metadata that the Implementation Issues table does not carry. |

Non-Status classes (the `simple`/`testable`/`critical` Complexity
group, the `koto` external-marker class, any future custom class)
are not checked against Status. The check applies only to nodes
carrying a class in the Status-bearing set.

**Notice message form**, mirroring the existing FC05/FC06 voice:

- `[FC07] node I<n> declared class "<declared>" but table row is
  <state>; expected class "<expected>"`

  Examples a reader of `PLAN-roadmap-plan-standardization.md`
  pre-#147 would have seen:
  - `[FC07] node I111 declared class "ready" but row is done;
    expected class "done"`
  - `[FC07] node I116 declared class "blocked" but row is open
    and all dependencies are done; expected class "ready"`

Each mismatch is a single notice naming the node, the declared
class, the observed table state, and the expected class.

### Truth-table edge: a node with no class

A diagram node with no `class` directive at all does not fire a
class-mismatch notice. The class-agreement check only fires on a
declared mismatch. This is deliberate: a missing class is a
presentation gap (the renderer falls back to default styling), not
a contract violation, and the dependency-diagram reference does not
require a class on every node.

## Edge cases and security

The extractor is total over arbitrary line input per #119's SECURITY
criterion -- no index panics, no unbounded loops. The cases below
are the ones the implementer must handle explicitly; the
recommended behavior for each:

| Case | Recommended behavior |
|------|----------------------|
| Unterminated fence (opening ```` ```mermaid ```` with no closing ```` ``` ```` before EOF) | The extractor reads to EOF and treats the gathered lines as the diagram body. FC07 surfaces a single notice (`[FC07] unterminated mermaid block`) so authors notice. No panic. |
| Ragged node declaration (`I111["#111: title` with no closing `"]`) | The line is unrecognized and ignored. The node is not added to the node set. FC07 will then fire a normal "missing diagram node" notice against the table row, which makes the defect visible without needing a dedicated parse-error notice. |
| Unknown class name (a `class I1 invented` line where `invented` is in neither the reference palette nor any `classDef` in this diagram) | The (id, name) pair is recorded. FC07 emits a notice `[FC07] node I1 declared class "invented" but no classDef defines it`. Treated as a normal class mismatch rather than a parse error. |
| Multi-key class statement with whitespace inside the list (`class I1, I2 ready`) | Tolerated: split on commas, trim each id. The corpus does not use this form but the reference does not forbid it. |
| Empty diagram (header only, e.g. `docs/roadmaps/ROADMAP-strategic-pipeline.md:437-439`) | Returns an empty `Diagram`. FC07 then sees no nodes/edges/class statements; the node-set check fires "table key has no diagram node" for every table key. This is the correct present-state signal -- the diagram is genuinely empty and needs populating. |
| No diagram at all in the doc (no ```` ```mermaid ```` block under Dependency Graph) | The extractor returns `None` (or equivalent). FC07 emits a single notice `[FC07] no mermaid diagram found under Dependency Graph` and skips the per-node checks. |
| Multiple ```` ```mermaid ```` blocks in one file | Use the first ```` ```mermaid ```` block that appears under the `## Dependency Graph` section (located via the existing `Doc.Sections` IR). Ignore later blocks. No corpus doc has more than one mermaid block today; this is a forward-compat policy. |
| A mermaid block outside the Dependency Graph section | Ignored. FC07 only reconciles the one block under Dependency Graph. |
| `flowchart TD` header instead of `graph TD` | Treated as a header-shape notice; the extractor still attempts to read the body. The reference forbids `flowchart`, so the notice prods authors to migrate. |
| Inline class syntax (`I1:::ready`) on a node decl or edge | Parsed: the inline class is recorded against the node, equivalent to a separate `class I1 ready`. Notice fires that inline syntax is not the canonical form. The corpus does not use this form today but the recommendation tolerates it to avoid catastrophic failures. |

The bounded-iteration guarantee is straightforward: the extractor
makes exactly one pass over the input lines between the opening and
closing fences (or to EOF). Each line is matched against a fixed
set of prefix patterns (`graph `, `class `, `classDef `, `subgraph `,
`end`, `%%`, or default-edge-or-node) in constant time. No nested
loops over input.

## Open questions for #119

The spike does not pre-empt every implementer call. The following
are deliberately left to #119 to decide during implementation:

1. **Promotion seam wording.** The promotion-to-error path is a
   one-line change in `IsNotice` once the corpus is reconciled. The
   spike does not prescribe the exact wording of the comment that
   marks that line as the promotion seam. Pick at impl time.

2. **Notice grouping vs per-defect notices.** A diagram with eight
   class mismatches in one row of `class` statements produces
   either eight notices (one per node) or one notice naming all
   eight. The spike recommends per-node for diagnostic clarity but
   does not require it; if test output gets noisy on the present
   corpus, group during impl.

3. **Roadmap profile class-vs-Status mapping.** The reference's
   Status values for roadmap (`Not Started`, `In Progress`, `Done`,
   plus `needs-*` annotations) do not map one-to-one to the diagram
   class palette (`done`/`ready`/`blocked`). The spike's truth
   table assumes `Done` and `Closed` both count as terminal and
   that `Not Started`/`In Progress` both count as open. The
   implementer should sanity-check this against the migrated
   roadmap corpus and refine the mapping in code if a roadmap row
   surfaces a case the spike missed.

4. **Whether to test on a pre-#147 fixture.** PR #147 hand-fixed
   the class-vs-Status drift in
   `PLAN-roadmap-plan-standardization.md`. A regression test that
   pins the pre-#147 state as a fixture and asserts FC07 fires the
   right notices would be a useful corpus-grounded test, but
   committing the fixture in a tests directory may run into
   validation. The implementer decides at impl time whether to use
   an inline string fixture or a fixture file.

5. **Edge directionality convention enforcement.** The spike binds
   FC07 to "blocker on the left, dependent on the right". If a
   future diagram convention proposal flips this, the check binds
   the wrong way. Worth a brief note in the FC07 doc comment so
   the convention is locatable.
