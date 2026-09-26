---
schema: plan/v1
status: Active
execution_mode: single-pr
tracking_level: none
split_mode_source: none
upstream: docs/designs/DESIGN-coordinate-dispatch-path.md
milestone: "Coordinate dispatch path"
issue_count: 6
---

# PLAN: coordinate-dispatch-path

## Status

Active

Authored at Active because this PLAN files no issues. Implementation starts
only once the record feature's template, `skills/coordinate/koto-templates/coordinate.md`,
is on the default branch and carries the seams listed in the DESIGN's "The
interface with the record feature"; the fifth outline fills that template's
states and can't be written before it exists.

## Scope Summary

Implement the dispatch path of the `coordinate` skill as designed in
`docs/designs/DESIGN-coordinate-dispatch-path.md`: the brief renderer, the
dispatch script and its holding gate, the wait path's scripts, the teardown
inventory, the template states that call them, and the skill text and evals,
in one pull request.

## Decomposition Strategy

**Horizontal, in one pull request.** The scripts are independent units with
stable interfaces the DESIGN fixes (their arguments, exit codes, and the
context keys they read and write), so each is built and tested on its own
before the template states that call them. The template outline comes after
the scripts because a state's gate can only be written against a script that
exists, and the skill text and evals come last because they describe and test
the finished states.

One pull request, under the repository's default `consolidated` delivery
preference. No split branch fires: the pieces land nothing useful alone (a
renderer with no dispatch, a gate with no state), and nothing forces an order
across pull requests. The dependency on the record feature's template is on
work outside this PLAN, and it gates when this pull request starts, not how
it's split.

## Issue Outlines

### Issue 1: feat(coordinate): render worker briefs from structured input

**Goal**: Add `dispatch-common.sh` (workspace-root lookup, topic slugging, the
entry-point table reader), `render-brief.sh`, and
`skills/coordinate/references/entry-points.tsv`, with tests, so a brief is
rendered from a JSON input and refused when incomplete.

**Acceptance Criteria**:
- [ ] Given a complete brief input, `render-brief.sh` writes
  `<workspace-root>/.niwa/dispatch-briefs/<topic>.md` whose sections, in the
  order of `references/brief-template.md`, each contain the input values given
  for them, including the dispatcher as the only source of direction, one line
  per surface's discipline coordinator with a copy to the dispatcher, the
  conventions pointer, the keep-alive note, and each standing rule verbatim.
- [ ] It exits non-zero and writes no file when any of topic, repo,
  entry_point, entry_args, run_mode, phase, authority, goal, checkpoints,
  acceptance or dispatcher_session is missing or empty; when a checkpoint
  contains "approval", "approve" or "wait for" (case-insensitive); when a
  `read_first` entry isn't a repository path, an issue or pull request
  reference, or an `https://` URL; when the topic fails
  `^[a-z0-9][a-z0-9-]*$`; and when a flag in `entry_args` isn't in that entry
  point's allowed set.
- [ ] The workspace-root lookup takes the parent of the nearest ancestor
  holding `.niwa/instance.json` and requires `.niwa/workspace.toml` there, uses
  the working directory only when no instance marker exists, and a test with a
  clone carrying its own `.niwa/workspace.toml` shows the clone's marker is
  never used.
- [ ] Neither the rendered brief nor any output names a session id, an
  instance path or a job id.
- [ ] `entry-points.tsv` covers every entry point the DESIGN's brief input
  admits: it lists `scope` and `execute` with their leg names,
  admitted templates and pinned inputs, and `deliver`, `work-on`, `explore`,
  `decision` and `coordinate` with `-` for the leg, each with its allowed
  flags.
- [ ] `render-brief_test.sh` and `dispatch-common_test.sh` pass and are run by
  the repository's script-test CI.

**Dependencies**: None

**Type**: code
**Files**: `skills/coordinate/scripts/dispatch-common.sh`, `skills/coordinate/scripts/render-brief.sh`, `skills/coordinate/references/entry-points.tsv`

### Issue 2: feat(coordinate): dispatch a worker and record its holding first

**Goal**: Add `dispatch-worker.sh` (with `--rebrief`) and
`holding-recorded.sh`, with tests against stubs, and declare `niwa` as a tool
the skill needs.

**Acceptance Criteria**:
- [ ] Against a stub `niwa`, a stub `koto request` and a stub record writer
  and reader that log their calls to one file, a dispatch writes the holding
  (`dispatching`, topic, repository, entry point, run mode, phase, date,
  return path, "none yet") before calling `niwa dispatch`, calls it once with
  `--name <topic>` and `--detach` from the workspace root, then rewrites the
  holding as `dispatched`.
- [ ] The prompt the stub `niwa` receives carries the authority sentence, the
  repository, the entry point's invocation with its arguments, the stop
  checkpoint, and the brief's path, as one argument.
