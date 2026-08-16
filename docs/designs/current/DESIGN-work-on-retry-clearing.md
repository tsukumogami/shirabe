---
schema: design/v1
status: Current
upstream: docs/prds/PRD-work-on-retry-clearing.md
problem: |
  Six gates in /work-on hold a key a re-entry can supply from the previous
  round. The only thing preventing a stale pass is the agent submitting an
  outcome that describes the round that just ran, which is prose on the workflow
  whose failure mode is prose being skipped. One phase file records that the
  structural fix is impossible because koto has no removal verb; koto has
  shipped one since v0.11.5.
decision: |
  A clearing block on each of the three retry-bearing paths removes the keys the
  re-entry will re-read, confirms each is gone with `koto context exists`, and
  prints a stdout diagnostic naming the key and the escalate outcome on failure.
  No gate changes: removal makes the presence gates already on main correct.
rationale: |
  `koto context exists` and the `context-exists` gate evaluator call the same
  `store.ctx_exists`, so verifying with it checks the gate's own predicate
  rather than a proxy for it. That is what makes a sentinel and a second gate
  type unnecessary, and it removes the whole class of failure where a marker
  value and a pattern drift into agreement.
---

# DESIGN: /work-on Retry Clearing

## Status

Current

## Context and Problem Statement

`/work-on` gates twelve states on `context-exists`. Six of them can be entered
twice, and on the second entry the gate finds the previous round's artifact and
reports it present. The full enumeration and the traversal that produces each
re-entry are in the PRD's Problem Statement; this document does not restate them.

The technical problem is narrow. koto's engine never writes to the context
store: `context_assignments:` on a transition is dropped at compile time, and a
gate's `key:` is a static literal the compiler copies verbatim. So nothing in
the state machine can invalidate a key on an edge, and any clearing has to
happen in something an agent runs, with the gate doing the enforcing afterwards.

What has changed since this problem was last designed is that koto v0.11.5 ships
`koto context remove`. That single fact removes the constraint the previous
design was shaped around, and the shape that follows is smaller.

## Decision Drivers

- **The guarantee must not rest on prose.** PRD R1 through R3. The current
  mechanism is an instruction to submit the right outcome; the replacement has
  to be something the workflow evaluates.
- **All six gates, with one mechanism.** PRD R1 and R2. A mechanism that reaches
  three of six leaves a follow-up that cannot reuse it.
- **A broken store must not brick the run.** PRD R6. The clearing step sits on
  the retry path, so its failure must still leave a terminal state reachable.
- **The failure must survive `2>/dev/null`.** PRD R4.
- **First-pass behaviour is frozen.** PRD R7.
- **The smallest change that holds.** PRD R5 freezes the gate declarations. A
  design that edits the template buys nothing here and costs a mermaid
  regeneration and eval-fixture churn.

## Considered Options

### Decision 1: how a re-entry is forced to produce a fresh artifact

The R6 shape predicates all fired negative at Phase 1: no architectural
alternative is left open, no new component, no complexity classification. This
is the minimum-roster case, so what follows records the one live option and why
no alternative is live rather than staging a contest between three.

#### Chosen: remove the key on the retry path, verify with `context exists`

Three parts.

**1. Removal, on every path that re-enters.** Each retry edge gains a block that
removes the keys the re-entry will re-read: the three panel keys on a
`blocking_retry`, `plan.md` on both edges that return to `analysis`,
`summary.md` on an `issues_found`. Removal is idempotent, so a key a phase has
not written yet costs nothing and needs no guard.

`plan.md` has two such edges, and both count. `implementation` submits
`implementation_status: scope_expanded_retry` and routes to `analysis`
(`work-on.md:488`), and `analysis` self-loops on `plan_outcome:
scope_changed_retry` (`work-on.md:417`). Both arrive at the same
`plan_artifact` gate holding the plan the state is being re-entered to replace,
so the block goes in `phase-4-implementation.md` as well as
`phase-3-analysis.md`. Covering one and not the other leaves the gate stale on
the uncovered edge, which is the defect this design exists to close.

**2. Verification with the gate's own predicate.** After removing, the block
runs `koto context exists` and requires it to report absent. This is the part
worth reading closely, because it is not the obvious choice and it is stronger
than the obvious choice:

