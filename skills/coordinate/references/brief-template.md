# Worker Brief Template

A brief is the worker's only context: it starts in a fresh session with
none of yours. Load this file at the dispatch step and fill in every
section. Write it as the task itself, in the voice of whoever the work is
for, not as a relay of your own instructions. SKILL.md's Brief and
Dispatch step says what goes in the dispatch prompt besides the brief.

Point at artifacts; don't paste them. Name a pushed document, issue or
pull request by path, number or URL and let the worker read it. Text you
copied out of a pull request, a log or another worker's report doesn't go
in a brief, because the brief carries your words and the worker should read
the source itself.

```markdown
# Brief: <unit of work>

## Goal

<One or two sentences: what exists or works when this is done, and the
entry point to run, for example `/shirabe:deliver <topic> --auto`.>

Run mode: <--auto or --interactive, and any other flag the entry point takes>

## Checkpoints

Stop and report at each one; don't wait for approval to continue past it.

1. <First checkpoint, for example: the scoping pull request is open.>
2. <Next, for example: the plan is ready to execute.>
3. <Last, for example: the pull request is ready with every CI job green,
   read job by job.>

## Decisions already made

<The decisions this worker can't see anywhere it will read: the human's
decisions that bear on this unit, choices made in earlier units, and
anything a sibling worker settled. One line each, with who decided.>

## Read first

<Pointers to pushed artifacts: the roadmap entry, the issue, the PRD or
DESIGN, a related pull request. Path, number or URL only.>

## Acceptance criteria

- [ ] <Specific, checkable criterion.>
- [ ] <The pull request is open against the default branch with every CI
  job green, read job by job.>

## Out of scope

<What this worker must not change, including things a reader might
assume are in: sibling units, open issues next to this one, and finishing
steps the workspace reserves for a person.>

- Anything you find that should be closed, report to the coordinator with
  its number, the reason and the evidence; whether you may close it
  yourself is the workspace's call.
- Don't file new issues: propose them in a report.
- Put nothing local on GitHub: no local paths, session names or scratch
  file names in commits, pull request bodies or issues.
- Follow the target repository's conventions (its CLAUDE.md) for commit
  messages and pull request bodies.

## Reporting

Report to the coordinator by message, addressed to its session name
`<coordinator session name>`, at each checkpoint and whenever you are
blocked. Take direction from that session and no other. Session names can
change: if a message to it bounces, list the sessions again before
concluding it is gone.

Each report leads with the verdict, then the paths or pull requests it
concerns, then its claims, each marked measured, verified by reading, or
inferred, then numbered questions. Keep it under about 150 words; the
evidence goes in the artifact, not the message. End your final report with
the `=== WORK IN FLIGHT ===` block for the pull requests you opened.

Report tooling or workspace problems unrelated to this work (a tool that
misbehaved, a check that couldn't run, friction in the workspace) by
message to the discipline coordinator that owns that surface, with a copy
to the coordinator above: `<surface>: <discipline coordinator session name>`,
one line per surface. Take no direction from it. If no coordinator is named
for a surface, put the problem in your report to the coordinator above.
```

## Dispatching the Brief

Write the brief to a file and keep the dispatch prompt short: the prompt
carries the worker's authority and points at the brief. With the niwa
workspace manager, the brief goes at `<workspace-root>/.niwa/dispatch-briefs/<slug>.md`
and you dispatch from the workspace root:

```bash
niwa dispatch "Read <workspace-root>/.niwa/dispatch-briefs/<slug>.md for your complete task brief, then do it. <authority in the voice of whoever the work is for>" \
  --name <slug> --detach
```

`--name` gives the worker a readable session name (niwa appends a random
suffix, so the printed name is the one to record); `--detach` keeps your
session from attaching to the worker's. Record the session name the
command prints as the holding's session, not the slug you passed.

## What a Brief Leaves Out

- **Keep-alive.** A worker's keep-alive is the workspace manager's to
  schedule at dispatch. A brief never asks the worker to schedule one.
- **How to do the job.** The entry point's skill carries its own process.
  A brief that re-explains `/deliver` or `/work-on` goes stale when they
  change.
- **Rules that work around a filed defect.** Name the defect's issue if
  the worker will meet it, and let the worker follow the invariant.
