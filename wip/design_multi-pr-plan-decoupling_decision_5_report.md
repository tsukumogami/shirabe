<!-- decision:start id="approval-gate-rekey" status="Accepted" -->

# Decision: Draft->Active approval-gate re-key

## Context

`docs/decisions/DECISION-multi-pr-posture-detection-2026-06-06.md` (Accepted)
establishes that PLAN docs share one unified `Draft -> Active -> Done ->
DELETED` lifecycle across `single-pr` and `multi-pr`, and that only the
`Draft -> Active` transition differs between them: "multi-pr requires human
approval (GitHub issues + milestone are created on the transition),
single-pr auto-fires when `/shirabe:plan` finishes authoring." That
parenthetical — GitHub-artifact creation is *why* multi-pr is gated — is
background justification inside the record's **Context** section. The
record's actual **Decision** (detect posture from the PLAN's frontmatter
`status:` field; the four-row Active/Draft/Done/absent table; the
atomic-commit completion gesture) never mentions the gate at all — it is
purely about status-field posture detection and is agnostic to why any
particular transition is gated.

`PRD-multi-pr-plan-decoupling.md` R7-R9 makes tracking level (`none`,
`issues`, `issues-and-milestone`) a preference independent of
`execution_mode`. Once that lands, "multi-pr" stops being a reliable proxy
for "creates GitHub issues": a `single-pr` plan with tracking `issues` now
creates them, and a `multi-pr` plan with tracking `none` doesn't. R11 states
the fix directly: "The approval gate that distinguishes automatic from
human-approved plan activation SHALL be keyed on whether the activation will
create GitHub issues, rather than on `execution_mode`." The DESIGN doc
in progress (`docs/designs/DESIGN-multi-pr-plan-decoupling.md:168-171`,
"Known Costs to Carry") already names this exact item and already commits to
the verb: "that predicate must be re-keyed onto 'does this run create
GitHub artifacts,' amending that record" — amending, not superseding.

There is direct in-corpus precedent for this identical shape: the roadmap
workflow's own R14 approval gate went through the same move.
`DECISION-populate-issueless-default-2026-08-10.md` inverted `shirabe
roadmap populate`'s default so the gate now fires only on the
issue-creating path, never on the issueless one — "does this run create
GitHub artifacts" was already the operative question there before this PRD
existed.

## Assumptions

- No code currently implements the multi-pr approval gate as a runtime
  block. `crates/shirabe-validate/src/transition.rs:261-265`'s own doc
  comment says the `Draft -> Active` gate difference "is enforced out-of-
  band by the calling skill, not by this subcommand." `phase-6-review.md`
  (the phase before Phase 7 fires issue creation) has no interactive
  confirm step keyed on `execution_mode` either. The "human approval" is a
  documented behavioral contract the skill prose asserts, not a gate the
  validator or transition subcommand enforces.
- PRD R11's scope is the gate's *predicate*, not a new enforcement
  mechanism. Nothing in R7-R12 asks for a new interactive confirmation UI.

## Chosen

**1. The re-key is prose-only, and touches more files than Phase 7 alone.**

No code implements the gate today (see Assumptions), so there is nothing to
re-key in `transition.rs` or `lifecycle.rs`. The change is textual, in five
places:

- `skills/plan/SKILL.md:59-60` — "Only the Draft -> Active gate differs:
  multi-pr requires human approval..."
- `skills/plan/references/quality/plan-doc-structure.md:85,92,96` — same
  framing, in the format's status-transition table.
