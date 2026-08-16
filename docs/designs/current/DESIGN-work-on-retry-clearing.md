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

**1. Removal, on every path that re-enters, covering the whole traversal.** Each
retry edge gains a block that removes every key its re-entry will re-read and
whose artifact the retry invalidates. Removal is idempotent, so a key a phase has
not written yet costs nothing and needs no guard.

The key set follows from one rule rather than from each phase's own output, and
this distinction is the design's second structural claim. Every retry returns to
`implementation`, directly or through `analysis`, and a code-typed run walks
forward from there through `scrutiny`, `review`, `qa_validation`, `verification`
and `finalization`. So every retry invalidates all four code-derived artifacts —
the three panel verdicts and `summary.md` — because the code they describe is
about to change. Edges that return to `analysis` to rewrite the plan invalidate
`plan.md` as well; the others do not, because the plan is still the thing being
implemented.

| Retry edge | From | Returns to | Keys cleared |
|---|---|---|---|
| `blocking_retry` | each panel | `implementation` | the four code-derived |
| `verification_outcome: failed` | `verification` | `implementation` | the four code-derived |
| `finalization_status: issues_found` | `finalization` | `implementation` | the four code-derived |
| `implementation_status: scope_expanded_retry` | `implementation` | `analysis` | those four **+ `plan.md`** |
| `plan_outcome: scope_changed_retry` | `analysis` | `analysis` | those four **+ `plan.md`** |

Deriving the set from the traversal rather than from the raising phase is what
this design got wrong first time and is worth stating plainly. An earlier version
cleared each phase's own key: the three panel keys on a `blocking_retry`,
`plan.md` on the analysis edges, `summary.md` on `issues_found`. That is right
about the key the phase writes and wrong about the traversal the retry begins.
Driven against real koto, two edges then advanced on a round-1 verdict with no
round-2 artifact written — `verification_outcome: failed`, which had no clearing
step at all, and `issues_found`, which cleared only `summary.md` and left all
three panel verdicts standing. `scope_expanded_retry` had the same shape.

`plan.md` has two edges and both count. `implementation` submits
`scope_expanded_retry` and routes to `analysis` (`work-on.md:488`); `analysis`
self-loops on `scope_changed_retry` (`work-on.md:417`). Both arrive at the same
`plan_artifact` gate holding the plan the state is being re-entered to replace.

`verification` is the one edge with no phase reference file — its directive lives
in the template — so its block goes there. That costs the empty template diff an
earlier draft of this design claimed as a virtue. It is prose in a directive, not
a gate change: PRD R5 holds, `koto template compile` exits 0, and the mermaid
companion is unchanged because directive text is not part of the graph.

**2. Verification on two signals, because neither alone is sufficient.** After
removing, the block stops if **either** `remove` reported failure **or**
`koto context exists` still reports the key present. That belt-and-braces shape
is not caution; each signal covers a blind spot the other has, and both blind
spots were reached by probing koto 0.11.5 rather than reasoned about.

*Why `exists` is needed.* It is the gate's own predicate rather than a proxy for
it: `koto context exists` calls `store.ctx_exists(session, key)`, and the
`context-exists` gate evaluator calls `store.ctx_exists(sess, &gate.key)`
(`koto/src/gate.rs:135`) — the same function over the same state. It catches a
removal that returns success without the key going away. `remove`'s status
cannot: it deletes the content file, then the lock file, then updates the
manifest under lock, so it can report non-zero on a removal whose gate-relevant
effect already landed.

*Why `exists` is not enough.* `ctx_exists` collapses "absent" and "unreadable"
into `false`. With the ctx directory unreadable, `remove` exits 3 and the key
survives on disk, but `exists` reports **absent** — so a block trusting `exists`
alone exits 0 believing it succeeded.

The refusal that follows looks like it saves us and does not. The gate makes the
same blind read, so the advancing outcome is refused at the moment it is
submitted. But koto buffers that evidence and re-evaluates it: restore the
permissions, make no further submission, and the workflow advances to the next
state on the previous round's artifact. Probed directly, with a control showing
a lock/unlock cycle and no submission leaves the state untouched — so the
advance is caused by the buffered evidence, not by the permission change.

That is the defect this whole design exists to close, reachable through a
transient outage, and it is why `remove`'s exit status is checked rather than
treated as the weaker signal. An earlier draft of this design asserted the
collapse "runs in the safe direction because the gate makes the same read." The
first half is true and the conclusion does not follow: a refusal that is undone
by a later re-evaluation is not a defence.

**3. A stdout diagnostic that names the way out.** On a failed verification the
block prints the key, says which outcome not to submit, and names the escalate
outcome that still reaches a terminal state. stdout because stderr is what
operators redirect to escape koto's migration noise. The escalate half is what
satisfies PRD R6: the block stops the agent from advancing, not from submitting
anything at all.

**And no gate changes.** With removal available, `context-exists` is exactly the
right gate for "this phase must produce a fresh artifact" — remove the key and
it fails. `work-on.md`'s `gates:` blocks are untouched; the only template edit is
directive prose for `verification`, which has no phase reference file of its own.

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

What falls out of the choice is that no gate declaration changes. The gate main
already ships turns out to be the right gate; it was only ever missing the verb
that makes a presence gate actionable. That is the design's main structural
claim, and it is verifiable by diffing the template's `gates:` blocks rather than
argued in prose.

