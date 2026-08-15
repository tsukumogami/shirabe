---
schema: design/v1
status: Planned
upstream: docs/prds/PRD-issue-outlines-one-parser.md
problem: |
  Three independent parsers read a single-pr PLAN's `## Issue Outlines`
  section and disagree in eight ways. The lenient Rust reader gates
  validation, the strict bash reader decides what gets built, and a PLAN with
  an unrecognized dependency reference validates at exit 0 and then extracts
  to a task graph with no edges at all.
decision: |
  One walk of the section lives in `shirabe-validate`, producing a record
  rich enough for every consumer. FC14 and L06 call it directly; the shell
  extractor reaches it through a new `shirabe plan outlines` subcommand that
  emits a versioned JSON envelope. The unresolvable-dependency finding gets
  its own error-level code so the fail-open case stops the run, while the
  cases that already fail closed stay notice-level.
rationale: |
  Agreement between readers is worth having as a structural property rather
  than a maintenance obligation, which is what #271 established one layer
  down for the `upstream:` field. The parse moves and the callers do not:
  naming, slug collision, and scheduling policy read nothing from the
  document, so moving them would widen the blast radius without buying any
  agreement.
---

# DESIGN: One parser for the Issue Outlines section

## Status

Planned

## Context and Problem Statement

`docs/prds/PRD-issue-outlines-one-parser.md` states the requirements. The
technical problem is narrower than the defect report suggests, and one part
of it is harder than it looks.

Three implementations walk `## Issue Outlines` today:

| Reader | Location | Consumer |
|---|---|---|
| `parse_issue_outlines` | `crates/shirabe-validate/src/table.rs` | FC14 |
| `parse_outline_acs` | `crates/shirabe-validate/src/table.rs` | L06 |
| `process_single_pr` | `skills/plan/scripts/plan-to-tasks.sh` | `/execute` |

They disagree in eight identified ways, catalogued during the PRD's research.
Collapsing them to one is straightforward for six of those. The two that need
actual decisions are what counts as a block boundary, and what the collapsed
parser's acceptance-criteria tolerance should be — because the two Rust
readers already answer both differently, and each answer is load-bearing for
its own consumer.

**Block boundary.** `parse_issue_outlines` and `parse_outline_acs` both open a
new block on any `### ` line. `process_single_pr` opens one only on
`### Issue <N>: <title>`, treats `### Dependencies` as a sub-section of the
block already open, and ignores every other `###` entirely — so a stray
sub-heading leaves the current outline in flight and its later fields still
attach to that outline. A collapsed parser has to pick one rule, and picking
the Rust one would change what gets built.

**Acceptance-criteria tolerance.** `parse_issue_outlines` ends AC accumulation
at the first non-blank line that is not a bullet. `parse_outline_acs` keeps
the block in flight until a `**Label**:`, `###`, or `##` line and silently
drops non-canonical bullets, which the cascade-outline-AC design records as a
deliberate strict-tolerance contract. These cannot both survive as written.

The saving detail is that FC14 never reads the accumulated list. It calls
`block.acceptance_criteria.is_none()`, and the parser sets that field to
`Some(vec![])` the moment the `**Acceptance Criteria**:` label appears. The
field is a label-presence boolean wearing a vector's clothes. So the two
tolerances are not actually in competition: L06's is the only one with a
consumer, and FC14 needs a boolean it can have for free.

The remaining problem is delivery. `plan-to-tasks.sh` is a bash script with a
documented contract, invoked by `/execute` against a file path with no network
and no GitHub access. Whatever surface it uses to reach a Rust parse has to
preserve that.

## Decision Drivers

- **One reader, structurally.** The point of the change is that agreement
  stops being something a maintainer verifies. Any option that leaves two
  implementations to keep in step fails on arrival, however well they agree
  on the day it lands.
- **The strict reader's behavior is the target.** Extraction decides what gets
  built, so where the readers disagree, the collapsed parser matches the
  extractor. Loosening it to meet the validator would trade a silent
  wrong-order build for a silent wrong-graph build.
