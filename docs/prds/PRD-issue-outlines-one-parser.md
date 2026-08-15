---
schema: prd/v1
status: Accepted
upstream: docs/briefs/BRIEF-issue-outlines-one-parser.md
source_issue: 275
problem: |
  The `## Issue Outlines` section of a single-pr PLAN is read by three
  independent parsers that disagree in eight identified ways. The lenient
  Rust reader gates validation; the strict bash reader decides what gets
  built. A PLAN whose dependency line reads `**Dependencies**: 3` validates
  at exit 0 and extracts to a complete task list with every `waits_on`
  empty, discarding the ordering its author declared with nothing reported
  above notice level.
goals: |
  One implementation parses the section and both consumers read its result,
  so agreement is a property of there being one reader rather than something
  maintainers verify by hand. A declaration the parser cannot resolve stops
  the work at both the validation boundary and the extraction boundary
  rather than passing through either.
motivating_context: |
  Found while executing PLAN-chain-cardinality. Four ordering constraints
  were declared, two of them settled over two rounds of design review, and
  all four would have been discarded. The document validated at exit 0. It
  was caught only by dumping the extracted task graph and reading it by hand
  before starting execution.
---

# PRD: One parser for the Issue Outlines section

## Status

Accepted

## Problem Statement

A single-pr PLAN carries its units of work in a `## Issue Outlines` section:
one `### Issue N: Title` block each, declaring a goal, acceptance criteria,
and the outlines it waits on. Two consumers read that section for different
purposes. `shirabe validate` reads it to say whether the document is
well-formed. `skills/plan/scripts/plan-to-tasks.sh` reads it to decide what
the orchestrator builds and in what order.

They do not share a reader, and there are in fact three:
`parse_issue_outlines` and `parse_outline_acs` in
`crates/shirabe-validate/src/table.rs`, and the bash state machine in
`plan-to-tasks.sh`. The first is deliberately lenient — its doc comment
declares it total over arbitrary input so FC14 can describe each defect
rather than refuse the document — and the third is deliberately strict,
because it decides what gets built. Each temperament is right for its
consumer. The arrangement is not: the lenient reader gates the strict one,
so the document that passes validation is not the document that gets read.

Reading the three against each other turns up eight disagreements. Two were
named in the filed issue; the other six were found during this PRD's research
and are recorded in full in the design's inputs. The ones that matter for
requirements:

- A dependency written as a bare number, or in any shape the extractor does
  not recognize, is a **notice** to the validator and **nothing at all** to
  the extractor. Exit 0, then an edgeless task graph. This fails open and
  silently, and it is why the issue was filed.
- A heading written as `### 4. Title` is an outline to the validator and not
  an outline to the extractor. Exit 0, then zero tasks and a loud refusal.
  This fails closed, and must keep doing so.
- `**Dependencies**: None.` — with the trailing period the contract's own
  example uses — is handled correctly by the extractor and reported by the
  validator as an unresolved dependency. The validator emits a false positive
  on the canonical form, live today on three fixtures.
- An outline whose dependencies are written under a `### Dependencies`
  sub-heading is understood by the extractor and read by the validator as a
  second outline named `Dependencies` missing every required field.
- The validator resolves dependency tokens against outlines' *positional
  index*, not the issue number in the heading, so a PLAN numbered `Issue 2`
  and `Issue 5` resolves against `Issue 1` and `Issue 2`.

The section is not under-specified. `plan-to-tasks-contract.md` already
states the heading shape and both dependency forms correctly. The contract is
right; the validator does not enforce it, because the validator has its own
parser. That is why writing the rules down more carefully is not the fix, and
why teaching one parser to check what the other checks is not either: these
two were written to agree and drifted anyway, and a third one nobody had
noticed had drifted further.

## Goals

- A PLAN that validates clean extracts to the dependency graph its author
  declared. Where that cannot be guaranteed, the author is told before
  anything runs, at a severity that stops the run.
- One implementation reads the section. Adding a field to the outline format
  is one edit, and both consumers see it or neither does.
