# Probe: does a delegated child share the orchestrator's session id?

Run during `/design` Phase 2. This corrects an error I made when briefing the
evidence decision, and the correction is load-bearing, so it is recorded rather
than quietly fixed.

## The two mechanisms behave differently

**Agent-tool subagents share the parent's session id.** Measured live: a
`PreToolUse` hook fired for both a parent's write and a subagent's write in one
`claude -p` run, and both invocations reported
`session_id = 0fd0a4c3-50a9-48a5-a6fd-20d78f0623a6`. The subagent was
distinguishable only by `agent_id` and `agent_type` in the hook input, which the
parent's invocation did not carry.

**koto-spawned `/work-on` children get their own session id.** Read from real
session state for the run `execute-calendar-cli-only`:

```
parent  session_id: b78e9f2e-d9da-4193-9d9f-0d2458d1ac8d   template_name: execute
child   session_id: bb804b4e-81b0-4ea7-ba96-81a616a78b36   template_name: work-on
                    parent_workflow: execute-calendar-cli-only
```

Not the same id. That parent has four child session directories, named
`<parent>.o-<task-slug>`.

## Why the distinction matters

I briefed the evidence decision that a session-id-keyed record cannot separate
orchestrator work from delegated work, generalizing from the Agent-tool probe.
For koto delegation that is false, and it understated the available evidence.

Three signals link a child to its parent without touching hook input:

1. Distinct session ids, so each child has its own workflow record.
2. `parent_workflow` in the child's header, naming the parent explicitly.
3. `template_name`, which is `execute` for the orchestrator and `work-on` for
   the child.

The practical consequence is that R2's "every issue was delegated" bar may be
boundable by counting children whose `parent_workflow` matches, and comparing
against the plan's issue count. That is a stronger check than `scheduler_ran`
with `spawned_count >= 1`, which establishes only that a fan-out occurred.

## What remains open

Which mechanism `/execute`'s `spawn_and_await` actually uses. If any part of the
sanctioned loop delegates through the Agent tool rather than through koto child
sessions, that part is invisible to a session-id-keyed check, and the caution in
the first probe applies to it. The evidence decision owns resolving this, and its
recommendation depends on the answer.

Also open: what the check should do when a plan legitimately produces fewer
children than it has issues, for instance an outline that was merged or an issue
closed as a no-op. A naive count comparison would report a correct run as
non-conforming.

## Method note

The first briefing was an inference from one probe generalized past what it
measured. The probe was sound; the generalization was not. Recording both the
error and its correction here because a later reader following the decision's
reasoning would otherwise find a claim in the transcript that the design
contradicts, with nothing explaining which is right.
