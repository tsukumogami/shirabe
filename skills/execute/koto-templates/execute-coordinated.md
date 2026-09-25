---
# The coordinated envelope. A coordinated PLAN runs, in one repository or
# several, as a loop over its PR nodes whose decisions live in scripts, not
# prose: coordinated-next.sh prints the one next action, node-cut.sh and
# node-push.sh own each node's branch and PR, coord-merge.sh merges, and
# coordination-verdict.sh decides where the run ended. This template is the
# thin koto envelope around that loop, so a coordinated run ends in the same
# result-declaring terminals a single-pr run does and a /deliver leg can read
# it. A full coordinated template with a state per action and a child per node
# waits for its own design.
#
# It shares the execute-<topic> session name with execute.md: koto-open.sh's
# --attach-live refuses a live session built from the other template
# (template_mismatch), and --replace-terminal replaces a finished one.
#
# Terminal-tick retention: EVERY `koto next` on this session carries
# --no-cleanup, as it does on execute.md. The session is always a root, so the
# flag withholds nothing from a parent; under --koto-leg the result reaches
# the leg by promotion. See ../../../references/koto-session-retention.md.
#
# Results. Every edge into a terminal assigns `outcome`, and assigns `step` or
# `reason` only where the edge fixes the value as a literal
# (coord_merge_confirm's merge-not-observed, and execute:status-read for an
# absent or unmatched verdict). Everything else a terminal reports was written
# to context by record-coordination-verdict.sh, because an assignment cannot
# read ${context.<k>}. There is no done_refused terminal: an init or attach
# refusal creates no session, and koto records it on the leg.
name: execute-coordinated
version: "1.0"
# koto-floor: pinned -- result maps, constrained and rebindable variables,
# transition context_assignments, and non-overridable gates need the koto
# release .tsuku.toml pins, the floor skills/execute/requires.tsv declares. The
# v0.12.2 floor check (scripts/check-koto-floor.sh) does not cover this template.
description: >
  Coordinated-PLAN envelope. Records the write set and the coordination home,
  runs the script-decided per-node loop, records the verdict the loop ended
  on, confirms a coordination-PR merge by a live read, and ends in a
  result-declaring terminal.
initial_state: coord_setup

variables:
  PLAN_DOC:
    description: >
      Path to the coordinated PLAN in the coordination checkout, relative to
      it. Interpolated into the verdict's default action, so it is held to a
      path of plain characters with no `..` segment. Not rebindable.
    required: true
    pattern: '^/?([A-Za-z0-9_][A-Za-z0-9._-]*/)*[A-Za-z0-9_][A-Za-z0-9._-]*\.md$'
  PLAN_SLUG:
    description: >
      The PLAN's topic slug, matching ^[a-z0-9-]+$. It names the session
      (execute-{{PLAN_SLUG}}), which the default actions rebuild, and every
      node branch (impl/<slug>-<node-id>). Not rebindable.
    required: true
    pattern: '^[a-z0-9-]+$'
  PLUGIN_ROOT:
    description: >-
      Absolute path to the shirabe plugin root, passed by execute-open.sh. The
      default actions run scripts that ship in the plugin, and koto resolves
      only {{KEY}} references in a command. The pattern admits an absolute path
      with no `..` segment, the same literal pattern execute.md and scope.md
      declare. Rebindable, so a resumed run takes this invocation's plugin root.
    required: true
    pattern: '^/([^/.][^/]*|\.[^/.][^/]*|\.\.[^/]+|\.)?(/([^/.][^/]*|\.[^/.][^/]*|\.\.[^/]+|\.)?)*$'
    rebind: true
  PAUSE_BEFORE_FINALIZE:
    description: >
      Passed by the shared entry from the execution mode, as on execute.md.
      The coordinated loop has no review pause of its own, so nothing here
      reads it; it is declared so a coordinated and a single-pr invocation
      pass the same variables. Rebindable.
    required: false
    default: "false"
    values: ["true", "false"]
    rebind: true
  MERGE:
    description: >
      This invocation's merge intent, from /execute's own --merge flag (false
      without it). Never agent evidence and never inherited: every invocation
      passes it and koto re-applies it on every accepted attach. The loop hands
      it to coordinated-next.sh as --merge, which prints a merge action only
      when it is true, and the verdict and the resume line read it too.
    required: false
    default: "false"
    values: ["true", "false"]
    rebind: true

