---
schema: prd/v1
status: Done
problem: |
  Operators running /execute on a branch that already carries an open PR get
  their per-issue children dispatched against a branch that was never created.
  The orchestrator records the settled branch with a koto subcommand that does
  not exist, the failure is indistinguishable from success once koto's stderr
  noise is filtered, and the read-back's fallback quietly supplies the branch
  the adopt path deliberately skipped creating.
goals: |
  /execute records the branch it settled on with a command that works, checks
  that the record took before anything depends on it, and stops with a named
  failure when it did not. The fresh path behaves exactly as it does today, and
  the adopt path stops producing a silent wrong answer.
upstream: docs/briefs/BRIEF-settled-branch-record.md
source_issue: 279
---

## Status

Done

Requirements are written from the accepted BRIEF. The choice of mechanism for
the read-back's failure behaviour is a DESIGN-altitude decision; this PRD states
the outcome the mechanism has to reach and leaves the shape open.

## Problem Statement

`/execute`'s `orchestrator_setup` directive records the branch the run settled
on so that `spawn_and_await` can route per-issue children to it. The recording
step runs `koto context set <session> settled_branch "$SETTLED_BRANCH"`. koto has
no `context set` subcommand — its context group is `add`, `get`, `exists`, `list`
— so the step has never worked on any platform. `add`, the subcommand that would
have been meant, reads its value from stdin or `--from-file` rather than as a
positional argument, so this is not a rename that can be applied mechanically.

The failure is quiet. koto prints many `migration skipped` lines to stderr in any
workspace with accumulated sessions, so operators filter with `2>/dev/null`; that
filter also swallows `error: unrecognized subcommand 'set'`. The command produces
no stdout on success either, so a failed write and a successful one are the same
observation.

The consequence lands on the one path the record exists to serve. On the fresh
path, `orchestrator_setup` creates `impl/<slug>` and the branch is derivable from
the PLAN's filename, so `spawn_and_await`'s `|| echo "impl/$PLAN_SLUG"` fallback
is exactly right. On the adopt path the run stays on an existing branch with an
open PR and deliberately skips branch creation, so the branch is derivable from
nothing — and the same fallback hands every child a branch that does not exist.
An operator reported twelve children about to be dispatched at
`impl/chain-cardinality`, a branch nobody had created; the run only survived
because they injected the branch into the task payload by hand.

Correcting the subcommand alone would fix today's instance and leave the route
open. Any later write failure — an unwritable store, a renamed session, a
permission change — reaches the same wrong branch through the same unguarded
fallback.

## Goals

- An `/execute` run that adopts an existing branch dispatches its children to
  that branch, with no manual payload injection.
- A failure to record the settled branch stops the run and names itself, rather
  than being absorbed by a fallback that produces a plausible wrong answer.
- A fresh run is unchanged: same branch, same PR, same task payload.
- The same defect shape elsewhere in the skills tree is found and recorded rather
  than left for the next operator to hit.

## User Stories

- As an operator finishing `/scope` on a `docs/<topic>` branch with an open PR, I
  want `/execute` to keep the work on that branch, so that the scoping PR is the
  home PR and I do not have to reroute children by hand.
- As an operator running `/execute` fresh from `main`, I want the run to behave
  exactly as it did before, so that the fix carries no migration cost for the
  common path.
- As an operator whose koto context store is unwritable or whose session was
  renamed, I want the run to stop at the recording step and tell me what failed,
  so that I fix the store instead of reviewing twelve children that ran against
  the wrong branch.
- As a maintainer of the skills tree, I want to know whether other directives
  name a koto subcommand that does not exist or depend on an unverified write, so
  that the audit is a recorded fact rather than a search each reader repeats.

## Requirements

**Functional**

- **R1** — `orchestrator_setup` SHALL record the settled branch using a koto
  subcommand that exists, in a form that actually stores the value. The stored
  value SHALL be readable by the `koto context get` call `spawn_and_await`
  already makes, with no trailing newline or other transformation that would
  change the branch name.
- **R2** — `orchestrator_setup` SHALL verify that the record took before the
  state advances. A write that fails, or a read-back that does not return the
  branch that was written, SHALL block the state rather than advance it.
- **R3** — When the settled branch cannot be recorded or cannot be read back on a
  run that adopted an existing branch, `/execute` SHALL NOT dispatch children
  against a branch derived from the PLAN slug. The run halts instead.
- **R4** — On the fresh path, the recorded value SHALL be `impl/<slug>` and the
  task payload each child receives SHALL be byte-identical to today's. No new
  flag, prompt, or state is introduced on that path.
- **R5** — The recovered branch name SHALL continue to be validated against
  `^[A-Za-z0-9._/-]+$` before it is stored or interpolated into emitted shell,
  and the same validation SHALL apply to the value read back.
- **R6** — The failure surfaced by R2 and R3 SHALL be legible when the command's
  stderr is redirected, since redirecting koto's stderr is the routine operator
  response to its migration noise.
