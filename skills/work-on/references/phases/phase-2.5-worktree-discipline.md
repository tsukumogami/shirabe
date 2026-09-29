# Phase 2.5: Worktree Discipline Check

The steps for `/execute`'s `worktree_discipline_check` state.

## Steps

You don't fetch, change the branch, or write any file in this phase. The fetch
and the catch-up with main already happened, and the facts are already
recorded.

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
and nothing was precomputed. Find the shared branch's commit from before the
catch-up with main in `git reflog`, and compare what `origin/main` changed since
its merge-base with that commit against the PLAN yourself.

### 2.5.2 Classify Upstream Impact

Classify main's changes as one of two classes; the third, "none", belongs to
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
about whether the catch-up was mechanically clean. A clean one can silently
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

Every `koto next` carries `--no-cleanup`, on a root and on a child alike; see
[`references/koto-session-retention.md`](../../../../references/koto-session-retention.md).
