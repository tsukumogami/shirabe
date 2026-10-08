---
schema: design/v1
status: Current
problem: |
  A roadmap item has no field for the outcome it delivers or the check a
  non-author can run, so nothing in shirabe can require one. The roadmap's
  readers disagree about what an item looks like: the Rust parser folds
  every unknown line into a description, the coordinator's bash picker reads
  only first-line `Feature N` dependencies and a Status that is exactly
  `Done`, and the coordinator's status writer deletes an item's
  `**Outcome:**` line to record merged pull requests.
decision: |
  Mark milestone roadmaps `schema: roadmap/v2` and keep the interim field
  spelling. The Roadmap format spec accepts both schema values, and a new
  error-level check, FC21, runs the milestone rules on v2 only. The shared
  Rust parser learns the milestone fields and one tag resolver that
  populate and FC21 share. The picker's reading of older roadmaps stays in
  the bash library its callers already share, with awk collecting the
  dependency paragraph and jq applying the rules. The status writer records
  merges on `**Delivered:**`. `/roadmap` drafts v2 milestones and gives its
  Active-roadmap resume branch a sharpen-in-place procedure.
rationale: |
  One format spec keeps prefix routing and every existing roadmap check
  unchanged for both versions, so `roadmap/v1` stays byte-identical in
  validation. Keeping the interim spelling lets a roadmap already written in
  milestone form migrate by changing one line. Leaving the picker in bash
  avoids tying every coordinator host to a new CLI release at pick time,
  and the PRD scopes the legacy reading rules to the picker alone.
upstream: docs/prds/PRD-milestone-format.md
decision_provenance: inline-resolved
---

# DESIGN: milestone-format

## Status

Current

## Context and Problem Statement

Roadmaps are read by five pieces of code, and none of them knows what a
milestone is.

`crates/shirabe-validate/src/features.rs` parses a roadmap's
`## Features` section into `Feature { id, label, needs, dependencies,
status, description, heading_line }`. It recognizes three field lines
(`**Needs:**`, `**Dependencies:**`, `**Status:**`), each one line long, and
folds every other line into `description`. An `**Outcome:**` paragraph, a
bulleted `**Evidence:**` list and `**Left open:**` would all end up in that
one flattened string. Its heading grammar is `### Feature N:` or
`### <letters><digits>:`, so a tag with a letter suffix (`AB10a`) isn't an
item at all.

`crates/shirabe/src/populate.rs` renders the reserved Implementation Issues
table and dependency diagram from those features. Its description cell is
the first sentence of `description` (or the text after a
`**Functional outcome:**` marker), and its dependency edges come from
`feature_refs_in`, which reads `Feature N`, `Features N, M` and nothing
else. A roadmap whose dependencies name prefixed tags gets a diagram with no
edges.

`shirabe validate` routes a `ROADMAP-*.md` file to the one Roadmap
`FormatSpec` by filename prefix, then `check_schema` compares the
document's `schema` to `roadmap/v1`. Any other value gets a `SCHEMA` notice
and skips every structural check, and CI's changed-docs job treats that as
incomplete (exit 4). No check reads the Features body: FC05 to FC09 read
the reserved table and diagram, FC16 their shape.

`skills/coordinate/scripts/record-common.sh` has the bash reader,
`lib_roadmap_features`, shared by the picker (`pick-facts.sh`), the
close-out reader (`closeout-read.sh`) and the status writer
(`roadmap-status.sh`). It reads only the first line of a Dependencies
entry, resolves `Feature N`, `Features N, M` and `F<N>` positionally, and
marks an item done when its Status is exactly `Done` or `Dropped` with at
most one trailing period. `pick-facts.sh` then counts a dependency
satisfied only when it reads exactly `Done`. On roadmaps already in use,
with prefixed tags, dependency prose wrapped over several lines,
explanatory parentheticals, soft dependencies and statuses such as
`Done -- shipped in #12` or `Shipped (#34)`, that reading reports items
blocked and unblocked in ways a person reading the roadmap wouldn't.