- `koto context exists` calls `store.ctx_exists(session, key)`.
- The `context-exists` gate evaluator calls `store.ctx_exists(sess, &gate.key)`
  (`koto/src/gate.rs:135`).

They are the same function over the same state. So "exists reports absent" is
not evidence that the gate will fail; it *is* the gate's predicate, evaluated
the same way. The removal's own exit status is the weaker signal: `remove`
deletes the content file, then the lock file, then updates the manifest under
lock, so a failure after the content is gone reports non-zero on a removal whose
gate-relevant effect already landed.

The verification is not optional. Probed against koto 0.11.5: with the ctx
directory unwritable, `remove` exits 3, the key survives, and submitting the
phase's advancing outcome then advances the workflow on the stale artifact. A
failed removal is silently fatal without the check.

**3. A stdout diagnostic that names the way out.** On a failed verification the
block prints the key, says which outcome not to submit, and names the escalate
outcome that still reaches a terminal state. stdout because stderr is what
operators redirect to escape koto's migration noise. The escalate half is what
satisfies PRD R6: the block stops the agent from advancing, not from submitting
anything at all.

**And no gate changes.** With removal available, `context-exists` is exactly the
right gate for "this phase must produce a fresh artifact" — remove the key and
it fails. `work-on.md` is not edited.

#### Alternatives Considered

- **Overwrite the key with a sentinel and convert the gate to
  `context-matches`.** This is not hypothetical: it is what the previous design
  for this problem chose, and it was correct then, because koto had no removal
  verb and overwrite-to-clear was the only way to make a cleared key
  distinguishable. It is rejected now on three counts. It cannot reach `plan.md`
  or `summary.md`, which are markdown written `--from-file`, so no pattern
  shaped around a JSON results artifact matches them — the mechanism would cover
  three of six and the other three would need a second technique. It introduces
  a sentinel value into the artifact namespace that a future consumer has to
  learn. And it splits the check from the gate: the block compares strings while
  the gate evaluates a regex, two operations over one value, which creates a
  fail-open mode where the sentinel and the pattern drift into agreement and the
  gate silently starts accepting cleared values. That hazard needed a dedicated
  test case to catch. Under removal it does not exist to catch.

- **Keep the prose guarantee and document it better.** The current mechanism —
  "what keeps an earlier pass from advancing the workflow is the
  `scrutiny_outcome` you submit" — could be extended to the other five phases
  and stated more forcefully. Rejected because it is the same bet that already
  lost: the guarantee is an agent following an instruction, on the workflow
  whose failure mode is an agent not following one. Better prose does not change
  what enforces it.

- **A `command` gate computing freshness from koto's event log.** `koto context
  add` appends a `ContextAdded` event carrying a timestamp to
  `koto-<session>.state.jsonl`, a file koto's `docs/workspace-layout.md` lists
  under AUTHORITATIVE state and whose envelope keys `docs/STABILITY.md` freezes.
  A gate reading it could compute genuine freshness — was this artifact written
  after the most recent re-entry? — and would need no clearing step at all,
  which is strictly more than this design achieves. Rejected as disproportionate
  rather than wrong: it replaces six presence gates with six command gates
  carrying shell, against a defect that a verb koto already ships closes
  directly. It also has a constraint worth recording for anyone reviving it,
  found during the previous design cycle:
  `scripts/check-template-interpolation.sh` rejects bare `$NAME` in `command:`
  fields, so such a gate must express its reads with nested `$(...)` and
  `{{SESSION_DIR}}` only.

## Decision Outcome

Removal, verification, and the diagnostic are one mechanism, and each covers
something the others do not. The removal makes the gate fail. The verification
catches the case where the removal did not take, which is silently fatal
otherwise. The diagnostic keeps a broken store from bricking the run.

What falls out of the choice is that `work-on.md` does not change at all. The
gate main already ships turns out to be the right gate; it was only ever missing
the verb that makes a presence gate actionable. That is the design's main
structural claim, and it is verifiable by an empty diff rather than argued in
prose.

## Solution Architecture

Six files change and one is new. No template, no mermaid companion, no eval
fixtures.

**The three retry-bearing phase files** — `phase-4a-scrutiny.md`,
`phase-4b-review.md`, `phase-4c-qa.md` — each gain the same block on the
`blocking_retry` path, byte-identical below its **first** line:

```bash
OUTCOME_FIELD=scrutiny_outcome   # review_outcome / qa_outcome in the other two
for KEY in scrutiny_results.json review_results.json qa_results.json; do
  koto context remove <WF> "$KEY" >/dev/null 2>&1
  if koto context exists <WF> "$KEY" >/dev/null 2>&1; then
    echo "$KEY is still in context after koto context remove."
    echo "The stale verdict is in place and the gate will accept it."
    echo "Do NOT submit $OUTCOME_FIELD: passed on the next pass."
    echo "To stop the run, submit $OUTCOME_FIELD: blocking_escalate with a failure_reason."
    exit 1
  fi
