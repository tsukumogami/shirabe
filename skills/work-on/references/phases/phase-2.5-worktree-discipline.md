# Phase 2.5: Worktree Discipline Check (Plan-Orchestrator Only)

Decide whether upstream main movement invalidates the PLAN's intent, before
any child workflow is dispatched. This phase runs inside the
`worktree_discipline_check` koto state defined in
`skills/execute/koto-templates/execute.md`.

## When This Phase Runs

This phase runs at most once per run, between `orchestrator_setup` and
`spawn_and_await`, in plan-orchestrator mode (`/execute` on a
`schema: plan/v1` doc). Single-issue `work-on.md` invocations do NOT execute
this phase.

Most runs never reach it. Before this state, koto runs two mechanical states
itself:

- `drift_facts` fetches `origin`, finds the PLAN's base (the merge-base of the
  PLAN's last commit and `origin/main`), and compares what main changed since
  then against the paths the PLAN references. It writes the result to the
  `drift_facts.json` and `plan_intent.md` context keys.
- `worktree_sync` rebases the shared branch onto that `origin/main`.

When the facts say main didn't move, or moved only in paths the PLAN doesn't
reference, the run goes straight to `spawn_and_await` and nobody is asked
anything. You're here only when the facts couldn't rule drift out: main
changed or deleted a path the PLAN references, the facts were cut to fit their
size limit, or the PLAN references no path beyond itself and its upstreams.

## Goal

Catch upstream drift before the children start rather than at PR
finalization. When main has advanced under a long-running PR's shared branch,
the PLAN's foundation may have shifted in ways the operator needs to act on
before the first child commits. Deciding this at the point recovery is
cheapest is the contract this phase delivers.

## Steps

You don't fetch, rebase, or write any file in this phase. The fetch and the
rebase already happened, and the facts are already recorded.

### 2.5.1 Read the Facts and the PLAN's Intent

```bash
koto context get {{SESSION_NAME}} drift_facts.json
koto context get {{SESSION_NAME}} plan_intent.md
```

`drift_facts.json` (schema `drift-facts/v1`, route `judge` whenever you're
here) carries:

- `reasons` -- why you're being asked: `overlap`, `deleted_references`,
  `truncated`, or `no_code_references`.
- `base` and `main_head` -- the commits compared, and `commits_since_base`.
- `referenced_paths` -- the paths the PLAN references, resolved against the
  base. A directory ends in `/`; a file the PLAN plans to create shows up as
  its nearest existing directory.
- `overlap` -- each changed path main touched inside that set, with its
  `status` (`modified`, `added`, `deleted`, `renamed`, ...), `added` and
  `removed` line counts, and `renamed_to` for a rename.
- `deleted_referenced_paths` -- referenced paths that exist at the base and no
  longer exist on main.
- `truncated` -- the lists were cut to keep the payload within 8192 bytes.

The facts hold no commit messages and no diff text. When a path's content
matters to the decision, read it yourself: `git show <main_head>:<path>` or
`git diff <base> <main_head> -- <path>`.

`plan_intent.md` holds the PLAN's title, upstreams, Scope Summary, and each
outline's goal -- what the PLAN is trying to do, which is what the changes are
measured against.

If `drift_facts.json` doesn't exist, the `drift_facts` state was overridden
and nothing was precomputed. Find the pre-rebase commit in `git reflog`, and
compare what `origin/main` changed since its merge-base with that commit
against the PLAN yourself.

### 2.5.2 Classify Upstream Impact

Read `${CLAUDE_PLUGIN_ROOT}/references/worktree-discipline.md` for the full
classification rule. There are two classes here; the third, "none", belongs to
the script, which has already routed that case past this state.

- **Informational** -- main touched paths the PLAN references, but the changes
  do NOT invalidate the PLAN's intent (e.g., docs-only edits, unrelated test
  additions, formatting passes, a change elsewhere in a directory the PLAN
  names).
- **Intent-changing** -- main changed something the PLAN depends on so the
  PLAN no longer holds as written: a referenced file was deleted or renamed,
  the contract the PLAN relies on was changed, the substrate the PLAN edits
  was restructured.

A PLAN that references no code (`no_code_references`) is asked about because
the facts can't tell; judge it from `commits_since_base` and what main
changed. If main didn't advance at all, it's `informational`.

The classification is about whether the PLAN's foundation still holds, not
about whether the rebase was mechanically clean. A clean rebase can silently
land a contract change that breaks the PLAN's references; a mechanical
conflict can be in a file the PLAN doesn't care about.

### 2.5.3 Submit Evidence

Submit `impact` to the `worktree_discipline_check` state:

```bash
koto next {{SESSION_NAME}} --with-data '{"impact": "informational", "rationale": "main reformatted docs/guide.md, which the PLAN only cites"}' --no-cleanup
# or
koto next {{SESSION_NAME}} --with-data '{"impact": "intent-changing", "rationale": "main deleted references/worktree-discipline.md that this PLAN renames to; PLAN must be re-planned against new main"}' --no-cleanup
```

`informational` routes forward to `spawn_and_await`. `intent-changing` routes
to `escalate_upstream_drift` → `done_blocked` carrying the rationale as the
actionable failure reason -- **inside the same `koto next` call**, because
`escalate_upstream_drift` declares required evidence but exits to
`done_blocked` unconditionally, so koto chains straight through it. That is
why every line above carries `--no-cleanup`: without it, the `intent-changing`
tick disposes of the orchestrator's session and destroys the record of why the
chain was stopped.

This file sits under `/work-on` but is read only by `/execute`'s
`worktree_discipline_check`, which runs on the orchestrator — always a root — so
the flag is correct here even though `/work-on`'s other phase files must not
carry it. See
[`references/koto-session-retention.md`](../../../../references/koto-session-retention.md).

## Why This Phase Exists

Without it, `/work-on`'s plan-orchestrator mode could ship a PR whose PLAN
foundation has silently shifted out from under it. The catastrophic failure
mode (SE11 PR-141 in the v0.7.0 friction record) hit when main moved during a
multi-day chain run and the operator only discovered the drift at PR
finalization — at which point recovery costs were maximal. This phase moves
the detection point to before the first child, where recovery is cheapest,
and the facts computed ahead of it keep the question from being asked when the
answer is mechanical.

## Quality Checklist

- [ ] `drift_facts.json` and `plan_intent.md` were read before classifying
- [ ] `impact` value is one of `informational`, `intent-changing`
- [ ] `rationale` is populated when `impact` is `intent-changing`
- [ ] The `koto next` submission carries `--no-cleanup`
