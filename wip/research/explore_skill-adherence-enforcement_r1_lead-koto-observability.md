# Lead: What guarantees does koto provide, and is "a koto session exists for this plan" observable from outside the agent?

Everything below marked **[confirmed]** was read from source or reproduced against
live state on this machine. **[inferred]** means I reasoned from confirmed facts
without a direct test.

## Findings

### 1. What koto actually is — and the one thing it is not

koto is a **state machine over files**. It is not a supervisor, not a daemon, and
not a process manager. `koto next` reads a state file, evaluates gates, appends
events, prints a directive, and exits. The *agent* is the executor.

This is decisive, and it is confirmed in source. The substrate-spawn trait that
would actually launch a child agent is a logging stub:

`public/koto/src/engine/respawn.rs:165-180`
```rust
pub struct LoggingRespawner;
impl SubstrateRespawner for LoggingRespawner {
    fn respawn(&self, request: &RespawnRequest) -> Result<(), EngineError> {
        eprintln!("info: SubstrateRespawner stub invoked for session '{}' ... \
                   concrete respawn-delivery primitive not yet wired", ...);
        Ok(())
    }
}
```
The doc comment on the default names the reason: "Default `SubstrateRespawner`
used by `handle_next` until a concrete substrate implementation (Claude Code
agent-membership poke, bunki BK2 hosted respawn) ships." **[confirmed]**

Same story for claims: `src/engine/claim.rs` is a `claim.lock` sidecar holding
`{coord_id, claimed_at}` written voluntarily by a coordinator. It binds a *logical*
coordinator id, not a PID, not a process tree, not an agent identity. **[confirmed]**

So the concrete guarantees a koto-driven execution provides over a hand-rolled loop
are all **bookkeeping** guarantees, not **enforcement** guarantees:

| Guarantee | Real? | Mechanism |
|---|---|---|
| Ordered state machine | yes | template transitions; illegal transitions rejected |
| Template integrity | yes | SHA-256 locked at `init`; `next` fails if the compiled template changes |
| Atomic, replayable audit log | yes | append-only JSONL, fsync, `O_APPEND` ≤ 4 KiB atomic appends |
| Dependency DAG over tasks | yes | `materialize_children` + `waits_on` + `children-complete` gate |
| Command gates | yes | koto itself runs the shell test and records the exit code |
| Recoverability / rewind | yes | event-log replay, `koto rewind` |
| **Per-issue spawn** | **no** | koto records a child session; the *agent* must go run it |
| **Review gates / CI monitoring / PR finalization** | **no** | these are directive *text* in the template; koto never verifies the work happened |

The state machine guarantees that *evidence was submitted in the right order*. It
guarantees nothing about whether the evidence is true. An agent can drive the whole
loop submitting fabricated evidence and koto will happily record a clean run. What
koto buys is that the run is **recorded** — and the record is what makes it
observable.

### 2. Where state lives

Four locations, all local files, all world-readable by the user. **[confirmed]**

**(a) `~/.koto/sessions/<session-id>/` — live session state.**

Current layout is **flat**, one dir per session id, *not* namespaced by repo.
The older `~/.koto/sessions/<repo-id>/<name>/` layout is legacy —
`src/session/local.rs:37` says "Sessions from the old per-repo layout
(`~/.koto/sessions/<repo-id>/`)" are migrated. On this machine both exist
(1210 dirs: hex-named legacy ones from March/April, flat named ones since).

Real layout from a real run:
```
~/.koto/sessions/execute-vale-adoption/
├── koto-execute-vale-adoption.state.jsonl
└── ctx/
    ├── manifest.json
    ├── home_pr            ← "269"
    ├── settled_branch     ← "docs/vale-adoption-scope"
    └── workflows/publish-location
```