`roadmap-status.sh --unit` writes a landed feature back to the roadmap: it
deletes the item's `**Needs:**` and `**Outcome:**` lines and writes
`**Status:** Done` followed by `**Outcome:** <what landed>`. On a milestone
that deletes the outcome the milestone is judged against, and only its
first line, leaving the rest of a wrapped Outcome behind.

The fifth reader is `/roadmap` itself: its format reference defines the
per-feature block as Needs, Dependencies and Status, its draft phase writes
that block, its jury rejects anything that looks like requirements (which
Evidence clauses resemble), and its resume logic offers "revise or start
fresh" on an Active roadmap with no procedure behind it. Nothing in code
enforces the rule that an Active roadmap's Features list is locked; it is
documentation only.

The PRD this design answers (`docs/prds/PRD-milestone-format.md`) asks for
milestone roadmaps marked `schema: roadmap/v2` (R1), a precise grammar
(R2), a stated Done rule and Active-roadmap edit rules (R3, R4), validator
errors naming a milestone that lacks its Outcome, Evidence or the rest of
its shape on v2 only (R5, R6), `roadmap/v1` validating exactly as today
(R7), unchanged lifecycle (R8), a parse that keeps milestone fields out of
v2 descriptions (R9), the picker's reading rules for any roadmap (R10),
prefixed tags resolving in populate and the validator (R11), a status
writer that never touches an Outcome (R12), `/roadmap` drafting milestones
and offering sharpen-in-place (R13, R14), scripts that run on bash 3.2
(R15), and verification by suites and CI rather than skill evals (R16).

## Decision Drivers

- **`roadmap/v1` stays untouched in validation** (R7). Every roadmap
  written so far must produce the same findings at the same severities.
- **One meaning per field across readers.** The validator, populate and
  the picker must agree on what a milestone's tag and dependencies are, or
  a roadmap that validates still gets misread at pick time.
- **The interim spelling is already in use.** A roadmap written in
  milestone form today should become valid `roadmap/v2` by changing its
  schema line, so the field names can't move.
- **The picker runs on coordinator hosts with bash 3.2, BSD userland and
  jq** (R15). Its reader can't assume GNU tools or a newer shirabe binary
  than the plugin it ships in.
- **Changes to `skills/coordinate/` stay contained.** Other work changes
  the picker too, so the change touches the parser library, the facts
  computation and the status writer, and not the koto template.
- **No enforcement of the Done rule here.** The rule is documented (R3);
  making the cascade and the coordinator obey it is later work.

## Considered Options

### Decision 1: How the validator accepts `roadmap/v2`

Resolved inline.

The validator has to run milestone rules on v2 documents and nothing new
on v1. Routing is by filename prefix, one `FormatSpec` per prefix, and the
schema gate compares the document's schema to the spec's single
`schema_version`.

Key assumptions:
- Only test helpers look a format up by `schema_version`; production code
  routes by prefix. FC02's `custom_statuses` override is keyed by
  `spec.schema_version`, so a v2 document inherits a repository's
  `roadmap/v1` status override, which is the behaviour wanted.
- FC16 checks `spec.schema_version == "roadmap/v1"`, which stays true for
  the one Roadmap spec, so FC16 keeps running on v2 documents.

#### Chosen: one Roadmap spec that accepts both schemas, plus FC21 gated on v2

`FormatSpec` gains a method `accepts_schema(&self, schema: &str) -> bool`
returning true for `schema_version` and, on the Roadmap spec, for
`roadmap/v2` (a `ROADMAP_V2_SCHEMA` constant in `formats.rs`).
`check_schema` calls it instead of comparing strings. A new check,
`check_fc21_milestones`, runs in the Roadmap arm of `validate_structural`
and returns nothing unless `doc.schema == ROADMAP_V2_SCHEMA`. FC21 is
error-level (absent from `is_intrinsic_notice`) and selectable with
`--check FC21`. Every existing roadmap check runs unchanged on both
versions, and a v1 document's findings can't change because nothing new
runs on it.