- The heading-shape mismatch keeps failing closed. Nothing here converts a
  loud refusal into a permissive parse.
- No document currently in the corpus silently changes what validation says
  about it. Where the fix does change a result — because the current result
  is wrong — the change is named in advance rather than discovered in a diff.

## User Stories

**As a PLAN author**, I want `shirabe validate` exiting 0 to mean my
declared ordering will be honored, so that I do not have to dump the
extracted task graph and read it by hand to find out.

**As a PLAN author**, I want a dependency reference the tooling cannot
resolve to stop me at validation time, so that I fix a typo instead of
discovering three merged PRs later that the ordering never applied.

**As an operator running `/execute`**, I want extraction to refuse rather
than emit a task graph the document did not describe, so that a PLAN that
reached the orchestrator without passing validation still cannot silently
lose its edges.

**As a maintainer extending the outline format**, I want to add a field in
one place and have validation and extraction both see it, so that a
half-applied change cannot produce the silent disagreement this PRD is
about.

## Requirements

### Functional

**R1 — One parse.** Exactly one implementation in the tree parses the
`## Issue Outlines` section. After this change, no second walk of that
section exists in any language, including the two that sit in
`crates/shirabe-validate/src/table.rs` today.

**R2 — Both consumers read that parse.** Validation (`FC14` and `L06`) and
task extraction (`plan-to-tasks.sh`'s single-pr path) each obtain the
section's contents from the single implementation. Neither re-derives any
part of it: not the section bounds, not the block boundaries, not the field
labels, not the dependency resolution.

**R3 — The parse resolves dependencies.** The single implementation reports,
per outline, the set of sibling outlines that outline waits on, resolved to
issue numbers, plus the set of dependency tokens it could not resolve. A
consumer never sees raw dependency text it has to interpret.

**R4 — The parse reports heading conformance.** The single implementation
reports, per block, whether the block's heading matches the canonical
`### Issue <N>: <Title>` shape, and the issue number and title when it does.
A non-canonical `###` heading inside the section is reported as a
non-conforming block rather than silently accepted or silently dropped.

**R5 — Shapes the contract already declares are accepted.** The single
implementation accepts every form
`skills/plan/references/plan-to-tasks-contract.md` and the current extractor
already accepts: `Issue N` and `<<ISSUE:N>>` dependency references; a
`Blocked by` prefix; a trailing period on the value; the literal `None` with
or without that period; `**Dependencies**:` and `**Dependencies:**`; and a
`### Dependencies` sub-heading whose body carries the references. This is a
requirement about not regressing the extractor's current tolerance, not
about widening it.

**R6 — Nothing is newly accepted.** No dependency shape or heading shape the
current extractor rejects becomes acceptable. Making the readers agree by
loosening the strict one is out of bounds; the strict reader's behavior is
the target both consumers converge on.

**R7 — An unresolvable dependency is an error at validation.** A single-pr
PLAN with a dependency reference that resolves to no sibling outline
produces an error-severity finding, so `shirabe validate` exits non-zero.
This is a change from today's notice.

**R8 — An unresolvable dependency is a refusal at extraction.** The
extractor exits non-zero with a message naming the offending outline and
token rather than emitting a task entry whose `waits_on` omits the edge.
R7 and R8 are both required; the reasoning is recorded under Decisions and
Trade-offs.

**R9 — The heading mismatch keeps failing closed.** A `## Issue Outlines`
section containing no canonically-shaped heading extracts to no tasks and
the extractor exits non-zero, as it does today.

**R10 — The `None.` false positive is removed.** `**Dependencies**: None.`
resolves as an intentional absence of dependencies in validation as it
already does in extraction, and produces no finding.

**R11 — The contract says where the parse lives.**
`skills/plan/references/plan-to-tasks-contract.md` is updated to name the
single implementation and the surface the extractor reaches it through. The
shapes it already documents do not change.

### Non-functional

**R12 — No existing test is modified.** `cargo test --workspace` and the
bash test suite at `skills/plan/scripts/plan-to-tasks_test.sh` both pass
with no pre-existing test case altered. A test that must change is reported
as a finding for a human to rule on, not edited quietly. The precedent is
#271, which held the same bar.

**R13 — Corpus results change only where named.** Validation output over
every tracked document is compared against a baseline captured before the
change. Any difference is one of the changes named in advance under Known
Limitations, or it is a regression.

**R14 — The extractor keeps working without a network or a repo.**
`plan-to-tasks.sh` runs today against a file path with no GitHub access and
no git state. Whatever surface it uses to reach the parse keeps that true.

**R15 — The CLI-surface rule is respected.** No subcommand renders or
creates an artifact body. The reasoning that places deterministic parsing
and feedback in the CLI is stated in the design rather than assumed.

## Acceptance Criteria

- [ ] Grepping non-test, non-fixture, non-documentation sources for the
      literal `## Issue Outlines` finds it in exactly one function. Every
      other reference is a call into that function.
- [ ] A single-pr PLAN with `**Dependencies**: 3` produces an error-severity
      validation finding naming the outline and the token, and
      `shirabe validate` exits non-zero on it.
- [ ] The same PLAN causes `plan-to-tasks.sh` to exit non-zero rather than
      emit a task list, and the message names the outline and the token.
- [ ] A single-pr PLAN whose headings read `### 4. Title` extracts to no
      tasks and the extractor exits non-zero.
- [ ] A single-pr PLAN with `**Dependencies**: None.` produces no finding
      and extracts with an empty `waits_on` for that outline.
- [ ] A single-pr PLAN with `**Dependencies**: <<ISSUE:2>>` and one with
      `**Dependencies**: Blocked by Issue 2.` produce the same `waits_on`
      edge.
- [ ] A single-pr PLAN whose dependencies are written under a
      `### Dependencies` sub-heading still produces its edges, and produces
      no phantom outline finding.
- [ ] A single-pr PLAN whose outline headings are numbered non-consecutively
      resolves dependencies against the numbers in the headings.
- [ ] `cargo test --workspace` passes with no pre-existing test modified.
- [ ] `bash skills/plan/scripts/plan-to-tasks_test.sh` passes with no
      pre-existing case modified.
- [ ] The whole-corpus validation diff against the pre-change baseline shows
      only the differences named under Known Limitations.
- [ ] `shirabe validate --lifecycle . --mode=draft` exits 0.
- [ ] This PRD's own downstream PLAN extracts to the task graph it declares,
      demonstrated by dumping the graph and comparing it to the document.

## Decisions and Trade-offs

The BRIEF deferred two questions here. Both are settled below.

### Where the single parse lives, and how the shell reaches it

**Decided:** the parse lives in the Rust `shirabe-validate` crate and the
shell extractor reaches it through a `shirabe` CLI subcommand that emits the
parsed, dependency-resolved outline set as JSON on stdout. The extractor
keeps everything downstream of the parse: slug generation, the `o-` prefix,
the 64-character truncation, collision suffixing, the file-ownership
`waits_on` edges, and the koto task-entry assembly.

**Alternatives considered.**

*Teach FC14 to check what the script checks.* Rejected, and #275 rejects it
by name. It leaves two implementations agreeing by hand, which is the
arrangement that already drifted — twice, since the third reader had drifted
further than either of the two the issue named.

*Move the whole single-pr extraction path into Rust.* Rejected as larger
than the problem. Naming and scheduling policy read nothing from the
document, so moving them buys no agreement; it does put 54 bash test cases
and the koto task-entry contract in the blast radius. The issue's own framing
is that what changes is where the parse lives, not who calls it.

*Generate the bash parser from a shared specification.* Rejected. Codegen for
one section of one document type costs a build step and a generated artifact
in review, for a duplication that a function call removes.

**Why the CLI is the right home rather than the skill.** The repo's rule
forbids a subcommand that renders or creates an artifact body, because
authoring belongs to a skill. Reading an existing document and reporting what
it says is the other half of that rule: deterministic parsing and feedback,
which the rule places in the CLI, alongside `validate` and
`slug-prefix-detect`. `plan-to-tasks.sh` is already a declared stable
sub-operation with a documented contract; it keeps that role and stops
carrying a parser.

### Whether an unresolvable dependency errors at validation or refuses at extraction

**Decided:** both. R7 and R8 are separate requirements and neither is
redundant.

Validation alone is not enough because validation is not a precondition of
extraction. `/execute` invokes `plan-to-tasks.sh` against a PLAN path
directly; nothing in that path requires the document to have been validated
first, and a PLAN authored by hand or carried in from elsewhere reaches the
orchestrator without a validator ever having seen it. An error-only answer
leaves the silent-edge-loss path open on exactly the invocations that skip
the gate.

Extraction alone is not enough because the complaint in the issue is
specifically that the document *validates clean*. A refusal at extraction
time leaves `shirabe validate` still saying exit 0 about a document that
cannot be built, which is the false reassurance that caused the miss.

They also differ in what they protect. The validation error catches the
mistake while the author is still editing the document. The extraction
refusal catches it at the last moment before work starts, on any path,
including paths that never validate. Closing one and calling it done would
leave a reachable route to the failure this PRD exists to remove.

**Trade-off accepted:** promoting the finding to error means a PLAN that
validated clean yesterday can fail today. The corpus survey found exactly one
such instance and it is a genuine defect rather than a false positive; it is
named under Known Limitations.

### Severity is per-check, so the promotion needs its own code

FC14's severity is keyed on the check code, and FC14 covers four structural
sub-checks that stay notice-level. Promoting one sub-check therefore means
giving the unresolvable-dependency finding a code of its own rather than
flipping FC14 wholesale, which would promote missing-`**Goal**:` and the
`issue_count` mismatch along with it and change results across the fixture
corpus. The design picks the code and states where it registers.

## Known Limitations

These are the validation-result changes the fix makes on purpose. Naming them
here is what lets R13's diff distinguish an intended change from a
regression.

**Three fixtures lose a false-positive finding.** The `None.` repair (R10)
removes FC14 `declares unresolved dependency 'None'` findings from
`skills/execute/evals/fixtures/plans/PLAN-diamond-test.md` (two),
`skills/work-on/evals/fixtures/plans/PLAN-diamond-test.md` (two), and
`skills/execute/evals/fixtures/plans/PLAN-legacy-four-column-test.md` (one).
All five are the validator misreading the contract's own canonical form.

**One fixture gains an error.**
`skills/execute/evals/fixtures/plans/PLAN-legacy-four-column-test.md` is
`single-pr` and its second outline declares `Blocked by #1`. `#N` is the
multi-pr table's dependency form; the single-pr contract's forms are
`Issue N` and `<<ISSUE:N>>`, and the extractor drops `#1` silently today.
This is a live instance of the defect sitting in the fixture corpus, so
R7 turns it from a notice into an error. Both files already exit 2 for
unrelated reasons, so no exit code changes.

**Documents under `docs/` are unaffected.** The only PLAN in `docs/` is
`PLAN-work-on-friction-fixes.md`, which is `multi-pr` with an unpopulated
outline section.

**The `#N` form stays unaccepted in single-pr outlines.** Teaching the
single-pr path to read `#N` would make the fixture above pass, and it is
exactly the loosening R6 forbids: the multi-pr form means a GitHub issue
number, and reading it as an outline reference in a document that has no
GitHub issues would invent an edge rather than find one.

## Out of Scope

- The `## Implementation Issues` section that multi-pr and coordinated PLANs
  use. It has its own table parser and is not implicated here.
- What `/plan` authors. The shapes it emits are the correct ones.
- The four filed tooling defects encountered in this area — the `/execute`
  worktree-gate variable expansion, the `koto context set` call that does not
  exist, `shirabe validate` exiting 0 on inputs it declines to check, and the
  whole-tree lifecycle CI workflow failing at startup. Each is filed and
  fixing any here would collide with other work.
- Widening either consumer's tolerance (see R6).
- Rewriting `plan-to-tasks.sh`'s multi-pr or coordinated paths, its naming
  and collision policy, or the koto task-entry contract.
