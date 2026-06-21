# Running /execute: branch targeting, the review pause, and the finalization guard

A developer-facing guide to three user-visible `/execute` behaviors: how branch and
PR targeting differs by execution mode, when an interactive run pauses for review
versus when `--auto` drives straight to a mergeable result, and how to check whether
a run's finalization actually completed.

If you are running `/execute docs/plans/PLAN-<topic>.md` and want to know where your
code will land, when the run will stop for you, or whether a finished run is really
finished, this is the guide.

## Mode-aware branch and PR targeting

Where `/execute` puts code depends on the PLAN's `execution_mode`. The two modes
target branches differently, and the difference is deliberate.

### Single-pr: adopt the scoping branch and PR

A single-pr PLAN lands as one PR. When you run `/execute` while standing on a
non-main branch that already has an open PR — typically the `docs/<topic>` scoping
branch `/scope` left you on — `/execute` **adopts** that branch and PR as the home
PR. It does not open a second PR and does not link a distinct one. The code from
every per-issue child commits to that same settled branch, alongside the scoping
documents already there. One branch, one PR, code and scoping docs together.

If instead you start fresh with no existing-PR context (on `main`, or on a branch
with no open PR), `/execute` behaves exactly as it always has: it creates
`impl/<slug>`, opens a draft PR, and routes children there. The adopt path fires
only when the predicate — a non-main branch with an open PR — is already true. The
default path is unchanged.

What this means for you: if you ran `/scope` and are sitting on its branch, just run
`/execute` from there. Your implementation lands on the scoping PR you already have.
You do not need to create a branch or pass a flag.

### Coordinated: code in per-repo worktrees, coordination branch for docs only

A coordinated PLAN spans more than one repository, so there is no single shared
branch. The **coordination branch and PR carry scoping documents only** — the
PR-Index and the merge-order block. Code never lands there.

For each repository that needs changes, `/execute` works that repo in its own
worktree on that repo's own branch and lands its changes as a separate per-repo PR.
Cross-unit context flows through the coordination PR's durable state, not through a
shared branch. The coordination PR merges last, once every per-repo PR has merged.

What this means for you: do not expect cross-repo code on the coordination branch.
Each repo gets its own PR; the coordination PR is the index that ties them together
and the thing that merges last.

## Interactive pause versus `--auto` finalizes

`/execute` resolves an execution mode — interactive (the default) or `--auto` — and
that resolution decides whether the run stops for your review before it finalizes.
This is driven by the mode, not by a separate flag. There is no `--pause-for-review`.

### Interactive (default): stop at a reviewable draft

In interactive mode the run drives through implementation and assembles the PR, then
**stops at a reviewable draft before finalizing**. The stop is a non-failure terminal
named `paused_for_review`. At the pause:

- the PR is assembled (conventional title, two-part body) but still **draft** —
  `gh pr ready` has not fired;
- the chain is **intact** — the PLAN is still on disk, and BRIEF/PRD/DESIGN are
  un-transitioned;
- the finalization cascade has **not** run.

`/execute` hands you the draft PR to review. The pause is a suspension, not a
termination — the run has not abandoned anything and has not reached an error. When
you are satisfied, re-invoke `/execute` on the same topic. The resume finds the open
draft PR, re-enters finalization, runs the cascade, flips the PR ready, and waits for
CI to land green. A re-passed pause intent is ignored on resume: the body is already
assembled and your intent is to land.

### `--auto`: drive straight through to a mergeable result

Under `--auto` the run does **not** pause. It drives through finalization to a
ready-to-merge, green PR with the chain transitioned: the cascade deletes the PLAN
and transitions BRIEF/PRD/DESIGN/ROADMAP, the PR flips ready, and CI runs strict on
the finalized chain. A developer who runs `--auto` expects a finished, mergeable
result, and that is what it delivers. No solicited pause fires.

What this means for you: run the default interactive mode when you want a checkpoint
to read the assembled PR before it transitions the chain. Run `--auto` when you have
authorized an autonomous run and want a finished PR with no stop.

## The finalization-not-done guard

A run whose finalization did not complete — a manual or fallback run that bypassed
the automated cascade, an `--auto` run that stopped short, or a paused interactive
run that was never resumed — is detectable mechanically. The guard is the existing
`shirabe validate --lifecycle-chain` mode under ready posture. It is not a new flag
and not a new subcommand.

### Invocation

```bash
shirabe validate --lifecycle-chain <seed-doc> --mode=ready --format human
```

### Exit-code contract

| Exit | Meaning |
|------|---------|
| 0 | Finalization **complete** — the chain is at its terminal: PLAN deleted, BRIEF/PRD at Done, DESIGN at Current. |
| 2 | Finalization **not done** — a present PLAN or an un-transitioned upstream fails `L01` under ready posture. The guard fires. |
| 1 | Tool-error — a bad invocation or unreadable input. **Inconclusive**, distinct from a violation. Never read it as a pass. |

The exit code alone is the pass/fail signal; the JSON or human output is for
diagnostics.

### The seed-doc rule

`--lifecycle-chain` seeds on a path that must exist. A missing seed returns `L05`
(exit 2), which looks like a real failure but is not. Pick the seed by what you are
checking:

- **Suspected mid-run** ("did my manual finalization land?"). Finalization did not
  complete, so the PLAN is still on disk. Seed on the PLAN:
  `docs/plans/PLAN-<slug>.md`. Ready posture fails `L01` (a present PLAN or
  un-transitioned upstream) and the guard fires with exit 2 — exactly the case the
  guard is for.
- **A finalized chain** (CI, or confirming completion). The PLAN is gone — the
  cascade deletes it — so seed on the **durable surviving anchor**: the DESIGN at
  `docs/designs/current/DESIGN-<slug>.md`, or the BRIEF/PRD at Done. **Never seed on
  the deleted PLAN path**, which returns `L05` (exit 2) and reads as a false failure.
  The same invocation returns exit 0 on a complete chain and exit 2 on an incomplete
  one.

The guard is meant to run at finalization time, not mid-effort. A chain that is
legitimately mid-flight has a present PLAN and reads "not done," which is correct but
noisy if you ask too early. CI gates the guard on a ready (non-draft) PR for exactly
this reason: the reusable lifecycle workflow runs the equivalent whole-tree ready
check only when the PR is marked ready-for-review, so a draft PR's mid-flight cascade
does not false-fire.