- **Blast radius.** 54 bash test cases and the koto task-entry contract sit
  downstream of `plan-to-tasks.sh`. The change should not require any of them
  to be rewritten, and per the PRD's R12 it must not require any to be edited.
- **Severity where it buys something.** Promoting a finding to error is a
  breaking change for every adopter. It is worth it for the case that fails
  open and silently; it buys nothing for the cases that already refuse loudly.
- **The CLI-surface rule.** No subcommand renders or creates an artifact body.
- **Offline and repo-free.** The extractor runs against a path today with no
  git state. It has to keep doing that.

## Considered Options

### Decision 1 — What surface exposes the parse to the shell

**Option 1A: a `shirabe plan outlines <PLAN.md>` subcommand emitting JSON.**
The CLI reads the document, parses the section, resolves dependencies, and
writes a versioned envelope to stdout. `plan-to-tasks.sh` consumes it with
`jq`, which the script already requires. **Chosen.**

**Option 1B: a `shirabe validate --outlines <PLAN.md>` mode.** Reuses the
existing command and its envelope. Rejected: `validate`'s envelope carries
findings, and the extractor wants the document's contents, not a verdict on
them. Bending the findings shape to carry outline data would make the JSON
schema serve two unrelated jobs, and the exit-code contract would then have to
mean both "this document has violations" and "here is what it says".

**Option 1C: move the whole single-pr extraction path into Rust.** The CLI
emits finished koto task entries and the bash single-pr branch disappears.
Rejected: naming, the `o-` prefix, 64-character truncation, collision
suffixing, and the file-ownership edges read nothing from the document, so
moving them buys no agreement. They do put the koto task-entry contract and
every one of the 54 bash cases in the blast radius. The issue's own framing is
that what changes is where the parse lives, not who calls it.

**Option 1D: generate the bash parser from a shared specification.** Rejected:
a build step and a generated artifact in review, for a duplication that a
function call removes. It also leaves a generated parser that can go stale
against its generator in a checkout that skipped the build.

### Decision 2 — How the two Rust readers collapse

**Option 2A: one walk producing a record that carries everything, with
`parse_outline_acs` retired and L06 reading the AC entries off the blocks.**
**Chosen.** The AC tolerance kept is L06's, because FC14 only reads label
presence (established above) and therefore loses nothing.

**Option 2B: keep both public functions, both delegating to one private
walk.** Rejected as a smaller version of the problem it fixes. Two entry
points over one walk is fine mechanically, but `parse_outline_acs`'s only
distinguishing behavior was its tolerance, and once that moves into the shared
walk the second function is a filter with a name that suggests it is a parser.
The next maintainer reading `parse_outline_acs` would reasonably expect it to
parse.

**Option 2C: keep `parse_outline_acs` and route FC14 through it too.**
Rejected: it is the narrower of the two, carrying no goal, dependency, type,
or files data, so FC14 would need a second source for everything else.

### Decision 3 — What opens a block

**Option 3A: only a conforming `### Issue <N>: <title>` opens an outline
block. `### Dependencies` opens a dependencies sub-section of the block
already open. Any other `### ` line inside the section is recorded as a
non-conforming heading, is not a boundary, and leaves the current block in
flight.** **Chosen** — this is `process_single_pr`'s behavior stated
positively, and Decision Driver 2 says the extractor's behavior is the target.

**Option 3B: any `### ` opens a block, as the Rust readers do today.**
Rejected: it is the rule that produces the phantom `Dependencies` outline, and
adopting it would mean the extractor changes what it builds for every document
using the `### Dependencies` shape that two existing tests cover.

**Option 3C: any `### ` opens a block, and `### Dependencies` is special-cased
back out.** Rejected as 3B with a patch. The general rule would still be wrong
for every other stray sub-heading, and the special case would be the second
thing a reader has to hold.

A consequence worth stating: under 3A a non-conforming heading's following
fields attach to the previous conforming block, or to nothing when no
conforming block has opened yet. That is odd, and it is what the extractor
does today. Changing it would change what gets built, which is out of bounds
here; recording the heading in a separate list is what lets the validator say
so out loud instead of the shape passing unremarked.

