---
schema: design/v1
status: Planned
problem: |
  /work-on and /execute take the agent's word for verdicts that shipped checks
  can decide: whether the pull request title and body conform, whether every
  commit follows the convention, whether wip/ files or visibility-restricted
  documents reach a pull request, whether verification passed, whether a review
  panel found anything blocking, and several script results the agent copies
  into answer fields. The checks exist, but they run in CI, on one path only,
  or not at all, so a wrong copy passes and a failure names no rule.
decision: |
  Add command gates to the two templates, in the states that produce each
  output, that run shirabe's shipped checks through small gate scripts with
  one exit convention (0 pass, 1 finding, 2 could not decide) and koto's
  ::koto-finding:: lines carrying a stable rule name as rule_id and the rule's
  source location as rule_ref. Remove every answer value that restated a
  script's result and route on a gate instead. Verification runs the
  repository's committed, machine-readable map in a bounded, detached runner
  that a polling gate waits on, and refuses a repository with no map. Panel
  gates recompute pass from the findings recorded in the panels' verdict
  ledger, and each panel state names the slot for a later shadow decider check.
rationale: |
  koto 0.15.0, already shirabe's floor, records findings, attempt counts and
  per-rule counts, waits on a polling gate, and routes on a template variable,
  so every gate here works on the koto shirabe requires and the feature asks
  for no release. Wrapping the shipped checks, rather than reimplementing them,
  keeps one rule per check. A detached runner is the only way a 30-second
  command limit can run suites that take minutes, and reading the map from the
  default branch keeps a change from choosing its own verification. Building
  the panel gate on the ledger the panels already keep puts koto, not the
  agent, between each reviewer's findings and the pass.
upstream: docs/prds/PRD-output-gates.md
---

# DESIGN: Output Gates

## Status

Planned

## Context and Problem Statement

/work-on and /execute each run as a koto workflow. koto evaluates gates (a
command's exit status, whether a context key exists or matches a pattern) and
routes on them; anything a gate doesn't decide, the agent submits as evidence.
The requirements (docs/prds/PRD-output-gates.md) ask that every verdict a
shipped check can decide be decided by a gate, in the state that produces the
output, and that every answer value restating a script's result go away.

The checks this design uses, as they ship on main:

| Check | Where it ships | How it is called today | Exit convention |
|---|---|---|---|
| PR title and body conformance (PB1 to PB4) | `shirabe validate --pr-body <file> --pr-title <title>` (`crates/shirabe/src/main.rs`) | `.github/workflows/pr-body.yml`, after the PR opens | 0 clean, 1 tool error, 2 violations, 3 I/O, 4 incomplete |
| Documents against the repository's visibility (R7, R8, R9) | `shirabe validate --visibility=<v> <files>` | `.github/workflows/validate-docs.yml`, after the PR opens | the same |
| Conventional Commits subject | the `commit_convention` gate regex in `work-on.md` | `pre_pr_evidence`, tip commit only | grep status |
| No `wip/` in the pushed tree | `git ls-tree -r --name-only <sha> -- wip/` in `skills/execute/scripts/node-push.sh` | coordinated /execute only | empty output means clean |
| Panel seat verdicts | `skills/work-on/scripts/panel-scope.sh` and its `verdict_ledger.json` | the agent records each round; a seat is blocking when the agent's `blocking_count` is above 0 | per mode |
| Session role | `skills/work-on/scripts/session-role.sh` | the agent runs it and copies the word | prints `root` or `child`, failing safe to `child` |
| Staleness | `skills/work-on/scripts/check-staleness.sh` | a gate, and the agent restates it | 0 fresh, 1 stale, 3 unavailable |
| Owned-PR lookup | `skills/execute/scripts/owned-pr.sh` | the agent runs it and copies the result | 0 with one URL, 0 with empty output (none), 2 read failure, 3 several, 4 ambiguous, 5 another run's, 64 usage |
| Cascade verdict | `skills/work-on/scripts/run-cascade.sh --push --session` | the agent runs it and copies `cascade_status` from its JSON | JSON verdict `completed`, `partial` or `skipped` |
| Verification map | a Markdown list in `.claude/shirabe-extensions/work-on.md` | the agent reads, selects, runs and reports | none |

koto 0.15.0 is shirabe's floor (`scripts/assert-koto-floor.sh`). It carries
koto#290 (a failed check's findings, attempt counts and per-rule counts on
`gate_evaluated`), koto#292 (a `poll:` command gate and stale-key clearing),
koto#294 (decider checks that can only veto) and koto#296 (routing on a
template variable). It runs each command for at most 30 seconds, in an
environment cleared at session creation except for the names a template lists
in `pass_env`.

