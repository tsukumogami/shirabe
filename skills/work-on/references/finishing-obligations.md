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
| The summary has the required shape | `pre_pr_evidence` | `summary_shape` | `summary.md` has no `## Changes Made` section. |
| The tip commit follows the commit convention | `pre_pr_evidence` | `commit_convention` | The tip subject is not a Conventional Commits subject. |
| The cleanup referent is a commit | `pre_pr_evidence` | `cleanup_referent` | `pre_pr.md` records something other than a sha — `done` does not match. |
| The diagram referent is a path or a stated reason | `pre_pr_evidence` | `diagram_referent` | `pre_pr.md` records neither a `docs/` path nor `not-applicable: <reason>`. |
| The issue has a PLAN behind it, or provably does not | `cascade_entry` | `anchor_present` | Undecidable rather than absent: an ambiguous or unreadable corpus stops the run instead of skipping the cascade in silence. |
| The run is a root, not a child | `ci_monitor` | (evidence: `session_role`) | See below — carried rather than gated, because the discriminator is a script the run calls. |

## Evidence-carried

Each field is an enum or a referent whose shape a gate checks. None is a free
string: koto's evidence schema has `type`, `required`, `values` and
`description`, and nothing that constrains a string, so a `type: string` field is
satisfied by `done` and the obligation is unenforced in substance while looking
enforced in the record.

| Obligation | State | Field | Why a placeholder cannot satisfy it |
|---|---|---|---|
| The code was cleaned up | `pre_pr_evidence` | `cleanup_done` | A closed enum (`removed`, `none_found`), with the commit reviewed recorded in `pre_pr.md` and gated for shape. |
| The design diagram was updated, or does not apply | `pre_pr_evidence` | `design_diagram` | A closed enum, with the path or the stated reason in `pre_pr.md` and gated for shape. |
| The run knows whether it is a root or a child | `ci_monitor` | `session_role` | A closed enum read from `session-role.sh`, which reads koto's own `parent_workflow`. Required, because the state's last edge is unconditional and a missing value would take it. |
| What the cascade did | `cascade_run` | `cascade_status` | A closed enum. |
| What the repository shows after the cascade | `cascade_run` | `post_state` | A closed enum of one success and five distinct causes, read from the verifier's exit code. |
| The anchor and the finalization commit | `cascade_run` | `anchor_plan`, `finalization_commit` | A path and a sha, both re-derivable: the verifier reads the same commit independently, so a wrong value fails the state rather than decorating it. |

## Deliberately advisory

| Obligation | Why it is not enforced here |
|---|---|
| Which reviewer-context sections a pull request body needs | Genuinely a judgment with no concrete referent, and the mechanical half of the body rule is already enforced by `shirabe validate --pr-body` in CI. Recording it as an evidence field would produce a field satisfied by any string, which R7a rules out. |
| Rebase currency beyond mergeability | `merge_state_clean` covers the case that blocks a merge. A stricter "is rebased on the latest default branch" check would fail runs that are merely behind, which is not a finishing defect. |

## What this table does not claim

The routing is real: a failing gate sends the run to a distinct terminal edge.
The human-readable reason attached to each edge is not currently recorded
anywhere, because `context_assignments` is inert in the engine
(tsukumogami/koto#204, tsukumogami/shirabe#335). Until that is fixed, a blocked
run's reason is recovered from the gate's own output, which is why the scripts
those gates call keep their stderr rather than discarding it.
