---
schema: design/v1
status: Planned
upstream: docs/prds/PRD-multi-pr-plan-decoupling.md
problem: |
  A PLAN's execution_mode answers three questions at once -- can this land in
  one pull request, should it, and what GitHub tracking gets created. The
  planning workflow has no repository-level preference to consult for the last
  two, and no PLAN records why it has the shape it has. Two mechanisms that
  would serve are already shipped one altitude away, and the rule governing the
  choice contradicts the multi-repository rule governing the same question.
decision: |
  Two new CLAUDE.md convention headers, `## Delivery Preference:
  consolidated|atomic` and `## Tracking Level: none|issues|
  issues-and-milestone`, resolved on the existing flag > header > default
  stack. A `split_rationale` PLAN frontmatter field naming one of three
  branches, checked by a new Plan-only lifecycle check L09 registered as
  draft-tolerable. A shared `references/split-triggers.md` that both P1 and the
  Coarsest-Legal-Grouping Rule cite, parameterized by altitude. A third
  ISSUE_SOURCE value, plan_item, so an issueless multi-PR plan keys its work
  items on outline-derived local ids rather than GitHub issue numbers.
rationale: |
  Each part reuses a shipped mechanism rather than inventing one: the header
  channel and its generic Rust walker, the DraftTolerable posture class, the
  single-pr outline parser and local-id algorithm, and P4's own
  shared-reference-parameterized-by-profile shape. The one place the design
  declines to reuse is FormatSpec, whose every consumer is answerable from the
  document alone and which would gain hidden filesystem I/O to serve one field
  of one format.
---

# DESIGN: Multi-PR Plan Decoupling

## Status

Planned

## Context and Problem Statement

`skills/plan/references/phases/phase-3-decomposition.md` step 3.6 runs one
branch that decides a PLAN's `execution_mode`. That branch evaluates two
unrelated things together, whether a hard constraint forces the work apart and
whether each resulting piece would deliver value on its own, and
`phase-7-creation.md` then reads the result as answering a third question,
filing GitHub issues under a milestone when the value is `multi-pr` and nothing
when it is `single-pr`.

The upstream PRD states the resulting three problems in full. What this design
adds is the technical landscape that shapes how they are closed.

**Two preference mechanisms already exist, scoped one altitude away.**
`## Roadmap Issues: optional|required` governs whether `shirabe roadmap
populate` files issues, resolved `flag > CLAUDE.md-header > default`, with a
rule that automatic runs are always issueless. `## PR Grouping Policy:` and
`## Reviewability Ceiling:` govern how a coordinated multi-repository effort
splits, with a named trigger list and a configurable threshold. Both are on the
stack this design reuses. Neither reaches the plan-level decision, and
`grep -rn "issueless\|no_issues" skills/plan/` returns nothing.

**The validator's structural layer is deliberately document-local.**
`crates/shirabe-validate/src/formats.rs` builds every `FormatSpec` with no I/O;
`required_fields` and `execution_mode_required_sections` are both answerable
from parsed frontmatter alone, and `check_fc01`'s signature is `(doc, spec)`
with no configuration parameter. A field required only under a condition that
partly depends on repository configuration does not fit that shape. Separately,
`crates/shirabe-validate/src/visibility.rs` already ships
`resolve_claude_md_header`, a generic walker that reads convention headers by
walking up from a document to its repository root, and
`crates/shirabe-validate/src/validate.rs` already ships `PostureClass`, which
makes a finding a notice under draft posture and an error under ready.

**Task extraction keys multi-PR work items on GitHub issue numbers.**
`skills/plan/scripts/plan-to-tasks.sh`'s multi-pr branch pulls `#N` from each
Implementation Issues row's first cell and resolves dependency edges by walking
further `#N` tokens in the Dependencies cell. A plan that files no issues has no
`#N` to parse, so making tracking optional is not a matter of gating an existing
step — the extraction needs a work-item key it does not have. The single-pr path
already solves the same problem with outline-derived local ids, but that machinery
is reached through a different code path.

**The rule contradicts itself across two files.** P1 in
`references/workflow-principles.md` permits splitting for a hard constraint or
genuine incremental value "and never by mechanism";
`references/coordination-strategy.md` lists exceeding a configured reviewability
ceiling as a legitimate trigger. Both govern how many pull requests work arrives
in. P4 in the same principles file forbids exactly the shape that would fix this
by copying: "per-skill restatement is the drift source the standardization
removes."

