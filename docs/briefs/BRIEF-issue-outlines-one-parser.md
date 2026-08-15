---
schema: brief/v1
status: Done
problem: |
  The `## Issue Outlines` section of a PLAN has three independent readers
  with different rules. The lenient one gates validation; the strict one
  decides what gets built. A PLAN can validate clean and then execute with
  every declared ordering constraint silently discarded.
outcome: |
  An author whose PLAN validates clean can trust that the dependency graph
  the document declares is the graph the orchestrator runs, because one
  implementation answers both questions. Where a declaration cannot be
  read, the author is told before anything executes.
motivating_context: |
  Caught while executing PLAN-chain-cardinality: the document validated at
  exit 0 with four ordering constraints declared, two of which took two
  rounds of design review to establish, and the extractor produced a task
  list with every `waits_on` empty. Nothing errored. It was found only by
  dumping the task graph and reading it by hand.
---

# BRIEF: One parser for the Issue Outlines section

## Status

Done

Framing for issue #275. The downstream PRD owns the requirements; this
brief stops at the problem, the outcome, the journeys that exercise it, and
where the boundary sits.

Two framing details are deferred to the PRD's Decisions and Trade-offs
section rather than settled here: where the single parse lives and by what
surface the shell extractor reaches it, and whether an unresolvable
dependency is an error at validation time or a refusal at extraction time.
Both were carried as Open Questions through the Draft and are recorded here
because Accepted status forbids that section.

## Problem Statement

A single-pr PLAN carries its work in a `## Issue Outlines` section: one
`### Issue N: Title` block per unit of work, each declaring a goal,
acceptance criteria, and the outlines it waits on. Two consumers read that
section for entirely different purposes. `shirabe validate` reads it to
decide whether the document is well-formed. `plan-to-tasks.sh` reads it to
decide what the orchestrator builds and in what order.

They do not share a reader. The validator has `parse_issue_outlines` in
`crates/shirabe-validate/src/table.rs`, written deliberately lenient — its
own doc comment says it is total over arbitrary input, so callers can
describe each defect rather than refuse the document. That is the right
temperament for a validator. The extractor has a line-by-line bash state
machine in `skills/plan/scripts/plan-to-tasks.sh` that matches
`### Issue N: <Title>` exactly and resolves dependencies written as
`Issue N` or `<<ISSUE:N>>`, and nothing else. That is the right temperament
for something that decides what gets built. Neither is wrong on its own.
The arrangement is wrong: the lenient reader is the gate in front of the
strict one, so the document that passes is not the document that gets read.

The two disagreements this produces are not equally bad.

A heading written as `### 4. Title` instead of `### Issue 4: Title`
validates clean — the validator never inspects the heading's shape — and
then extracts to zero tasks and exits with an error naming the empty
section. Annoying, and safe.

A dependency written as `**Dependencies**: 3` instead of `Issue 3`
validates at exit 0, because the validator reports an unresolved dependency
token as a notice rather than an error. The extractor then emits a complete
task list with every `waits_on` empty. The orchestrator materializes every
outline as unblocked and runs them in whatever order it likes. Nothing
errors, nothing warns above notice level, and the ordering the author wrote
down is gone. This is the failure that motivates the brief: it fails open,
and it fails silently.

The section is not under-specified. `plan-to-tasks-contract.md` already
states the heading shape and both dependency forms correctly. The contract
is right and the validator does not enforce it, because the validator has
its own parser.

Reading the code turns up a third reader the issue did not name.
`parse_outline_acs`, in the same file as the first, walks the same section
again with its own section-locating loop and its own field-label list to
feed check L06. So the section is parsed three times, and two of those
parses sit a few dozen lines apart in one file and still had to be written
twice.

That count is the real shape of the problem. Two implementations that
disagree can be made to agree by hand; that is what these were, and they
drifted anyway. Three of them, one of which nobody had noticed, is evidence
that hand-agreement is not a stable arrangement here.

## User Outcome

A PLAN author writes a document, runs `shirabe validate`, sees it pass, and
can act on that result. Passing means the dependency graph the document
declares is the graph the orchestrator will run — not because two
implementations were checked against each other, but because one
implementation answered both questions.

