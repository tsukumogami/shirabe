# /brief Phase 1 discover: work-on-retry-clearing

Invoked under `/scope`'s `parent_orchestration:` sentinel
(`invoking_child: brief`, `rationale: fresh-chain`,
`suppress_status_aware_prompt: true`), so Phase 5 runs the
**parent-delegated-approval** fallback: the brief lands in `Draft` and
`/scope` owns the transition to `Accepted`.

No `--upstream` was supplied and no ROADMAP grounds this topic, so the produced
BRIEF records no `upstream:` field.

## The feature being framed

`/work-on`'s three review-bearing phases -- `scrutiny`, `review`, and
`qa_validation` -- each end a round by writing a results artifact into koto
context and submitting a `passed` outcome. Each also has a `blocking_retry`
outcome that routes back to `implementation` so a coder agent can fix what was
found. The feature being framed is the contract that governs what happens to
last round's results artifact when the workflow comes back around.

## Grounded facts, verified rather than assumed

Checked against the repo and against a live koto 0.11.4 (`koto version` ->
`koto 0.11.4 (eb626d9 2026-08-05T20:38:49Z)`):

1. `koto context` has exactly four verbs: `add`, `get`, `exists`, `list`.
   There is no `remove`. `skills/work-on/references/phases/phase-4a-scrutiny.md:45`
   instructs the agent to run one.
2. All three phases gate on `type: context-exists`
   (`skills/work-on/koto-templates/work-on.md`, the `scrutiny`, `review`, and
   `qa_validation` states). `context-exists` tests presence, not content and
   not freshness.
3. All three `blocking_retry` transitions target `implementation`, and
   `implementation` transitions forward to `scrutiny` for `issue_type: code`.
   So a retry from `review` walks implementation -> scrutiny -> review, and a
   retry from `qa_validation` walks all three. Every retry re-enters every
   review phase at or above the one that fired it.
4. Only `scrutiny` documents a clearing step at all, and that step is the
   broken command. `review` and `qa_validation` document none.
5. `context_assignments:` on a transition -- which would have let the state
   machine itself invalidate the key on the retry edge -- is **not a koto
   feature**. Probed directly: a template carrying
   `context_assignments: {probe_key: "assigned-by-transition"}` on a firing
   transition compiles with the key silently dropped
   (`koto template compile` output carries `target` and `when` only), and after
   the transition fires `koto context list` returns `[]`. koto's `Transition`
   struct (`src/template/types.rs`) has exactly two fields, `target` and
   `when`. This rules out a whole family of otherwise-attractive mechanisms and
   is recorded so the DESIGN does not re-derive it.

## The framing-shift question (R4)

Cold start -- no BRIEF, PRD, DESIGN, or PLAN exists for this topic, so there is
no prior framing to have shifted. Answer: no signal yet.

## Scope decision (lightweight protocol, Tier 2)

<!-- decision:start id="retry-clearing-phase-coverage" status="confirmed" -->
### Decision: how many phases the retry-clearing contract covers

**Question:** Does this work fix the retry-clearing contract for `scrutiny`
alone -- the phase the filed issue names -- or for all three retry-bearing
review phases?

**Tier:** 2. Reversibility is low-cost (extending to two more phases later is a
symmetric edit), a clear winner emerges from the evidence, and this is not the
primary question the phase exists to answer. Under
`references/decision-protocol.md`'s three-signal checklist that is Tier 2, which
stays in the micro-protocol rather than escalating to `/decision`. The
mechanism question is separately Tier 4 and does escalate.

**Evidence:** Facts 2, 3, and 4 above. The three phases are not merely similar
-- they are on one path. Because every `blocking_retry` returns to
`implementation` and `implementation` runs forward into `scrutiny`, a retry
fired from `review` re-enters `scrutiny` *and* `review`, and a retry fired from
`qa_validation` re-enters all three. Fixing `scrutiny` alone would clear the
first gate on every retry and leave the second and third satisfied by the
previous round's artifacts, so the workflow would still advance past `review`
and `qa_validation` on a verdict nobody re-derived. Scrutiny-only is not a
smaller version of the fix; it is a fix that leaves the same hole open two
states later on the same traversal.

**Choice:** All three retry-bearing phases -- `scrutiny`, `review`, and
`qa_validation`.

**Alternatives considered:**
- *Scrutiny alone, matching the filed issue's title.* Rejected on the traversal
  evidence: it does not make a retry safe, it makes the first third of a retry
  safe. The precedent that confined `/execute`'s fix to one state (#279 / PR
  #306) confined it across *skills* and filed the remainder as its own issue;
  here the remainder is two states on the same path inside the same file, with
  no independent issue and no independent decision. Splitting it would ship a
  known-incomplete contract and file an issue against work this PR is already
  touching.

**Assumptions:**
- `issue_type: code` is the path that matters. The `docs` and `task` paths skip
  the review panels entirely (`implementation` routes them straight to
  `verification`), so they carry none of this.

**Consequences:** Three phase files change instead of one, and three gate and
transition shapes change instead of one. The edits are symmetric, which is what
keeps the PR reviewable: a reviewer checks one shape and then confirms the other
two match it.

**Reversibility:** low cost.
<!-- decision:end -->

## Mechanism probe (run against koto 0.11.4, for the DESIGN to consume)

Not a BRIEF-altitude decision, but the facts were established while checking
whether the option space was what the issue assumed. A probe template carrying a
`scrutiny`-shaped state with a `context-matches` gate
(`pattern: '(?s)^\{.*"round": *[0-9]+.*\}\s*$'`) referenced from the `passed`
transition's `when` clause, driven against real koto sessions:

| Case | Stored value | Submission | Result |
|---|---|---|---|
| 1 | `{"passed": true, "round": 2, ...}` via `printf '%s'` | `passed` | advances |
| 2 | overwritten with `{"cleared": true, ...}` | `passed` | **holds**, response names `scrutiny_results` with `matches: false` |
| 3 | same cleared value | `blocking_retry` | advances (the retry edge carries no gate reference, so it stays reachable) |
| 4 | key absent | `passed` | holds, same blocking condition |
| 5 | fresh value written with a **trailing newline** | `passed` | advances |

Case 2 also confirms an overwrite replaces rather than appends: `koto context
list` returns exactly one key after two writes.

Case 5 is the one that changed the pattern. An end-anchored pattern without
`\s*` rejects a value written by a heredoc, because koto stores stdin verbatim
and the heredoc leaves a trailing newline -- which is how all three phases write
today. Anchored strictly, the gate would have failed every legitimate pass. The
`\s*$` makes the gate fail-closed on a cleared value without punishing a
cosmetic difference in how the artifact was written.

## What is deferred downstream

The mechanism -- what command or state-machine shape actually forces the fresh
verdict -- is DESIGN altitude and is not settled here. It is genuinely contested
(one live option changes another repository), so `/design` escalates it to
`/decision` at Tier 4.
