# Bakeoff: Alternative 4 — Defer, ship tracking decoupling only

## Position

Decline to answer "should P1 be invertible or should reviewability become a
named P1 trigger" right now. Ship only the tracking half: a `## Plan Issues:`
header on the proven `flag > CLAUDE.md-header > default` stack, and the
re-keying of the Draft->Active approval gate onto "does this run create
GitHub artifacts." Leave P1, the decomposition preference, and the fused
Phase 3.6 branch untouched for a follow-up decision.

## 1. Strengths

**The two halves rest on different principles, not one theme with two
faces.** `references/workflow-principles.md:41` lists "A self-contained PLAN
doc over GitHub issues when the work is single-pr" as a rule derived from
**P2** (lowest ceremony), not P1. P1's own rules-derived section
(`workflow-principles.md:20-22`) only states the cardinality rule
("multi-pr requires a named escape condition") — it says nothing about
issues or milestones. The tracking question ("does this plan get a
GitHub-side grouping handle") and the cardinality question ("how many PRs")
are answered by different numbered principles today, in the source of truth
itself, not merely by research inference. That is a real seam, not a
rhetorical one — Alternative 4 can ship without touching the P1 text that
Alternatives 1–3 all have to reword.

**Proven precedent, not invention.** `## Roadmap Issues: optional|required`
already ships this exact shape for the roadmap layer, resolved
`flag > CLAUDE.md-header > default`
(`references/fixes/claude-md-conventions.md:64`,
`docs/decisions/DECISION-populate-issueless-default-2026-08-10.md:83`).
Extending the same header pattern one layer down to PLAN — `## Plan Issues:`
— is a parameterization of shipped machinery, including the "automatic runs
are always issueless regardless of header" carve-out that
`DECISION-populate-issueless-default-2026-08-10.md` already worked through
once. There is no open design question about *how* a header-resolution
preference behaves; only about which header name and which artifact it
gates.

**Narrow, well-fenced blast radius.** `skills/execute/SKILL.md:40` states
multi-pr is "out of scope for `/execute`; multi-pr plans run one issue at a
time" and redirects to `/work-on`. So every consumer of multi-pr GitHub
state lives in one skill. Within `/work-on`, milestones have exactly one
functional consumer: the M<N> selector at `skills/work-on/SKILL.md:19`
("list open issues in the milestone and select the first unblocked one").
I grepped `skills/execute/` and `skills/inflight/` for milestone logic and
confirmed the finding: nothing reads it there. Cutting tracking loose
touches one skill, one selector, and one CLAUDE.md header — not Phase 3.6's
branch logic, not the validator's trigger surface, not `plan-format.md`'s
frontmatter schema for `execution_mode` itself.

**Milestones carry no strategic weight to lose.** They're an issue-selection
filter plus GitHub-UI grouping, not a progress rollup or completion gate. A
plan going issueless doesn't strand any downstream consumer that currently
reads milestone semantics for anything but "what's next."

## 2. Weaknesses

**It ships half the ask and the author was explicit that the two halves are
one theme.** `findings.md:180-183` records: "The author framed both halves
as one theme while inviting a split into two issues, and asked that the
relationship between them be the deliverable." Alternative 4 answers "what's
the relationship" with "there isn't one, they're independent" — which is a
legitimate answer, but it leaves the decomposition half (the "should" gate)
exactly as fused as it was found, with the Phase 3.6 4-way branch untouched
in `skills/plan/references/phases/phase-3-decomposition.md`. An author who
wanted "multi-pr in my repo should mean atomic-by-default" gets nothing
today under this alternative — that preference has no home.

**The trust goal is unaddressed, not solved.** The author's stated goal —
"multi-pr becomes reliable evidence that no other option existed" — is
research finding #4's territory, and Alternative 4 does nothing to close
it. It's arguably compatible with deferring (nothing gets worse), but it
isn't progress toward the goal either.

## 3. Risks

**Re-keying the Draft→Active approval gate is real surgery, not a
one-line change.** I read `docs/decisions/DECISION-multi-pr-posture-detection-2026-06-06.md`
in full. Its Context section states the current rule explicitly: "multi-pr
requires human approval (GitHub issues + milestone are created on the
transition), single-pr auto-fires when `/shirabe:plan` finishes authoring."
The decision's *own detection table* is keyed on the PLAN's `status:` field
being uniform across modes — but the *gate* (auto vs. human) is described as
tracking `execution_mode` directly, via the "GitHub artifacts get created"
justification. Once tracking is decoupled, a `single-pr` + `## Plan Issues:
required` plan also creates GitHub artifacts and would need the same human
gate; a `multi-pr` + `## Plan Issues: optional` plan (issueless) would not.
That's a predicate flip from `execution_mode == multi-pr` to
`plan_issues_resolved == required`, touching whatever code path currently
tests the enum for the approval gate — not just documentation. This has to
land in the same PR as the header, or the system ships an inconsistency
where the gate's stated justification (in a currently-Accepted decision
record) no longer matches its trigger condition. That record likely needs
its own amendment, not just new code.

