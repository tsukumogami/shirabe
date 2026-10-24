---
name: work-on
description: >-
  Take one known piece of work from where it stands now to a ready pull
  request with passing CI: branch, read the surrounding code, implement, test, open the PR,
  watch CI. Use it when asked to work on, implement, fix, build, tackle, pick
  up, close, or ship something that is already specified — a GitHub issue by
  number or URL, the next unblocked issue on a milestone, a red CI run or a
  failing test on an open PR, or a task stated plainly enough to just do. It
  also runs a `multi-pr` PLAN, one issue at a time, each landing its own pull
  request; every other plan mode belongs to `/execute`, which calls back into
  this skill per issue. Do NOT use it for a feature whose requirements are not
  written down anywhere — starting to code is how that feature gets decided
  by accident, and `/scope` is what settles it first.
argument-hint: '<issue_number | #issue | issue-url | M<milestone> | milestone-url | "Milestone Name" | docs/plans/PLAN-*.md | "task description"> [--review-floor=<level>] [--review-ceiling=<level>] [--verification=hosted-ci --verification-reason=<why>] [--koto-leg=<request-id>:work-on]'
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh *), Bash(true)
---

!`${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh work-on 2>&1 || true`

@.claude/shirabe-extensions/work-on.md
@.claude/shirabe-extensions/work-on.local.md

# Feature Development Workflow

Your goal is to work on a GitHub issue and deliver a high-quality, well-tested pull request.

## Input Resolution

The input `$ARGUMENTS` can be an issue reference or a milestone reference.

**Issue inputs**: `71`, `#71`, `owner/repo#71`, or issue URL - resolve directly to the issue number.
When an `owner/repo#71` or a URL names a repository other than the one you're working
in, the issue lives elsewhere: read it with `gh issue view <N> --repo <owner/repo>`
and record the repository at init as `ISSUE_REPO` (see **An issue in another
repository** under **Initialize**).

**Milestone inputs**: `M3`, `M#3`, milestone URL, or `"Milestone Name"` - list open issues in the milestone and select the first unblocked one (an issue is blocked if its Dependencies section references open issues). If multiple unblocked issues exist, pick the one with lowest number. Report to the user which issue was selected and why (e.g., "Selected issue #N — lowest-numbered unblocked issue in milestone M3"). If no unblocked issues exist, report which issues are blocked and stop.

### Handling `needs-triage` Issues

If the selected issue has a `needs-triage` label, the issue needs classification before implementation. Read CLAUDE.md and check its `## Label Vocabulary` section for the routing options available. If your project's extension file defines a triage workflow, invoke it now. Otherwise, read the issue body and present the routing decision with AskUserQuestion following the pattern in `${CLAUDE_PLUGIN_ROOT}/references/decision-presentation.md`. Recommend one: "Proceed directly (Recommended)" when the issue body already states what to build and the change is bounded, "Reclassify (Recommended)" when the body leaves the requirements or the approach open. Ground the recommendation in the issue body — quote the sentence that settles it, or name what the body leaves unanswered — and give the option that ranks lower a short reason. If the body is genuinely borderline, say so, still recommend one, and name the tiebreaker.

### Handling Blocking Labels

After resolving the issue and reading it with `gh issue view`, check for blocking labels before proceeding.

The label `needs-design` is universally recognized: if an issue carries it, stop immediately and inform the user that a design document is required before implementation can begin. This check applies even if no project label vocabulary is defined.

Other blocking labels (requiring design, requirements definition, or feasibility investigation) are defined in your project's label vocabulary (`## Label Vocabulary` in CLAUDE.md). If the issue has any such label, display the appropriate routing message and **stop execution**.

If the issue has a label indicating it tracks a child artifact whose implementation is underway, stop and direct the user to work on the child artifact instead.

Your project's extension file (`.claude/shirabe-extensions/work-on.md`) defines additional label names and routing messages to use. It also declares the project's **verification map** that the definition-of-done gate reads — see `references/verification-map.md` for the schema (path-glob to verification command(s), an optional default test command, fail-closed on cannot-verify).

---

## Definition of Done

Before an issue can finalize, the `verification` state runs a definition-of-done gate.
Done is verified by execution, not by the presence of a verification artifact. A
verification command that exists but was not run does not count — the gate runs the
command and requires a passing result.

koto runs the gate itself; the agent neither runs the commands nor reports their
outcome. On entry, the state's default action, `scripts/run-verification.sh --start`,
starts the selected commands in a bounded, detached supervisor and returns at once,
and the `verification_verdict` gate, `scripts/check-verification.sh --verdict`, is a
`poll:` gate that waits on the result and routes on it. A pending result is a wait,
not a failure: tick again when the response says to.

The gate reads the project's **verification map**, committed as
`.claude/shirabe-extensions/verification-map.json` and read at the merge-base with the
default branch, so a branch that edits the map is still verified by the map it started
from. The map's schema — path-globs bound to command(s), a default list, the bounds on
each command, and the fail-closed contract — is defined in
`references/verification-map.md`. Read that reference for the schema; this section
does not restate it. The map's commands are the project's own; never derive a command
from issue text or any other untrusted input.

The gate runs as follows:

1. **Classify the diff.** Take the issue branch's changed files (`git diff` against the
   base) and match each against the map's path-globs. Matches are additive: a file
   matching several entries runs each matched entry's command(s).
2. **Run the matched commands.** Run every command bound to a matched entry and require
   each to pass.
3. **Fall through to the default.** When no map entry matches the changed files, run the
   project's default test command declared in the extension.
4. **Announce what ran.** State which commands the gate selected and ran, and each one's
   pass/fail result. The announcement names the commands explicitly so the operator can
   see what "done" was checked against.

Outcomes:

- **Passed** — every selected command ran and passed. The workflow advances to
  `pass_counting` (see **Fixes Start Red**), then finalization.
- **Failed** — a command ran and did not pass. The workflow returns to implementation to
  fix the failure; a failing verification never advances toward a clean finalization.
- **Cannot-verify** — no map entry matched and no usable default exists, or a selected
  command could not run. This **fails closed**: it must never read as "verified" and
  never silently advances. It halts as a blocking condition that surfaces to the human.

The verdict's exit status carries the outcome: 0 passed, 1 failed, 3 no map (or a map
that does not parse, or selects nothing) and 4 a command that needs a person, timed
out, grew past its process bound, could not start, or a dirty tree — both of the last
two cannot-verify, ending at `done_blocked`. Each violation names its rule
(`verification/...`) in a koto finding, and the result is recorded in context as
`verification_results.json`.

### Deferring Verification to Hosted CI

Some hosts must not run a repository's suites: a host in a measurement window, or
one too small for the map's commands. A run started there can defer verification to
the pull request's hosted CI instead, and the deferral is explicit and recorded,
never a silent skip:

- **Chosen at init, with a reason.** `VERIFICATION=hosted-ci` names the choice and
  `VERIFICATION_DEFERRAL_REASON` states why (see **Initialize**; under `--koto-leg`,
  `--verification=hosted-ci --verification-reason=<why>`). Neither is rebindable, so
  the choice is fixed before any state runs. The default, `VERIFICATION=local`, is
  the gate described above, unchanged.
- **The reason's characters.** koto accepts a variable value only within its
  allowlist, `^[a-zA-Z0-9._/:@+ \-]*$`: letters, digits, spaces and `. _ / : @ + -`.
  Apostrophes and commas are not among them, so `host can't run suites, CI only` is
  refused; `host is in a measurement window until 02:40Z` fits. The reason must also
  start with a letter or digit. Under `--koto-leg`, `work-on-open.sh` refuses a
  reason with any other character before koto runs, and before its own checks of
  the flag (`error=usage`, exit 64), naming the characters; a direct `koto init`
  gets koto's `invalid_var`. Either way, reword the reason and start again.
- **The map never launches.** Every edge that would enter `verification` goes to
  `verification_deferred` instead. koto runs a state's entry action before anything
  else in it, so the deferral is decided on the way in: `run-verification.sh` never
  runs and no supervisor starts. The reason is recorded in context as
  `verification_deferral`. A deferral with no reason ends at `done_blocked`; it
  neither runs the map nor goes on unexplained.
- **The run still finishes.** From `verification_deferred` the run goes through
  `pass_counting` and `finalization` and opens its pull request as any other, and
  its result carries `pr`.
- **The record is the run's, and the body says it plainly.** `verification_deferral`
  in context is the record, and the PR body's Verification section says hosted CI
  verified the change. A repository that opts in to workflow content (see **Pull
  Request Text** below) gets the deferral in the body too: there
  `pr_creation`'s `verification_deferral_recorded` gate holds `pr_status: created`
  until the body says local verification did not run, has the line
  `Reason: <reason>`, and says hosted CI is the build of record
  (`references/phases/phase-6-pr.md` has the section). `ci_monitor` then requires
  that CI green, as it does for every run.

### Fixes Start Red

A unit whose purpose is to correct behaviour reported as wrong is a **fix**, and a
fix starts from a check that fails for the reported reason, recorded before the
correcting change, and ends with that check passing. `references/red-first.md` has
the rules; this is the route.

- **`fix_determination`**, after the review level is chosen and before
  implementation. Its action, `scripts/fix-kind.sh resolve`, records the unit as a
  fix when its issue carries a label the repository's `## Fix Labels:` lists (`bug`
  by default) or its plan step has a `**Fixes**:` line (`FIX_REPORT`), and as a
  change otherwise. The run adds a fix itself with `fix-kind.sh declare --reason`
  when the report describes existing behaviour as wrong. A fix is never withdrawn.
  A change goes straight to implementation and owes nothing more.
- **`reproduce`**, for a fix. The run commits its reproducing test and records the
  red with `scripts/red-first.sh red`: the check run on the base code with the
  unit's committed tests applied, failing, with a marker found in a verbatim
  passage of the report and in the output. A bug no check can reproduce records a
  before-observation instead. `red_recorded` holds the run here until one exists.
- **`pass_counting`**, after every passing check (verification's exit 0, or a
  deferral to hosted CI). A fix needs its green, the red's command re-run at HEAD
  with `red-first.sh green` and exiting 0, before `fix_green` lets it finalize.
  `tests_counted` (`scripts/test-change.sh status`) holds a unit whose committed
  diff edits a test (removes a line, deletes it, renames it with a change) or
  that rests on observations, until someone other than the run accepts it. In a
  repository that isn't person-required the run mints an acceptance seat with
  `test-change.sh seat`, commissions it with the brief the script prints, and the
  seat accepts or declines under its minted identity; nothing waits for a person.
  A decline returns the run to implementation, and the third decline of the same
  tests ends it at `done_blocked`. A unit that only adds tests is counted at once.
  A repository whose `CLAUDE.md` declares `## Test Change Acceptance: person` takes
  no seat: the run stops at `pass_counting`, `status` prints the exact
  `test-change.sh accept` command a person runs in a terminal, and the run is
  resumed once they have. A higher authority can overrule an acceptance with
  `test-change.sh overrule`, before or after the run finished.
- **`pr_precheck`** re-runs `status` as `tests_still_counted`, so a commit made
  after counting that edits a test is held again (`precheck_status: recount`
  goes back to `pass_counting`).
- **`ci_pass_counting`**, after CI passes on the open pull request. The same two
  gates run again, since a commit that fixed CI may have edited a test; a decline
  returns the run to `ci_monitor`. Who accepted, under what authority, reads back
  from the session with `test-change.sh record`; nothing is written to the pull
  request.

### Finalization and No Silent Deferral

When an acceptance criterion is unmet, finalization reports `deferral_requested`, which
routes to the blocking `deferral_approval` human gate. The human makes an explicit
decision:

- **Approved** — the deferral is recorded as the human's decision through
  `scripts/run-trail.sh decision` with actor `person` (which also sends it through
  `koto decisions record`), and as a `deferral` departure against the step, so the
  audit trail shows what was deferred and on whose authority, and the PR body says
  in plain terms what the change leaves undone. The workflow then proceeds to PR
  creation.
- **Rejected** — the issue is not done. The workflow routes to `done_blocked`, a
  non-clean terminal, rather than shipping with the criterion silently unmet.

### Pull Request Text

The PR title, body and commit messages describe the change and how it was verified,
in terms a reader of the repository understands. By default they carry none of the
workflow's own records: no review panel table, no override or deferral notes, no
session, state or ledger names, no pointers to PLAN or ROADMAP files, which are
deleted when the work completes. Those stay in the run's session. A repository opts
in to them with a `## PR Workflow Content: include` header in its `CLAUDE.local.md`
or `CLAUDE.md`; `${CLAUDE_PLUGIN_ROOT}/scripts/pr-workflow-content.sh` prints
`include` or `omit` for the repository and is the one reader every skill and gate
uses. Under `omit`, `pr_creation`'s `pr_body_conformant` gate holds on the records it
can see (`pr-body/workflow-content`). `references/phases/phase-6-pr.md` says what goes
where under each setting.

A coordinator that dispatched this run reads its review round from this run's session,
not from the body. When the brief asks for the round, record it once the seats at the
head you report ready have passed:
`${CLAUDE_PLUGIN_ROOT}/skills/coordinate/scripts/review-round.sh record --session <WF> <round.json>`,
the round a JSON object with `reviewed_head` and one `seats` entry per seat (`seat`,
`model`, `run`, `verdict`). It refuses a round the land step would call malformed.