**The approval gate's justification is prose, not code.**
`DECISION-multi-pr-posture-detection-2026-06-06.md` explains the asymmetric
Draft→Active gate by multi-pr being the moment remote artifacts are created.
Nothing in `transition.rs` or `lifecycle.rs` implements that gate; it lives in
prose at eleven sites across the tree, and the phrasing varies across them. Three
of those sites are `Current` design docs, which assert present architecture rather
than history, so they need correcting too. That changes what re-keying it means.

## Decision Drivers

- **D1: Reuse the shipped preference channel.** Six `## <Noun Phrase>: <value>`
  headers already carry repository-scoped scalar preferences, with a documented
  registry and a tested Rust parser.
  `DESIGN-roadmap-issueless-preference.md` already rejected a config file for
  this purpose. No new channel.
- **D2: Keep the structural validator document-local.** Any check that reads
  outside the document must not force `FormatSpec` to acquire I/O, because that
  cost is paid by all eight formats to serve one.
- **D3: Do not weaken the value guard.** Step 3.5a asks whether each unit
  delivers observable value alone. No preference, and no branch of the split
  rule, may exempt a unit from it.
- **D4: Honor P4 over convenience.** A trigger list consumed at two altitudes
  is a shared shape. It gets one source, parameterized by profile, the way
  `issues-table.md` and `dependency-diagram.md` already are.
- **D5: An unstated preference changes what is produced, never what is
  recorded.** A repository stating nothing gets today's `execution_mode` and
  today's GitHub artifacts. The `split_rationale` record is the deliberate
  exception, because a shape without a reason is the defect the feature exists
  to close.
- **D6: Strictness tracks blast radius.** New checks land as notices under
  draft posture and errors under ready, on the shipped `PostureClass`
  mechanism rather than a new enforcement path.
- **D7: Name nothing that collides.** `Execution Mode` is taken by the
  autonomy header and would also collide with the `execution_mode` frontmatter
  field. A third meaning would be a shipped defect.
- **D8: Amend the current owner.** `DESIGN-roadmap-plan-standardization.md`
  Decision 6 owns the split rule today and already de-conflated decomposition
  strategy from execution mode. This design extends it rather than re-deriving
  it.

## Considered Options

Five decisions were evaluated independently and cross-validated. Each records
its alternatives; the reports are consolidated here.

### Decision A: Header names and value vocabulary

**Chosen: `## Delivery Preference: consolidated|atomic` and `## Tracking Level:
none|issues|issues-and-milestone`.**

Both names are taken from the vocabulary the PRD's Definitions section already
established, so the header a reader finds in CLAUDE.md and the term the
requirements use are the same word. Both sit in the existing noun-phrase family
and neither collides with the six shipped headers (D7).

*`## PR Delivery Preference:`, rejected.* The `PR` prefix reads as scoping the
preference to pull requests as artifacts, when what it configures is how work
arrives. It is also the longer of two names that carry identical information,
and the existing family favours the shorter form (`Planning Context`, not
`Planning Context Scope`).

*`## PR Grouping Policy:` widened to cover plan altitude, rejected.* It already
means something precise for coordinated efforts: how one repository's work
groups into pull requests within a multi-repository effort. Widening it to also
mean how a single-repository plan chooses its execution mode gives one header
two referents at two altitudes, which is the ambiguity D7 exists to prevent.

*Alternative value spellings, rejected.* The corpus splits into a capitalized
family (`Public|Private`) and a lowercase-hyphenated family (`optional|required`,
`coarsest-legal`, `auto|interactive`). Both new headers take multi-word values,
which places them in the second family. The PRD's spellings already conform.

**`## Reviewability Ceiling:` stays coordination-only.** An `atomic` repository
would naturally reach for it, and it resolves to a value defined nowhere in the
tree. Widening its declared scope while it has no definition would ship a knob
that reads as configurable and is not. Recorded as `assumed`; this is the
decision most likely to be revisited once the ceiling has a value.

### Decision B: How the validator expresses a conditionally required field

**Chosen: a new Plan-only check, `L09`, in the lifecycle family, registered as
`DraftTolerable` in `validate::posture_class()`. `FormatSpec` is untouched.**

