# Maintaining the coordinate skill

Nothing loads this file at runtime. No state, script or reference reads or
links it, and a coordinator never needs it to run. The runtime rules live in
four places:

- `SKILL.md`, the entry every start loads at turn 0: the identity rules, the
  first steps and the opener call, the settings, the standing tick rules,
  Roles, Reporting and the glossary.
- The opener's stderr guidance (`scripts/coordinate-open.sh`, its text in
  `scripts/coordinate-open.wording.tsv`): a family's block prints when the
  opener reaches the output line that names its situation, such as a
  takeover, an import, a carry or a refusal.
- The template's states (`koto-templates/coordinate.md`): each state's
  directive and details carry the rules for what that state does, and come
  back on every arrival and through `koto status`.
- The references a state or the entry names, listed in
  `references/reference-files.tsv`.

This file holds what a maintainer needs instead: the background of the
record, where shipped behaviour departs from a design, what is left for
later, the known limitations, and how to change the skill.

## The Record

The record stores only what GitHub can't recompute: the holdings (including
workers with no pull request yet), deferrals, side effects in flight such as a
merge attempted and never confirmed, and the reasoning behind reversals.
Feature state is never stored; it is read from the roadmap and the pull
requests every time. When a roadmap feature lands, the skill writes it back:
`scripts/roadmap-status.sh` opens a pull request setting its Status to Done
and writing what landed on a `**Delivered:**` line (never on its
`**Outcome:**`, which is the promise, and in a public roadmap naming only
public pull requests; the script's `--outcome` flag carries that Delivered
text), which whoever merges roadmap changes merges, and the record holds it
as a side effect in flight so pick never offers the feature again meanwhile.
That write-back is a feature roadmap's; on a milestone roadmap a merge sets
nothing, and a verdict does.

At both scopes the record is the coordinator's own koto session on this
host: one key per section, written by its writers through one write core and
read through one reader. Nothing about it is on GitHub: no issue, no pull
request, nothing committed. A discipline rotation is its own session, with its
window and the reasoning it leaves the next rotation in its session
(`record/rotation`, `record/reasoning`), and the next rotation carries its
state. The workflow finds it, checks it, and confirms every change the
coordinator makes to it; the coordinator writes it only through the scripts
its states name. Its state is JSON, one key per section: `record/meta` with
the scope and the written time, the four sections, then Holds once the record
holds a merge, then the stored set a replacement continues from (Run,
Standing and Work, written only by `scripts/state-stored-set.sh`), then
Decisions once it holds a decision. `references/state-keys.md` has every key,
its shape and its one writer. A person reads the state through koto's session
view, `koto context get <session> <key>` over the coordinator's session;
nothing renders it as a page.

A coordinator's state lives in two places, both in its koto session: the
session's journal on this host between checkpoints, and the record's keys. It
keeps no tools directory, no snapshot of the state, no standing answers or
progress facts in a local file: what has to outlive the session goes in the
record.

## Verdicts

Two points of the shipped behaviour follow the milestone verdicts PRD where
its design says otherwise. A changes-needed
edit leaves Delivered unchanged, where the design appends the work checked
to it. And a verdict-owed row whose Who is `none`, because no holding named
the milestone, runs `check-verdict` without `--worker`, so no checker name is
refused on that run, where the design always passes the worker's topic.

## What This Version Leaves for Later

Both features this version named as later work have landed: the dispatch
path runs dispatch, wait and teardown through scripts, and reconcile's
re-check is the `reconcile_pass` state. What is still open is below.

Verdicts leave two things for later. How a separate reviewing session, or
a sort before review, consumes the verdicts on a record has its own owner:
this version makes verdicts exist and readable, and nothing reads them but
the scripts above. And nothing retires a milestone roadmap once every
milestone is verified. The cascade no longer deletes it, so how a finished
milestone roadmap ends is left to the roadmap's own lifecycle.

## Known Limitations

