# Lead: How should the summary reach the user for background/dispatched sessions?

## Findings

### Headline: the niwa mesh no longer exists

The exploration context's "what we already know" is stale on a load-bearing point. The
mesh — MCP server, task-delegation substrate (`niwa_delegate`, `niwa_report_progress`,
`niwa_finish_task`, `.niwa/tasks/<task-id>/`), per-worktree daemon, and apply-pipeline
hook synthesis — was removed from niwa in full:

- `public/niwa/docs/prds/PRD-niwa-mesh-removal.md` (status: Done) — "Remove the
  non-functional mesh subsystem in full"; R3/R4 delete the MCP server and the
  task-delegation CLI cluster. `DESIGN-niwa-mesh-removal.md` sits in
  `docs/designs/current/`; the mesh designs (`DESIGN-mesh-session-lifecycle.md`,
  `DESIGN-cross-session-communication.md`, `DESIGN-coordinator-loop.md`, etc.) are in
  `docs/designs/archive/`.
- Zero Go files in `public/niwa/` reference `report_progress`/`finish_task`. There is
  no `internal/mesh`, `internal/mcp`, or task package under `public/niwa/internal/`.
- The `/niwa-mesh` skill referenced by the workspace `CLAUDE.overlay.md` does not exist
  in either workspace `.claude/` directory. The only root skill installed is
  `dispatch` (`/home/dangazineu/dev/niwaw/tsuku/.claude/skills/dispatch`, sourced from
  `public/niwa/internal/workspace/rootskills/dispatch/SKILL.md`).
- `PRD-mesh-session-lifecycle.md` is explicitly marked "Superseded"; only the
  git-worktree session model survived (as `niwa worktree`).

So channels (b) and (c) below are answered by absence: there is no
`niwa_report_progress` payload and no `niwa_finish_task` result schema to extend. Any
design that routes the summary through mesh tools would target dead code. The
workspace-root CLAUDE.md/overlay "Channels" section is documentation debt.

### (a) Agent View — Claude Code's surface, not niwa's

"Agent View" in niwa docs means Claude Code's own background-session dashboard — the
`claude agents` / `claude attach` UI. niwa does not render it and cannot change it:

- `PRD-instance-dispatch.md` R17: the dispatched session "SHALL be listable and
  attachable via Agent View (`claude agents` / `claude attach`)". Known Limitations
  and Out of Scope state that Agent-View-side capabilities depend on unshipped Claude
  Code features (upstream anthropics/claude-code#60975, #31940).
- niwa's contribution to what Agent View shows is exactly one thing: the session's
  display name. `dispatch.go` forwards the sanitized `--name` slug to the worker as
  `claude --bg --name <slug>` (`buildDispatchPassthrough`,
  `internal/cli/dispatch.go:413-428`), so the Agent View row carries a readable name.
- Per the round-1 finding, Claude Code's `claude agents` UI already has a PR column and
  clickable PR links in session results. That means Agent View is already the
  per-session dashboard where PR links belong — and it is fed by the session itself
  (final message / harness PR detection), not by anything niwa writes.

Conclusion for (a): Agent View needs no niwa-side change and cannot get one. It is
reached purely by convention: whatever the worker puts in its final assistant message
(and whatever PRs the harness detects) is what the user sees in the dashboard row and
result view.

### (d) The dispatch flow — what the user actually sees

`niwa dispatch` (`internal/cli/dispatch.go`) prints, at launch time
(`dispatch.go:286-290`):

```
Dispatched session <full-uuid>
  instance: <path>
  claude attach <short-id>
  claude logs <short-id>
  claude stop <short-id>
```

Default behavior attaches the terminal to the new session; `--detach` returns
immediately after the hints (the fan-out mode the `/dispatch` skill mandates).

When a detached worker finishes: **niwa pushes nothing.** There is no completion
notification, no SessionEnd hook at the workspace root (PRD R27: the root SessionEnd
hook does not fire for instance-rooted sessions), and no niwa command that reports
"worker X finished with result Y". `niwa list` (`internal/cli/list.go`) shows only
instance name/path/ephemeral — not session status, not label, not results. The user
discovers completion only through Claude Code surfaces: the Agent View row, `claude
logs <short-id>`, or attaching. The durable artifacts of a finished dispatch are:

1. Pushed git state — branches and PRs on the remotes (the instance is a fresh clone;
   anything unpushed dies with it).
2. The Claude Code session transcript/result (what Agent View and `claude logs` show),
   which persists until the user deletes the session.
3. Files written to the **workspace root** (same filesystem), e.g. the
   `.niwa/dispatch-briefs/<slug>.md` handoff files, which are never reaped.

So for a dispatched worker, "the summary reaching the user" reduces to: put the
standardized block (PRs + status + links) in the worker's **final assistant message**,
where Agent View's result view and PR column pick it up. That is the same convention
interactive sessions would follow — one convention, two surfaces.

### (e) A ledger file in the instance — written into a directory scheduled for deletion

The reclamation rule (`internal/cli/reap.go`, `internal/cli/job_state.go`): a mapped
ephemeral instance is force-destroyed (`destroyInstanceFunc`, whole directory) exactly
when its Claude Code job entry at `~/.claude/jobs/<session-id>/` is **gone** — the
proxy for the user deleting the session from Agent View. Liveness deliberately ignores
terminal state and idle TTLs ("delete-only" teardown, `reap.go:35-52`): a session that
finished its task keeps its job entry, so its instance survives and stays resumable.

Implications for an in-instance ledger:

- Nothing ever reads it. No niwa code reads any per-instance results file; no hook
  fires at the root on worker completion; the coordinator session has no reason to know
  the instance path unless it saved the dispatch output.
- Its lifetime is perverse: it survives while the session is listed in Agent View
  (when the user can already read the richer transcript) and is deleted at the exact
  moment the user tidies up — which is when a post-hoc "what did that worker ship?"
  question would arise.
- The workspace root is the durable alternative the codebase already demonstrates: the
  `/dispatch` skill has workers read their brief by absolute path from
  `<workspace-root>/.niwa/dispatch-briefs/<slug>.md`
  (`rootskills/dispatch/SKILL.md:45-53`). A symmetric results file (e.g.
  `<workspace-root>/.niwa/dispatch-results/<slug>.md`) would survive reap and be
  readable by the coordinator — but it is still pull-only; someone must look.

### Assessment against the exploration's three questions

- **Should the completion contract require a PR list?** There is no live completion
  contract to amend — `niwa_finish_task` is gone. The live contract is the `/dispatch`
  skill's brief convention (`rootskills/dispatch/SKILL.md`). The smallest change with
  real effect: the skill's step-1 brief template gains a mandatory closing requirement
  ("end your final message with the standardized summary block: PRs opened/updated with
  URL and status"), and step 4 ("Report back") tells the coordinator to relay the
  attach/logs hints as the place that block will appear. This is a one-file change in
  niwa's embedded root skill, convention-only, no Go change.
- **Should report_progress carry the summary at PR events?** N/A — the tool no longer
  exists. Mid-flight visibility for a dispatched worker is `claude attach`/`claude
  logs`/Agent View streaming (plus Claude Code Remote when
  `remote_control_on_dispatch = true`, `docs/guides/remote-control-on-dispatch.md`),
  all of which show whatever the worker says in its transcript. Emitting the summary
  block as a normal transcript message at PR events covers this for free.
- **Does Agent View need a change?** Not one niwa can make. The harness already grew a
  PR column; the convention's job is to make sure PR links reliably appear in the
  worker's messages/results so that column populates.

## Implications

- For background/dispatched sessions, the standardized summary has exactly one reliable
  push-adjacent surface: the session transcript, terminating in the final assistant
  message. Agent View (rows, results, PR column), `claude logs`, and Claude Code Remote
  are all views over it. The convention should therefore be defined once ("emit the
  summary block into the transcript at PR events and at completion") and it covers
  interactive statusline-less workers, detached workers, and remote monitoring
  simultaneously.
- Enforcement belongs in the instruction channels that are guaranteed delivered to a
  dispatched worker: the `/dispatch` brief (niwa's embedded root skill) and the shirabe
  workflow skills' completion steps. The SPIKE below shows skills can fail to load in a
  fresh instance, so the brief is the stronger of the two anchors; putting the
  requirement in both is cheap defense-in-depth.
- Any per-instance ledger is the wrong home. If a machine-readable record is wanted at
  all, it must live at the workspace root (dispatch-briefs pattern) or in pushed git
  state (the PR itself). Otherwise skip the ledger: the PRs are on GitHub and the
  summary is in the transcript.
- Design docs referencing the mesh channel list (workspace CLAUDE.overlay.md) must not
  be trusted; the exploration should record the mesh removal so later rounds don't
  re-propose `finish_task` schema changes.

## Surprises

- **The mesh is gone.** `PRD-niwa-mesh-removal.md` (Done) removed every tool this
  lead's questions (b) and (c) were about. The workspace root CLAUDE.md/overlay still
  documents the tools and a `/niwa-mesh` skill that is not installed anywhere —
  live documentation pointing at deleted infrastructure.
- **Reap is delete-only, not done-triggered.** `reap.go` reclaims only when the job
  entry disappears (user deletes the session), not when the session reaches `done`.
  Finished workers keep resumable instances indefinitely. This is friendlier than the
  PRD's original R28 wording suggests, but it also means in-instance artifacts die at
  user-cleanup time — the worst possible moment for an audit trail.
- **Dispatched workers have hand-run risk.** `docs/spikes/SPIKE-dispatched-worker-pr-template-gap.md`
  documents a real incident: a github-sourced plugin (shirabe) raced Claude Code's
  startup skill enumeration, so the worker couldn't invoke `/execute` and hand-ran the
  workflow, dropping the PR template. niwa now pre-warms plugins
  (`Applier.PrewarmDeclaredPlugins`), but the spike's lesson stands: a summary
  convention embedded only in a skill can be silently skipped by a dispatched worker;
  the brief file is the only instruction channel guaranteed to reach it.
- **An unstoppable orphan is possible.** `dispatch.go` (long help + step 10 comment):
  if session-id capture fails after launch, the instance is rolled back but the
  background worker keeps running unmapped — niwa never learned its id and cannot stop
  it. A rare case, but such a worker's summary would surface only in `claude list`/Agent
  View, reinforcing that the transcript is the one channel that never depends on niwa's
  bookkeeping succeeding.

## Open Questions

- Does Claude Code's Agent View PR column populate from harness-side detection of PR
  URLs anywhere in the transcript, or specifically from the final message/result? This
  determines whether the convention must say "final message" or merely "any message".
  (Harness behavior, not answerable from niwa source.)
- Should the coordinator's `/dispatch` step-4 report-back be extended to poll or check
  the worker later (e.g. a `claude logs` scrape convention), or is that over-engineering
  given Agent View already exists?
- Is a workspace-root `dispatch-results/` twin worth adopting, or does it duplicate
  what GitHub (the PR list on the branch) already records durably?
- Will the reap contract stay delete-only? The summary-surfacing design shouldn't
  depend on instance longevity either way, but a future done-triggered reap would
  further shorten any in-instance artifact's life.

## Summary

The mesh channels this lead asked about (`niwa_report_progress`, `niwa_finish_task`, task queues) no longer exist — PRD-niwa-mesh-removal (Done) deleted them, and the workspace CLAUDE.md still advertising them is stale — so there is no structured result payload to put a `prs: []` field into. For a dispatched worker the only reliable surface is its own session transcript: niwa pushes nothing at completion, `niwa list` shows only instance names, an in-instance ledger is force-deleted at reap (which fires when the user deletes the session in Agent View — exactly when they'd want to read it), and Agent View is Claude Code's dashboard, which niwa can only feed via the worker's messages (it already forwards `--name` for the row label, and the harness already grew a PR column). The smallest effective change is convention-only: require the standardized summary block (PR links + status) in the worker's transcript at PR events and in its final message, anchored in the `/dispatch` brief template (`public/niwa/internal/workspace/rootskills/dispatch/SKILL.md`) since the spike on the plugin-load race shows the brief is the only instruction channel guaranteed to reach a dispatched worker.