The code lands in the `L` family rather than the `FC` family, and that is
load-bearing rather than cosmetic. `validate.rs` documents an invariant twice:
"the entire FC-family" is `AlwaysEnforced`. An `FC` code in the draft-tolerable
set would break it and force the invariant to be rewritten with an exception.
The `L` family already carries exactly this shape: `L06` is outline-AC
completeness, a single-document property that is a legitimate intermediate state
while a plan is in flight and must resolve before ready. A missing
`split_rationale` on a draft plan is the same kind of thing. `L08` is taken, so
the code is `L09`.

The check short-circuits before touching the filesystem: when `execution_mode`
is not `single-pr`, R13's first disjunct already holds and the field is required
with no CLAUDE.md read at all. Only a `single-pr` plan causes the resolver to
run, via `visibility::resolve_claude_md_header`, the same walker
`resolve_doc_visibility` and the prose-vocabulary parser already share.

*Extending `FormatSpec` with a conditional-required-fields mechanism,
rejected.* Every existing consumer of `FormatSpec` is answerable from parsed
frontmatter, and `formats()` builds all eight specs with zero I/O. Adding a
condition that reads CLAUDE.md means either giving the struct a field that can
perform filesystem reads, or threading repository context through `check_fc01`,
whose signature has no configuration parameter today. Either breaks the module's
document-local contract for all eight formats to serve one field of one (D2).

*Making the field unconditionally required with a sentinel for the exempt case,
rejected.* It satisfies `required_fields` as written, at the cost of putting a
new mandatory field on every single-pr plan, the common case, and of inventing
a sentinel value whose meaning ("this plan owes no reason") a reader has to
learn. D5 says an unstated preference should not add ceremony to the common
case.

*Splitting the check in two, document-local in `FormatSpec` and
configuration-dependent elsewhere, rejected.* It produces two findings for one
requirement, so a plan can fail half of R13, and a reader has to know which half
they are reading. The short-circuit in the chosen option gets the same
performance property without splitting the finding.

*Filing it in the `FC` family as `FC20`, rejected on review.* This was the
first choice, on the reading that the `L` family is about status-transition
legality across a document chain while this is a single-document property. That
reading does not survive contact with `L06`, which is single-document too. The
decisive fact is the other way round: `validate.rs` documents "the entire
FC-family" as `AlwaysEnforced` in two places, so an `FC` code in the
draft-tolerable set costs an invariant rewrite that the `L` family does not.

### Decision C: Work-item keys when tracking is `none`

**Chosen: a third `ISSUE_SOURCE` value, `plan_item`, with `m-<slug>` local ids,
built by reusing the `## Issue Outlines` parse and the local-id machinery
single-pr already uses.**

`process_multi_pr` has exactly two responsibilities that depend on GitHub:
pulling `#N` from the row's first cell, and pulling further `#N` tokens from the
Dependencies cell. Both are replaced by the outline-based resolution
`process_single_pr` already performs — sibling-outline references plus `Files`
ownership edges — so PRD R12's "no GitHub issue numbers as keys" falls out of
reusing existing logic rather than writing new logic. The id prefix pairs with
single-pr's `o-` and coordinated's `pr-`/`gate-`, so each mode's ids remain
visually distinct in a task graph.

*Reusing `plan_outline` verbatim, rejected.* The value is consumed downstream
as a signal about which execution model is in play, and single-pr's model is a
shared branch with one pull request. An issueless multi-PR plan shares the
parser but not the model, so reusing the value would make a downstream consumer
that branches on it wrong.

*Making the first cell a stable internal id in all modes and carrying the GitHub
number in a separate column — rejected, and this is the closest call.* It is the
more correct fix: it stops `#N` being the key everywhere rather than adding a
third scheme beside it. It is rejected because it changes the Implementation
Issues table's meaning in modes this feature does not otherwise touch, including
coordinated, and would require every committed multi-pr PLAN and every fixture
to migrate. Choosing the narrower fix is a deliberate trade: this design accepts
a third scheme now over a table migration whose blast radius exceeds the feature.
The more correct fix stays available and is named in Consequences.

*Not supporting issueless multi-PR at all, narrowing R8, rejected.* It would
remove exactly the combination the requester asked for by name: several pull
requests with the work items tracked in the document.

