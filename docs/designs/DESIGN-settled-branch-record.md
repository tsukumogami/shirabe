---
schema: design/v1
status: Accepted
upstream: docs/prds/PRD-settled-branch-record.md
problem: |
  /execute's orchestrator_setup records the settled branch with `koto context
  set`, a subcommand koto does not have. The write fails silently once stderr
  is redirected, and spawn_and_await's `|| impl/$PLAN_SLUG` fallback then
  dispatches every child at a branch the adopt path never created.
decision: |
  Write with `printf '%s' | koto context add`, read the value straight back and
  compare in the same block with the diagnostic on stdout, and add a
  context-matches gate on orchestrator_setup whose result is referenced by the
  completed and override transitions. The read site in spawn_and_await is left
  byte-identical.
rationale: |
  Two of the three changes are checks that do not depend on an agent following
  prose: the read-back compares bytes, and the gate is evaluated by koto. That
  matters because this is the second defect of the same class in this template
  -- a directive naming something that does not resolve -- so a fix whose only
  guarantee is better-worded prose repeats the bet that already lost.
---

# DESIGN: Settled-Branch Record

## Status

Accepted

## Context and Problem Statement

`/execute` drives a koto state machine whose first state, `orchestrator_setup`,
decides which branch the run's per-issue children commit to. It has two paths.
The fresh path creates `impl/<slug>` from the PLAN's filename and opens a draft
PR. The adopt path — taken when the run starts on a non-main branch that already
has an open PR — stays where it is and skips branch creation entirely. The branch
is then whatever the operator was standing on, most often a `docs/<topic>`
scoping branch, and nothing downstream can derive it.

That is why `orchestrator_setup` records it. The directive ends with

```bash
koto context set {{SESSION_NAME}} settled_branch "$SETTLED_BRANCH"
```

and koto has no `context set`. Its context group is `add`, `get`, `exists`,
`list`, and `add` takes its value from stdin or `--from-file` rather than as a
positional argument, so the fix is not a rename. The write has never worked.

`spawn_and_await` reads the value back on both of its ticks as

```bash
SETTLED_BRANCH=$(koto context get {{SESSION_NAME}} settled_branch 2>/dev/null || echo "impl/$PLAN_SLUG")
```

and injects it as each task's `SHARED_BRANCH`. With the write broken, the read
falls through to `impl/$PLAN_SLUG` — correct on the fresh path, and on the adopt
path a branch that does not exist. The technical problem is therefore not one
wrong command but a chain with no point at which a missing record is
distinguishable from a recorded one: the write is silent on success, silent on
failure once stderr is redirected, and the read's fallback produces a
well-formed answer either way.

## Decision Drivers

- **The fresh path must not move.** PRD R4 requires the fresh-path task payload
  to stay byte-identical, so any mechanism that changes what `SHARED_BRANCH`
  holds on a fresh run is disqualified.
- **The failure has to survive `2>/dev/null`.** PRD R6. Redirecting koto's stderr
  is the routine operator response to its migration noise, so a mechanism whose
  only failure signal is a stderr message is a mechanism that fails silently
  again.
- **The guarantee should not depend on an agent following prose.** The directive
  is executed by an agent reading markdown. A rule the state machine enforces
  holds under an agent that skips a step; a rule written only in prose does not.
- **koto's existing interface is the boundary.** PRD Out of Scope forbids adding
  a `context set` subcommand, so the design composes what koto already has:
  `context add`, `context get`, and the `context-exists` / `context-matches`
  gate types the engine already evaluates.
- **Re-running after a crash must stay safe.** PRD R8. `orchestrator_setup` is
  documented as idempotent and the recording step must not break that.
- **The blast radius is one state plus its directive.** PRD R9 confines the
  change; a mechanism that requires new template variables, new states, or
  changes to koto itself is out of proportion to the defect.

## Considered Options

### Decision 1: How the run guarantees children reach the settled branch

The full evaluation is in the decision report at
`wip/design_settled-branch-record_decision_1_report.md`; the substance is
reproduced here because that file is not durable.

The question merges three sub-questions that turned out to be coupled: which
command records the value, how a failed record is detected, and what the read
site does when the value is absent. They cannot be answered independently — the
answer to the third is what decides whether the second needs to be structural.

Key assumptions, verified against koto's source rather than assumed:

- `ContextStore::add` creates **or replaces**, so recording twice is safe and R8
  is satisfied by the interface (`src/session/context.rs`).
- `koto context get` writes the stored bytes verbatim with no added newline
  (`handle_get` → `write_all`), so a `printf '%s'` write round-trips byte-exact.
- A failed gate on a state that has an `accepts` block does **not** block by
  itself; it blocks only when a transition's `when` clause references it
  (`src/engine/advance.rs`, and the `gate_failed_skips_unconditional_fallback`
  test). This is what makes the `when`-clause references load-bearing rather
  than decorative.
- `context-matches` evaluates `Regex::is_match`, a substring test, so its
  pattern must be anchored or it will pass values that merely contain a match.
- `{{SESSION_NAME}}` is a koto runtime variable (`RESERVED_VARIABLE_NAMES`), not
  a declared one, so no `variables:` block change is needed.

#### Chosen: Structural gate plus in-block read-back verification

Three changes that together move the guarantee off the fallback.

1. **The write becomes a command that exists.** `printf '%s' "$SETTLED_BRANCH" |
   koto context add {{SESSION_NAME}} settled_branch`. `printf '%s'` rather than
   `echo` because `add` stores stdin verbatim and a trailing newline would change
   the branch name the read returns.

2. **The write is verified in the same block, on stdout.** The directive reads
   the value straight back and compares it to what it wrote. On mismatch it
   prints a diagnostic naming the step and the branch, and the agent submits
   `status: blocked`. The diagnostic goes to stdout, not stderr, because stderr
   is the stream an operator redirects to escape koto's migration noise — a
   failure message on stderr disappears exactly when it is needed.

3. **A `context-matches` gate on `orchestrator_setup` binds the guarantee to the
   state machine.** It keys on `settled_branch` with the anchored pattern
   `^[A-Za-z0-9._/-]+$`, and its result is referenced in the `when` clause of the
   `completed` and `override` transitions — and deliberately not in the `blocked`
   transition, which must stay reachable. With the key absent or malformed,
   neither success transition matches and the run cannot leave
   `orchestrator_setup` except by declaring itself blocked.

The fallback at the read site is unchanged, byte for byte. It stops being load
bearing: it is reachable only on runs where the gate already confirmed a
well-formed value.

#### Alternatives Considered

- **Path-aware fallback** — record which path was taken and fall back only on the
  fresh path. Rejected because the discriminator shares a failure mode with the
  thing it discriminates: it is recorded through the same store by the same step,
  so a write failure loses both keys and the read site is back to today's
  ambiguity. A guard that fails whenever the thing it guards fails is not a
  guard.
- **Read-back verification and nothing else** — fix the write, compare, exit
  non-zero, leave the template alone. Rejected as the whole answer and adopted as
  part of one: the emitted block's exit status does not reach koto, so nothing
  stops the agent from submitting `status: completed` after a failed
  verification. It is the right way to produce a readable failure and the wrong
  way to enforce one.
- **Drop the fallback** — make an absent key a hard error at the read site.
  Rejected because it converts a path that cannot currently fail into one that
  can, for no gain once the gate is in place, and because it breaks a contract
  the eval suite grades explicitly: that the fallback yields the identical string
  on a crash-and-re-run with the key absent.
- **Derive the branch from HEAD** — drop the key and re-read `git rev-parse
  --abbrev-ref HEAD` at spawn time. Rejected because the record exists precisely
  to survive a HEAD that moved; the skill's durability contract says a resumed
  session may run on a different branch, so deriving from HEAD reintroduces the
  assumption the record was created to remove, and fails silently when it fails.
- **Record to a `wip/` file** — write the branch to
  `wip/execute_<slug>_settled_branch` and gate on `test -f`. Rejected because
  `wip/` is non-durable by workspace rule and is deleted by the finalization
  cascade before merge, and because it adds a second state substrate alongside
  the koto context store for one value.

## Decision Outcome

The recording step, its verification, and the gate are one mechanism, and each
piece covers a failure the others do not. The write fixes the immediate defect.
The read-back gives a human a sentence to act on, on the stream that survives the
redirection operators actually perform. The gate makes the guarantee hold under
an agent that skipped the verification, which is the failure mode this template
has now produced twice.

What falls out of the choice is that `spawn_and_await` needs no change at all.
That is the design's main structural claim: by making the missing-key state
unreachable, the read site's fallback can keep its exact current text, so
fresh-path parity is demonstrated by an empty diff rather than argued in prose.

## Solution Architecture

Two files change, and one gains a test.

**`skills/execute/koto-templates/execute.md` — template frontmatter.**
`orchestrator_setup` gains a gate block and two `when`-clause keys:

```yaml
  orchestrator_setup:
    gates:
      settled_branch_recorded:
        type: context-matches
        key: settled_branch
        pattern: '^[A-Za-z0-9._/-]+$'
    accepts:
      status:
        type: enum
        values: [completed, override, blocked]
        required: true
      detail:
        type: string
    transitions:
      - target: worktree_discipline_check
        when:
          status: completed
          gates.settled_branch_recorded.matches: true
      - target: worktree_discipline_check
        when:
          status: override
          gates.settled_branch_recorded.matches: true
      - target: done_blocked
        when:
          status: blocked
        context_assignments:
          failure_reason: "orchestrator_setup blocked: ${evidence.detail}"
