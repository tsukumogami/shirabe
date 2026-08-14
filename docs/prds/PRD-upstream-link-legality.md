---
schema: prd/v1
status: In Progress
problem: |
  The `upstream:` field is a document's only durable record of its lineage, and
  nothing defines what makes a link legal or checks that it is. Links point the
  wrong way down the chain, and links point at documents whose deletion is
  already scheduled. Eight edges in this repository are illegal today and every
  one of them passes validation.
goals: |
  Legality becomes a declared property of each artifact type, covering both the
  direction of a link and the lifetime of its target, and `shirabe validate`
  enforces it. The skills that write upstream links stop producing the illegal
  kind, and the one automated consumer that reached a roadmap through a link
  this work removes reaches it through a legal one instead.
upstream: docs/briefs/BRIEF-upstream-link-legality.md
motivating_context: |
  Two issues arrived from opposite directions. One proposed a type-pair check
  and excluded the BRIEF edge; the other was entirely about that edge. Neither
  fix works alone, and the exclusion in the first is what makes the second
  invisible.
---

# PRD: Upstream Link Legality

## Status

In Progress

## Problem Statement

A shirabe document names its parent in one frontmatter field, `upstream:`. That
field is the audit trail: a reader who asks why a design exists follows it to a
PRD, to a brief, and out to whatever framed the work. When a hop is wrong the
trail does not degrade, it ends.

Nothing states what makes a link legal, and nothing checks. Two failures follow
and they fail on different properties.

The first is direction. Each format reference names the type that sits above it,
and none of that is enforced — a document naming something below itself
validates clean. This repository carries eight such edges. Every one is a brief:
four name a design, two name a plan, two name a sibling brief. Five of the eight
also dangle, and the resolution check catches those five for the wrong reason —
because the path is missing, not because the edge is backwards. Correcting the
paths would leave all eight illegal.

The second is lifetime. ROADMAP and PLAN declare Working lifecycle and are
deleted when their work completes; the other six types are Durable. A durable
document naming a working one holds a reference that is correct the day it is
written and dangling the day the cascade runs. The formats do not merely permit
this — a brief's only stated legal upstream is a ROADMAP, so following the rule
as written produces the defect. The cascade deletes the roadmap and transitions
the naming brief to Done in the same commit, leaving the brief permanently
pointing at a file that no longer exists.

Both failures have the same cause: legality is prose, written across format
references and skill files for a human reading them at the moment they write the
field. Nothing carries it to the moment a link is created — by hand, by a skill,
or by a parent skill handing a path to a child.

The system already answers a related question. A public document whose upstream
is private does not record it: the field is omitted, the context is absorbed,
and the document stands as the head of its own lineage. Nine places in the skill
corpus state that rule. An ephemeral upstream has the same shape — a real parent
that cannot be durably named — and whether these are one rule or two is a
question this PRD has to answer rather than inherit.

## Goals

Legality is declared, not narrated. Each artifact type carries two facts
alongside its required sections and valid statuses: whether it survives the
completion of its own work, and which types may sit above it. A maintainer
adding a type declares both and gets both enforced.

An illegal link fails at authoring time. `shirabe validate` reports the
offending document, the offending value, and which of the two properties failed,
in a message an author can act on without opening a format reference.

The skills stop producing illegal links on their own. An author running a chain
does not have to know the rule; where an upstream exists but cannot be recorded,
the producing skill reads it, omits the field, and says so.

The change costs no working behaviour. One automated consumer reaches a roadmap
by walking a link this work removes; it reaches the same roadmap through a link
the new rule permits.

## User Stories

**As a maintainer writing a brief by hand,** I want the validator to tell me my
`upstream:` points at a design rather than a roadmap, so that I fix the field
before the commit exists rather than after a reader follows it.

**As an author running the tactical chain under a roadmap,** I want the chain to
read the roadmap for framing without recording a link that the cascade will
later break, so that nothing I produce dangles when the roadmap is deleted.

