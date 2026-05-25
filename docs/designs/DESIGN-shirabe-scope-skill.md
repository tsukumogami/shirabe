---
status: Proposed
upstream: docs/prds/PRD-shirabe-scope-skill.md
---

# DESIGN: shirabe-scope-skill

## Status

Proposed

## Context and Problem Statement

`/scope` is the second parent skill landing in shirabe. The first
parent, `/charter`, shipped against the strategic chain
(`/vision → /strategy → /roadmap`) under the shared design
`docs/designs/current/DESIGN-shirabe-progression-authoring.md`,
which lifts the parent-skill pattern v1 into a contract surface
that future parents bind to without re-deriving. The technical
problem this design solves is binding the same pattern surface to
the tactical chain (`/brief → /prd → /design → /plan`) — a chain
whose shape diverges from the strategic chain at three load-
bearing points the pattern doc has no v1 language for.

The asymmetries the design must absorb without breaking the v1
pattern contract:

- **Two settled-upstream boundaries instead of one.** `/charter`'s
  re-evaluation exit fires at one point (an existing Accepted
  STRATEGY). `/scope` fires at two — an Accepted PRD and an
  Accepted DESIGN, with separate Decision Record sub-shapes and a
  resume-ladder ordering rule (DESIGN above PRD when both exist).
  The pattern's `re-evaluation` exit must gain a `boundary:`
  discriminator without changing the three-exit count.
- **No Phase-N Reject finalization on `/prd` or `/design` today.**
  `/charter`'s rejection sub-shape rides on `/strategy`'s Phase 5
  Reject. The tactical-chain children have no analogous reject
  contract. Either the rejection sub-shape silently disappears in
  `/scope` (an asymmetry inside the pattern contract that has
  nothing to do with the strategic/tactical distinction), or
  `/prd` and `/design` grow Phase-N Reject contracts as `/scope`
  prerequisites. SE7 takes the latter path; this design enumerates
  the contract extensions to both children.
