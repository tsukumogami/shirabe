---
schema: prd/v1
status: Done
upstream: docs/briefs/BRIEF-plan-preflight-one-validator.md
source_issue: 276
problem: |
  Two implementations answer "may a PLAN be built from this", and on the
  question of what status the PLAN's upstream may hold they give opposite
  answers for two of the four statuses a DESIGN can carry. Both are reachable
  in CI on the same pull request. Separately, `shirabe validate` exits 0 for
  inputs it never examined, so "validation passed" means either "checked and
  fine" or "skipped, could not tell what this was" with nothing to tell them
  apart.
goals: |
  One implementation answers the upstream question, its rule is written down
  with the reasoning that chose it, and its success verdict means the document
  was checked. An automated caller that reads only the exit code can tell a
  clean pass from a declined input.
motivating_context: |
  The two defects have to be fixed in one order. The bash script is the only
  thing today that fails a PLAN whose `schema:` is missing or wrong, and it is
  the only thing catching that because the CLI goes quiet on exactly those
  inputs. Removing the duplicate before closing the silence would open a hole
  rather than close one.
---

# PRD: One validator for whether a PLAN may be built from

## Status

Done

Requirements for issues #276 and #285, written from
`docs/briefs/BRIEF-plan-preflight-one-validator.md`. The two framing questions
that brief deferred are settled below under Decisions and Trade-offs.

## Problem Statement

A PLAN document is checked twice before anything is built from it, by two
implementations that do not know about each other.

`skills/plan/scripts/validate-plan.sh` is a 298-line bash pre-flight validator
that predates the CLI. `shirabe validate` is the Rust validator whose own design
document, `docs/designs/current/DESIGN-gha-doc-validation.md`, names the script
as the thing it was replacing — and then deliberately leaves the upstream-status
check with it as a scoped-out v1 cut, expecting a later revision to return. The
gap has since been filled from the other side by the lifecycle check, and the
script was never retired.

The two overlap on nearly everything: frontmatter fields, whether the `upstream:`
target exists on disk, whether git tracks it. On the one rule both own — what
status a PLAN's upstream may be at — they contradict each other in both
directions. The script accepts `Accepted` and rejects `Current`; the lifecycle
check rejects `Accepted` and accepts `Current`. `check-plan-docs.yml` runs the
script over every changed PLAN and `lifecycle.yml` runs the lifecycle check over
the tree, so both verdicts are reachable on one pull request and an author's
answer depends on which one fires.

The script is also not a consistent second opinion. It is a strict subset on
frontmatter — it misses `status` and `milestone`, which the CLI catches — while
being the only side that hard-fails on `schema`. That last asymmetry is the one
that makes the ordering load-bearing.

`shirabe validate` reports success for two classes of input it never examined.
A `--lifecycle` root that carries no `docs/` beneath it indexes zero documents
and exits 0, reporting a clean tree it never opened; two baseline measurements in
an earlier investigation were false negatives for exactly this reason. And a
document whose filename prefix routes it to a format, but whose `schema:` field
is missing or holds an unsupported value, produces a notice and exits 0. A notice
is not enough: the exit code is the surface CI and every calling skill branch on,
and `validate-docs.yml` documents that contract explicitly — it "reads the exit
code as a zero/non-zero pass-fail gate".

So the script cannot simply be deleted. It is the only thing failing a PLAN whose
`schema:` is missing or wrong, and it holds that job precisely because the CLI
declines those inputs silently.

## Goals

- One implementation answers "may a PLAN name this upstream". The other is gone,
  along with its test suite and its CI wiring.
- The chosen upstream-status rule is recorded with the reasoning that chose it,
  and the corpus effect of choosing it is named before the diff is taken, so an
  intended behavior change is never read as a regression.
- `shirabe validate` distinguishes "checked and clean" from "declined to check"
  on the exit code, without claiming that a document it declined to check is
  defective.
- The refusals only the script has — an `upstream:` that is a symlink, and one
  that resolves outside the repository — survive the deletion.
- The scope of the change stays inside the script's own surface. Nothing about
  the CLI's upstream checking widens beyond what absorbing the script requires.

## User Stories

- As a planning author, I want one pre-flight verdict on my PLAN, so that I fix
  the thing that is actually wrong instead of reconciling two tools that disagree
  about which status my upstream should hold.

- As a planning author whose PLAN omits its `schema:` line, I want the validator
  to tell me it did not check the document, so that I do not read a green result
  as evidence the document is well-formed.

- As an operator running the whole-tree lifecycle check, I want a run that
  indexed nothing to say so, so that a mistyped root does not read as a clean
  corpus.

- As a maintainer meeting a verdict that contradicts what the old script said, I
  want the rule's reasoning recorded in a durable document, so that I can find
  out why it is the rule rather than re-deriving the argument.

- As a CI consumer that branches only on the exit code, I want the declined-input
  signal to reach me through that surface, so that I do not need to parse output
  to learn the run was incomplete.

## Requirements

### Functional

**R1.** `shirabe validate` SHALL report a run in which at least one input was
accepted but not checked with an exit status distinct from both a clean run and a
run carrying violations.