**As an engineer auditing a shipped feature,** I want every hop of a durable
document's upstream chain to resolve, so that the audit trail is the thing it
claims to be.

**As a maintainer adding a new artifact type,** I want to declare the type's
lifetime and its legal parents in one place and have both enforced, so that I do
not have to find four skill files to learn what the type may point at, and so
that I cannot accidentally declare a durable type whose parent is deleted on
completion.

**As the cascade,** I want to find the roadmap whose feature this chain
implemented, so that I can mark the feature Done and delete the roadmap when its
last feature lands.

## Requirements

### The definition

**R1.** An `upstream:` entry is legal when both properties hold:

- **Direction** — the entry's target is of a type the naming document's format
  declares as a legal parent.
- **Lifetime** — the target outlives the naming document, or they are retired
  together.

An entry violating either property is illegal. The two properties are
independent: an entry can satisfy one and fail the other.

**R2.** Each artifact type declares its lifetime class — `Durable` or `Working`
— as a structural property of the type, in the same place its required sections
and valid statuses are declared. The classes are those already documented in
each skill's `## Artifact Lifecycle` section: Working is ROADMAP and PLAN;
Durable is VISION, STRATEGY, BRIEF, PRD, DESIGN, and COMP.

**R3.** Each artifact type declares the set of types that may be named as its
upstream, in the same place. The set may be empty, which states that the type is
always the head of its own lineage.

**R4.** No Durable type may declare a Working type in its legal parent set. A
maintainer who writes such a declaration finds out before it can reach the
corpus.

**R5.** The declared legal parent sets are:

| Type | Lifetime | Legal parents |
|---|---|---|
| VISION | Durable | VISION |
| STRATEGY | Durable | VISION |
| ROADMAP | Working | STRATEGY |
| BRIEF | Durable | *(none)* |
| PRD | Durable | BRIEF |
| DESIGN | Durable | PRD, BRIEF |
| PLAN | Working | DESIGN, PRD, BRIEF, ROADMAP |
| COMP | Durable | *(none)* |

**R5.1.** Two readings behind the table are settled rules this PRD adopts
unchanged from `references/pipeline-model.md`. The strategic chain is strict —
each type names its immediate parent only — because skipping an altitude there
leaves the skipped reasoning unreachable from the path a reader walks. The
tactical chain admits any strictly-higher tactical altitude, because its steps
are not all mandatory and the field records the chain that was actually walked.

**R5.2.** Three rows change what the references currently document, and all
three follow from R4 rather than from a new judgment about the chain's shape.
`pipeline-model.md` states outright that a BRIEF's upstream is a ROADMAP, and
that a PRD's is a ROADMAP when no BRIEF was written; `prd-format.md` repeats the
PRD case. The DESIGN case is not stated outright but follows from the same
file's nearest-produced rule — each artifact names the nearest artifact actually
produced above it — and the shape is exercised today by the cascade's
short-chain design fixture and its matching test scenario. ROADMAP is Working
and all three of those types are Durable, so R4 forbids each of them. The
consequence, stated once: **no durable tactical document may name a ROADMAP, so
the crossing from the strategic chain into the tactical one is recorded on the
PLAN alone.** Every reference that currently documents one of the three
forbidden shapes is updated to match, so that after the change no format or
pipeline reference documents a ROADMAP as a legal upstream for a BRIEF, a PRD,
or a DESIGN.

**R5.3.** PLAN's set gains BRIEF, which no `/plan` input mode produces today.
It is admitted because the tactical reading in R5.1 allows any strictly-higher
altitude and excluding it would be a special case with no reason behind it.

### Enforcement

**R6.** `shirabe validate` reports an error-severity finding for every illegal
`upstream:` entry, naming the document, the offending value, the resolved type
pair, and which property failed.