#### Alternatives Considered

**A second `FormatSpec` for `roadmap/v2`.** Rejected: `detect_format`
returns one spec per prefix, so routing would have to read the schema
before choosing a spec, every `schema_version == "roadmap/v1"` gate would
need a second arm, and the format-count tests change for a spec that
differs only by one check.

**Strict milestone checks on any roadmap whose items carry an Outcome.**
Rejected: roadmaps that recorded merged pull requests on `**Outcome:**`
would start failing, which breaks R7, and the switch would be invisible in
the document.

### Decision 2: How the Rust readers share milestone fields and tag resolution

Resolved inline.

Populate and FC21 both need the milestone fields and the same answer to
"which milestone does this dependency name". Populate's output on a
`roadmap/v1` roadmap is committed in roadmaps already in use, so its
description cells can't shift.

Key assumptions:
- Populate keeps reading only the Dependencies line (R11).

#### Chosen: extend `Feature`, gate the description change on v2, share one resolver

`Feature` gains `tag` (the heading's tag, `Feature 3` or `AB10a`),
`outcome`, `evidence`, `left_open` and `delivered` as `Option` values
(`None` when the field line is absent), and `dependencies_continued`
(true when a non-blank, non-field line follows the Dependencies line).
`parse_features` reads the field extents of PRD R2: a value runs to the
first blank line, the next field line or the next heading, and an
Evidence clause is a column-0 `- ` line plus indented continuation lines.
Any column-0 `**Name:**` line, `**Downstream:**` included, ends the field
before it. The parser reads `doc.schema`: on a `roadmap/v2` document the
free `description` holds only lines outside every field line's extent; on
`roadmap/v1` it is built exactly as today, so populate's v1 output is
unchanged.

One resolver, `features::dependency_positions(deps: &str, features:
&[Feature]) -> Vec<usize>`, replaces populate's `feature_refs_in`. It
returns 1-based positions, first-seen order, deduplicated, from `Feature
N`, `Features N, M and K` and `F<N>` (each resolving to the item tagged
`Feature N` when one exists, else to position N) and from whole-word tags
equal to another feature's tag. FC21 checks v2 Dependencies tokens
against the same tag table.

The heading grammar gains the optional lowercase letter suffix, so
`### AB10a:` is an item in every Rust reader.

#### Alternatives Considered

**A separate milestone parser beside `parse_features`.** Rejected: two
parsers of one section are how readers drift, which is the problem this
work exists to fix.

**Removing field text from `description` on both versions.** Rejected:
every populated v1 roadmap whose features carry an `**Outcome:**` line
would change on its next populate run, for no reader's benefit.

### Decision 3: Where the picker's reading of older roadmaps lives

Resolved inline.

PRD R10 gives the picker eight rules for reading any roadmap: item
headings, finished and closed statuses, the wrapped dependency paragraph,
soft markers, parentheticals, sentences opening with `Soft`, resolution,
and when an item is blocked. The picker runs on coordinator hosts.

Key assumptions:
- jq's regex engine (Oniguruma) supports `scan`, `splits`, `gsub`, inline
  `(?i:...)` groups and lookahead on macOS (jq 1.7.1) and on the Linux
  runners; the soft-marker step uses one lookahead.

#### Chosen: keep the reading in `lib_roadmap_features`, awk to collect and jq to decide

`lib_roadmap_features` stays the one bash reader its three callers share.
Its awk pass recognizes item headings by the R2 grammar and emits, per
item, the status line and the dependency paragraph (the Dependencies line
plus following lines up to a blank line, a field line or a heading). Its
jq pass applies R10's rules 2 and 4 to 7 and emits `{number, id, title,
status, finished, done, dependencies}`, adding `finished` beside the
existing `done` (finished or closed). `pick-facts.sh` counts a dependency
satisfied when the depended-on unit is `finished`, and never marks a
`done` unit blocked. `roadmap-status.sh` and `closeout-read.sh` keep
reading `done`, which now also covers annotated and `Shipped` statuses.

#### Alternatives Considered

**A `shirabe roadmap facts` subcommand the picker calls.** Rejected: every
coordinator host would need a shirabe binary at least as new as the
plugin, the picker would gain a process boundary for a few dozen lines of
text processing, and PRD R10's legacy rules are the picker's alone, so the
CLI would carry rules nothing else uses.

**All rules in awk.** Rejected: BSD awk has no case-insensitive matching
or capture groups, which the soft-marker and token rules need, and
resolving tags against the whole item list is a second pass jq already
makes easy.

### Decision 4: How `/roadmap` offers sharpen-in-place

Resolved inline.

The PRD's walkthrough runs `/roadmap` on an Active roadmap. The skill's
resume logic already lands there on its row "ROADMAP exists with status
Active: offer to revise or start fresh", with no procedure behind it.

#### Chosen: give the Active-roadmap resume row a procedure

On an Active `roadmap/v2` roadmap the row offers two choices: sharpen one
milestone's Evidence or Left open in place, or start a new roadmap. A new
reference file, `skills/roadmap/references/phases/sharpen.md`, holds the
procedure: pick the milestone and the field, rewrite only that field's
lines, run `shirabe validate`, and commit. A `roadmap/v1` Active roadmap
keeps "start a new roadmap" as its only choice, with a note that
migrating to `roadmap/v2` is what makes sharpening available.

#### Alternatives Considered

**A `/roadmap sharpen <path> <tag>` verb.** Rejected: a second entry point
for the same situation, which an author has to know exists, and one more
token the `activate` and `done` verb parsing has to keep apart.

## Decision Outcome

Milestone roadmaps are an opt-in schema value with the spelling roadmaps
in milestone form already use. The validator sees one Roadmap format and
runs one extra check on v2, so nothing changes for v1. The Rust readers
gain the fields and one tag resolver, which makes the validator and
populate agree on what a dependency names; the bash picker reads the same
item grammar and tags, plus the legacy rules that only older roadmaps
need. The status writer stops writing the field milestones depend on.
`/roadmap` writes v2 by default and its existing Active-roadmap branch
gets the sharpen procedure, which the edit rules in the format reference
now allow.

The decisions don't conflict: decision 2's resolver and decision 3's jq
rules share the item grammar, the whole-token tag match and the
`Feature N` fallback. Each side has its own tests over the same cases
(prefixed tags, a letter suffix, `Feature N` on a prefixed roadmap); the
legacy prose rules exist only on the bash side.

## Solution Architecture

### Overview

Five components change, each owning one reader, and the format reference
states the contract all of them read.

### Components

**Format reference** (`skills/roadmap/references/roadmap-format.md`). A
new "Milestone roadmaps (`roadmap/v2`)" section carries the grammar of PRD
R2 with a worked milestone, the four Status values, the Done rule of R3,
and the Active-roadmap edit rules of R4, including the amendment line
`- YYYY-MM-DD: <tag> Outcome amended -- <what changed and why>`. The
existing Heading forms text gains the letter suffix. Validation
Enforcement lists FC21. A "Migrating a roadmap" note says a roadmap
already written in the interim milestone spelling migrates by changing its
schema line.

**Parser** (`crates/shirabe-validate/src/features.rs`).

```rust
pub struct Feature {
    pub id: usize,
    pub tag: String,                 // "Feature 3", "AB10a"
    pub label: String,
    pub needs: String,
    pub dependencies: String,        // the Dependencies line, as today
    pub dependencies_continued: bool,
    pub status: String,
    pub outcome: Option<String>,     // joined with single spaces
    pub evidence: Option<Vec<String>>, // one string per clause
    pub left_open: Option<String>,
    pub delivered: Option<String>,
    pub description: String,
    pub heading_line: usize,
}