The state file's first line is the header. This is the real thing, verbatim:
```json
{"schema_version":1,"workflow":"execute-vale-adoption","template_hash":"ef4bb04f19bfaf8e80b050bde8feb0d16a1cd2c3b138548c129ce58cb6452948","created_at":"2026-08-13T22:08:02.631Z","template_source_dir":"/home/dgazineu/.claude/plugins/cache/shirabe/shirabe/0.16.1-dev/skills/execute/koto-templates","session_id":"01fddf49-fe9f-4461-bf48-7ddcc7a5ff34","template_name":"execute","dispatch_epoch":0}
```
and the first events:
```json
{"seq":1,...,"type":"workflow_initialized","payload":{"template_path":"/home/dgazineu/.cache/koto/ef4bb04f....json","variables":{"PLAN_DOC":"docs/plans/PLAN-vale-adoption.md","PAUSE_BEFORE_FINALIZE":"false"}}}
{"seq":2,...,"type":"transitioned","payload":{"from":null,"to":"orchestrator_setup","condition_type":"auto"}}
{"seq":4,...,"type":"context_added","payload":{"key":"settled_branch","hash":"229e...","size":25}}
{"seq":5,...,"type":"context_added","payload":{"key":"home_pr","hash":"317b...","size":4}}
```

**The header carries `template_name`, `template_source_dir` (which names the
shirabe plugin and its version), and — in `workflow_initialized` — the exact
`PLAN_DOC` path.** That is a complete provenance record: *which skill, which
version, which plan.* **[confirmed]**

A child session's header adds the parent link:
```json
{"schema_version":1,"workflow":"execute-calendar-cli-only.o-the-week-to-window-helper","template_hash":"9f03...","created_at":"2026-08-13T21:37:44.871Z","parent_workflow":"execute-calendar-cli-only","template_source_dir":".../shirabe/0.15.1-dev/skills/execute/koto-templates/../../work-on/koto-templates","session_id":"bb804b4e-...","template_name":"work-on","dispatch_epoch":0}
```
Children are named `<parent>.o-<task-slug>`, so they are also prefix-discoverable
without opening a file. **[confirmed]**

**(b) `~/.koto/_terminal_index.jsonl` — workspace-wide terminal index.**
Append-only, one line per terminal transition. Real tail:
```json
{"session_id":"issue_303","terminal_at":"2026-08-15T18:56:15.820Z","header_mtime_ns":1786820175811366677,"terminal_state":"completed","has_result":true}
```
Only four fields (`src/engine/terminal_index.rs:70-97`). **No repo, no plan, no
template.** Session *name* is the only join key. **[confirmed]**

**(c) `~/.koto/coordinators/<id>/scan_cursor.toml`** — scheduler bookkeeping only.

**(d) `~/.claude/projects/<encoded-cwd>/<claude-session-id>/workflows/koto-<uuid>.json`
— the `/workflows` surface. This is the important one; see §3.**

Cloud sync to S3/R2 exists but defaults off (`[session] backend = "local"` in the
resolved config on this machine). **[confirmed]**

### 3. The load-bearing discovery: koto stamps the Claude Code session

`src/workflows_surface/materialize.rs` is called from `LocalBackend::append_event`
— "the single low-level commit funnel every state mutation passes through — so it
fires uniformly for `koto next`, directed `--to`, `koto rewind`, and error/limit
exits without instrumenting individual commands." **[confirmed]**

It resolves a target directory by self-discovery:
```rust
const CLAUDE_SESSION_ID_ENV: &str = "CLAUDE_CODE_SESSION_ID";   // line 39
let session_id = std::env::var(CLAUDE_SESSION_ID_ENV).ok()?;    // line 268
let projects = Path::new(&home).join(".claude").join("projects");
let project_dir = find_session_project_dir(&projects, session_id)?;  // dir holding <sid>.jsonl
```
and writes `<projectDir>/<sessionId>/workflows/koto-<koto-uuid>.json`. Default on
(`workflows.native = true`, confirmed in the resolved config here).