states:
  coord_setup:
    # Agent-run: the agent runs record-coord-setup.sh in the coordination
    # checkout, then ticks. The gates read back what the script wrote and
    # cannot be overridden, so a run whose write set was never recorded never
    # reaches the loop, and an override can't name a write set.
    gates:
      repos_recorded:
        type: context-matches
        key: repos
        pattern: '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(,[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)*$'
        overridable: false
      home_repo_recorded:
        type: context-matches
        key: home_repo
        pattern: '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
        overridable: false
      coord_branch_recorded:
        type: context-matches
        key: coord_branch
        pattern: '^[A-Za-z0-9._/-]+$'
        overridable: false
    accepts:
      setup_status:
        type: enum
        values: [blocked]
        description: >-
          Submitted only when record-coord-setup.sh refuses and the cause
          can't be fixed; the passing path submits nothing.
      detail:
        type: string
        description: Why the write set could not be recorded.
    transitions:
      - target: coord_loop
        when:
          gates.repos_recorded.matches: true
          gates.home_repo_recorded.matches: true
          gates.coord_branch_recorded.matches: true
      - target: done_error
        when:
          gates.repos_recorded.matches: false
          setup_status: blocked
        context_assignments:
          outcome: error
          step: "execute:coord_setup"
          failure_reason: "coord_setup blocked: ${evidence.detail}"

  coord_loop:
    # Agent-run. The agent runs coordinated-next.sh, performs exactly the
    # action it prints, and repeats. Evidence is accepted only when the script
    # printed a stopping line; which terminal the run reaches is decided by
    # coord_verdict from live reads, never from this evidence. The line is kept
    # as loop_line for one purpose: naming the step when the loop stopped early.
    accepts:
      loop_exit:
        type: enum
        values: [done, pause, error]
        required: true
        description: >-
          Which stopping line coordinated-next.sh printed: `done:<outcome>` is
          done, `pause` is pause, `error:<step>` is error.
      loop_line:
        type: string
        description: The exact line coordinated-next.sh printed last.
    transitions:
      - target: coord_verdict
        when:
          loop_exit: done
        context_assignments:
          loop_line: "${evidence.loop_line}"
      - target: coord_verdict
        when:
          loop_exit: pause
        context_assignments:
          loop_line: "${evidence.loop_line}"
      - target: coord_verdict
        when:
          loop_exit: error
        context_assignments:
          loop_line: "${evidence.loop_line}"

  coord_verdict:
    # The verdict, recorded by koto, not by the agent.
    # record-coordination-verdict.sh clears coord_verdict, pr, waiting, resume,
    # reason, and step; runs coordination-verdict.sh; and writes each field
    # only when every one matches its closed pattern. It reads GitHub and writes
    # koto context, nothing else. koto substitutes declared variables into a
    # default_action command, never context keys, so the script reads the
    # recorded write set and coordination branch itself.
    default_action:
      command: '{{PLUGIN_ROOT}}/skills/execute/scripts/record-coordination-verdict.sh --session "execute-{{PLAN_SLUG}}" --merge "{{MERGE}}" --plan "{{PLAN_DOC}}" --slug "{{PLAN_SLUG}}"'
      fallback: >-
        koto could not record the coordinated verdict. Read the command's own
        output above: exit 1 means coordination-verdict.sh failed or printed a
        field outside its pattern, 64 a missing coord_setup record, 70 a
        context write, and a timeout means the reads took longer than koto
        allows. The keys were cleared first, so nothing stale is read as
        current. Fix the cause and tick again to re-run it. There is no
        evidence to submit here and no override: the run leaves this state
        only on a verdict the script recorded.
    gates:
      verdict_merged:
        type: context-matches
        key: coord_verdict
        pattern: '^merged$'
        overridable: false
      verdict_ready:
        type: context-matches
        key: coord_verdict
        pattern: '^ready$'
        overridable: false
      verdict_paused:
        type: context-matches
        key: coord_verdict
        pattern: '^paused$'
        overridable: false
      verdict_dirty:
        type: context-matches
        key: coord_verdict
        pattern: '^dirty$'
        overridable: false
      verdict_error:
        type: context-matches
        key: coord_verdict
        pattern: '^error$'
        overridable: false
    transitions:
      - target: coord_merge_confirm
        when:
          gates.verdict_merged.matches: true
          gates.verdict_ready.matches: false
          gates.verdict_paused.matches: false
          gates.verdict_dirty.matches: false
          gates.verdict_error.matches: false
      # reason, pr, and waiting reach the result through the keys the record
      # script wrote; no edge out of this state assigns a reason.
      - target: ready_awaiting_merge
        when:
          gates.verdict_merged.matches: false
          gates.verdict_ready.matches: true
          gates.verdict_paused.matches: false
          gates.verdict_dirty.matches: false
          gates.verdict_error.matches: false
        context_assignments:
          outcome: ready-awaiting-merge
      - target: paused_awaiting_merges
        when:
          gates.verdict_merged.matches: false
          gates.verdict_ready.matches: false
          gates.verdict_paused.matches: true
          gates.verdict_dirty.matches: false
          gates.verdict_error.matches: false
        context_assignments:
          outcome: paused-awaiting-merges
      # A DIRTY blocker is ready-awaiting-merge with reason=merge-state:DIRTY,
      # which the record script wrote.
      - target: done_blocked
        when:
          gates.verdict_merged.matches: false
          gates.verdict_ready.matches: false
          gates.verdict_paused.matches: false
          gates.verdict_dirty.matches: true
          gates.verdict_error.matches: false
        context_assignments:
          outcome: ready-awaiting-merge
          failure_reason: "coord_verdict: a node PR's merge state is DIRTY"
      # The step is the one the record script wrote.
      - target: done_blocked
        when:
          gates.verdict_merged.matches: false
          gates.verdict_ready.matches: false
          gates.verdict_paused.matches: false
          gates.verdict_dirty.matches: false
          gates.verdict_error.matches: true
        context_assignments:
          outcome: error
          failure_reason: "coord_verdict: the coordinated run stopped on an error"
      # No verdict recorded, or one outside the set (something other than the
      # record script wrote or removed the key after the action ran): never
      # read as progress. A failing action stops the tick before the gates are
      # read, so it holds the run here instead.
      - target: done_blocked
        when:
          gates.verdict_merged.matches: false
          gates.verdict_ready.matches: false
          gates.verdict_paused.matches: false
          gates.verdict_dirty.matches: false
          gates.verdict_error.matches: false
        context_assignments:
          outcome: error
          step: "execute:status-read"
          failure_reason: "coord_verdict: no coordinated verdict was recorded"

  coord_merge_confirm:
    # The confirm read runs as a default action, never as a command gate:
    # merge-verdict.sh --confirm exits 0 on both outcomes, so a gate routing
    # on its exit code would always pass. record-merge-verdict.sh --confirm
    # clears confirm_verdict, finds the coordination PR itself through
    # owned-pr.sh --state all on the recorded home_repo and coordination
    # branch (never from evidence or an index entry), and writes the confirm
    # line only when it matches ^(merged|not-merged:merge-not-observed)$. The
    # repository is home_repo, a single owner/repo, never the comma-joined
    # repos write set. This is the only state with an edge into `merged`.
    default_action:
      command: '{{PLUGIN_ROOT}}/skills/execute/scripts/record-merge-verdict.sh --confirm --session "execute-{{PLAN_SLUG}}" --merge "{{MERGE}}" --repo "$(koto context get execute-{{PLAN_SLUG}} home_repo)" --head-branch "$(koto context get execute-{{PLAN_SLUG}} coord_branch)"'
      fallback: >-
        koto could not record the confirm read of the coordination PR. Read the
        command's own output above: exit 1 means no single owned coordination
        PR was found or the read printed something outside its grammar, 64 a
        missing home_repo or coord_branch record, 70 a context write. Tick
        again to re-run it. If it keeps failing, submit
        `confirm_status: unreadable`: with nothing confirmed, the run ends
        ready-awaiting-merge naming merge-not-observed, never merged.
    gates:
      confirmed_merged:
        type: context-matches
        key: confirm_verdict
        pattern: '^merged$'
        overridable: false
    accepts:
      confirm_status:
        type: enum
        values: [unreadable]
        description: >-
          Absent on every normal path. Submitted only when the confirm read
          keeps failing; it re-evaluates the gate on the cleared key, which can
          only route to ready_awaiting_merge.
    transitions:
      - target: merged
        when:
          gates.confirmed_merged.matches: true
        context_assignments:
          outcome: merged
          waiting: ""
      - target: ready_awaiting_merge
        when:
          gates.confirmed_merged.matches: false
        context_assignments:
          outcome: ready-awaiting-merge
          reason: merge-not-observed

  merged:
    # Reached only from coord_merge_confirm, on a live read of MERGED.
    terminal: true
    result:
      outcome: "${context.outcome}"
      step: "${context.step}"
      reason: "${context.reason}"
      pr: "${context.pr}"
      repos: "${context.repos}"
      resume: "${context.resume}"
      waiting: "${context.waiting}"

  ready_awaiting_merge:
    # Nothing is left to start, and something is unmerged: a node PR or the
    # coordination PR waits on a human (or a later /execute --merge).
    terminal: true
    result:
      outcome: "${context.outcome}"
      step: "${context.step}"
      reason: "${context.reason}"
      pr: "${context.pr}"
      repos: "${context.repos}"
      resume: "${context.resume}"
      waiting: "${context.waiting}"

  paused_awaiting_merges:
    # A node waits on an unmerged predecessor. The coordination PR stays open;
    # a later /execute on the same PLAN resumes from it.
    terminal: true
    result:
      outcome: "${context.outcome}"
      step: "${context.step}"
      reason: "${context.reason}"
      pr: "${context.pr}"
      repos: "${context.repos}"
      resume: "${context.resume}"
      waiting: "${context.waiting}"

  done_blocked:
    terminal: true
    failure: true
    result:
      outcome: "${context.outcome}"
      step: "${context.step}"
      reason: "${context.reason}"
      pr: "${context.pr}"
      repos: "${context.repos}"
      resume: "${context.resume}"
      waiting: "${context.waiting}"

  done_error:
    terminal: true
    failure: true
    result:
      outcome: "${context.outcome}"
      step: "${context.step}"
      reason: "${context.reason}"
      pr: "${context.pr}"
      repos: "${context.repos}"
      resume: "${context.resume}"
      waiting: "${context.waiting}"