## Plan Input (Dispatcher)

When `$ARGUMENTS` is a path to a PLAN.md file, `/work-on` acts as a thin dispatcher
on the PLAN's `execution_mode`. `/work-on` no longer orchestrates a whole plan:
plan-level execution (single-pr and coordinated) is owned by `/execute`, which
delegates each single issue back to `/work-on`'s Plan-Backed Child Mode below.

Read `execution_mode` from the PLAN frontmatter and **re-validate it against the
closed set `{single-pr, multi-pr, coordinated}` before using it in any path or
branch interpolation** (an out-of-set value halts with a clear error). Then route:

- **`single-pr` or `coordinated`** — hand off to `/execute`. `/work-on` does not run
  these directly; direct the caller to invoke `/execute <PLAN>` (the
  implementation-altitude coordinator that owns plan-level execution and its
  ephemeral home). When `/execute` is already driving the plan, it spawns `/work-on`
  per issue via Plan-Backed Child Mode.
- **`multi-pr`** — run in place, one issue at a time. Select the next unblocked issue
  from the PLAN (an issue is blocked while its Dependencies reference open issues) and
  run it as a single issue-backed unit against the repo-persisted PLAN, each landing
  its own PR. There is no shared branch and no cross-issue carry-forward — multi-pr
  issues are independent, per the DESIGN's ephemeral-home model. On a `plan/v2` step
  plan the unit is a step, taken in step order: an outline step waits on the step
  before it. Before a step's work starts, run
  `${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/step-detail-check.sh <PLAN> <N>`;
  when it exits 1 the step is still a one-line outline, so stop there and report its
  message, since the plan's owner details the step first. Exit 2 means the check
  refused to decide: a malformed step number, a plan path that is missing or outside
  the repository, a PLAN that is not `plan/v1` or `plan/v2`, no such step, or a
  missing or too-old `shirabe`. Stop there too and report its message; it says what
  to fix, and the step's work does not start until the check exits 0.

### Mode Detection

When invoked as `/work-on <argument>`:

Detect the mode on `$ARGUMENTS` with any `--koto-leg` token (and its value, when
given separately) set aside: it names a caller's request leg (see **Answering a
Caller's Leg**) and is never part of an issue reference, a PLAN path, or a task
description. Set aside the review-level bound the same way, `--review-floor=<level>`
and `--review-ceiling=<level>` (see **Review Level**), and the verification deferral,
`--verification=<value>` and `--verification-reason=<why>` (see **Deferring
Verification to Hosted CI**). Set aside only for
detection: the tokens file `work-on-open.sh` reads is the original `$ARGUMENTS`,
`--koto-leg`, the bound and the deferral included.

- If `$ARGUMENTS` begins with `-- plan-backed` — **plan-backed child mode** (highest priority; the plan-level coordinator /execute is spawning this as a per-issue child workflow)
- If the argument is a path matching `docs/plans/PLAN-*.md`, or any `.md` file whose frontmatter contains `schema: plan/v1` or `schema: plan/v2` — **plan dispatcher mode** (see Plan Input above). `plan/v1` plans carry issue outlines; `plan/v2` plans carry steps (see `skills/plan/references/plan-format.md`)
- If the argument is an issue reference (`#N` or a GitHub issue URL) — **issue-backed mode**
- If the argument is a free-form task description — **free-form mode**

Plan-backed child mode is checked first. Plan dispatcher mode is checked before issue-backed mode.

### Plan-Backed Child Mode

When `$ARGUMENTS` begins with `-- plan-backed`, extract these variables from the remaining arguments:
- `ISSUE_SOURCE`: `github` or `plan_outline`
- `ISSUE_NUMBER`: GitHub issue number (github source only)
- `ARTIFACT_PREFIX`: workflow name for this child
- `PLAN_DOC`: path to the parent PLAN document
- `ISSUE_TYPE`: issue type hint (`code`, `docs`, or `task`) from the PLAN outline's `**Type**:` field
- `FIX_REPORT`: a step's `**Fixes**:` line, when it has one; the step is then a fix
  and the line is its report (see **Fixes Start Red**)

Submit entry evidence: `{"mode": "plan_backed", "issue_source": "<source>", "issue_number": "<N>"}`.

For `ISSUE_SOURCE=github`: read the GitHub issue with `gh issue view <ISSUE_NUMBER>` during the `plan_context_injection` state to get the issue title, body, and labels. Then proceed directly to `setup_plan_backed` → `analysis`.
For `ISSUE_SOURCE=plan_outline`: extract the outline from the PLAN doc during `plan_context_injection`. Then route through `plan_validation` → `setup_plan_backed` → `analysis`.

**A `plan/v2` step.** `/execute` names each task of a step plan `step-<N>`, and that
name is the child's `ARTIFACT_PREFIX`. The context is the `### Step <N>:` block, read
from the PLAN as committed when the child runs. At `plan_validation` koto runs
`scripts/step-detail-check.sh` as the `step_detail` gate. A step that is still a
one-line outline fails it with `step <N> is an outline; the plan's owner details it
before its work starts`: `proceed` is refused, so submit `verdict: exit` with that
message as the rationale, and build nothing. Never detail the step yourself. Once the
plan's owner commits the detail, running the same child again passes the gate and
builds from the detailed text. A `plan/v1` task passes the gate without it reading
anything.

**The report for a step.** The `summary.md` of a `plan/v2` step names
"the behaviour this step added" and the check that shows it, with the check's
result: the step's `**Check**:` as the plan states it, run, and the line of output
or the state that showed it worked. Not the files changed or a test count. Put it
in `## What Was Implemented`; the format behind the rule is the report rule in
`skills/plan/references/plan-format.md`.

Skip staleness checks in plan-backed mode.

When the orchestrator provides a `SHARED_BRANCH` variable, do not create a new branch. koto skips `setup_plan_backed` (its `skip_if` records `status: override`), so the response arrives with `advanced: true`: submit nothing for that state, call `koto next` again, and commit directly to `SHARED_BRANCH`. All child workflows in the batch share this branch and the same draft PR.

**PR creation for plan-backed children**: when `SHARED_BRANCH` is set, the orchestrator owns the PR. At the `pr_creation` state, submit `pr_status: shared` — skip PR creation and route directly to `done`. The orchestrator's `pr_finalization` state updates the shared PR after all children complete. A child that deferred verification records its reason as `verification_deferral`, as a standalone run does, but its `shared` edge skips `verification_deferral_recorded`: `pr_finalization` reads each child's reason and holds until the shared PR's body records it.

