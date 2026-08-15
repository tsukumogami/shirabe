# Decision Report: settled-branch record and its failure behaviour

Prefix: `design_settled-branch-record_decision_1`
Complexity: critical (Tier 4, full path)
Validator mechanics: the bakeoff, peer revision, and cross-examination were run
serially in-process (the serial-self-jury fallback shape) rather than as spawned
validator agents. The rubric set and the adversarial structure are preserved;
the parallelism is not.

<!-- decision:start id="settled-branch-record" status="confirmed" -->
### Decision: How /execute guarantees children are dispatched to the settled branch

**Context**

`orchestrator_setup` settles on a branch by one of two routes. The fresh route
creates `impl/<slug>` from the PLAN's filename; the adopt route stays on a branch
that already has an open PR and creates nothing. Only the adopt route produces a
branch nothing downstream can re-derive, which is why the value is recorded at
all. The record is then read by `spawn_and_await` on both of its ticks and
injected into every child task as `SHARED_BRANCH`.

Three properties of the current chain combine into the defect. The write names
`koto context set`, which does not exist. The write is silent on success, so
its silence on failure is not distinguishable — and because koto floods stderr
with `migration skipped` lines, operators redirect stderr as a matter of course,
which removes the one signal that was there. And the read carries `|| echo
"impl/$PLAN_SLUG"`, which turns the missing value into a well-formed answer that
happens to name a branch the adopt path deliberately did not create.

The question is therefore not only which command to write with. It is where the
guarantee lives: what, in the run, makes it impossible for children to be
dispatched at a branch that was never settled on, and what the run does when
that cannot be guaranteed.

**Assumptions**

- koto's `ContextStore::add` will continue to create-or-replace rather than
  error on an existing key. If that changed, the recording step would stop being
  idempotent and `orchestrator_setup` would fail on re-run after a crash.
- `koto context get` will continue to emit the stored bytes verbatim with no
  trailing newline. If it grew one, the anchored `context-matches` pattern would
  start failing on every run — loudly, which is the right direction to fail.
- The gate evaluator will continue to require a `when`-clause reference for a
  failed gate to block a state that has an `accepts` block. If gates ever became
  unconditionally blocking, this design's transitions would still be correct;
  they would merely be redundant.
- Operators redirect stderr, not stdout. The verification's diagnostic goes to
  stdout for that reason.

**Chosen: Structural gate plus in-block read-back verification**

Three changes that together make the guarantee hold without the fallback being
the thing that decides correctness.

1. **The write becomes a command that exists.** `printf '%s' "$SETTLED_BRANCH" |
   koto context add {{SESSION_NAME}} settled_branch`. `printf '%s'` rather than
   `echo` because `add` stores stdin verbatim and a trailing newline would
   change the branch name the read returns. `add` replaces an existing key, so
   re-running `orchestrator_setup` after a crash is safe.

2. **The write is verified in the same block, on stdout.** The directive reads
   the value straight back and compares it to what it wrote. A mismatch prints a
   diagnostic naming the step and the branch, and the agent submits `status:
   blocked` rather than `completed` or `override`. The diagnostic goes to
   **stdout**, not stderr, because stderr is the stream an operator redirects to
   escape koto's migration noise — a failure message on stderr is a failure
   message that disappears exactly when it is needed.

3. **A `context-matches` gate on `orchestrator_setup` binds the guarantee to the
   state machine.** The gate keys on `settled_branch` with the anchored pattern
   `^[A-Za-z0-9._/-]+$`, and its result is referenced in the `when` clause of the
   `completed` and `override` transitions — and deliberately not in the `blocked`
   transition, which must stay reachable. With the key absent or its value
   malformed, neither success transition matches and the run cannot leave
   `orchestrator_setup` except by declaring itself blocked. `spawn_and_await` is
   unreachable with a missing record, which is what lets its fallback keep its
   exact current shape.

The fallback at the read site is unchanged, byte for byte. It is no longer load
bearing: it is reachable only on runs where the gate already confirmed a
well-formed value, so on the fresh path it still yields `impl/$PLAN_SLUG` for a
crash-and-re-run, and on the adopt path it is not reached with the key missing.

**Rationale**

The defect being fixed is a directive that said something untrue and was believed
because nothing checked. Two of the three changes above are checks that do not
depend on an agent reading prose correctly: the read-back compares actual bytes,
and the gate is evaluated by koto. That matters more here than elsewhere, because
this is the second defect of exactly this class in the same template — a
directive naming something that does not resolve — and a fix whose only guarantee
is a better-worded directive would be the same bet that already lost.

Anchoring the gate's pattern also discharges the read-side half of R5 structurally.
The directive already validated the branch name before storing it; the gate now
validates what comes back out, at the state machine rather than in a shell case
statement the agent could omit.

Keeping the fallback is what makes the change reviewable. R4 asks for a
byte-identical fresh-path payload, and the strongest evidence for that is a read
site whose diff is empty. Moving the correctness decision up to the gate is what
buys the right to leave the fallback alone.