pub fn dependency_positions(deps: &str, features: &[Feature]) -> Vec<usize>;
pub fn is_milestone_heading(line: &str) -> bool; // R2 grammar, non-empty title
```

**Validator** (`formats.rs`, `checks.rs`, `validate.rs`).
`FormatSpec::accepts_schema` and `ROADMAP_V2_SCHEMA`; `check_schema`
calls `accepts_schema`; `check_fc21_milestones(doc, spec)` returns one
`ValidationError` per finding, with the milestone's heading line and a
message `[FC21] milestone '<tag>: <title>' <problem>`:

| Condition | Problem text |
|-----------|--------------|
| `outcome` is `None` | `has no Outcome` |
| `outcome` is empty | `has an empty Outcome` |
| `evidence` is `None` | `has no Evidence` |
| `evidence` has no clause | `has no Evidence clause` |
| `left_open` is `None` or empty | `has no Left open` |
| `dependencies` empty | `has no Dependencies` |
| `dependencies_continued` | `has a Dependencies line that continues onto the next line` |
| an entry that is neither `None` alone, another milestone's tag, nor `<owner>/<repo>#<n>` | `names '<entry>' in Dependencies, which is no other milestone` |
| `status` not one of the four values | `has Status '<status>', not one of Not started, In progress, Done, Dropped` |
| two milestones share a tag | `repeats the tag of the milestone at line <n>` |
| a `###` line in Features fails `is_milestone_heading` | `heading '<text>' is not a milestone heading` (on that line) |

