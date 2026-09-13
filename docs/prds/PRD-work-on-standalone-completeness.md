---
schema: prd/v1
status: In Progress
problem: |
  A single-issue `/work-on` run opens a pull request and stops before the
  change is mergeable. The document-chain cascade is unreachable from it
  entirely, and its other finishing obligations are prose a run may skip rather
  than states a run cannot advance past. Whoever supervises has to know the
  missing steps and say them out loud, which happened three times in two days
  across three repositories.
goals: |
  A single-issue run finishes its own work or stops and names what it could not
  discharge, with the obligations that decide "finished" enforced where a run
  cannot skip them and reachable by a child run that never loads the skill's
  prose. Running a whole plan keeps its current cadence, and the plan entry
  point becomes the only way a plan is run.
absorbed:
  - docs/briefs/BRIEF-work-on-standalone-completeness.md
source_issue: 361
motivating_context: |
  Three dispatched worker sessions ran the single-issue skill standalone on
  2026-09-12 and 2026-09-13. Each ended looking complete and was not. The
  tracking issue attributed this to five capabilities living in the wrong
  skill; an exploration established from the code that two of those five are
  not gaps at all, which is why this PRD's requirements are narrower and
  differently shaped than that issue's acceptance criteria.
---

## Status

In Progress

Absorbed [BRIEF-work-on-standalone-completeness](docs/briefs/BRIEF-work-on-standalone-completeness.md); carried in Absorbed Brief.

## Absorbed Brief

A `/work-on` run invoked on one issue opens a pull request and stops, leaving a
change that looks finished and is not. Whoever supervises has to know what is
missing and say it out loud, every time — which happened three times in two days
across three repositories.

The feature is for the person or agent running a single issue. What is different
for them afterwards is that the run either reaches a genuinely mergeable pull
request on its own, or stops and names the obligation it could not discharge
instead of reaching a terminal state that reads as success. An ordinary bug fix
with no documents behind it finishes without ever mentioning a document chain;
an issue that sits under a design has that chain pulled to its terminal state in
the same run; an orchestrator running a whole plan sees the cadence it sees
today, once per plan; and someone who points the single-issue entry point at a
plan is told where a plan is run now rather than getting a partial result.

The boundary the framing drew holds in this document: in scope are the cascade
becoming reachable including the no-chain case, the prose obligations becoming
gated, where the shared machinery lives, the multi-pr migration, the per-child
suppression signal, and keeping every obligation somewhere a child receives it.
Out of scope are four defects reported alongside this one but caused by
something else — the verification-map gap, the missing staleness script, the
pre-existing terminal-record defect, and panel observability — plus the naming
fossils from the earlier split, and merging the pull request itself.

## Problem Statement

A `/work-on` run invoked on a single issue opens a pull request and stops
there. What it leaves behind looks finished and is not, so the person or
session supervising it has to know the remaining steps and supply them. That
cost was paid three times in two days across three separate repositories: one
run had to be told to open its pull request at all, to put the closing keyword
in the body, and to watch CI; another had to be told that its document chain
needed pulling to its terminal state before the pull request could merge.

Two distinct things are wrong, and they need different fixes.

**The cascade is unreachable, and one half of that is already fixed.** Nothing
in `/work-on` touches the document chain. The cascade script that does this
work takes a plan-shaped document path as its only positional argument and has
no mode that accepts no document, so an ordinary issue with nothing behind it
cannot invoke it at all. That is genuine missing work. The neighbouring case —
a plan that exists but resolves to no upstream chain — already behaves
correctly, committing and pushing just the plan's deletion and reporting that
it skipped; that was fixed recently and is pinned by its own test. Treating
"the cascade does not run for single-issue runs" as one gap would put work on
the half that is already done and under-specify the half that is not.

**The other obligations exist but are unenforced.** `/work-on` has a spine of
states with typed evidence schemas, and four of them carry gates. But the
obligations that decide whether a change is actually finishable — merge and
rebase cleanliness, the closing keyword, pull-request body content beyond the
mechanical check CI already runs, code cleanup, the summary's shape, commit
message convention — live only as prose in reference files. The prose is
delivered: the template's own per-state directives cite those files, so a run
receives the instruction. All three field runs received it and skipped it
anyway. The defect is the absence of anything that would catch the omission,
not the absence of the instruction.