**The `#N` parsing dependency in `plan-to-tasks.sh` blocks issueless
multi-pr from being schedulable, and Alternative 4 has to solve this or
admit it's out of scope.** I read the relevant loop in
`skills/plan/scripts/plan-to-tasks.sh:295-355` directly. For multi-pr rows,
`issue_num` is captured via `re_issue_num` matching `#N` in the first data
cell, and dependency edges are built the same way: `re_issue_ref="#([0-9]+)"`
walks the Dependencies cell for `#N` tokens and resolves each to
`issue-${dep_num}`. An issueless multi-pr PLAN has no `#N` to parse — the
Implementation Issues table would have no GitHub number to key on. Findings
already names this gap (`findings.md:158-163`): single-pr's alternative
scheme (`o-<slug>` from Issue Outlines) is "not a drop-in" because it's
bound to `/execute`'s shared-branch model, which multi-pr deliberately
avoids. This isn't cosmetic — it's the mechanism that turns a PLAN row into
a schedulable task name. Shipping `## Plan Issues: optional` without solving
it means issueless multi-pr plans have no `/work-on`-consumable dependency
graph, i.e., no working "what's next" scheduler. That's not a nice-to-have
gap; it would make issueless multi-pr non-functional for anything with
inter-issue dependencies.

**"Defer" is not free — it's a decision with its own opportunity cost, and
the fused branch stays load-bearing.** Every future `/plan` run through
Phase 3.6 keeps making a should-judgment call that the tree already knows is
principle-inconsistent (P1 forbids reviewability-driven splits;
`coordination-strategy.md` permits them one altitude up). Alternative 4
doesn't make that inconsistency worse, but it also doesn't stop new plans
from being decomposed under it while the follow-up decision waits. If the
follow-up decision doesn't happen promptly, "defer" quietly becomes
"decline" by default.

## 4. Implementation implications

Concrete files touched by tracking-only decoupling:

- `references/fixes/claude-md-conventions.md` — new header row, `## Plan
  Issues: optional|required`, alongside the existing `## Roadmap Issues:`
  row (line ~64) it's modeled on.
- `skills/plan/references/phases/phase-7-creation.md` — currently hardcodes
  `create-issues-batch.sh --milestone` for multi-pr; needs a header-resolved
  branch mirroring how `/roadmap populate` already resolves `## Roadmap
  Issues:`.
- `skills/plan/references/plan-format.md` — `execution_mode` frontmatter
  currently still documented as a two-value enum in places (findings.md
  notes drift re: `coordinated`); this work should not compound that drift
  and may need a `plan_issues` field or header cross-reference.
- `skills/plan/scripts/plan-to-tasks.sh` and
  `skills/plan/references/plan-to-tasks-contract.md` — must gain a
  third source-var scheme for issueless multi-pr rows (no `#N` to key on),
  per the risk above. This is the piece most likely to be underestimated if
  scoped as "just add a header."
- `docs/decisions/DECISION-multi-pr-posture-detection-2026-06-06.md` — the
  Draft→Active gate's stated rationale needs an amendment (or a superseding
  decision) re-keying the trigger predicate from `execution_mode` to
  "does this transition create GitHub artifacts."
- `skills/work-on/SKILL.md:19` — the M<N> milestone selector's precondition
  ("milestone exists") becomes conditional on tracking mode; `/work-on`
  needs a documented answer for "what selects next work in an issueless
  multi-pr plan" (open gap, not solved by the header alone).
- `crates/shirabe-validate` — a `PostureClass::DraftTolerable` finding for
  "GitHub artifacts declared required but the approval gate didn't run" (or
  the inverse), mirroring the pattern already used for other advisory
  checks.

## 5. Recommendation

Ship it, but be precise about what "defer" buys and doesn't. The principle
question (P1 vs. an invertible default vs. a named trigger) is genuinely
separable from tracking — the source-of-truth text in
`workflow-principles.md` already assigns tracking to P2 and cardinality to
P1, so this isn't a post-hoc rationalization. Deferring the principle
question is a real deferral, not a disguised "no": nothing about shipping
`## Plan Issues:` forecloses any of Alternatives 1, 2, or 3 later, since none
of them touch the tracking mechanism.