**What is lost.** `/work-on M<N>` has no milestone to resolve against when
tracking is `none`, and `/execute` declines `multi-pr` outright
(`skills/execute/SKILL.md`, Input Modes), so there is no path-driven fallback
either. No entry point can drive a `multi-pr` plus `none` plan even after this
lands. That is a capability gap rather than a lost ergonomic; see Consequences
for why the extraction change is still worth making, and for what closing the
gap would take.

### Decision D: Single-sourcing the split rule

**Chosen: extract `references/split-triggers.md`, cited by both P1 and the
Coarsest-Legal-Grouping Rule, parameterized by altitude the way
`issues-table.md` is parameterized by profile.**

The shared core names three branches:

1. **Hard Constraint**. a named, non-optional forcing condition: cross-repo
   landing order, a workflow that must reach the default branch before it can be
   invoked, a merge gate between steps.
2. **Incremental Value**. each resulting unit is independently useful to a
   reader who encounters it alone, per the existing value-confirmation guard,
   which is unchanged and still runs regardless of which branch produced the
   default (D3).
3. **Stated Preference**. the repository has said on the durable convention
   channel that it wants this shape: the plan-altitude `atomic` delivery
   preference, or the coordinated-altitude reviewability ceiling.

The third branch is the sentence that resolves the contradiction. Reviewability
is expressed through Stated Preference at both altitudes, so neither file has to
claim reviewability is or is not a legitimate reason — it is legitimate, and it
is a preference rather than a constraint.

The coordinated profile adds one branch that does not exist at plan altitude,
**Merge-Order Necessity**: a split required to break a contraction cycle in the
merge-order DAG. The old triggers "independently mergeable" and "independently
rollback-able" are retired as free-standing triggers and folded into Hard
Constraint's coordinated examples — a repository boundary or a landing-order
requirement is what makes a slice independently mergeable, so the old wording
named the symptom rather than the cause. That retirement is also what stops those
two from over-firing if lifted to plan altitude, which was the objection to
lifting the list verbatim.

*Leaving the two rules separate with cross-references — rejected on P4's own
text.* A cross-reference acknowledging the other rule does not stop either
file's trigger list from drifting; the enumerated list stays duplicated, which is
the defect the extraction exists to close.

*Rewriting P1 to carry all three branches inline and having
coordination-strategy.md cite P1, rejected.* It makes the coordination contract
depend on a principle written for single-repository work, and gives P1 a
profile-specific fourth branch it has no use for.

*Rewriting coordination-strategy.md to cite P1 plus its own fourth trigger —
rejected* for the mirror-image reason: the shared core ends up owned by whichever
file happened to be edited first, which is how the two drifted apart originally.

`skills/plan/SKILL.md` keeps a short always-loaded summary naming the three
branches, because Decision 6's reason for surfacing the rule there still holds.
The definitions and worked examples live only in the shared reference.

### Decision E: The approval-gate re-key

**Chosen: a prose-only re-key across every site that carries the old framing, and
an amendment to the existing decision record rather than a supersession.**

No code implements the gate. Nothing in `transition.rs` or `lifecycle.rs` reads
`execution_mode` to decide whether Draft→Active is automatic or human-approved.
But "no code implements it" is not the same as "no code mentions it," and an
earlier draft of this section conflated the two, enumerating four skill-prose
sites plus the decision record and calling that the whole surface. It is not. The
framing is also restated in Rust doc comments that no longer describe reality once
the gate is re-keyed:

| Site | Occurrences | Kind | Action |
|---|---|---|---|
| `skills/plan/SKILL.md` | 1 | live skill prose | re-key |
| `skills/plan/references/quality/plan-doc-structure.md` | 3 | live format contract | re-key |
| `skills/plan/references/phases/phase-7-creation.md` | 1 | live phase prose | re-key |
| `skills/plan/references/plan-format.md` | `### Transitions` | live format contract | re-key |
| `crates/shirabe-validate/src/lifecycle.rs` | 3 (52, 61, 764) | Rust comment | re-key, comment-only |
| `crates/shirabe-validate/src/transition.rs` | 4 (263, 469, 1960, 2011) | Rust comment | re-key, comment-only |
| `docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md` | 1 | Current design | re-key |
| `docs/designs/current/DESIGN-shirabe-artifact-decision-contract.md` | 4 | Current design | re-key |
| `docs/designs/current/DESIGN-roadmap-plan-standardization.md` | 7 | Current design | re-key, with Issue 8's amendment |
| `docs/decisions/DECISION-multi-pr-posture-detection-2026-06-06.md` | 2 | decision record | amend, do not rewrite |
| `crates/shirabe/tests/fixtures/golden/corpus/real/PLAN-roadmap-plan-standardization.md` | 1 | golden fixture | leave |