The file it writes, verbatim (tail):
```json
  "koto": {
    "sessionId": "01fddf49-fe9f-4461-bf48-7ddcc7a5ff34",
    "workflow": "execute-vale-adoption",
    "currentState": "orchestrator_setup",
    "contractVersion": 2
  }
}
```
with `"name": "execute · orchestrator_setup"` and `"status": "running"` at the top,
plus a phase list rendered from the template.

Three properties make this the answer to the lead:

1. **It is keyed by the Claude Code session id** — the same value a PreToolUse hook
   receives in its input JSON. The join needs no agent cooperation and no koto
   invocation. **[confirmed for the file; the hook-input field name is [inferred]
   from the documented hook contract — verify against the niwa gate already
   shipping.]**
2. **It is repo-scoped by construction** — the encoded project dir is the cwd path.
   `~/.koto/` is not repo-scoped at all, so this is the *only* place koto state is
   bound to a repository.
3. **It survives session cleanup.** koto deletes `~/.koto/sessions/<id>/` on
   reaching a terminal state (`--no-cleanup` opts out). The workflows JSON is not
   deleted; it renders `"status": "completed"`. Verified empirically: session
   `issue_2474` reached `done`, `~/.koto/sessions/issue_2474/` does not exist, and
   `.../fe5bd5e5-.../workflows/koto-29bfa055-....json` still reads
   `"currentState": "done", "status": "completed"`. **[confirmed]**

65 such records exist on this machine.

**Caveat found empirically:** one Claude Code session id can appear under more than
one encoded project dir (cwd changed mid-session — e.g. on worktree entry), and the
copies disagree. For `fe5bd5e5-...` the worktree project dir holds a stale
`setup_issue_backed / blocked` copy (mtime 1785767054) while the non-worktree dir
holds the final `done / completed` copy (mtime 1785770963). A checker must scan all
project dirs for that session id and take the freshest by mtime.

### 4. Runnable checks

**Is there an active koto session for this plan right now?**
```bash
# Live sessions only, TSV: name, state, elapsed, status, description, template, ..., liveness
koto dashboard --once
```
Real output on this machine:
```
execute-calendar-cli-only.o-the-week-to-window-helper	entry	45h32m	running		work-on	45h32m	needs-you-stalled
execute-calendar-cli-only	spawn_and_await	45h38m	blocked	Plan orchestrator template...	execute	45h32m	needs-you-blocked
execute-vale-adoption	orchestrator_setup	45h2m	running	Plan orchestrator template...	execute	45h1m	needs-you-stalled
```
Nine live sessions out of 1210 dirs — it filters to non-terminal.

Plan-exact, no CLI at all (survives a broken/absent `koto` binary):
```bash
PLAN=docs/plans/PLAN-vale-adoption.md
grep -l "\"PLAN_DOC\":\"$PLAN\"" ~/.koto/sessions/*/koto-*.state.jsonl
```

Session state without noise (`koto status` prints migration warnings to stderr —
always redirect):
```bash
koto status execute-vale-adoption 2>/dev/null
# {"current_state":"orchestrator_setup","is_terminal":false,"name":"execute-vale-adoption",
#  "template_hash":"ef4bb04f...","template_path":"/home/dgazineu/.cache/koto/ef4bb04f....json"}
```

Did children actually get spawned (the thing the second incident skipped)?
```bash
S=execute-vale-adoption
ls -d ~/.koto/sessions/"$S".o-* 2>/dev/null            # one dir per child
grep -o '"type":"scheduler_ran".*' ~/.koto/sessions/"$S"/koto-"$S".state.jsonl
```
Real `scheduler_ran` payload from a run that did fan out:
```json
"type":"scheduler_ran","payload":{"state":"spawn_and_await","tick_summary":{"spawned_count":4,"errored_count":0,"skipped_count":0,"reclassified":true},"timestamp":"2026-08-13T21:37:44.883Z"}
```