**R7.** The direction violation and the lifetime violation carry distinct check
codes so each can be selected with `--check` and each message can state its own
fix. When one entry violates both, the lifetime finding is reported and the
direction finding is suppressed for that entry: a reader who fixed only the
direction would still be naming a document scheduled for deletion.

**R8.** Legality is decided from the naming document's format and the target's
basename alone. Nothing about the check causes `docs/visions/` or
`docs/strategies/` to be indexed, so no VISION or STRATEGY is drawn into the
orphan rule, which was never written for them.

**R9.** An entry whose target basename matches no known artifact prefix is
unchecked rather than failed. This covers cross-repo `owner/repo:path` values —
whose file component is still resolved for its type when it names a known prefix
— and any path that is not an artifact.

**R10.** Each entry of a multi-valued `upstream:` is judged independently and
reported independently, matching the per-entry reporting the resolution check
already does. A placeholder entry is skipped; a blank entry is already the
resolution check's finding and is not re-reported here.

### Recording

**R11.** No skill records an `upstream:` value the definition forbids. Where the
value is legal, the skill records it as it does today, except where a
requirement below says otherwise.

**R12.** Where an upstream exists, is correct, and cannot be recorded, the
producing skill reads it for context, omits the field, and announces the
omission and its reason in its run output. This is the same obligation the
existing private-upstream rule imposes; see Decisions and Trade-offs. The
announcement is graded by the skill's eval suite rather than by a string match,
which is how the five skills that already carry this obligation are graded.

**R13.** `/brief` no longer records a ROADMAP as the produced brief's
`upstream:`. Its roadmap input mode and its `--upstream` flag are unchanged as
*inputs* — the roadmap is still read, and still grounds the framing conversation
— and the produced brief carries no `upstream:` field.

**R14.** Where a tactical chain runs under a roadmap, the produced PLAN records
that ROADMAP among its `upstream:` entries, alongside the design or other
tactical source it already records. `/plan` accepts the roadmap path on the same
`--upstream <path>` flag that `/brief`, `/prd`, `/roadmap`, `/strategy` and
`/comp` already carry, so the value never reaches the positional slot and never
derives the plan's topic slug. This is the requirement that discharges R19.

**R15.** `/explore` no longer passes a VISION path to `/roadmap` as its
`--upstream` value. A ROADMAP's only legal parent is a STRATEGY, and `/roadmap`'s
own contract already says a VISION must not be substituted for one; the handoff
contradicts it today and produces a link the definition forbids.

**R16.** A skill records the same `upstream:` value when invoked standalone as it
does when a parent skill invoked it. No parent suppresses or rewrites what a
child records at the moment the child records it.

**R16.1.** `/scope`'s consolidation absorb is not an exception to R16. It
rewrites a surviving PRD's `upstream:` after both children have returned and one
document has been removed, which is a statement about the corpus after a
deletion rather than an override of what a child recorded. Under R13 the
absorbed brief carries no upstream, so the absorb's existing rule — remove the
survivor's field when the absorbed artifact had none — leaves the survivor
correctly headed, with no separate guard needed.

**R17.** The obligation that a document with no recorded upstream be
self-contained is discharged by the self-containment each format already
requires of its head sections. No section, field, or check is added for it: the
change introduces exactly the two check codes R7 names and alters no format's
required-section list.

### Keeping consumers whole

**R18.** The chain-walking readers — the finalization walk and the lifecycle
chain walk — keep their current type-agnostic behaviour. A chain authored before
this change, including one in which a BRIEF names a ROADMAP, walks and cascades
exactly as it does today. The opinion about legality is the validator's alone.

**R19.** The cascade must still locate the ROADMAP whose feature a completed
chain implemented, so that the feature's status is updated and the roadmap is
deleted when its last feature lands. R14 supplies the link it walks.