---

## coord_setup

Record the run's write set and its coordination home. Run this in the coordination checkout, the one holding the coordination branch and the PLAN:

```bash
bash {{PLUGIN_ROOT}}/skills/execute/scripts/record-coord-setup.sh --session {{SESSION_NAME}} --plan {{PLAN_DOC}}
```

It records four keys, each fixed for the rest of the run: `repos`, the sorted, comma-joined `owner/repo` list of every PR node's repository, which is the run's write set; `home_repo`, this checkout's repository, which must be one of them; `coord_branch`, the branch checked out here; and `plan_abs`, the PLAN's absolute path, which outline-sourced children receive as `PLAN_DOC`. Then tick with `koto next {{SESSION_NAME}} --no-cleanup`; the state's gates read the record back and move the run to the loop.

The script refuses a detached HEAD (exit 65), a home repository outside the write set (66), the default branch (67), and a value that differs from one already recorded (68). If the cause can't be fixed, submit `setup_status: blocked` with `detail`, which ends the run at `done_error` with `step=execute:coord_setup`.

## coord_loop

Run the coordinated loop. Its decisions are the script's, not yours: run `coordinated-next.sh`, do exactly the action it prints, and run it again, until it prints `done:<outcome>`, `pause`, or `error:<step>`.

```bash
REPOS=$(koto context get {{SESSION_NAME}} repos)
HOME_REPO=$(koto context get {{SESSION_NAME}} home_repo)
CB=$(koto context get {{SESSION_NAME}} coord_branch)
ATTEMPTS=$(koto context get {{SESSION_NAME}} merge_attempts) || ATTEMPTS=""
bash {{PLUGIN_ROOT}}/skills/execute/scripts/coordinated-next.sh --plan {{PLAN_DOC}} --slug {{PLAN_SLUG}} \
  --repos "$REPOS" --home-repo "$HOME_REPO" --coord-branch "$CB" --merge {{MERGE}} --attempts "$ATTEMPTS"
```