**Alternatives Considered**

- **Path-aware fallback.** Record which path was taken (a `setup_path:
  fresh|adopt` key, or a variable the directive sets) and fall back to
  `impl/$PLAN_SLUG` only when the run took the fresh path. Rejected because the
  discriminator shares a failure mode with the thing it discriminates: it is
  recorded through the same store by the same step, so a write failure loses both
  keys and the read site is back to the ambiguity this was meant to remove. A
  guard that fails whenever the thing it guards fails is not a guard.

- **Read-back verification in the directive, and nothing else.** Fix the write,
  compare the read-back, exit non-zero on mismatch, leave the template alone.
  Rejected as the whole answer, and adopted as part of one: the emitted block's
  exit status does not reach koto. Nothing stops the agent from submitting
  `status: completed` after a failed verification, so the guarantee is again an
  instruction rather than a constraint. It is the right way to produce a
  human-readable failure and the wrong way to enforce one.

- **Drop the fallback.** Remove `|| echo "impl/$PLAN_SLUG"` and let an absent key
  be a hard error at the read site. Rejected because it converts a path that
  cannot currently fail into one that can, for no gain once the gate is in place:
  with the gate, the read site is unreachable with a missing key, so the fallback
  is dead code on the failure path rather than a wrong answer. It also breaks a
  contract the eval suite grades explicitly — that the fallback yields the
  identical string on a crash-and-re-run with the key absent — and paying that
  cost to delete a branch that can no longer misfire is a bad trade.

- **Derive the branch instead of recording it.** Drop the key and have
  `spawn_and_await` re-read `git rev-parse --abbrev-ref HEAD`, which is the
  settled branch on both paths at the moment `orchestrator_setup` finishes.
  Rejected because the record exists precisely to survive a HEAD that moved. The
  skill's own durability contract says a resumed session may run on a different
  branch and rebuilds from the home PR; deriving from HEAD reintroduces the
  assumption the record was created to remove, and it fails silently when it
  fails, which is the property under repair.

- **Record to a `wip/` file instead of koto context.** Write the branch to
  `wip/execute_<slug>_settled_branch` and gate on `test -f`. Rejected because
  `wip/` is non-durable by workspace rule and is deleted by the finalization
  cascade before merge, and because it would introduce a second state substrate
  alongside the koto context store for one value. The `context-matches` gate
  gives the same structural check without the second substrate.

**Consequences**

Easier: a run that cannot record its settled branch stops at
`orchestrator_setup` instead of producing twelve children aimed at a branch
nobody created. The stop is visible in `koto status` as a state that will not
advance, independently of how the operator redirected any stream. The read site's
diff is empty, so fresh-path parity is verifiable by inspection rather than by
argument.

Harder: the change now spans the template's state definitions as well as the
directive prose, so a reviewer has to read both. A failed gate reports as a bare
exit code with no message, so an operator who ignores the directive's stdout
diagnostic sees a stuck state without a reason — the directive prose has to name
what to check, the way `worktree_discipline_check`'s note already does for its own
gate. And the fresh path, which previously could advance with a broken context
store, now cannot; that is intended, but it is a behaviour change on a path the
PRD otherwise freezes.
<!-- decision:end -->

## Output contract

```yaml
decision_result:
  status: "COMPLETE"
  chosen: "Structural gate plus in-block read-back verification"
  confidence: "high"
  rationale: >-
    Two of the three changes are checks that do not depend on an agent following
    prose: the read-back compares bytes, and the context-matches gate is
    evaluated by koto and referenced in the success transitions' when clauses.
    The read site keeps its exact current shape, so fresh-path parity is an empty
    diff rather than an argument.
  assumptions:
    - "koto context add continues to create-or-replace rather than error on an existing key"
    - "koto context get continues to emit stored bytes verbatim with no trailing newline"
    - "a failed gate blocks a state with accepts only when a when clause references it"
    - "operators redirect stderr, not stdout"
  rejected:
    - name: "Path-aware fallback"
      reason: "The path discriminator is recorded through the same store by the same step, so it is lost by the same failure it is meant to discriminate."
    - name: "Read-back verification alone"
      reason: "The emitted block's exit status does not reach koto; nothing prevents the agent from submitting status: completed after a failed verification."
    - name: "Drop the fallback"
      reason: "Converts a path that cannot fail into one that can, and breaks the crash-and-re-run parity the eval suite grades, to delete a branch the gate already makes unreachable."
    - name: "Derive the branch from HEAD"
      reason: "The record exists to survive a HEAD that moved; deriving from HEAD reintroduces the assumption it was created to remove."
    - name: "Record to a wip/ file"
      reason: "wip/ is non-durable and deleted by the finalization cascade, and it adds a second state substrate for one value."
  report_file: "wip/design_settled-branch-record_decision_1_report.md"
```