**A child under the lead shape.** When `/execute` runs a plan in the lead shape, a
step agent drives this child to its terminal from the hand-off in
`skills/execute/references/step-agent-handoff.md`, not the session that owns the
plan. The step agent may spawn its step's review seats, the panels the run's level
calls for; the seats spawn nothing themselves. A step agent never edits a step's
entry in the PLAN: the owning session details each step. The level is this child's
own choice inside the run's bound, and `review_level_check` floors it on the
child's own commits: on a shared branch `impl_base` is the only base, so earlier
steps' commits don't raise it (see `references/review-levels.md`).

If the koto scheduler marks this child as skipped due to a failed dependency (`failure_policy: skip_dependents`), the workflow enters with `mode: skipped`. Submit entry evidence `{"mode": "skipped"}` and enter the execution loop — koto routes directly to the `skipped_due_to_dep_failure` terminal state, which carries `skipped_marker: true`. Do not perform any implementation work.

The plan-level orchestrator — shared branch and draft PR, child spawning, escalation and PR finalization — lives in `/execute` (`skills/execute/`), which delegates each single issue back to `/work-on` through Plan-Backed Child Mode above. The completion cascade is shared rather than owned by either: its script lives here, at `scripts/run-cascade.sh`, because `/work-on` runs it for a standalone issue in its `cascade_run` state, and `/execute` reaches across to run it once per plan from `plan_completion`.

---

You are assigned to work on the resolved issue. The issue number determined above replaces `<N>` throughout this workflow. The workflow name `<WF>` is the ARTIFACT_PREFIX value: `issue_<N>` for issue-backed, `task_<slug>` for free-form.

## Koto Orchestration

### Initialize

**Issue-backed mode:**
```bash
koto init <WF> --template ${CLAUDE_PLUGIN_ROOT}/skills/work-on/koto-templates/work-on.md \
  --var ISSUE_NUMBER=<N> \
  --var ARTIFACT_PREFIX=issue_<N> \
  --var PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT}
```

**Free-form mode:**
```bash
koto init <WF> --template ${CLAUDE_PLUGIN_ROOT}/skills/work-on/koto-templates/work-on.md \
  --var ARTIFACT_PREFIX=task_<slug> \
  --var PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT}
```

**The review-level bound.** When `$ARGUMENTS` carries `--review-floor=<level>` or
`--review-ceiling=<level>`, add `--var REVIEW_FLOOR=<level>` or
`--var REVIEW_CEILING=<level>` to either init above, one `--var` per flag given and
the value exactly as typed. Without the flags add nothing: the init is the one
above, unchanged. koto checks the value against `^(light|standard|full)?$` and
refuses anything else at init (`invalid_var`), and a flag given twice is its
`duplicate_var`; report the refusal and stop. For example:

```bash
koto init <WF> --template ${CLAUDE_PLUGIN_ROOT}/skills/work-on/koto-templates/work-on.md \
  --var ISSUE_NUMBER=<N> \
  --var ARTIFACT_PREFIX=issue_<N> \
  --var PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT} \
  --var REVIEW_FLOOR=standard
```

**The verification deferral.** When `$ARGUMENTS` carries `--verification=hosted-ci`,
add `--var VERIFICATION=hosted-ci` and
`--var VERIFICATION_DEFERRAL_REASON=<why>`, the reason from
`--verification-reason=<why>` exactly as typed, to either init above (see
**Deferring Verification to Hosted CI**). A deferral without a reason is not a
deferral: stop and say so rather than init without one, since the run would end at
`done_blocked` before opening its pull request. The reason may use only letters,
digits, spaces and `. _ / : @ + -`, starting with a letter or digit: no apostrophes,
no commas (see **Deferring Verification to Hosted CI**). Check it before the init,
and when it has any other character, stop and say which, rather than init. koto
refuses a `VERIFICATION` other than `local` or `hosted-ci`, and a reason outside its
pattern or its variable allowlist (`invalid_var`); report the refusal and stop.
Without the flag add nothing. For example:

```bash
koto init <WF> --template ${CLAUDE_PLUGIN_ROOT}/skills/work-on/koto-templates/work-on.md \
  --var ISSUE_NUMBER=<N> \
  --var ARTIFACT_PREFIX=issue_<N> \
  --var PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT} \
  --var VERIFICATION=hosted-ci \
  --var "VERIFICATION_DEFERRAL_REASON=host is in a measurement window until 02:40Z"
```

**An issue in another repository.** When the issue reference names a repository other
than the one you're working in (an `owner/repo#N` or a URL, as **Input Resolution**
says), add `--var ISSUE_REPO=<owner/repo>` to the issue-backed init, with the owner and
repository from the reference. Leave it off for an issue in this repository, which is
every bare `#N`: an empty `ISSUE_REPO` is the run as it was before the variable
existed. The state directives then give `extract-context.sh` and the review packet
(`review-packet.sh --issue`) the value as `--issue-repo`, so both read the issue from
that repository; pass the flag as the directive writes it, empty or not. Neither
script looks the value up or falls back to this repository without it.
`pr_creation`'s `closing_keyword` gate asks for `Fixes <owner/repo>#<N>` and refuses
any closing reference to this repository's issue `<N>`, which would close on merge: a
bare `#<N>`, `GH-<N>`, this repository's `owner/repo#<N>` or its issue URL, the
markdown link `[#<N>](<its issue URL>)`, and any of them under a name this repository
had before a rename.
koto refuses a value that isn't `owner/repo` (`invalid_var`); report the refusal and
stop. For example:

```bash
koto init <WF> --template ${CLAUDE_PLUGIN_ROOT}/skills/work-on/koto-templates/work-on.md \
  --var ISSUE_NUMBER=<N> \
  --var ARTIFACT_PREFIX=issue_<N> \
  --var PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT} \
  --var ISSUE_REPO=acme/tracker
```

**Plan-backed mode** is initialized with the task variables (`ISSUE_SOURCE`, `PLAN_DOC`,
`SHARED_BRANCH`, `ISSUE_TYPE`, `REVIEW_FLOOR`/`REVIEW_CEILING` when the `/execute`
run was given a bound, and `VERIFICATION`/`VERIFICATION_DEFERRAL_REASON` when it
was given `--verification=hosted-ci`) and enters with `mode: plan_backed` (see **Plan-Backed Child
Mode**), which routes to `plan_context_injection`.

**Under `--koto-leg`** (issue-backed or free-form), don't run `koto init` yourself; open
the session through `work-on-open.sh` as **Answering a Caller's Leg** below says.

### Answering a Caller's Leg

