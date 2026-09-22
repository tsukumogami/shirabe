# Lead: How does `/scope` finish today, and what does its exit hand to the next step?

Paths are relative to the shirabe repo root.

## Findings

### Exit paths

`/scope` ends at one of three recorded exits plus an unrecorded cancel
(`skills/scope/SKILL.md:417-432`; `skills/scope/references/phases/phase-3-exit-finalization.md:33-160`):

- **`full-run`**: the chain walked through `/plan`, and the PLAN sits at `docs/plans/PLAN-<topic>.md`.
- **`re-evaluation`**: a settled PRD or DESIGN was rejected at a boundary. Writes a Decision Record under `docs/decisions/`.
- **`abandonment-forced`**: a child was mid-flight when the run stopped. Its intermediate is force-materialized as a Draft carrying a `scope-status-block: abandonment-forced` marker.
- **Clean cancel** (`bail_ack: cancel`): no exit value, no artifact. Only `wip/scope_<topic>_state.md` is deleted (phase-3 lines 217-247).

The koto template routes `finalize` to `exit_full_run` / `exit_re_evaluation` / `exit_abandonment`. Each of those goes to its own `cleanup_*` state and then to a terminal `done_*` (`skills/scope/koto-templates/scope.md:423-723`). `exit_full_run` carries the chain-wide gate `chain_complete`: `hop-complete.sh` runs once per hop, joined with `&&` (lines 445-497). If it fails, the run goes to `full_run_blocked`, which offers only `recheck` or `abandon` (lines 499-541).

### State written at exit

- On full-run: `exit: full-run`, `chain_completed`, `plan_execution_mode: single-pr | multi-pr | coordinated`, and `exit_artifacts` (every surviving durable artifact, not only the PLAN) (phase-3 lines 50-62). In the template, `plan_execution_mode` is a required enum evidence field on `exit_full_run` (scope.md:472-475). The agent reads the value off what `/plan` settled on in its hop (scope.md:967-968).
- R9 Part 3 requires `plan_execution_mode` to be present if and only if `/plan` is in `chain_ran` (phase-3 lines 306-310).
- `boundary: prd | design` and `decision_record_sub_shape` are written only on `re-evaluation` (phase-3 lines 119-128; `references/parent-skill-state-schema.md:78-88`).
- Phase 4 then deletes the state file (`skills/scope/references/phases/phase-4-cleanup.md`). The koto session is kept with `--no-cleanup` (scope.md:1281-1285). **After a finished run, `plan_execution_mode` survives only in the retained koto session evidence and in the PLAN's own `execution_mode` frontmatter.** The wip state file is gone.

### Final message and next-step recommendation

The last thing `/scope` prints is a single line (phase-4-cleanup.md:139-153):

```
/scope finished: exit=full-run; artifact=docs/plans/PLAN-<topic>.md
```

That line names no next step. The `done_full_run` terminal body only restates that the chain completed (scope.md:1324-1327). The only next-step advice in the chain comes from the child `/plan`, not `/scope`:

- For single-pr, `/plan` recommends "Run `/work-on docs/plans/PLAN-<topic>.md`" (`skills/plan/references/phases/phase-7-creation.md:363-365`, 518-520).
- For multi-pr, it prints a "Next Steps" list of dependency-free issues (phase-7 lines 500-514).

This single-pr advice contradicts `/execute`'s own routing. `/execute` owns single-pr and coordinated plans and sends only multi-pr to `/work-on` (`skills/execute/SKILL.md:44-49`).

### PLAN status by mode

The two skills disagree here.

- **`/scope` says:** Draft when single-pr, Active (with a milestone) when multi-pr or coordinated (phase-3 lines 44-48).
- **`/plan` says** (the current contract, `skills/plan/SKILL.md:66-77`; phase-7 lines 311-321): the Draft to Active gate depends on whether GitHub issues get filed, not on the mode.
  - A PLAN that files nothing is authored directly at `status: Active`.
  - One that files issues needs human approval first.
  - A committed PLAN at `status: Draft` is a lifecycle-check violation.
  - A default single-pr PLAN therefore lands Active, not Draft.

### Are issues filed?

That's decided by `/plan`'s tracking level, resolved as `flag > CLAUDE.md ## Tracking Level > default`. It's a separate question from the mode (phase-7 lines 70-105).

- The default is `none` for single-pr (no issues, no milestone) and `issues-and-milestone` for multi-pr.
- Coordinated tracking is governed by `references/coordination-strategy.md`.
- `/scope` itself files nothing.
- Activation that files issues requires human approval (plan SKILL.md:72-76). That's a potential stop point for an unattended session.

### Branch / PR for the scoping docs

- `branch_check` refuses to start unless HEAD is on a named branch other than main or master. `/scope` never creates the branch; it refuses (scope.md:61-114; phase-2 lines 521-543).
- Each hop is committed locally, one pathspec per artifact (phase-2 lines 545-578).
- **Nothing pushes** (phase-2 line 580: "a branch reaches a remote when the author or a downstream skill puts it there"; SKILL.md:505-507).
- Single-repo runs open no PR.
- Coordinated runs create a draft coordination PR up front with `gh pr create` (SKILL.md:202-225; `skills/scope/requires.tsv:21-22`). That PR merges last, as the effort's done-signal (`references/coordination-strategy.md:28-35, 66-72`).
- `/scope` never merges anything. The only `gh` action it takes at the end is `gh pr close` on the coordination PR, and only when a coordinated run is abandoned (phase-3 lines 162-177).

### Existing route to `/execute` or `/work-on` at exit

None. `/scope` doesn't invoke either one and has no chaining flag.