Which PR does this session own?
```bash
cat ~/.koto/sessions/execute-vale-adoption/ctx/home_pr          # 269
cat ~/.koto/sessions/execute-vale-adoption/ctx/settled_branch   # docs/vale-adoption-scope
```

**Did THIS agent session drive a koto loop?** — the hook-grade check. This is the
one I'd build on. Tested working against three real sessions (positive execute,
positive work-on across duplicate project dirs, negative unknown-session):

```bash
#!/usr/bin/env bash
# koto-adherence-check.sh <claude-code-session-id> [template-name]
# exit 0 = matching koto workflow record exists
# exit 1 = no koto record for this session  (the adherence failure)
# exit 2 = no such Claude Code session on this machine
set -uo pipefail
SID="${1:?usage: $0 <claude-code-session-id> [template-name]}"
WANT="${2:-execute}"

mapfile -t WFDIRS < <(find "$HOME/.claude/projects" -mindepth 3 -maxdepth 3 \
  -type d -path "*/$SID/workflows" 2>/dev/null)

if [ "${#WFDIRS[@]}" -eq 0 ]; then
  find "$HOME/.claude/projects" -maxdepth 2 -name "$SID.jsonl" -quit \
    | grep -q . && { echo "NO-KOTO"; exit 1; }
  echo "NO-SESSION"; exit 2
fi

found=0
for d in "${WFDIRS[@]}"; do
  for f in "$d"/koto-*.json; do
    [ -e "$f" ] || continue
    IFS=$'\t' read -r name status wf state < <(
      jq -r '[(.name//"?"),(.status//"?"),(.koto.workflow//"?"),(.koto.currentState//"?")]|@tsv' "$f")
    # .name is "<template> · <state>" -- template discriminator that does not
    # depend on the session-naming convention (execute-<slug> vs issue_<n>).
    case "$name" in "$WANT "*|"$WANT") : ;; *) continue ;; esac
    echo "KOTO template=$WANT workflow=$wf state=$state status=$status mtime=$(stat -c %Y "$f") file=$f"
    found=1
  done
done
[ "$found" -eq 1 ] || { echo "NO-KOTO"; exit 1; }
```
Verified output:
```
$ koto-adherence-check.sh b0818094-4831-4792-a6ae-bd1be88ee18d execute
KOTO template=execute workflow=execute-vale-adoption state=orchestrator_setup status=running mtime=1786658910 file=.../workflows/koto-01fddf49-....json
exit=0

$ koto-adherence-check.sh fe5bd5e5-5123-4e28-a1f1-f8bf0ed780af work-on
KOTO template=work-on workflow=issue_2474 state=setup_issue_backed status=blocked mtime=1785767054 file=.../-2474/.../koto-29bfa055-....json
KOTO template=work-on workflow=issue_2474 state=done      status=completed mtime=1785770963 file=.../-e90f2b57/.../koto-29bfa055-....json
exit=0
```

**Forensic confirmation of the second incident, using exactly this check.** The
workspace project dirs for the incident workspace are:
```
~/.claude/projects/-home-dgazineu-dev-niwaw-tsuku-tsuku-execute-and-work-on-trigger-d36b0bbf
~/.claude/projects/-home-dgazineu-dev-niwaw-tsuku-tsuku-execute-and-work-on-trigger-d36b0bbf-public-shirabe--claude-worktrees-skill-adherence-enforcement
```
`find ... -name workflows -type d` under the first returns **nothing**. No koto
loop was ever driven from any Claude Code session in that workspace. The check
correctly reports the failure the exploration is trying to catch. **[confirmed]**

### 5. What koto leaves in git — nothing usable

I read `pr_finalization` in `skills/execute/koto-templates/execute.md:425-470` line
by line. The PR title is `feat: $PLAN_SLUG`. The body is a factual paragraph, a
`---`, and a per-child outcome table. **There is no session id, no template hash,
no koto marker, no commit trailer, no branch-name encoding beyond `impl/<slug>`.**
`references/pr-body-conformance.md` explicitly forbids an AI-attribution footer, and
the workspace CLAUDE.md forbids attribution trailers. **[confirmed]**