`--koto-leg=<request-id>:work-on` (or `--koto-leg <request-id>:work-on`) lets a
coordinator run `/work-on` as a worker and read its result from koto's request store
instead of from what the worker says. Mode Detection sets it aside; it is not part
of the issue reference or the task description. The leg must be
named `work-on`, the one leg `/work-on` answers. It applies to issue-backed and
free-form runs only: a plan-backed child is `/execute`'s, which already receives its
result, and a PLAN path runs several issues. `work-on-open.sh` refuses the flag with
either (`error=usage`, exit 64, no koto call), on the same signals Mode Detection
uses; stop there and tell the user the flag doesn't apply. Without the flag nothing
below applies and the run is unchanged.

1. **Check the floor.** The flag needs koto's entry flags, which a koto older than
   the one `requires.tsv` names lacks:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh work-on --mode koto-leg 2>&1 || true
   ```
   Anything it prints is a missing prerequisite: report it and stop.
2. **Apply the Resume guard first.** A finished `<WF>` must be cleaned up or the run
   renamed before the open (see **Resume**); the open never replaces one.
3. **Write the tokens.** Split the original `$ARGUMENTS`, `--koto-leg` included, into
   tokens as typed and write them as a JSON array of strings, with the Write tool
   or `jq`, into a private directory outside the work tree:
   ```bash
   ARGS_DIR=$(${CLAUDE_PLUGIN_ROOT}/scripts/koto-open.sh --alloc-dir)
   ```
4. **Open.**
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/work-on-open.sh --workflow <WF> \
     --var ISSUE_NUMBER=<N> --var ARTIFACT_PREFIX=issue_<N> "$ARGS_DIR/tokens.json"
   ```
   An issue in another repository also passes `--var ISSUE_REPO=<owner/repo>`, as
   under **Initialize**. Free-form passes only `--var ARTIFACT_PREFIX=task_<slug>`. Don't pass the
   review-level bound or the verification deferral as `--var`: the script reads
   `--review-floor=`, `--review-ceiling=`, `--verification=` and
   `--verification-reason=` from the tokens itself, and refuses
   `--verification=hosted-ci` without a reason, and a reason with a character
   outside letters, digits, spaces and `. _ / : @ + -` (an apostrophe or a comma,
   say), naming the characters (`error=usage`, exit 64, no koto call). It adds
   `PLUGIN_ROOT`, and on a
   live session the `REVIEW_LEVEL` its ledger last recorded (an attach resets
   every rebind variable it isn't passed), and makes one `koto init` with
   `--attach-live --koto-leg`: no
   session means a new one bound to the leg, and a live one (a resume) is attached
   and bound. It removes the tokens file on every path. `session=<WF>` means the run
   is bound. Go on with the entry evidence, or, on a resume, with `koto next`.
   `error=usage` (exit 64) is a malformed, missing, or repeated `--koto-leg`: no
   koto call was made, so nothing is on the leg; report it and stop. `refused=<code>`
   (exit 2, or koto's own code such as 1 for lock contention) is a refusal; report
   it and stop. `refused=args_file_in_work_tree` is `koto-open.sh`'s own and never
   reaches koto. `failed=<kind>` (exit 127 for a missing koto or jq, or koto's own
   code) means no session was opened and nothing is on the leg; report it and
   stop. koto records a refusal only on a leg that
   is still open and unbound (`result_source: refused`, payload `outcome: refused`
   and a kebab-case `reason` such as `input-mismatch` or `var-mismatch:ISSUE_NUMBER`).
   On a leg already bound to this session, a re-dispatch that koto refuses (from
   another worktree, say, which is `origin_mismatch`) records nothing, and the leg
   stays bound and open.

Once bound, the run is still a root session: every tick carries `--no-cleanup`
as always, and the terminal tick still promotes the result onto the leg. That
result is `status` (`success`, or
`failure` for `done_blocked`) and the terminal state, which the leg records as
`result_final_state` and a `request-leg` gate exposes as `final_state` (`done`,
`done_already_complete`, `done_blocked`, `validation_exit`). koto 0.13.0 defines
that gate output, empty for explicit and refused results, in its koto-author
template-format reference (the `request-leg` rows of the gate output table). A coordinator routes a
promoted `work-on` leg on both, since `validation_exit` is a success too, and routes
a refusal on its source rather than on the payload: the leg records
`result_source: refused`, which a `request-leg` gate exposes as `source`.

The payload is `pr` alone. `done` and `done_already_complete` declare a `result:`
map whose one key, `pr`, is the URL submitted as `pr_url` with `pr_status: created`.
A run that opened no pull request (an already-complete issue, or a child on
`/execute`'s shared branch) resolves `pr` to `""`, and koto lists it under
`missing`. The payload carries no head: a coordinator reads that from GitHub when
it verifies. `done_blocked` and `validation_exit` declare no map, so their payload
is koto's own. work-on.md declares no `outcome`, so a coordinator still routes on
status and final state, and reads the pull request from `pr`.

Some exits never reach the leg, which stays open and unbound: an `error=usage` from
`work-on-open.sh`, a failed `--mode koto-leg` preflight, and the flag given with a
plan-backed or PLAN-path input. So does a worker that stops before its terminal. A
request-leg gate waits on an open leg indefinitely, so the coordinator needs its
own fallback for a worker that ended without a result: a check on the worker's
exit, or a deadline after which it abandons the leg.

What the coordinator puts on the leg, so koto admits the session:

| Leg field | Value |
|-----------|-------|
| name | `work-on` |
| `template` | `work-on.md` |
| `inputs` | Issue-backed: `ISSUE_NUMBER` (the issue number) and `ARTIFACT_PREFIX` (`issue_<N>`). Both optional; each one named must equal what the run passes. Free-form: none. The agent picks the `task_<slug>` itself, so a pinned `ARTIFACT_PREFIX` can't be relied on to match. |

koto compares only the inputs the leg names, and only against variables that
aren't `rebind`: `PLUGIN_ROOT` is `rebind`, so an input for it is never compared.
Pin nothing else: every other input the leg names is compared against the
session's recorded value, which for a variable the run never sets is its default
(`code` for `ISSUE_TYPE`, empty for `SHARED_BRANCH`), and any other value is
refused as `input-mismatch` on the leg. A
coordinator running several workers gives each its own request, or at least its own
leg, since one leg answers one session.

### Scripts

- `scripts/session-role.sh <session-name>` — prints `root` or `child`, from
  koto's `parent_workflow`. The discriminator for any `/work-on` behaviour that
  must differ between a directly-invoked run and one materialized as a child of
  `/execute`; its one caller today is `ci_pass_counting`'s `is_root` gate, which
  sends a root to the cascade and a child to `done`. Call it as
  `${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/session-role.sh <WF>`, and
  **treat any answer that is not exactly `root` as `child`** — that is what
  makes its fail-safe hold. The script's header covers calling it from a
  `work-on.md` state directive, where `{{SESSION_NAME}}` supplies the name.
- `scripts/ci-cancel-after-merge.sh <session-name>` — run by koto, never by the
  agent, as `ci_passing`'s fallback when its filter says not green. It exits 0
  only when GitHub reports the PR MERGED and every non-green check is a
  cancelled run of a workflow the repo's `scripts/check-macos-floor-setup.sh
  --workflows` lists, and then records those checks in context as
  `ci_cancelled_after_merge.txt`; otherwise 1. It matches by workflow and the
  PR's state, not by when the cancel happened, and close-cancel cancels whole
  runs, so a Linux job of a floor workflow counts too; a failed one still
  blocks. A repo without that script gets a quiet 1. `/execute`'s
  `owned_ci_passing` runs the same script with `--owned <owned-pr.sh arguments>`,
  which judges the PR that run owns instead of the current branch's, so the
  rule has one copy. `scripts/ci-cancel-after-merge_test.sh` is its harness, and
  `skills/execute/scripts/owned-ci-cancel_test.sh` covers `--owned`.
- `scripts/ci-none-declared.sh <session-name> [--owned <owned-pr.sh arguments>]`
  — run by koto, never by the agent, as `ci_passing`'s and `owned_ci_passing`'s
  last fallback. Both gates read a pull request with no checks as not green; this
  passes one only when the repository's default branch carries
  `.claude/shirabe-extensions/hosted-ci.json` saying `"hosted_ci": "none"` with
  a one-line `"reason"`, and the pull request body records it as a
  `Reason: <reason>` line. It then
  records `ci_none_declared.txt` in context; otherwise 1. The default branch is
  read through the GitHub API, so a pull request can't declare itself.
  `scripts/ci-none-declared_test.sh` is its harness, and drives both gates.
- `scripts/pr-checks.sh [<pr>] [--repo R] [--json F] [--jq Q]` — the one read
  of a pull request's checks, in place of `gh pr checks` with the same
  arguments: `ci_passing`, `/execute`'s `owned_ci_passing`, both fallbacks
  below and `/execute`'s merge-verdict.sh read through it. Wherever the token
  can read checks it runs `gh pr checks` and passes its output, stderr and exit
  status through unchanged. Where GitHub refuses the check read (a
  fine-grained token on some repositories, #1132) it builds the same list from
  the Actions jobs at the head and the commit's statuses, and lists each
  required check neither answers, or that only another app's check run could,
  in the bucket `unreadable`, which no gate counts as green. It never touches
  the token. `scripts/pr-checks_test.sh` is its harness.
- `scripts/pr-url.sh` — sourced, never run: `pr_url_parse` splits a pull
  request URL into its host, owner and repository, or refuses it. Both CI
  fallbacks above take the repository from the pull request's URL through it
  and send their `gh api` reads to that URL's host (`--hostname`), so a pull
  request on a host other than gh's default is read from its own. The one
  exception is `ci-none-declared.sh --owned`, whose declaration read comes
  before the lookup and stays on gh's default host, the one owned-pr.sh
  searches. `scripts/pr-url_test.sh` is its harness.
- `scripts/record-changed-paths.sh --base|--write <session-name>` — run by koto
  itself, never by the agent: `analysis` runs `--base` on entry to record
  `impl_base` once, and `changed_paths_record` runs `--write` to put
  `changed_paths.txt` in context before `issue_type_routing` asks for the type.
  Exit codes: 0 written, 64 no base resolves, 66 a context write failed, 67 a
  missing argument. The script's header has the base rules and the caps.
- `scripts/panel-scope.sh --plan|--carried|--recorded|--verdict|--open-count|--record|--mark-fixed <panel> <session>`
  — the findings ledger and what a panel round runs. koto runs `--plan` on
  entering `scrutiny`, `review`, `qa_validation` and `light_review`, and
  `--carried`, `--recorded` and `--verdict` as each one's gates; the agent runs
  `--record` after each round and `--mark-fixed` after committing a fix. A full
  round spawns every seat; any other round keeps every seat and runs at most one
  re-verifier, which answers the findings the fix made due by id and reviews the
  fix diff once per retry. A panel passes only when every blocking finding is
  closed, and one with nothing to run and nothing open is carried through by
  koto. `--open-count` gives `panel-retry-budget.sh` its count. The phase files
  under `references/phases/phase-4*` say how to act on the scope;
  `scripts/panel-scope_test.sh` is its harness.
- `scripts/review-level.sh init|set|facts|check|slice|report|level` — the run's
  review level (`references/review-levels.md`). koto runs `init` on entering
  `review_level_choice`, and `facts`, `check` and `slice` at
  `review_level_check`; the agent runs `set <session> <level>` to choose,
  raise or lower the level, which rebinds `REVIEW_LEVEL` and appends to the
  `review_level.jsonl` ledger together, and a maintainer runs `report` to read
  the ledgers of retained sessions. `work-on-open.sh` runs `level` to read the
  ledger's last level before it attaches a live session. The script's header has every subcommand's
  exit codes; `scripts/review-level_test.sh` and `scripts/review-level-routes_test.sh`
  are its harnesses.
- `scripts/fix-kind.sh resolve|declare|withdraw|agree|kind` — whether the unit is a
  fix (`references/red-first.md`). koto runs `resolve` as `fix_determination`'s
  action and `agree` as its `kind_unchanged` gate; the agent runs `declare
  <session> --reason <why>` to make the unit a fix. It rebinds `UNIT_KIND` and
  appends to the `fix_kind.jsonl` ledger together, and refuses (exit 1) to make a
  fix a change. Its rebind passes `REVIEW_LEVEL` and `PLUGIN_ROOT` through, since
  an attach resets every rebind variable it leaves out. Exit codes are in its
  header; `scripts/fix-kind_test.sh` is its harness.
- `scripts/red-first.sh red|observe|green|check-red|check-green` — a fix's red,
  observations and green, in context as `red_first.json`. The agent runs `red`
  at `reproduce` and `green` at `pass_counting`; koto runs `check-red` and
  `check-green` as the `red_recorded` and `fix_green` gates, which report
  `red-first/no-red` and `red-first/no-green`. `scripts/red-first_test.sh` and
  `scripts/red-first-routes_test.sh` are its harnesses.
- `scripts/test-change.sh init|classify|note|seat|accept|decline|overrule|status|covered|record`
  — the held test change (`references/red-first.md`), the only writer of the
  `test_change_ledger.jsonl` context key. koto runs `init --entry` in
  `fix_determination`'s action and `status` as `pass_counting`'s and
  `ci_pass_counting`'s `tests_counted` gate and `pr_precheck`'s
  `tests_still_counted` (finding `test-change/held`); the agent runs `note` while
  implementing and `seat` at a hold, and the seat runs `accept` or `decline`. A
  person runs `accept` at a terminal, a coordinator or person `overrule`, and
  anyone `record` to read the ledger back. Every decision is
  asked of `scripts/lib/acceptance-rule.sh`, the interim rule, which a later
  shared decision rule replaces in that one file. Exit codes are in its header;
  `scripts/test-change_test.sh`, `scripts/test-change-routes_test.sh` and
  `scripts/lib/acceptance-rule_test.sh` are its harnesses.
- `scripts/work-on-open.sh --workflow <WF> [--var NAME=VALUE]... [--dispatched-by <dispatcher>] <tokens-file>`
  — the `--koto-leg` entry (see **Answering a Caller's Leg**): checks the flag,
  maps `--review-floor=`/`--review-ceiling=` from the tokens, passes a live
  session's recorded `REVIEW_LEVEL` back, then makes one
  `koto init --attach-live --koto-leg` through the shared
  `scripts/koto-open.sh`; with `--dispatched-by` it then records the
  dispatcher with `koto session link` (the script's header has the retry and
  the `warning=link-failed` record). Exit codes: 0 opened or attached, 2 refused (recorded on
  the leg only when the leg was still open and unbound), 64 its own usage refusal
  with no koto call, 127 no koto or jq, and koto's own code otherwise.
- `scripts/panel-retry-budget.sh <session-name> <panel>` — decides
  whether a review panel that found blocking issues may send the work back
  again, reading the count of unclosed blocking findings from the ledger
  (`panel-scope.sh --open-count`), and records each retry it grants in
  `panel_retries`. The panel
  directives run it before the retry loop. Exit codes: 0 granted, 1 refused,
  64 the record could not be read or is malformed, 66 the grant could not be
  recorded, 67 bad arguments; every exit but 0 means escalate.
- `scripts/check-closing-keyword.sh --issue <N> --repo <owner/repo>` — run by
  koto, never by the agent, as `pr_creation`'s `closing_keyword` gate when the
  run has `ISSUE_REPO`: 0 when the body closes the issue with
  `<keyword> <owner/repo>#<N>`, 1 when it doesn't, also closes issue `<N>` of the
  pull request's own repository (`#<N>`, `GH-<N>`, `owner/repo#<N>` or its URL,
  the markdown link `[#<N>](<its URL>)`, or under an old name of the repository) for an issue
  elsewhere, or the pull request can't be read, 2 usage, 3 a lookup of another
  repository the body closes the issue in failed or ran out of time, which
  holds the state like 2. With
  `ISSUE_REPO` empty the gate's own expression runs and this script doesn't.
  `scripts/closing-keyword-gate_test.sh` is its harness.
- `scripts/check-branch-output.sh`, `scripts/check-pr-output.sh`,
  `scripts/run-verification.sh` and `scripts/check-verification.sh` — the
  output gates, run by koto, never by the agent: `commit_convention` at
  `finalization`, `deferral_approval` and `pre_pr_evidence`,
  `branch_docs_visibility` at `pr_precheck`, `pr_body_conformant` at
  `pr_creation`, and the launcher and `verification_verdict` at `verification`.
  Exit 0 passes, 1 is a violation with a `::koto-finding::` line naming its rule,
  2 could not decide. Run one by hand for the reason a gate holds; each header
  has the details.
- `scripts/retry-clearing_test.sh`, `scripts/terminal-retention_test.sh`,
  `scripts/ci-monitor-role_test.sh`, `scripts/record-changed-paths_test.sh`,
  `scripts/work-on-open_test.sh`, `scripts/panel-retry-budget_test.sh`,
  `scripts/output-gates-routing_test.sh` — the harnesses; see each file's
  header.

### Execution Loop

Repeat:

1. Run `koto next <WF> --no-cleanup`
2. If `action: "execute"` with `advanced: true` — run it again
3. If `action: "execute"` with `expects` — do the work described in `directive`,
   read any phase file it references, then submit evidence from a file:
   write the JSON object (`{"field_name": "value", ...}`) to `evidence.json` in
   the run's scratch directory with the Write tool, tick, and remove the file:
   ```bash
   koto next <WF> --with-data @<scratch>/evidence.json --no-cleanup
   rm <scratch>/evidence.json
   ```
   Provide the fields listed in `expects`. Check `expects.options` for valid values.
4. If `action: "done"` — report the outcome and stop.

**Evidence goes in a file, never inline.** Every command in this workflow that
passes `--with-data` (`koto next`, `koto decisions record`) passes `@<file>`,
not a quoted JSON argument. Claude Code's worktree-isolation check refuses a
quoted argument after a token-stripping prefix such as `env -u GH_TOKEN`,
reading the JSON as the program `env` runs, and the file form gives it
nothing to misread. The scratch directory is the run's own, from
`${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh scratch` (private, outside the
work tree; `references/skill-session-convention.md`): allocate it once, write
each evidence file there, remove each after its tick, and remove the directory
when the run ends. The JSON is the same object the inline form would have
passed. Never reword evidence to get a command past a refusal.

**Retention: every `koto next` in this workflow carries `--no-cleanup` — every
tick of the loop above, the entry-evidence tick, and the Resume tick below —
whether this run is a root or a child that `/execute` materialized from
`work-on.md`.** Without it, the tick that reaches a success terminal disposes of
the session and takes `plan.md` and the run's other context keys with it. koto
keeps a session that reaches a failure terminal either way, and on a child the flag only keeps the session: the child's result still
reaches its parent on that tick. `scripts/terminal-retention_test.sh` pins the behaviour.

**Errors:** exit 1 = gate failed (fix and retry), exit 2 = bad evidence (check `expects`).
Use `koto rewind <WF>` to step back.

### Review Level

Every run chooses a review level after `analysis` and before implementing,
at `review_level_choice`, with `scripts/review-level.sh set`:

- `light` — one panel, `light_review`, of one reviewer seat.
- `standard` — `scrutiny` then `review`, no QA.
- `full` — `scrutiny`, `review` and `qa_validation`.

A code change passes `review_level_check` before its first panel, on every
lap: the facts of the change (its size, the path classes it touched, whether
tests or acceptance criteria changed) set a floor, and koto holds the run
until the level is at or above it. Facts can raise the level, never lower it;
a lower needs a recorded reason and never goes below the floor. A session from
an earlier template has no level and takes the full path. `docs` and `task`
runs record a level too, and their routes skip the panels as before.
`references/review-levels.md` has the rules, the bound and the ledger.

A caller can bound the choice with `--review-floor=<level>` and
`--review-ceiling=<level>`, which become `REVIEW_FLOOR` and `REVIEW_CEILING` at
init (see **Initialize**); `/execute` and `/deliver` take the same two flags and
pass them to every `/work-on` run they start. `review_level_choice` records the
bound in the ledger's `bound` line before the first `choose`, and the bound doesn't
move inside a run.

| Flag | Variable | Values |
|------|----------|--------|
| `--review-floor=<level>` | `REVIEW_FLOOR` | `light`, `standard` or `full`; the lowest level the run may choose |
| `--review-ceiling=<level>` | `REVIEW_CEILING` | `light`, `standard` or `full`; a raise past it needs a recorded reason, except a raise to the facts floor |

### Review Panel

Read `references/review-panel-orchestration.md` for details (panel states: `scrutiny`, `review`, `qa_validation`, `light_review` — require parallel spawns, not standard directive execution).

An edited test is reviewed apart from an added one. A change that edits a test (removes
or changes a line, deletes it, renames it with a change) floors at `full`
(`tests_edited`); one that only adds tests floors at `standard`. The code packet lists
added and edited tests in its own `## Test changes` section, with the edited hunks;
every seat that runs judges each edited test as `corrects` or `weakens` in its
`test_edits`, `panel-scope.sh --record` refuses a round that skips one, and a `weakens`
is a blocking finding raised by that seat. None of it reaches the pull request.

### Resume

1. `koto workflows` — find a workflow matching this issue.
2. **If found, read its state before ticking it:**
   ```bash
   koto status <WF>
   ```
   `is_terminal: true` means a previous run already finished. It is NOT
   resumable, and this run has done no work — do not report the issue complete.
   Start fresh instead: `koto session cleanup <WF>` when its record is no longer
   wanted and then `koto init`, or `koto init` under a different workflow name to
   keep the record. (`koto init` on a name still in use refuses and says the
   same.) Under `--koto-leg` either init goes through `work-on-open.sh`; a
   renamed run still passes `ARTIFACT_PREFIX=issue_<N>`, so a leg that pins it
   still admits the session.
3. `is_terminal: false` is a genuine resume: `koto next <WF> --no-cleanup`. Under
   `--koto-leg`, open through `work-on-open.sh` first, which attaches the live
   session and binds it to the leg, then tick.
4. If none, `koto init` fresh (under `--koto-leg`, through `work-on-open.sh`).

Ticking is not a substitute for the state read: a finished session answers
`action: "done"` to any tick, which the loop would report as this run's outcome.

### Decision Capture

During analysis and implementation, record non-obvious decisions. Write
`{"choice": "...", "rationale": "...", "alternatives_considered": ["..."]}` to
`decision.json` in the run's scratch directory, then:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/run-trail.sh" decision --session <WF> --step <ARTIFACT_PREFIX> --actor agent:<WF> < <scratch>/decision.json
rm <scratch>/decision.json
```

`scripts/run-trail.sh` keeps the decision in the run's record, with the step
it belongs to and who made it, as `trail/decision/<n>.json` in this session,
and sends the same choice and rationale through `koto decisions record`. The
step is the run's `ARTIFACT_PREFIX` (`step-<N>` or `issue-<N>` for a
plan-backed child). The actor is `agent:<WF>` for a call the agent made, and
`person` when a human made it, as at `deferral_approval`. The text goes only on
stdin: the script refuses (exit 64 or 65, nothing recorded) text passed as an
argument, a document without a choice and a rationale, and one holding a
token, an `Authorization:` line or a private key. A refusal means the record is
wrong, not that the decision goes unrecorded: fix the document and run it
again.

The same script records the run's departures, each against its step, at the
sites that make one: a deviated acceptance criterion at finalization
(`references/phases/phase-5-finalization.md`), an approved deferral at
`deferral_approval`, and a scope change at either retry loop
(`references/phases/phase-3-analysis.md`,
`references/phases/phase-4-implementation.md`). Each writes
`{"what": "...", "why": "..."}` to `departure.json` in the scratch directory and
runs:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/run-trail.sh" departure --session <WF> --step <ARTIFACT_PREFIX> --kind <deviated|deferral|scope-change> < <scratch>/departure.json
rm <scratch>/departure.json
```

## Output

An open, ready PR with passing CI, referencing the source issue (or, for a
PLAN outline, the outline it implements). `/work-on` does not merge it; that
is left to a reviewer. A plan-backed child on a shared branch opens no PR of
its own: its commits land on the branch `/execute` owns.

## Begin

**Execution mode:** check `$ARGUMENTS` for `--auto` or `--interactive` flags,
then CLAUDE.md `## Execution Mode:` header (default: `interactive`). In --auto
mode, follow `references/decision-protocol.md` at decision points W1 (handling a
`needs-triage` issue) and W2 (clarifying an ambiguity during introspection). Safety
gates W3 (CI failure guidance) and W4 (accepting a red check) remain blocking in both
modes: blocking means the run ends at `done_blocked` through `failing_unresolvable`,
and an unattended run never asks the user instead. Capture any decisions made
with `scripts/run-trail.sh decision` (see **Decision Capture**).

First, resolve the input using the Input Resolution section above. Once you have an
issue number, read the issue with `gh issue view <issue-number>` (adding
`--repo <owner/repo>` for an issue in another repository). Apply the Handling
Blocking Labels rules (including `needs-design` universal check) and stop if any
blocking label is present.

Detect repo visibility from CLAUDE.md (`## Repo Visibility: Public|Private`). If not
found, infer from repo path (`private/` -> Private, `public/` -> Public; default to
Private). Load the appropriate content governance skill:
- **Private repos:** Read `skills/private-content/SKILL.md`
- **Public repos:** Read `skills/public-content/SKILL.md`

If your project's extension file defines a language skill or PR creation skill, invoke
those for project-specific quality and PR requirements.

Then:
1. `koto workflows` — find a workflow matching this issue, or `koto init` with
   the template path and appropriate variables if none does. Under
   `--koto-leg`, on a found workflow apply the **Resume** guard first,
   then open through `work-on-open.sh` (see **Answering a Caller's Leg**),
   fresh or resumed.
2. On a fresh workflow, submit entry evidence from a file (see the execution
   loop), with `--no-cleanup` like every later tick. Write the object to
   `<scratch>/evidence.json`:
   - Issue-backed: `{"mode": "issue_backed", "issue_number": "<N>"}`
   - Free-form: `{"mode": "free_form", "task_description": "..."}`

   then run `koto next <WF> --with-data @<scratch>/evidence.json --no-cleanup`
   and remove the file.
3. Enter the execution loop.

If no extension file exists at `.claude/shirabe-extensions/work-on.md`, the skill
proceeds with generic behavior: no language-specific quality checks. The `needs-design`
blocking label is still enforced regardless.