**R20.** The orphan rule's exemption for a document whose upstream is an Active
ROADMAP becomes unreachable for documents authored under this rule, because no
durable type may name a ROADMAP. The exemption, its behaviour, and its tests
stay as they are; nothing in the corpus depends on it, and no document's
validation result changes. A brief that heads its own lineage with no downstream
document yet receives the same orphan notice an upstream-less brief receives
today — notice-level under draft posture, resolved as soon as its PRD names it.

### Compatibility

**R21.** No existing test in `cargo test --workspace` is modified, and the frozen
expected output of every golden-corpus fixture is unchanged. The two new check
codes must not collide with any code an existing test asserts is unrecognized,
so neither may be `R5` or `FC99`.

**R22.** Five skill eval expectations assert the behaviour R13 and R14 change,
and updating them is part of this work rather than a silent repair. Each is named
here so the change is visible in review rather than discovered in a diff:

| Eval | Scenario | Asserts today | Disposition |
|---|---|---|---|
| `skills/brief/evals/evals.json` | `upstream-roadmap-grounding` | the brief declares the ROADMAP as its frontmatter `upstream` | rewritten: the roadmap grounds the framing and no field is written |
| `skills/brief/evals/evals.json` | `upstream-flag` | Phase 2 writes `upstream: <roadmap>` into the produced brief | rewritten to the same shape |
| `skills/scope/evals/evals.json` | `upstream-flag-consumed` | the produced brief carries `upstream: <roadmap>` | rewritten: the roadmap reaches the PLAN instead |
| `skills/scope/evals/evals.json` | `pre-authoring-notice-cold-start` | the notice says supplying a roadmap means "this chain will attach the BRIEF to it" | reworded: the chain attaches the PLAN. The same sentence is committed twice in `skills/scope/references/phases/phase-1-discovery.md`, and the prose changes with the eval |
| `skills/execute/evals/evals.json` | the full-chain cascade scenario | the chain is PLAN to DESIGN to PRD to BRIEF to ROADMAP | rewritten to the new route, against a new-shape fixture chain added alongside the frozen old-shape one |

**R23.** Two cascade eval fixtures carry edges the definition forbids —
`skills/execute/evals/fixtures/briefs/BRIEF-cascade-test-full.md` names a
ROADMAP, and `skills/execute/evals/fixtures/designs/DESIGN-cascade-test-short.md`
names one directly. They are kept in the old shape deliberately, as the evidence
for R18 that a pre-existing corpus still cascades, and are exempt from R24's
no-other-changes clause on that basis. A new-shape fixture chain, in which the
PLAN carries the roadmap and no durable node does, is added beside them and is
what the rewritten cascade eval runs against. Adding fixtures is a deliverable
of this change, not a change to an eval outside R22's list.

**R24.** Every document under `docs/` whose validation result changes is named
before the change is measured, so an intended change is never mistaken for a
regression. The list is fixed by R5 and is exactly:

| Document | Today | After |
|---|---|---|
| `docs/briefs/BRIEF-fc06-index-alias.md` | clean | direction violation (BRIEF names DESIGN) |
| `docs/briefs/BRIEF-lifecycle-draft-ready-discipline.md` | clean | direction violation (BRIEF names BRIEF) |
| `docs/briefs/BRIEF-skill-cascade-lifecycle-check.md` | clean | direction violation (BRIEF names BRIEF) |
| `docs/briefs/BRIEF-cascade-outline-ac-completeness.md` | R6 error | R6 error plus lifetime violation |
| `docs/briefs/BRIEF-single-pr-plan-validation.md` | R6 error | R6 error plus lifetime violation |
| `docs/briefs/BRIEF-legend-vs-classdef-reconciliation.md` | R6 error | R6 error plus direction violation |
| `docs/briefs/BRIEF-lifecycle-passing-state-validation.md` | R6 error | R6 error plus direction violation |
| `docs/briefs/BRIEF-table-diagram-reconciliation.md` | R6 error | R6 error plus direction violation |

The other 73 edges under `docs/` stay legal and the 68 documents with no
`upstream:` field are untouched. Repairing the eight is out of scope; naming
them is not.