One obligation is worse than unenforced: the design-document diagram update
sits two reference-hops from the template and its own contract permits skipping
it silently, so it is neither delivered reliably nor checked.

Underneath both is a constraint that decides where any fix may be written. A
child run is seeded directly from its compiled template and never loads the
skill's `SKILL.md`, so an obligation written there is unreachable by a child
rather than merely skippable. A fix in the wrong file would pass under direct
invocation and silently never reach a child.

Finally, the same skill is currently the documented way to run a whole class of
plan — multi-pr plans, one issue at a time. That makes the single-issue entry
point responsible for deciding when a plan is finished, which is the plan entry
point's job and which it already has the machinery for.

## Goals

A person or agent running `/work-on` against one issue reaches a genuinely
mergeable pull request without anyone supplying a step from memory. When the
run cannot get there, it stops and names the obligation it could not discharge
rather than reaching a terminal state that reads as success.

The obligations that decide "finished" are enforced at a level a run cannot
skip, and are written where a child run actually receives them.

Running a plan keeps the cadence it has today — the chain is pulled to its
terminal state once per plan, not once per issue — and the plan entry point
becomes the single way a plan is run, whatever its execution mode.

## User Stories

This is developer tooling, so several of these read as use cases rather than
user stories; that is the format the repository's own PRDs use for this kind of
feature.

- As a maintainer fixing a one-off bug with no documents behind it, I want the
  run to finish without mentioning a document chain, so that ordinary issue
  work is not burdened by machinery that has nothing to act on.
- As a maintainer implementing the last issue behind a design, I want the chain
  pulled to its terminal state in the same run, so that a merged change never
  leaves a stale chain behind it.
- As a maintainer whose run cannot finish, I want it to stop and name the
  obligation it could not discharge, so that I can tell an unfinished run from
  a finished one without reconstructing what the skill should have done.
- As an orchestrator running a multi-issue plan, I want each child to do its
  issue and not finalize, so that the chain is pulled once for the plan rather
  than once per issue.
- As someone who reads yesterday's documentation and points the single-issue
  skill at a whole plan, I want to be told where a plan is run now, so that a
  changed route produces a redirect rather than a confusing partial result.
- As a reviewer of this repository, I want the documents that currently state
  the opposite routing to be superseded on the record, so that the corpus does
  not accumulate another document describing a capability that does not exist.

## Requirements

### Functional — cascade reachability

**Terms used below.** A *run* and a *session* are the same materialized thing
seen at two layers: "run" is used throughout the requirements for the unit of
work a person or agent invokes, and "session" where the distinction between a
root invocation and a child dispatched by it is what matters, which is the
workflow layer's own vocabulary. R19 uses "session" for exactly that reason.

*Anchor* means the PLAN that sequences the issue being
worked. It is the only document the cascade can be entered from: the cascade
script takes a plan-shaped path as its sole positional argument. An issue has
an anchor when such a PLAN exists and resolves; it has none when the issue was
filed on its own. "Anchor" never refers to a BRIEF, PRD or DESIGN — those are
reached *through* the anchor, by the cascade's own walk, and never entered
directly.

- **R1.** A single-issue run whose issue has a resolvable document chain SHALL
  pull that chain to its terminal state as part of the same run, before the
  pull request is presented as mergeable.
- **R2.** A single-issue run SHALL determine whether an anchor document exists
  *before* invoking the cascade, and SHALL NOT invoke the cascade when there is
  none. The cascade script accepts a plan-shaped path as its only positional
  argument and has no no-document mode, so "invoke it and let it skip" is not
  available.
- **R3.** A run with no anchor SHALL complete normally and SHALL NOT emit
  cascade-related output. A maintainer fixing an ordinary bug must not learn
  that a cascade step exists.