The only in-repo trace is `wip/execute_<topic>_state.md` — the `wip-yaml-md`
projection (`skills/execute/SKILL.md:342-395`). It fails as an adherence signal on
two counts: it is **agent-authored prose**, trivially forgeable by an agent doing
the work inline; and the finalization cascade `git rm`s it before the PR flips
ready, so a post-hoc CI check finds nothing. The `wip/work-on_<slug>_impact.json`
file that the `worktree_discipline_check` gate tests is likewise agent-written —
what makes it meaningful is that *koto ran the test and recorded the exit code*, not
the file's existence.

**A CI check cannot tell a koto-driven PR from a hand-rolled one.** The
distinguishing state never leaves the developer's machine. If a post-hoc CI gate is
wanted, something must be *added* to the PR — a `Koto-Session:` trailer or a fenced
body block written by `plan_completion`. Note `/execute`'s Security Considerations
define a **closed write-target set**; adding a remote write is an explicit R9
amendment (`SKILL.md:408-412` defers exactly this for the run-report emit).

### 6. Where the koto session first becomes observable, and the gap

Sequence, with the first externally visible artifact at each step:

| Step | Externally visible? |
|---|---|
| `preflight.sh` | no — plain bash, prints and exits, touches nothing |
| `koto init execute-<slug>` | **YES — first observable moment.** Creates `~/.koto/sessions/execute-<slug>/`, writes the header, and (via the `append_event` funnel) materializes the `/workflows` JSON into the Claude Code session dir |
| `orchestrator_setup` | branch + draft PR on GitHub; `ctx/settled_branch`, `ctx/home_pr` |
| `worktree_discipline_check` | `gate_evaluated` event — koto ran the test itself |
| `plan-to-tasks.sh` | **no — stdout only** |
| `koto next --with-data @tasks` | `scheduler_ran` with `spawned_count`; child session dirs `<parent>.o-*` |
| `pr_finalization` | PR title/body edit — carries no koto marker |
| `plan_completion` | cascade + `gh pr ready`; session dir deleted at terminal |

**The earliest, cheapest, most reliable durable artifact proving the koto loop
actually ran is the `/workflows` JSON written at `koto init`** — it lands on the
very first state commit, is bound to the Claude Code session, is repo-scoped, and
outlives cleanup. `~/.koto/sessions/execute-<slug>/` is equally early but
disappears at terminal; the terminal index survives but has no repo or plan binding.
Use the workflows JSON as the primary signal and the session dir as the live-detail
lookup.

**Why the scripts are the gap.** `skills/plan/scripts/plan-to-tasks.sh` is a pure
stdout emitter — its own header says "Reads a PLAN.md path and outputs a JSON array
of koto task-entry objects on stdout." Its entire interface is
`plan-to-tasks.sh <PLAN.md-path>`. **It takes no session argument. It cannot
register what it emits, because it does not know what to register it against.**
Submission is a separate step, three lines later in the template
(`execute.md:388-396`):
```bash
TASKS=$(${CLAUDE_PLUGIN_ROOT}/skills/plan/scripts/plan-to-tasks.sh {{PLAN_DOC}})
...
echo "{\"tasks\": $TASKS_WITH_BRANCH}" > "$TMP"
koto next {{SESSION_NAME}} --with-data @"$TMP"
```
An agent that runs line 1 and stops has a valid payload and no session — exactly
the second incident. And it happens *inside* `spawn_and_await`, which is only
reachable after `koto init`, so an agent that got this far normally *would* have a
session. The incident agent skipped `koto init` entirely and ran the script
standalone.