- **A terminal child with two output modes.** `/plan`'s `single-
  pr` mode produces a self-contained PLAN doc; `multi-pr` mode
  produces a PLAN doc plus a GitHub milestone with issues. The
  pattern's `planned_chain`/`chain_ran`/`chain_skipped` triad
  doesn't capture output-mode selection; `/scope`'s state file
  needs a new `plan_execution_mode:` field so re-entry against an
  Active PLAN reads the correct surface.

`/prd`'s invocation gate sits on top of those three. `/charter`'s
three gate vocabularies (EITHER-signal, ALWAYS, shape-dependent)
don't fit `/prd` cleanly. `/prd` is mandatory unless an Accepted
PRD already exists; that auto-skip is real and load-bearing. The
pattern's gate vocabulary needs a fourth entry
(Mandatory-with-auto-skip) so the gate is named honestly inside
the pattern doc, not jammed into a misnamed third gate.

System boundaries touched by this design:

- `skills/scope/SKILL.md` (new) — the loadable skill body, with
  the seven pattern-level structural elements R1 names and a body
  prose section per `/scope`-specific requirement (R2, R4-R8,
  R15-R23).
- `references/parent-skill-pattern.md` (edit) — add the fourth
  gate type (Mandatory-with-auto-skip) to the gate vocabulary,
  with `/prd`'s gate as the canonical example.
- `references/parent-skill-state-schema.md` (edit) — add the
  `boundary:` and `plan_execution_mode:` conditional-field
  semantics (with I-5 absent-when-ungated bindings).
- `references/parent-skill-resume-ladder-template.md` (edit) —
  document the two-boundary re-evaluation ordering rule (DESIGN
  above PRD) and the PLAN-status-aware refuse-and-redirect rows
  (Active → `/work-on`, Done → `/release`).
- `references/parent-skill-child-inspection.md` (no edit needed)
  — the per-parent surface table already covers doc-emitting
  children; `/scope`'s four children are all doc-emitting and
  fall under the existing row.
- `references/parent-skill-worktree-discipline.md` (new) — a
  top-level reference that captures R21's worktree-staleness
  trigger condition as shared infrastructure both `/charter` and
  `/scope` cite. `/charter`'s SKILL.md gains a follow-up reference-
  table citation in a back-edit.
- `skills/prd/SKILL.md` + phase references (edit) — ship the
  Phase-N Reject finalization contract at `/prd`'s Phase 4 (per
  R23 and AC30a).
- `skills/design/SKILL.md` + phase references (edit) — ship the
  Phase-N Reject finalization contract at `/design`'s Phase 6
  (per R23 and AC30b).
- `skills/scope/evals/evals.json` (new) — eval scenarios covering
  US-1 through US-6 (per R18 and AC24b).
- Workspace and shirabe `CLAUDE.md` — surface `/scope` entry
  triggers (R17a, R17b); shirabe's CLAUDE.md gains a "Tactical
  Chain Entry: /scope" section paralleling the existing
  "Strategic Chain Entry: /charter" section.

Existing architecture this design inherits without alteration:

- The two-layer contract (Layer 1 semantic invariants I-1 through
  I-7; Layer 2 reference implementation under the v1 substrate
  identifiers `wip-yaml-md` and `single-team-per-leader-no-
  nested`) carries verbatim from
  `DESIGN-shirabe-progression-authoring.md`. `/scope` v1 binds
  the same substrates.
- The pattern's seven semantic invariants stand as `/charter`
  ratified them; `/scope` adds gate vocabulary and one new
  top-level reference but does not edit the invariants. I-6
  (cross-branch resume) remains the named-but-unsatisfied
  invariant the amplifier-layer migration closes; `/scope`'s
  state file is branch-coupled in v1.
- The team-lead operating discipline (the 5-step sleep-check-
  nudge loop encoded as I-7) binds `/scope` at the child-
  dispatch layer; `/scope` v1 is single-agent at its own layer
  (no peers dispatched at the `/scope`-itself layer), so the
  binding is vacuous at the parent-itself layer and concrete at
  the child-skill dispatch layer (each `/brief`, `/prd`,
  `/design`, `/plan` invocation is a dispatch in the discipline
  sense).

## Decision Drivers

The drivers below combine PRD-derived constraints (from
`PRD-shirabe-scope-skill.md` Requirements and Acceptance
Criteria) with implementation-specific constraints the PRD does
not surface explicitly. Drivers are ordered from most-binding to
least.

1. **Pattern contract symmetry across both parent skills.** The
   parent-skill pattern v1 has only one ground-truth example
   (`/charter`). `/scope` shipping is what ratifies the pattern
   for the next two parents (`/work-on` migration, future
   tactical parents). Any asymmetry left unaddressed in `/scope`
   compounds across SE8/SE9/SE12. Per PRD Decision 1, the design
   chooses full symmetry over narrow shipping: the rejection
   sub-shape, the Mandatory-with-auto-skip gate, the worktree-
   discipline reference all land at the pattern level.

2. **L9 pattern-level requirement-tagging traceability.** The PRD
   tags every requirement `[pattern-level]` or `[/scope-
   specific]` so reviewers can grep-verify pattern-doc edits.
   The design MUST mirror this distinction in its Solution
   Architecture: components labeled as pattern-doc edits cover
   the eleven pattern-level requirements (R1, R3, R9, R10, R11,
   R12, R13, R14, R17a, R18, R19); components labeled as
   `/scope` body slots cover the fifteen `/scope`-specific
   requirements (R2, R4, R5, R6, R7, R7.5, R8, R15, R16, R16.5,
   R17b, R20, R21, R22, R23). 1:1 traceability is the design's
   reviewer-checkability surface.

3. **Two-substrate respect for the v1 core layer.** `/scope`
   ships against the existing core-layer substrates:
   `storage_substrate: wip-yaml-md` (state at
   `wip/scope_<topic>_state.md` as YAML-in-.md), `team_primitive:
   single-team-per-leader-no-nested` (no nested teams; inline
   decision walks; upfront upper-bound roster). Implementation
   choices that would require amplifier-layer substrates are
   out of scope for v1.

4. **Six user stories as the eval surface.** Per R18 and AC24b,
   `skills/scope/evals/evals.json` MUST cover US-1 through US-6.
   The design's architecture must make each story
   eval-reachable: the chain-proposal output (R7.5) must contain
   literal-grep-checkable substrings, the state file's
   `exit:`/`boundary:`/`decision_record_sub_shape:` fields must
   be observable post-run, the abandonment-forced HTML-comment
   marker must be schema-compliant.

5. **Cross-boundary resume across four child positions plus three
   PLAN statuses plus DESIGN's directory-move lifecycle.** The
   resume ladder (R11) is the most complex pattern component
   `/scope` ships against. The ladder must consult the state
   file, four child snapshots (status + content-hash dual-check
   per R10), four `wip/{child}_<topic>_*` partial-run signals,
   and emit refuse-and-redirect rows for PLAN-Active (→
   `/work-on`) and PLAN-Done (→ `/release`). The ladder is the
   surface where most contract-violation bugs would surface; the
   design must keep the row ordering reviewable.

6. **Manual fallback as first-class steady-state behavior.** R13
   binds: a child invoked directly outside `/scope` MUST leave
   identical externally-visible surfaces. The design must NOT
   add hooks, marker files, or coupling that would distinguish
   in-chain from out-of-chain invocations on the durable
   artifact. Child-snapshot drift detection (status OR
   content-hash differs) is the only allowed signal the parent
   reads on resume.

7. **PRD-defined design-altitude open questions land in this
   doc.** Five questions in the PRD's "Questions Deferred to
   Design" section (Phase-N Reject placement; R6 shape-predicate
   evaluation mechanism; PLAN-status-aware signaling to `/plan`;
   the worktree-discipline reference's exact prose; cross-
   boundary state-snapshot semantics) are explicit design-team
   territory. Each must be resolved here, not punted.

8. **Tactical chain spans longer than strategic.** Four children
   per full run vs three; requirements/design churn faster than
   thesis. Two implementation-specific consequences: (a)
   `--max-rounds=N` default of 5 instead of `/charter`'s 3 (per
   R16.5), and (b) the worktree-staleness check trigger fires
   before each Phase 2 child invocation (per R21) rather than
   once per parent invocation.

9. **Public-visibility content governance.** shirabe is a public
   repo. The design MUST NOT reference private resources, pre-
   announcement features, or competitive material. The upstream
   PRD is public; this design is public; both follow the
   public-content discipline shipped at `skills/public-
   content/SKILL.md`.

10. **wip-hygiene rule.** wip/ files are non-durable and cleaned
    before merge. The design MUST NOT reference any wip/... path
    from frontmatter, prose, or code comments that survives the
    cleanup commit. Phase 6's reference-hygiene grep enforces
    this; the design itself must self-comply.

## Considered Options

The design decomposes into eight decision questions, each with
two or three viable alternatives. The questions are independent
in the sense that the choice for one does not constrain the
choice for any other, with one exception flagged below: D3
(parent-to-child suppression signaling) and D8 (pattern-doc edit
surface) make complementary edits to the same pattern reference,
and D3's recommendation extends D8's pattern-doc edit set with
one additional pattern-level convention. The Decision Outcome
section addresses the merge explicitly.

### Decision 1: Phase-N Reject contract placement on /prd and /design

PRD R23 names a Phase-N Reject finalization contract on `/prd`
(Phase 4) and `/design` (Phase 6) that adds an Accept / Reject /
Continue-revising gate at the child's existing finalization step.
On Reject the child runs `git rm` against the durable artifact,
cleans up `wip/<child>_<topic>_*` files, and commits
`docs(<type>): discard <TYPE> draft for <topic>`. The PRD
defers to design the question of where exactly the gate inserts
into each child's existing finalization phase, whether it
replaces or augments the existing approval prompt, and (for
`/design` only) how it orders against the `docs/designs/` →
`docs/designs/current/` directory move on accept.

The placement question is contract-shaping rather than
cosmetic: the gate's location determines what is on disk when
the gate fires (is the artifact already committed? is it in the
"current" subdirectory?) and what the discard commit removes.
The contract surface must be identical between in-chain
(`/scope`-invoked) and out-of-chain (direct invocation) per
AC30c, so any choice must work in both contexts.

Key constraints:

- `/strategy` Phase 5.2 already ships an analogous 3-option gate
  (Accept / Reject-with-Reject-Pass-thru / Continue-revising);
  the `/scope`-prerequisite contracts on `/prd` and `/design`
  should mirror that precedent unless a tactical-chain
  asymmetry forces divergence.
- The `docs/designs/` → `docs/designs/current/` move belongs to
  the Planned → Current transition driven by `/plan` and
  post-implementation cascade — NOT Phase 6 acceptance. The
  PRD's framing of "ordering vs the directory move" rests on a
  misunderstanding of the lifecycle that this design resolves
  in favor of the canonical lifecycle: `/design` Phase 6
  acceptance flips status to `Accepted` without moving the
  file.
- AC30a and AC30b name the `git rm` and commit messages
  verbatim; any placement choice must produce those exact
  artifacts.

#### Chosen: Option A — Augment Existing Gates with a Third Option

`/prd` Phase 4 step 4.5's existing 2-option AskUserQuestion
(Approved / Needs iteration) becomes a 3-option AskUserQuestion
(Approved / Reject / Continue-revising). The handler for the
existing Approved branch stays unchanged. The Continue-revising
branch is renamed from "Needs iteration" but preserves identical
behavior. The new Reject branch is parallel to the existing two
branches: it asks the author for a one-sentence rejection
rationale (logged in the discard commit body), runs `git rm
docs/prds/PRD-<topic>.md`, removes `wip/prd_<topic>_*.md`, and
commits `docs(prd): discard PRD draft for <topic>` with the
rationale in the body.

`/design` Phase 6 step 6.7's existing 2-option AskUserQuestion
(Approved / Needs iteration) likewise becomes a 3-option gate.
The Reject branch runs `git rm docs/designs/DESIGN-<topic>.md`
(the file is still in `docs/designs/` at this point because the
Planned → Current move hasn't happened), removes
`wip/design_<topic>_*.md` and `wip/research/design_<topic>_*.md`,
and commits `docs(design): discard DESIGN draft for <topic>`.

The 3-option choice fires identically in-chain and out-of-chain
— the gate is the child's own, not `/scope`'s. On in-chain
Reject, control returns to `/scope`, which writes the
rejection-sub-shape Decision Record (per D5's frozen-snapshot
rule referencing the discard commit SHA, not the absent
artifact). On out-of-chain Reject, the discard commit is the
durable trace and no Decision Record is written (AC30c).

This works because the existing finalization step is already an
AskUserQuestion presenting binary choices; growing it to three
options is the minimal-surface-area change. The gate fires
after the child has produced a Draft artifact ready for
human-decision review — exactly the point at which "reject the
draft entirely" is a meaningful option. The artifact is on
disk and tracked at that point, so `git rm` works
deterministically.

#### Alternatives Considered

**Option B: Insert a new standalone Phase-N Reject Gate step
BEFORE the existing approval step.** A new step 4.4 (`/prd`) or
6.6 (`/design`) asks Continue vs Reject; the existing approval
step (4.5 / 6.7) fires only if Continue was chosen. Rejected
because the new step duplicates the AskUserQuestion surface
without adding evaluation. The author already has to evaluate
the artifact at the approval step; adding a pre-gate forces a
second evaluation moment without new evidence. Also breaks the
1:1 mapping to `/strategy` Phase 5.2's precedent (which is a
single 3-option gate, not a sequence of two gates).

**Option C: Reorder /design Phase 6 — move Commit and PR
AFTER the approval gate, then augment.** Currently `/design`
Phase 6 commits the design before the approval prompt fires
(step 6.6 Commit / 6.7 Approve). Option C swaps the order so
the commit happens after Approve, eliminating the need for `git
rm` on Reject (the design file would never have been committed).
Rejected because the swap creates a workflow gap where the
in-progress design exists only as a working-tree change for the
duration of the approval prompt — meaning a session interruption
loses the draft. The existing commit-then-approve ordering
preserves the Draft as a durable artifact across interruptions;
adding `git rm` on Reject is a smaller cost than losing
durability.

### Decision 2: R6 shape-predicate evaluation mechanism

PRD R6 names three shape predicates that `/scope` Phase 1
evaluates against the just-produced or existing PRD to decide
whether `/design` fires (shape-dependent gate). The predicates
are: (P1) the PRD's Requirements section contains 2+
requirements that imply architectural alternatives; (P2) the PRD
references components, interfaces, or data flows not yet defined
in the repo; (P3) the PRD's complexity assessment classifies
Complex per `/design`'s complexity table. The PRD specifies the
predicates but defers the evaluation mechanism to design — does
the agent walk a structured checklist during Phase 1 discovery,
respond to a structured prompt, or delegate to a sub-decision
skill?

Key constraints:

- `team_primitive: single-team-per-leader-no-nested` forbids
  spawning sub-decision teams inside Phase 1 (driver 3).
- The chain-proposal output (R7.5) must contain per-predicate
  reasons authors can review (AC9 names the chain proposal as a
  literal-substring-checkable surface).
- The mechanism must reproduce across runs against the same
  PRD (drivers 4 and 7).

#### Chosen: Option A — Structured Checklist Walk During Phase 1 Discovery

The R6 evaluation mechanism is a structured checklist walk
documented at `skills/scope/references/phases/phase-1-discovery.md`.
The walk inspects the PRD's named sections in order:

1. **P1 (architectural-alternatives count)**: parse the
   Requirements section, count requirements that imply choice
   between architectural alternatives or multiple components.
   The walk includes 3-4 worked examples in the phase reference
   showing positive cases (e.g., "the PRD says SHALL use TLS
   for transport; cipher suite to be decided" → 1 architectural
   alternative) and negative cases (e.g., "the PRD says SHALL
   log to stderr at INFO level" → 0 alternatives).
2. **P2 (new-component references)**: scan the PRD body for
   component-noun-phrases ("a new daemon", "a webhook
   receiver", "the X service") and check each against the
   current repo's component inventory (file paths matching
   `skills/*`, `recipes/*`, etc.). Positive when the
   noun-phrase has no corresponding repo entry.
3. **P3 (Complex classification)**: read the PRD's complexity
   assessment block (the table cited at
   `skills/design/SKILL.md:198-203`) if present; if absent,
   evaluate the four criteria (files-to-modify count, new test
   infrastructure, API surface changes, cross-package work)
   against the PRD body.

Each predicate emits a per-predicate verdict (`fires` /
`does-not-fire`) and a one-line reason. The reasons feed
directly into the chain-proposal output (R7.5): when one or more
predicates fires, the chain proposal includes `/design` with the
firing predicate's reason; when no predicate fires, the chain
proposal records `/design` in `chain_skipped` with the per-
predicate verdicts as the skip reason.

This is recommended because the walk is pattern-coherent with
`/charter`'s shape-dependent gate evaluation (both parent
skills evaluate shape-dependent gates inline during Phase 1
against named upstream-artifact sections), it costs zero
per-invocation overhead beyond the existing Phase 1
conversation, and it produces the chain-proposal one-liner as
its primary output rather than a derivative summary. Worked
examples in the phase reference bound the interpretive drift
P1 most exposes.

#### Alternatives Considered

**Option B: Delegate to a sub-decision skill.** `/scope` Phase
1 invokes `/decision` against an R6-shape-predicate
question, gets back a structured verdict, uses it. Rejected
because (a) the team-primitive constraint forces
`/decision` to run inline in the same agent context anyway, so
the framing as "sub-skill delegation" is misleading; (b)
`/decision` is overpowered for a 3-predicate evaluation — its
adversarial bakeoff and cross-examination phases are designed
for irreversible 3+ option choices, not for a "fires / doesn't
fire" verdict on each predicate; (c) the chain-proposal output
needs per-predicate reasons but `/decision`'s synthesis produces
a unified recommendation, not a structured verdict per
predicate.

**Option C: Pure structured prompt to the agent without a
checklist walk.** The agent receives an unstructured prompt
("evaluate R6 against this PRD") and responds freely. Rejected
because (a) reproducibility on P1's interpretive classification
is much worse without the walked structure — the agent's
free-form answer varies across runs; (b) the chain-proposal
output gains no canonical reason format; (c) the lack of worked
examples means new authors writing PRDs cannot calibrate
expectations for the gate.

### Decision 3: Parent-to-child resume-suppression signaling

PRD R11's last paragraph requires that when `/scope` re-enters
against an existing Draft child doc (BRIEF, PRD, DESIGN, PLAN)
and decides upfront that the re-entry is a fresh chain (not a
re-evaluation exit), `/scope` MUST signal the child to suppress
its own status-aware re-entry prompt — otherwise the child's
"Draft exists → Offer to continue or start fresh" prompt
hijacks `/scope`'s flow. The PRD names this generalization
across four children; the question is which mechanism `/scope`
SHALL use.

The decision sits at the intersection of three load-bearing
contracts: (a) the pattern-doc rule "parents do not extend
children's input surfaces" (L13 in the team-lead's framing,
named in `parent-skill-pattern.md` under Conditional Feeder
Invocation Shape) forbids adding flags or arguments to children;
(b) R14's child-isolation rule forbids `/scope` from inspecting
child internals; (c) `/charter` ships TODAY with a
`--parent-orchestrated` flag in `phase-resume.md` that
anticipates child-side recognition, but no shirabe child
currently recognizes that flag.

The honest framing surfaced during cross-validation: `/charter`'s
`--parent-orchestrated` flag IS in tension with L13 as written.
The pattern-doc literally says "SHALL NOT add flags or
arguments to the child". Either L13 is amended to permit a
pattern-level suppression flag (chosen here), or `/scope`
works strictly within L13 as written (the topic-slug-only or
refuse-and-restart alternatives).

#### Chosen: Option A — State-File Sentinel via parent_orchestration: Block, with L13 Amended at the Pattern-Doc Layer

`/scope`'s state file at `wip/scope_<topic>_state.md` gains a
new conditional block:

```yaml
parent_orchestration:
  invoking_child: <child-name>          # brief | prd | design | plan
  suppress_status_aware_prompt: true
  rationale: <fresh-chain | revise>
```

`/scope` writes the block immediately BEFORE invoking the
child; the block is cleared (entire `parent_orchestration:` key
removed from the state file) immediately AFTER the child
invocation returns. The block is ephemeral within the chain
and never persists across chain boundaries — it is gated by
"in-flight child invocation", an even more granular conditional
than the `exit:`-gated fields per I-5.

The child reads the sentinel by checking for the parent's state
file at the well-known path `wip/scope_<topic>_state.md` and
inspecting the `parent_orchestration:` block at child Phase 0
(immediately on invocation, before consulting its own resume
ladder). When the sentinel is present and names the invoking
child, the child suppresses its own status-aware re-entry
prompt and treats the run as a fresh invocation. When the
sentinel is absent (standalone invocation), the child's normal
resume ladder fires unmodified.

The L13 rule in `references/parent-skill-pattern.md` is amended
in SE7. The new wording (replacing the existing "Parents do
not extend children's input surfaces" prose):

> Parents do not extend children's input surfaces with
> parent-specific flags or arguments. A pattern-level
> suppression signal — defined once in the pattern-doc, read
> by all parents, and recognized by all children identically —
> is permitted as a parent-orchestration primitive. The signal
> mechanism is the parent's state file's
> `parent_orchestration:` block at a substrate-defined path;
> children consult it as a pattern-level convention, not as a
> per-parent API.

The amendment keeps L13's intent (no per-parent flags, no
coupling to a specific parent's API) while permitting a uniform
pattern-level convention every parent uses identically. The
signal is NOT a `/scope`-specific flag and NOT a `/charter`-
specific flag; it is a pattern-doc-defined convention.

This is recommended because:

1. **The L13 amendment is honest, not weaseling.** The
   pattern-doc already grows new vocabulary for `/scope`'s
   shape (Mandatory-with-auto-skip gate, `boundary:`,
   `plan_execution_mode:`); the `parent_orchestration:`
   sentinel is one more entry on the same list. The
   alternative — leaving `/charter`'s `--parent-orchestrated`
   flag as an unmarked L13 exception — bakes in an asymmetry
   the next reviewer trips on.

2. **The filesystem substrate matches L13's spirit.** L13's
   stated concern is coupling the parent to the child's API:
   "Extending the child's input surface would couple the
   parent to the child's API and break the moment the child
   refactors its inputs." The state-file sentinel does NOT
   touch the child's `$ARGUMENTS`, flag parser, or env-var
   consumption. The child reads a file at a known path; that
   path is defined at the pattern-doc layer. If a child
   refactors its `$ARGUMENTS`, the sentinel still works.

3. **R14 child-isolation is unaffected.** R14 says the parent
   reads only the child's durable externally-visible surface
   — but it does NOT prohibit the CHILD from reading the
   parent's externally-visible state file. The asymmetry is
   intentional: the parent must not couple to child internals;
   the child reading a uniform pattern-level sentinel falls
   outside R14's prohibition.

4. **Backward-compatible deployment.** Children that do not
   yet recognize the sentinel default to surfacing their own
   prompts — the worst case is the status quo. As children
   adopt the sentinel in small per-child PRs, the prompt-
   hijack issue resolves child by child. `/charter`'s revision
   from `--parent-orchestrated` to the same state-file
   sentinel is a small follow-up PR.

#### Alternatives Considered

**Option B: Argument passthrough (`--parent-orchestrated` flag
added to each child's `$ARGUMENTS` parser).** This is the
mechanism `/charter`'s `phase-resume.md` documents today.
Rejected because (a) it requires modifying four children's
`$ARGUMENTS` surface, the literal violation L13 forbids; (b)
the flag name becomes part of each child's API, coupling the
parent to the child's input surface; (c) future child input-
surface refactors risk silently dropping the flag without the
parent noticing.

**Option C: Environment variable
(`SHIRABE_PARENT_ORCHESTRATED=true` set by `/scope` before
invoking the child).** Rejected because (a) it still extends
the child's input surface (the child has to read an env var it
didn't read before); (b) env vars don't survive across process
boundaries reliably in all skill-invocation substrates; (c) the
sentinel becomes invisible to humans reviewing the workflow
— the state file is reviewable, an in-process env var is not.

**Option D: Topic-slug-only with child's own resume logic (no
signal).** This is the strict L13-compliant option. `/scope`
invokes `/prd <topic>` with the slug alone; `/prd`'s own
resume ladder detects the Draft PRD and surfaces "Offer to
continue or start fresh"; the author chooses. Rejected because
R11's last paragraph explicitly forbids letting the child's
resume prompt hijack `/scope`'s flow. R11 requires upfront-
decided suppression; topic-slug-only forces the decision into
the child's prompt.

**Option E: Refuse-and-restart (parent destroys the partial wip
+ Draft child doc before invoking the child).** Rejected
because (a) it forces destructive action (a `git rm` on the
Draft child doc) BEFORE the author has confirmed the chain
proposal, violating "warn but never act unilaterally" (R13's
framing); (b) it loses information the author may have written
into the Draft and may want preserved for re-authoring.

### Decision 4: Worktree-discipline reference content

PRD R21 specifies the trigger condition (worktree-staleness
check fires before each Phase 2 child invocation) and the
three-option prompt (rebase / proceed anyway / bail). PRD
Decision 4 specifies the location (`references/parent-skill-
worktree-discipline.md` at the top-level reference root, not
parent-specific). The question deferred to design is the
detailed prose: rebase mechanics, the "proceed anyway" state-
file recording semantics, and how the check integrates with the
chain-proposal prompt.

#### Chosen: Substrate-Agnostic Top-Level Reference with Four Named Sections

The reference body is parent-agnostic prose with the following
four sections:

1. **Trigger Condition.** Defines "before each Phase 2 child
   invocation" precisely: after `/scope` Phase 1 emits its
   chain-proposal output and the author confirms (R7.5), AND
   before each child invocation in `planned_chain`. The check
   fires four times per full-run chain (once before each of
   `/brief`, `/prd`, `/design`, `/plan`), not once per parent
   invocation. The trigger is bounded by the chain step count,
   not by wallclock time.
2. **Three-Option Prompt.** "Rebase / Proceed anyway / Bail"
   surfaced when `git fetch && git status --branch --short`
   shows the upstream has new commits on the tracking branch.
   Rebase re-fetches and rebases the feature branch (the
   parent skill emits the `git fetch && git rebase` commands
   and waits for the author's manual approval before running
   them — never auto-rebases). Proceed anyway accepts the
   risk and continues to child invocation; the state file
   records the divergence per the Recording Section below.
   Bail routes per the parent's own bail-handling rule (for
   `/scope`, R8).
3. **Recording "Proceed Anyway" Divergence.** When the author
   selects Proceed anyway, the parent's state file gains a new
   conditional entry under
   `worktree_divergences:` (a list, since one chain can have
   up to four divergence events) with `{phase: <child-name>,
   upstream_ahead_by: <count>, accepted_at: <ISO-8601>}`. The
   list is conditional (absent when no divergence accepted)
   per I-5; the field tail is appended to as additional
   divergences occur.
4. **Integration with Chain-Proposal Prompt.** The check is
   AFTER chain-proposal confirmation, not before — the
   confirmation prompt itself is short and well-bounded
   (R7.5), running `git fetch` before it would add latency
   without proportionate value (the author hasn't decided to
   proceed yet). The integration prose addresses the order
   explicitly so future parents follow the same convention.

A fifth "Binding Notes" section names per-parent bindings:
`/scope` v1 (load-bearing — 4 children, longest chain in
shirabe); `/charter` (back-edit; 3 children, also load-
bearing); `/work-on` (future; binding deferred to amplifier-
layer parent).

This is recommended because the reference's parent-agnostic
core lets future parents (the SE8 `/work-on` migration, any
amplifier-layer parents) inherit the discipline without re-
deriving it — the load-bearing concern Decision 4 in the PRD
calls out. The Binding Notes section keeps `/charter`'s back-
edit cost bounded (a single reference-table addition plus a
citation in `/charter`'s phase-2 doc).

#### Alternatives Considered

**Option B: Place at `skills/scope/references/operational-
runbook.md`.** Rejected per PRD Decision 4 — the worktree
discipline isn't `/scope`-specific (`/charter` also benefits),
so parent-specific placement creates known re-home work in
SE12. The exploration's learning-fold-opportunities Lead
recommended parent-specific for velocity; the exploration's
decisions doc overrode this for the same reason captured
above.

**Option C: A single dense prose paragraph at the top-level
without sub-section structure.** Rejected because the four
concerns (Trigger, Prompt, Recording, Integration) are
genuinely independent dimensions reviewers grep separately;
the section structure makes the contract surface mechanically
auditable.

### Decision 5: Cross-boundary state-snapshot semantics on Decision Record write

PRD R10 specifies `child_snapshots:` as a per-child block
recording `{path, status, content_hash}` for each child the
parent has invoked. PRD R11 names drift detection (status OR
content-hash differs from snapshot) as a resume-ladder signal.
The question deferred to design: when `/scope` writes a
re-evaluation Decision Record, does `child_snapshots` advance
to record the Decision Record path, or stay frozen on the
referenced upstream artifact?

#### Chosen: child_snapshots Stays Frozen on the Referenced Upstream Artifact

The Decision Record is recorded exclusively in two places:
`exit_artifacts:` (with `status: Accepted`) and
`referenced_artifact:` (which names the upstream artifact —
the existing PRD or DESIGN — by path, NOT the Decision
Record). The `child_snapshots:` entry for the boundary's child
(`prd` on PRD-boundary; `design` on DESIGN-boundary) retains
the `{path, status, content_hash}` triple captured at the
moment the chain last advanced past or exited at that child.

For downstream children (those past the boundary), snapshots
retain their values from the last chain run that touched them
— typically `Absent` if the chain never reached that child
(e.g., `child_snapshots.plan` is `Absent` after a PRD-boundary
re-evaluation exit), or the values from the prior full-run
that produced them.

This is recommended because:

1. **Drift detection's job is to detect change.** A snapshot
   that always reflects the current state is by definition
   never drifted. Snapshotting the Decision Record path would
   freeze the boundary's snapshot to the Decision Record's
   blob hash, which never changes once written — drift
   detection on the upstream PRD/DESIGN would then never fire
   on a subsequent `/scope` resume, because the snapshot
   "advanced past" the artifact the drift check needs to
   compare against.
2. **The Decision Record is a re-evaluation conclusion, not a
   new chain advance.** A re-evaluation exit explicitly
   concludes the existing PRD/DESIGN still holds. The
   `referenced_artifact:` field is the explicit pointer to
   what the conclusion attaches to; `child_snapshots:` is the
   drift-detection backing store. Conflating them defeats the
   purpose of having both.
3. **Re-evaluation isn't chain advancement; abandonment-
   forced isn't either.** Only full-run advances the chain
   past each child boundary. The snapshot semantics follow
   the chain-advance semantics — snapshots advance when the
   chain crosses the corresponding child boundary, not when
   any chain-terminating exit fires.

#### Alternatives Considered

**Option B: Advance child_snapshots to the Decision Record
path on re-evaluation Decision Record write.** Rejected
because it defeats drift detection on subsequent
`/scope` resumes — the snapshot would point at the Decision
Record's never-changing blob hash, masking edits to the
underlying PRD/DESIGN. The hypothesis behind advancing
("the Decision Record IS what /scope concluded last") confuses
the conclusion artifact with the artifact-being-evaluated.

### Decision 6: Resume-ladder body-slot fills (Slots 5/6/7) for /scope

PRD R11 names a resume-ladder ordering for `/scope` and AC15-
AC18b specify the row vocabulary contract (which prompts must
or must not contain "Re-evaluate / Revise / Bail" literals,
the DESIGN-above-PRD ordering rule per AC17b, the PLAN-Active
refuse-and-redirect to `/work-on` per AC17c). The question
deferred to design: the specific row ordering and prompt
vocabulary for the parent-specific body slots (Slot 5 status-
aware re-entry, Slot 6 partial-child-run detection, Slot 7
feeder-doc-detected) inside the universal meta-ladder.

#### Chosen: Adopt PRD R11 Ordering Verbatim with Slot Labels and a Vocabulary Contract Sub-Section

**Slot 5 — Status-aware re-entry (nine rows in most-downstream-
first first-match-wins order):**

| Row | Match condition | Action | Vocabulary contract |
|-----|----------------|--------|---------------------|
| 5.1 | `docs/plans/PLAN-<topic>.md` status Active | Refuse re-entry; redirect to `/work-on` | Literal "redirect to /work-on"; MUST NOT contain "Re-evaluate / Revise / Bail" (AC17c) |
| 5.2 | `docs/plans/PLAN-<topic>.md` status Done | Refuse re-entry; redirect to `/release` | Literal "redirect to /release"; MUST NOT contain "Re-evaluate / Revise / Bail" (AC17c) |
| 5.3 | `docs/plans/PLAN-<topic>.md` status Draft | Two-option: Continue PLAN draft into `/plan` OR Start fresh | "Continue draft" / "Start fresh"; MUST NOT contain re-evaluation triad |
| 5.4 | `docs/designs/current/DESIGN-<topic>.md` status Accepted AND no PLAN at any status | Three-option entry against DESIGN-boundary | MUST contain "Re-evaluate / Revise / Bail"; MUST identify DESIGN-boundary (AC17b) |
| 5.5 | `docs/designs/DESIGN-<topic>.md` status Proposed AND no PLAN | Two-option: Continue DESIGN draft OR Start fresh | "Continue draft" / "Start fresh"; MUST NOT contain triad |
| 5.6 | `docs/prds/PRD-<topic>.md` status Accepted AND no DESIGN at any status AND no PLAN | Three-option entry against PRD-boundary | MUST contain "Re-evaluate / Revise / Bail"; MUST identify PRD-boundary; MUST NOT contain "Continue / Start fresh" (AC17a) |
| 5.7 | `docs/prds/PRD-<topic>.md` status Draft AND no DESIGN AND no PLAN | Two-option: Continue PRD draft OR Start fresh | "Continue draft" / "Start fresh"; MUST NOT contain triad |
| 5.8 | `docs/briefs/BRIEF-<topic>.md` status Accepted or Done AND no PRD AND no DESIGN AND no PLAN | Auto-skip `/brief` in chain proposal | No re-evaluation prompt — BRIEF is upstream input |
| 5.9 | `docs/briefs/BRIEF-<topic>.md` status Draft AND no PRD AND no DESIGN AND no PLAN | Two-option: Continue BRIEF draft OR Start fresh | "Continue draft" / "Start fresh" |

The ordering is most-downstream-first first-match-wins (PLAN
above DESIGN above PRD above BRIEF), ratifying AC17b's
"DESIGN above PRD" rule. The natural reading direction is
"the rightmost child that has produced an artifact" — that
child's status determines the prompt.

**Slot 6 — Partial-child-run detection (four rows):**

| Row | Match condition | Action |
|-----|----------------|--------|
| 6.1 | `wip/plan_<topic>_*.md` exists | Resume into `/plan` |
| 6.2 | `wip/design_<topic>_*.md` exists | Resume into `/design` |
| 6.3 | `wip/prd_<topic>_*.md` exists | Resume into `/prd` |
| 6.4 | `wip/brief_<topic>_*.md` exists | Resume into `/brief` |

Same most-downstream-first ordering. Slot 6 fires when no
durable child doc exists for the topic but a partial-run
`wip/` artifact does — the chain was interrupted mid-child.

**Slot 7 — Feeder-doc-detected (vacuous in v1):**

The slot exists in the meta-ladder template but is empty in
`/scope` v1. The tactical chain has no feeder analogous to
`/charter`'s `/comp`; per PRD Out-of-Scope #7, a future
feeder (e.g., `/spike-feasibility`) would populate this slot
when shipped. The slot is documented in `/scope`'s SKILL.md
explicitly as "No feeder defined in v1; reserved for future"
to keep the slot count consistent with the meta-ladder
template.

This is recommended because the PRD R11 ladder rows are
authored at requirement altitude precisely so the design can
ratify them verbatim with the AC vocabulary contract layered
on top. The slot labels (5.1-5.9, 6.1-6.4) are an
implementation convenience for the eval surface; the rows
themselves are PRD-authored. The vocabulary contract sub-
section is what the eval scenarios grep against.

#### Alternatives Considered

**Option B: Most-upstream-first ordering (BRIEF above PRD
above DESIGN above PLAN).** Rejected because it inverts
AC17b's explicit DESIGN-above-PRD rule and would force every
re-entry to find the most-upstream-existing artifact first,
which is conceptually inverted: when both an Accepted PRD and
an Accepted DESIGN exist, the more-downstream DESIGN is the
later-decided artifact and the natural starting point.

**Option C: Two-slot split — separate slots for re-evaluation
boundaries vs continuation prompts.** Rejected because the
meta-ladder template (universal pattern-doc fixture) names
exactly three body slots (5/6/7) and adding a fourth would
break the meta-ladder count contract every other parent's
SKILL.md inherits. The contract requires `/scope` to fit
inside the existing slot structure.

### Decision 7: Abandonment-forced HTML-comment marker schema

PRD R15 third bullet names the marker as "an HTML-comment
marker inside the artifact's existing Status section". AC13
specifies the marker's literal substring (`<!-- scope-status-
block: abandonment-forced; ... -->`). AC23 requires the marker
not invalidate the artifact-type schema (must stay inside the
existing Status section, not a new required section). The
question deferred to design: the exact marker text, what
metadata it carries beyond the abandonment flag, and whether
the marker is uniform across artifact types or tailored per
child.

#### Chosen: Uniform Single-Line HTML-Comment Marker at the End of the Existing Status Section

The literal marker text:

```
<!-- scope-status-block: abandonment-forced; triggering-child: <name>; partial-phase-reached: <phase>; chain-started: <ISO-8601 timestamp> -->
```

The marker is a single-line HTML comment. Whitespace inside
the comment is significant — readers (validators, scope's own
resume detection, human reviewers) match against the exact
substring `scope-status-block: abandonment-forced`; the marker
SHALL NOT add line breaks within the comment, SHALL NOT add
additional fields, and SHALL NOT reorder the fields.

The four fields are populated from the `/scope` state file at
chain finalization:

- `<name>` — substituted from `triggering_child:` in state.
  One of `brief`, `prd`, `design`, `plan` resolved by the R8
  tie-break.
- `<phase>` — substituted from `partial_phase_reached:` in
  state. The phase pointer the triggering child had reached.
- `<ISO-8601 timestamp>` — substituted from `chain_started:`
  in state. The original chain start time, not the
  force-materialization time.

The marker is placed at the END of the artifact's existing
Status section (after the status word `Draft`, on a new line).
Placement at the end of the section keeps the section's
parsing semantics intact for all four artifact types — every
artifact validator treats the Status section as "the word at
the start, optional prose lines afterwards"; an HTML comment
at the end falls inside the "optional prose" zone for all
four schemas.

This is recommended because the uniform-marker approach makes
the marker grep-checkable across artifact types with a single
substring (`scope-status-block: abandonment-forced`), satisfies
AC13's literal-substring requirement uniformly, and avoids
per-child schema variation that would expand the validator
surface. Single-line keeps the marker safe across artifacts
that strip or reformat multi-line comments.

#### Alternatives Considered

**Option B: Per-artifact-type tailored marker prose.** Each
child gets a marker phrased to match its existing Status
section's conventions (BRIEF's marker references "framing
not validated", PRD's "requirements not finalized", etc.).
Rejected because (a) per-child variation breaks the
grep-checkable uniformity AC13's eval scenarios require; (b)
the metadata carried in the comment is identical across all
four (triggering_child, partial_phase_reached, chain_started)
— variation in surrounding prose adds review burden without
adding contract value.

**Option C: Uniform marker but extended metadata (timestamp +
artifact-path + R8-step).** Rejected because the metadata
proliferation would force the marker to span multiple lines
(YAML-block-in-HTML-comment), which would conflict with
single-line schema-compliance assumptions. The four chosen
fields are the minimal set the abandonment-forced resume
surface needs.

### Decision 8: Pattern-doc edit surface for the fourth gate type and state-schema extensions

PRD R1, R3, R9, R10, R11, R12, R13, R14, R17a, R18, R19 are all
tagged `[pattern-level]`. The PRD's Downstream Artifacts
section names four pattern reference files as edit targets and
two new top-level references (`parent-skill-worktree-
discipline.md`; settled in D4). The question deferred to
design: where the new vocabulary (Mandatory-with-auto-skip
gate, `boundary:` and `plan_execution_mode:` state fields, the
PLAN-Active/Done refuse-and-redirect rows) lands inside the
four existing pattern reference files, and which parts of the
audit's "verbatim inheritance" recommendation hold vs need
softening.

#### Chosen: Surgical Reference Edits with One Universal-Meta-Ladder Addition, Three New State-Schema Fields, Two New Pattern-Doc Sections, Zero Child-Inspection Edits

The edit surface across the four pattern reference files:

**A. `references/parent-skill-pattern.md`.**

A.1. **New Gate Vocabulary section.** Inserted between the
existing "Three Exit Paths" and "Conditional Feeder Invocation
Shape" sections. Lists all four gate shapes (EITHER-signal,
ALWAYS, shape-dependent, Mandatory-with-auto-skip), with a
canonical example per shape: `/charter`'s `/vision` invocation
for EITHER-signal, `/charter`'s `/strategy` for ALWAYS,
`/charter`'s `/roadmap` for shape-dependent, `/scope`'s `/prd`
for Mandatory-with-auto-skip. The Mandatory-with-auto-skip
shape: "The child SHALL be invoked unless its durable artifact
already exists in the published-Accepted status at the
canonical path; in that case the child is recorded in
`chain_skipped` and the chain proceeds to the next gate."

A.2. **L13 amendment (per Decision 3 above).** The existing
"Parents do not extend children's input surfaces" paragraph is
rewritten to permit a pattern-level suppression signal as the
sole permitted form of parent-orchestration primitive,
mechanically defined as the parent's state file's
`parent_orchestration:` block at the substrate-defined path.
Combined with A.1, this is the only `parent-skill-pattern.md`
edit beyond the new Gate Vocabulary section.

**B. `references/parent-skill-state-schema.md`.**

B.1. **Two new conditional-field bullets in the Field
Semantics section.** `boundary:` (gated by `exit:
re-evaluation`; valid values `prd | design`) and
`plan_execution_mode:` (gated by `/plan` appearing in
`chain_ran`; valid values `single-pr | multi-pr`). Both are
parent-specific Layer-2 extensions per the existing extension
discipline; the bullets cite the extension discipline section
and link back to the design's Decision Outcome.

B.2. **Chain-tracking paragraph addition.** A new paragraph
under the Chain-tracking sub-section notes that
`plan_execution_mode:` is recorded separately from
`chain_ran`/`chain_skipped` because the chain-tracking unit
does not capture output-mode selection — the field decouples
execution-mode persistence from chain membership.

B.3. **R9 hard-finalization-check additions.** Part 2 ("Sub-
shape valid when applicable") gains a one-paragraph addition
naming `boundary:` as a sub-shape discriminator alongside
`decision_record_sub_shape:` (both must be set when `exit:
re-evaluation` fires). Part 3 ("Conditional fields absent when
ungated") gains a one-paragraph addition naming both
`boundary:` and `plan_execution_mode:` as I-5-conditional
fields.

**C. `references/parent-skill-resume-ladder-template.md`.**

C.1. **Single paragraph appended to Slot 5 spec.** The
paragraph documents the refuse-and-redirect prompt shape for
parents whose terminal artifact has an in-implementation or
completed lifecycle owned by a downstream skill. The 9-row
meta-ladder count is preserved (the addition lives inside the
existing Slot 5 spec, which is parent-specific by template
contract).

**D. `references/parent-skill-child-inspection.md`.**

D.1. **No edits.** The audit's verbatim recommendation holds:
all four tactical-chain children are doc-emitting and fall
under the existing "doc-emitting child" row in the per-parent
surface table. The PLAN doc's GitHub milestone side-effect is
NOT a child-inspection surface — `/scope` does NOT read
milestone state to drive its decisions; `plan_execution_mode:`
in the state file records the side-effect's selection.

Estimated total edit surface: ~90-112 added lines across three
of four pattern reference files; D4's new top-level reference
adds an additional ~80-100 lines.

This is recommended because surgical placement keeps the
pattern doc reviewable (each edit has a clear semantic home),
respects the audit's verbatim-inheritance call where it
genuinely holds (the child-inspection row), softens it where
the second parent's shape forces new vocabulary (the gate
list), and bounds `/charter`'s back-edit cost to a reference-
table citation addition.

#### Alternatives Considered

**Option B: Fold Mandatory-with-auto-skip into the existing
Conditional Feeder Invocation Shape section as a subsection.**
Rejected because the feeder shape is a *specific* three-
condition gate (signal + skill-exists + visibility);
Mandatory-with-auto-skip is a different category of gate
(main-chain, not feeder) that doesn't share the three-
condition structure. Folding it inside would conflate two
distinct gate categories.

**Option C: Add PLAN-Active and PLAN-Done as universal meta-
ladder rows (raising the 9-row count to 11).** Rejected
because the meta-ladder template explicitly promises "the same
9-row ladder shape" to readers of any parent's SKILL.md (lines
8-10 and 19 of the template). Slot 5's existing language
already admits the refuse-and-redirect prompt shape; the
single-paragraph addition makes it explicit without growing
the meta-ladder count.

**Option D: Add `boundary:` to the 5-field minimum (raising
it to a 6-field minimum).** Rejected because most parents
recognize one re-evaluation boundary or none. Making
`boundary:` minimum-required would force every parent to write
`boundary: <single-value>` or `boundary: null` — the latter
violates I-5. Conditional-field-with-extension-discipline is
the correct framing.

**Option E: Edit `parent-skill-child-inspection.md` to add a
row for "doc-emitting child plus side-effect resource" (PLAN
doc plus GitHub milestone).** Rejected because the milestone
is not a child-inspection surface — `/scope` does NOT read
milestone state. The "doc-emitting" row covers PLAN without
modification.

## Decision Outcome

**Chosen: 1A + 2A + 3A + 4A + 5A + 6A + 7A + 8A.**

### Summary

`/scope` ships as a single-agent loadable skill at
`skills/scope/SKILL.md` plus four pattern-doc edits (across
three of the four pattern-reference files), one new top-level
reference (`references/parent-skill-worktree-discipline.md`),
and two child-side contract extensions (Phase-N Reject
finalization gates on `/prd` Phase 4 and `/design` Phase 6).
The architecture is built around the parent-skill pattern v1's
two-layer contract — semantic invariants I-1 through I-7
inherited verbatim from `DESIGN-shirabe-progression-
authoring.md`, with `/scope`-specific bindings added inside
the v1 substitution surface (`storage_substrate: wip-yaml-md`,
`team_primitive: single-team-per-leader-no-nested`).

The chain runs in five phases: Phase 0 setup, Phase 1
discovery + chain proposal, Phase 2 child invocation loop
(per-child worktree-staleness check → invoke child via
state-file `parent_orchestration:` sentinel → read child's
durable status → record exit_artifacts), Phase 3 exit
finalization, Phase 4 wip cleanup. Each phase has a reference
file at `skills/scope/references/phases/`. The R6 shape-
predicate evaluation walks the PRD's named sections inline in
Phase 1 against three predicates (architectural-alternatives
count, new-component references, Complex classification),
emitting per-predicate verdicts whose reasons feed directly
into the chain-proposal output. The R7.5 chain-proposal output
contains the literal substrings `Proceed`, `Adjust`, and
`Bail` per AC9; the resume-ladder body-slot prompts contain
the literal `Re-evaluate / Revise / Bail` per AC17a/AC17b at
the PRD and DESIGN re-evaluation boundaries.

The three exit paths bind concretely to `/scope`'s tactical
shape. Full-run exits land at `docs/plans/PLAN-<topic>.md`
(Draft in single-pr mode; Active in multi-pr mode alongside a
GitHub milestone). Re-evaluation exits write a Decision
Record at `docs/decisions/DECISION-{prd|design}-<topic>-
{re-evaluation|rejection}-<YYYY-MM-DD>.md` with two boundary
positions (PRD or DESIGN) and two sub-shapes (re-evaluation
or rejection). Abandonment-forced exits force-materialize the
most-recently-running child's intermediate as a Draft
artifact, with the single-line HTML-comment marker
`<!-- scope-status-block: abandonment-forced; triggering-
child: <name>; partial-phase-reached: <phase>; chain-started:
<ISO-8601 timestamp> -->` at the end of the artifact's Status
section.

The state file at `wip/scope_<topic>_state.md` is pure YAML
under the `.md` extension. Its schema extends the pattern's
5-field minimum (`topic`, `last_updated`, `phase_pointer`,
`exit`, `exit_artifacts`) with `/scope`-specific fields:
`chain_started`, `chain_completed`, `planned_chain`,
`chain_ran`, `chain_skipped`, `boundary` (conditional on
`exit: re-evaluation`), `decision_record_sub_shape`
(conditional on `exit: re-evaluation`),
`plan_execution_mode` (conditional on `/plan` in `chain_ran`),
`referenced_artifact`, `discard_commit_sha`,
`rejection_rationale`, `triggering_child`,
`partial_phase_reached`, `child_snapshots` (the per-child
status + content-hash dual-check block), and the ephemeral
`parent_orchestration` block (present only during child
invocation; cleared on return). `worktree_divergences` is a
conditional list capturing each Proceed-anyway divergence
accepted during Phase 2.

The resume ladder follows the universal meta-ladder template
with Slot 5 spanning 9 rows in most-downstream-first first-
match-wins order (PLAN-Active → `/work-on`, PLAN-Done →
`/release`, PLAN-Draft continue/start-fresh, DESIGN-Accepted
three-option at DESIGN-boundary, DESIGN-Proposed continue/
start-fresh, PRD-Accepted three-option at PRD-boundary, PRD-
Draft continue/start-fresh, BRIEF-Accepted auto-skip, BRIEF-
Draft continue/start-fresh), Slot 6 spanning 4 rows for
partial-`wip/`-child-run detection, and Slot 7 vacuous
(reserved for a future tactical-chain feeder).

Drift detection on the child snapshots' status OR content-
hash fires the three-option prompt (re-run downstream / accept
downstream as still-valid / proceed without downstream) per
AC18a/AC18b. The snapshot semantics on Decision Record write
stay frozen on the referenced upstream artifact — the Decision
Record is recorded in `exit_artifacts` and `referenced_artifact`
but does NOT advance `child_snapshots`. This preserves drift
detection on subsequent `/scope` resumes against the same
PRD/DESIGN.

The pattern-doc edits are surgical. `parent-skill-pattern.md`
gains a new "Gate Vocabulary" section between "Three Exit
Paths" and "Conditional Feeder Invocation Shape" listing all
four gate shapes, plus the L13 amendment permitting a
pattern-level `parent_orchestration:` state-file sentinel as
the sole permitted form of parent-to-child orchestration
signal. `parent-skill-state-schema.md` gains two new
conditional-field bullets, a Chain-tracking paragraph
addition, and R9 hard-finalization-check additions naming
`boundary:` as a sub-shape discriminator and both new fields
as I-5-conditional. `parent-skill-resume-ladder-template.md`
gains a single paragraph appended to the Slot 5 spec
documenting the refuse-and-redirect prompt shape (preserving
the 9-row meta-ladder count). `parent-skill-child-inspection.md`
is untouched — all four tactical-chain children are doc-
emitting and fit the existing row.

The Phase-N Reject contract extensions to `/prd` Phase 4 step
4.5 and `/design` Phase 6 step 6.7 replace each child's
existing 2-option AskUserQuestion with a 3-option gate
(Approved / Reject / Continue-revising), mirroring
`/strategy`'s Phase 5.2 precedent. On Reject, the child runs
`git rm` against the durable artifact, removes `wip/`
intermediates for the topic, and commits
`docs(<type>): discard <TYPE> draft for <topic>` with the
author's rationale in the body. The contract fires identically
in-chain and out-of-chain (AC30c).

`/charter`'s back-edit absorbs a single reference-table
citation addition for the new worktree-discipline reference
plus a Gate Vocabulary citation; no body-slot-5 row addition
is needed because `/charter`'s STRATEGY has no Active/Done
analog. `/charter`'s existing `--parent-orchestrated` flag
documentation in `phase-resume.md` is replaced by a pointer
to the new pattern-level `parent_orchestration:` sentinel
in a small follow-up PR. The migration is incremental: each
of the four shirabe children adopts the sentinel in a small
per-child PR; until adopted, the child surfaces its own
prompts (the worst case is the status quo).

### Rationale

The combination works because all eight decisions converge on
the same architectural principle: the pattern's two-layer
contract is the freeze line; `/scope`'s extensions ride inside
the substitution surface and the body slots, never outside
them. D1's Augment Existing Gates choice keeps the Phase-N
Reject contract inside each child's existing finalization
phase (no new phases). D2's Structured Checklist Walk keeps R6
evaluation inside Phase 1 discovery (no new sub-skills, no
team-primitive violation). D3's State-File Sentinel + L13
Amendment chooses a pattern-level convention over per-parent
flags, formalizing in the pattern doc what `/charter` ships
informally today. D4's Substrate-Agnostic Reference makes
worktree-discipline a shared infrastructure both parents (and
future parents) cite. D5's Frozen Snapshots preserves drift
detection's invariant: the snapshot tracks what the chain has
seen of the artifact, not what the chain has concluded about
it. D6's Verbatim Adoption of PRD R11 with a Vocabulary
Contract Sub-Section makes the resume ladder eval-checkable.
D7's Uniform Single-Line HTML-Comment Marker keeps the
abandonment-forced contract schema-checkable across all four
artifact types. D8's Surgical Edits absorb every pattern-
level requirement without re-doing the pattern doc's structure.

The accepted trade-offs:

- **Pattern doc grows three new sections plus one
  amendment.** The growth is one-time and load-bearing —
  every future parent benefits from a documented Gate
  Vocabulary, a parent-level state-file sentinel, and a
  surgical extension discipline for state-schema fields.
- **Four shirabe children eventually need a small per-child
  PR to recognize the `parent_orchestration:` sentinel.** The
  worst case before adoption is the status quo (child prompt
  may hijack parent flow); the migration is incremental and
  bounded by four small PRs.
- **The worktree-staleness check adds `git fetch` overhead
  four times per full-run chain.** Bounded operational cost
  (PRD line 1511); the trigger is bounded to before-each-
  child invocation, not per-operation.
- **`/scope`-specific resume ladder has 9 rows in Slot 5
  alone, plus 4 rows in Slot 6.** Higher than `/charter`'s
  slot fills, but the tactical chain has 4 children + 3 PLAN
  statuses + DESIGN's directory-move lifecycle — the row
  count tracks the chain's inherent complexity.

The L9 PRD-tag traceability holds: each pattern-level
requirement (R1, R3, R9, R10, R11, R12, R13, R14, R17a, R18,
R19) maps to a pattern-doc edit in D8 (covering R1 via the
SKILL.md structural elements list; R3 via the topic-slug
regex citation; R9 via state-schema's R9 additions; R10 via
schema's new field bullets; R11 via the resume-ladder slot
addition + ordering paragraph; R12, R13, R14 via no-edits-
needed pattern-level surfaces; R17a via CLAUDE.md updates;
R18 via the eval-suite requirement carried in this design's
implementation approach; R19 via inherited I-7 from
`progression-authoring`). Each `/scope`-specific requirement
(R2, R4, R5, R6, R7, R7.5, R8, R15, R16, R16.5, R17b, R20,
R21, R22, R23) maps to a section in `skills/scope/SKILL.md` or
its phase references, enumerated in Solution Architecture
below.