- **R4.** The existing behaviour for an anchor that resolves to no upstream
  chain SHALL be preserved unchanged: the plan's deletion is committed and
  pushed on its own and the result is reported as skipped. This case is already
  correct and is pinned by an existing test; the requirement is that it is not
  regressed.
- **R5a.** Where the shared cascade machinery lives SHALL be settled by the
  design that precedes implementation and recorded there as an explicit
  decision, rather than fixed incidentally by whoever writes the first caller.
  This PRD settles the constraint on that decision and not the location: the
  chosen location SHALL NOT leave the single-issue skill depending on the plan
  entry point.
  The script lives under the plan entry point's own directory today, so the
  naive reading of "both call one script" would invert the dependency
  direction that this feature's whole shape rests on, and would add a second
  load-bearing cross-skill path of the kind the repository already guards with
  a dedicated assertion.
- **R5.** Both failure shapes the cascade can report — nothing published, and
  partially published-and-pushed — SHALL be handled by the single-issue caller
  identically to how the plan entry point handles them today, including the
  same recovery guidance. Two callers of one script must not disagree about
  what a partial result means.

### Functional — enforcement altitude

- **R6.** Every finishing obligation that resolves to a fact observable from
  `gh` or from git SHALL be enforced by a gate, not stated as prose. The
  closing keyword in the pull request body and merge/rebase cleanliness are in
  this class.
- **R7.** Every finishing obligation that is irreducibly a judgment call SHALL
  be carried as a named, required evidence field on the state that owns it, so
  that omitting it is visible in the run's record rather than silent. Code
  cleanup and the summary's shape are in this class.
- **R7a.** Each such evidence field SHALL be typed to a concrete referent — a
  path, a commit identifier, or the output of a named command — rather than to
  free prose. A field that accepts any string is satisfied by a placeholder,
  which makes the obligation unenforced in substance while appearing enforced
  in the record. Where an obligation genuinely has no concrete referent, it
  SHALL be recorded as advisory under R8 rather than given a prose field.
- **R8.** Each obligation SHALL be classified as **gate-enforced** (R6) or
  **evidence-carried** (R7), and the classifications SHALL be recorded together
  in a classification table committed with the change, one row per obligation
  naming the obligation, its class, and where it is enforced or carried. An
  obligation
  that is neither gated nor carried as evidence is not a requirement of this
  feature and SHALL be dropped or recorded as deliberately advisory.
- **R9.** The design-document diagram update SHALL either be brought within one
  reference-hop of the template and given an evidence field, or be recorded as
  deliberately optional. Its present state — two hops away with a contract
  permitting silent skipping — SHALL NOT persist unexamined.
- **R10.** No obligation introduced by this feature SHALL live only in
  `skills/work-on/SKILL.md`. Every one SHALL be reachable from
  `skills/work-on/koto-templates/work-on.md` — its states, its gates, or its
  per-state prose — so that a child run materialized by the plan entry point
  receives it.

### Functional — cadence and the child signal

- **R11.** A child run dispatched by the plan entry point SHALL NOT pull the
  document chain to its terminal state. Finalization is the plan's, once.
- **R12.** The signal that suppresses child self-finalization SHALL be distinct
  from the existing shared-branch signal. Single-pr children route from pull
  request creation straight to done and never reach CI monitoring, but multi-pr
  children land their own pull requests and do reach it, so the existing
  discriminator does not cover them.
- **R13.** A plan run's observable cascade cadence SHALL be unchanged: once per
  plan.

### Functional — multi-pr migration

- **R14.** The plan entry point SHALL accept a multi-pr plan and run it one
  pull request at a time, reusing its existing per-issue dispatch loop and its
  single end-of-run cascade call.
- **R15.** The single-issue entry point's response to being handed a multi-pr
  plan SHALL be the disposition recorded under Decisions and Trade-offs below,
  and SHALL NOT be a confusing partial result or a failure that reads as a
  defect.