- `skills/plan/references/phases/phase-7-creation.md` — the phase's
  mode-branch headers ("multi-pr Mode: Steps 7.1-7.4 apply when
  `execution_mode: multi-pr`") gate GitHub issue creation on
  `execution_mode` directly. This has to change regardless of R11: R8
  requires all six `{single-pr, multi-pr} x {none, issues,
  issues-and-milestone}` combinations reachable, so Phase 7 can no longer
  branch issue-creation on `execution_mode` alone — it must branch on
  resolved tracking level. R11's re-key is a direct byproduct of this
  rewrite, not an independent edit to the same file.
- `docs/decisions/DECISION-multi-pr-posture-detection-2026-06-06.md` — the
  Context sentence naming the old justification (amendment, see below).
- Two already-`Current` DESIGN docs that independently repeat the same
  "auto for single-pr, human-approved for multi-pr" framing in their PLAN
  lifecycle instantiation, unrelated to Phase 7's code path:
  `docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md:397-398`
  and `docs/designs/current/DESIGN-shirabe-artifact-decision-contract.md:451-453`.
  Their ROADMAP instantiation
  (`DESIGN-shirabe-artifact-decision-contract.md:469-470`, "keeps its
  existing human-approval semantic") is explicitly **not** touched — R10
  exempts `coordinated`/roadmap tracking from this PRD's preference, and
  roadmap's own gate is already keyed on issue-creation via the
  populate-issueless-default precedent cited above.

**Verifying the prior reviewer's claim** ("the same Phase 7 multi-pr branch
tracking decoupling already touches, not separate surgery"): partially
right, partially wrong. The functional predicate change rides for free on
Phase 7's mandatory R8 rewrite — true, not separate surgery there. But the
claim undersells the footprint: the DECISION amendment and the two
`docs/designs/current/` files sit entirely outside Phase 7 and outside any
file the tracking-preference code path touches. Nobody rewriting Phase 7's
branch predicate will incidentally fix those three files; they need to be
named explicitly or they drift. Treat the claim as "same mechanism, wider
prose sweep than 'just Phase 7.'"

**2. L01/L02 do not need re-keying, and no issueless multi-pr plan is at
risk of being unable to reach Active.**

`crates/shirabe-validate/src/lifecycle.rs` reads `execution_mode` in exactly
one place relevant here, `infer_posture_from()` (line 782), and only to
choose a posture *label* — `MultiPrInFlight`/`MultiPrWorkCompleting` vs.
`SinglePrMidPR`/`SinglePrAtMerge` — for message wording and Draft-vs-Done
bucketing. `compute_passing_state()` (lines 822-879) then maps *every*
in-flight posture, multi-pr or single-pr alike, to the same required state
for the Plan role: `Status("Active")`. Every work-completing/at-merge
posture maps to `Deleted`, again regardless of mode. The auto-vs-human
distinction was never encoded as a differing required *state* — both modes
demand `Active` for a committed, mid-PR PLAN, and a `Draft` PLAN fails L01
in either mode (a Draft PLAN on a branch means *some* gate — auto or human —
didn't fire; L01 doesn't care which). So an issueless `multi-pr` plan
reaching `Active` is not blocked by anything in `lifecycle.rs` today, and
nothing there needs to change when R11 lands. Question 3's premise doesn't
hold.

**3. Amend in place; do not supersede.**

The corpus's own decision-record format (`skills/decision-record` /
`tsukumogami:decision-record`) defines a strict lifecycle:
`Proposed -> Accepted -> {Deprecated, Superseded}`, with no "Amended"
status, and "Superseded -> any: Forbidden. Superseded is terminal";
superseding requires "a new decision record explicitly replaces this one."
Superseding is the wrong tool here: the DECISION's actual `## Decision`
content — frontmatter-status-field detection, the four-row state table, the
atomic-commit gesture — is unchanged and unaffected by R11 (confirmed by
point 2: the states it demands don't depend on why a gate fired). Only one
clause of **Context** background prose goes stale. Marking the whole record
Superseded would misrepresent a live, still-correct decision as replaced.

The corpus does have precedent for updating a shipped document without a
full supersession cycle: `DESIGN-scope-artifact-persistence.md`'s write-
target table lists "Two shipped documents | Appended dated amendment
sections" as the applied pattern for exactly this situation (a document
whose core content stands but whose stated facts moved). Follow that
pattern here: append a dated `## Amendment (<PR/date>)` section to the end
of `DECISION-multi-pr-posture-detection-2026-06-06.md` that names
`PRD-multi-pr-plan-decoupling.md` R11 as the trigger and restates the
Context sentence's corrected form — "the gate is human-approved whenever
the resolved tracking level creates GitHub issues (today, exactly when
`execution_mode` is `multi-pr`; once tracking is independent, whenever
tracking resolves to `issues` or `issues-and-milestone`, regardless of
`execution_mode`)." Frontmatter `status:` stays `Accepted`. No
`superseded_by` field, no new ADR file.

**4. Fold into the tracking-preference issue; do not split out.**

R11 is grouped under the PRD's "Functional — tracking preference" heading
(R7-R12), between R10 (coordinated exemption) and R12 (task extraction),
not under the R13-R16 "shape record" group. Its only implementation
surface — Phase 7's issue-creation branch — is the identical code path
R9's default-resolution logic and R12's schedulability work already touch.
Splitting R11 into its own issue would create a dependency edge back onto
that same Phase 7 edit for no isolation benefit; the DECISION amendment and
the two `docs/designs/current/` prose touches are small, textual, and ride
along cheaply. Recommend: one issue (the tracking-preference issue) with
explicit acceptance criteria covering (a) `phase-7-creation.md` branching on
resolved tracking level rather than `execution_mode`, (b) `SKILL.md` and
`plan-doc-structure.md` language re-keyed, (c) the DECISION doc's dated
amendment, (d) the two `docs/designs/current/` files' PLAN-instantiation
language updated, and (e) explicit confirmation that their ROADMAP-
instantiation language is left untouched (cite R10).

## Rationale

Every sub-answer traces to something already in the tree rather than new
argument: the transition subcommand's own comment says the gate is out-of-
band (no code to re-key there); `lifecycle.rs`'s passing-state table is
uniform across modes for the Plan role (no reachability risk); the decision-
record skill's format forbids treating a live, correct decision as
Superseded; and the roadmap's R14 gate already made this exact "key on
issue-creation, not on a mode enum" move, which is why R11 is expressible at
all — the PRD is generalizing an established pattern, not inventing one.

## Alternatives Considered

**Supersede the DECISION with a new ADR.** Rejected. The decision-record
format reserves Superseded for "explicitly replaces this one," and nothing
here replaces the frontmatter-status-field detection mechanism or its state
table — those remain correct verbatim. Superseding would also make L01/L02's
`execution_mode`-derived posture labels look like they need review when they
don't (point 2).

**Edit the Context sentence in place, no dated amendment section.**
Considered. Would be lighter-weight, but the corpus already has a named
convention (dated appended amendment sections) for this exact situation, and
losing the "why did this sentence change" trail makes a `git blame` reader
re-derive the R11 connection from scratch. The dated-amendment pattern costs
one extra paragraph and keeps the audit trail intact.

**Split R11 into its own issue.** Rejected in point 4: no isolation benefit
(same file, same code path as the tracking-preference issue), and it would
force an artificial ordering dependency between two issues that both edit
`phase-7-creation.md`'s mode branch.

**Leave the two `docs/designs/current/` files alone as pre-existing
documentation debt, out of scope.** Considered, since neither file's status
depends on this PRD and both are already `Current` (finalized). Rejected:
both assert the same now-inaccurate causal claim ("human-approved for
multi-pr" as a fact about `execution_mode`, not about tracking), and leaving
stale-but-Current design docs contradicting a newly-Accepted DECISION
amendment is exactly the kind of drift `DECISION-multi-pr-posture-detection`
was written to prevent for the PLAN lifecycle in the first place.

## Consequences

What becomes easier: the approval gate's stated justification tracks its
actual trigger (issue creation) instead of a proxy (`execution_mode`) that
R7-R9 make unreliable; the DECISION record's audit trail shows exactly when
and why its background claim changed, without a spurious Superseded status;
L01/L02 need zero changes, so this item carries no validator risk.

What becomes harder: the issue implementing R7-R12 now carries five textual
touch-points instead of one, spread across two directories
(`skills/plan/`, `docs/decisions/`, `docs/designs/current/`) outside its
primary code change — a reviewer checking "did the re-key actually land"
has to know to look in `docs/designs/current/` for repeated framing that
isn't obviously related to the PLAN format work.

Accepted trade-off: the dated-amendment section on the DECISION doc grows
that file rather than replacing it, so the record now carries both the
original (still-correct) reasoning and a later correction living side by
side — intentional, per the corpus's existing convention for shipped
documents.

<!-- decision:end id="approval-gate-rekey" -->
