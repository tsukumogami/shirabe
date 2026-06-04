---
schema: design/v1
status: Accepted
problem: |
  shirabe plans and roadmaps render a feature's structure on two surfaces -- the
  Implementation Issues table and the Dependency Graph mermaid block --
  authored by hand and reconciled by no validator check. The parent design's
  Decision 3 staged the reconciliation check behind a mermaid feasibility
  spike and a notice-then-error rollout; both upstreams have landed. This
  design picks up the open questions that surfaced in the spike (extractor
  view shape, per-defect vs grouped notices, the promotion seam wording, the
  fixture strategy, the edge-directionality binding) and adds an FC08-class
  scope-extension that folds class-versus-Status reconciliation into the
  same check.
decision: |
  FC07 lands as a single check function in the existing shirabe-validate
  crate. A new line-oriented stdlib-only extractor module produces a
  Diagram value with four parallel views (node set, edge set, class
  statements, classDef set), and FC07 reconciles those views against the
  parsed Table across three dimensions (node-set bijection, edge agreement,
  class-versus-Status agreement) in one pass. The check ships at notice
  level by joining the existing is_notice membership; the promotion seam is
  the membership entry itself. Per-defect notices, an inline-string test
  fixture pattern (including a pinned pre-cleanup regression case), and a
  doc-comment binding on the edge-directionality convention round out the
  open-question settlements.
rationale: |
  The line-oriented extractor and the single-pass three-dimension check
  preserve the parent design's staging shape while keeping the new code
  small (one new module plus one new check function, no new dependency).
  Joining the existing is_notice membership reuses the schema-gate
  precedent the parent design and PRD already sanction, and the
  membership-entry seam is a one-line diff that is independently
  reviewable. Per-defect notices match FC05/FC06 voice, give authors a
  mechanical fix path, and degrade gracefully if a future grouping
  refinement becomes worthwhile. The inline-string fixture strategy keeps
  the test corpus in the same crate as the check (no new testdata
  validation surface) and the pinned pre-cleanup regression case anchors
  the class-versus-Status dimension to the exact defect that motivated
  the scope extension.
upstream: docs/prds/PRD-table-diagram-reconciliation.md
---

# DESIGN: table-diagram-reconciliation

## Status

Accepted

## Context and Problem Statement

The shirabe-validate crate already parses the Implementation Issues table
into a `Table` IR and dispatches FC05 (schema conformance) and FC06
(cross-reference) over it in the plan and roadmap arms of `validate_file`.
It does not yet read the Dependency Graph mermaid block, so it cannot
reconcile the two surfaces. The reconciliation requirement (FC07) spans
three dimensions named by the PRD: a node-set bijection over the
issue-keyed subset, edge agreement over the same subset, and a
class-versus-Status agreement that compares Status-bearing diagram classes
against the table row's terminal-or-open state.

Two implementation gaps follow from this. First, the crate carries no
mermaid reader; this design adds the smallest one that gives FC07 the
inputs the spike enumerated. Second, the existing `Table` parser strips
plan-profile strikethrough from cells before classifying rows, and it does
not surface the roadmap-profile Status column value to consumers. FC07
needs both signals to evaluate the class-versus-Status truth table, so
the design extends the `Row` carrier with a terminality input the extractor
side does not otherwise need.

The parent design `DESIGN-roadmap-plan-standardization.md` Decision 3
established the staging shape -- a feasibility spike upstream of the
reconciliation check, a notice-then-error rollout, and a line-oriented
extractor with no new dependency. Both upstreams now exist: the spike
`docs/spikes/SPIKE-mermaid-parser.md` enumerated the per-dimension
strictness contracts the corpus subset supports, and the PRD encoded those
contracts as numbered requirements R1-R12 with binary acceptance criteria.
This design refines the parent Decision 3 in light of the spike's open
questions and the class-versus-Status scope extension; it does not
supersede the parent.