done
koto next <WF> --with-data "{\"$OUTCOME_FIELD\": \"blocking_retry\"}"
```

The differing line is the first rather than the last because the diagnostic has
to name the phase's own field, and PRD R4 requires it to. Hoisting the field into
a variable at the top is what keeps everything below it identical; a diagnostic
that interpolated the field inline would leave three blocks differing in four
places, and "identical below the first line" is an assertion a harness can make
where "mostly the same" is not.

`phase-3-analysis.md` and `phase-4-implementation.md` each gain the same shape
over `plan.md`, on `plan_outcome: scope_changed_retry` and
`implementation_status: scope_expanded_retry` respectively, and
`phase-5-finalization.md` over `summary.md` on `finalization_status:
issues_found`. Each names its own escalate outcome in the third diagnostic
line: `scope_changed_escalate` for `analysis`, `partial_tests_failing_escalate`
for `implementation`, `deferral_requested` for `finalization`.

**`review-panel-orchestration.md`** gains the all-three contract and loses
nothing else.

**`phase-4a-scrutiny.md`'s Retry Loop section** is rewritten. Its two loadbearing
sentences today are that koto has no removal verb and that the submitted outcome
is what holds the line; the first is false and the second describes the
mechanism being replaced.

**A new harness** at `skills/work-on/scripts/retry-clearing_test.sh`, with a
`work-on` suite registered in `scripts/check-bash-floor.sh` and a
`.github/workflows/check-work-on-scripts.yml` modelled on
`check-execute-scripts.yml`.

### Why the block carries no `exists` guard before removing

An earlier design of this problem guarded each key with `koto context exists ...
|| continue` to skip keys a phase had not written. That is a trap, and it is
recorded here because the shape is tempting: `ctx_exists` collapses "absent" and
"unreadable" into `false` in both backends, so on a transient read failure the
guard skips a key whose real artifact is still there.

It is also unnecessary. `koto context remove` is idempotent — removing a key
that was never written exits 0 — so there is nothing for a guard to protect
against.

### Data flow

```
retry decided (blocking_retry | scope_changed_retry
               | scope_expanded_retry | issues_found)
  for KEY in <the keys this re-entry will re-read>
    koto context remove   ->  key deleted; ContextRemoved event appended
    koto context exists   ->  MUST report absent (the gate's own predicate)
        present? -> stdout diagnostic naming key + escalate outcome; exit 1
  koto next --with-data '<retry outcome>'
        |
        v
implementation (or analysis) -> forward through the re-entered phases
        |
        v
koto advance: context-exists gate evaluated on each re-entered phase
  +-- key absent  + advancing outcome -> no transition; state holds
  +-- key present + advancing outcome -> advances (this round's artifact)
  +-- any         + escalate outcome  -> terminal state, always reachable
```

## Implementation Approach

1. **Add the clearing block to the three panel phase files**, and rewrite
   `phase-4a-scrutiny.md`'s Retry Loop, including the false koto claim.
2. **Add it to `phase-3-analysis.md`, `phase-4-implementation.md`, and
   `phase-5-finalization.md`** over their own keys and escalate outcomes. The
   first two are both `plan.md`; they are separate edges, not a duplicate.
3. **Correct `review-panel-orchestration.md`.**
4. **Write the harness** and run it. It extracts the shipped blocks rather than
   pasting copies.
5. **Register the suite and add the workflow.**
6. **Update and run `/work-on`'s evals.**

Steps 1 and 2 are independent of each other. Nothing here depends on step 4, but
step 4 cannot be written first: the harness extracts the shipped text, so there
is nothing to extract until the blocks exist.

### What the harness must cover

Cases, in the order they should appear:

- Each of the six keys: removed, its gate then holds the phase on the advancing
  outcome, and koto's response names the gate.
- Each of the six: present, the phase advances. First-pass parity, PRD R7.
- The traversal from all three panel entry points, asserting every panel at or
  above the raiser is cleared.
- **Both** edges into `analysis` clear `plan.md`, driven separately:
  `plan_outcome: scope_changed_retry` and `implementation_status:
  scope_expanded_retry`. Covering one and asserting the other by inspection is
  the failure this case exists to prevent.
- `issues_found` clears `summary.md`, and neither `finalization` nor
  `deferral_approval` then advances on it.
- The block exits 0 when a key it removes was never written.
- With the store unwritable: the block exits non-zero, prints on stdout with
  stderr discarded, and names both the outcome to avoid and the escalate outcome.
- **The escalate exits stay reachable with the store broken** — the PRD R6 case,
  driven against real koto rather than read off the template.
- The blocks are byte-identical across the three panel files below their first
  line.

## Security Considerations

**The key lists are fixed literals.** Each block iterates a hardcoded list of
context keys defined in the file it lives in. Nothing is composed from run
state, so no caller-controlled string reaches a `koto context remove` argument.
`"$KEY"` is quoted at every use.

**Removal is scoped by koto, not by the block.** `koto context remove` validates
the key through `validate_context_key` and resolves it under the session's own
ctx directory, so a malformed key is rejected by koto rather than reaching the
filesystem. The block cannot address a path outside the session.

**The blast radius of the new verb is a deletion, which deserves stating.** This
design introduces the first use of a destructive koto verb in shirabe's skills.
What it deletes is a workflow's own intermediate evidence, inside a session
directory koto owns, and only on a path where that evidence is already known
stale. It does not touch the repository, the worktree, or any artifact under
`docs/`. The `ContextRemoved` event koto appends leaves the removal auditable in
the session log.

**The failure mode is fail-closed, with one qualification.** A removal that does
not take is caught by the verification and stops the run before the advancing
outcome is submitted. The qualification is that the verification uses
`ctx_exists`, which reports `false` for an unreadable store as well as an absent
key — but here the collapse runs in the safe direction, because the gate uses
the same call and also reports absent, so the phase refuses to advance either
way. The ambiguity bites a caller that uses `exists` to decide whether to *skip*
work, which is exactly why this design has no `exists` guard.

**`koto overrides record` remains an escape hatch.** It advances past a failing
gate whether or not the gate declares `override_default`. That is correct and
auditable behaviour, and it means the guarantee is structural modulo a recorded
override rather than absolute.

## Consequences

**Positive.** A retry cannot advance any re-entered phase on the previous
round's artifact, and the refusal is the state machine's rather than an
instruction's. One mechanism covers all six gates, including the two markdown
ones no content-shaped pattern could reach. `work-on.md` is untouched, so there
is no template diff, no mermaid regeneration, and no eval-fixture churn. And no
sentinel value enters the artifact namespace, so nothing has to be kept in sync
with a pattern.

**Negative.** The clearing block is duplicated in six phase files rather than
referenced once, and the three panel copies must stay identical — asserted by
the harness rather than by construction. The key list in the panel blocks is a
literal, so adding or removing a panel phase means updating it in three places,
and nothing catches all three agreeing with each other while disagreeing with
the state graph.

**The residual, stated plainly.** The clearing step is agent-performed and an
agent that skips it entirely leaves the artifacts in place. This is better than
what it replaces — today's guarantee is an agent submitting the right *outcome*,
a judgment call, whereas the new one is a command sitting on the same path as
the submission — but it is bounded rather than eliminated. R3's verification
makes a *failed* removal loud; a *skipped* one stays possible.

**Recorded, not fixed.** `context_assignments:` is not a koto feature: the
`Transition` struct carries `target` and `when` only, the block is dropped at
compile time, and the store is empty after a transition carrying one fires. So
every `failure_reason` assignment in `work-on.md` is a no-op, and the escalation
paths propagate no reason to context. Wider than this design and left for its
own issue.