```

The pattern is anchored at both ends. Unanchored, `is_match` would accept any
value containing a legal substring, which is every value.

The `blocked` transition carries no gate reference on purpose. A gate that also
governed the failure exit would make a run with an unwritable store unable to
reach any terminal state.

**`skills/execute/koto-templates/execute.md` — the `orchestrator_setup`
directive.** The recording block becomes:

```bash
SETTLED_BRANCH=$(git rev-parse --abbrev-ref HEAD)
case "$SETTLED_BRANCH" in
  *[!A-Za-z0-9._/-]*|"") echo "refusing unsafe settled branch: $SETTLED_BRANCH"; exit 1 ;;
esac
printf '%s' "$SETTLED_BRANCH" | koto context add {{SESSION_NAME}} settled_branch
# 2>/dev/null suppresses koto's migration-skipped noise. It is safe here only
# because the comparison below, not the absence of an error message, is what
# decides whether the record took.
RECORDED=$(koto context get {{SESSION_NAME}} settled_branch 2>/dev/null)
if [ "$RECORDED" != "$SETTLED_BRANCH" ]; then
  echo "settled_branch NOT recorded: read back '$RECORDED', expected '$SETTLED_BRANCH'"
  echo "submit status: blocked -- do NOT submit completed or override"
  exit 1
