---
schema: design/v1
status: Accepted
problem: |
  /work-on and /execute take the agent's word for verdicts that shipped checks
  can decide: whether the pull request title and body conform, whether every
  commit follows the convention, whether wip/ files reach a pull request,
  whether verification passed, whether a review panel found anything blocking,
  and several script results the agent copies into answer fields. The checks
  exist, but they run in CI, on one path only, or not at all, so a wrong copy
  passes and a failure names no rule.
decision: |
  Add command gates to the two templates, in the states that produce each
  output, that run shirabe's shipped checks through small gate scripts with
  one exit convention (0 pass, 1 finding, 2 could not decide) and koto's
  ::koto-finding:: lines keyed by each rule's source location. Remove every
  answer value that restated a script's result and route on a gate instead.
  Verification becomes two states: a polling default action that starts the
  repository's committed, machine-readable map in a bounded, detached runner,
  and a verdict state that routes on the runner's result and refuses a
  repository with no map. Panel gates recompute pass from per-reviewer
  findings keys stamped with the head they reviewed, and each panel state
  names the slot for a later shadow decider check.
rationale: |
  Routing on exit status works on koto 0.14.1, so the build waits on no koto
  release; findings and attempt counts arrive with the first release that
  carries koto#290 and koto#292, with no template change. Wrapping the shipped
  checks, rather than reimplementing them, keeps one rule per check. A
  detached runner started by a polling launcher is the only way a 30-second
  command limit can run suites that take minutes, and reading the map from the
  default branch keeps a change from choosing its own verification. Per-reviewer
  keys let koto see every reviewer's findings rather than an aggregate the
  agent wrote, and the head stamp keeps an old round's pass from counting.
upstream: docs/prds/PRD-output-gates.md
---

# DESIGN: Output Gates

## Status

Accepted

## Context and Problem Statement

/work-on and /execute each run as a koto workflow. koto evaluates gates (a
command's exit status, whether a context key exists or matches a pattern) and
routes on them; anything a gate doesn't decide, the agent submits as evidence.
The requirements (docs/prds/PRD-output-gates.md) ask that every verdict a
shipped check can decide be decided by a gate, in the state that produces the
output, and that every answer value restating a script's result go away.

The checks this design uses, as they ship at a916ccc:

| Check | Where it ships | How it is called today | Exit convention |
|---|---|---|---|
| PR title and body conformance (PB1 to PB4) | `shirabe validate --pr-body <file> --pr-title <title>` (`crates/shirabe/src/main.rs`) | `.github/workflows/pr-body.yml`, after the PR opens | 0 clean, 1 tool error, 2 violations, 3 I/O, 4 incomplete |
| Conventional Commits subject | the `commit_convention` gate regex in `work-on.md` | `pre_pr_evidence`, tip commit only | grep status |
| No `wip/` in the pushed tree | `git ls-tree -r --name-only <sha> -- wip/` in `skills/execute/scripts/node-push.sh` | coordinated /execute only | empty output means clean |
| Session role | `skills/work-on/scripts/session-role.sh` | the agent runs it and copies the word | prints `root` or `child`, failing safe to `child` |
| Staleness | `skills/work-on/scripts/check-staleness.sh` | a gate, and the agent restates it | 0 fresh, 1 stale, 3 unavailable |
| Owned-PR lookup | `skills/execute/scripts/owned-pr.sh` | the agent runs it and copies the result | 0 with one URL, 0 with empty output (none), 2 read failure, 3 several, 4 ambiguous, 5 another run's, 64 usage |
| Cascade verdict | `skills/work-on/scripts/run-cascade.sh --push --session` | the agent runs it and copies `cascade_status` from its JSON | JSON verdict `completed`, `partial` or `skipped` |
| Verification map | a Markdown list in `.claude/shirabe-extensions/work-on.md` | the agent reads, selects, runs and reports | none |

koto 0.14.1 is the latest release. It routes on gate exit codes and context
matches, runs each command with a 30-second limit, supports a `default_action`
with `polling`, re-runs a state's action on every tick that carries no
evidence, and discards a failed gate's output. koto#290 (findings, attempt
counts, captured streams) and koto#292 (gate polling, stale-key clearing) are
merged on koto's main, which is at 0.14.2-dev, and in no release yet;
koto#294 (decider checks) likewise.

## Decision Drivers

- **D1. Settle the verdict where the output is made.** A gate in CI settles it
  after a reviewer has seen the pull request; a gate in the producing state
  settles it before.
- **D2. Call checks as they ship.** A gate that reimplements a check creates a
  second rule that can drift from the first.
- **D3. No koto change and no release request.** The design has to route on
  what 0.14.1 already does.
- **D4. Remove copied verdicts, keep judgment.** Where a script decides, the
  agent stops answering. Where only judgment decides (retry or escalate after
  a blocking finding, whether a fix was pushed), the agent still answers.