**R25.** `shirabe validate --lifecycle . --mode=draft` exits 0 after the change,
as it does before it.

## Acceptance Criteria

- [ ] A durable document naming a Working-lifecycle document as `upstream:`
      produces an error-severity finding from `shirabe validate` that names the
      document, the offending value, and the lifetime property.
- [ ] A document naming a type absent from its declared legal parent set
      produces an error-severity finding naming the resolved type pair.
- [ ] An entry that violates both properties produces exactly one finding, the
      lifetime one.
- [ ] An entry whose target basename matches no artifact prefix produces no
      finding.
- [ ] Every entry of a multi-valued `upstream:` produces its own finding, each
      carrying the `upstream:` field's line number, as the resolution check's
      per-entry findings already do.
- [ ] Both new check codes are selectable with `shirabe validate --check <CODE>`,
      and the message listing valid codes names them.
- [ ] A test asserts that no Durable type declares a Working type among its
      legal parents, and fails when one is added.
- [ ] A test asserts all eight declared lifetime classes and all eight declared
      legal parent sets against R2 and R5 verbatim, and fails on a single
      changed entry in any row.
- [ ] `is_known_check_code` gains exactly the two new codes, and no format's
      required-section list changes.
- [ ] `/brief` handed a roadmap produces a brief with no `upstream:` field. Its
      eval suite grades that the roadmap's feature entry still grounded the
      framing conversation, and that the run announced the omission and its
      reason.
- [ ] A `/scope` run supplied with a roadmap produces a chain in which no
      durable artifact names the roadmap, and the produced PLAN carries the
      roadmap among its `upstream:` entries. Where the run's consolidation
      absorbs the brief, the surviving PRD is left with no `upstream:` field
      rather than the roadmap's path.
- [ ] A document whose `upstream:` names a `VISION-` or `STRATEGY-` basename is
      judged without that file being read from disk, and a `--lifecycle` run
      over a tree containing a VISION emits the same finding set before and
      after the change.
- [ ] No file under `references/` or `skills/*/references/` documents a ROADMAP
      as a legal upstream for a BRIEF, a PRD, or a DESIGN.
- [ ] `/plan` accepts `--upstream <roadmap-path>`, records it, and derives its
      topic slug from the positional argument rather than from the flag.
- [ ] `/explore` passes no `--upstream` value to `/roadmap` that is not a
      STRATEGY.
- [ ] Running the cascade against a chain authored under the new rule updates
      the roadmap feature's status and deletes the roadmap, matching the
      existing cascade eval's expectations for those two steps.
- [ ] Running the cascade against the frozen old-shape fixture chain, in which
      the brief names the roadmap, still reaches the roadmap.
- [ ] The eight documents named in R24 produce exactly the findings R24
      predicts, and no other document under `docs/` changes its findings.
- [ ] `shirabe validate --lifecycle . --mode=draft` exits 0 and emits the same
      finding set it emits before the change, notices included.
- [ ] `cargo test --workspace` passes with no existing test modified, and every
      golden-corpus fixture's frozen expected output is byte-identical.
- [ ] The five eval expectations named in R22 are updated, and no eval outside
      that list changes. Fixtures added under R23 are deliverables, not changes
      to an eval outside the list.

## Decisions and Trade-offs

### The private-upstream rule and the ephemeral rule are one rule with two triggers

The brief deferred this. The answer is one rule, and the reasoning is that the
obligation is identical while only the trigger differs.

Both cases are an upstream that exists, is correct, and cannot be durably
referenced from this document. The private case cannot be referenced because a
public reader cannot reach the target; the ephemeral case cannot be referenced
because the target will not be there. In both, the settled response is the same
three acts: read the upstream for context, omit the field, say so in the run
output. Nine places in the skill corpus already state those three acts for the
private trigger, in the same order and with the same announcement obligation.
Adding a tenth statement with a different shape for the ephemeral trigger would
make the system carry two rules that a reader has to notice are the same one.