Where a declaration cannot be resolved, the author finds out before
anything executes, at a severity that stops the run rather than scrolling
past in a notice. The author never has to dump the extracted task graph and
read it by hand to find out whether the ordering survived, which is how the
motivating instance was actually caught.

A maintainer adding a field to the outline format edits one parser and both
consumers see the field. Today the same edit is three edits in two
languages, and forgetting one of them produces exactly the silent
disagreement this brief is about.

## User Journeys

### A PLAN author writes a dependency the extractor cannot resolve

An author drafting a single-pr PLAN writes `**Dependencies**: 3` — reading
naturally, meaning the third outline — and runs `shirabe validate` before
committing. Today the command exits 0 and prints a notice among however
many other notices the document produced, and the author reasonably reads
exit 0 as "this is fine." The outcome shape: the author is told the
dependency does not resolve, at a severity that matches what will happen if
they ignore it, and the run does not reach the orchestrator with an
ordering the document did not declare.

### A PLAN author writes a heading the extractor cannot parse

An author writes `### 4. Rework the resolver` instead of
`### Issue 4: Rework the resolver`, validates clean, and hands the PLAN to
`/execute`. Today the extractor finds no outlines and exits with a loud
error. The outcome shape: this keeps failing closed. It is the one behavior
here that already works, and the point of naming it as a journey is that
the fix must not quietly convert it into something more permissive.

### A maintainer adds a field to the outline format

A maintainer wants outlines to carry a new annotation — the way `**Type**:`
and `**Files**:` were added for the work-on-efficiency change. Today
`**Type**:` and `**Files**:` are read by the bash extractor, named by one
Rust parser only as things that terminate an acceptance-criteria block, and
unknown to the other. The outcome shape: the maintainer adds the field to
one parser, and validation and extraction both see it or both do not.

### An operator runs a PLAN through the orchestrator

Someone runs `/execute` against a PLAN that validated clean. The outcome
shape: either the task graph matches the document's declared edges, or the
extraction refuses. There is no third result where a graph is produced that
the document did not describe.

## Scope Boundary

### In

- One implementation that parses `## Issue Outlines`, with validation and
  task extraction as its two consumers. No second parse of that section
  survives anywhere in the tree, including the two that sit in the same
  Rust file today.
- A decided answer for the unresolvable-dependency case: either validation
  treats it as an error, or extraction refuses to emit an edgeless task
  set. The brief does not pick; it requires that one be picked and the
  reason recorded, because the two failure modes carry different severities
  and treating them identically is what produced the defect.
- Preserving the heading-shape mismatch as a closed failure.
- Whatever contract text has to move so the single parser is the documented
  one. `plan-to-tasks-contract.md` is already correct about the shapes; if
  the parse relocates, the contract says where it lives.

### Out

- The `## Implementation Issues` section, which multi-pr and coordinated
  PLANs use instead. It has its own reader and its own table parser and is
  not implicated in this defect.
- Changing what `/plan` authors. The shapes it emits are the correct ones.
  This brief is about who reads them.
- The four filed tooling defects hit while working in this area — the
  `/execute` worktree-gate variable expansion, the `koto context set` call
  that does not exist, `shirabe validate` exiting 0 on inputs it declines
  to check, and the whole-tree lifecycle CI workflow failing at startup.
  Each is filed separately and fixing any of them here would collide with
  other work.
- Broadening the extractor to accept shapes it rejects today. Making the
  two readers agree by loosening the strict one is the same
  agree-by-hand arrangement in a different direction.

## References

- `crates/shirabe-validate/src/table.rs` — `parse_issue_outlines` and
  `parse_outline_acs`, the two Rust readers.
- `crates/shirabe-validate/src/checks.rs` — FC14, the validation consumer.
- `skills/plan/scripts/plan-to-tasks.sh` — the extraction consumer.
- `skills/plan/references/plan-to-tasks-contract.md` — the already-correct
  statement of both shapes.
- `crates/shirabe-validate/src/upstream.rs` — the precedent: three readers
  of the `upstream:` field routed through one normalization helper so
  agreement became structural.