**R2.** A document whose format was detected from its filename prefix, and whose
`schema:` field is absent, SHALL be reported under R1 rather than as a clean pass.

**R3.** A document whose format was detected from its filename prefix, and whose
`schema:` field holds a value outside the supported range for that format, SHALL
be reported under R1 rather than as a clean pass.

**R4.** A `--lifecycle` invocation whose root resolves to a location under which
no artifact directory exists, and which therefore indexes zero documents, SHALL
fail as a tool error naming the root and what was expected there. It SHALL NOT
report a clean tree.

**R5.** The JSON envelope SHALL carry, for each input reported under R1, an entry
naming the input and the reason it was not checked, so a caller that reads the
envelope learns which inputs were skipped and why.

**R6.** Where more than one outcome applies to a single run, the reported status
SHALL follow a fixed precedence: a tool error outranks violations, violations
outrank an incomplete run, and an incomplete run outranks a clean one.

**R7.** `shirabe validate` SHALL refuse an `upstream:` entry whose resolved
target is a symbolic link, naming the entry and the reason.

**R8.** `shirabe validate` SHALL refuse an `upstream:` entry whose canonical path
resolves outside the repository working tree, naming the entry and the resolved
location.

**R9.** Exactly one implementation SHALL answer "may a PLAN name this upstream".
`skills/plan/scripts/validate-plan.sh` and its test suite
`skills/plan/scripts/validate-plan_test.sh` SHALL be removed.

**R10.** `.github/workflows/check-plan-docs.yml` SHALL invoke the surviving
implementation rather than the removed script.

**R11.** `.github/workflows/check-plan-scripts.yml` SHALL no longer reference the
removed script or its test suite, and the bash floor runner under `scripts/`
SHALL no longer name them.

**R12.** `/plan`'s phase 7 pre-flight step SHALL invoke the surviving
implementation rather than the removed script, and its prose SHALL describe what
that implementation checks rather than what the script checked.

**R13.** The upstream-status rule the surviving implementation enforces SHALL be
recorded in a durable document together with the reasoning that selected it over
the alternative, and the corpus effect of the selection.

### Non-functional

**R14.** No existing test SHALL be modified to accommodate the change. A test
that cannot pass unmodified is a finding to report, not a file to edit.

**R15.** The change SHALL leave `cargo fmt --check` clean, which CI gates.

**R16.** The remaining shell suites SHALL pass both on Linux and under the bash
3.2 floor, checkable through the local floor runner at
`scripts/check-bash-floor.sh`.

**R17.** Whole-tree validation SHALL be captured before the change and diffed
after, and every difference SHALL be one named in advance under Decisions and
Trade-offs.

**R18.** `shirabe validate --lifecycle . --mode=draft` SHALL exit 0 from the
repository root after the change.

## Acceptance Criteria

- [ ] Running `shirabe validate` on a `PLAN-*.md` with no `schema:` field exits
      with the incomplete status, not 0.
- [ ] Running `shirabe validate` on a `PLAN-*.md` whose `schema:` is `plan/v2`
      exits with the incomplete status, not 0.
- [ ] Running `shirabe validate --lifecycle docs` from the repository root fails
      as a tool error naming the root, rather than reporting a clean tree.
- [ ] Running `shirabe validate --lifecycle .` from the repository root indexes
      the corpus and exits 0 under `--mode=draft`.
- [ ] A run carrying both a violation and a skipped input reports violations, per
      the precedence in R6.
- [ ] The JSON envelope for a run with a skipped input names that input and the
      reason it was skipped.
- [ ] A PLAN whose `upstream:` entry is a symlink is refused, with the entry
      named in the message.
- [ ] A PLAN whose `upstream:` entry resolves outside the working tree is
      refused, with the resolved location named in the message.
- [ ] `skills/plan/scripts/validate-plan.sh` and
      `skills/plan/scripts/validate-plan_test.sh` are absent from the tree, and
      no file in the repository references either path.
- [ ] `check-plan-docs.yml` runs the surviving implementation over each changed
      PLAN and fails the job when it reports a violation.
- [ ] `/plan` phase 7 names the surviving implementation, and its prose describes
      that implementation's checks.
- [ ] The chosen upstream-status rule and its reasoning are recorded in
      `docs/designs/current/DESIGN-plan-preflight-one-validator.md`.
- [ ] `cargo test --workspace` passes with no existing test file modified.
- [ ] `cargo fmt --check` passes.
- [ ] `scripts/check-bash-floor.sh` passes for every remaining suite it covers.
- [ ] The before/after whole-tree validation diff contains only differences named
      under Decisions and Trade-offs.

## Out of Scope

- **Repairing the corpus the schema change surfaces.** Thirty-two committed
  documents carry no `schema:` field. Giving them one exposes 22 further content
  defects underneath — measured, not estimated. Both the field additions and the
  defects are follow-up work.
- **Issue #298**, the single brief carrying an illegal upstream edge. A one-line
  documentation fix that belongs in its own change.