`--merge {{MERGE}}` is this invocation's own merge intent; don't change it. The actions:

- `dispatch:<node>` — the node's predecessors are all merged and it has no PR yet. Take its `REPO` and `ISSUES` from `plan-to-tasks.sh {{PLAN_DOC}}` (the entry named `<node>`). Cut its branch from the default branch in its own worktree: `bash {{PLUGIN_ROOT}}/skills/execute/scripts/node-cut.sh {{PLAN_SLUG}} <node>` (add `--repo-dir <clone>` when the node's repository isn't this one). In that worktree, dispatch the node's work items, in `ISSUES` order, each as a `/work-on` plan-backed child on the node branch: `ISSUE_SOURCE` from the node entry, `SHARED_BRANCH=impl/{{PLAN_SLUG}}-<node>`, and, for `plan_outline`, `ISSUE_NUMBER=<item>` and `PLAN_DOC` set to the `plan_abs` value (`koto context get {{SESSION_NAME}} plan_abs`), the PLAN in this coordination checkout, since the node branch doesn't carry it; for `github`, the child reads its issue as usual. Each child commits to the node branch and submits `pr_status: shared`; no child opens a PR. Then push the node and record it: `bash {{PLUGIN_ROOT}}/skills/execute/scripts/node-push.sh node --slug {{PLAN_SLUG}} --node <node> --repo <REPO> --issues <ISSUES> --home-repo "$HOME_REPO" --coord-branch "$CB"`, run in the node worktree. It sweeps `wip/`, pushes, opens the node's draft PR (or adopts the one owned PR on the branch), and writes the node's index line with `head=`. If a child fails and can't be resolved, stop the loop with `loop_exit: error` and `loop_line: error:execute:dispatch`.
- `evaluate:<node>` — the node's PR is a draft, or its checks are still running. Wait for its checks. Mark it ready only once every check passed and `git ls-tree -r --name-only <pushed head> -- wip/` prints nothing: `gh pr ready <n> --repo <REPO>`. A check that fails comes back from the script as `error:execute:ci`.
- `merge:<node>` — only ever printed with `--merge true`. Run `bash {{PLUGIN_ROOT}}/skills/execute/scripts/coord-merge.sh --session {{SESSION_NAME}} --slug {{PLAN_SLUG}} --home-repo "$HOME_REPO" --coord-branch "$CB" --node <node>`. It merges only through `merge-exec.sh`, at the `head=` the node's push recorded, and confirms with a live read; a merge it did not see land is recorded so it isn't called again.
- `cascade` — every node PR reports `MERGED`. In this checkout, run the finalization cascade once, on the coordination branch: `bash {{PLUGIN_ROOT}}/skills/work-on/scripts/run-cascade.sh --push {{PLAN_DOC}}` (skip it when the PLAN is already gone), then record the coordination PR's own head: `bash {{PLUGIN_ROOT}}/skills/execute/scripts/node-push.sh coordination --slug {{PLAN_SLUG}} --home-repo "$HOME_REPO" --coord-branch "$CB"`.
- `evaluate-coordination` — run the merge-last gate over every indexed PR except the coordination PR itself, then mark the coordination PR ready: `gh pr view <n> --repo "$HOME_REPO" --json body --jq .body | bash {{PLUGIN_ROOT}}/scripts/coordination-gate-refs.sh "$HOME_REPO" <n>` gives the refs; pass each as `--pr <ref>` to `shirabe validate --merge-gate --mode=ready`, and only when it passes, `gh pr ready <n> --repo "$HOME_REPO"`.
- `merge-coordination` — only with `--merge true`: `coord-merge.sh` as above with `--node coordination`. It runs the merge-last gate itself before merging.