- **Which pull requests a worker owns (shirabe#395, fixed for `/execute` by
  shirabe#421).** The workflow relies on each worker's run identifying only its
  own pull requests. `/execute` now marks every pull request it opens with its
  run and looks up only its own; `/scope`'s pull requests and ones opened before
  that fix still fall back to author login and branch name, and every worker a
  coordinator dispatches shares one login. The coordinator's own reads go by pull
  request number and dispatch topic. For reconcile, a pull request that
  appeared on a holding's branch since the record is reported as appeared, not
  adopted, so a sibling's pull request on a shared branch name shows up as one
  to look at rather than as the holding's.
- **The coordinator's record has no merge order (shirabe#396, fixed by shirabe#412).** When a worker runs a
  coordinated PLAN, `/execute` renders that PLAN's merge order into its
  coordination pull request's merge-order block from the `waits_on` graph, so
  a merge order survives the PLAN. The merge gate never reads the block, and
  the coordinator's own record has no merge-order section: the order it hands
  the human still comes from its reading of dependencies.
- **Pull request bodies that aren't scoped (shirabe#398).** A worker's pull request body
  can describe more than the pull request carries. The verify step's file-list
  read is the defence, at one more read per report. Reconcile makes the same
  file-list read only for a holding marked scoping ahead, to flag one whose
  pull request changes paths outside `docs/`.
- **Wakes are local to one machine (tsukumogami/koto#250, fixed in koto
  0.14.0).** koto records a wake when a leg a session requested resolves, and
  the wait state's leg watch (`koto request watch` with a two-hour bound) is
  how the coordinator hears it; a worker on another machine reports by
  message. A reconcile pass left pending (a worker's listing re-read still 30
  seconds away) waits for the next tick a message or the watch brings.
- **`koto next --to` past a check (koto#251, fixed in koto 0.14.0).** koto
  0.14.0 and later refuse a directed transition past a failing non-overridable
  gate, so no check can be skipped that way. The seal stays as defence in depth:
  each check's verdict is sealed to the visit that produced it, and every write
  script and later reader scans the session log and refuses after any directed
  transition. The teardown inventory is sealed the same way, and the destroy
  step's reader refuses after a directed entry.
- **Checks run in the coordinator's own environment (koto#261).** koto runs
  every action and gate with the environment of the `koto next` call that
  triggered it. A `PATH` entry can stand in for `gh`, `jq` or `git`, and so can an
  exported shell function where `/bin/sh` is bash (not dash). The same goes for a
  shim put first on `PATH` by accident, which a check then reads silently. The
  checks hold against a wrong submitted value or a skipped step. They don't hold
  against a coordinator that rewrites its own tools, or its files, which no fix
  to the environment covers. The template's states carry the runtime form of
  this caveat where a coordinator acts on it.
- **One machine and one HOME (no tracking issue: a property of koto's per-user store).** koto's request and session stores
  are per-user and machine-wide under the koto home, so a coordinator and the
  workers that answer its legs share one machine and one HOME, and a worker on
  another host reports by message. Session names are machine-wide too: a second
  live worker on a topic already held collides with the first (koto refuses the
  attach as `origin_mismatch` and records nothing on a leg already bound), so the
  dispatch check refuses a topic a Holdings row already names.
- **A resumed or imported run's /workflows location stays where it was
  (tsukumogami/koto#361).** koto stores a session's /workflows location once, in
  its reserved `workflows/publish-location` key, on the session's first commit,
  and only writes it when absent. A run resumed under a new Claude session, or
  imported on another host, keeps publishing to the location of the session that
  opened it. The opener writes none of koto's keys and sets no koto variable to
  move it. The template's states carry the runtime form of this caveat where a
  coordinator acts on it.
- **A run moves plugin roots only when its template lets it.** A run records
  the plugin root it was opened with, every check it runs is a script under
  that root, and provenance accepts only a run whose root, as koto applies it
  now, is this plugin's. A run opened from a template that declares
  `PLUGIN_ROOT` rebindable is re-attached with this plugin's root when a start
  or an import finds it under another (`rebound=` in the output), so a plugin
  upgrade or another checkout resumes it. A run opened from an earlier
  template can't be rebound: the import stops at `refused=session-provenance`
  and a start carries its record into a new run, as before.
- **Which template a run may continue on is the compat table's call.** The
  table beside the template (`koto-templates/coordinate.compat.json`) lists
  every compiled template this plugin's scripts can drive at the table's
  compat number; a run compiled from one of them is resumed or imported
  whatever its directive text. Any other is carried by a start, and an import
  of one is refused as `template-incompatible`, naming both compat numbers.
  CI (`scripts/check-template-compat.sh`) fails a change that moves the
  template's structure without raising the compat number, or changes a script
  a gate reaches without recording the new digest. A script change that alters
  what a run does also changes how the template invokes it, since runs are
  told apart by structure; raising the number alone is refused.
- **One topic per worker.** A unit dispatched again after a failure takes a new
  topic: the dispatch script refuses a topic whose session is still live. A
  worker on the message path that went quiet past the second silence, whose
  unit is chosen to dispatch again, is marked stranded first
  (`state-holding.sh --strand <topic>`, refused for a leg-bound worker), and
  the new brief input names it in `continues`: the new topic's brief names
  that holding's branch and last pushed head, and only its row is retired
  once the new worker is dispatched, so a late report from the old topic
  matches no holding. A dispatch without `continues` takes no stranded row,
  even one on the same unit. A `dispatch-failed` row whose unit has
  moved on, such as one carried into a continued run, is retired the same way
  (`state-holding.sh --topic <topic> --retire`), which refuses while niwa lists
  a session or an unfinished Claude job carries the topic and leaves an entry
  when the row goes.
- **A worker launched outside the dispatch script can't be adopted.** The
  dispatch script refuses a topic whose session is already live, so a worker
  started by hand never gets a holding through it. Stop that worker's session
  and dispatch the unit again through the script, under a new topic.
- **Session names aren't predictable (niwa#325).** niwa appends a random token to
  the name it's given and doesn't report the launched session in a
  machine-readable form, so the dispatch script reads the name from the dispatch
  output or `niwa list --json` and matches it by its whole shape. The name is
  used to message the worker and is never recorded.
- **No workspace root from niwa (niwa#326).** The scripts find the workspace root
  by walking up from the working directory, guarded against a repository's own
  workspace configuration; a coordinator started outside the workspace can't
  dispatch.
- **Destroy refuses squash-merged branches (niwa#322).** `niwa destroy` treats a
  branch whose pull request was squash-merged as unmerged, so the destroy step
  needs `--force`, passed only after the sealed inventory proved every
  repository durable.
- **A verdict check proves the entry, not the looking.** `milestone.sh
  check-verdict` proves a verdict's lines are well formed and agree with
  each other and with the Evidence; whether the checker ran each clause is
  on the coordinator or the person who gave it. Its `--worker` refusal
  catches a checker that names the holding worker by mistake, not a forger
  holding the coordinator's session, and a verdict-owed row with Who `none`
  skips it.
- **One roadmap edit at a time.** A verdict's edit and a reopen each wait
  while any roadmap pull request is pending, so verdicts on a busy roadmap
  queue up, and a milestone stays verdict-owed until its turn.
- **A reopened milestone's dependents keep running.** A dependent that
  already holds a worker reads blocked once the reopen lands, but nothing
  stops its worker: `--reopen` names it and the coordinator decides.
- **Verdicts have one reader, and milestone roadmaps don't retire.** No
  reviewing session consumes the verdicts yet, and a milestone roadmap whose
  every milestone is verified stays where it is (see What This Version
  Leaves for Later).
- **A failure after the record closed.** A failure against a milestone
  whose roadmap's record is closed has no step here: edit the roadmap by
  hand, or start a coordinator on the roadmap again, whose new record takes
  it.
- **Two Evidence readers.** `shirabe validate` and `milestone.sh` each read
  a milestone's Evidence, so a change to the format has to touch both.
- **Where the next checks attach.** Three checks reconcile doesn't make yet
  have a place to go. Liveness (whether a found worker is still making
  progress, not only present) belongs in the host re-check, beside the listing
  read, as a second fact on the same holding. The double-held check (one pull
  request, branch or worker claimed by two holdings, or by another
  coordinator's record) belongs where the pass assembles facts from the parsed
  record, before the report, so it lands under "Changed since then". Moving the
  reads off the coordinator's host (externalised load) belongs at the pass's
  single launch point for a re-check, which already runs each read as its own
  process with its own deadline.

## Changing This Skill

Invented process and general practice belong in the skill. A rule whose justification
would disappear once a filed defect is fixed does not: state the invariant the
defect breaks, and keep the defect filed. Check each new rule against that test
before adding it.

Two tests hold what the skill costs a session. `scripts/entry-ceiling_test.sh`
holds the rendered SKILL.md (frontmatter dropped, includes counted in full)
under the row in `scripts/entry-ceiling.tsv`, read at the merge base, with a
fixed cap of 8,400 bytes over every row, so a change can lower its row but
not raise it. `scripts/directive-ceiling_engine_test.sh` fails a change that
grows the `wait` directive, or any other state with a row, past its ceiling at
the merge base (`scripts/directive-ceiling.tsv`).

New situational text is never appended to SKILL.md. Text acted on before the
first tick, or where no run exists, goes to the opener's stderr, as a block in
`scripts/coordinate-open.wording.tsv` keyed to the output line that names the
situation. Text acted on after that goes to the template state where it's
acted on. Within the template, new text goes in a script or gate first, then
the state its event routes to, then a reference file with a one-line cue, and
into `wait` only by replacing or tightening text already there; nothing goes
into the silent action states or the `done*` states. A new reference file gets
a row in `references/reference-files.tsv`, so every start digests it into the
run's `rules` rows and `--rules` can answer from it. Maintainer text, like
everything in this file, goes here and nowhere a session loads.
