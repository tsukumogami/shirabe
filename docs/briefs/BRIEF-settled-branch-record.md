---
schema: brief/v1
status: Done
problem: |
  /execute's orchestrator_setup records the settled branch with a koto
  subcommand that does not exist, and the failure reads as success. On the
  adopt path that record is the only thing that knows which branch the run
  settled on, so its absence routes every child at a branch nobody created.
outcome: |
  An operator running /execute on an adopted branch sees children commit to
  that branch. When the record cannot be made or cannot be read back, the run
  stops and names what failed instead of continuing against a guessed branch.
motivating_context: |
  Found running /execute --auto against a twelve-issue single-pr PLAN, on a
  docs/<topic> scoping branch with an open PR. The run only survived because
  the shared branch was injected into the task payload by hand.
---

## Status

Done

The framing stops at the boundary: which record `/execute` keeps of the branch
it settled on, and what happens when that record is missing. The downstream PRD
owns the requirements, and the DESIGN owns the choice between keeping a
path-aware fallback, verifying the read-back, and dropping the fallback.

## Problem Statement

`/execute`'s `orchestrator_setup` directive ends by recording the branch the run
settled on:

```bash
koto context set {{SESSION_NAME}} settled_branch "$SETTLED_BRANCH"
```

koto has no `context set`. Its context group offers `add`, `get`, `exists`, and
`list`, and `add` reads its value from stdin or `--from-file` rather than taking
it as a third positional argument. So the recording step has never worked, on any
platform, since the directive was written.

Two things make that worse than a step that fails loudly. The first is that koto
is noisy: in a workspace with accumulated sessions, every invocation prints dozens
of `koto: migration skipped ...` lines to stderr, so an operator's natural move is
to append `2>/dev/null`. That filter swallows `error: unrecognized subcommand
'set'` along with the noise, and since the command writes nothing to stdout on
success either, a failed write and a successful one look identical.

The second is where the value is used. `orchestrator_setup` has two paths. The
fresh path creates `impl/<slug>` and opens a draft PR, and there the branch is
derivable from the PLAN's own name. The adopt path stays on a branch that already
carries an open PR — an author's branch, or a `docs/<topic>` scoping branch — and
deliberately skips branch creation. On that path the branch is not derivable from
anything, which is the whole reason it is recorded. `spawn_and_await` later reads
it back as `koto context get ... || echo "impl/$PLAN_SLUG"`, finds nothing, and
substitutes a branch the adopt path never created. Every child is then dispatched
against a branch that does not exist, in exactly the situation the record exists
to serve.

The fallback is not the defect, but it is what turns the defect into a silent
wrong answer rather than a stop. It is correct on the fresh path and wrong on the
adopt path, and today nothing distinguishes the two — so any future write failure,
from a permission problem to a renamed session, reaches the same wrong branch by
the same route.

## User Outcome

An operator who runs `/execute` on a branch that already has an open PR gets
children that commit to that branch. Nothing about the adopt path requires them to
inject the branch by hand, inspect koto's context store, or know that a recording
step exists at all.

When the record cannot be made — the store is unwritable, the session was renamed,
the write is rejected for any reason — the run halts and says which step failed and
what it was trying to record. The operator reads a stop, not a stack of children
that ran against the wrong branch and a PR that gained nothing.

An operator on the fresh path sees no change at all: the branch is `impl/<slug>`,
as it always was.

## User Journeys

### Adopting a scoping branch

An operator has just finished `/scope` on `docs/settled-branch-record`, which has
an open PR. They run `/execute docs/plans/PLAN-settled-branch-record.md --auto`
from that branch. `orchestrator_setup` detects the non-main branch with an open PR,
takes the adopt path, records `docs/settled-branch-record`, and `spawn_and_await`
reads that value back and injects it as each child's `SHARED_BRANCH`. Every child
commits to the branch the operator was standing on, and the existing PR is the home
PR.

### A fresh run from main

An operator runs `/execute docs/plans/PLAN-<topic>.md` from `main`. There is no
open PR on the current branch, so `orchestrator_setup` runs the creation script,
checks out `impl/<topic>`, pushes, and opens the draft PR. The recorded branch is
`impl/<topic>` — the branch just created — and the children land on it. The
operator sees the same behaviour they saw before this work.

### The record cannot be written

An operator runs `/execute` in a workspace where koto's context store is not
writable, or where the session name in the directive no longer resolves. The
recording step fails. The run stops at `orchestrator_setup` and reports which
command failed and which branch it was trying to record, so the operator can fix
the store and re-run. No child is dispatched.

### A maintainer auditing the skills tree

A maintainer wants to know whether the same shape appears elsewhere: a koto
subcommand that does not exist, or a write whose success is never checked before
its value is depended on. They read the skills tree and find the answer recorded,
so the sweep is a fact in the audit trail rather than a search each reader repeats.

## Scope Boundary

**In:**

- The `orchestrator_setup` step that records the settled branch: which command it
  runs, and in a form that actually stores the value.
- The `spawn_and_await` read-back on both ticks, and what it does when the value
  is absent.
- The failure contract when either the write or the read-back fails, on each of
  the two paths, so a failure to record stops presenting as success.
- A sweep of the skills tree for the same non-existent subcommand and for the same
  write-then-depend-on-it-unchecked shape, with the result recorded.

**Out:**

- The rest of `/execute`'s surface. The finalization cascade, the CI monitor, the
  coordinated mode, and the interactive pause are untouched.
- Adding a `context set` subcommand to koto. The fix uses the interface koto has.
- koto's migration-skipped stderr noise. It is what makes the failure quiet, and it
  is a koto concern rather than a `/execute` one; the work here makes the failure
  survive the noise instead of removing the noise.
- The `/scope` artifact-set question and the other open `/execute` friction items.
  They are separate work with their own issues.
- `shirabe validate`'s silent-decline behaviour on directory positionals and
  schema-less documents. It is worked around here, not fixed.

## References

- `skills/execute/koto-templates/execute.md` — the `orchestrator_setup` and
  `spawn_and_await` directives this brief frames.
- `skills/execute/SKILL.md` — the prose contract for the adopt path and the
  settled-branch read-back.