`parse_features` drops a `###` line that isn't an item, so FC21 scans the
Features section's body lines itself for that last row, using the same
section bounds. `is_known_check_code` gains `FC21`.

**Populate** (`crates/shirabe/src/populate.rs`). `feature_refs_in`
callers move to `dependency_positions`. On a `roadmap/v2` document the
description fed to `summarize_description` and to an `--issues` issue body
is the Outcome; on `roadmap/v1` it is `description`, as today.

**Picker library** (`skills/coordinate/scripts/record-common.sh`).
`lib_roadmap_features` keeps its signature and adds `finished`:

1. awk, over CR-stripped input: inside `## Features`, a `### ` line
   matching `^(Feature [0-9]+|[A-Za-z]+[0-9]+[a-z]?): ` starts an item,
   any other `### ` line ends one; `**Status:**` sets the status; the
   `**Dependencies:**` line starts the paragraph, and following lines join
   it until a blank line, a line matching `^\*\*[A-Z][A-Za-z ]*:\*\*`, or a
   heading. Tabs become spaces and each item prints one TSV row.
2. jq, with the whole item list in hand:
   - `finished`: status matches `^(Done|Shipped)([^A-Za-z0-9-]|$)`;
     `done`: `finished` or status matches `^Dropped([^A-Za-z0-9-]|$)`.
   - dependencies: empty when the paragraph's first word is `None`;
     otherwise each soft mention is struck where it stands: a tag followed
     by a parenthesised marker (`soft`, `optional`, `preferred`,
     `sequencing-preferred`, `paced by`, any case) loses the tag alone,
     found with a lookahead so the parenthetical stays for the next step,
     and a tag followed by a bare marker goes with its marker. A hard
     mention of the same tag elsewhere still counts. Then
     `\([^()]*\)` pairs are stripped while one matches
     (at most 20 passes), the text is split at `[.;]\s+`, sentences whose
     first word is `soft` (any case) are dropped, and the rest resolves
     `Feature N`, `Features N, M and K` and `F<N>` (tag `Feature N` if
     present, else position N) and tags of other items, matched as whole
     `[A-Za-z0-9]+` tokens, minus the item's own tag; positions sorted
     ascending and unique.

**Facts** (`skills/coordinate/scripts/pick-facts.sh`). The `$by` list
counts a dependency unsatisfied unless the depended-on unit is `finished`;
`blocked` is `(not done) and ($by | length > 0)`; `blocked_by` is `[]` for
a done unit.