### Decision 4 — Severity, and which code carries it

**Option 4A: a new error-level `FC17` for the unresolvable-dependency finding;
FC14 keeps its existing notice-level structural sub-checks, and the new
non-conforming-heading finding joins them at notice level.** **Chosen.**

**Option 4B: promote FC14 wholesale by removing its arm from
`is_intrinsic_notice`.** Rejected: severity is keyed on the code, and FC14
covers four sub-checks. Promoting the one that matters would promote
missing-`**Goal**:`, missing-`**Acceptance Criteria**:`, and the `issue_count`
mismatch along with it, turning several fixtures from exit-0-with-notices into
errors for reasons unrelated to this defect.

**Option 4C: promote nothing and let the extractor's refusal carry the whole
job.** Rejected by the PRD's R7, and for the reason recorded there: the
complaint is specifically that the document validates clean.

The line between the two severities is worth naming, because it is the rule a
future check should be measured against rather than a per-case judgment.
**A finding is promoted to error when the failure it describes is silent and
permissive; it stays a notice when the failure it describes already refuses
loudly.** An unresolvable dependency produces a plausible task graph missing
an edge, and nothing downstream says so — error. A non-conforming heading
produces no tasks and a refusal with a message — notice, because the run
already stops and adding a second stop earlier buys the author nothing they
were not about to be told.

### Decision 5 — Finding the binary from the shell

**Option 5A: the `SHIRABE_BIN` precedence ladder `run-cascade.sh` already
uses — the environment variable, then `shirabe` on `PATH`, then a locally
built release or debug binary — with a missing binary a hard exit.**
**Chosen.** A sibling script in this repo already solves this exact problem,
including the environment override the test harness needs.

**Option 5B: require `shirabe` on `PATH` and nothing else.** Rejected: it
breaks a developer working from a `cargo build` in a checkout, which is how
the bash suite runs.

**Option 5C: fall back to the existing bash parser when the binary is
missing.** Rejected, and it is the option most worth rejecting explicitly. It
would leave a second parse in the tree, reachable exactly when nobody is
watching, which is the arrangement this design exists to remove. A missing
binary is a broken environment and should say so.

One difference from `run-cascade.sh`: that script requires a git repository
and exits when `git rev-parse` fails, because it transitions documents.
`plan-to-tasks.sh` reads one file and must keep working outside a repo, so the
repo-root probe is best-effort and only feeds the target-directory fallbacks.

## Decision Outcome

The parse moves into `shirabe-validate` as a single walk producing an
`OutlineBlock` rich enough for all three consumers. FC14 and L06 call it
in-process. `plan-to-tasks.sh` calls `shirabe plan outlines <PLAN.md>` and
reads a versioned JSON envelope, keeping every naming and scheduling decision
it makes today. The unresolvable-dependency finding becomes an error under a
new `FC17`; everything that already fails closed stays a notice under FC14.

The pieces fit because each consumer takes a different projection of one
record and none of them re-reads the document. FC14 reads three booleans and
the unresolved-token list. L06 reads the acceptance-criteria entries. The
extractor reads numbers, titles, resolved dependencies, types, and files. Add
a field to the record and all three can see it; today the same field is three
edits in two languages and the middle one is easy to miss.

The severity split holds the line the PRD drew without over-reaching: the one
failure mode that was silent stops the run, and the ones that were already
loud stay where they are.

## Solution Architecture

### The record

`OutlineBlock` gains the fields the extractor needs and the conformance
information the validator needs. The section-level result carries the blocks
plus the headings that were not blocks.

```rust
pub struct OutlineSection {
    /// One entry per conforming `### Issue <N>: <title>` heading, in
    /// document order.
    pub blocks: Vec<OutlineBlock>,
    /// `### ` headings inside the section that are neither a conforming
    /// outline heading nor the `Dependencies` sub-heading. Recorded so a
    /// consumer can report them; they are not block boundaries.
    pub nonconforming_headings: Vec<NonconformingHeading>,
}