## Decision Drivers

- **D1. Settle the verdict where the output is made.** A gate in CI settles it
  after a reviewer has seen the pull request; a gate in the producing state
  settles it before.
- **D2. Call checks as they ship.** A gate that reimplements a check creates a
  second rule that can drift from the first.
- **D3. No koto change and no release request.** Everything has to work on
  koto 0.15.0.
- **D4. Remove copied verdicts, keep judgment.** Where a script decides, the
  agent stops answering. Where only judgment decides (retry or escalate after
  a blocking finding, whether a fix was pushed), the agent still answers.
- **D5. Verification is chosen by the base, bounded, and readable.** The
  change being judged can't choose its own commands, a runaway suite is
  stopped by process count and not only by time, and a failure leaves logs a
  person can read (the constraints in #384).
- **D6. No pass skips a panel.** Every gate this design adds can only stop a
  run or send it back; none can advance past a panel whose seats haven't
  judged the current head.
- **D7. Per-rule data that survives edits.** A rule's id has to stay the same
  across template versions, so before-and-after counts line up.
- **D8. No false positives on shirabe itself.** A gate that fires on content
  the repository legitimately carries holds every run in that repository and
  teaches people to override it.

## Considered Options

### Decision 1: How a gate reaches a shipped check

**Chosen: thin gate scripts that call the shipped check and translate its
result.** Each script fetches the input (a PR's title and body, a commit
range, the changed documents), calls the check unchanged, prints one
`::koto-finding::` line per violation, and exits 0, 1 or 2. The shipped check
keeps its own flags, output and exit codes.

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

**Chosen: a detached, bounded runner started by the state's default action,
and a `poll:` gate that waits on its result.** The `verification` state's
`default_action` runs `run-verification.sh --start`, which returns within a
second: it either finds a result for the current head, or starts a supervisor
that runs the selected commands and writes a result to disk. The state's
`verification_verdict` gate runs `check-verification.sh --verdict`, which exits
75 (koto's default pending code) until the result exists and then exits with
the verdict. koto re-runs it every 15 seconds for up to `hold_secs: 480` of one
`koto next`, under the ten minutes an agent's tool call can wait, and reports
pending as a temporal, non-actionable condition; the agent ticks again and the
wait continues until `timeout_secs: 7200`. A pending evaluation counts no
attempt, so a long suite doesn't read as repeated failure.

*Alternative: a plain command gate per map command.* Simple, and exactly what
koto's 30-second limit forbids: `cargo test --workspace` takes minutes.
Rejected because it can't run the commands the map names.

*Alternative: let the agent run the commands and gate on a results file it
writes.* This is the current arrangement with a file instead of a string. The
agent still chooses the commands and reports the result. Rejected by R6.

*Alternative: a polling `default_action` and a separate verdict state.* The
shape a koto without `poll:` needs: the action re-runs on an interval until a
"settled" gate passes, and a second state routes on the verdict, because
polling continues until every gate in the state passes. It works, and it
spends a state and an extra gate on what `poll:` does in one, with pending
counted as failed evaluations. Rejected now that the floor has `poll:`.

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

### Decision 4: How a panel's pass is computed

**Chosen: a gate that reads the panels' verdict ledger and passes exactly
when no seat of the panel holds a blocking finding, with blocking derived from
each finding's severity.** The panels already keep a per-seat ledger,
`verdict_ledger.json`, through `panel-scope.sh`: each seat's verdict is stamped
with the commit it judged, a seat whose judgment the fix touched is rerun, and
the `<panel>_recorded` gate refuses a round whose spawned seats weren't
recorded. What the ledger still takes on the agent's word is the verdict
itself: a seat is blocking when the round file's `blocking_count` is above 0.

Two changes close that. `panel-scope.sh --record` requires each finding in the
round file to carry `severity: blocking` or `severity: advisory`, records a
seat as blocking exactly when one of its findings is `blocking`, and ignores
`blocking_count`, `passed` and any other summary field. A new mode,
`panel-scope.sh --verdict <panel> <session>`, is the panel's gate: exit 0 when
every seat of the panel has a recorded verdict and none is blocking, 1 when a
seat is blocking (printing one finding per blocking finding), 2 when the
ledger can't be read. The agent's `*_outcome: passed` and the
`*_results.json` existence gate go; `blocking_retry` and `blocking_escalate`
stay, for exit 1. The verdict lives where the ledger does, in koto context,
never in the repository and never in `wip/`; reviewer detail files stay in
`mktemp` paths outside the repository.

*Alternative: per-reviewer koto keys stamped with the head, read by a separate
script.* This design's first version, written before the ledger existed. It
duplicates what the ledger already records (who judged what, at which commit)
and would fight the ledger's carry and recheck logic, which decides when an old
verdict still counts. Rejected in favor of extending the ledger.

*Alternative: recompute from an aggregate key the agent writes.* The gate
could read `scrutiny_results.json` and count findings, but that file is the
agent's summary of the seats; a dropped seat or finding is invisible.
Rejected because it leaves the agent between the reviewers and koto.

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
anyone noticing. Rejected by D7.

*Alternative: the PB codes and invented short codes (`PB3`, `OG1`).* Short,
but the PB codes exist only inside one reference, the other rules have none,
and opaque codes don't tell a reader of the event log what failed. Rejected;
the PB code stays in the finding's message.

*Alternative: let koto's default rule_id stand (the gate's name).* Free, and
too coarse: a failing commit walk would say nothing about whether a subject or
a trailer broke the rule. Rejected.

### Decision 6: The koto version the design needs

**Chosen: koto 0.15.0, shirabe's current floor.** It carries every koto
feature the design uses: findings, attempt counts and per-rule `rule_counts`
on `gate_evaluated` (koto#290), the `poll:` gate (koto#292), decider checks
(koto#294) and variable routing (koto#296). The feature requests no release,
and every run on a supported koto contributes per-rule data.

*Alternative: route only on what 0.14.1 supports.* This design's first
version did, because 0.15.0 wasn't released yet. It cost a polling action and
an extra state for verification and left variable routing out. Rejected now
that the floor has moved.

### Decision 7: A public-content gate in /work-on and single-PR /execute

**Chosen: no marker-grep gate in this feature.** The shipped marker check (a
`private/` path component or a `Repo Visibility: Private` line) runs in
`node-push.sh` only when a private home drives a public node, and in
`publish-scoping-pr.sh` only over `wip/` files. Run over every commit and
added line of a public repository, it fires on shirabe itself: the skills and
references that document the visibility rule contain both markers, and so
does this design. A gate that holds every shirabe run until a person
overrides it breaks D8 and trains overrides. The coordinated path keeps its
check, unchanged.

The leak class is not unchecked: the review-shadow trial's private-name
criterion (`rs-002`) already runs on every pull request before its pre-merge
panel, against a terms file kept outside every repository, so private names
are caught, just later than the state that produced them.

*Alternative: run the marker grep everywhere with an allowlist.* Makes the
gate usable in shirabe, but an allowlist of files that may name the markers is
a second rule to maintain, and the check still says nothing about private
names, which is the leak that actually happens. Rejected.

*Alternative: move `rs-002` into the producing state.* The right shape, still
in its trial, and it needs a terms file a worker may not have. Deferred: when
the trial settles it, it belongs in the decider slot or a command gate beside
the panels.

### Decision 8: Checking documents against the repository's visibility

**Chosen: a gate that runs `shirabe validate --visibility=<declared> --format
json` over the documents the branch changed under `docs/`, and counts only
the visibility-gated codes.** The validator's visibility-gated checks are R7
(prohibited VISION sections in a public repository), R8 (prohibited STRATEGY
sections in a public repository) and R9 (a private-only artifact type, such as
COMP, outside a private repository), per
`crates/shirabe-validate/src/visibility.rs` and `docs/guides/doc-validation.md`.
The gate passes the changed `docs/**/*.md` files; a finding with one of those
codes is a violation, and every other code is left to `validate-docs`, which
already runs in CI, so the gate doesn't turn a formatting nit into a held run.
It fires on neither shirabe's skills nor its references, because it reads
only documents under `docs/` and only the three codes. It runs in the states
that present the branch's documents: /work-on's `pr_precheck` and /execute's
`pr_finalization`.

One case it can't catch: a public document whose `upstream:` names a private
artifact in another repository. The validator resolves nothing for a
cross-repo value, so such a document validates clean, as /scope's Phase 0
reference records; the skills that write `upstream:` check it when they write
it.

*Alternative: run the whole validator over changed documents.* One more set of
codes caught before CI, and a gate that holds a run for a missing section the
author is already told about in CI. Rejected as scope beyond visibility.

*Alternative: leave it to CI.* What happens today, and the "settled after a
reviewer sees it" case D1 exists to remove. Rejected.

### Decision 9: Keeping routing gates out of the violation counts

Some gates in this design decide a route rather than judge output: whether the
session is a root, which owned PR the run has, what the cascade reported,
whether the staleness check said fresh. Their non-zero exits are answers, not
violations. koto 0.15.0 has no way to say so: only `children-complete` and
request-leg gates are temporal (`gate_blocking_category` in koto's
`src/gate.rs`), and `build_failure` in `src/findings.rs` adds a koto-written
finding, `rule_id` set to the gate's name, to every failed command or context
gate that printed no `error` finding.

**Chosen: routing gates print no findings, and a koto-written fallback whose
`rule_id` is not a registered rule name is not a violation.** A consumer of
the event log counts a finding as a violation only when its `rule_id` is one of
the names in the gate scripts' rule tables. A fallback on a routing gate's
answer therefore counts toward no rule and no retry or loop cap. A fallback on
a `timed_out` or `error` outcome still counts, since the gate failed to answer
rather than answering. This is the interim rule; tsukumogami/koto#306 asks for
a gate-level declaration (`role: route`) so a routing gate writes no fallback
at all, and replaces it when it ships. The rule is applied by whatever counts
violations from the event log, not by the templates; what this feature
guarantees is its precondition, that no routing gate prints a finding.

*Alternative: make every routing gate exit 0 and route on a context key it
writes.* Avoids the fallback, but each branch then needs a context-matches
gate that fails on the branches not taken, which produces the same fallbacks
one level down. Rejected.

## Decision Outcome

Four gate scripts and a runner, all under `skills/work-on/scripts/` so both
templates reach them through `{{PLUGIN_ROOT}}`, share one exit convention:
**0** the output passes, **1** at least one violation, **2** the check could
not decide (a usage error, a missing tool, a read that failed). Each prints
`::koto-finding::` lines on stdout for its violations and a human line on
stderr.

| Script | Shipped or new | Calls |
|---|---|---|
| `check-pr-output.sh` | new, wrapper | `--pr-body`: `shirabe validate --pr-body <tmp> --pr-title <title> --format json`, unchanged, mapping its 0 to 0, 2 to 1, and 1, 3, 4 to 2. `--owned-pr`: `owned-pr.sh`, unchanged, mapping one URL to 0, empty output or 3, 4, 5 to 3, and 2, 64 or a timeout to 2 |
| `check-branch-output.sh` | new | `--commits`: the shipped `commit_convention` regex over every non-merge commit in a range, plus a new AI-trailer check; `--wip`: the shipped `git ls-tree -r --name-only HEAD -- wip/`; `--docs-visibility`: `shirabe validate --visibility=<declared> --format json` over changed `docs/**/*.md`, unchanged, counting only R7, R8 and R9; `--synced`: the ancestry test `worktree_sync` already runs |
| `panel-scope.sh` | shipped, extended | `--record` derives blocking from finding severity; new `--verdict` mode is the panel gate |
| `run-verification.sh` | new | the committed map's commands, in a bounded detached runner |
| `check-verification.sh` | new | reads the runner's on-disk result for the current head |

`session-role.sh`, `check-staleness.sh`, `owned-pr.sh`, `run-cascade.sh` and
`shirabe validate` ship today and are called exactly as they ship, with one
addition: `run-cascade.sh --session` already records the pushed head in koto
context, and it also records its JSON verdict there as `cascade_result.json`.
The AI-trailer check is the one new rule implementation: no shipped check
reads commit trailers. It uses the same predicate PB3 applies to a body
(`crates/shirabe-validate/src/pr_body.rs`, `is_attribution_line`): a
`Co-Authored-By:` line naming Claude or Anthropic, or a "Generated with
Claude Code" line.

## Solution Architecture

### Gate inventory

"Hold" means no transition matches, so the run stays in the state with the
failing gate named and its findings in the response, and the agent fixes the
output and ticks again, the pattern `finalization` already uses. "Routing"
marks a gate whose non-zero exit is an answer (Decision 9).

| # | Skill and state | Gate | Command | Route |
|---|---|---|---|---|
| 1 | work-on `finalization`, `deferral_approval` | `commit_convention` (command changes, name kept) | `check-branch-output.sh --commits --session {{SESSION_NAME}}` over `impl_base..HEAD` | hold on 1 or 2, like the other early checks there |
| 1b | work-on `pre_pr_evidence` | `commit_convention` (same) | same | backstop: 1 and 2 to `done_blocked`, as the ladder routes the tip check today |
| 2 | work-on `pr_precheck` | `branch_wip_clean` | `test -n "{{SHARED_BRANCH}}" \|\| check-branch-output.sh --wip` | hold on 1 or 2 |
| 3 | work-on `pr_precheck` | `branch_docs_visibility` | `test -n "{{SHARED_BRANCH}}" \|\| check-branch-output.sh --docs-visibility --session {{SESSION_NAME}}` | hold on 1 or 2 |
| 4 | work-on `pr_creation` | `pr_body_conformant` | `check-pr-output.sh --pr-body` (the branch's PR) | hold on 1 or 2 |
| 5 | work-on `verification` | `verification_verdict` (`poll:`) | `check-verification.sh --verdict --session {{SESSION_NAME}}` | 0 `finalization`, 1 `implementation`, 3 and 4 `done_blocked`, 75 waits, 2 holds |
| 6 | work-on `scrutiny`, `review`, `qa_validation`, `light_review` | `<panel>_verdict` | `panel-scope.sh --verdict <panel> {{SESSION_NAME}}` | 0 advances with no evidence (with the state's existing `recorded`, `has_commits` and level gates), 1 the agent decides retry or escalate, 2 holds |
| 7 | work-on `ci_monitor` | `is_root` (routing) | `test "$(session-role.sh {{SESSION_NAME}})" = root` | with green CI: 0 `cascade_entry`, 1 `done` |
| 8 | work-on `staleness_check` | `staleness_fresh` (existing, routing) | unchanged | 0, 3 and -1 `analysis`, 1 `introspection`, with no evidence |
| 9 | execute `orchestrator_setup` | `setup_owned_pr` (routing) | `check-pr-output.sh --owned-pr ...` after the agent runs `adopt-or-create-pr.sh` | 0 `settled_branch_record`, 3 `pr_adopt` terminal, 2 `status_read` terminal |
| 10 | execute `pr_finalization` | `final_owned_pr` (routing) | `check-pr-output.sh --owned-pr ...` | 3 and 2 to the `pr_adopt` and `status_read` terminals |
| 11 | execute `pr_finalization` | `owned_pr_body_conformant` | `check-pr-output.sh --pr-body --owned` (resolves the PR itself) | hold on 1 or 2 |
| 12 | execute `pr_finalization` | `settled_commits` | `check-branch-output.sh --commits --base-ref origin/<default>` | hold on 1 or 2 |
| 13 | execute `pr_finalization` | `settled_wip_clean` | `check-branch-output.sh --wip` | hold on 1 or 2 |
| 14 | execute `pr_finalization` | `settled_docs_visibility` | `check-branch-output.sh --docs-visibility --base-ref origin/<default>` | hold on 1 or 2 |
| 15 | execute `pr_finalization` | none: routes on `vars.PAUSE_BEFORE_FINALIZE` | variable routing (koto#296) | `true` to `paused_for_review`, `false` to `plan_completion`, replacing `pause_decision` |
| 16 | execute `plan_completion` | `cascade_completed`, `cascade_skipped`, `cascade_partial` (routing) | context matches on `cascade_result.json`'s `cascade_status` | completed or skipped to `ci_monitor`; partial holds, as the directive already halts it |
| 17 | execute `plan_completion` | `ready_owned_pr` (routing) | `check-pr-output.sh --owned-pr ...` | 3 and 2 to the terminals |
| 18 | execute `ci_monitor` | `owned_ci_passing`, `owned_merge_state_clean` (existing), `monitor_owned_pr` (new, routing) | unchanged, plus the lookup | green: `merge_readiness` with no evidence; DIRTY: `escalate_dirty_merge_state`; lookup 3 or 2: terminals |
| 19 | execute `worktree_sync` | `current_with_main` (existing) | moves into `check-branch-output.sh --synced`, same test | unchanged routing; a failure now prints a finding with a rule name |

Gate names differ between the templates, and between states with different
arguments, because `validate-template-mermaid.sh` check 4 holds one gate name
to one command across templates.

The commit walk skips merge commits (`git log --no-merges`), since a branch
catches up with main by merging it in and a merge commit's subject is git's,
not the author's.

A /work-on child on /execute's shared branch opens no pull request of its own
(`pr_status: shared`), so gates 2 and 3 pass for it and /execute's gates 13
and 14 check the shared branch once, before the pull request is finalized. The
commit walk (gate 1) still runs per child over that child's own
`impl_base..HEAD`.

### Copied verdicts, before and after

| State | Before: the agent submits | After |
|---|---|---|
| work-on `staleness_check` | `staleness_signal: fresh`, `stale_requires_introspection` or `unavailable`, restating `check-staleness.sh`'s exit 0, 1 or 3 | Transitions route on `gates.staleness_fresh.exit_code` alone, including -1; `staleness_signal` keeps only `override` and `blocked` |
| work-on `scrutiny`, `review`, `qa_validation`, `light_review` | `*_outcome: passed`, gated on a results key existing; each seat's blocking status taken from the agent's `blocking_count` | `<panel>_verdict` exit 0 advances with no evidence; blocking comes from finding severity; `*_outcome` keeps `blocking_retry` and `blocking_escalate`, accepted only on exit 1 |
| work-on `verification` | `verification_outcome` and a free-text `commands_run` | koto starts the map's commands and routes on the result; the only evidence left is `verification_status: blocked` with `detail`, for a runner that can't start |
| work-on `ci_monitor` | `session_role: root` or `child`, copied from `session-role.sh`; `ci_outcome: passing` next to green gates | `is_root` decides the role; green CI routes with no evidence; `ci_outcome` keeps `failing_fixed` and `failing_unresolvable` |
| execute `orchestrator_setup` | `status: completed`, `pr_adopt` or `status_read`, restating `adopt-or-create-pr.sh`'s result | `setup_owned_pr` routes all three; `status` keeps `override` and `blocked` |
| execute `pr_finalization` | `finalization_status: pr_adopt` or `status_read`, restating `owned-pr.sh`; `updated`, restating `gh pr edit`; `pause_decision`, restating `PAUSE_BEFORE_FINALIZE` | `final_owned_pr` routes the lookup; the output gates (11 to 14) passing is what "updated" meant; the variable routes the pause; `finalization_status` keeps `update_failed` |
| execute `plan_completion` | `cascade_status: completed`, `partial` or `skipped`, copied from `run-cascade.sh`'s JSON; `pr_adopt` or `status_read`, restating `owned-pr.sh` | Gates on `cascade_result.json`, which the script records itself, and `ready_owned_pr` route all five; the agent submits only `cascade_detail` |
| execute `ci_monitor` | `ci_outcome: pr_adopt`, `status_read`, restating `owned-pr.sh`; `dirty_merge_state`, restating `mergeStateStatus`; `passing` next to green gates | Gates route all four; `ci_outcome` keeps `failing_fixed`, `pending` and `failing_unresolvable` |

### Verification

The map, `.claude/shirabe-extensions/verification-map.json`, as shirabe's own
would read:

```json
{
  "schema": "shirabe-verification-map/v1",
  "commands": {
    "cargo-test": {"run": ["cargo", "test", "--workspace"], "timeout_secs": 1200},
    "plan-to-tasks": {"run": ["skills/plan/scripts/plan-to-tasks_test.sh"]},
    "run-cascade": {"run": ["skills/work-on/scripts/run-cascade_test.sh"]},
    "check-skill": {"run": ["scripts/check-skill.sh"], "each": "skills/*"}
  },
  "entries": [
    {"paths": ["skills/**"], "commands": ["check-skill"]}
  ],
  "default": ["cargo-test", "plan-to-tasks", "run-cascade"]
}
```

- `run` is an argv array, executed from the repository root with no shell.
- `each`, when present, runs the command once per distinct changed directory
  matching that pattern, with the directory's last component appended as the
  final argument. It is how `scripts/check-skill.sh <skill>` is expressed.
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

1. Resolve `HEAD` and the merge-base with the default branch. If a result for
   this head exists, exit 0.
2. Read the map at the merge-base. If it is absent or doesn't parse, write a
   `no-map` or `bad-map` result and exit 0.
3. Select commands. If any selected command is `unattended: false`, write an
   `attended` result naming them and exit 0. If nothing is selected, write a
   `no-map` result, since the map declares nothing for this change.
4. If a lock for this head names a live supervisor, exit 0. A lock whose
   process is gone is removed.
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
`${XDG_STATE_HOME:-$HOME/.local/state}/shirabe/verification/<session>/<head>/`,
in directories created with mode 0700 and pruned to the last ten heads per
session, outside every repository. The result, one JSON object with the head
and each command's id, exit status, duration, and whether it timed out or was
killed for runaway growth, is written atomically beside the logs.

`check-verification.sh --verdict` reads it, and on a settled result also
records it in koto context as `verification_results.json` for the audit
trail (a gate command may write context):

| Exit | Meaning | Route |
|---|---|---|
| 75 | no result for this head yet | waits (koto's pending code) |
| 0 | every selected command passed | `finalization` |
| 1 | a command failed | `implementation` |
| 3 | no verification map, a map that does not parse, or a map that selects nothing | `done_blocked`: "no verification map" (or "the verification map does not parse") |
| 4 | a command needs a person, timed out, was killed for runaway growth, could not start, or the tree was dirty | `done_blocked`, naming which |
| 2 | the result could not be read | hold |

A repository without the file is refused, never passed, which means every
repository that adopts this release stops at verification until it commits a
map. That is the intended reading of R8; the plan lands shirabe's own map with
the gate, and shirabe's runs keep working once that merge is the merge-base.

### Panels

The round file `panel-scope.sh --record` reads gains a severity on every
finding:

```json
[{"seat": "completeness",
  "cited": [{"path": "src/a.sh", "lines": "10-24"}],
  "findings": [{"severity": "blocking", "summary": "...", "path": "src/a.sh", "lines": "12-12"}]}]
```

A finding without a `severity` makes `--record` refuse the round, so a seat
can't be recorded as passing by omission. `blocking_count` may still be
present and is ignored. `--verdict` reads the ledger's seats for the panel and
passes when every seat has a recorded verdict and none is blocking; each
blocking finding becomes one `::koto-finding::` line naming the seat and the
finding's location. The `<panel>_carried` route (every seat kept) is
unchanged, because a kept seat's recorded verdict is already non-blocking.

**The decider slot.** Each panel state is where a later `decider-check` gate
goes, named `<panel>_decider`, in `mode: shadow`. It carries the trial's
model-graded criteria from `scripts/review-shadow/criteria.json` under the
same rule ids (`rs-007` to `rs-010`, four, which is koto's limit per state),
with the trial's `pr-summary`, `doc-pairs` and `code-hunks` slicers as its
extraction commands. The trial's script-observed criteria (`rs-001` to
`rs-006`) are command checks, not decider criteria, and stay in the trial.
koto forbids any `when` clause, `skip_if` or context assignment from reading a
decider check's output, and a shadow check never blocks, so adding it can't
change which transition a panel takes. It is not built here.

The existing `override_default` on the panels' gates stays, in an exit-code
form, so a person's override remains the only way past a panel gate and is
listed by `koto overrides list`, as it is today.

### Mapping to koto's gate events

Every gate in the inventory is a `command` gate or a `context-matches` gate,
and the verification launcher is a `default_action`. They produce koto's
existing events and no field of their own:

| Gate kind | Event | What koto records |
|---|---|---|
| command and context gates | `gate_evaluated` | gate name, state, outcome and exit code or match, `attempt`, `visit_attempt`, the check's `findings`, per-rule `rule_counts` on failure, duration, 4 KiB of a failed command's streams; a `failure` object on the `koto next` response |
| `verification_verdict` while pending | `gate_evaluated` with `poll` | `status: pending` and the window; no `attempt`, no `rule_counts`, no fallback finding |
| verification launcher | `default_action_executed` | command, exit code, both streams, attempt fields |
| decider slot (later) | `decider_checked` | the criterion's `rule_id` and verdict |

Each violation's `rule_id` and `rule_ref` (the `rule_ref` written with
`@<12-char commit>`; the line ranges below are at the design's base and the
build re-pins them, with the excerpt test keeping them honest):

| Gate | Violation | `rule_id` | `rule_ref` |
|---|---|---|---|
| 1, 1b, 12 | subject not a Conventional Commits subject | `commit/conventional-subject` | `references/pr-body-conformance.md#L40-L44` |
| 1, 1b, 12 | AI-attribution trailer on a commit | `commit/no-ai-trailer` | `references/pr-body-conformance.md#L57-L60` |
| 2, 13 | a path under `wip/` in the tree | `branch/no-wip-files` | `references/wip-hygiene.md#L14-L16` |
| 3, 14 | R7, R8 or R9 on a changed document | `docs/visibility-vision-sections`, `docs/visibility-strategy-sections`, `docs/private-only-type` | `docs/guides/doc-validation.md#L22-L27` |
| 4, 11 | PB1, PB2, PB3, PB4 | `pr-body/conventional-title`, `pr-body/one-separator`, `pr-body/no-ai-trailer`, `pr-body/no-heading-in-part1` (chosen by the validator's message; an unrecognized message is `pr-body/conformance`) | `references/pr-body-conformance.md` `#L40-L50`, `#L51-L56`, `#L57-L60`, `#L61-L75`; `#L34-L80` |
| 5 | a command failed | `verification/command-failed` | `skills/work-on/references/verification-map.md#L28-L44` |
| 5 | no map, or nothing selected | `verification/no-map` | same |
| 5 | a map that does not parse | `verification/bad-map` | same |
| 5 | needs a person, timed out, runaway, could not start, dirty tree | `verification/needs-person`, `verification/timed-out`, `verification/runaway`, `verification/not-started`, `verification/dirty-tree` | same |
| 6 | a blocking finding from a seat | `panel/blocking-finding` | the panel's aggregation lines in its phase file |
| 19 | `origin/main` not merged in, or a merge in progress | `branch/current-with-main` | the `current_with_main` comment in `execute.md` |
| 7 to 10, 16 to 18 | routing gates | none (Decision 9) | none |

### What waited on the contradiction-settlement work

The design first marked several gates as waiting on rules the
contradiction-settlement work (#507) was settling. That work has merged, and
every rule a gate reads is now on main:

| Gates | Rule | Settled on main by |
|---|---|---|
| 6 (panels) | where reviewer detail files live versus wip hygiene | #557: detail files are `mktemp` paths outside the repository |
| 6 (panels) | the retry cap that bounds the panel loop | #531 and #557: 2 blocking retries, shared, stated in each panel's directive |
| 19 | merge main in, never rebase, with ancestry tests | #545: `worktree_sync` merges and gates on `current_with_main` |
| 7 and 18 (`ci_monitor`, both skills) | a fixed CI failure is re-checked rather than ending the run | #557 for /work-on (loops back to `ci_monitor`), #545 for /execute (`failing_fixed` goes to `merge_readiness`, which re-reads CI) |
| 4 (work-on PR body) | PR-body conformance sections restored | #557 |
| 9 to 17 (execute PR output) | /execute's PR-title type | #545: the title is `$PR_TYPE: <slug>`; PB1 checks the shape, so how the type is chosen (tracked in #672) doesn't affect the gate |
| 5 (verification) | the verification map's wording | #557 |

No gate waits on #666 or #667, and none of #672's open items touches a rule a
gate reads.

## Implementation Approach

The build proceeds in this order, all in one pull request:

1. **Gate script library.** `check-branch-output.sh` and `check-pr-output.sh`
   with their rule tables, `_test.sh` suites using fixture repositories and a
   fake `gh`, `shirabe` and `owned-pr.sh` on `PATH`, and the excerpt test for
   rule references.
2. **shirabe's own verification map.** Commit
   `.claude/shirabe-extensions/verification-map.json` equivalent to today's
   Markdown map, document the schema in `verification-map.md`, and change the
   Markdown section to point at the file.
3. **Verification runner.** `run-verification.sh` and `check-verification.sh`,
   with tests that show the gate going red: a failing command gives 1, a
   command that forks past `max_procs` gives 4, a timeout gives 4, a missing
   map gives 3, a dirty tree gives 4, and a map edited on the branch is
   ignored. One test drives the launcher and the polling gate under a real
   `koto next`.
4. **work-on output gates.** Gates 1 to 5, 7 and 8, with the evidence values
   removed as the before-and-after table says, and the directives updated to
   name the gate scripts.
5. **work-on panel gates.** `panel-scope.sh --verdict` and the severity rule
   in `--record`, gate 6 on all four panel states, and the round-file format in
   the panel phase files.
6. **execute output gates.** Gates 9 to 19 and the `cascade_result.json`
   record in `run-cascade.sh`.

The template tests that exist (`pre-pr-evidence_test.sh`,
`finalization-shape_test.sh`, `ci-monitor-role_test.sh`,
`panel-scope_test.sh`, `execute-template-structure_test.sh`) gain cases for
each new route, driven by fake gate results in the way they already are.

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

**Credentials.** koto 0.15.0 starts commands in an environment cleared at
session creation, keeping only koto's defaults and the names in the template's
`pass_env`. A map command that needs a key gets it only if the template names
it, and the verification state names none until a repository's map declares a
networked command that needs one. The supervisor inherits the launcher's
cleared environment. Nothing in the runner prints its environment, and logs
hold only the commands' own output.

## Consequences

**Positive.** Every mechanical verdict in the two skills is decided by a
check, in the state that produced the output, and the agent stops answering
questions a script already answered. A malformed PR body, a non-conforming or
attributed commit, a stray `wip/` file or a visibility-restricted document
stops the run before a reviewer sees it. Verification can no longer pass on a
sentence, and a repository without a map is told so. A panel passes only when
no seat's findings include a blocking one. Each violation names a rule whose
id survives edits, so per-rule counts line up across template versions.

**Negative.** Every repository stops at verification until it commits a
machine-readable map, which is a real adoption cost. A new suite added in a
pull request doesn't verify that pull request. Every reviewer finding must
carry a severity, one more field in each seat's instructions. The gate
scripts duplicate a little plumbing (reading a range, fetching a PR) that a
later `shirabe validate` mode would own. Routing gates still write koto
fallbacks, which consumers must filter until koto#306 ships. Private content in
a single-PR run is caught only before the pre-merge panel, by the trial.

**Mitigations.** The refusal message names the file and schema a repository
needs, and shirabe's own map lands with the gate. The gate scripts are small
and tested, and each one's rule table is the input a rule registry would need.
The interim routing rule is one filter on `rule_id`, dropped when koto#306
lands.