The two triggers are not symmetric in one respect, and it is worth stating
rather than smoothing over: only the lifetime trigger can be checked by tooling.
A cross-repo value resolves to nothing, so a public document naming a private
one validates clean today and always will — every skill that states the private
rule says so explicitly, and `/scope` describes itself as owning "the check the
validator cannot make." The lifetime trigger resolves from a basename, so it can
be checked. One rule, two triggers, one of them enforceable. The asymmetry lives
in the enforcement, not in the rule.

Alternatives considered: keeping them as two rules stated side by side, which
was rejected because it doubles the prose a maintainer must keep in sync for no
behavioural gain; and generalizing further into a single "unreferenceable
upstream" abstraction covering `wip/` paths too, which was rejected because
`wip/` and untracked paths are *rejected* rather than omitted — they are
malformed input the author can fix, not legitimate values this document cannot
record, and collapsing that distinction would silently continue a run that
should stop.

### The mechanism is to record nothing, not to navigate further up

The brief left two candidates open: record the nearest durable ancestor, or
record nothing and require self-containment.

Navigating up was rejected on three counts. It crosses a chain boundary — a
brief's nearest durable ancestor above a roadmap is a STRATEGY, which describes
a medium-term bet rather than this feature, so a reader following the link lands
somewhere that does not describe what they were reading about. It contradicts
the strict-strategic-chain rule, which forbids skipping an altitude precisely
because the skipped reasoning becomes unreachable. And it has no precedent in
the system, while recording nothing has two: the private-upstream rule, and
`/strategy`'s refusal to record a grounding PRD it nevertheless reads.

Recording nothing also has a property navigating up does not: it makes the
brief's declared legal parent set empty, which is a checkable statement. "A
brief is always the head of its tactical lineage" is enforced by R5 and R6 with
no special case anywhere. Under the navigate-up mechanism, a brief's legal
parent set would be `{STRATEGY}` — an edge that skips two altitudes and that the
chain walk explicitly declines to follow.

### The brief edge is checked, not carved out

One of the two issues behind this work proposed leaving BRIEF upstreams
unchecked, reasoning that the lifecycle chain walk already declares a brief's
upstream "a cross-chain reference, not a chain-membership edge, and we do not
follow it."

That reasoning is about the walk, not about legality. The walk declining to
follow an edge says nothing about whether the edge is well-formed; it says the
walk has no use for it. And the exclusion is self-defeating here: every irregular
edge in the corpus is a brief's, so an unchecked BRIEF means a check that finds
nothing, and the one durable-to-working edge the formats direct is precisely
BRIEF to ROADMAP, so an unchecked BRIEF means the lifetime rule has nothing to
bind to either. Checked on its merits, the edge is where all the signal is.

The cost of checking it is three documents that are clean today and fail
afterwards, all named in R24 and all genuine lineage errors: two briefs naming
sibling briefs and one naming a design.

### "Absorb the context" is the self-containment each format already requires

The brief's second open question asked whether "absorb the context" is a real
obligation or an aspiration, and whether a document that is the head of its
lineage must carry something specific for that to be true.

It is real, and it is already written down. Every format that can head a lineage
requires its opening sections to stand alone — a brief's Problem Statement must
let a cold reader grasp the gap "without having to open the upstream roadmap", a
PRD "states its own problem in full", a strategy grounded in a PRD names the
grounding in Strategic Context prose. Removing the link does not create a new
obligation; it removes the crutch that let the existing one go unexercised.
Adding a second, link-specific self-containment requirement would duplicate a
rule that is already enforced by the Phase 4 juries and, for the sections the
validator knows about, by the required-sections check.

### The PLAN carries the roadmap link, and no durable document does

Something has to name the roadmap, because the cascade updates a roadmap
feature's status and eventually deletes the roadmap, and it finds the file by
walking a completed plan's upstream chain. Removing the brief's link without
replacing it would convert a loud dangling reference into a silent omission: the
cascade would exit clean having quietly skipped the roadmap forever, and the
roadmap's features would stay Planned after they shipped.

