# Architecture Re-Review: DESIGN-work-on-standalone-completeness

## Verdict

FAIL

## The four prior findings — closed or not

**1. PRD R5 (cascade failure-recovery handling) — closed.** The Decision Outcome
now states: "`run-cascade.sh` reports `completed`, `partial` or `skipped`
(`execute.md:439-455`)" and cites the recovery split at `execute.md:735-740`.
Both citations check out against the current `execute.md`: lines 439-455 are
the `plan_completion` `accepts`/`transitions` block naming the three enum
values, and lines 735-740 are the two recovery-shape bullets ("A refused
`transition_*` with NO `commit` step: the cascade published nothing on
purpose... A refused `transition_*` WITH `commit` and `push` at `ok`: ...
recovery is a follow-up commit or a revert, not a reset"). The design's own
text — "a refused transition *without* `commit` and `push` at `ok` leaves
nothing published, so recovery is local; a refused transition *with* them
published what it reached... recovery is a follow-up commit or a revert
rather than a reset" — is a faithful paraphrase. The routing divergence is
also correctly reasoned and matches the cited source: `/execute` routes all
three verdicts to `ci_monitor` (confirmed identical target on all three
`when:` branches at lines 447-455) and lets the halt be agent-observed
(`execute.md:757`, confirmed: "There is no separate terminal for `partial`,
so the halt is the agent's to observe rather than the machine's to
enforce"), whereas this design runs the cascade after `ci_monitor` and
therefore needs `cascade_run` to route `partial` to `done_blocked` itself.
R5's "identically... including the same recovery guidance" requirement is met
in substance.

**2. "Grows four states" — named now, but the label is still wrong.**
Consequences now reads: "`work-on.md` grows four states — the pre-PR
evidence state, `cascade_entry`, `cascade_run` and the `partial` failure
route — in a template that already declares twenty-eight," and the Decision
Outcome section calls out the prior gap by name: "an earlier draft of this
design omitted it entirely — a gap its own Consequences section pointed at by
claiming four new states while naming three." So the omission is fixed at the
letter: a fourth item is named, and the data-flow diagram does show it (the
`done_blocked` box under the `cascade_status: partial` branch, with "failing
step's detail + shape-specific recovery" annotated beneath it).

But the fourth item is not a new state. I checked `skills/work-on/koto-templates/work-on.mermaid.md`:
`done_blocked` already exists as a terminal with 20 existing incoming edges
(`analysis`, `ci_monitor`, `context_injection`, `deferral_approval`,
`implementation`, `pr_creation`, `pr_precheck`, `verification`, etc. all
transition into it today). The Solution Architecture Components table itself
only claims three new states — "one new pre-PR evidence state; new
cascade-entry and cascade states" — and the mermaid row says "One entry per
new state, per check 1," which is consistent with three, not four. Routing
`cascade_status: partial` to the pre-existing `done_blocked` terminal is a
new *edge*, not a new *state*: `work-on.md` doesn't grow a fourth state, it
grows three states and one new transition into a state it already had. The
document's own Decision Outcome text even says this plainly a few lines above
the Consequences claim — "this design runs the cascade *after* `ci_monitor`,
so there is no later state to absorb a halt. The fourth state is therefore an
explicit failure route: `cascade_run` accepts `cascade_status`... and routes
`partial` to `done_blocked`" — which describes a branch inside the
already-counted `cascade_run` state, not a fourth node. Naming something is
not the same as it being what it's named: this is the same class of
inaccuracy the original finding flagged, just narrower and dressed up to hit
a target count of four rather than left as an unexplained gap.

**3. Decision 3's rejected alternatives — "what it buys" restored, but the
unsupported rejection reason for the batching-state option was not
replaced.** All three alternatives now lead with a "buys" clause, matching
the required-changes item ("acknowledge Option B's real auditability
advantage") — Option B's buys clause ("maximal isolation: each obligation's
failure is its own state, legible in the run record, and a later change to
one cannot entangle review of another") and Option C's buys clause ("zero new
states and no mermaid changes, the smallest diff of the three") both track
`decision_3_report.md`'s actual "What it buys" sections closely.

Option A does not. The design still rejects "One batching state for
everything" with: "Rejected because two of the obligations have byte-level
precedents in `execute.md`, and re-deriving them as new standalone states
means re-justifying invariants that template already settled — for no
legibility gain, since `validate-template-mermaid.sh` check 4 makes copying
the merge gate verbatim close to mandatory anyway." That is nearly verbatim
the *report's own justification for Option C's two-obligation exception* in
its Recommendation section ("Re-deriving these as new standalone states would
mean re-justifying invariants `execute.md` already worked out, for no
legibility gain... `validate-template-mermaid.sh` check 4 makes copying the
merge-cleanliness gate verbatim close to mandatory rather than optional") —
not the report's stated cost of Option A itself, which is "The sequencing
problem this runs into immediately": pre-PR and post-PR obligations split by
when they're observable, so "a single state cannot sit both before
`pr_creation` and after it in the same linear walk without either running
twice... or deferring the PR-dependent checks to a second pass that isn't
structurally a single state anymore" — i.e., the batching option is not
merely suboptimal, it doesn't structurally work as described. The prior
review named this exact substitution and asked for the swap by name:
"replace the Option A rejection reason ('re-derives invariants `execute.md`
already settled') with the report's actual reasoning (the pre-PR/post-PR
sequencing problem)." The current text still uses the same reasoning the
prior review flagged as misattributed, now with a buys-clause bolted in front
of it. This required change was not made.

**4. Decision 5's PR-body rejection — closed.** The fabricated causal link
("deleted by the squash-merge, which is how material has been lost here three
times in two days," tying an unrelated incident to this claim) is gone; I
grepped the current document for "three times," "two days," and
"squash-merge" and the only hit is the new text. The rejection now reads:
"PR-body text, which buys zero repository footprint and puts the inventory
where reviewers already read, but is not durable — these pull requests
squash-merge and the branch is deleted, so the body is not where a later
reader looking for the routing surface would find it." This matches
`decision_5_report.md`'s actual reasoning: "R16a requires the inventory to be
'committed with the change' and the acceptance criteria describe re-running
its command and checking rows against the merged tree — both presume the
inventory survives the squash-merge. A PR-body Part 2 location does not
survive it. This option fails on its own terms, not on taste." The option
now states what it buys, as required.

## The added problem-statement paragraph — earns its place

Earns it. The fourth-run paragraph is immediately followed by two paragraphs
of deliberate epistemic hygiene: it names the confound ("Part of the cause
was a coordination gap rather than a skill gap: the brief that dispatched
that worker named its entry point and never said what should pick up the
finished plan"), states plainly that what it reveals — the undefined handoff
at chain exit — "is a real defect and it is **not** one this design
addresses; it is not in the accepted PRD's scope, and it argues for
specifying the handoff rather than for any of the directions this feature
chose between," and closes by tying it back only to the general diagnosis
("when the finishing discipline is not enforced where the work happens,
capable agents reconstruct it by hand or skip it") rather than to any
decision this design makes. It is used as corroborating evidence for the
motivation, not smuggled in as a requirement or a design driver — Consequences
lists it under "What is deliberately left to other work" with the same
scoping language repeated. This is honest handling, not scope drift.

## Strawman check, per decision

- **Decision 1:** well-represented; matches `decision_1_report.md`'s
  alternatives and reasoning.
- **Decision 2:** well-represented; the false-negative failure direction and
  the gate-only shape match the source report.
- **Decision 3:** the two extend-in-place obligations and Option B/C are
  fairly stated; Option A's rejection reason is still misattributed (see
  finding 3 above) rather than a strawman built from nothing, but it is not
  the report's actual case against Option A.
- **Decision 4:** well-represented; the mechanical argument for one
  discriminator, two consumption sites is accurately drawn from its source.
- **Decision 5:** well-represented after the fix; both real-choice questions
  (inventory location, refusal mechanism) now carry accurate buys/costs on
  both sides.

## Requirement coverage

R5 (cascade failure handling), R5a (dependency direction), R6/R7/R8/R9
(enforcement altitude and classification), R10 (reachability, now argued at
length with file-level citations), R13, R19b, R22, and the R16a/R16b routing
inventory are each addressed with a traceable mechanism in Solution
Architecture or Decision Outcome. No requirement inspected here is silently
dropped. The one substantive shortfall is internal, not a coverage gap:
Decision 3's stated rejection reasoning for the batching alternative doesn't
match its own source material, which is a fidelity problem within a covered
requirement rather than an uncovered requirement.

## Required changes

1. Replace Decision 3's rejection reason for "One batching state for
   everything." The current text ("two of the obligations have byte-level
   precedents... re-deriving them... for no legibility gain") is the report's
   justification for Option C's two-obligation carve-out, not a reason
   Option A itself fails. Use the report's actual case: pre-PR and post-PR
   obligations are observable at different points in the walk, so a single
   state can't host both without running twice ("Option A run twice"), which
   is a structural objection, not a legibility preference.
2. Fix the Consequences claim "`work-on.md` grows four states." Three states
   are added (the pre-PR evidence state, `cascade_entry`, `cascade_run`); the
   `partial` route is a new transition into the pre-existing `done_blocked`
   terminal (confirmed already present with 20 incoming edges in
   `work-on.mermaid.md`), not a fourth state. State the count as three states
   plus one new failure edge into an existing terminal, or otherwise stop
   calling the edge a state.