**Why the three `Current` designs are re-key and not leave.** An earlier draft of
this section marked them `leave`, reasoning that a design records what was decided
when it was written. That reasoning is wrong for this status, and the format
contract says so directly: the `Planned -> Current` directory move "is
load-bearing: it distinguishes designs that documented historical decisions from
designs that document the current architecture," and "a reader scanning
`docs/designs/current/` sees only currently-applicable designs"
(`skills/design/references/design-format.md`). A `Current` design that says the
gate is mode-keyed after the gate stops being mode-keyed is not a historical
record; it is a false statement about the present. Each of the three mentions the
gate only as collateral context while documenting a different subject, so the edit
is the same comment-only correction the Rust files get.

The `DECISION` record is genuinely point-in-time — that is what a decision record
is — so it is amended rather than rewritten. The golden fixture is pinned test
input; editing it would change what the test asserts.

`DESIGN-roadmap-plan-standardization.md` is re-keyed by **Issue 8**, not Issue 6,
because Issue 8 already edits that file for Decision 6's amendment. Note its line
577 sits in a Data Flow paragraph rather than in Decision 6, so the amendment does
not cover it and the re-key is a separate edit within the same issue.

Two properties of these sites defeat a single verification grep, and both were
found the hard way during review. The phrasing is not uniform — "human approval",
"human-approval", "human-approved", and at `phase-7-creation.md` "multi-pr-style
approval gate" with no "human" in it — so a pattern must cover all four forms.
And the mode is often named on a neighbouring line rather than the same one, so
filtering to lines containing `multi-pr` silently drops `transition.rs:1960` and
`:2011` and `lifecycle.rs:61`. A file-scoped completeness grep over
the six `re-key` files and a tree-wide discovery grep answer different questions
and are both required; either alone passes while real sites survive.

This also refutes the reading that the re-key is the same Phase 7 branch the
tracking work already touches. Phase 7 is one site of eleven, nine of which need editing.

Two combinations become reachable that the current transition tables have no row
for, and both need one:

| Combination | Draft to Active | Why |
|---|---|---|
| `multi-pr` + `none` | automatic | Nothing remote is created, so there is nothing for a human to approve before it appears |
| `single-pr` + `issues` | human-approved | Issues are created, which is the fact the gate exists to guard |

Stated as a rule rather than as two rows: activation is automatic when the
resolved tracking level is `none`, and human-approved otherwise. `execution_mode`
does not appear in the rule at all, which is the point.

*Superseding `DECISION-multi-pr-posture-detection-2026-06-06.md`, rejected.*
Its decision — that the gate is asymmetric, and why an asymmetric gate is right —
survives intact. Only its predicate changes, because the fact it keyed on
(multi-pr is when remote artifacts appear) stops being true. An amendment records
that precisely; a supersession would imply the original reasoning was wrong.

## Decision Outcome

The feature ships as two independently triggered capabilities riding one shared
mechanism, plus the record that makes either auditable.

The shared mechanism is the CLAUDE.md convention-header channel and its existing
resolution order. Two headers bind to it: `## Delivery Preference:` selects which
shape the planning workflow reaches for by default, and `## Tracking Level:`
selects which GitHub artifacts a plan's work items get. Neither reads the other,
and the tracking level is consulted independently of `execution_mode` whenever it
is stated; only its default is derived from the mode.

**The resolved tracking level is written into the PLAN's frontmatter**, as a
`tracking_level` field, at the moment the plan is authored. This is not
bookkeeping. Task extraction runs against a committed PLAN, potentially long
after authoring, and if it re-resolved the level from CLAUDE.md then a repository
that changed its header would change how an already-written plan's work items
key — silently, and after the fact. Persisting the resolved value makes
extraction a function of the document, which is the same property that makes
`split_rationale` worth writing down. It also gives `process_multi_pr` a
deterministic branch signal rather than forcing it to infer the level by
inspecting the table's shape.