**Can it be made atomic?** Yes, and the change is small and mechanical: give the
script a required `--session <name>` and have it perform the `koto next
--with-data` itself, emitting to stdout only under an explicit `--dry-run`. Then
"produced a payload" and "registered a payload" are the same act, and the standalone
verification-only use the incident agent made becomes a use that has to say so.
Two things to check before committing to that: `/plan` also calls this script (it
lives under `skills/plan/`, and `plan-to-tasks_test.sh` exercises the pure-stdout
contract), so the dry-run path must stay first-class; and `spawn_and_await` calls it
**twice** — Tick 1 to spawn and Tick 2 to re-submit for dedup alongside
`batch_outcome` — so `--session` alone is not enough, the script would need to
carry the extra evidence field too. That is a real design question, not a
one-liner. **[inferred]**

### 7. Can koto be a PreToolUse gate?

**No, not in the sense of "is this edit inside a koto task." koto is structurally
blind to edits.** There is no koto process in the edit path, no PID relationship, no
environment variable stamped into the agent's process, and no notion of a "current
task" at all. The information flows exactly one way: Claude Code's
`CLAUDE_CODE_SESSION_ID` flows *into* koto; nothing flows back out into the agent's
environment. The `KOTO_*` env vars in source are configuration knobs
(`KOTO_SESSIONS_BASE`, `KOTO_WORKFLOWS_DIR`, `KOTO_REQUEST_STORE_*`) and one host
handoff (`KOTO_WORKFLOWS_HOST_SESSION`) — none identifies "the task currently
executing." **[confirmed]**

What a hook **can** ask, correlationally, is strictly weaker but still useful:

- *"Does a koto workflow record exist for MY Claude Code session, over the shirabe
  `execute` or `work-on` template?"* — the §4 check. Session-exact, repo-scoped,
  agent-independent. This catches the second incident.
- *"Is the branch I'm about to edit a branch some live koto session settled on?"* —
  `grep -l "$(git rev-parse --abbrev-ref HEAD)" ~/.koto/sessions/*/ctx/settled_branch`.
  Branch-scoped correlation, not causation.
- *"Is the live session non-terminal, and past `spawn_and_await`?"* — `koto status`
  or the workflows JSON's `currentState`.

None of these proves the edit in front of the hook is *caused by* a koto directive.
They prove a koto loop is running in this session over this repo. For the stated
problem — an agent that skipped the loop and implemented six issues inline — that
is sufficient: the incident agent would have failed the first check outright,
because no workflows dir exists for its workspace.

## Implications

1. **Adherence is measurable, and the measurement already exists.** koto writes a
   session-bound, repo-scoped, cleanup-surviving record on every state commit,
   without the agent choosing to. The §4 check is ~25 lines of bash with no koto
   dependency and no network. Nothing needs to be built in koto to make adherence
   observable — it needs to be *read*.

2. **Invocation is the wrong unit, and the right unit is `koto init`.** The second
   incident agent ran two real skill scripts and produced a valid six-edge task
   payload. Every "did it run the skill" check passes it. The `/workflows` record
   appears at `koto init` and nowhere earlier — it is the exact line between
   "consulted the skill" and "submitted to the loop."

3. **A PreToolUse gate is the right shape; a CI gate is not.** All distinguishing
   state is local. A CI check on a merged PR cannot tell a koto run from an inline
   one, because the PR body carries no marker and the `wip/` projection is deleted
   before merge. Enforcement has to happen on the machine, at edit time — which is
   also where niwa already injects a shirabe PreToolUse gate.

4. **The scripts gap is real but narrower than it looks.** `plan-to-tasks.sh` cannot
   self-register because it has no session parameter. Adding `--session` makes
   payload-production and submission atomic, but the script is shared with `/plan`
   and called twice per run with different evidence, so it needs design, not a
   patch.

5. **The user's "no visibility" loss has a ready-made fix.** The `/workflows` JSON
   is what feeds Claude Code's live workflow view, and `koto dashboard --once` gives
   the same data as scriptable TSV. Both were available during both incidents and
   both were empty — which is precisely the signal.