- [ ] The logged holding write contains no session id, instance path or job
  id, including the session name niwa printed, which only reaches stdout.
- [ ] For an entry point with a leg, it creates a one-leg request whose role
  is the leg name and whose inputs pin the table's keys, records
  `<request-id>:<leg>` as the return path, and puts `--koto-leg=<id>:<leg>` in
  the prompt; for one without, the return path is `message` and the prompt
  carries no `--koto-leg`.
- [ ] A second run for a `dispatched` topic calls `niwa dispatch` zero times,
  writes nothing, prints `already-dispatched`, and exits 0.
- [ ] A run finding a `dispatching` row with the topic's session in the stub
  listing confirms it as `dispatched` without launching; with no session, it
  launches once reusing the recorded request.
- [ ] A failing stub `niwa` whose listing then shows no session leaves the row
  `dispatch-failed`, abandons the request, and exits 4; one whose listing
  shows the session confirms `dispatched`; one whose listing can't be read
  leaves `dispatching` and exits 6.
- [ ] Two concurrent runs for one topic launch once (the per-topic lock); a
  live session named `api_v2-1a2b3c4d` doesn't match topic `api`, and a live
  session named `api-1a2b3c4d` makes a run for `api` exit 5 before launching.
- [ ] A `dispatch_topic` that differs from the brief input's topic exits 2
  with nothing written.
- [ ] `--rebrief` for a held topic takes repository, entry point and flags from
  the holding row, re-renders the brief, updates the row's date, and calls
  `niwa dispatch` zero times.
- [ ] `holding-recorded.sh` exits 0, 1, 3, 4 and 2 for a `dispatched` row, no
  row, a `dispatch-failed` row, a `dispatching` row and an unreadable record,
  reading the record through the reader and nothing else.
- [ ] `skills/coordinate/requires.tsv` declares `niwa`,
  `scripts/lib/tool-routes.tsv` carries its tsuku route, and the skill
  preflight passes with niwa installed and names the route when it isn't.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `skills/coordinate/scripts/dispatch-worker.sh`, `skills/coordinate/scripts/holding-recorded.sh`, `skills/coordinate/requires.tsv`, `scripts/lib/tool-routes.tsv`

### Issue 3: feat(coordinate): pick the wait target and check a report's path

**Goal**: Add `wait-target.sh` and `report-source.sh`, with tests, for the
wait path's actions and gate.

**Acceptance Criteria**:
- [ ] `wait-target.sh select`, over stub holdings and stub `koto request get`
  output, writes `wait_target` and prints the request id of a resolved leg when
  one exists, else of the oldest open leg, else prints `none`; it never prints
  nothing.
- [ ] `wait-target.sh leg` prints the leg name from `wait_target` and writes
  `report_topic` from it.
- [ ] `report-source.sh` exits 0 for a leg report, and for a message report
  whose topic's holding has return path `message`; it exits non-zero for a
  message report whose topic's holding is bound to a leg, and for a topic with
  no holding.
- [ ] `wait-target_test.sh` and `report-source_test.sh` pass.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `skills/coordinate/scripts/wait-target.sh`, `skills/coordinate/scripts/report-source.sh`

### Issue 4: feat(coordinate): inventory a worker's instance before teardown

**Goal**: Add `teardown-inventory.sh`, with tests over fixture repositories
built in the test, giving a per-repository durability verdict proven by
content.

**Acceptance Criteria**:
- [ ] Over fixture repositories, it reports `unique` for an uncommitted
  change, an untracked file, a stash entry, a worktree on a detached HEAD with
  an unpushed commit, a branch whose remote branch was deleted without
  merging, and an unpushed branch whose changed files differ from its target.
- [ ] It reports `durable (vs merge <sha>)` for a squash-merged branch whose
  changed files match the merge commit, including when the default branch
  later changed those files, and `durable (vs default <branch>)` for an
  unpushed branch with no merged pull request whose changed files match the
  default branch.
- [ ] It exits 0 when all repositories are durable, 1 when any is unique, and
  2 for a submodule, a bare repository or an unreadable repository, never
  reporting those durable.
- [ ] Every path it prints is relative to the instance.
- [ ] A test shows it writes nothing to any fixture repository but
  remote-tracking refs, and it calls no destroy, stop or delete command.
- [ ] `--seal` stores the verdict in the session's context through the record
  feature's seal helper and prints `sealed:<visit-seq>:<sha256>` of it; a
  test shows a verdict edited after sealing fails the helper's check.
- [ ] Each repository's fetch runs under its own deadline, and a fetch that
  misses it makes that repository an error, so a whole run stays within
  koto's 30-second action limit on the test fixtures.
- [ ] `teardown-inventory_test.sh` passes.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `skills/coordinate/scripts/teardown-inventory.sh`

### Issue 5: feat(coordinate): fill the dispatch and wait states and add the teardown states