The record is a `split_rationale` frontmatter field on the PLAN, holding free
text that names one of three branches — Hard Constraint, Incremental Value, or
Stated Preference — together with the specific justification. It is required
whenever the plan is not `single-pr`, or is `single-pr` in a repository whose
stated preference would have produced something else. `L09` checks its presence
as a notice while the pull request is a draft and an error once it is ready.

Those three branch names are not invented for the field. They are the branches of
a split rule extracted into `references/split-triggers.md` and cited by both the
plan-altitude principle and the coordination contract, which is what stops the
two from disagreeing about reviewability: it is a Stated Preference at both
altitudes.

An issueless multi-PR plan keys its work items on `m-<slug>` ids derived from the
plan's own Issue Outlines section, emitted as `ISSUE_SOURCE=plan_item`, reusing
the parser and the local-id algorithm the single-pr path already runs.

## Solution Architecture

### Components and where they change

| Component | Change |
|---|---|
| `references/fixes/claude-md-conventions.md` | Two new header entries, each with accepted values, default, and precedence order |
| `references/split-triggers.md` | New. Shared core (three branches) plus plan and coordinated profiles |
| `references/workflow-principles.md` | P1 cites the shared reference instead of enumerating; the reviewability contradiction resolves |
| `references/coordination-strategy.md` | The Coarsest-Legal-Grouping Rule cites the shared reference; keeps Merge-Order Necessity as its profile-specific branch |
| `skills/plan/SKILL.md` | Execution Mode Decision reads the delivery preference; keeps a three-branch summary; gate prose re-keyed |
| `skills/plan/.../phase-3-decomposition.md` | Step 3.6 resolves the preference before recommending; emits the branch name for the record |
| `skills/plan/.../phase-7-creation.md` | Issue and milestone creation gated on the resolved tracking level rather than on `execution_mode`; gate prose re-keyed |
| `skills/plan/references/plan-format.md` | `split_rationale` documented; the issueless multi-pr table row shape documented; the `### Transitions` section re-keyed off `execution_mode` onto whether the transition creates issues |
| `skills/plan/references/quality/plan-doc-structure.md` | Status-transition table re-keyed the same way; one of the `re-key` rows in Decision E's site table |
| `skills/plan/scripts/plan-to-tasks.sh` | `process_multi_pr` branches on the PLAN's `tracking_level` field; the `none` path reuses the outline parse and emits `plan_item` |
| `skills/plan/references/plan-to-tasks-contract.md` | Third source-var scheme documented |
| `crates/shirabe-validate/src/lifecycle.rs` | `L09` implemented alongside `L06`, whose single-document draft-tolerable shape it follows; module-doc comment restating the gate as mode-keyed re-keyed |
| `crates/shirabe-validate/src/validate.rs` | `L09` added to `posture_class`'s `DraftTolerable` arm; the two doc comments enumerating that set updated to name it; `posture_class_classifies_lifecycle_codes` extended |
| `crates/shirabe-validate/src/transition.rs` | Comment-only: two sites restating the gate as mode-keyed |
| `docs/decisions/DECISION-multi-pr-posture-detection-2026-06-06.md` | Amended: predicate re-keyed, decision preserved |
| `docs/designs/current/DESIGN-roadmap-plan-standardization.md` | Decision 6 amended: the default is now preference-conditional |

### Data flow — resolving a plan's shape

```
/plan
  |
  +-- resolve Delivery Preference   (flag > CLAUDE.md header > consolidated)
  |
  +-- step 3.5a  value-confirmation guard          [unchanged, always runs]
  |
  +-- step 3.6   recommend execution_mode
  |                using the resolved preference,
  |                and select the branch that produced it
  |
  +-- emit  execution_mode + split_rationale       [record written here]
  |
  +-- resolve Tracking Level        (flag > CLAUDE.md header > mode-derived)
  |
  +-- phase 7    create issues / issues+milestone / nothing
                 approval gate keys on "will create issues"
```

### Data flow — task extraction