When it prints a stopping line, submit it: `loop_exit: done` for `done:<outcome>`, `pause` for `pause`, `error` for `error:<step>`, with the line as `loop_line`. What you submit doesn't pick the ending; `coord_verdict` recomputes it from GitHub.

The loop never merges anything itself outside `coord-merge.sh`, never closes the coordination PR, and never writes a `head=` field. A node PR is never cut from the coordination branch, a predecessor's branch, or `HEAD`.

Evidence schema:
- `loop_exit`: `done`, `pause`, or `error`
- `loop_line`: the line `coordinated-next.sh` printed

## coord_verdict

Recording where the coordinated run ended. koto runs the record script itself on entry; you only see this state if it could not.

<!-- details -->

The command is `record-coordination-verdict.sh`. It clears `coord_verdict`, `pr`, `waiting`, `resume`, `reason`, and `step`; runs `coordination-verdict.sh`, which recomputes the run's position from the coordination PR, its index, and live `gh`; and writes the verdict and its fields only when every one matches its pattern. It writes nothing to GitHub. A recorded `merged` goes to `coord_merge_confirm`; `ready` to `ready_awaiting_merge`; `paused` to `paused_awaiting_merges`; `dirty` and `error` to `done_blocked`; a key that holds no verdict from that set to `done_blocked` with `step=execute:status-read`.

