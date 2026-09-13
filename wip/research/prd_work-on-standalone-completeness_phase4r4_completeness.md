# Completeness Review (round 4): PRD-work-on-standalone-completeness

## Verdict

PASS

## The R16a exclusion — gap or correct scoping

Correct scoping, with one edge case worth naming as an observation rather than
a required change.

The exclusion draws its line at the right altitude: "the surface" is defined
as the live operational corpus (skill prose/frontmatter, references, routing
tables, evals, README, shared references) plus exactly the two documents R18
names as making a decision-level claim this feature contradicts — an accepted
requirement in `PRD-execute-skill.md` and the chosen option in
`DESIGN-execute-skill.md`. Everything else at terminal status is left alone on
the theory that the repository corrects settled decisions by supersession, not
by editing history after the fact — which is how this repository already
treats decision records generally.

I went looking for a document that would break this: a terminal-status
artifact, not named by R18, that makes an actual decision-level assertion
about which entry point runs a multi-pr plan. I found one candidate,
`docs/designs/current/DESIGN-capstone-orchestration.md` (status: `Current`,
i.e., terminal for a DESIGN), which says "`/work-on` collapses issues to PRs
only via the `single-pr`/`multi-pr` binary" and binds its own coordinated-mode
decision to `/scope` and `/work-on`. Checked against
`skills/work-on/SKILL.md`'s actual current dispatcher logic, that line is
descriptive background explaining why coordinated mode needed cross-repo
work, not a "chosen option" the way `DESIGN-execute-skill.md`'s is — it never
weighs single-issue-skill-vs-plan-entry-point as an alternative and decides
between them. It will read as mildly imprecise once `/work-on` stops running
`multi-pr` in place, but a reader relying on it to learn where a multi-pr plan
runs would still land in roughly the right place, and it isn't the kind of
"documented capability that doesn't exist" the BRIEF's motivating problem was
about. That distinguishes it from the two documents R18 does name, both of
which assert the old routing as their own settled content rather than in
passing. I don't think this rises to a gap R18 was obligated to close.

## The changed text

**R16a's "What 'the surface' bounds" clause** is new since round 3 and is the
centerpiece of this round's review — assessed above.

**R19b** gained a block distinguishing "the merged pull request" from "the
filed issue" as its referent, with a testable definition of "reuse" (same
named helper/discriminator; a search for a second implementation returns
nothing) and an escalation clause for the case where the other fix hasn't
landed or differs. This directly answers round 3's own observation (there
noted as a minor miss, not required) that R19b had no stated fallback for a
late or differently-shaped upstream fix. It now does, and ties the "reuse"
verb to something a reviewer can actually check rather than leaving it to
interpretation.

**The terms clause** opening Requirements ("A *run* and a *session* are the
same materialized thing seen at two layers...") is new, purely definitional,
and exists to ground this document's own R19/R19a/R19b vocabulary shift to
"session." It doesn't add or remove testable content and doesn't create any
new goal-traceability surface to check.

**Two new acceptance criteria** — one requiring inventory rows correspond to
actually-edited files ("the named file at the named location contains that
row's 'after' text and no longer contains its 'before' text"), one requiring
classifications be correct rather than merely present (a gate-enforced row
must name a gate that exists and fails when driven to failure; an
evidence-carried row must name a field the schema marks required) — both
attach to existing requirements (R16a, R8) rather than introducing new ones,
so they don't create new orphans in either direction.

## Per-criterion findings

1. **Section order/presence** — Status, Problem Statement, Goals, User
   Stories, Requirements, Acceptance Criteria, Out of Scope, Decisions and
   Trade-offs, Known Limitations. Unchanged from round 3, still complete and
   correctly ordered.

2. **BRIEF IN items** — unchanged since round 3; all six still covered by
   R1–R18 as previously mapped.

3. **BRIEF OUT items** — Out of Scope section unchanged this round; all six
   still present and worded consistently with the BRIEF.

4. **BRIEF's three deferred Open Questions** — all three still closed under
   Decisions and Trade-offs (multi-pr refusal-with-pointer, no-anchor
   pass-through, supersession-by-decision-record). Untouched this round.

5. **Goal-requirement traceability** — the terms clause and the two new ACs
   attach to existing requirements; no new requirement was introduced this
   round, so no new orphan risk on either side. R16a/R16b/R18 continue to
   trace to the goals clause about the plan entry point becoming the sole way
   a plan is run.

6. **The R16a exclusion (this round's focus)** — see above. Judged as correct
   scoping.

7. **Content boundaries** — the new R19b block and R16a clause stay at
   requirements altitude: they state a referent, a test for "reuse," and an
   escalation rule, without prescribing where the shared mechanism lives or
   how it's implemented. In bounds.

8. **Out of Scope consistency** — unaffected by this round's edits; still
   consistent with the requirements it excludes.

## Required changes

None.

## Observations

- `docs/designs/current/DESIGN-capstone-orchestration.md` contains one
  sentence that will be mildly stale after this feature ships (it describes
  `/work-on` as handling the `single-pr`/`multi-pr` binary directly, which
  stops being true once `multi-pr` moves to the plan entry point). It's
  background prose in service of a different decision, not a claim this
  feature "contradicts" in R18's sense, so I don't think it belongs in R18's
  two — but if a future reader ends up confused by it, this is the document
  to point them past.
- R19b's fix for round 3's fallback observation is a clean, complete close —
  no residual concern there.
