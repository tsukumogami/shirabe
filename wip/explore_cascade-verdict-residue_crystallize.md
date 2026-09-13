# Crystallize Decision: cascade-verdict-residue

## Chosen Type

File an issue. The issue already exists: it's #354 itself, with its first and third
criteria reworded. The next step is `/work-on 354`: a docs-only PR against
`DESIGN-completion-cascade.md` and the script's verdict comment, with `Fixes #354`.

This is recommended and awaits the coordinator's confirmation. See "Open question
for the coordinator" below: this arm's own guard objects when the decisions file
has entries, and it does.

## Candidacy

- /execute: not a candidate. The only PLAN in `docs/` is
  `docs/plans/PLAN-work-on-friction-fixes.md`, which is `execution_mode: multi-pr`
  and on another topic. (VERIFIED)
- Competitive analysis: not a candidate. The repo is public. (VERIFIED)

## Rationale

The exploration answered its core question. The residue of #354 is documentary, and
changing the code back isn't safe.

- **Why a docs-only answer is safe, not just convenient.** On 7cd13d1 the cascade's
  verdict is `partial` iff some step is `failed`. The only production reader of a
  step's `status` is `execute.md`'s halt on a `partial`, which prints
  `.steps[] | select(.status == "failed")` to say why the run stopped (VERIFIED by
  reading; `execute.md` is read-only here).
  - Reverting the not-found arms to `skipped` would make that halt stop with nothing
    printed.
  - It would falsify `execute.md`'s definition of `partial` ("at least one failed").
  - It would break the rule the suite pins: Scenarios 5, 12, 28 and the post-verify
    scenarios. The suite is MEASURED at 33 passed / 0 failed.
  - So the `failed` label #353 chose carries weight, and the documents must move to
    it, not the other way round.

- **What the design actually says** (VERIFIED by reading). It has one model for this
  case, in four places: a `skipped` step under a `partial` verdict (`:340-356`,
  `:388-391`, `:407-410`, `:572-574`). Its one internal contradiction is `:562-564`
  ("silently skipped"). The "Failures" table at `:296-304` that #353 cited is an
  error-message contract: it covers skipped and failed steps alike, and its "Issue
  still open" row ships as `skipped` under `completed`. The code comment at
  `run-cascade.sh:486-499` and the #353 PR body misread it.

- **The work** is one bounded, docs-only change one person can make without a
  written contract:
  - correct those passages in place;
  - state the step-status rule the design never wrote down;
  - fix the script's emit comment (`run-cascade.sh:1129-1136`), which leaves
    not-found out of `partial` and overstates `completed`;
  - fix the misreading in the handler comment (`:486-499`);
  - reword #354's first and third criteria.

  It needs neither `execute.md` nor `work-on.md`.

## Stage 1 Evidence

### Signals Present
- A chain, "converged on something someone will build": the design amendment and the
  criteria rewrite.
- A chain, "decisions need a durable home and downstream work": the step-status rule
  (`failed` means asked and couldn't; `skipped` means nothing to do, couldn't verify,
  or deferred). Its home is the amended design.
- A chain, "a scope boundary emerged": #354's docs fix is in; the ROADMAP lookup gap
  is handed off; the #358 architecture rewrite is out.
- Decision Record, "a single decision with clear options was evaluated": `failed` vs
  `skipped`, with resolutions (a) through (d) costed by lead-consumers-and-landing.
- Decision Record, "future contributors need to understand why": yes. #353 recorded
  the reason by misreading a table.
- Decision Record, "compared specific alternatives with trade-offs": yes.

### Anti-Signals Checked
- A chain, "nothing was left to build": not present. The docs fix remains.
- A chain, "the whole output is one choice between named options": not present. The
  criteria rewrite and the landing against #358 come with it.
- Decision Record, "multiple interrelated decisions came with work attached":
  present.
- Rejection Record, "leads ran out without a conclusion": the conclusion is to
  proceed. No positive rejection evidence exists for #354's direction.
- Spike Report, "the question is not feasibility": present.

### Ranking
- A chain: 3
- Decision Record: 2 (demoted)
- Rejection Record: 0
- Spike Report: -1 (demoted)
- Competitive Analysis: not a candidate

## Stage 2 Evidence

Stage 2 ran because a chain ranked top in stage 1.

### Signals Present
- File an issue, "simple enough to act on directly": about five passages in one
  design, two comments in the script, an issue-body edit.
- File an issue, "one person can implement without coordination": yes. #358
  sequencing is noted as a follow-up, not a prerequisite.
- File an issue, "short exploration (1 round) with high confidence": yes.
- File an issue, "the right next step is just do it": yes.
- /scope, "decisions made during exploration should be on record": the step-status
  rule.

### Anti-Signals Checked
- File an issue, "any architectural, dependency, or structural decisions were made":
  present. The step-status rule is a contract decision, and the deliverable writes it
  into the design it amends.
- File an issue, "others need documentation to build from" and "multiple people":
  not present.
- /scope, "one person can act on this without a written contract": present.
- /scope, "a single coherent feature, unclear requirements, approach between
  options": none present.