fi
```

Both diagnostics go to stdout. The pre-existing `refusing unsafe settled branch`
message moves off stderr for the same reason the new one is not put there.

**`skills/execute/SKILL.md`.** The `orchestrator_setup` bullet gains one clause
naming the gate, so the prose contract and the template agree.

**A round-trip test.** A shell test under `scripts/` drives a real koto session:
initialize a workflow from the template, run the recording block against an
adopt-path branch name, read the value back the way `spawn_and_await` does, and
assert the two strings are equal. The same script asserts the negative: with the
key absent, the gate reports `matches: false` and `orchestrator_setup` does not
advance on `status: override`. This is the demonstration PRD acceptance requires,
captured as script output rather than asserted in prose.

### Data flow

```
orchestrator_setup directive
  git rev-parse --abbrev-ref HEAD  ->  SETTLED_BRANCH
  case ... esac                    ->  reject unsafe ref (stdout diagnostic)
  printf | koto context add        ->  ctx/settled_branch
  koto context get + compare       ->  human-readable pass/fail on stdout
        |
        v
koto advance: gates evaluated on orchestrator_setup
  context-matches(settled_branch, ^[A-Za-z0-9._/-]+$)
        |
        +-- matches:true  + status completed|override -> worktree_discipline_check
        +-- matches:false + status completed|override -> no transition; state holds
        +-- any           + status blocked            -> done_blocked
        |
        v
spawn_and_await (unchanged)
  koto context get ... || echo "impl/$PLAN_SLUG"
  case ... esac  ->  re-validate, fall back on malformed
  jq --arg b ... ->  SHARED_BRANCH on every task
