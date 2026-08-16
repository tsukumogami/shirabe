# Phase 5: Execute

This arm exists only when a qualifying PLAN is already on disk. Crystallize
checked that before scoring — a file at `docs/plans/PLAN-*.md`, or any `.md`
whose frontmatter carries `schema: plan/v1`, whose `execution_mode` reads
`single-pr` or `coordinated`. If you reached this file without that path in
hand, the arm was not a candidate and something upstream misrouted; go back to
`wip/explore_<topic>_crystallize.md` and read the Candidacy section.

`/execute` accepts a PLAN path and nothing else. It has no topic mode, so the
arm is named only alongside the path it hands over.

**What the arm passes:** the PLAN path, exactly as it appears on disk.

No handoff artifact is written. The PLAN is the input, it already exists, and
`/execute` reads it directly.

Tell the author:

> Your exploration confirmed the scope and approach that
> `docs/plans/PLAN-<name>.md` already assumes, and what remains is execution.
> Run `/execute docs/plans/PLAN-<name>.md`.
>
> Your exploration research is saved in `wip/` if you need to reference it.

If the exploration changed the scope the PLAN assumes, `/execute` is the wrong
arm even with the file present — say so and route back to crystallize, where
that is a stage-2 anti-signal rather than a judgment made here.

## Artifact State

After this step:
- All explore artifacts in `wip/` (untouched)
- No new artifacts; the author runs `/execute <plan-path>` separately