## Surprises

- **koto self-discovers the Claude Code session and writes into its directory.** I
  went in expecting `~/.koto/` to be the whole story. The strongest observability
  surface is not in `~/.koto/` at all — it is
  `~/.claude/projects/<encoded-cwd>/<session-id>/workflows/`, and it is the only
  koto state anywhere that is bound to a repository.

- **`~/.koto/sessions/` is not repo-scoped, and `koto workflows` lies about it.**
  Its help says "List all active workflows in the current directory"; it returns
  every session on the machine. Any repo-scoped check must go through the project
  dir or read `PLAN_DOC` out of the state file.

- **Successful runs delete their own evidence.** Session dirs are removed on
  reaching terminal. The naive check `test -d ~/.koto/sessions/execute-<slug>` is
  *false for every successful run* — it inverts the signal. Only the `/workflows`
  record and the terminal index survive.

- **The same session id can hold two disagreeing workflow records** under different
  encoded project dirs when cwd changes mid-session. Reproduced, not theorized.

- **`koto status` and `koto session list` write hundreds of legacy-migration
  warnings to stderr on every invocation** on this machine. Harmless with
  `2>/dev/null`, but it would swamp a hook's log.

- `spawn_and_await` calls `plan-to-tasks.sh` **twice** — the Tick 2 dedup re-submit
  is easy to miss and constrains any atomicity fix.

## Open Questions

1. **Do subagents inherit `CLAUDE_CODE_SESSION_ID`?** If a `/work-on` child spawned
   via the Agent tool gets a *different* session id, its koto calls materialize
   under a different directory and per-child observability fragments. koto's
   `resolve_publish_location` walks the parent chain to the nearest published
   ancestor, which suggests children are expected to publish alongside the parent —
   but I did not test it. This decides whether a per-child adherence check works.

2. **What exactly is in the PreToolUse hook input?** I asserted `session_id` is
   present from the documented contract but did not read the niwa gate that already
   ships. That gate is the cheapest place to confirm, and it is also where any new
   check should live.

3. **Should `plan-to-tasks.sh --session` land, given `/plan` shares it?** Needs the
   Tick-2 evidence question answered and `/plan`'s use audited.

4. **Is a `Koto-Session:` PR trailer worth the R9 amendment?** It would make the
   signal survive off-machine and enable a CI gate, at the cost of widening
   `/execute`'s closed write-target set. Out of scope for a hook-based fix, but it
   is the only route to post-hoc verification.

5. **What is `has_result: true` in the terminal index pointing at?** The doc calls
   it a done-bit for a `WorkflowResult` envelope living "on the child log and on the
   parent's `ChildCompleted`" — both inside session dirs that cleanup deletes. Where
   the envelope survives to, if anywhere, I did not trace.

## Summary

koto's guarantees are bookkeeping, not enforcement — it is a state machine over
files with a stubbed spawn primitive, so it never sees an edit and cannot gate one —
but it does stamp an unforgeable, agent-independent record: on every state commit it
self-discovers `CLAUDE_CODE_SESSION_ID` and writes
`~/.claude/projects/<encoded-cwd>/<session-id>/workflows/koto-<uuid>.json` carrying
the template name, workflow name, and current state, repo-scoped by the project path
and surviving the session-directory cleanup that erases `~/.koto/sessions/<id>/` on
success. That file appears at `koto init` and nowhere earlier, which makes it the
exact artifact separating "ran the skill's scripts" from "submitted to the loop" —
the distinction the second incident turns on, and one I confirmed forensically: the
incident workspace's project directory contains no `workflows/` directory at all,
and the 25-line check in §4 reports the failure correctly. The biggest open question
is whether Agent-tool subagents inherit the parent's `CLAUDE_CODE_SESSION_ID`, since
that decides whether per-child `/work-on` adherence is observable or only the
parent's.