**Status writer** (`skills/coordinate/scripts/roadmap-status.sh`). Its awk
drops the item's `**Needs:**` and `**Delivered:**` fields with their
continuation lines, prints `**Status:** Done` then `**Delivered:**
<text>` in place of the Status line, and passes every other line
through, `**Outcome:**` included. A dropped field's extent is its marker
line plus the following lines up to a blank line, the next column-0
`**Name:**` line or a heading. The post-write check greps for the
Delivered line. `--confirm`'s own `case Done|Done.|Dropped|Dropped.` test
moves to the library's `done`, so an annotated `Done -- shipped in #12`
confirms. The `--outcome` flag keeps its name, so the coordinator's
koto template is untouched; its help text and the coordinate skill's prose
say the value lands on `**Delivered:**`.

**`/roadmap` skill** (`skills/roadmap/`). `SKILL.md` says drafts are
`roadmap/v2` milestones and points the Active-roadmap resume row at
`references/phases/sharpen.md`. Phase 1 adds "Outcome and evidence per
milestone" to its coverage dimensions; phase 2's agents check that each
outcome is something a user can do and each evidence clause is judgeable
by a non-author; phase 3's template writes `schema: roadmap/v2` and the
R2 fields; phase 4's annotation-and-boundary reviewer reports a
mechanism Outcome, an author-only or merge, test-run or artifact Evidence
clause, and a Left open holding part of the Outcome as findings that send
the draft back, and its "no requirements" rule says Evidence is how
someone else checks the outcome end to end, not how the feature must
behave. Two evals are added for the walkthroughs.

### Key Interfaces

- `schema: roadmap/v2` in a roadmap's frontmatter is the switch.
- `FC21` is the new validator code; its messages always start with the
  milestone's `'<tag>: <title>'`.
- `lib_roadmap_features` output gains `finished`; existing fields keep
  their meaning except that `done` and `dependencies` follow PRD R10. The
  wider `done` reaches `closeout-read.sh`, `roadmap-status.sh` and, through
  the facts, `progress-view.sh`.
- `roadmap-status.sh --unit TAG --outcome TEXT` writes `**Delivered:**
  TEXT`.

### Data Flow

An author's `/roadmap` run writes a v2 roadmap; `shirabe validate` reads
it through `parse_features` and FC21; `shirabe roadmap populate` renders
the reserved sections from the same parse. A coordinator reads the same
file from the host's default branch through `lib_roadmap_features`,
computes facts in `pick-facts.sh`, and, when work lands, writes the
Delivered line back through `roadmap-status.sh`. Nothing new is stored
anywhere.

## Implementation Approach

### Phase 1: Parser and resolver

Extend `Feature`, the field extents, the heading suffix,
`dependency_positions` and `is_milestone_heading`, with unit tests for a
three-line Outcome, three Evidence clauses (one wrapped), a two-line Left
open, a Delivered line, v1 description unchanged, and each resolution
form.

Deliverables:
- `crates/shirabe-validate/src/features.rs`

### Phase 2: Validator

`accepts_schema`, `ROADMAP_V2_SCHEMA`, FC21 and its registration, with one
test per condition in the table above, a fully valid v2 fixture, the
v1/v2/v3 schema trio, and a v2 transition test.

Deliverables:
- `crates/shirabe-validate/src/formats.rs`, `checks.rs`, `validate.rs`
- fixtures under `crates/shirabe-validate/tests/` or inline test docs

### Phase 3: Populate

Description and issue body from Outcome on v2, prefixed-tag edges on
both versions, with CLI tests.

Deliverables:
- `crates/shirabe/src/populate.rs`, `crates/shirabe/tests/populate_cli.rs`

### Phase 4: Picker and status writer

The awk and jq passes, the facts change, the Delivered writer, and a
picker fixture roadmap committed with its expected facts covering every
R10 rule, run under `/bin/bash` 3.2.

Deliverables:
- `skills/coordinate/scripts/record-common.sh`, `pick-facts.sh`,
  `roadmap-status.sh` and their tests
- `skills/coordinate/scripts/testdata/milestones/` fixture and expected
  facts
- `skills/coordinate/SKILL.md`, `references/record-template.md` prose

### Phase 5: Format reference and `/roadmap`

The format reference section, the skill and phase prose, the sharpen
procedure, two evals, and release notes under `docs/guides/`.