## Decision Drivers

- **PRD requirements bind first.** The 12 requirements (R1-R12) of the PRD
  and the 26 acceptance criteria attached to them set the contract; every
  decision below must keep them satisfied.
- **The spike's per-dimension recommendations bind the strictness.** The
  spike's truth tables (node-set bijection over the issue-keyed subset,
  symmetric edge agreement, four-case class-versus-Status) and the
  edge-case behavior table fix the surface of the check; the design
  settles only the open questions the spike left for implementation.
- **Stdlib-only, no new dependency (R11).** The crate's existing
  dependencies (the `regex` carrier `features.rs` already uses) are the
  budget; the extractor uses only line splitting, prefix matching, and
  optionally that existing regex.
- **Notice-level v1 via the existing `is_notice` membership (R6, R7).**
  The schema-gate precedent (`code == "SCHEMA"`) is the reuse target; the
  promotion seam is the membership entry itself.
- **Bounded iteration over arbitrary input (R10 / SECURITY).** One pass
  over the lines of the fenced block; constant-time per-line prefix
  matching; no nested loops over input; no panics on UTF-8 boundaries.
- **Public-cleanliness of notice prose (R12).** Every notice body and
  every shared rule citing FC07 is reviewed against the parent PRD's R22
  invariant.
- **Total-over-arbitrary-input parsing (parent design's R6 invariant).**
  The mermaid extractor follows the same totality discipline the existing
  `Table` parser holds: malformed input produces a result and a specific
  notice rather than a panic.
- **Single, locatable promotion seam.** Maintainer cleanup is a one-line
  membership change; the seam must be in one place and independently
  reviewable.

## Considered Options

This design settles six implementation questions. Each subsection records
the chosen approach, at least one rejected alternative with its reason,
and a one-line citation back to the spike or PRD where the binding came
from.

### Decision 1: Extractor view shape and ownership

**Chosen.** Add a new module `crates/shirabe-validate/src/mermaid.rs`
exposing `extract_diagram(lines: &[&str]) -> Diagram`, where `Diagram` is
a flat struct with four owned fields: `nodes: Vec<Node>` (id and label),
`edges: Vec<Edge>` (src, dst), `class_assignments: Vec<ClassAssignment>`
(id, class-name, optional source-form marker for inline vs canonical),
and `class_defs: HashSet<String>` (declared class names only -- style
bodies are not parsed). The function takes the lines between the opening
``` ```mermaid ``` fence and the matching close (or EOF on an
unterminated fence). A separate `find_dependency_graph_block(doc: &Doc)
-> Option<BlockLocation>` helper locates the first fenced mermaid block
under `## Dependency Graph` using the existing `Doc.sections` IR; it
returns the body line range plus an `Issue` enum value for the malformed
cases the spike enumerated (`UnterminatedFence`, `MissingBlock`,
`HeaderFlowchart`, etc.). FC07's check function pulls both -- the
location and the extracted views -- and emits per-issue notices in
addition to the per-dimension reconciliation notices.

**Alternatives considered.**

- *Return separate `Vec`/`HashSet` values from the extractor without a
  carrier struct.* Rejected: the carrier struct localises the four
  parallel views so FC07's check signature does not multiply, and adding
  a fifth view in a future increment (e.g. `subgraph` groupings) does
  not break callers.
- *Co-locate the extractor inside `checks.rs` as a private helper.*
  Rejected: the extractor is the only line-oriented mermaid reader in the
  crate, has its own unit-test surface (the spike's edge-case table),
  and benefits from being independently testable. A separate module
  matches the existing `table.rs` precedent the prior table-parser
  increment landed.

**Citation.** Spike, "Extractor scope recommendation", and R5 of the PRD.

### Decision 2: Notice grouping (per-defect over grouped)

**Chosen.** Each reconciliation defect produces exactly one notice. A
diagram with eight class mismatches yields eight notices; a missing edge
produces one notice naming source and destination; a missing diagram
node produces one notice per table key. Notice text mirrors the
FC05/FC06 voice (`[FC07] <description>`), names the diagram id rather
than a URL, and includes observed-vs-expected state where applicable.

**Alternatives considered.**

- *Group all mismatches per file into a single multi-line notice.*
  Rejected: a multi-line notice obscures the per-defect fix path the
  PRD user stories require ("the fix path is mechanical"), and the
  existing FC05/FC06 voice is per-defect rather than per-file. Grouping
  would also collapse line numbers, which the GHA-annotation surface
  uses to attach the notice to the right line.
- *Group per dimension (one notice per dimension per file).* Rejected:
  same loss of per-line targeting, and the user stories explicitly want
  the specific cell or line called out (Journeys 1, 2, 3 in the BRIEF
  all name a single specific defect site).

The spike flagged the test-output-noise risk that grouping might address
later. The design records that risk in Consequences and leaves grouping
as a deferred refinement if v1 notice volume on the cleaned corpus
becomes the bottleneck.

**Citation.** Spike, open-questions section, notice-grouping item;
R8 of the PRD.

### Decision 3: Promotion-to-error seam at the is_notice membership

**Chosen.** The `is_notice` function in `validate.rs` becomes a small
match expression over the `code` field rather than the literal-equal
that exists today. The body reads:

```rust
pub fn is_notice(err: &ValidationError) -> bool {
    matches!(err.code.as_str(), "SCHEMA" | "FC07")
}
```

A doc-comment directly above the function marks it as the promotion
seam in prose: "FC07 ships notice-level for v1; remove the `FC07`
arm from this match to promote the check to error in a single-line
diff." The promotion PR is that one-line change plus the matching
test update; nothing else moves.

**Alternatives considered.**

- *Introduce a `severity()` method on `ValidationError`.* Rejected:
  the existing notice/error split is a binary, the schema-gate
  precedent already drives off `is_notice`, and a method would
  multiply the surface for no functional gain.
- *Gate FC07 behind a runtime flag (`--check-fc07`) that defaults
  off.* Rejected by the PRD's Decision 2: a flag-gated check is
  invisible to authors and provides no forcing function for the
  cleanup.

The seam wording (the doc-comment text quoted above) is the spike's
open-question item 1; this design fixes it so the implementer does
not re-derive the prose.

**Citation.** Spike, open-questions section, promotion-seam wording
item; PRD R6, R7, Decision 2.

### Decision 4: Test strategy (inline-string fixtures with a pinned pre-cleanup case)

**Chosen.** Tests live in `mermaid.rs` and `checks.rs` as Rust
`#[cfg(test)]` modules using inline-string fixtures, matching the
existing precedent in `table.rs` and `checks.rs`. The fixture pattern
is one Rust `&str` constant per scenario, fed to the extractor or the
full validator. A single pinned regression case captures the
pre-cleanup state of `PLAN-roadmap-plan-standardization.md` that the
recent class-versus-Status hand-fix corrected: the table row is in
a terminal state, the diagram declares class `blocked`, and FC07 must
emit the four-line truth-table notice. The fixture is a Rust
constant in the test module, not a file under `tests/data/`, so it
does not enter the validation surface and does not need its own
schema.

**Alternatives considered.**

- *Externalize fixtures under `tests/data/mermaid/`.* Rejected: the
  shared validation surface in this crate validates Markdown docs
  whose paths land in `docs/`. A fixture under `tests/data/` does not
  trigger the validator the way the crate's own validate command
  walks the corpus, so the path adds no signal and adds a maintenance
  surface. The crate's existing parsers use inline-string fixtures
  for the same reason.
- *Build a corpus-grounded test that walks every plan and roadmap in
  the committed corpus.* Rejected for v1: the committed corpus
  currently carries unreconciled diagrams that FC07 will surface as
  notices; a walk-the-corpus test would assert against that drift
  rather than against the contract. After the cleanup PR lands, a
  walk-the-corpus check is a sensible follow-up but not in v1's
  scope.

The pinned pre-cleanup regression test is the spike's open-question
item 4. The design settles it on inline strings.

**Citation.** Spike, open-questions section, pre-cleanup-fixture
item; R9 acceptance criteria attached to malformed-input behavior.

### Decision 5: Edge-directionality binding (doc-comment on the FC07 check)

**Chosen.** The "blocker on the left, dependent on the right"
convention is recorded as a `///` doc comment on the FC07 check
function. The comment names the convention explicitly and points the
reader to `references/dependency-diagram.md` and the spike for the
corpus survey that confirms the convention is consistent. The doc
comment is the single locatable artifact for the binding; runtime
behavior does not duplicate it (the edge-agreement check uses the
convention but does not re-derive it from prose).

**Alternatives considered.**

- *Surface the convention as a runtime configuration knob.* Rejected:
  no user story asks for a flipped convention, the convention has
  been consistent across every corpus diagram surveyed, and adding a
  knob would expand the public API of the check for a need that does
  not exist today.
- *Record the convention only in `references/dependency-diagram.md`
  and leave the FC07 check silent about it.* Rejected: a maintainer
  reading the check function in isolation should not have to grep the
  references directory to find which side of `-->` the check binds.
  The doc comment is the right granularity.

**Citation.** Spike, open-questions section,
edge-directionality-binding item; PRD Known Limitations (the
directionality clause).

### Decision 6: Row terminality input (extend `Row` with a `terminal` flag)

**Chosen.** Extend the `Row` struct in `table.rs` with a `terminal:
bool` field populated during classification. For plan-profile rows,
`terminal` is true when the original (pre-strip) first cell is
wrapped in `~~...~~`. For roadmap-profile rows, `terminal` is true
when the Status cell value is `Done` or `Closed` (case-insensitive,
trimmed). The classifier preserves the original cells alongside the
strikethrough-stripped form so the test for strikethrough is local
to `classify_row`; the existing `Description`/`Entity`/`Child`
classification rule reads from the stripped form and is unchanged.
A second new field `status: Option<String>` carries the raw Status
cell value (roadmap profile only) so FC07's per-defect notice can
echo the observed state verbatim.

The `Table.profile` is detected from `Table.columns`: a 4-column
table with the last column named `Status` indicates the roadmap
profile; the canonical 3-column plan shape indicates the plan
profile. A small enum `Profile { Plan, Roadmap }` is added to the
`Table` struct.

**Alternatives considered.**

- *Re-derive terminality inside FC07 by re-parsing the doc body
  itself.* Rejected: the `Table` parser is the canonical reader of
  the table; pushing terminality into FC07 would either duplicate
  the parser or read the body twice. The cost of the extra `Row`
  field is one boolean plus an optional string.
- *Carry the raw first cell on `Row` and let FC07 detect
  strikethrough on the fly.* Rejected: every consumer of terminality
  pays the same parse cost; doing it once in the classifier and
  caching on `Row` is more direct. The cost is the same on disk.

The PRD's R4 truth table requires the terminal-or-open distinction
in both profiles, and the spike notes the roadmap-profile Status
mapping (`Done` and `Closed` count as terminal; `Not Started` and
`In Progress` count as open) as item 3 of its open questions. The
roadmap mapping is encoded here as a default; a roadmap row with a
`needs-*` Status annotation counts as open for v1 (the parent design
treats `needs-*` rows as pre-binding).

**Citation.** Spike, open-questions section, roadmap-Status-mapping
item; PRD R4 and its acceptance criteria.

## Decision Outcome

FC07 is one check function in `crates/shirabe-validate/src/checks.rs`,
dispatched in the `Plan` and `Roadmap` arms of `validate_file`
alongside FC05 and FC06. It consumes the parsed `Table` (with the
terminality and Status fields the design adds in Decision 6) and the
extracted `Diagram` (produced by the new `mermaid.rs` module in
Decision 1) and reconciles them across all three dimensions in a
single pass. Notice membership joins the existing `is_notice`
function via a match arm (Decision 3); notices are per-defect with
the FC05/FC06 voice (Decision 2). Tests use inline-string fixtures
with a pinned pre-cleanup regression case (Decision 4); the
edge-directionality convention is recorded as a doc comment on the
check function (Decision 5).

The six decisions compose: Decision 1 fixes the extractor surface,
Decision 6 fixes the table-side surface, Decision 2 fixes the notice
shape FC07 emits, Decision 3 fixes the membership wiring, Decision 4
fixes how the contract is tested, and Decision 5 fixes the single
non-obvious binding (edge directionality) so a future reader can
locate it. No decision contradicts the parent design's Decision 3:
the spike-then-notice-then-error staging is preserved, the
line-oriented stdlib-only constraint is preserved, and the
single-point promotion seam is preserved.

## Solution Architecture

### Components

- **`crates/shirabe-validate/src/mermaid.rs` (new).** Exposes
  `extract_diagram(lines: &[&str]) -> Diagram` and
  `find_dependency_graph_block(doc: &Doc) -> Option<BlockLocation>`
  plus the `Diagram`, `Node`, `Edge`, `ClassAssignment`,
  `BlockLocation`, and `Issue` types. No external mermaid grammar
  dependency. Internal parsing uses string slice operations and
  optionally the `regex` carrier the crate already uses for
  features.

- **`crates/shirabe-validate/src/checks.rs` (modified).** Adds
  `check_fc07(doc: &Doc, spec: &FormatSpec) -> Vec<ValidationError>`.
  The function returns an empty vec when the spec has no
  `issues_table_columns` (the same no-op gate FC05/FC06 use), then
  loads the parsed `Table`, locates the diagram block, extracts the
  views, and runs the three reconciliation passes (node-set
  bijection, edge agreement, class-versus-Status). All issue cases
  the extractor surfaces (`UnterminatedFence`, `MissingBlock`,
  `HeaderFlowchart`, ragged-line skip, etc.) are converted to
  per-issue notices before the per-dimension passes; a `MissingBlock`
  short-circuits the per-node checks per R9.

- **`crates/shirabe-validate/src/table.rs` (modified).** Adds
  `terminal: bool` and `status: Option<String>` to `Row`, and adds
  `Profile` enum plus `profile: Profile` to `Table`. The classifier
  is updated to populate the new fields without changing the
  existing `RowKind` classification rule.

- **`crates/shirabe-validate/src/validate.rs` (modified).** Adds
  `FC07` to the `is_notice` match expression (Decision 3) and adds
  the FC07 dispatch in the `Plan` and `Roadmap` arms.

### Key Interfaces

```rust
// mermaid.rs (new module)
pub struct Diagram {
    pub nodes: Vec<Node>,
    pub edges: Vec<Edge>,
    pub class_assignments: Vec<ClassAssignment>,
    pub class_defs: HashSet<String>,
}

pub struct Node { pub id: String, pub label: String, pub line: usize }
pub struct Edge { pub src: String, pub dst: String, pub line: usize }
pub struct ClassAssignment {
    pub id: String,
    pub name: String,
    pub inline: bool,
    pub line: usize,
}

pub enum Issue {
    UnterminatedFence { line: usize },
    MissingBlock { line: usize },
    HeaderFlowchart { line: usize },
    HeaderUnrecognized { line: usize },
    InlineClassSyntax { line: usize },
    UndefinedClass { name: String, line: usize },
}

pub struct BlockLocation {
    pub body_start: usize,
    pub body_end: usize,
    pub issues: Vec<Issue>,
}

pub fn extract_diagram(lines: &[&str]) -> Diagram;
pub fn find_dependency_graph_block(doc: &Doc) -> Option<BlockLocation>;
```

```rust
// table.rs (extended)
pub enum Profile { Plan, Roadmap }

pub struct Row {
    pub kind: RowKind,
    pub key: String,
    pub deps: Vec<String>,
    pub line: usize,
    pub raw: String,
    pub terminal: bool,        // new
    pub status: Option<String>,// new (roadmap only)
}

pub struct Table {
    pub columns: Vec<String>,
    pub rows: Vec<Row>,
    pub header_line: usize,
    pub profile: Profile,      // new
}
```

```rust
// checks.rs (new function signature)
pub fn check_fc07(doc: &Doc, spec: &FormatSpec) -> Vec<ValidationError>;
```

```rust
// validate.rs (updated is_notice)
pub fn is_notice(err: &ValidationError) -> bool {
    matches!(err.code.as_str(), "SCHEMA" | "FC07")
}
```

### Data Flow

`validate_file(doc, spec, cfg)` runs the schema gate, the visibility
gate, FC01-FC04, and then dispatches to the format-specific arm. The
`Plan` and `Roadmap` arms call `check_fc05`, `check_fc06`, and the new
`check_fc07` in that order. `check_fc07` parses the issues table
(reusing the existing `parse_issues_table`), locates the diagram block
under `## Dependency Graph` via `find_dependency_graph_block`, extracts
the views via `extract_diagram`, and runs the three reconciliation
passes. Each pass produces zero or more `ValidationError` values with
`code = "FC07"`. The driver collects them into the returned vec; the
caller (`shirabe validate`) uses `is_notice` to annotate them and
exits 0 if every error is a notice.

### Scope, in and out (spike enumeration)

The extractor recognises:

- The opening fence ``` ```mermaid ``` and the matching closing fence
  ``` ``` ``` (or EOF on unterminated input -- an Issue::UnterminatedFence
  is emitted and the body is read to EOF).
- The header line starting with `graph ` (TD or LR). A `flowchart `
  header emits `Issue::HeaderFlowchart` and continues; any other header
  emits `Issue::HeaderUnrecognized` and the block is treated as empty.
- Node declarations of shape `<id>["<label>"]` with any leading
  whitespace. The id is any non-whitespace token that matches
  `[A-Za-z_][A-Za-z0-9_]*`.
- Edges of shape `<id> --> <id>` including chained forms
  `A --> B --> C` (split into adjacent pairs).
- `class <id-list> <name>` statements with comma-separated ids,
  whitespace tolerated inside the list.
- `classDef <name> <styles...>` statements; only the name is captured.
- Inline class syntax `<id>:::<class>` on a node declaration or edge:
  parsed and recorded equivalent to a `class <id> <class>` statement,
  with `Issue::InlineClassSyntax` emitted as a tolerance notice.
- `subgraph` / `end` markers: skipped (the spike confirmed the corpus
  does not use them, but tolerating them defends against future
  diagrams without forcing parsing of the block structure).
- `%%`-prefix lines: skipped as mermaid comments.

The extractor does not recognise (and the FC07 check does not consume):

- Arrow variants other than `-->` (`---`, `==>`, `-.->`, edge labels).
  The line is skipped; the consequence (a missing edge in the
  edge-agreement pass) surfaces through the normal per-defect notice.
- Alternate node-bracket forms (`{...}`, `(...)`, `>...]`). The corpus
  uses only the `["..."]` form; alternates do not parse.
- `classDef` style content beyond the class name.
- Multiple `class` names per statement (`class I1 ready blocked`). No
  corpus diagram uses this form and the reference does not allow it.

## Implementation Approach

The work decomposes into four implementation increments. Each is one
PR-sized step; the dependencies are linear and named.

### Step 1: Extend `Row` and `Table` with terminality and Status (Decision 6)

Add `terminal`, `status`, and `profile` fields. Update `classify_row`
to populate them. Add unit tests for plan-profile strikethrough
detection (with and without strikethrough), for roadmap-profile
Status values (`Done`, `Closed`, `In Progress`, `Not Started`,
`Done with needs-*` and similar tolerance cases), and for profile
detection from columns. No existing test breaks; FC05 and FC06 do
not consume the new fields.

### Step 2: Add `mermaid.rs` and the extractor (Decision 1)

Create the new module. Implement `extract_diagram`,
`find_dependency_graph_block`, the carrier types, and the `Issue`
enum. Unit-test every row of the spike's edge-case table (the ten
malformations listed under R9, plus the chained-edge expansion, the
multi-key class form, and the inline-class tolerance). Include the
empty-diagram and missing-block cases as separate tests.

### Step 3: Add `check_fc07` and wire it into `validate_file` (Decisions 2 and 5)

Implement the three per-dimension passes and the per-issue notice
emission. Add the doc-comment recording the edge-directionality
convention (Decision 5). Wire FC07 into the `Plan` and `Roadmap`
arms of `validate_file`. Integration-test the dispatch with at
least one plan and one roadmap fixture that exercise each
dimension.

### Step 4: Promote FC07 to notice-level via `is_notice` (Decision 3)

Update `is_notice` to the match expression. Add the doc-comment
seam wording. Add the pinned pre-cleanup regression test (Decision
4) that asserts FC07 emits the right four-line truth-table notice
on the captured pre-PR-cleanup state of
`PLAN-roadmap-plan-standardization.md`.

The four steps are sequential because Step 2 reads the `Table`
profile that Step 1 adds, Step 3 calls the extractor Step 2 lands,
and Step 4 is the membership wiring that turns the check into a
notice rather than an error. A single PR carrying all four steps is
the default shape; if the maintainer prefers to land Step 1 first
for a smaller diff, the work can split at that boundary without
behavioral surprise.

## Security Considerations

The FC07 check and its extractor are total over arbitrary line
input. The extractor makes one pass over the lines between the
opening and closing fences (or to EOF on an unterminated fence).
Each line is matched against a fixed set of prefix patterns
(`graph `, `class `, `classDef `, `subgraph `, `end`, `%%`, or the
default node/edge shapes) in constant time. There are no nested
loops over input. Per-line operations rely on `str::strip_prefix`,
`str::find`, `str::split`, and at most one `regex::Regex::captures`
call (using a pre-compiled `LazyLock<Regex>` matching the same
precedent the existing parsers use). All operations are total on
arbitrary UTF-8 input; none indexes by byte position into a
multi-byte boundary, and none unwraps a `None` from a missing
match.

The four malformations the spike enumerated as failure shapes --
unterminated fence, ragged node declaration, an inline class on an
edge, and a class-statement id list with internal whitespace -- are
covered by dedicated tolerance branches in the extractor with unit
tests. The "very long line" and "deeply nested punctuation" cases
named in the PRD's R10 acceptance criterion are handled by the
constant-time prefix matching the design uses: line length affects
only the time of `str::find` for the canonical patterns; nested
punctuation is not parsed (the extractor reads only the canonical
shape and skips the rest).

The notice messages FC07 emits are reviewed against the parent
PRD's R22 public-cleanliness invariant before the implementation
PR merges. The R12 acceptance scan (no private repo names, paths,
filenames, external issue numbers, or pre-announcement features in
notice bodies) is the test surface; the scan is run as part of
Step 3's test additions.

FC07 does not read files outside the doc passed to `validate_file`,
does not write to disk, does not invoke external processes (no `git
ls-files` is needed -- the table's terminality is local to the
parsed cells, and the diagram's content is local to the doc body),
and does not allocate unbounded buffers. Memory usage is linear
in the number of fenced lines.

## Consequences

### Positive

- The reconciliation across all three dimensions lives in one
  check function, with one membership wiring and one promotion
  seam. A maintainer doing the cleanup PR touches a single line.
- The extractor is the smallest possible mermaid reader for the
  contract: ~150-200 lines of straight-line parsing, no new
  dependency, total over arbitrary input.
- The `Table` extension (terminality and Status) is reusable by
  future checks that need row-state-aware reconciliation without
  re-parsing the body.
- The pinned pre-cleanup regression test anchors the
  class-versus-Status dimension to the exact defect that motivated
  the scope extension. The fixture catches the same defect on the
  next occurrence and documents the truth-table assignment by
  example.
- Per-defect notices give authors a mechanical fix path. The
  BRIEF's four user journeys map directly to four notice shapes.

### Negative

- Notice volume on the present committed corpus is bounded by the
  existing drift; until the cleanup PR lands, every plan or
  roadmap doc with drift carries FC07 notices on every CI run.
  The signal degrades if authors learn to skim past FC07 output
  without reading it; the forcing function is the maintainer's
  cleanup PR.
- The `Table` extension grows the surface area of the `Row` type
  by two fields. Future serialization or test setup that
  constructs `Row` values by hand has to set the new fields.
- The inline-string fixture pattern bloats the test module of
  `mermaid.rs` (every edge-case row gets its own constant). The
  alternative (externalized fixtures) was rejected for reasons in
  Decision 4; the cost is a longer test file.
- The convention that "blocker on the left, dependent on the
  right" is bound at the function-comment level. If a future
  proposal flips the convention, the FC07 check binds the wrong
  way and a separate refactor is needed to point at the
  refactored references doc.

### Mitigations

- The notice-erosion risk is mitigated by the BRIEF's Journey 4
  (the maintainer's cleanup PR) and by FC07's per-defect specificity:
  every notice points at a concrete line, so an author treating the
  notices as actionable converges on zero quickly.
- The `Row` field additions are non-breaking inside the crate; a
  future serialization use case can add a `#[serde(skip)]` (or the
  equivalent) on the new fields without touching FC07.
- The fixture bloat in `mermaid.rs` is bounded by the spike's
  edge-case enumeration: 10 cases, each one Rust constant. The
  test file stays under a few hundred lines.
- The edge-directionality binding is recorded in two places (the
  doc comment on the check function and the parent
  `references/dependency-diagram.md`); if a future proposal flips
  the convention, both are findable by a single grep for the
  word "blocker".

## References

- **Parent design (the Decision 3 this design refines).**
  `docs/designs/DESIGN-roadmap-plan-standardization.md`, Decision 3
  ("The mermaid-parser spike and the staged reconciliation check");
  Solution Architecture, "Validator"; Implementation Approach,
  Phase 7.
- **Source PRD.** `docs/prds/PRD-table-diagram-reconciliation.md`
  (R1-R12 and their 26 acceptance criteria; Decisions 1-4 frame
  this design's six decisions).
- **Source brief.** `docs/briefs/BRIEF-table-diagram-reconciliation.md`
  (four user journeys; scope boundary).
- **Feasibility spike.** `docs/spikes/SPIKE-mermaid-parser.md`
  (per-dimension strictness tables; edge-case behavior table; the
  five open questions this design settles).
- **Canonical issues-table conventions.**
  `references/issues-table.md` (Status column for the roadmap
  profile; strikethrough-on-done for the plan profile).
- **Canonical dependency-diagram conventions.**
  `references/dependency-diagram.md` (graph subset; the
  status-class palette; the forbidden forms).
- **Validation precedents.**
  `crates/shirabe-validate/src/checks.rs` (FC05 and FC06 voice);
  `crates/shirabe-validate/src/validate.rs` (the dispatcher and
  the `is_notice` membership FC07 joins);
  `crates/shirabe-validate/src/table.rs` (the existing parser this
  design extends).