- The only mentions of `/execute` in `/scope` are internal cross-references, e.g. "a chain that folds everything away is handled downstream by `/execute`'s finalization guard" (phase-2 line 844).
- `/work-on` shows up only in the resume ladder's refuse-and-redirect. Slot 5.1, PLAN-Active, emits "redirect to /work-on <topic-slug>" (`skills/scope/references/phases/phase-resume.md:18-26`).
- The redirect is stale in two ways:
  - It sends coordinated and single-pr Active PLANs to `/work-on`, when `/execute` now owns those.
  - Since single-pr PLANs now land Active, re-invoking `/scope` right after a full-run would hit it.

### Flags

`/scope` accepts:

- `--auto`, `--interactive` (the default), and `--max-rounds=N` (SKILL.md:162-181)
- `--coordinated` / `--no-coordinated` (SKILL.md:208-210)
- `--upstream <path>`

It has no `--continue`, `--then-execute`, or equivalent. Phase 2 doesn't say explicitly that `--auto` is forwarded to the children. `/plan` has its own `--auto` (plan SKILL.md:277); under it, the mode recommendation is followed automatically (phase-3-decomposition.md:577-579).

### How the mode is picked (context for the launch-time uncertainty)

- It's resolved in `/plan` step 3.6. The default comes from `## Delivery Preference`: `consolidated`, the default, means single-pr.
- It leaves single-pr only through a named branch: Hard Constraint, Incremental Value, or Stated Preference (plan SKILL.md:151-195).
- A roadmap input is always multi-pr.
- `coordinated` is for multi-repo efforts (plan SKILL.md:197-215).
- So for a single-repo feature in a repo with no headers, the likely outcome is single-pr, but the launching session can't know that at launch.

## Implications

- A "scope then execute" session has to read the mode after `/scope` returns. The most durable place is the PLAN's `execution_mode` frontmatter, because the state file is gone after Phase 4. The session then branches:
  - single-pr or coordinated: `/execute`
  - multi-pr: `/work-on`, or stop
- None of that routing exists at `/scope`'s exit today.
- The scoping commits are local only. Something downstream has to push them.
  - For single-pr, `/execute` presumably carries the PLAN commit on the same branch into its implementation PR.
  - For multi-pr, a separate docs PR or the first issue's PR has to carry them.
- Coordinated isn't a "one session to merged" case like single-pr. It's multi-PR, with a coordination PR that merges last, so merge rights matter there as well.
- `/plan`'s approval gate on issue filing (the multi-pr default) can block an unattended session before `/scope` even finishes. Under `--auto` that behavior needs checking.

## Surprises

1. **The status table in `/scope` is stale.** Phase 3 says single-pr PLANs are Draft, but `/plan` now authors every no-issue PLAN at Active and treats a committed Draft PLAN as a violation.
2. **The next-step advice points the wrong way.** `/plan`'s single-pr advice is `/work-on PLAN`, but `/execute` claims single-pr. The resume ladder's PLAN-Active redirect also still says `/work-on`.
3. **The docs contradict each other on the PR body.** Phase 3 and `state-schema.md:266-270` say Phase 3 writes `chain_ran`, `chain_skipped` and `consolidation_judgments` into "the run's pull-request body". But `/scope` never opens a PR in single-repo mode and never pushes. The koto cleanup directive also says the per-hop record "is never copied into a committed artifact or a pull-request body" (scope.md:1284-1285; phase-4-cleanup.md:122-124).
4. **`references/parent-skill-state-schema.md:89-90` is out of date.** It lists `plan_execution_mode` values as only `single-pr | multi-pr`, while `/scope`'s template and state-schema include `coordinated`.
5. **`coordinated` behaves like multi-pr here.** The exploration grouped "single-pr or coordinated" as the one-session case, but coordinated is always multi-PR, with a coordination PR merging last.

## Open Questions

- Does `/scope --auto` forward `--auto` to `/plan`, so the mode choice and the issue-filing approval don't block? Phase 2 doesn't say.
- For single-pr, does `/execute` push the branch that already carries the scoping commits and fold them into its PR? Or does it expect a clean branch? Its Phase 0 "home-PR" lookup needs checking.
- Does single-pr `/execute` actually merge, or does it stop at `gh pr ready` (execute SKILL.md:144-147)? If it stops there, a session without merge rights ends at a ready PR even in single-pr mode.
- For multi-pr, what should carry the scoping docs to main, given that `/scope` never pushes?

## Summary

`/scope` ends at `full-run`, `re-evaluation`, or `abandonment-forced` (or a clean cancel). On full-run it records `plan_execution_mode` in a state file that Phase 4 then deletes, so after the run the mode survives only in the PLAN's `execution_mode` frontmatter and the retained koto session. Its final output is the one-line `/scope finished: exit=full-run; artifact=docs/plans/PLAN-<topic>.md`, with no next step and no route to `/execute` or `/work-on`, and it has no continue or chaining flag (only `--auto`, `--interactive`, `--max-rounds`, `--coordinated` and `--upstream`). It commits the scoping docs locally on a pre-existing non-default branch, never pushes, never opens a PR (except the up-front draft coordination PR in coordinated mode) and never merges anything, while issue filing is left to `/plan`'s tracking level (none for single-pr by default, issues plus milestone for multi-pr, behind a human-approval gate) — and several docs are stale: `/scope` says single-pr PLANs land Draft though `/plan` now writes them Active, `/plan` and the resume ladder still point single-pr and Active PLANs at `/work-on` though `/execute` owns single-pr and coordinated, and `coordinated` is really a multi-PR mode rather than a single-session one.