- **R16.** Every routing claim stating that multi-pr plans run through the
  single-issue skill SHALL be updated. Because the mode's name also appears in
  roughly 830 lines of enum and schema content that this migration does not
  touch, "search returns nothing" is not a usable test. The requirement is
  therefore in two parts:
  - **R16a.** The implementation SHALL produce a written inventory, committed
    with the change, listing every routing claim in the surface: its file, its
    line, what it says now, what it says after, and its **disposition** —
    `edited` when the claim is corrected in place, `superseded` when the
    document carrying it is corrected by a decision record under R18 rather
    than rewritten, and `delegated` when R17 governs it. The disposition is
    what keeps R16a's completion check from contradicting R18: a `superseded`
    row is satisfied by the decision record existing, never by the file
    changing.
    **What "the surface" bounds.** It is the live operational corpus — skill
    prose and frontmatter, reference files, routing tables, eval suites, the
    repository `README.md`, and shared references such as the pipeline model —
    plus exactly the two settled documents R18 names as superseded. It
    excludes durable artifacts that have finished their own lifecycle and
    assert the old routing. Each type's format reference defines that for
    itself: a BRIEF or PRD at `Done`, a DESIGN at `Current` or `Superseded`,
    and any decision record. Those are the audit trail — they record what was
    true when they were written, and the repository corrects them by
    supersession rather than by editing history, which is exactly what R18 does
    for the two that matter. An implementer who rewrote them would destroy the
    record this feature is otherwise careful to preserve.
    `Accepted` is NOT such a status for any type: an Accepted BRIEF still feeds
    a PRD and an Accepted PRD still feeds a DESIGN, so both remain live
    operational documents inside the surface. A DESIGN has no `Done` state at
    all. The one DESIGN R18 supersedes is `Current`, and R18 names it
    explicitly rather than reaching it through this exclusion.
    A *routing claim* is a
    statement that directs a reader or an agent to one entry point rather than
    the other for a given execution mode; an occurrence that merely names the
    mode as a value, a schema field, or a fixture is not one.
    **Boundary against R17.** An occurrence inside an eval suite is governed by
    R17 and SHALL NOT be resolved under R16a. The inventory still lists it,
    marked as delegated to R17, so that the surface stays complete and the two
    requirements never both claim the same line. Without this boundary the eval
    scenarios satisfy R16a's own definition — they are directive prose — and
    two reviewers triaging the same output would split on whether eval files
    count.
  - **R16b.** The inventory SHALL record the exact command that produced the
    candidate set it was triaged from, so a reviewer can re-run it and confirm
    that every hit is either in the inventory or is non-routing by the
    definition above.
- **R17.** The three eval scenarios that assert the current routing SHALL be
  updated to assert the new routing. They are the dispatcher scenario in the
  plan entry point's suite, and two in the single-issue skill's suite,
  including a cross-mode contamination scenario an earlier sweep missed.
- **R18.** The two settled documents this feature contradicts — a requirement in
  the plan entry point's own PRD, which is at `Done`, and the chosen option in a
  DESIGN at `Current` — SHALL be superseded on the record by the mechanism
  chosen under Decisions and Trade-offs, not silently contradicted. Both are at
  a terminal status by R16a's own definition, and they are inside the surface
  only because R16a names them in addition to it; they are the exception the
  exclusion is written around, not instances of it.

### Functional — terminal record retention

- **R19.** Every terminal tick this feature introduces that a **root** session
  runs SHALL retain its workflow context record, and **no child session SHALL
  ever request that retention**. The retention flag suppresses both sources the
  parent's child-completion gate reads, so a child that passes it wedges its
  parent indefinitely. The single-issue skill's koto template is also the child
  template, so an unconditional edit there would hand the flag to every child:
  the discipline is root-only at runtime, not textual.
- **R19a.** The change SHALL carry a regression test asserting that a child
  session does not request retention, so that a later tidy-up cannot
  reintroduce it by making the behaviour unconditional.
