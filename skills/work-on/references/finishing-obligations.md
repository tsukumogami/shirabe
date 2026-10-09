# Finishing obligations: what enforces each one

Every obligation that decides whether a change is finishable is either
**gate-enforced** — a fact the engine checks by running something — or
**evidence-carried** — a judgment the run must state, in a form a placeholder
does not satisfy. An obligation in neither class is not a requirement of this
workflow; the last section records the ones deliberately left advisory.

The distinction is not bookkeeping. An obligation stated only as prose in a
reference file is delivered to a run and can be skipped by it without anything
noticing, which is what happened on three separate standalone runs and is why
this table exists.

## Gate-enforced

| Obligation | State | Gate | Fails when |
|---|---|---|---|
| The pull request body closes its issue | `pr_creation` | `closing_keyword` | The body GitHub actually has carries no closing keyword for this issue number. Free-form work has no issue and the gate passes without consulting the body. |
| The pull request is mergeable | `ci_monitor` | `merge_state_clean` | GitHub reports `DIRTY`. Necessary because a conflicted pull request gets no new check-runs, so the CI gate reads as green on one. |
| CI is green | `ci_monitor` | `ci_passing` | Any check is outside the pass and skipping buckets. |
| The summary has the required shape | `finalization` / `deferral_approval`, then `pre_pr_evidence` | `summary_shape` | `summary.md` has no `## Changes Made` section. |
| Every commit follows the commit convention | `finalization` / `deferral_approval`, then `pre_pr_evidence` | `commit_convention` | `check-branch-output.sh --commits` finds a commit in `impl_base..HEAD` (merges skipped) whose subject is not a Conventional Commits subject (`commit/conventional-subject`) or that carries an AI-attribution trailer (`commit/no-ai-trailer`), or can't decide (exit 2). |
| The change passes the project's verification map | `verification` | `verification_verdict` (`poll:`) | `check-verification.sh --verdict` reads the result of the commands `run-verification.sh --start` ran from the map at the merge-base: exit 1, a command failed, returns to `implementation`; exit 3 (no map, a bad map, nothing selected) and exit 4 (needs a person, timed out, runaway, not started, dirty tree) end at `done_blocked`; 75 waits; 2 holds. |
| No `wip/` file reaches the pull request | `pr_precheck` | `branch_wip_clean` | `check-branch-output.sh --wip` finds a path under `wip/` in `HEAD`'s tree (`branch/no-wip-files`), or can't decide. Passes on a shared branch, whose pull request `/execute` owns. |
| Changed documents respect the repository's visibility | `pr_precheck` | `branch_docs_visibility` | `check-branch-output.sh --docs-visibility` finds a changed `docs/` document failing `shirabe validate`'s visibility rules (R7, R8, R9), or can't decide. Passes on a shared branch. |
| The pull request title and body conform | `pr_creation` | `pr_body_conformant` | `check-pr-output.sh --pr-body` runs `shirabe validate --pr-body` on the title and body GitHub has, and it reports a PB1 to PB4 violation, or the check can't decide. |
| The cleanup referent is a commit in the branch's history | `finalization` / `deferral_approval`, then `pre_pr_evidence` | `cleanup_referent` | `pre_pr.md` records something other than a sha (`done`), a sha that names no commit, or a commit that is not `HEAD` or an ancestor of it. |
| The diagram referent is a file or a stated reason | `finalization` / `deferral_approval`, then `pre_pr_evidence` | `diagram_referent` | `pre_pr.md` records neither a `docs/` path that is a file in `HEAD`'s tree nor `not-applicable: <reason>`. |
| The issue has a PLAN behind it, or provably does not | `cascade_entry` | `anchor_present` | Undecidable rather than absent: an ambiguous or unreadable corpus stops the run instead of skipping the cascade in silence. |
| The run is a root, not a child | `ci_monitor` | `is_root` (routing) | Not a failure: an answer. `session-role.sh` prints anything but `root`, so a run with green CI goes to `done` instead of `cascade_entry`. |
| The issue is still current | `staleness_check` | `staleness_fresh` (routing) | Not a failure: an answer. `check-staleness.sh` exits 1 (stale), and the run goes to `introspection`; 0, 3 and -1 go to `analysis`. Only exit 2 holds. |