pub struct OutlineBlock {
    pub key: String,             // heading text, "Issue 1: feat: add parser"
    pub number: u32,             // parsed from the heading
    pub title: String,           // parsed from the heading
    pub line: usize,             // 1-indexed heading line
    pub goal_declared: bool,
    pub acceptance_criteria_declared: bool,
    pub acceptance_criteria: Vec<OutlineAc>,
    pub dependencies_declared: bool,
    pub dependencies_none: bool,
    /// Sibling outline numbers this block waits on, in written order,
    /// de-duplicated.
    pub waits_on: Vec<u32>,
    /// Dependency tokens that named no sibling outline, verbatim.
    pub unresolved_dependencies: Vec<String>,
    pub issue_type: Option<String>,
    pub files: Vec<String>,
}
```

`OutlineAc` keeps its current shape (`outline_key`, `ac_text`, `ticked`,
`line`), so L06 is unchanged apart from where it gets its input.

`goal_declared` and `acceptance_criteria_declared` replace the
`Option`-wrapped fields FC14 reads today. They say what FC14 actually asks,
and they remove the misleading `Some(vec![])` that looked like content and
never was.

### The walk

One pass over the section, two-stage. Stage one collects blocks, fields, and
non-conforming headings. Stage two resolves dependencies, which cannot happen
during stage one because a block may name a sibling that appears later.

Recognition rules, all of them the extractor's current behavior stated
positively:

| Line shape | Meaning |
|---|---|
| `### Issue <N>: <title>` | Opens a block. Closes the previous one. |
| `### Dependencies` | Opens a dependencies sub-section of the open block. |
| Any other `### ` | Recorded as non-conforming. Not a boundary. |
| `**Goal**:` | Sets `goal_declared`. |
| `**Acceptance Criteria**:` | Sets the declared flag, enters the AC state. |
| `**Dependencies**:` or `**Dependencies:**` | Sets the declared flag, carries the value. |
| `**Type**:` | Records the value, lowercased. |
| `**Files**:` | Records the backtick-quoted tokens. |
| `- [ ]` / `- [x]` / `- [X]` in the AC state | An acceptance criterion. |

Any `**Label**:` line, a `###`, or the section end leaves the AC state. A
non-canonical bullet inside the AC state is dropped without leaving it, which
is L06's strict-tolerance contract carried over unchanged.

Dependency value handling: strip a trailing period, then test the literal
`None` case-insensitively — in that order, which is what fixes the false
positive on the contract's own `**Dependencies**: None.` example. Otherwise
extract `<<ISSUE:N>>` placeholders and `Issue N` references and resolve each
against the set of block numbers parsed from the headings. A reference to a
number no block declares lands in `unresolved_dependencies` verbatim.

Resolution is by declared number, not by position. The two agree for a
document numbered `1..N` in order and diverge for anything else, and the
heading is what the author wrote.

### The CLI surface

```
shirabe plan outlines <PLAN.md>
```

A `plan` subcommand group with one subcommand, following the `roadmap
populate` precedent. It reads the document, runs the walk, and writes one JSON
object to stdout:

```json
{
  "schema": "shirabe-plan-outlines/v1",
  "path": "docs/plans/PLAN-x.md",
  "execution_mode": "single-pr",
  "outlines": [
    {
      "number": 1,
      "title": "feat: add parser",
      "key": "Issue 1: feat: add parser",
      "line": 42,
      "goal_declared": true,
      "acceptance_criteria_declared": true,
      "dependencies_declared": true,
      "dependencies_none": false,
      "waits_on": [],
      "unresolved_dependencies": [],
      "type": null,
      "files": []
    }
  ],
  "nonconforming_headings": []
}
```

Acceptance-criteria entries are not in the envelope. The extractor does not
read them and the only in-process consumer is L06, so shipping them over the
CLI boundary would be schema surface with no reader.