**Goal**: In the record feature's `skills/coordinate/koto-templates/coordinate.md`,
fill `dispatch` and `wait` and add `wait_leg`, `take_report`,
`classify_report`, `rebrief`, `quiesce`, `teardown`, `promote` and `destroy`, with their
gates, captures and context assignments as the DESIGN's state table gives
them, and update the mermaid companion.

**Acceptance Criteria**:
- [ ] The template compiles, and every template check the repository's CI
  runs passes (templates, directives, freshness, interpolation, decider
  declarations, init sites, entry floor).
- [ ] `holding_recorded`, `leg_target`, `leg_result`, `report_present`,
  `report_source_ok` and `inventory_durable` are declared
  `overridable: false`, and `koto overrides record` can't unblock any of them.
- [ ] A session in `dispatch` whose record has no holding for
  `dispatch_topic` doesn't advance, even with a context key claiming the
  holding exists.
- [ ] On a leg-bound holding, a promoted resolved leg moves `wait_leg` to
  `take_report` with `worker_report` holding the gate's status, final state,
  outcome, step, reason and pull request; an explicit or refused result, an
  abandoned leg and a missing leg each go to the surface step; an open leg
  holds the state until `rescan` or `report_from`.
- [ ] On the message path, `take_report` doesn't advance while
  `worker_report` is absent or whitespace, and advances once it holds the
  report; a message report for a leg-bound topic returns to `wait`.
- [ ] `report_class` declares a decider with every answer `shadow`, the escape
  `unclear`, and the one input `worker_report` gated by `report_present`; the
  coordinator's submitted answer routes `done` to `verify`, `needs_fix` to
  `rebrief` and `blocked` to the surface step.
- [ ] `worker_report` and `report_topic` are cleared on every edge into
  `wait` and on no edge into `take_report`; `dispatch_topic` is read, never
  written, by these states.
- [ ] `rebrief` goes to `wait` on `sent`, clearing `worker_report` and
  `report_topic`, and to `pick` on `worker_gone`; `quiesce` goes to
  `teardown` on `stopped` and nowhere else.
- [ ] `teardown` is reachable only through `quiesce` or `promote`, has no
  `accepts` block, runs the sealed inventory as a non-polling action, and
  moves to `destroy` only when the seal checks and the verdict is durable.
- [ ] `destroy`'s directive has the coordinator read the verdict through the
  seal-checking reader first, and a session moved into `destroy` with `koto
  next --to` is refused by that reader and routed to the surface step; the
  directive names one instance and no form that takes no target.
- [ ] Each directive names the script it has the coordinator run, and the
  wait directive says to tick on each message or notification and never
  poll; any background wait it names carries a deadline.

**Dependencies**: Blocked by <<ISSUE:2>>, <<ISSUE:3>>, <<ISSUE:4>>

**Type**: code
**Files**: `skills/coordinate/koto-templates/coordinate.md`, `skills/coordinate/koto-templates/coordinate.mermaid.md`

### Issue 6: docs(coordinate): skill text, known limitations and evals for the dispatch path

**Goal**: Point the skill's text at the new states and scripts, name the
known limitations, and add evals for the three scenarios the PRD requires.

**Acceptance Criteria**:
- [ ] `skills/coordinate/SKILL.md` names the dispatch, wait and teardown
  states' scripts where the thin contract points at step guidance, and its
  Known Limitations names shirabe #395, #396, #398 and #401, koto#250 and
  niwa#322, koto#251 (the directed-transition gate skip, with the seal helper
  as its detection), and the one-topic-per-worker
  and unpredictable-session-name constraints, each with its cost today.
- [ ] `references/brief-template.md` says the brief is rendered by
  `render-brief.sh` and shows the input it takes.
- [ ] `evals/evals.json` adds scenarios for a brief rendered with both
  channels (asserting both channels and the dispatcher as the only source of
  direction), a dispatch refused to leave the state without a holding
  (asserting the gate blocked), and a report classified in shadow (asserting
  the coordinator's answer routed and the shadow suggestion was recorded);
  each fails against the prose-only skill, and every existing scenario still
  passes.
- [ ] None of the files this PLAN adds or changes names a path under the
  workflow scratch directory, a private repository, path or issue.

**Dependencies**: Blocked by <<ISSUE:5>>

**Type**: docs
**Files**: `skills/coordinate/SKILL.md`, `skills/coordinate/references/brief-template.md`, `skills/coordinate/evals/evals.json`

## Implementation Sequence

**Critical path**: Issue 1, then Issue 2, then Issue 5, then Issue 6.

**Parallel after Issue 1**: Issues 2, 3 and 4 touch disjoint scripts and can be
built in any order once the shared helpers exist.

**External gate**: Issue 5 can't start until the record feature's template is
on the default branch with the seams the DESIGN lists; Issues 1 to 4 can be
built before it.