### Routing gates

`is_root` and `staleness_fresh` decide a route rather than judge output, so
their non-zero exits are answers, and neither prints a `::koto-finding::` line.
The evidence values that used to restate them (`staleness_signal: fresh`,
`stale_requires_introspection` and `unavailable`, and the root-or-child field
`ci_monitor` asked for) are gone: koto routes on the exit status, so there is
no copy for a run to get wrong.

### Checked where it is written, and again at the end

`summary.md` and `pre_pr.md` are both written at `finalization`, and their
three gates run twice, as does `commit_convention`. `summary_shape` checks a shape; the two referent gates
run `scripts/check-pre-pr-referents.sh`, which checks that the commit and the
path exist, since a shape check passed a sha that named nothing. At
`finalization` (and on `deferral_approval`'s
approved edge) a failure matches no edge: the run holds in that state with the
gate named, and the agent fixes the artifact in place. At `pre_pr_evidence` the
same failure routes to `done_blocked`. The second check is the backstop and is
not weakened by the first; the first exists because that terminal is expensive:
the run has to be re-entered to fix what was one edit away. The gate definitions
must be identical in all three states, which `scripts/finalization-shape_test.sh`
checks.

## Evidence-carried

Each field is an enum or a referent a gate checks. None is a free
string: koto's evidence schema has `type`, `required`, `values` and
`description`, and nothing that constrains a string, so a `type: string` field is
satisfied by `done` and the obligation is unenforced in substance while looking
enforced in the record.

| Obligation | State | Field | Why a placeholder cannot satisfy it |
|---|---|---|---|
| The code was cleaned up | `pre_pr_evidence` | `cleanup_done` | A closed enum (`removed`, `none_found`), with the commit reviewed recorded in `pre_pr.md` and gated as `HEAD` or an ancestor of it. |
| The design diagram was updated, or does not apply | `pre_pr_evidence` | `design_diagram` | A closed enum, with the path or the stated reason in `pre_pr.md`, and a path gated as a file in `HEAD`'s tree. |
| What the cascade did | `cascade_run` | `cascade_status` | A closed enum. |
| What the repository shows after the cascade | `cascade_run` | `post_state` | A closed enum of one success and five distinct causes, read from the verifier's exit code. |
| The anchor and the finalization commit | `cascade_run` | `anchor_plan`, `finalization_commit` | A path and a sha, both re-derivable: the verifier reads the same commit independently, so a wrong value fails the state rather than decorating it. |

## Deliberately advisory

| Obligation | Why it is not enforced here |
|---|---|
| Which reviewer-context sections a pull request body needs | Genuinely a judgment with no concrete referent, and the mechanical half of the body rule is enforced by `pr_body_conformant` (and by `shirabe validate --pr-body` in CI). Recording it as an evidence field would produce a field satisfied by any string, which R7a rules out. |
| Currency with the default branch beyond mergeability | `merge_state_clean` covers the case that blocks a merge. A stricter "has merged the latest default branch" check (`origin/main` an ancestor of `HEAD`) would fail runs that are merely behind, which is not a finishing defect. A branch that is behind catches up by merging main in, never by a rebase. |

## What this table does not claim

The routing is real: at `pre_pr_evidence` a failing gate sends the run to a
distinct terminal edge (the early copies at `finalization` and
`deferral_approval` hold in place instead).
Each edge's `context_assignments` writes a human-readable `failure_reason` into
the session's context, which says which rung fired. It does not say why the
gate failed. The gate scripts this workflow's output gates call
(`check-branch-output.sh`, `check-pr-output.sh`, `check-verification.sh`) print
one `::koto-finding::` line per violation, which koto keeps in the response and
the event log with the rule's name and reference. The referent checks print no
findings, so their detail has to be recovered by running the script by hand,
which is why the scripts keep their stderr rather than discarding it. For the
referent gates the finalization directive gives the command.
