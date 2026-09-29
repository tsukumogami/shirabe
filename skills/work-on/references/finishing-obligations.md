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
| The tip commit follows the commit convention | `pre_pr_evidence` | `commit_convention` | The tip subject is not a Conventional Commits subject. |
| The cleanup referent is a commit in the branch's history | `finalization` / `deferral_approval`, then `pre_pr_evidence` | `cleanup_referent` | `pre_pr.md` records something other than a sha (`done`), a sha that names no commit, or a commit that is not `HEAD` or an ancestor of it. |
| The diagram referent is a file or a stated reason | `finalization` / `deferral_approval`, then `pre_pr_evidence` | `diagram_referent` | `pre_pr.md` records neither a `docs/` path that is a file in `HEAD`'s tree nor `not-applicable: <reason>`. |
| The issue has a PLAN behind it, or provably does not | `cascade_entry` | `anchor_present` | Undecidable rather than absent: an ambiguous or unreadable corpus stops the run instead of skipping the cascade in silence. |
| The run is a root, not a child | `ci_monitor` | (evidence: `session_role`) | See below — carried rather than gated, because the discriminator is a script the run calls. |

### Checked where it is written, and again at the end

`summary.md` and `pre_pr.md` are both written at `finalization`, and their
three gates run twice. `summary_shape` checks a shape; the two referent gates
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
| The run knows whether it is a root or a child | `ci_monitor` | `session_role` | A closed enum read from `session-role.sh`, which reads koto's own `parent_workflow`. Required, because the state's last edge is unconditional and a missing value would take it. |
| What the cascade did | `cascade_run` | `cascade_status` | A closed enum. |
| What the repository shows after the cascade | `cascade_run` | `post_state` | A closed enum of one success and five distinct causes, read from the verifier's exit code. |
| The anchor and the finalization commit | `cascade_run` | `anchor_plan`, `finalization_commit` | A path and a sha, both re-derivable: the verifier reads the same commit independently, so a wrong value fails the state rather than decorating it. |

## Deliberately advisory

| Obligation | Why it is not enforced here |
|---|---|
| Which reviewer-context sections a pull request body needs | Genuinely a judgment with no concrete referent, and the mechanical half of the body rule is already enforced by `shirabe validate --pr-body` in CI. Recording it as an evidence field would produce a field satisfied by any string, which R7a rules out. |
| Currency with the default branch beyond mergeability | `merge_state_clean` covers the case that blocks a merge. A stricter "has merged the latest default branch" check (`origin/main` an ancestor of `HEAD`) would fail runs that are merely behind, which is not a finishing defect. A branch that is behind catches up by merging main in, never by a rebase. |

## What this table does not claim

The routing is real: at `pre_pr_evidence` a failing gate sends the run to a
distinct terminal edge (the early copies at `finalization` and
`deferral_approval` hold in place instead).
Each edge's `context_assignments` writes a human-readable `failure_reason` into
the session's context, which says which rung fired. It does not say why the
gate failed. koto keeps a failed command gate's exit status
and discards what the command printed, so the detail has to be recovered by
running the gate's script by hand, which is why the scripts those gates call
keep their stderr rather than discarding it. For the referent gates the
finalization directive gives the command.