**Exit codes** follow the established scheme: 0 when the document parsed, 1
when it could not be read or is not a PLAN, 3 on I/O failure. Parsing is not
judgment, so a document full of unresolvable dependencies still exits 0 and
reports them in the envelope. The refusal is the consumer's call, which is
what keeps this a parser with two consumers rather than a third opinion.

**Why this is not artifact authoring.** The rule in CLAUDE.md forbids a
subcommand that renders or creates an artifact body, because authoring belongs
to a skill. This subcommand writes no document and creates nothing; it reads
one and reports what it says, which is the deterministic parsing and feedback
the same rule places in the CLI next to `validate` and `slug-prefix-detect`.
The distinction that matters is the direction of the data: `roadmap populate`
was allowed because it fills reserved sections from context the CLI can
compute, and the removed `coordination create` subcommand was not because it
rendered a body. This one only ever reads.

### The validation consumers

`check_fc14` calls the walk and reads `goal_declared`,
`acceptance_criteria_declared`, `dependencies_declared`, and
`nonconforming_headings`. Its four existing sub-checks keep their messages;
`issue_count` compares against `blocks.len()`, which is now the count of
conforming outlines rather than of `###` lines.

`check_fc17` is new. For each block, each entry in `unresolved_dependencies`
produces one error-level finding naming the outline key, the token, and the
accepted forms. `FC17` registers in `is_known_check_code` and stays out of
`is_intrinsic_notice`, which is what makes it an error; it takes no
`posture_class` entry, so it is enforced in both draft and ready posture.

`check_l06` reads `acceptance_criteria` off the blocks. Its own logic is
untouched.

### The extraction consumer

`process_single_pr` loses its parsing loop and keeps everything else. It
resolves the binary, calls the subcommand, and reads the envelope:

1. Resolve `SHIRABE_BIN` by the ladder from Decision 5. A missing binary is
   `die_input` with a message naming the three ways to supply one.
2. Run `"$SHIRABE_BIN" plan outlines -- "$file"`. A non-zero exit is
   `die_input` carrying the binary's stderr.
3. Refuse when the envelope reports any `unresolved_dependencies`, with
   `die_schema` naming each offending outline and token. This is the PRD's R8
   and it fires before any task entry is built.
4. Refuse when `outlines` is empty, with the message the script emits today,
   which is what keeps the heading mismatch failing closed.
5. Build names, handle collisions, add file-ownership edges, and assemble the
   task entries exactly as now, reading `waits_on` numbers from the envelope
   and mapping them through the number-to-name table it already builds.

Nothing downstream of step 5 changes, which is why the koto task-entry
contract and the 54 test cases are untouched.

### Test-harness and CI shape

`plan-to-tasks_test.sh` gains a setup step that builds the release binary and
exports `SHIRABE_BIN`, copied from `run-cascade_test.sh`, which already does
this. No test case changes — the preamble is harness, not a case, and the
distinction is worth stating because the PRD's R12 forbids editing a case.

`check-plan-scripts.yml` needs its `paths:` filter widened to include
`crates/**`. Without that, a change to the Rust parser does not run the bash
suite that now depends on it, which would reintroduce the drift this design
removes — in CI configuration rather than in code, but with the same effect.

## Implementation Approach

Five steps, ordered by what has to exist before what.

**Step 1 — the walk and the record.** Replace `parse_issue_outlines` with the
`OutlineSection` walk, retire `parse_outline_acs`, and move `check_l06` onto
the block-carried entries. FC14 moves to the new field names with its messages
unchanged. This step is behavior-preserving for L06 and behavior-changing for
FC14 only in the ways the PRD names.

**Step 2 — FC17.** Add the check, register the code, and wire it into the Plan
arm of `validate_file`. Independent of step 3 and after step 1, since it reads
`unresolved_dependencies`.

**Step 3 — the CLI subcommand.** The `plan` group, the `outlines` subcommand,
and the envelope. After step 1, since it serializes the record.

**Step 4 — the extractor.** Binary resolution, the call, the two refusals, and
the removal of the parsing loop. After step 3, since it consumes the envelope.

