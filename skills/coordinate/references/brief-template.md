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
  "dispatcher_session": "<written by dispatch-worker.sh: the run rendering the brief>",
  "decisions": [{"decision": "Feature 3 waits until the 1.4 release ships.", "by": "the human"}],
  "read_first": ["docs/roadmaps/ROADMAP-plugin-system.md"],
  "out_of_scope": ["Feature 3, which a sibling worker holds."],
  "surfaces": [{"surface": "ci-health", "coordinator": "<its session name>"}],
  "standing_rules": ["<the workspace's own rules for workers, copied verbatim>"],
  "review_level": {"ceiling": "standard"}
}
```

The first twelve fields are required; the rest add lines to their
sections. `entry_args` is the positional argument and any flags the entry
point allows (`references/entry-points.tsv`), and `run_mode` holds the
execution flags, empty only for an entry point that takes none
(`/shirabe:release`). `dispatcher_session` is your koto run, which a request
leg names as its requester and a message-path worker records as its
dispatcher; it is never the address the worker reports to. That address,
`reports_to`, comes from the record's Run `coordinator` row. `dispatch-worker.sh`
writes both into the input (`dispatcher_session` as the run rendering the
brief), so leave them out. `phase` is
`scoping` (the unit is its scoping alone, from pick's `scope`),
`scoping-ahead` or `executing`. No checkpoint
may wait on an approval, and no value may carry a session id.
`standing_rules` is where the workspace's own rules for workers go, such as
where to start a koto session; they come from the workspace, and the brief
carries them verbatim under a Workspace rules heading.

`review_level` bounds the review level every `/work-on` run under the worker
picks: a `floor`, a `ceiling` or both, each `light`, `standard` or `full`,
the floor no higher than the ceiling. Give it only for an entry point that
takes the bound (`/deliver`, `/execute`, `/work-on`; their rows in
`references/entry-points.tsv` admit `--review-floor` and `--review-ceiling`).
The brief gets one line in Acceptance criteria and the invocation gets
`--review-floor=<x>` and `--review-ceiling=<y>`. Never put those flags in
`entry_args` or `run_mode`: `render-brief.sh` refuses them there, so the
level names always go through its check. Leave the field out and the brief
is the same as before it existed.

`grant` is what the worker is dispatched holding: the named authorities for
the landing steps the brief hands it to take itself (`merge-pr`,
`close-issue`, `cut-release`), left out or empty when it hands it none, or
`own` for a successor coordinator (entry point `coordinate`), which takes your
own grant as `niwa authority check` reported it. `dispatch-worker.sh` passes
it to `niwa dispatch` as `--grant`, with your instance as `--parent-from`, when
the installed niwa takes those flags, and replaces it with what the launch
asked for, so the brief's Goal carries one `Named authority:` line that names
exactly those authorities, or says the worker holds none (always so with a
niwa that takes no `--grant`). That line also tells the worker that a merge,
close or release its grant doesn't cover goes back to you in a report. The
grant is never wider than your own: niwa refuses one that is, and the
refusal is reported, never retried wider.

`launch` is how niwa starts the worker, and changes nothing in the brief.
Give it one or more of `model`, `permission_mode` and
`accept_session_messages`:

```json
"launch": {"model": "opus", "permission_mode": "bypassPermissions", "accept_session_messages": true}
```

`model` is one of niwa's capability categories (`balanced`, `fast`,
`powerful`) or a versionless model name (`fable`, `opus`, `sonnet`,
`haiku`); `permission_mode` is one of `default`, `acceptEdits`, `plan`,
`auto`, `dontAsk` and `bypassPermissions`; `accept_session_messages` is
`true` or `false`. `render-brief.sh` refuses any other key or value, so
nothing you didn't pick from those sets reaches the launch. Use it to start
a worker in the permission mode you run in, so it doesn't stall on a prompt
nobody answers, and with `accept_session_messages: true`, so your messages
reach it without an approval in its session. Leave it out and the worker
gets niwa's and the machine's defaults, as before the field existed.

The rendered brief also names both reporting channels (status and blockers
to your session, the only source of direction; tooling problems to the
discipline coordinator for the surface), shows the invocation with
`--koto-leg` when the worker reports through a request leg, and adds the
settings-file line and the keep-alive note.

## The Dispatcher on the Message Path

A worker on a request leg is joined to your run by the leg. A worker on the
message path has no leg, so it records your run as its dispatcher itself, from
its own session, and its brief tells it how. The Goal names your run as
`dispatcher_session: <your run>` and shows the exact command, with
`--dispatched-by <your run>` already filled in:

| Entry point | The command |
|-------------|-------------|
| `/coordinate` | `coordinate-open.sh --plugin-root ... --dispatched-by <your run> "$ARGS_DIR/args.json"`, in place of the open its skill shows |
| `/explore`, `/decision`, `/release` | `skill-session.sh open <skill> <topic> --dispatched-by <your run>`, in place of the open its skill shows |
| `/scope`, `/deliver`, `/execute`, `/work-on` | `link-dispatcher.sh <session> --dispatched-by <your run>`, once the entry point has opened its session |

The command links the worker's session to your run and, when the link fails,
runs it once more. A second failure prints `warning=link-failed
dispatched_by=<your run>` and records it in the worker's own context key
`session/link-warning`; the worker's session stays open and it goes on. You
learn of it from the worker's result, never by reading the worker's key.

The Reporting section then names the worker's report step:
`scripts/render-result.sh --session <its session>`, with `--pr <url>` per
pull request, whose block goes in the final report. It reads the worker's own
session and carries the worker's review round as a `review_round=` line, which
is where the land step reads it for a worker with no leg, and a
`warning=link-failed dispatched_by=<your run>` line for a link that failed. No
skill's text asks the worker to pass either on: the script does.

A worker moved to the message path later (a re-brief, an execution sent to an
entry point with no leg, a leg found unwatchable after an import) is
re-briefed through `dispatch-worker.sh`, so its new brief carries the command
too, and its `dispatcher_session` names the run that rendered it.

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

<On the message path only: `dispatcher_session: <your run>`, and the command
that records it in the worker's session with `--dispatched-by <your run>`
filled in (see The Dispatcher on the Message Path).>

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
- [ ] Review level: <floor X, ceiling Y>; /work-on's choice must fall
  inside it. (Only when the input gives `review_level`.)
- [ ] Each pull request has your review round recorded in your /work-on
  run's session with `review-round.sh record` (the round in
  `verification-checklist.md`), at the head you report ready. The land step
  reads it from there, through the worker's leg or in the result block its
  report step prints, and runs no review of its own. It never reads a round
  from the pull request body, so the worker puts none there. (Always; the
  renderer adds it.)

## Out of scope

<What this worker must not change, including things a reader might
assume are in: sibling units, open issues next to this one, and finishing
steps the brief doesn't hand it, which come back to you in a report.>

- Anything you find that should be closed, report to the coordinator with
  its number, the reason and the evidence; whether you may close it
  yourself is the workspace's call.
- Don't file new issues: propose them in a report.
- Follow the target repository's conventions (its CLAUDE.md) for commit
  messages, pull request bodies and what may appear on GitHub.

## Reporting

Report to the coordinator by message, addressed to `<the record's
coordinator address>`, the address its record names, at each checkpoint and whenever you are
blocked. Take direction from that session and no other. Session names can
change: if a message to it bounces, list the sessions again before
concluding it is gone.

Before each report, run `scripts/resolve-coordinator.sh <dispatcher_session>`
and send the report to the session its `coordinator=` line names: after a
takeover that is the run's newest member, which the brief never has to be
edited to name. When it prints no `coordinator=` line, report to the address
above.

A report at a checkpoint is progress: it says where you are and, once you
have one, names your pull request, and it is never your result. When your
invocation carries a request leg, your result still comes through that leg
when your entry point finishes; a checkpoint message doesn't stand in for it,
so keep going to the end.

On the message path only: your report step. When your entry point finishes,
run `scripts/render-result.sh --session <your session> --dispatcher
<dispatcher_session>`, with `--pr <url>` for each pull request you opened, and
put the block it prints in your final report, just before the `=== WORK IN
FLIGHT ===` block, sent to the session its `coordinator=` line names. That block is your
result; it carries your review round, and a link to the coordinator that
failed.

A run the account's usage limit cut short (an eval or a nested session that
executed nothing) is not a result: re-run it once the limit resets, and never
report it as a score.

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
  --brief <workspace-root>/.niwa/dispatch-briefs/<topic>.md --skill shirabe:<entry point> \
  --grant <authority> --parent-from <your instance root> \
  --model <model> --permission-mode <mode> --accept-session-messages
```

`--brief` and `--skill` let niwa put the brief's digest and the requested
skill on the worker's telemetry. niwa accepts them from 0.28.0; with an older
niwa, leave both off, since it refuses flags it doesn't know. `--grant` (one
per authority, none for a worker granted nothing) and `--parent-from` go on
only when `niwa dispatch --help` lists them, for the same reason. So do
`--model`, `--permission-mode` and `--accept-session-messages`
(`--accept-session-messages=false` for `false`), one for each key of the
input's `launch`; a flag the help doesn't list is left off with a line on
stderr naming it, and the worker gets niwa's default for it.

Record the holding under the dispatch topic you passed, with
`state-holding.sh`, before any other action. `scripts/dispatch-worker.sh`
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