An earlier draft made the stronger claim that `work-on.md` does not change at
all, and treated the empty template diff as the evidence. That was true only
because the draft had missed the `verification_outcome: failed` edge, whose
directive lives in the template and nowhere else. The weaker claim is the one
that was actually load-bearing: gate declarations unchanged, which is what PRD R5
asks for and what makes the mermaid companion and the eval fixtures safe.

## Solution Architecture

Ten files change and two are new: six phase reference files, the panel
orchestration reference, the template's `verification` directive,
`scripts/check-bash-floor.sh` and `skills/work-on/evals/evals.json`; new are
`skills/work-on/scripts/retry-clearing_test.sh` and
`.github/workflows/check-work-on-scripts.yml`. No mermaid companion and no eval
fixtures.

**The three retry-bearing phase files** — `phase-4a-scrutiny.md`,
`phase-4b-review.md`, `phase-4c-qa.md` — each gain the same block on the
`blocking_retry` path, byte-identical below its **first** line:

```bash
OUTCOME_FIELD=scrutiny_outcome   # review_outcome / qa_outcome in the other two
for KEY in scrutiny_results.json review_results.json qa_results.json summary.md; do
  koto context remove <WF> "$KEY" >/dev/null 2>&1
  REMOVE_STATUS=$?
  if [ "$REMOVE_STATUS" -ne 0 ] || koto context exists <WF> "$KEY" >/dev/null 2>&1; then
    echo "$KEY was not confirmed cleared from context."
    echo "The stale artifact may still be in place, and its gate may accept it."
    echo "Do NOT submit $OUTCOME_FIELD: passed on the next pass."
    echo "To stop the run, submit $OUTCOME_FIELD: blocking_escalate with a failure_reason."
    exit 1
  fi
done
koto next <WF> --with-data "{\"$OUTCOME_FIELD\": \"blocking_retry\"}"
```

The blocks are generated from the edge table above rather than hand-written per
file, which is how the traversal rule stays applied consistently: the hand-written
version is what missed three of the five edges.

The differing line is the first rather than the last because the diagnostic has
to name the phase's own field, and PRD R4 requires it to. Hoisting the field into
a variable at the top is what keeps everything below it identical; a diagnostic
that interpolated the field inline would leave three blocks differing in four
places, and "identical below the first line" is an assertion a harness can make
where "mostly the same" is not.

`phase-3-analysis.md` and `phase-4-implementation.md` gain the same shape over
the five-key set, on `plan_outcome: scope_changed_retry` and
`implementation_status: scope_expanded_retry` respectively;
`phase-5-finalization.md` over the four-key set on `finalization_status:
issues_found`; and the template's `verification` directive over the four-key set
on `verification_outcome: failed`.

Each names the way out on its **fourth** diagnostic line — the third names the
outcome not to submit. `scope_changed_escalate` for `analysis`,
`partial_tests_failing_escalate` for `implementation`, `cannot_verify` for
`verification`, `deferral_requested` for `finalization`.

`finalization` is the one that is not an escalate outcome, and the wording of
this design has to be careful about it. `finalization` has no escalate edge at
all; `deferral_requested` targets `deferral_approval`, which is a human gate
rather than a terminal state. What PRD R6 requires is that a broken store leave
a reachable exit, and `deferral_requested` is `finalization`'s. Calling it "the
escalate outcome" would be wrong twice over — wrong about its name and wrong
about where it goes.

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

**The failure mode is fail-closed, and the two-signal check is what makes it
so.** A removal that does not take stops the run before the advancing outcome is
submitted, whether the store was unwritable (`exists` sees the surviving key) or
unreadable (`exists` is blinded, but `remove` reports failure).

The unreadable case is worth restating here because it is the one that looks
handled and is not. `ctx_exists` reports `false` for a store it cannot read as
well as for a key that is not there. The gate makes the same blind read, so an
advancing outcome submitted in that window is refused — and that refusal does
not hold. koto re-evaluates the buffered evidence, so once the permission
problem clears the run advances on the surviving artifact with no further
submission. Checking `remove`'s exit status is what closes it; the gate agreeing
with `exists` is not a defence, only a delay.

The same ambiguity is why this design has no `exists` guard *before* removing: a
caller using `exists` to decide whether to **skip** work will skip a key that is
really there. The rule that falls out is narrow and worth keeping: `ctx_exists`
may be used to detect a key that is present, never to conclude one is absent.

**`koto overrides record` remains an escape hatch.** It advances past a failing
gate whether or not the gate declares `override_default`. That is correct and
auditable behaviour, and it means the guarantee is structural modulo a recorded
override rather than absolute.

## Consequences

**Positive.** On each of the five retry edges, a phase the run re-enters cannot
advance on the previous round's artifact, and the refusal is the state machine's
rather than an instruction's — demonstrated per edge against real koto rather
than argued from the graph. The claim is scoped to those edges deliberately: an
earlier version of this sentence said "any re-entered phase," which was false on
the three edges whose traversal it had not covered.

One mechanism covers all six gates, including the two markdown ones no
content-shaped pattern could reach. No gate declaration changes, so the mermaid
companion is unchanged and no eval fixture is rebuilt. And no sentinel value
enters the artifact namespace, so nothing has to be kept in sync with a pattern.

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