- **R19b.** The separately-filed defect covering today's terminal ticks lands
  before this work and establishes the root-only mechanism. This feature SHALL
  reuse that mechanism rather than inventing a second one.
  **The referent is the merged change, not the filed issue.** That issue's text
  proposes retention unconditionally, which predates the discovery that
  unconditional retention wedges a parent; relying on the issue as written
  would reintroduce the defect this requirement exists to avoid. The mechanism
  this feature reuses is the one the merged fix names in its pull request.
  **What "reuse" means testably:** the cascade states call the same named
  helper or discriminator that fix introduces, and a search for a second
  implementation of the same root-versus-child test returns nothing.
  If that fix has not landed when this work reaches implementation, or its
  mechanism differs from what is assumed here, that is an escalation rather
  than a licence to invent a parallel one.
  Whether that same mechanism also serves the child-suppression signal of R12
  is a design question, deliberately left open here: the two behaviours are the
  same shape and may want one discriminator, but that is not a
  requirements-level call.

### Non-functional

- **R20.** The change SHALL NOT alter the execution-mode enum or its schema.
  The overwhelming majority of occurrences of the mode name in this repository
  are enum and schema content untouched by this migration; only routing claims
  change.
- **R21.** Template authoring SHALL follow the repository's existing rules for
  gates and default actions, including the constraints its own linter imposes.
- **R22.** The work SHALL be reviewable as two pull requests: the single-issue
  completeness work first, the multi-pr migration second. The order is a
  requirement, not a preference — the migration rewrites the routing rules that
  the first body of work is implemented under.

## Acceptance Criteria

- [ ] A single-issue run against an issue with no BRIEF, PRD, DESIGN or PLAN
      reaches a mergeable pull request, and its output contains no
      cascade-related text (R2, R3).
- [ ] A single-issue run against an issue whose chain resolves pulls that chain
      to its terminal state in the same run, and the pull request is not
      presented as mergeable before that has happened (R1).
- [ ] An anchor that resolves to no upstream chain still commits and pushes the
      deletion alone and reports skipped; the existing test covering this passes
      unchanged (R4).
- [ ] The location of the shared cascade machinery is recorded with its
      reasoning, and the single-issue skill does not reference any path under
      the plan entry point's directory. Verified by searching the single-issue
      skill's tree for such references and finding none (R5a).
- [ ] For each of the two cascade failure shapes, the single-issue caller's
      behaviour and recovery guidance match the plan entry point's, verified by
      comparing both paths against the same shape (R5).
- [ ] A classification table is committed with the change, and every obligation
      in it is classified gate-enforced or evidence-carried, with none left in
      neither category (R6, R7, R8).
- [ ] Each classification is correct, not merely present: every row classified
      gate-enforced names a gate that exists on the state it names and that
      fails when driven to failure, and every row classified evidence-carried
      names a field that the state's own evidence schema marks required. A row
      naming a gate that does not exist, or a field that is optional, fails
      this criterion (R8).
- [ ] A run that omits a gated obligation cannot advance past the state that
      owns it, demonstrated by driving the gate to failure (R6).
- [ ] Every evidence-carried obligation's field is typed to a concrete referent
      — a path, a commit identifier, or a named command's output — and
      submitting a placeholder or empty value for it fails the state rather
      than satisfying it. Demonstrated per field, not asserted (R7, R7a).
- [ ] No obligation introduced by this feature appears only in the skill's
      `SKILL.md`; each is reachable from the koto template. Verified by
      checking each new obligation against what a materialized child receives
      (R10).
- [ ] The design-diagram obligation is either within one reference-hop with an
      evidence field, or explicitly recorded as advisory with the reason (R9).
- [ ] A child dispatched by the plan entry point does not cascade, and a
      multi-issue run's chain is pulled exactly once (R11, R13).
- [ ] The child-suppression signal is distinct from the shared-branch signal,
      and a multi-pr child — which reaches its own CI monitoring — is correctly
      suppressed by it (R12).
- [ ] The plan entry point accepts a multi-pr plan and runs it to completion,
      one pull request per issue, cascading once at the end (R14).
- [ ] Handing a multi-pr plan to the single-issue entry point produces the
      recorded disposition, and a person doing so is told where a plan is run
      now (R15).
- [ ] The change commits a routing-claim inventory naming every claim's file,
      line, prior text and new text, including the repository `README.md` and
      the shared pipeline-model reference (R16a).