- **R7** — The skills tree SHALL be swept for the same non-existent subcommand
  and for the same write-then-depend-unverified shape, and the result SHALL be
  recorded in a durable artifact.

**Non-functional**

- **R8** — The recording step SHALL be idempotent: re-running
  `orchestrator_setup` after a crash SHALL leave the same stored value rather
  than failing on a key that already exists.
- **R9** — The change SHALL be confined to the `orchestrator_setup` and
  `spawn_and_await` directives and the prose that documents them. No other
  `/execute` state changes behaviour.
- **R10** — `cargo test --workspace` SHALL pass with no existing test modified.
  A test that must change is reported as a finding rather than edited silently.

## Acceptance Criteria

- [ ] Running the `orchestrator_setup` recording command as written stores the
      branch: `koto context get <session> settled_branch` returns exactly the
      value that was written, byte for byte (R1).
- [ ] `koto context list <session>` includes `settled_branch` after the recording
      step runs (R1).
- [ ] A demonstrated adopt-path round trip: starting on a non-main branch with an
      open PR, the branch recorded by `orchestrator_setup` is the same string
      `spawn_and_await` injects as `SHARED_BRANCH` into every task in the payload
      (R1, R3). The demonstration is captured as output, not asserted in prose.
- [ ] With the recording step forced to fail, `orchestrator_setup` does not
      advance and reports the failing command and the branch it was recording
      (R2, R6).
- [ ] With the recording step forced to fail, no task payload is produced that
      names `impl/<slug>` on a run that adopted an existing branch (R3).
- [ ] On a fresh run from `main`, the recorded value is `impl/<slug>` and the
      emitted task payload is byte-identical to the payload the previous
      directive produced (R4).
- [ ] A branch name containing a character outside `^[A-Za-z0-9._/-]+$` is
      rejected before it is stored, and a stored value that fails the same test
      when read back is rejected before it reaches a task payload (R5).
- [ ] The failure message from a blocked recording step is visible when the
      command's stderr is redirected to `/dev/null` (R6).
- [ ] Running the recording step twice in a row leaves one `settled_branch` key
      holding the same value, with no error on the second run (R8).
- [ ] `grep -rn "koto context" skills/` shows no subcommand outside
      `{add, get, exists, list}`, and the sweep's findings are recorded in a
      durable artifact (R7).
- [ ] `cargo test --workspace` passes, and `git diff` shows no modification to an
      existing test (R10).
- [ ] `shirabe validate --lifecycle . --mode=draft` exits 0.
- [ ] The `/execute` evals covering `orchestrator_setup` pass, changed only where
      the contract they describe genuinely changed.

## Out of Scope

- The rest of `/execute`'s surface: the finalization cascade, the CI monitor,
  coordinated mode, and the interactive pause are untouched.
- Adding a `context set` subcommand to koto. The fix uses koto's existing
  interface; changing the CLI to match a directive would invert the dependency.
- koto's `migration skipped` stderr noise. It is what makes the failure quiet, but
  it belongs to koto; R6 makes the failure survive the noise rather than removing
  it.
- The `/scope` artifact-set question and the other open `/execute` friction items.
  They are separate work with their own issues.
- `shirabe validate`'s silent-decline behaviour on directory positionals and on
  documents missing `schema:`. It is worked around here (explicit file paths,
  `schema:` on every authored document), not fixed.

## Decisions and Trade-offs

**The failure contract is a requirement, not an implementation detail.** The
upstream BRIEF left the mechanism open, and this PRD keeps it open: R2 and R3
state that a failed record must block and must not reach the PLAN-derived branch,
without saying whether that is achieved by a path-aware fallback, a verified
read-back, or dropping the fallback on the adopt path. The alternative was to
write the mechanism into the requirements, which would have settled a contested
question at the wrong altitude and left the DESIGN with nothing to decide.

**The fresh path keeps its fallback behaviour as a stated requirement (R4).**
The alternative — treating both paths identically for symmetry — was rejected
because the fresh path's fallback is not a guess: `impl/<slug>` is derived from
the PLAN filename by the same rule that created the branch, so it is correct by
construction. Requiring byte-identical payloads on that path also makes the
change reviewable: any diff in fresh-path behaviour is a regression.

**Idempotence is required rather than assumed (R8).** `orchestrator_setup` is
documented as safe to re-run after a crash, and a recording step that failed on
an existing key would break that property. koto's context store replaces on
write, so the requirement is satisfied by the interface rather than by extra
logic — but it is stated so a later change to the recording mechanism cannot
quietly remove it.

## Known Limitations

The verification R2 asks for is a read-back through the same store the write went
to. It catches a rejected write, a wrong key, and a value that did not survive
the round trip; it cannot catch a store that accepts and returns a value it will
lose later. That failure mode is out of reach of any check `/execute` can make
from the outside, and the run's later behaviour — children failing to find the
branch — is the only signal.
