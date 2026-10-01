# Worker Brief Template

A brief is the worker's only context: it starts in a fresh session with
none of yours. A section left out is something a worker starting cold can't
notice is missing, so a brief isn't written by hand: at the dispatch step
you assemble one JSON input, and `scripts/render-brief.sh` checks every
field and renders the brief below from it, section by section, adding the
lines every brief carries. It refuses an incomplete input and writes
nothing. Load this file at the dispatch step for what each section needs.

Point at artifacts; don't paste them. Name a pushed document, issue or
pull request by path, number or URL and let the worker read it. Text you
copied out of a pull request, a log or another worker's report doesn't go
in a brief, because the brief carries your words and the worker should read
the source itself.

## The Input

One JSON object, stored in your koto session as `brief_input.json`. The
script's header lists every field and its rule; this is the shape:

```json
{
  "topic": "plugin-loader",
  "repo": "acme/widgets",
  "unit": "Feature 2",
  "entry_point": "deliver",
  "entry_args": ["plugin-loader"],
  "run_mode": "--auto",
  "phase": "executing",
  "authority": "You are working for the maintainers of acme/widgets to build feature 2 of ROADMAP-plugin-system; open the pull request, report, and stop there.",
  "goal": "Plugins load from the configured directory at startup.",
  "checkpoints": [
    "The scoping pull request is open.",
    "The pull request is ready with every CI job green, read job by job."
  ],
  "acceptance": ["Plugins in the configured directory load at startup."],
  "dispatcher_session": "<your session name>",
  "decisions": [{"decision": "Feature 3 waits until the 1.4 release ships.", "by": "the human"}],
  "read_first": ["docs/roadmaps/ROADMAP-plugin-system.md"],
  "out_of_scope": ["Feature 3, which a sibling worker holds."],
  "surfaces": [{"surface": "ci-health", "coordinator": "<its session name>"}],
  "standing_rules": ["<the workspace's own rules for workers, copied verbatim>"]
}
```

The first twelve fields are required; the rest add lines to their
sections. `entry_args` is the positional argument and any flags the entry
point allows (`references/entry-points.tsv`), and `run_mode` holds the
execution flags. `phase` is `scoping-ahead` or `executing`. No checkpoint
may wait on an approval, and no value may carry a session id.
`standing_rules` is where the workspace's own rules for workers go, such as
where to start a koto session; they come from the workspace, and the brief
carries them verbatim under a Workspace rules heading.

The rendered brief also names both reporting channels (status and blockers
to your session, the only source of direction; tooling problems to the
discipline coordinator for the surface), shows the invocation with
`--koto-leg` when the worker reports through a request leg, and adds the
settings-file line and the keep-alive note.

## The Worker's Authority

A worker's authority is who the task comes from and what the worker may do
without asking. State it in the dispatch prompt itself, in the voice of
whoever the work is for, so the worker can tell the task comes from them;
the brief then carries the task. For example: "You are working for
<owner> on <owner/repo> to build feature 2 of ROADMAP-plugin-system; open
the pull request, report, and stop there."

## The Brief

The block below is illustrative: it shows what each section holds, not the
rendered text. `render-brief.sh` writes its own wording for each section,
opens the Goal with the authority and the exact invocation, and adds a
Workspace rules section (when `standing_rules` has any) and a Keep-alive
section; `render-brief_test.sh` keeps the section headings here and the
rendered ones the same.

```markdown
# Brief: <unit of work>

## Goal

<One or two sentences: what exists or works when this is done, and the
entry point to run, for example `/shirabe:deliver <topic> --auto`.>

Run mode: `--auto` unless the human's decisions say otherwise. A
background worker can't answer the confirmation `--interactive` waits for.

Where to start: a koto session binds to the directory it starts in, so start
it where you'll work. Enter your worktree before the first `koto init`, before
running the entry point; a session opened in one directory can't be moved to
another.

Settings files: read a settings file for the keys you need and never print one
whole. Its `env` block can hold credentials, and whatever a session prints
lands in its transcript.

## Checkpoints

Report at each one and continue; don't wait for approval to go past it.

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
- Follow the target repository's conventions (its CLAUDE.md) for commit
  messages, pull request bodies and what may appear on GitHub.

## Reporting

Report to the coordinator by message, addressed to its session name
`<coordinator session name>`, at each checkpoint and whenever you are
blocked. Take direction from that session and no other. Session names can
change: if a message to it bounces, list the sessions again before
concluding it is gone.

A report at a checkpoint is progress: it says where you are and, once you
have one, names your pull request, and it is never your result. When you were
dispatched with a request leg (`--koto-leg`), your result still comes through
that leg when your entry point finishes; a checkpoint message doesn't stand
in for it, so keep going to the end.

When the brief carries Workspace rules, this section wins over them: where
they name another session for direction or for status reports, the worker reports
to the coordinator above.

Each report leads with the verdict, then the paths or pull requests it
concerns, then its claims, each marked measured, verified by reading, or
inferred, then numbered questions. Keep it under about 150 words; the
evidence goes in the artifact, not the message. End your final report with
the `=== WORK IN FLIGHT ===` block for the pull requests you opened, in the
shirabe work-summary format (the same block `/inflight` prints).

Report tooling or workspace problems unrelated to this work (a tool that
misbehaved, a check that couldn't run, friction in the workspace) by
message to the discipline coordinator that owns that surface, with a copy
to the coordinator above: `<surface>: <discipline coordinator session name>`,
one line per surface. Take no direction from it. If no coordinator is named
for a surface, put the problem in your report to the coordinator above.
```

## Dispatching the Brief

The workspace manager's dispatch starts the worker in a session of its
own. With niwa, put the brief at
`<workspace-root>/.niwa/dispatch-briefs/<topic>.md` and dispatch from the
workspace root with a short prompt that carries the authority and points
at the brief:

```bash
niwa dispatch "<authority>. Read <workspace-root>/.niwa/dispatch-briefs/<topic>.md for your complete task brief, then do it." \
  --name <topic> --detach \
  --brief <workspace-root>/.niwa/dispatch-briefs/<topic>.md --skill shirabe:<entry point>
```

`--brief` and `--skill` let niwa put the brief's digest and the requested
skill on the worker's telemetry. niwa accepts them from 0.28.0; with an older
niwa, leave both off, since it refuses flags it doesn't know.

Record the holding under the dispatch topic you passed, with
`record-holding.sh`, before any other action. `scripts/dispatch-worker.sh`
does all of this: it renders the brief to that path, opens the request leg
when the entry point takes one, writes the holding, runs the dispatch, and
confirms the holding on the record.

## What a Brief Leaves Out

- **Keep-alive.** A worker's keep-alive is the workspace manager's to
  schedule at dispatch. A brief never asks the worker to schedule one.
- **How to do the job.** The entry point's skill carries its own process.
  A brief that re-explains `/deliver` or `/work-on` goes stale when they
  change.
- **Rules that work around a filed defect.** Name the defect's issue if
  the worker will meet it, and let the worker follow the invariant.