- /charter: nearly every anti-signal is present, because the project exists and the
  work is one bounded fix.

### Ranking
- File an issue: 4 - 1 = 3 (demoted)
- /scope: 1 - 1 = 0 (demoted)
- /charter: negative (demoted)

Both leading options carry one anti-signal each, so the demotion rule leaves their
order unchanged. File an issue leads by three points, outside the one-point
tiebreak window.

## Tiebreakers Applied
- None needed; the margin is outside one point. Were it needed, "/scope vs file an
  issue" would answer the same way: one person can act without a written contract.

## Alternatives Considered
- **/scope**: it would carry the step-status decision into a PRD or DESIGN of its
  own. That's a full chain for a five-passage correction, and the decision's natural
  home is the design being corrected.
- **Decision Record via /decision**: it would give the `failed`-vs-`skipped` rule its
  own ADR. It ranked lower because the decision comes with work attached. It stays a
  fallback if the coordinator wants the rule recorded apart from the design.
- **Rejection Record / Spike Report**: neither fits. The conclusion is to proceed,
  and feasibility was never the question.

## Open question for the coordinator

The file-an-issue arm's guard says that if the decisions file has entries, the
exploration "decided something that needs a durable home" and filing an issue is the
wrong arm. Here the decisions do have a durable home: the deliverable writes the
step-status rule into `DESIGN-completion-cascade.md`, the document that should always
have stated it. The other entries (the handoff, crystallize, scope exclusions) are
process decisions that the PR body and the #354 closing comment carry.

Recommendation: take the file-an-issue arm, reusing #354, on the condition that the
PR states the rule in the design. Alternative: `/decision` for a standalone ADR
first, then the same PR.

Coordinator's provisional answer, pending its verdict: proceed without a separate
`/decision`. The design is the durable home, and an ADR would be a second copy to
drift.

## Review depth

The explore skill doesn't call for a jury or review panel at any phase. What did run:

- Four research agents, one per lead, each working separately:
  - design reading
  - step-status vocabulary
  - behaviour gaps
  - consumers and landing
- The orchestrator re-read the load-bearing claims against the code and docs, and
  re-ran the cascade suite (33 passed / 0 failed).

The claim that carries this routing, that `execute.md`'s halt prints only `failed`
steps, reached the routing decision verified only by reading. The coordinator's
repo agent was its first execution. That review ran `execute.md`'s halt block
exactly as written, with both arms reverted to `skipped`: a `partial` halted rc=1
and printed nothing. With `failed` it printed the reason.

The same review found a gap in the criteria. Reverting only the second not-found arm
leaves the suite at 33/0, so AC2 now requires a scenario for that arm. It also added a
criterion that the design states the step-status rule.

## Proposed wording for #354's reworded criteria

This file is the source text. The coordinator's side applies issue edits to #354 and
#358 through one writer, after review; this worker doesn't edit either issue.
- **AC1:** A ROADMAP feature the cascade can't find yields `cascade_status: partial`,
  recorded as a `failed` `update_roadmap_feature` step carrying the design's "no
  matching feature entry was found" detail. This covers both arms: no `Downstream:`
  line names the plan slug, or the line has no `### ` heading above it.
- **AC2:** unchanged. Scenario 28 covers the first arm (MEASURED PASS). A scenario
  for the second arm is optional.
- **AC3:** `DESIGN-completion-cascade.md` describes this case the way the script
  records it: step `failed`, verdict `partial`. The worked example, the
  `handle_roadmap` step list, and the Consequences and Mitigations prose all agree.

## Landing against #358

- Land the #354 amendment first. It touches none of the architecture sections #358
  rewrites.
- #358's suggested scope ("worked examples as they are") and its third criterion
  ("remain available as the cascade's contract") need editing regardless. On
  7cd13d1 the report schema has drifted in more places (VERIFIED by reading):
  - the `action` enum lists `transition_roadmap`, which is never emitted, and misses
    six emitted actions;
  - "always emits JSON to stdout" is false;
  - the `check_issue_closed` origin-equality claim is false.
- Proposed wording for #358's third criterion: "the report schema and worked examples
  remain available and match what `run-cascade.sh` emits."

## Unfiled neighbours to propose (not this worker's)

- **A not-found run through a DESIGN, PRD or BRIEF chain still commits and pushes
  before reporting `partial`** (AGENT-MEASURED, E1/E2/E2b/E2c). Scenario 28's comment
  "nothing publishes" holds only for the direct shape. `execute.md`'s recovery list
  has no entry for this state, and adding one needs the read-only file, so the
  coordinator has to sequence it.
- **The open-issue `delete_roadmap` skip can't be recovered from**
  (AGENT-MEASURED, E7/E7b/E7c; re-run exit VERIFIED by reading). Its advice to "run
  the cascade again" can't be followed once the PLAN is deleted, and a `gh` failure
  is read as "issue still open". This may fold into the lookup-gap issue the
  coordinator is filing.
- **Already filed, so not proposed:** #362 covers the no-op awk rewrites and the
  `git add ... || true` sites.
</content>