The rule says which node may carry it. Links run from the shorter-lived document
to the longer-lived one, so the node that may name a roadmap is one that does not
outlive it. The PLAN is that node: it is Working, and the cascade that would
delete the roadmap deletes the plan first, so a plan naming a roadmap cannot
dangle. Every durable node in the chain fails that test, which is why the
crossing from the strategic chain into the tactical one now lands on the plan
and nowhere else.

Alternatives considered: giving the cascade a reverse lookup that finds the
roadmap whose feature names this chain, which works but rests on a roadmap field
that the roadmap format does not actually document, so it would have to
canonicalize that field first; and leaving the roadmap unreachable, rejected for
the reason in the first paragraph.

### Two check codes rather than one

The two properties get separate codes so that `--check` can select either, so
each message states its own fix, and so a corpus report distinguishes a
mis-directed link from a link with a death date. The cost is one extra code in
the registry and a precedence rule (R7) deciding which fires when both apply.
A single code was considered and rejected because its message would have to
branch anyway, and the branch would then be invisible to `--check`.

## Known Limitations

The lifetime check finds nothing in this repository's corpus that the existing
resolution check does not already flag — both documents that violate it also
dangle. Its value is preventive and shows up in repositories that actually carry
roadmaps, of which this is not one. That is an argument about where the check
earns its keep, not about whether it is correct, but a reader comparing the two
checks' corpus yields should know that the direction check finds three documents
on its own and the lifetime check finds zero.

The lifecycle traversal named in R25 is a weak regression guard. It emits no
per-file findings, so neither the five dangling briefs that fail per-file
validation today nor the new checks affect its exit code. It proves the
traversal was not disturbed and nothing more; the per-file evidence is R24's
table.

A brief authored under this rule and left without a downstream PRD carries an
orphan notice until the PRD is written. That is the behaviour an upstream-less
brief already has, and R13 makes it the normal case rather than the exception.
Under ready posture the notice is an error, so a pull request that ships a brief
alone has to reach for draft posture — which is what draft posture is for.

The check reasons from basenames. A document at a path that does not match its
own type's conventional directory is still judged by its prefix, and a target
renamed without its prefix changing is still judged as its old type. This is the
same assumption the format detection already makes everywhere else.

Cross-repo upstreams are judged on their file component's prefix alone. A
cross-repo value naming a `ROADMAP-` file from a durable document is caught; one
naming a file whose prefix is unrecognizable is not, and neither is a cross-repo
value whose target has been deleted in the other repository.

## Out of Scope

**Repairing the eight illegal edges.** They are named in R24 so the diff is
readable, and they stay illegal after this change. Correcting them is a separate
job with its own review, and three of them are already tracked elsewhere as
dangling-reference repairs.

**Whether one upstream may have several downstream documents of the same type.**
That is a cardinality question about how many children a parent may have, not
about whether an edge is legal, and it has its own exploration.

**Removing multi-valued `upstream:`.** The formats permit it, the chain walk
handles it, and R10 judges each entry independently. R14 relies on it.

**Indexing the strategic directories.** R8 rules it out: the check decides from
two basenames.

**Teaching the cascade to strip inbound references when it deletes a working
artifact.** That treats the dangling link as cleanup rather than as something
that should never have been written. If the rule holds, there is nothing to
strip.

**Canonicalizing the roadmap's per-feature downstream field.** The cascade both
reads and writes a field the roadmap format does not specify. That is a real
gap, and it is the reason the reverse-lookup alternative was not chosen, but
fixing it is a roadmap-format job rather than a legality one.

**A general "unreferenceable upstream" abstraction covering `wip/` and untracked
paths.** Those are rejected rather than omitted, and the distinction is
load-bearing; see Decisions and Trade-offs.
