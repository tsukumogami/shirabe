# Phase 4 — Cleanup

Phase 4 removes key `work/prior-run.md` from `scope-<topic>` after
Phase 3's R9 hard-finalization check has passed, on every exit path.
That key carries the finished-run facts (`outcome`, `exit`, `intent`,
`step`) that `scope-open.sh` wrote from a replaced session's result;
once the run has ended and any publish retry has run, nothing may
read it a second time. A successful publish removes it too, and the
removal is idempotent: with no key it changes nothing.

```bash
koto context remove scope-<topic> work/prior-run.md
```

Nothing else is swept. The parent's own state is key `work/state.md`
in the same session, kept with the run's per-hop record (the session
ends with `--no-cleanup`), and each child keeps its own working files
as keys in its own session, which `close-children` closed at Phase 3.
No file under the staging folder is written by a run, so there is none
to delete. The terminal artifact (PLAN, Decision Record, or
force-materialized child doc) remains on disk on every exit path, and
Phase 4 does not touch durable documents under `docs/`.

## Trigger

Phase 4 runs ONLY after Phase 3's R9 hard-finalization check
returns success. A run that failed R9 stops at Phase 3 with the
violation surfaced; Phase 4 does NOT run against an unfinalized
state. The dependency is one-way: Phase 3's success gate is
the Phase 4 trigger.

## What Each Exit Path Leaves

The removal is the same on every exit path; the exit decides only which
durable document stays on disk, and Phase 4 does not touch it:

- `exit: full-run` -> `docs/plans/PLAN-<topic>.md`.
- `exit: re-evaluation` ->
  `docs/decisions/DECISION-{brief|prd|design}-<topic>-{re-evaluation|rejection}-<YYYY-MM-DD>.md`
  (`brief` with `rejection` only).
- `exit: abandonment-forced` ->
  `docs/{briefs|prds|designs}/<TYPE>-<topic>.md` (the marked
  document; a Draft unless it is the upstream document `/plan`
  was running against). No PLAN is left on disk.

On `abandonment-forced` the children's sessions are closed `abandoned`
and their keys stay readable, so a later session that resumes the
abandoned chain can read the child's last intermediate state back. The
publish step's untrack (see `skills/scope/SKILL.md`, Publish) keeps its
own `wip/` pathspecs: it guards history against staging-folder files and
is not part of this phase.

## Success Summary

The exit block is rendered from the terminal result by
`skills/scope/scripts/print-scope-exit.sh`, and the agent composes no
exit line. Once the `koto next` that reaches the terminal returns,
run

```bash
${CLAUDE_PLUGIN_ROOT}/skills/scope/scripts/print-scope-exit.sh --topic <topic> --session scope-<topic>
```

and print its output verbatim. The script reads the result koto
recorded (`koto status`) and prints, one `key=value` per line:

```
/scope finished: exit=<full-run|re-evaluation|abandonment-forced>; artifact=<terminal-artifact-path>
intent=<continue|stop|none>                   always
outcome=<scoped|handed-off-multi-pr|executed|error>
                                              full-run, executed, or error
step=<scope:push|scope:pr-create|scope:intake|scope:resume-probe|scope:refused>
                                              error only
next=<command>                                full-run only
pr=<url>                                      intent runs only
pr_state=<merged|open>                        executed only
wip_paths=<comma-separated paths>             when set
#<N> <title>                                  multi-pr startable items,
<closing line>                                then one closing line
```

`next=` is `/execute docs/plans/PLAN-<topic>.md` for a `single-pr` or
`coordinated` PLAN and `/work-on #<first startable>` for a `multi-pr`
one (R10). A `multi-pr` run lists every work item with no dependency
inside the PLAN, in PLAN order, and closes with one line: with intent,
that they can start once the scoping PR merges, naming it; without,
that they can start once the PLAN is on the default branch (R11).
Re-evaluation, abandonment and cancelled runs print today's exit
record with no `outcome=` line. A refusal prints its refusal text,
then `intent=`, `outcome=error` and `step=scope:refused`; `refused`
is never printed after `outcome=`. Every value is checked against a
closed pattern and dropped if it fails.

Example summaries:

- `/scope finished: exit=full-run; artifact=docs/plans/PLAN-my-topic.md`
- `/scope finished: exit=re-evaluation; artifact=docs/decisions/DECISION-prd-my-topic-re-evaluation-2026-05-31.md`
- `/scope finished: exit=abandonment-forced; artifact=docs/prds/PRD-my-topic.md`

The summary closes the chain. After Phase 4 returns, `/scope`
has no `work/prior-run.md` left and writes nothing under `wip/`; a
future `/scope` invocation against the same topic starts fresh
unless the terminal artifact's lifecycle has advanced (e.g.,
the PLAN moved Draft → Active under `/work-on`, which routes
through Slot 5's refuse-and-redirect on the next `/scope` run).

## References

- `skills/scope/references/phases/phase-3-exit-finalization.md`
  — the R9 hard-finalization check whose success is Phase 4's
  trigger.
- `skills/scope/SKILL.md` Security Considerations — the closed
  write-target set Phase 4's removals stay inside.
- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`
  — `exit:` enum the success summary names.