**Step 5 — contract and CI.** Update `plan-to-tasks-contract.md` to name the
single implementation and the subcommand, and widen the workflow's `paths:`
filter. Last, because it documents what the earlier steps built.

Verification runs at each step: `cargo test --workspace`, the bash suite, and
a whole-corpus validation diff against the baseline captured before step 1.
The diff is expected to differ only in the ways the PRD's Known Limitations
enumerates.

## Security Considerations

**Path handling at the new CLI boundary.** The subcommand takes a file path
and reads it. It writes nothing, creates nothing, and follows no reference out
of the document, so the surface is a read of a caller-named path — the same
surface `validate` already has, with the same answer: the caller chose the
path, and the command has no privilege the caller lacks.

**Shell interpolation in the extractor.** `plan-to-tasks.sh` passes the PLAN
path to the binary. It is quoted and passed after `--`, so a path beginning
with a dash or containing a metacharacter cannot become a flag or a second
command. This matters more after the change than before, because before the
change the path only ever reached a `read` redirect and now it reaches an
`exec`.

**JSON from the binary into the shell.** The envelope is parsed with `jq` and
its values are assigned to shell variables, never evaluated. Two of those
values originate in the document and can carry arbitrary text: the outline
title and the `**Files**:` tokens. Titles already flow into `slugify`, which
reduces them to `[a-z0-9-]`, and the result is checked against the R9 name
regex before it is used. File tokens are already word-split by the existing
loop, which is pre-existing behavior this design does not change and does not
worsen; the tokens are compared and stored, never executed.

**Denial of service through a hostile document.** The walk is a single linear
pass with no backtracking and no recursion. Dependency resolution is linear in
tokens against a set of block numbers. A large or adversarial document costs
time proportional to its size, which is the same bound the current parsers
have.

**No new trust boundary.** The binary and the script ship in the same plugin
and run as the same user against the same working tree. The change moves a
computation across a process boundary that already existed for `validate`,
`transition`, and `finalize-chain`, and introduces no network access, no
credential, and no elevation.

**Fail-closed on a missing binary.** Decision 5C is a security-relevant
rejection as much as a correctness one: a silent fallback parser would be code
that runs only when the primary path is unavailable, which is the condition
under which nobody is testing it.

## Consequences

### Positive

- One parse, so the eight divergences cannot recur and a ninth cannot be
  introduced by editing one reader.
- The fail-open case stops the run at both boundaries, which is the outcome
  the PRD's user stories ask for.
- The validator stops emitting a false positive on the contract's own
  canonical `**Dependencies**: None.` form.
- Dependency resolution follows the numbers the author wrote rather than
  positional index, so a non-consecutively-numbered PLAN resolves correctly.
- FC14's `goal_declared` and `acceptance_criteria_declared` say what the check
  asks, replacing a vector that was never read as a vector.
- Extending the outline format becomes one edit.

### Negative

- `plan-to-tasks.sh` now needs a `shirabe` binary. A checkout with no build
  and no install cannot extract tasks, where before it could. Mitigation: the
  three-way resolution ladder covers the installed, built, and injected cases,
  and the failure message names all three.
- The bash suite gets slower by one release build on a cold cache.
  Mitigation: the build is incremental after the first run, and
  `run-cascade_test.sh` already pays the same cost.
- One fixture becomes an error where it was a notice, and three lose findings
  they should never have had. Mitigation: both directions are enumerated by
  file in the PRD's Known Limitations, so the corpus diff distinguishes them
  from a regression.
- A process boundary sits between the parse and one of its consumers, so a
  version skew between an installed binary and a checked-out script is newly
  possible. Mitigation: the envelope is versioned, and the extractor refuses
  an unrecognized `schema` value rather than reading fields positionally.

### Neutral

- The `#N` dependency form stays unaccepted in single-pr outlines. Accepting
  it would make one fixture pass and would invent edges from GitHub issue
  numbers in documents that have no GitHub issues.
- The non-conforming-heading finding is new but notice-level, so no document
  changes its exit code because of it.