- [ ] The inventory records the command that produced its candidate set, and
      re-running that command yields no hit that is absent from the inventory
      and is a routing claim by the PRD's definition (R16b).
- [ ] For every inventory row with disposition `edited`, the named file at the
      named location contains that row's "after" text and no longer contains
      its "before" text. A correct inventory committed alongside unedited files
      fails this criterion (R16a).
- [ ] Every inventory row with disposition `superseded` names one of the two
      documents R18 covers, and those documents are NOT edited in place — their
      correction is the decision record. A row marked `superseded` that names
      any other document, or a superseded document whose text was rewritten,
      fails this criterion (R16a, R18).
- [ ] **Neither document R18 names has its contradicted text rewritten.** A diff
      of each against its pre-change state shows its routing claim preserved
      verbatim — not reworded, not deleted. The only modification permitted to
      either is the addition of a pointer to the decision record. This is the
      converse of the criterion above and is what makes the disposition
      non-self-serving: without it, a row naming one of those two documents
      could be labelled `edited`, the claim rewritten in place, and every other
      criterion still pass — including R18's own, which checks that a
      supersession record exists and not that the superseded text survived
      (R16a, R18).
- [ ] Every inventory row with disposition `delegated` names a file inside an
      eval suite and is resolved under R17 (R16a, R17).
- [ ] All three eval scenarios assert the new routing and pass (R17).
- [ ] A decision record exists that names both superseded items — the
      requirement in the plan entry point's PRD and the chosen option in the
      `Current` design — and states what supersedes each and why. Each of the
      two documents carries a pointer to that record, added without touching
      the contradicted text itself, which is the one modification the criterion
      above permits. The validator reports no lifecycle or upstream-link
      violation (R18).
- [ ] Every terminal tick this feature introduces retains its context record
      when a root session runs it, verified against the states this feature adds
      rather than the pre-existing ones (R19).
- [ ] A child session running the same states does NOT request retention, and
      its parent's child-completion gate still converges. Demonstrated by
      running a parent to convergence over a child that reaches one of the new
      terminal states (R19).
- [ ] A regression test fails if the retention behaviour is made unconditional
      (R19a).
- [ ] The root-only mechanism used is the one established by the separately
      landing fix, not a second implementation of the same idea (R19b).
- [ ] The execution-mode enum and schema are unchanged (R20).
- [ ] `scripts/validate-template-mermaid.sh`, `scripts/check-template-directives.sh`
      and `scripts/check-template-interpolation.sh` all pass against the edited
      templates (R21).
- [ ] The work lands as two pull requests in the stated order (R22).

## Out of Scope

- **The definition-of-done gate returning cannot-verify.** A per-repository
  configuration gap: the gate reads a verification map most repositories have
  never written. Both entry points run the same state, so nothing here changes
  anyone's exposure.
- **The staleness gate calling a script that is not shipped.** A separate
  missing-file defect with its own recorded open question.
- **Terminal ticks that predate this feature destroying their context record.**
  Filed separately and landing before this work. R19 covers only the states
  this feature adds.
- **Gates being unable to observe whether a review panel ran.** Deferred until
  this feature settles which skill owns those panels, so the redesign happens
  once.
- **The naming fossils left by the earlier split of these two skills.** Worth
  correcting; not this feature's purpose.
- **Merging the pull request.** The feature ends at a mergeable pull request.
- **The execution-mode enum itself**, per R20.

## Decisions and Trade-offs

These close the three questions the absorbed framing deferred.

### The single-issue skill refuses a multi-pr plan and names where one is run

**Decided:** refuse with a pointer, rather than retaining the mode for
compatibility or dropping it silently.

**Alternatives.** Retaining it keeps two ways to run a plan, which is the
defect this feature exists to remove, and leaves the single-issue entry point
deciding when a plan is finished. Dropping it silently turns a documented
invocation into a confusing failure; the earlier split of these two skills
already rejected hard-removing this input on exactly that ground, observing
that it "breaks existing invocations and `/work-on`'s own evals". That
objection is on the record and applies here unchanged.