- **Issue #265** (shape-gating) and the prose-reference-staleness work. Same
  crate, unrelated defects, and a chain already planned against those files.
- **Fixing the tooling defects this work routes around.** A known-open orchestrator
  defect is worked around rather than closed.
- **Widening the CLI's upstream checks beyond the script's own surface.** The
  script checked existence, git tracking, symlink-ness, tree containment, and
  status. Nothing beyond that set is added.
- **Rewriting any other shell script.** `plan-to-tasks.sh` in particular is
  untouched.

## Decisions and Trade-offs

### The declined-input signal is a distinct exit status, not a flag

The BRIEF deferred which surface carries the signal. Three were live: a distinct
exit code, a field in the JSON envelope alone, and a strictness flag callers opt
into.

The envelope alone fails the one constraint the brief attached to the question —
the signal has to reach a caller that reads only the exit code, and
`validate-docs.yml` says in its own comments that it does exactly that. A
strictness flag fails a different way: it leaves the default behavior silent,
which is the defect, and makes the fix conditional on every caller remembering to
opt in.

So: a distinct exit status for an incomplete run, with the envelope entry of R5
carried alongside it for diagnosis rather than instead of it. The exit status is
the contract; the envelope is the detail.

The cost is that the incomplete status is a fourth value in an exit-code ladder
that had three, and every consumer documenting the ladder has to learn it. That
is a real cost and it is paid once.

### The skip is reported as incomplete, not as a violation

Promoting the schema skip to an ordinary content violation was the simpler
change and was rejected on evidence. Thirty-two committed documents carry no
`schema:` field; treating the skip as a violation would assert those documents
are defective, which is not what is known about them — what is known is that
they were never checked. Reporting them as incomplete says the true thing.

It also bounds the change. Adding the field to those 32 documents surfaces 22
further errors (the tree goes from 7 to 29), and repairing those is a different
project that this change explicitly does not start.

### The upstream-status rule is the lifecycle model's, and the script's is retired

The two rules disagree on `Accepted` and on `Current`, and one has to go.

The lifecycle model's rule is the correct one, for a reason about what each
status means rather than about which implementation is newer. `/plan` transitions
the upstream DESIGN from `Accepted` to `Planned` as part of authoring the PLAN.
So a committed PLAN naming a DESIGN still at `Accepted` is evidence that the
transition never ran — the chain is in a state it should not be in, and the
script was passing it. In the other direction, the script's refusal of `Current`
has no basis in the model as it now stands: a single-pr chain mid-PR legitimately
holds its DESIGN at `Planned` or at `Current`, and the script rejects the second
only because it was written before promotion to `Current` existed.

**Corpus effect, named in advance.** One PLAN document exists in the tree,
`docs/plans/PLAN-work-on-friction-fixes.md`, and it carries no `upstream:` field
at all. So no committed document changes verdict under the new rule, and the
before/after whole-tree diff shows nothing from this decision. The effect lands
entirely on PLANs authored after this change — including the one this chain
produces, whose upstream DESIGN sits at `Planned` and passes under both rules.

That the measured effect is empty does not make the decision cosmetic. It means
the behavior change is being made at the cheapest moment available, before a
corpus exists to migrate.

### The two script-only refusals survive by extending the existing check

The BRIEF deferred whether the symlink and tree-containment refusals are
preserved or recorded as removed. They are preserved, in the CLI's existing
upstream-resolution check rather than in a new one.

The reason to keep them is the reason the script had them: the value reaches a
committed frontmatter field. A symlinked upstream resolves differently for
different readers, and one resolving outside the tree names something no other
clone has. Neither is caught anywhere else.

The reason to put them in the existing check rather than a new one is that the
existing check already resolves the entry, already walks every written shape of
the field through one normalizer, and already reports under one code. A second
check would give the same entry two places to be refused from.

**Corpus effect, named in advance.** No file under `docs/` is a symlink and no
`upstream:` entry resolves outside the working tree, so the before/after diff
shows nothing from this decision either.

### The ordering is fixed and is not an implementation preference

Closing the silence comes first; removing the duplicate comes second. The script
is the only thing failing a PLAN with a missing or wrong `schema:`, and it holds
that job because the CLI declines those inputs quietly. Reversing the order
leaves a window in which no implementation catches the case. The requirements
above are numbered so that R1 through R8 are satisfiable without R9 through R12,
and R9 through R12 are not attempted before R1 through R3 hold.

## Known Limitations

- **The incomplete status turns green runs red for 32 documents.** Any pull
  request whose changed-file set includes one of the schema-less documents moves
  from exit 0 to the incomplete status, and `validate-docs.yml` treats any
  non-zero as failure. This is the forcing function the change exists to create,
  and it is the largest single consequence of shipping it.

- **A fourth exit value is a compatibility surface.** Consumers that treat
  "non-zero" as failure are unaffected. Consumers that switch on specific values
  need updating, and the ones inside this repository are updated here; any
  outside it are not visible from here.

- **The upstream-status rule is enforced by the lifecycle chain check, which is a
  different invocation from the per-file one.** A caller wanting both answers runs
  both. Unifying the two invocations is not attempted.