Deliverables:
- `skills/roadmap/references/roadmap-format.md`, `SKILL.md`,
  `references/phases/phase-1-scope.md` to `phase-4-validate.md`,
  `references/phases/sharpen.md`, `evals/evals.json`
- `docs/guides/RELEASE-NOTES-milestone-format.md`

## Security Considerations

The change reads and writes Markdown roadmaps. The new code downloads
nothing, executes nothing from the documents, and adds no permission,
credential or network call. The picker and status writer keep the `gh`
reads and writes they already make, and the Delivered text the writer
records still comes from the coordinator, as the Outcome text did. No
reader resolves a cross-repo Dependencies entry over the network; FC21
checks its shape only.

Roadmap text is untrusted input, both to these parsers and to the agents
that later read the fields. The Rust parser treats it as data. The bash
library passes it to awk on stdin and to jq as data, never through a shell
or `eval`, and compares tags as literal strings (token equality, awk
`index()`), never as patterns. The status writer passes its text to awk
through the environment rather than `-v` and prints it without
`sub`/`gsub`, so backslashes, `&` and quotes arrive as written; its
post-write check is a fixed-string `grep -qxF`; and it keeps refusing an
`--outcome` with a newline or carriage return.

Three bounds keep hostile or careless text from stalling or fooling the
picker. The parenthesis-stripping step loops only while a `\([^()]*\)`
pair matches and stops after 20 passes; anything nested deeper stays in
the text and counts as a dependency, which errs toward blocked. A
dependency paragraph over 4 KB makes the reader exit with an error naming
the item, rather than truncating it and dropping dependencies. And a jq
whose regex engine rejects a pattern makes the reader exit with an error
rather than report dependencies as absent. The picker fixture includes an
unbalanced-parenthesis case and an over-long paragraph.

A hostile or careless roadmap can at worst make the picker read a wrong
blocked state. `finished` now matches `Done` or `Shipped` followed by any
punctuation, so `Done?` reads finished; anyone who can edit a roadmap on
the default branch could already unblock its dependents by writing
`Done`. Roadmaps are reviewed like code before they reach the default
branch, which is the control both cases rely on.

Nothing private moves in this change. The format reference and test
fixtures are public and synthetic, not copied from real roadmaps, and the
corpus check runs locally with its results kept outside the repository.
One residual risk carries over from the old Outcome line: the text a
coordinator records on `**Delivered:**` in a public roadmap could name
private work. The coordinate skill's prose and the release notes say that
text names only public pull requests; a mechanical guard is left to the
later work on the coordinator's write-back.

## Consequences

### Positive

- An author gets milestones without asking, and the validator holds every
  v2 roadmap to its fields.
- The validator, populate and the picker agree on tags and dependencies,
  so prefixed-tag roadmaps draw edges and pick correctly.
- Roadmaps in the interim spelling migrate with a one-line change.
- A coordinator's record of what merged can no longer erase an outcome.

### Negative

- Two readings of dependencies exist: the strict one-line list of v2, and
  the picker's prose heuristics for older roadmaps. The heuristics can
  misread prose nobody anticipated.
- `done` in `lib_roadmap_features` widens (annotated `Done`, `Shipped`),
  so `roadmap-status.sh --unit` refuses items it accepted before, and
  close-out reads a roadmap complete sooner.
- Populate output on a `roadmap/v1` roadmap with prefixed-tag dependencies
  changes on its next run, as edges appear.
- The Done rule is documented, not enforced; the status writer and the
  cascade still set Done on a merge.

### Mitigations

- The picker fixture pins every heuristic with expected facts, and the
  heuristics apply only where a v2 roadmap's validated list doesn't, so
  migrating a roadmap retires them for it.
- The wider `done` is what a reader of those statuses means; the release
  notes call out the refusal change.
- The new edges are correct ones, and FC06 and FC07 accept the regenerated
  sections.
- The format reference says the rule isn't enforced yet, and a
  coordinator driving a milestone roadmap can decline to run the
  merge-driven writer until later work changes the tools.