But "tracking decoupling" is not as small as its blast-radius framing
suggests once the two hard dependents are counted honestly: the Draft→Active
gate re-key and the `plan-to-tasks.sh` `#N`-parsing replacement are both
load-bearing, not incidental, and both are absent from a naive "just add a
header" scope. If this alternative is chosen, the scope should explicitly
include both — shipping the header without them produces an issueless
multi-pr mode that either breaks the approval-gate contract or produces
plans `/work-on` cannot schedule. Framed that way, Alternative 4 is honest
work, not a shortcut: smaller than any option that also resolves P1, but not
free, and it leaves the author's second complaint (the "should" gate) fully
open for a decision that still has to happen.

## Final Position

**Q1 — does separability survive a shared recording slot and shared
`DraftTolerable` check?** Yes, with one condition. I re-read
`skills/plan/references/phases/phase-7-creation.md` directly for this
cross-examination and found the "gate" is not a separate mechanism at all —
it *is* Phase 7's existing `single-pr Mode` / `multi-pr Mode` branch (line 64
vs. 237): single-pr writes the PLAN straight to `status: Active` with no
side effect; multi-pr's 7.1 creates GitHub issues and that act *is* the
Draft→Active transition. So a shared recording slot that captures both "why
not single-pr" (cardinality, P1) and "why GitHub artifacts were/weren't
created" (tracking, P2) as two distinct keys in one frontmatter block, read
by one generic advisory pass, doesn't fuse the decisions — it's the same
pattern the PLAN frontmatter already uses for `execution_mode` and `status`
living side by side, checked by one validator, without anyone claiming
those two fields are one decision. The condition: it only stays separable if
implemented as two independently-settable keys (e.g. `split_trigger:` and
`plan_issues:`), not one overloaded field pressed into service for both
questions — collapsing them into a single value would be the mirror image of
the error `DESIGN-capstone-orchestration.md` Decision G already rejected
(splitting one identity across two fields); cramming two identities into one
field is equally wrong. Shared plumbing is fine; shared *meaning* is not.

**Q2 — rank the two dependents; does either argue for sequencing after the
recording slot?** Reading `phase-7-creation.md` directly changes my
ranking. The Draft→Active gate re-key is not separate surgery — it collapses
into the same Phase 7 branch that tracking decoupling already has to add
(skip 7.1's issue creation when `## Plan Issues: optional` resolves for a
multi-pr plan). It's not free — `DECISION-multi-pr-posture-detection-2026-06-06.md`'s
prose rationale still needs a documentation amendment so it doesn't
misdescribe the trigger — but it's a cheap edit riding work already in
scope, not a second design. The `plan-to-tasks.sh` `#N` scheme is the real
risk: it's a new source-var scheme in a shared, tested contract
(`plan-to-tasks-contract.md`), not a documentation update, and nothing about
building the recording slot first retires it — the recording slot answers
"why," the `#N` problem is "how does `/work-on` find the next task," a
different subsystem entirely. So: no, neither named dependent is a reason to
sequence tracking after the recording slot on its own; the #N scheme has to
be solved as part of tracking regardless of order. The one sequencing
argument I'll grant is the one Q1 surfaces, not Q2's dependents: if the
recording slot is going to be tracking's home for `plan_issues:`, building
that shared frontmatter shape first avoids implementing an ad hoc field for
tracking now and migrating it later.

**Q3 — concede or defend "different principles → two designs"?** Partial
concession. The principle claim is correct and I stand on it: P1 owns
cardinality, P2 owns tracking, and that's in the source text
(`workflow-principles.md:20-22` vs. `:41`), not inferred. But "two designs"
overstates what that separation implies, given how much the two halves
actually share once implementation is examined closely — the same
`flag > header > default` stack, plausibly the same frontmatter block, the
same advisory-validator pattern, and now (per Q2) the same Phase 7 branch
point. The honest answer to "what's the relationship" is closer to: **one
shared mechanism, two independently-triggered decisions** — which argues for
one design document with two decision sections, the same shape
`DESIGN-roadmap-plan-standardization.md` already used for its Decision 6,
rather than either a single fused design or two unrelated efforts. That's a
better answer to the author's actual question than my original alternatives
doc gave, and it doesn't cost Alternative 4 anything: deferring the P1
decision section while shipping the tracking decision section is exactly
what "one design, staged decisions" allows.

**Final position:** Alternative 4 (or 4 co-sequenced with Alternative 5's
recording slot, landing first) remains the right call for *this decision
point specifically* — the P1 question is genuinely separable and doesn't
block tracking. But the deliverable the author actually asked for is better
served by treating this as one design with two decision sections than by
treating tracking and cardinality as two unrelated pieces of work. Ship
tracking now under that framing, name the P1 section as the deliberately
deferred second half of the same document, and use the shared
`split_trigger` / `plan_issues` frontmatter shape from the start so the
later P1 decision has a home to land in rather than a retrofit.