```
plan-to-tasks.sh
  |
  +-- execution_mode == single-pr      -> process_single_pr  -> ISSUE_SOURCE=plan_outline, o-<slug>
  +-- execution_mode == coordinated    -> process_coordinated -> pr-/gate- nodes
  +-- execution_mode == multi-pr
        |
        +-- tracking_level != none     -> process_multi_pr    -> ISSUE_SOURCE=github, #N
        +-- tracking_level == none     -> outline parse       -> ISSUE_SOURCE=plan_item, m-<slug>
                                          (read from the PLAN, not re-resolved
                                           from CLAUDE.md)
                                          (shared with single-pr's parser
                                           and local-id algorithm)
```

### The check

`L09` runs only for `Plan` documents. Its logic, in order:

1. If `execution_mode == "single-pr"`, resolve the repository's delivery
   preference via `resolve_claude_md_header`. If the preference is
   `consolidated`, the plan matches and the check passes with no further work.
   If it is `atomic`, the plan departed and the field is required.
2. Otherwise the plan is not `single-pr` and the field is required
   unconditionally, with no filesystem read.
3. When required, the field must be present, non-empty, and name one of the
   three branches.

The ordering matters: the common case — a non-single-pr plan — never reads
CLAUDE.md, and the case that does read it is the one where the answer cannot be
derived from the document.

## Implementation Approach

Four batches. The sequencing is driven by what each batch unblocks, not by
file locality.

**Batch 1: the record, its emitter, and its check.** `split_rationale`
documented in `plan-format.md`, `L09` implemented in `lifecycle.rs` and added to
the `DraftTolerable` set, `references/split-triggers.md` authored with its three
branches and two profiles, P1 and the Coarsest-Legal-Grouping Rule repointed to
cite it, and step 3.6 in `phase-3-decomposition.md` taught to emit the branch
name it selected.

The emitter belongs in this batch rather than in Batch 2. Without it the batch
would ship a check for a field nothing writes, and every plan authored between
Batch 1 and Batch 2 would carry a finding its author had no supported way to
clear. With it, Batch 1 stands alone and delivers the auditability the feature
exists for: a repository that stops here gets plans that record why they are
shaped as they are, using the two branches that exist before any preference
does. Only the third branch, Stated Preference, waits on Batch 2, and `L09`'s
departure predicate is inert until there is a header to depart from.

**Batch 2 — The delivery preference.** The `## Delivery Preference:` header, its
registry entry, step 3.6's resolution, and `L09`'s departure branch (which needs
the header to exist before it can read one). Depends on Batch 1 for the branch
vocabulary the record names.

**Batch 3 — The tracking level.** The `## Tracking Level:` header, its registry
entry, Phase 7's gating, and the approval-gate prose re-key across its five
sites. Independent of Batch 2 — it touches a different phase and a different
header — so it can run in parallel with it if a reviewer wants, but it depends on
Batch 1 for nothing and could equally precede Batch 2.

**Batch 4 — Issueless task extraction.** `plan-to-tasks.sh`'s `none` path,
the contract's third variable scheme, and the test surface. Depends on Batch 3,
because the tracking level has to be resolvable before extraction can branch on
it. This is the batch with the most implementation risk and the least
documentation surface, which is why it is last: everything above it is
verifiable without it.

The decomposition is horizontal by capability rather than vertical by file
because the batches have genuinely different reviewers — a documentation change,
a skill-prose change, a Rust change, and a shell change — and because Batch 1
delivers standalone value: a repository that stops there still gets plans that
record why they are shaped as they are.

## Security Considerations

The feature reads new configuration, writes a new free-text field, derives new
identifiers, and gates the creation of remote artifacts. Each is considered.

**Untrusted configuration read.** Both headers are read from CLAUDE.md, which is
repository content and therefore attacker-controlled in a fork or an untrusted
branch. The mitigation is that both values are matched against closed
enumerations and an unrecognized value falls through to the default rather than
being used — the same treatment `parse_visibility_header` already gives an
unrecognized visibility. Neither value is interpolated into a path, a command, or
a URL; each selects a branch. `resolve_claude_md_header` stops at the first
`.git` boundary walking up, so a CLAUDE.md outside the repository cannot be
reached. It resolves to the nearest CLAUDE.md or CLAUDE.local.md above the
document rather than to the repository root specifically, which means L09's
departure predicate can differ by directory within one repository. That is the
same resolution visibility detection already uses and is inherited rather than
introduced, but L09 is a new consumer of it and the property is stated here so
a reader does not assume repository-root semantics.