- **D5. Verification is chosen by the base, bounded, and readable.** The
  change being judged can't choose its own commands, a runaway suite is
  stopped by process count and not only by time, and a failure leaves logs a
  person can read (the constraints in #384).
- **D6. No pass skips a panel.** Every gate this design adds can only stop a
  run or send it back; none can advance past a panel that hasn't run on the
  current head.
- **D7. Wait only on the rule touched.** A gate depends on the
  contradiction-settlement work (#507) only through the specific rule it
  reads.
- **D8. No false positives on shirabe itself.** A gate that fires on content
  the repository legitimately carries holds every run in that repository and
  teaches people to override it.

## Considered Options

### Decision 1: How a gate reaches a shipped check

**Chosen: thin gate scripts that call the shipped check and translate its
result.** Each script fetches the input (a PR's title and body, a commit
range), calls the check unchanged, prints one `::koto-finding::` line per
finding, and exits 0, 1 or 2. The shipped check keeps its own flags, output
and exit codes.

*Alternative: inline gate commands.* The existing gates are mostly one-line
shell commands in the template. That works for a single grep, but the PR-body
check needs a temporary file, two `gh` reads and a translation of five exit
codes, and the commit walk needs a loop. Inline, those become long quoted
commands that `check-template-interpolation.sh` refuses when they need a shell
variable, and they can't be tested without koto. Rejected on testability
(R15).

*Alternative: new `shirabe validate` modes.* A `--commits` or `--wip` mode in
the Rust validator would be one binary with one exit convention. It is the
planned direction elsewhere, and R1 says that work is not a dependency. Taking
it here would make this feature wait on a binary release. Rejected for now;
the gate scripts are small enough to retire into those modes later.

### Decision 2: How verification runs under a 30-second command limit

**Chosen: a detached, bounded runner started by a polling default action, and
a separate verdict state.** The `verification` state's `default_action` runs
`run-verification.sh --start`, which returns within a second: it either finds
a result for the current head, or starts a supervisor that runs the selected
commands and writes a result to disk. The `verification_settled` gate passes
once that result exists. koto polls it for up to eight minutes per tick, and
because koto re-runs the action on every tick without evidence, the agent
ticks again after a window expires and polling resumes. The next state,
`verification_verdict`, routes on `check-verification.sh`'s exit code. Two
states are needed because polling continues until every gate in the state
passes; a failing verdict gate in the polling state would wait out the window
instead of routing.

*Alternative: a plain command gate per map command.* Simple, and exactly what
koto's 30-second limit forbids: `cargo test --workspace` and the eval runner
both take minutes. Rejected because it can't run the commands the map names.

*Alternative: let the agent run the commands and gate on a results file it
writes.* This is the current arrangement with a file instead of a string. The
agent still chooses the commands and reports the result. Rejected by R6.

*Alternative: koto#292's gate `poll:`.* A polling command gate, with a hold
bound built for exactly this, is the cleaner long-term shape and needs a koto
release that doesn't exist. The runner's interface doesn't change when it
arrives; only the launcher's state does. Deferred to the release floor below.

### Decision 3: The verification map's form and where it is read from

**Chosen: a JSON file committed beside the extension config, read from the
default branch's copy at the run's merge-base.** The file is
`.claude/shirabe-extensions/verification-map.json`. The runner reads it with
`git show <merge-base>:.claude/shirabe-extensions/verification-map.json`,
where the merge-base is between `HEAD` and the default branch. A branch that
edits the map is verified by the map it started from. A missing file at that
commit is "no verification map".

This pins the list of commands, not what they run: the test suites and
scripts a command invokes come from the branch, as they must, since they are
what the change is tested with. #384's second requirement is met for the map
and stated as a residual for the suites.

*Alternative: keep the Markdown list and parse it.* The schema reference says
the layout is each project's choice, so no parser can read every map, and an
agent reading it is the arrangement being replaced. Rejected.

*Alternative: TOML.* Consistent with shirabe's other data files, but the
runner is a shell script and `jq` is already a declared dependency; a TOML
reader is not. Rejected on dependencies.

*Alternative: read the map from the working tree.* This is what the schema
reference and today's agent do, and it has a real advantage: a change that
adds a new suite gets verified by that suite in the same pull request, rather
than one merge later. Rejected because the same property lets a change remove
the command that would fail it, which D5 rules out.

### Decision 4: Where panel verdicts live and how pass is computed

**Chosen: one koto context key per reviewer, stamped with the head it
reviewed, and a gate that recomputes pass from all of them.** Each reviewer
writes its own verdict with `koto context add <session> <panel>.<focus>.json`.
The gate script `check-panel-verdict.sh` knows each panel's reviewer set
(scrutiny: completeness, justification, intent; review: pragmatic, architect,
maintainer; qa: qa), reads every key, and passes exactly when every key is
present, parses, names the current `HEAD` as the commit it reviewed, and holds
no finding with severity `blocking`. It ignores `passed`, `blocking_count` and
any other summary field. A key from an earlier round names an older head, so
a loop back through `implementation` that adds a commit makes every old key
stale, whether or not the retry loop managed to clear it.

*Alternative: keep one aggregate key the agent writes.* The gate could still
recompute from a findings list, but the list is the agent's summary of three
reviewers; a dropped reviewer or a dropped finding is invisible. Rejected
because it leaves the agent between the reviewers and koto.

*Alternative: verdict files on disk.* A file under the repository is what the
wip-hygiene rule forbids, and #557 already moved reviewer detail files to
`mktemp` paths outside the repository for that reason. A file outside the
repository is invisible to koto's context log. Rejected.

*Alternative: rely on the retry loop's key clearing.* The phase files already
remove the panel keys before a retry. That clearing warns and continues when a
removal fails, and `finalization: issues_found` and a failed verification also
loop back to `implementation` without it. Rejected as the only guard; the
head stamp makes clearing a tidiness step rather than a safety one.

### Decision 5: What a finding's rule_id is

**Chosen: a stable name as the `rule_id`, and the source location as the
`rule_ref`.** Each rule a gate script can report gets a name of the form
`<area>/<rule>` (for example `pr-body/no-ai-trailer`), chosen so a later rule
registry can adopt it unchanged. Once a name has been emitted it never
changes; a rule whose meaning changes gets a new name. Each gate script
carries a small rule table: one row per rule, holding the name, the
source-location key (`<path>#L<start>-L<end>`), the commit the key is exact
at, and a short excerpt. Findings print the name as `rule_id` and the key as
`rule_ref`, written `<path>#L<start>-L<end>@<12-char commit>`, the slot koto's
finding shape gives an opaque pointer to the rule's text. A test re-resolves
each excerpt inside its referenced range at `HEAD` and fails when an edit
moves the text, so a stale reference is caught by CI; the fix updates the
`rule_ref` and leaves the `rule_id` alone.

*Alternative: the source-location key as the `rule_id`.* Precise and free of
naming decisions, and it breaks the one thing a rule id is for: any edit that
shifts lines renames the rule, and a different rule can later inherit the same
range, so per-rule counts from two template versions stop lining up without
anyone noticing. Rejected.

*Alternative: the PB codes and invented short codes (`PB3`, `OG1`).* Short,
but the PB codes exist only inside one reference, the other rules have none,
and opaque codes don't tell a reader of the event log what failed. Rejected;
the PB code stays in the finding's message.

*Alternative: let koto's default rule_id stand (the gate's name).* Free, and
too coarse: a failing commit walk would say nothing about whether a subject or
a trailer broke the rule. Rejected.

### Decision 6: The koto version the design needs

**Chosen: route on 0.14.1; name the first release after 0.14.1 that contains
koto#290 and koto#292 as the floor for findings, attempt counts and gate
polling.** Every transition in this design tests an exit code, a context match
or a context key, which 0.14.1 supports, so the build can land and route
correctly today. On 0.14.1 a failed gate's output is discarded, so each
directive keeps the existing instruction to run the gate script for the
reason. When that release is installed, the same scripts' finding lines reach
the `failure` object and the event log with no template change, and
`scripts/assert-koto-floor.sh` takes its version number then. The feature
requests no release.

Runs on 0.14.1 contribute no per-rule data: koto records no findings and no
`rule_counts` there, so a failing gate is visible only as a failed
`gate_evaluated` with its exit code. Any per-rule figure (how often
`commit/no-ai-trailer` fires, before and after a template change) counts only
runs on the release that carries koto#290.

*Alternative: require the next release outright.* Cleaner events from day one,
and a build blocked on a schedule this feature doesn't own. Rejected.

### Decision 7: A public-content gate in /work-on and single-PR /execute

**Chosen: no such gate in this feature.** The shipped marker check (a
`private/` path component or a `Repo Visibility: Private` line) runs in
`node-push.sh` only when a private home drives a public node, and in
`publish-scoping-pr.sh` only over `wip/` files. Run over every commit and
added line of a public repository, it fires on shirabe itself: the skills and
references that document the visibility rule contain both markers, and so
does this design. A gate that holds every shirabe run until a person
overrides it breaks D8 and trains overrides. The coordinated path keeps its
check, unchanged.

*Alternative: run the marker grep everywhere with an allowlist.* Makes the
gate usable in shirabe, but an allowlist of files that may name the markers is
a second rule to maintain, and the check still says nothing about private
names, which is the leak that actually happens. Rejected.

*Alternative: gate on the review-shadow trial's private-name criterion.* The
trial checks private names against a terms file kept outside every
repository, which is the right shape. It is still in its trial and needs a
terms file the worker may not have. Deferred: when the trial settles it, it
belongs in the decider slot or a command gate beside the panels.

The leak class is not unchecked in the meantime: the trial's private-name
criterion (`rs-002`) already runs on every pull request before its pre-merge
panel, so private names are caught, just later than the state that produced
them.

This decision covers the marker grep only. `shirabe validate --visibility`,
which checks documents against the repository's declared visibility, is a
different check and gets a gate (Decision 8).

### Decision 8: Checking documents against the repository's visibility

**Chosen: a gate that runs `shirabe validate --visibility=<declared> --format
json` over the documents the branch changed under `docs/`, and counts only the
visibility-gated codes.** The validator already resolves visibility from the
repository's `CLAUDE.md` header, and its visibility-gated checks are R7
(prohibited VISION sections in a public repository), R8 (prohibited STRATEGY
sections in a public repository) and R9 (a private-only artifact type, such as
COMP, outside a private repository), per `crates/shirabe-validate/src/visibility.rs`
and `docs/guides/doc-validation.md`. The gate passes the changed `docs/**/*.md`
files, a finding with one of those codes is a violation, and every other code
is left to the `validate-docs` workflow that already runs in CI, so the gate
doesn't turn a formatting nit into a held run. It fires on neither shirabe's
skills nor its references, because it only reads documents under `docs/` and
only the three codes. It runs in the states that present the branch's
documents: /work-on's `pr_precheck` and /execute's `pr_finalization`.

One case it can't catch: a public document whose `upstream:` names a private
artifact in another repository. The validator resolves nothing for a
cross-repo value, so such a document validates clean, as /scope's Phase 0
reference already records; the skills that write `upstream:` check it at
authoring time, and this gate adds nothing there.

*Alternative: run the whole validator over changed documents.* One more set of
codes caught before CI, and a gate that holds a run for a missing section or a
status mismatch the author is already told about in CI. Rejected as scope
beyond visibility.

*Alternative: leave it to CI.* This is what happens today, and it is the
"settled after a reviewer sees it" case D1 exists to remove. Rejected.

## Decision Outcome

Four gate scripts and a runner, all under `skills/work-on/scripts/` so both
templates reach them through `{{PLUGIN_ROOT}}`, share one exit convention:
**0** the output passes, **1** at least one finding, **2** the check could not
decide (a usage error, a missing tool, a read that failed). Each prints
`::koto-finding::` lines on stdout for its findings and a human line on
stderr.

| Script | Shipped or new | Calls |
|---|---|---|
| `check-pr-output.sh` | new, wrapper | `--pr-body`: `shirabe validate --pr-body <tmp> --pr-title <title> --format json`, unchanged, mapping its 0 to 0, 2 to 1, and 1, 3, 4 to 2. `--owned-pr`: `owned-pr.sh`, unchanged, mapping one URL to 0, empty output or 3, 4, 5 to 3, and 2, 64 or a timeout to 2 |
| `check-branch-output.sh` | new | `--commits`: the shipped `commit_convention` regex over every non-merge commit in a range, plus a new AI-trailer check; `--wip`: the shipped `git ls-tree -r --name-only HEAD -- wip/` |
| `check-panel-verdict.sh` | new | reads the panel's per-reviewer koto keys |
| `run-verification.sh` | new | the committed map's commands, in a bounded detached runner |
| `check-verification.sh` | new | reads the runner's on-disk result for the current head |

`session-role.sh`, `check-staleness.sh`, `owned-pr.sh`, `run-cascade.sh` and
`shirabe validate --pr-body` ship today and are called exactly as they ship,
with one addition: `run-cascade.sh --session` already records the pushed head
in koto context, and it also records its JSON verdict there as
`cascade_result.json`. The AI-trailer check is the one new rule
implementation: no shipped check reads commit trailers. It uses the same
predicate PB3 applies to a body (`crates/shirabe-validate/src/pr_body.rs`,
`is_attribution_line`): a `Co-Authored-By:` line naming Claude or Anthropic,
or a "Generated with Claude Code" line.

## Solution Architecture

### Gate inventory

Every gate below routes on an exit code or a context match. "Hold" means no
transition matches, so the run stays in the state with the failing gate
named, and the agent fixes the output and ticks again, the pattern
`finalization` already uses.

| # | Skill and state | Gate | Command | Route |
|---|---|---|---|---|
| 1 | work-on `finalization`, `deferral_approval` | `commit_convention` (command changes, name kept) | `check-branch-output.sh --commits --session {{SESSION_NAME}}` over `impl_base..HEAD` | hold on 1 or 2, like the other early checks there |
| 1b | work-on `pre_pr_evidence` | `commit_convention` (same) | same | backstop: 1 and 2 to `done_blocked`, as the ladder routes the tip check today |
| 2 | work-on `pr_precheck` | `branch_wip_clean` | `test -n "{{SHARED_BRANCH}}" \|\| check-branch-output.sh --wip` | hold on 1 or 2 |
| 3 | work-on `pr_creation` | `pr_body_conformant` | `check-pr-output.sh --pr-body` (the branch's PR) | hold on 1 or 2 |
| 4 | work-on `verification` | `verification_settled` | `check-verification.sh --settled --session {{SESSION_NAME}}` | 0 to `verification_verdict`; polled |
| 5 | work-on `verification_verdict` | `verification_passed` | `check-verification.sh --verdict --session {{SESSION_NAME}}` | 0 `finalization`, 1 `implementation`, 3 and 4 `done_blocked`, 2 hold |
| 6 | work-on `scrutiny` | `scrutiny_verdict` | `check-panel-verdict.sh --panel scrutiny --session {{SESSION_NAME}}` | 0 `review` (with `has_commits`), 1 agent decides retry or escalate, 2 hold |
| 7 | work-on `review` | `review_verdict` | `check-panel-verdict.sh --panel review ...` | 0 `qa_validation`, 1 agent decides, 2 hold |
| 8 | work-on `qa_validation` | `qa_verdict` | `check-panel-verdict.sh --panel qa ...` | 0 `verification`, 1 agent decides, 2 hold |
| 9 | work-on `ci_monitor` | `is_root` | `test "$(session-role.sh {{SESSION_NAME}})" = root` | with green CI: 0 `cascade_entry`, 1 `done` |
| 10 | work-on `staleness_check` | `staleness_fresh` (existing) | unchanged | 0, 3 and -1 `analysis`, 1 `introspection`, with no evidence |
| 11 | execute `orchestrator_setup` | `setup_owned_pr` | `check-pr-output.sh --owned-pr ...` after the agent runs `adopt-or-create-pr.sh` | 0 `settled_branch_record`, 3 `pr_adopt` terminal, 2 `status_read` terminal |
| 12 | execute `pr_finalization` | `final_owned_pr` | `check-pr-output.sh --owned-pr ...` | 3 and 2 to the `pr_adopt` and `status_read` terminals |
| 13 | execute `pr_finalization` | `owned_pr_body_conformant` | `check-pr-output.sh --pr-body --owned` (resolves the PR itself) | hold on 1 or 2 |
| 14 | execute `pr_finalization` | `settled_commits` | `check-branch-output.sh --commits --base-ref origin/<default>` | hold on 1 or 2 |
| 15 | execute `pr_finalization` | `settled_wip_clean` | `check-branch-output.sh --wip` | hold on 1 or 2 |
| 16 | execute `plan_completion` | `cascade_completed`, `cascade_skipped`, `cascade_partial` | context matches on `cascade_result.json`'s `cascade_status` | completed or skipped to `ci_monitor`; partial holds, as the directive already halts it |
| 17 | execute `plan_completion` | `ready_owned_pr` | `check-pr-output.sh --owned-pr ...` | 3 and 2 to the terminals |
| 18 | execute `ci_monitor` | `owned_ci_passing`, `owned_merge_state_clean` (existing), `monitor_owned_pr` (new) | unchanged, plus the lookup | green: `merge_readiness` with no evidence; DIRTY: `escalate_dirty_merge_state`; lookup 3 or 2: terminals |
| 19 | execute `worktree_sync` | the ancestry gate #545 lands | `git merge-base --is-ancestor origin/main HEAD` and no `MERGE_HEAD` | unchanged routing; a failure gains a finding line when the gate moves into `check-branch-output.sh --synced` |

Gate names differ between the templates, and between states with different
arguments, because `validate-template-mermaid.sh` check 4 holds one gate name
to one command across templates.

The commit walk skips merge commits (`git log --no-merges`), since a branch
catches up with main by merging it in and a merge commit's subject is git's,
not the author's.

A /work-on child on /execute's shared branch opens no pull request of its own
(`pr_status: shared`), so gate 2 passes for it and /execute's gate 15 checks
the shared branch once, before the pull request is finalized. The commit walk
(gate 1) still runs per child over that child's own `impl_base..HEAD`.

### Copied verdicts, before and after

| State | Before: the agent submits | After |
|---|---|---|
| work-on `staleness_check` | `staleness_signal: fresh`, `stale_requires_introspection` or `unavailable`, restating `check-staleness.sh`'s exit 0, 1 or 3 | Transitions route on `gates.staleness_fresh.exit_code` alone, including -1; `staleness_signal` keeps only `override` and `blocked` |
| work-on `scrutiny`, `review`, `qa_validation` | `*_outcome: passed`, gated only on a results key existing; the key holds `passed` and `blocking_count` the agent wrote | The verdict gate's exit 0 advances with no evidence; `*_outcome` keeps `blocking_retry` and `blocking_escalate`, accepted only on exit 1 |
| work-on `verification` | `verification_outcome` and a free-text `commands_run` | koto starts the map's commands (`verification`) and routes on the result (`verification_verdict`); the only evidence left is `verification_status: blocked` with `detail`, for a runner that can't start, and `rerun` once per head on a failure |
| work-on `ci_monitor` | `session_role: root` or `child`, copied from `session-role.sh`; `ci_outcome: passing` next to green gates | `is_root` decides the role; green CI routes with no evidence; `ci_outcome` keeps `failing_fixed` and `failing_unresolvable` |
| execute `orchestrator_setup` | `status: completed`, `pr_adopt` or `status_read`, restating `adopt-or-create-pr.sh`'s result | `setup_owned_pr` routes all three; `status` keeps `override` and `blocked` |
| execute `pr_finalization` | `finalization_status: pr_adopt` or `status_read`, restating `owned-pr.sh`; `updated`, restating `gh pr edit` | `final_owned_pr` routes the lookup; the output gates (13 to 15) passing is what "updated" meant; `finalization_status` keeps `update_failed` |
| execute `plan_completion` | `cascade_status: completed`, `partial` or `skipped`, copied from `run-cascade.sh`'s JSON; `pr_adopt` or `status_read`, restating `owned-pr.sh` | Gates on `cascade_result.json`, which the script records itself, and `ready_owned_pr` route all five; the agent submits only `cascade_detail` |
| execute `ci_monitor` | `ci_outcome: pr_adopt`, `status_read`, restating `owned-pr.sh`; `dirty_merge_state`, restating `mergeStateStatus`; `passing` next to green gates | Gates route all four; `ci_outcome` keeps `failing_fixed`, `pending` and `failing_unresolvable` |

`pause_decision` in /execute's `pr_finalization` copies the
`PAUSE_BEFORE_FINALIZE` variable rather than a script. Routing on a variable
needs koto#296, which is also unreleased; it is proposed as follow-up work, not
built here.

### Verification

The map, `.claude/shirabe-extensions/verification-map.json`:

```json
{
  "schema": "shirabe-verification-map/v1",
  "commands": {
    "cargo-test": {"run": ["cargo", "test", "--workspace"], "timeout_secs": 1200},
    "evals": {"run": ["scripts/run-evals.sh"], "each": "skills/*", "timeout_secs": 1800,
              "network": true, "unattended": true}
  },
  "entries": [
    {"paths": ["skills/**"], "commands": ["evals"]}
  ],
  "default": ["cargo-test"]
}
```

- `run` is an argv array, executed from the repository root with no shell.
- `each`, when present, runs the command once per distinct changed directory
  matching that pattern, with the directory's last component appended as the
  final argument. It is how `scripts/run-evals.sh <skill>` is expressed.
- `timeout_secs` defaults to 1800 and may not exceed 3600.
- `network` defaults to `false`. A command that reaches the network says so.
- `unattended` says whether koto may start the command with no person
  present. It defaults to `true` for a command with `network: false`, and has
  no default for a networked one: a map that marks a command `network: true`
  and omits `unattended` doesn't parse. A command marked `unattended: false`
  is never started by koto.
- `max_procs` defaults to 256.

Selection is additive, as the schema reference already says: every entry
whose globs match a changed path contributes its commands, and changed paths
no entry matches add the `default` list. The changed paths are
`git diff --name-only <merge-base>..HEAD`, computed by the runner, not read
from the truncated `changed_paths.txt`. The runner refuses a working tree with
uncommitted changes to tracked files, since the paths it selects on and the
code it tests would then differ.

`run-verification.sh --start --session <s>` does this, and always returns
within a second:

1. Resolve `HEAD`, the merge-base with the default branch, and the run's
   attempt number for this head (0, or 1 after one `rerun`, read from koto
   context, which an action may read). If a result for this head and attempt
   exists, exit 0.
2. Read the map at the merge-base. If it is absent or doesn't parse, write a
   `no-map` or `bad-map` result and exit 0.
3. Select commands. If any selected command is `unattended: false`, write an
   `attended` result naming them and exit 0. If nothing is selected, write a
   `no-map` result, since the map declares nothing for this change.
4. If a lock for this head and attempt names a live supervisor, exit 0. A lock
   whose process is gone is removed.
5. Start the supervisor detached, with standard input from `/dev/null`, both
   outputs to its log, and koto's inherited tick marker cleared from its
   environment, and exit 0.

The supervisor never calls koto. It runs each command in turn in its own
process group, with its own deadline and, when `systemd-run --user --scope`
works on the host, inside a scope with `TasksMax=<max_procs>`. Where it
doesn't, a watchdog counts the processes in the command's process group every
second and kills the group when the count exceeds `max_procs`. It uses job
control and a sleep loop rather than GNU `timeout` or `setsid`, which the
macOS floor lacks. Each command's output goes to a log under
`${XDG_STATE_HOME:-$HOME/.local/state}/shirabe/verification/<session>/<head>-<attempt>/`,
in directories created with mode 0700 and pruned to the last ten heads per
session, outside every repository. The result, one JSON object with the head,
the attempt, and each command's id, exit status, duration, and whether it timed
out or was killed for runaway growth, is written atomically beside the logs.

`check-verification.sh --settled` exits 0 when the result file for the current
head and attempt exists. `--verdict` reads it, and the `verification_verdict`
state's own `default_action` (`check-verification.sh --record`) copies it into
koto context as `verification_results.json` for the audit trail, from inside a
tick:

| Exit | Meaning | Route |
|---|---|---|
| 0 | every selected command passed | `finalization` |
| 1 | a command failed | `implementation`, or back to `verification` on `verification_status: rerun`, accepted once per head |
| 3 | no verification map, or a map that selects nothing | `done_blocked`: "no verification map" |
| 4 | a command needs a person, timed out, was killed for runaway growth, could not start, or the tree was dirty | `done_blocked`, naming which |
| 2 | the result could not be read | hold |

The `verification` state polls with `interval_secs: 15` and
`timeout_secs: 480`. `koto next` polls inside one call, so the window is kept
under the ten minutes an agent's tool call can wait. When it expires with the
runner still going, the fallback text tells the agent to tick again: koto
re-runs a state's action on every tick that carries no evidence, the launcher
finds its own running supervisor and returns, and polling resumes. The
runner's per-command deadlines, not koto's window, end a slow run, so a long
suite costs the agent a few ticks rather than a verdict.

A repository without the file is refused, never passed, which means every
repository that adopts this release stops at verification until it commits a
map. That is the intended reading of R8; the plan lands shirabe's own map
before the gate so shirabe's runs keep working.

### Panels

Each reviewer writes one key, `<panel>.<focus>.json`:

```json
{"schema": "shirabe-panel-verdict/v1", "panel": "scrutiny", "focus": "completeness",
 "head": "<40-char sha the reviewer read>", "round": 1,
 "findings": [{"severity": "blocking", "message": "...", "path": "src/x.rs", "line": 12}]}
```

`severity` is `blocking` or `advisory`. The gate passes when all of the
panel's keys are present, parse, name the current `HEAD`, and none holds a
blocking finding. A missing or stale key is exit 2, so a panel with a reviewer
that never reported, or reported on an older head, holds rather than passes.
The retry loop's key-clearing list (the `for KEY in ...` blocks in the three
panel phase files and `phase-4-implementation.md`) names the per-reviewer keys
in place of the three aggregate keys. Detail files stay where #557 put them,
in `mktemp` paths outside the repository.

**The decider slot.** Each panel state is where a later `decider-check` gate
goes, named `<panel>_decider`, in `mode: shadow`. It carries the trial's
model-graded criteria from `scripts/review-shadow/criteria.json` under the
same rule ids (`rs-007` to `rs-010`, four, which is koto's limit per state),
with the trial's `pr-summary`, `doc-pairs` and `code-hunks` slicers as its
extraction commands. The trial's script-observed criteria (`rs-001` to
`rs-006`) are command checks, not decider criteria, and stay in the trial.
koto forbids any `when` clause, `skip_if` or context assignment from reading a
decider check's output, and a shadow check never blocks, so adding it can't
change which transition a panel takes. It needs a koto release carrying
koto#294 and is not built here.

The existing `override_default` on the panels' gates stays, in an exit-code
form, so a person's override remains the only way past a panel gate and is
listed by `koto overrides list`, as it is today.

### Mapping to koto's gate events

Every gate in the inventory is a `command` gate or a `context-matches` gate,
and the verification launcher and recorder are `default_action`s. They produce
koto's existing events and no field of their own:

| Gate kind | Event | What koto records on 0.14.1 | What the release carrying koto#290 and koto#292 adds |
|---|---|---|---|
| command and context gates (1 to 19) | `gate_evaluated` | gate name, state, pass or fail, exit code or match | `attempt`, `visit_attempt`, `findings`, per-rule `rule_counts` on failure, duration, 4 KiB of failed streams; a `failure` object on the `koto next` response |
| verification launcher and recorder | `default_action_executed` | command, exit code, both streams | the same attempt fields; context reads and writes logged with their writer |
| `verification_settled` under polling | `gate_evaluated` per re-evaluation | pass or fail | with the gate moved to `poll:`, a pending result without attempt stamps |
| decider slot (later, koto#294) | `decider_checked` | not available | the criterion's `rule_id` and verdict |

Each finding line's `rule_id`, at the design's base commit a916ccc (the build
re-pins them at its own base, and the excerpt test keeps them honest):

| Gate | Finding | rule_id key |
|---|---|---|
| 1, 1b, 14 | subject not a Conventional Commits subject | `references/pr-body-conformance.md#L40-L44` (the type list and non-empty description; the issue-number scope rule at L45-L50 is not what the subject regex checks) |
| 1, 1b, 14 | AI-attribution trailer on a commit | `references/pr-body-conformance.md#L57-L60` |
| 2, 15 | a path under `wip/` in the tree | `references/wip-hygiene.md#L14-L16` |
| 3, 13 | PB1, PB2, PB3, PB4 | `references/pr-body-conformance.md` `#L40-L50`, `#L51-L56`, `#L57-L60`, `#L61-L75`, chosen by the validator's message; an unrecognized message takes the whole gated section, `#L34-L80` |
| 5 | a command failed, timed out, needs a person, or no map | `skills/work-on/references/verification-map.md#L28-L44` |
| 6, 7, 8 | a blocking finding, or a missing or stale reviewer key | `skills/work-on/references/phases/phase-4a-scrutiny.md#L29-L34` and the matching lines of `phase-4b-review.md` and `phase-4c-qa.md` |
| 4, 9 to 12, 16 to 18 | routing gates, no violation | none; koto's default finding (the gate name) covers a script that could not run |
| 19 | `origin/main` not merged in, or a merge in progress | the line #545 settles in `execute.md` |

Every key is written `@<12-char commit>` in the finding's `rule_id`, and the
finding's `rule_ref` is the permalink at that commit.

### What waits on the contradiction-settlement work

Gates that read a rule #507 settles wait on that rule only. Status is as read
at a916ccc.

| Gates | Rule they wait on | Where it lands | Status |
|---|---|---|---|
| 6, 7, 8 (panels) | where reviewer detail files live versus wip hygiene | #557 | merged: detail files are `mktemp` paths outside the repository |
| 6, 7, 8 (panels) | the retry cap that bounds the panel loop | #531 (decision), #557 (applied) | merged: 2 blocking retries, shared by the three panels, stated in each panel's directive |
| 19, and the gates around `worktree_sync` | merge main in, never rebase, with ancestry tests | #545 | open |
| 9 (work-on `ci_monitor`) | a fixed CI failure loops back rather than ending unverified | #557 | merged |
| 18 (execute `ci_monitor`) | the same rule for /execute | #545 | open |
| 3 (work-on PR body) | PR-body conformance sections restored | #557 | merged |
| 11 to 17 (execute PR output) | /execute's PR-title type | #545 | open |
| 4, 5 (verification) | whatever #507 settles about the verification map's wording | #557 for /work-on's items | merged; the build re-reads the wording at its base |

Everything else (gates 1, 1b, 2 and 10) depends on no unsettled rule. All of
it builds after #545 merges, because both features edit the same skill files.

## Implementation Approach

The build proceeds in this order, each step a single pull request's worth:

1. **Gate script library.** `check-branch-output.sh` and `check-pr-output.sh`
   with their rule tables, `_test.sh` suites using fixture repositories and a
   fake `gh`, `shirabe` and `owned-pr.sh` on `PATH`, and the excerpt test for
   rule keys.
2. **shirabe's own verification map.** Commit
   `.claude/shirabe-extensions/verification-map.json` equivalent to today's
   Markdown map, document the schema in `verification-map.md`, and change the
   Markdown section to point at the file. This lands on main before step 4 so
   shirabe's own runs find a map at their merge-base.
3. **Verification runner.** `run-verification.sh` and `check-verification.sh`,
   with tests that show the gate going red: a failing command gives 1, a
   command that forks past `max_procs` gives 4, a timeout gives 4, a missing
   map gives 3, a dirty tree gives 4, and a map edited on the branch is
   ignored. One test drives the launcher from inside a real `koto next` tick.
4. **work-on output gates.** Gates 1 to 5, 9 and 10, and the new
   `verification` and `verification_verdict` states, with the evidence values
   removed as the before-and-after table says, and the directives updated to
   name the gate scripts.
5. **work-on panel gates.** `check-panel-verdict.sh`, gates 6 to 8, the
   per-reviewer keys in the three phase files, and the retry-clearing lists.
6. **execute output gates.** Gates 11 to 19 and the `cascade_result.json`
   record in `run-cascade.sh`, after #545 merges.

The template tests that exist (`pre-pr-evidence_test.sh`,
`finalization-shape_test.sh`, `ci-monitor-role_test.sh`,
`execute-template-structure_test.sh`) gain cases for each new route, driven
by fake gate results in the way they already are.

## Security Considerations

**The verification runner executes repository code unattended.** It already
does today, through the agent; what changes is that koto starts it, outside
whatever permission or sandbox layer the agent's harness applies to its own
commands. The map is read from the default branch at the merge-base, so a pull
request can't add a command to, or remove one from, the list that verifies
it. The suites those commands run come from the branch, and a change can still
weaken a test it is judged by; that residual is #384's and stays open.
Commands run as argv, never through a shell, from the repository root. A
networked command must be marked `unattended` explicitly, and one marked
`false` is never started. Process growth is bounded by `TasksMax` where the
host supports a user scope and by a watchdog elsewhere. The watchdog is a
one-second poll over one process group, so a fork storm can overshoot the
limit briefly, and a descendant that starts its own session escapes the count.
Both residuals are stated in the map schema.

**Logs stay out of the repository.** Runner logs go under the user's state
directory in 0700 directories, keyed by session and head and pruned, never
into the work tree, so they can't be committed or reach a pull request.

**Gate inputs are data.** The PR title reaches `shirabe validate` as one
quoted argument and the body as a file, the same injection-safe handling
`pr-body.yml` uses. Nothing a PR or commit contains is evaluated.

**No list of private names enters the repository.** This design adds no
private-content check (Decision 7), and nothing it adds carries such a list in
any form.

**Credentials.** On koto 0.14.1 a command inherits the whole environment of
`koto next`, so a map command sees every token the agent's shell holds, as it
does today when the agent runs it. On koto's main, commands start in a cleared
environment and a networked command's key has to be named in the template's
`pass_env`; the verification state's `pass_env` names the eval runner's key
variable and nothing else. Nothing in the runner prints its environment, and
logs hold only the commands' own output.

## Consequences

**Positive.** Every mechanical verdict in the two skills is decided by a
check, in the state that produced the output, and the agent stops answering
questions a script already answered. A malformed PR body, a non-conforming or
attributed commit, or a stray `wip/` file stops the run before a reviewer sees
it. Verification can no longer pass on a sentence, and a repository without a
map is told so. Panel verdicts reflect every reviewer's findings on the head
that ships. Once koto's next release is installed, each failure names its rule
in the event log with no further change.

**Negative.** Every repository stops at verification until it commits a
machine-readable map, which is a real adoption cost. A new suite added in a
pull request doesn't verify that pull request. The panels' reviewers each
write a koto key stamped with the head, one more step in each reviewer's
instructions. The gate scripts duplicate a little plumbing (reading a range,
fetching a PR) that a later `shirabe validate` mode would own. On 0.14.1 a
failing gate's reason still has to be read by running the script. Private
content in a single-PR run is still caught only by review and by the trial.

**Mitigations.** The plan lands shirabe's own map first, and the refusal
message names the file and schema a repository needs. The gate scripts are
small and tested, and each one's rule table is the input a rule registry
would need. The directive's "run the script for the reason" line is deleted
when the floor moves to the release that carries koto#290.
