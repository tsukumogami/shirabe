# Architecture Review (round 3): DESIGN-work-on-standalone-completeness

## Verdict

PASS

## The two prior findings — closed, or a new inaccuracy introduced

**1. Decision 3's Option A rejection reason — closed.** The design now reads:
"Rejected on sequencing: the obligations split cleanly by when they are
observable. Code cleanup, summary shape, the design diagram and the
commit-message convention are all decidable *before* `pr_creation` runs; the
closing keyword and merge cleanliness both need a pull request to exist before
anything can query one. A single state cannot sit on both sides of
`pr_creation` in a linear walk without either running twice — which concedes
that one state cannot hold everything — or deferring the PR-dependent half to
a second pass that is no longer one state." This tracks the report's actual
Option A section: "Obligations split cleanly into two groups by when they're
observable... A single state cannot sit both before `pr_creation` and after it
in the same linear walk without either running twice... or deferring the
PR-dependent checks to a second pass that isn't structurally a single state
anymore." The design's closing line — "'One state' therefore degrades in
practice into a pre-PR batching state plus reuse of the existing post-PR
states, which is the hybrid actually chosen, reached honestly rather than by
accident" — is the report's own conclusion ("which is really a hybrid, not a
clean single-state design"). This is no longer Option C's carve-out reasoning
("re-deriving these as new standalone states would mean re-justifying
invariants `execute.md` already worked out"), which the design now correctly
reserves for its own rejection of "Extending existing states in place
throughout" and for the Recommendation's actual chosen-hybrid text. Fixed, and
correctly attributed.

**2. "Grows four states" — closed, and the correction did not introduce a
third inaccuracy.** Consequences now reads: "`work-on.md` grows **three**
states — the pre-PR evidence state, `cascade_entry` and `cascade_run` — in a
template that already declares twenty-eight, plus one new edge from
`cascade_run` into the pre-existing `done_blocked` terminal for a `partial`
cascade. An earlier draft called that edge a fourth state; it is not, and the
miscount is recorded here rather than silently corrected because it is the
second time a stated cardinality in this document disagreed with its own
enumeration." I checked `work-on.mermaid.md` and the Solution Architecture
Components table (line 390: "one new pre-PR evidence state; new cascade-entry
and cascade states") — three states, consistent. The Decision Outcome's R5
paragraph was also corrected: "an earlier draft of this design omitted it
entirely — a gap its own Consequences section pointed at by claiming four new
states while naming three" (referring to the round-1 draft's gap), and the
mechanism itself is now labeled correctly: "The halt is therefore an explicit
failure **edge** rather than a new state: `cascade_run` accepts
`cascade_status`, routes `completed` and `skipped` to `done`, and routes
`partial` into the pre-existing `done_blocked` terminal... No new terminal is
introduced." I grepped the whole document for "four"/"fourth" — the only
remaining hits are "A fourth run" (the fourth field observation, unrelated)
and the two places above, both now describing the miscount as history rather
than repeating it. No third inaccuracy was introduced; the correction is
internally consistent between Consequences and Decision Outcome.

## The rewritten file-placement constraint

Sound, and appropriately hedged. The new text drops the retracted claim ("a
child never loads `SKILL.md`") for the narrower one — reachability depends on
whether the compiled template leads to the obligation, not on the filename —
and grades its own evidence honestly: "Established by file inspection, not by
watching a spawn... an observed materialization would be better evidence if
one falls out of implementation." I verified the load-bearing citations
directly against the current code rather than trusting the prose:

- `koto/src/cli/init_child.rs` contains no reference to `SKILL.md`, no prompt
  construction, no process spawn — confirmed by grep. Supports "koto does not
  load `SKILL.md`."
- `work-on.md`'s `## verification` state text points to "the `## Definition of
  Done` section of SKILL.md" — confirmed, supporting the claim that a child
  *can* reach `SKILL.md` when a state's prose cites it.
- `SHARED_BRANCH` is a declared template variable (near line 34-38), consumed
  in `setup_plan_backed`'s `skip_if: vars.SHARED_BRANCH` condition (near line
  283-287), with "do not create a branch" reinforced by
  `references/phases/phase-1-setup.md:15` ("If `SHARED_BRANCH` is set
  (plan-backed mode), use it — skip branch creation") and the shared-PR route
  reinforced by `references/phases/phase-6-pr.md:52` ("`pr_status: shared` —
  set when running as a plan-backed child with `SHARED_BRANCH` set. No PR is
  created or monitored"). All confirmed present, at or within a couple lines
  of the cited numbers, and all in template prose rather than `SKILL.md`.

The reasoning that follows is coherent: the two "SKILL.md-only" additions this
design actually makes (`skills/work-on/SKILL.md`'s multi-pr refusal,
`skills/execute/SKILL.md`'s third execution path) don't violate the
sharpened constraint, because both are reasoned about explicitly on grounds
independent of the retracted claim — "no session should exist for a plan that
is refused — the decision happens before one is created" (Decision 5) means
there is no child to fail to reach, not that `SKILL.md` is safely unreachable.
R10's Decision Driver ("means `work-on.md` and never `SKILL.md` alone")
already used the narrower framing and needed no correction. Nothing else in
the document leans on the stronger, now-retracted claim.

## Strawman check, per decision

- **Decision 1:** unchanged from round 2, still fair — verified again against
  `execute.md:598,618` and `assert-child-template.sh`.
- **Decision 2:** unchanged, still fair.
- **Decision 3:** now fair on all three alternatives, verified above and
  against Option B/C's buys-and-costs, which match the report closely (Option
  B: "maximal isolation... a later change to one cannot entangle review of
  another" tracks "isolates blast radius"; Option C: "load-bearing for the
  deferral human-gate contract, so a change to the design-diagram evidence
  field would drag review of the human-approval path with it" is close to the
  report's own words).
- **Decision 4:** unchanged, still fair.
- **Decision 5:** unchanged, still fair (the squash-merge rejection reason
  fixed in round 2 remains fixed).

## Requirement coverage

R1-R4, R5/R5a, R6-R10, R11-R13, R14-R22 all still have a traceable home,
matching round 2's assessment; nothing inspected here regressed. R5
specifically: the cascade's `partial` verdict routes to `done_blocked` with
recovery guidance split by whether `commit`/`push` reached `ok`, matching
`execute.md:735-740`'s two recovery shapes, and is now correctly described as
an edge rather than a state. R8's classification table and R19a's regression
test are not reproduced inside the design body, but neither was expected to
be (like the routing-claim inventory, they are implementation-time artifacts
the design commits to producing, and this was already the case in rounds 1-2
without objection).

## Required changes

None.