**Free-text field reaching a committed artifact.** `split_rationale` holds author
prose and is written into PLAN frontmatter. It is never interpolated into an
emitted shell command, a branch name, or a path — `L09` reads it and checks it,
and no consumer executes it. This is the property that makes free text acceptable
where the PRD's R20 chose it over an enumeration; had the value reached a
command, the enumeration would have been required regardless of vocabulary
instability.

**Derived identifiers reaching task names.** `m-<slug>` ids are derived from
outline heading text, which is author-controlled. They are produced by the same
slugify, collision-suffixing, and 64-character truncation the single-pr path
already applies to `o-<slug>`, so the identifier surface is unchanged in kind and
inherits the existing bounds. No new characters become reachable.

**Remote-artifact creation moves behind a preference.** A repository can now
configure `## Tracking Level: none`, which suppresses issue creation. This is a
reduction in what the workflow does remotely, not an expansion, and it cannot be
used to cause creation that would not otherwise happen — `issues` and
`issues-and-milestone` produce exactly what `multi-pr` produces today. The
approval-gate re-key preserves the property that a human approves before remote
artifacts appear; it makes the gate track the artifacts rather than a proxy for
them, which closes rather than opens a case (`single-pr` + `issues` would
otherwise create artifacts through the automatic path).

**Residual risk accepted.** `L09` confirms a reason is present and names a
branch; it cannot confirm the reason is true. A plan asserting a hard constraint
that does not exist validates clean. The check is an auditability mechanism, not
an authorization one, and no security property depends on the field's accuracy.

## Consequences

### Positive

- A merged plan answers why it has its shape, and the answer is checkable rather
  than dependent on the author having remembered to write it.
- Two legitimate delivery cultures are both expressible, and the team whose
  reason is reviewability stops having to describe it as incremental value.
- All six combinations of delivery shape and tracking level become reachable,
  including the two the requester named specifically: several pull requests
  without issues, and issues without a milestone.
- Two files stop contradicting each other about reviewability, and the rule they
  disagreed about gains a single source that P4's own examples already model.
- The common case gets cheaper to validate, not more expensive: `L09`
  short-circuits before any filesystem read for every non-single-pr plan.

### Negative, with mitigations

- **A third work-item keying scheme.** `plan_item` sits beside `github` and
  `plan_outline` rather than replacing the `#N` dependency that made it
  necessary. *Mitigation:* the narrower fix was chosen deliberately over the
  table migration, and the more correct fix — a stable internal id in the first
  cell in all modes, with the GitHub number in its own column — is recorded here
  so a later change has a starting point rather than rediscovering it.
- **No entry point can drive an issueless multi-PR plan.** `/work-on M<N>` has no
  milestone to resolve against, and `/execute` declines `multi-pr` outright
  (`skills/execute/SKILL.md`, Input Modes), so there is no path-driven fallback
  either. This is a capability gap, not a lost ergonomic, and an earlier draft of
  this section understated it by claiming the author could drive the plan by path
  "the way `/execute` already drives single-pr and coordinated plans" — `/execute`
  does not drive multi-pr at all. *Mitigation:* none within this design's scope.
  The extraction change is still worth landing, because its acceptance surface is
  the emitted task graph rather than an orchestrator run, and because the graph is
  the input any future entry point would consume. Building that entry point — a
  `/work-on` dispatcher branch that reads the graph plus some non-GitHub
  completion signal — is separate, currently unowned work, and this design does
  not claim it.
- **`L09`'s departure branch reads live repository configuration.** A repository
  that changes its delivery preference after a plan is authored can see the
  finding appear or disappear without the plan changing. *Mitigation:* the
  finding is draft-tolerable, so the window in which it matters is the window in
  which the plan is being edited anyway; and the record, once written, is not
  removed by a preference change.
- **The reviewability ceiling stays undefined.** An `atomic` repository can say
  it wants small increments but not how small. *Mitigation:* the preference is
  useful as a posture without a threshold, and the ceiling's definition is named
  in the PRD's Out of Scope rather than silently assumed.
- **Two decision records and one design need amending.** The posture-detection
  record's predicate and Decision 6's default both change. *Mitigation:* both are
  amendments rather than supersessions, and both are listed in the component
  table so the plan cannot omit them.