```

## Implementation Approach

1. **Fix the write and add the verification** in the `orchestrator_setup`
   directive. Self-contained; nothing else depends on it.
2. **Add the gate and the two `when` references** to the template frontmatter.
   Confirm the template still compiles (`koto template compile` or the existing
   template-validation scripts) — a `when` key naming a gate field koto does not
   produce is a compile-time or resolve-time failure, and finding that out here
   rather than in a live run is the point of doing it as its own step.
3. **Write the round-trip test** and run it. It covers both the positive
   (recorded value equals injected value) and the negative (missing key holds the
   state) case.
4. **Sweep the skills tree** for `koto context <verb>` outside
   `{add, get, exists, list}` and for other write-then-depend-unverified shapes,
   and record the result in this document's Consequences.
5. **Reconcile the prose**: `skills/execute/SKILL.md`'s `orchestrator_setup`
   bullet, and the `/execute` evals that describe the settled-branch contract —
   changed only where the contract genuinely changed, which is the addition of
   the gate, not the read site.

Steps 1 and 2 are independent of each other in edit terms but must land
together: step 1 without step 2 is the prose-only alternative this design
rejected, and step 2 without step 1 gates on a key nothing writes.

## Security Considerations

**The recorded branch name is untrusted input.** It comes from `git rev-parse`
against a worktree the run does not own, and it ends up interpolated into emitted
shell via `jq --arg`. Three checks now cover it: the existing `case` statement on
the write side, the gate's anchored pattern on the way out of the store, and the
existing `case` statement at the read site. The middle one is new and is the only
one an agent cannot skip.

**The anchoring is the security-relevant detail.** `context-matches` calls
`Regex::is_match`, which is a substring test. An unanchored `[A-Za-z0-9._/-]+`
pattern would pass `main; rm -rf /` because `main` matches. `^...$` is what makes
the gate a validator rather than a formality, and the round-trip test should
assert the rejection of a value containing a shell metacharacter so a later
edit that drops an anchor fails a test rather than a production run.

**Residual, unchanged by this work:** the accepted pattern permits `.` and `/`
in any arrangement, so `../../foo` is a pattern-valid branch name. This is the
pattern the skill already commits to and PRD R5 freezes it, and the value reaches
git as a ref-name argument — which git validates itself and rejects — rather than
as a filesystem path. It is recorded here as a known residual rather than
silently tightened, because tightening it is a contract change the PRD did not
ask for.

**No new trust boundary is crossed.** The gate's pattern is a literal in the
template, not author-supplied. No network access, no credential handling, and no
new file is written outside koto's own session directory. The stored value is a
branch name, not a secret, so the context store gains no new sensitivity.

**The failure mode is fail-closed.** With the store unreadable, the gate reports
`matches: false` and the two success transitions do not match, so the run cannot
proceed to dispatch children. The previous behaviour — proceed with a guessed
branch — was fail-open.

## Consequences

**Positive.** A run that cannot record its settled branch stops at
`orchestrator_setup` rather than producing children aimed at a branch nobody
created. The stop is visible in `koto status` as a state that will not advance,
independently of how any stream was redirected. The read site's diff is empty, so
fresh-path parity is verifiable by inspection. R5's read-side validation becomes
structural rather than a shell idiom the agent could omit.

**Negative.** The change now spans the template's state definitions as well as
the directive prose, so a reviewer reads both. A failed gate reports as a bare
exit code with no message, so an operator who ignores the directive's stdout
diagnostic sees a stuck state without a stated reason. And the fresh path, which
previously could advance with a broken context store, now cannot — intended, but
a behaviour change on a path the PRD otherwise freezes.

**Mitigations.** The directive prose names the gate and what to check when the
state will not advance, in the shape `worktree_discipline_check` already uses for
its own gate. The round-trip test pins both the positive and the negative case, so
a later edit that removes the gate or unanchors its pattern fails a test.

**Sweep result (PRD R7).** Recorded here as the durable home for the audit.
koto's context group is `add`, `get`, `exists`, `list` and nothing else, so the
sweep asks which calls in the skills tree name a verb outside that set.

Two do. `koto context set` appears once as a command — the line this design
replaces — plus two prose citations in the issue-outlines BRIEF and PRD, which
name it as the defect rather than instructing anyone to run it. **And
`skills/work-on/references/phases/phase-4a-scrutiny.md` instructs the agent to run
`koto context remove <WF> scrutiny_results.json` to clear a stale artifact before
a re-run.** There is no `koto context remove`: `ContextStore::remove` exists as a
trait method in koto's source but is not exposed on the CLI, and the command
exits with `error: unrecognized subcommand 'remove'`. It is the same defect as
this one, one skill over, and it fails the same quiet way — the re-run proceeds
against the stale artifact it believed it had cleared.

It is not fixed here. R9 confines this change to `orchestrator_setup`,
`spawn_and_await`, and the prose documenting them, and `/work-on`'s scrutiny
phase is neither; widening the change to reach it would make this PR the thing
R9 exists to prevent. It is filed as its own issue instead: tsukumogami/shirabe#304.

On the second half of the sweep — writes whose value is depended on without
anything checking the write took — the other `koto context add` calls in the tree
are each read back by a later state through a `context-exists` gate that already
exists: `context.md`, `baseline.md`, `introspection.md`, `plan.md`,
`scrutiny_results.json`, and `review_results.json` are all gated in
`work-on.md`. `settled_branch` was the one key written by one state and read by
another with no gate between them, which is why it is the one that failed.