You are here because the script failed; the response above carries its exit code and stderr. Fix the cause and tick again to re-run it. There is no evidence to submit and no override: only a verdict the script records moves the run on.

## coord_merge_confirm

Confirming the coordination PR's merge. koto runs the confirm read itself on entry; you only see this state if it could not.

<!-- details -->

The command is `record-merge-verdict.sh --confirm` on the recorded `home_repo` and coordination branch. It finds the coordination PR itself through the ownership filter, re-reads it for up to 20 seconds, and records `merged` or `not-merged:merge-not-observed`. Only a recorded `merged` reaches `merged`; anything else ends `ready_awaiting_merge` with `reason=merge-not-observed`.

You are here because the script failed; the response above carries its exit code and stderr. Tick again to re-run it. If it keeps failing, submit `confirm_status: unreadable`, which re-evaluates the gate on the cleared key and ends the run ready-awaiting-merge naming merge-not-observed, never merged.

Evidence schema (optional; the passing path submits nothing):
- `confirm_status`: `unreadable`

## merged

The coordination PR merged, last, and a live read confirmed it. Render the exit lines from the terminal result; don't compose them yourself:

```bash
koto status {{SESSION_NAME}} | {{PLUGIN_ROOT}}/skills/execute/scripts/print-exit.sh
```

## ready_awaiting_merge

Nothing is left to start, and a node PR or the coordination PR is still unmerged: it waits on a human, or on a later `/execute --merge`. The result's `reason` names why (the merge wasn't requested, a review or protection rule, a moved head, a merge call that failed, or a merge that wasn't observed yet and may still land). Render the exit lines from the terminal result:

```bash
koto status {{SESSION_NAME}} | {{PLUGIN_ROOT}}/skills/execute/scripts/print-exit.sh
```

## paused_awaiting_merges

A node can't start because a predecessor's PR is unmerged. The coordination PR stays open: it is the durable record the pause rests on, and a later `/execute` on this PLAN resumes from it. Don't close it. Render the exit lines, which carry one line per unmerged PR and the resume command, from the terminal result:

```bash
koto status {{SESSION_NAME}} | {{PLUGIN_ROOT}}/skills/execute/scripts/print-exit.sh
```

## done_blocked

The coordinated run stopped on a blocker: a node PR's merge state is DIRTY (the result carries `outcome=ready-awaiting-merge` with `reason=merge-state:DIRTY`), or an error whose `step` the result names. Render the exit lines from the terminal result:

```bash
koto status {{SESSION_NAME}} | {{PLUGIN_ROOT}}/skills/execute/scripts/print-exit.sh
```

The `failure_reason` context key carries the detail: `koto context get {{SESSION_NAME}} failure_reason`.

## done_error

The run could not record its write set and stopped before the loop. Render the exit lines from the terminal result:

```bash
koto status {{SESSION_NAME}} | {{PLUGIN_ROOT}}/skills/execute/scripts/print-exit.sh
```