**Why refuse-with-pointer wins.** It honours the objection — the invocation
still lands somewhere legible — without preserving the second route. The
existing evals that assert the old behaviour are updated to assert the
redirect, which is work either way.

### A run with no anchor is a pass-through, not a skipped cascade

**Decided:** the absence of a chain is established before the cascade is
invoked, and the cascade is not invoked at all.

**Alternatives.** Invoking it and letting it report a skip would be uniform,
and was the shape assumed before the cascade script was read closely. It is not
available: the script takes a plan-shaped path as its only positional argument
and has no no-document mode, so there is nothing to hand it. Synthesizing an
anchor document to satisfy the argument was considered and rejected — it would
put a fabricated document into a real chain to make a control-flow decision.

**Consequence.** "Done" for an issue with no documents behind it means exactly
what it means today. This is deliberately not a behaviour change for the
common case.

### The shared machinery must not invert the dependency direction

**Decided:** the constraint, not yet the location. Wherever the shared cascade
machinery ends up, the single-issue skill SHALL NOT depend on the plan entry
point to reach it. Which directory it lands in is a design-hop choice; that it
cannot be the plan entry point's own is settled here.

**Why it needs deciding at all.** The script lives under the plan entry point's
directory today, because a recorded decision put it there when the plan-level
orchestrator was carved out of the single-issue skill. The naive reading of
"both callers share one script" is to leave it there and call across the
boundary — which would make the skill that everything else depends on depend on
its own consumer, inverting the argument this feature's shape rests on, and
adding a second load-bearing cross-skill path of the kind the repository
already guards with a dedicated assertion.

**Alternatives considered.** Duplicating the cascade logic in both skills was
rejected: the repository does accept deliberate duplication guarded by a drift
check, and uses it for one CI-gate expression, but a 200-line script is not a
one-line expression and the drift would not stay caught. A shared *template*
was rejected on the record once already, for muddying the single-issue
template's legibility; that rejection stands and is not being reopened, because
a script is executed rather than read into a run's context and is not the thing
that was rejected.

**Left to the design hop.** The repository already has a root-level `scripts/`
directory holding cross-skill machinery, including the test for the one
expression both templates duplicate on purpose. That is the obvious candidate,
and naming it here would be deciding a layout question without having looked at
what else moves with it.

### The contradicted documents are superseded by a decision record

**Why neither type's own supersession route fits.** A PRD has no `Superseded`
state at all: its format reference says to create a new PRD and mark the old one
`Done` with a note that it was replaced. The PRD in question is already `Done`,
and this feature does not replace it — it contradicts one requirement inside a
document that is otherwise still an accurate record. A DESIGN reaches
`Superseded` only when a successor DESIGN names it as `superseded_by:`, and
there is no successor here either: the design remains `Current` and accurate
apart from the one option this feature reverses. Marking either document
wholly superseded would assert something false.

That is why the mechanism is a decision record plus a pointer, and why the
contradicted text stays where it is. The old decision is not wrong about what
was decided then; it is superseded about what holds now, and those are
different claims that a rewrite would conflate.

**Decided:** one decision record amending both the settled requirement and the
chosen design option, rather than editing either in place.

**Alternatives.** Editing in place is cheaper and loses the reasoning: a reader
of the design would find the new option with no trace that another was chosen
first, which is the failure mode this repository's decision records exist to
prevent. Writing a new document that simply disagrees with both was rejected
outright — the repository already carries a queue of documents describing
capabilities that do not exist, and adding another while fixing two of them
would be perverse.

## Known Limitations

- The classification of obligations into gate-enforced and evidence-carried is a
  judgment itself. A meaningful minority resolve to observable facts; the
  remainder become evidence fields whose honesty depends on the run. This
  feature narrows the gap rather than closing it, and R8 exists so the residue
  is recorded rather than assumed away.
- Refusing a multi-pr plan at the single-issue entry point is a breaking change
  for anyone currently relying on the documented behaviour, mitigated by the
  redirect but not eliminated.
- The two pull requests are sequenced, so the second cannot start until the
  first lands. That is the cost of not rewriting the routing rules underneath
  the work being implemented under them.
