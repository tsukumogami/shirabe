---
schema: design/v1
status: Current
upstream: docs/prds/PRD-red-first-fixes.md
problem: |
  /work-on can't tell a fix from other work, records no failing check before
  a fix's correcting change, counts a pass that came with an edited test like
  any other, and gives review no way to tell an edited test from an added
  one. A green check after a run therefore says nothing reliable to the
  maintainer, coordinator or reviewer who reads it.
decision: |
  A UNIT_KIND variable, bound by fix-kind.sh at a new fix_determination state
  from a fix label, a plan step's Fixes line or the run's own one-way
  declaration, routes a fix through a reproduce state where red-first.sh runs
  the check on the base code with the run's tests applied and records the
  failure with a marker found in both the report and the output. After every
  passing check, a counting state needs the fix's green and classifies the
  diff's test files by shape; an edited test or an observation holds the unit
  until a session ledger, written only by test-change.sh and judged by one
  rule library, shows a live acceptance by someone other than the author. A
  fresh acceptance seat accepts in autonomous runs; a person accepts at a
  terminal where the repository requires one; a higher authority overrules by
  appending to the same ledger. Review floors an edited test at full, shows it
  in its own packet section, and requires every seat to judge it.
rationale: |
  The variable-plus-ledger pattern is the one the template already trusts for
  the review level, and running the red on the base code makes the order a
  property of the record rather than something to police. A session ledger is
  the only record that lives with the run, takes a later overruling and
  separates the run, its seat, a coordinator and a person under one shared
  GitHub login. One classifier and one rule library keep the hold, the floor
  and the packet in agreement and make the interim rule a one-file swap.
decision_provenance: inline-resolved
---

# DESIGN: red-first fixes and held-back test changes

## Status

Current

Amended 2026-10-23: pull requests carry no workflow-tool record. Everything
below that writes to a pull request is withdrawn: `test-change.sh render` and
`render --update`, the pull request section and its markers, the
`check-pr-output.sh` section check, and an overrule re-rendering a section.
Acceptances, refusals and overrulings live in the run's session ledger only and
are read back with `test-change.sh record`; the walkthroughs' pull request
checks become `record` checks. `pr_precheck` still re-runs `status`.

## Context and Problem Statement

`/work-on` drives one unit of work (an issue, a free-text task, or a plan
step `/execute` hands it) through a koto workflow,
`skills/work-on/koto-templates/work-on.md`. The states that matter here run
in this order: `analysis` (which records the implementation base,
`impl_base`, through `record-changed-paths.sh --base`), `offload_canary`,
`review_level_choice`, `implementation`, `changed_paths_record`,
`issue_type_routing`, `review_level_check`, the review panels (`scrutiny`,
`review`, `qa_validation`, or `light_review`), then `verification` (local,
running the repository's verification map through `run-verification.sh` and
`check-verification.sh`) or `verification_deferred` (hosted CI), then
`finalization`, `pre_pr_evidence`, `pr_precheck`, `pr_creation` and
`ci_monitor`. Nothing in that sequence knows a fix from a feature: the only
trace of a bug label is the branch-prefix advice in
`references/phases/phase-1-setup.md` and the plan-template choice in
`phase-3-analysis.md`, both prose. The issue-type question
(`issue_type_routing`, values `code`, `docs`, `task`) is asked after
implementation, too late to order anything before it.

Tests are written and run by the agent inside `implementation`, which has no
test gate. When one fails, `phase-4-implementation.md` lists "Test bug:
update test" as an option, and `phase-6-pr.md` lists "test failure" among the
CI failures to fix locally. Nothing separates a code fix from a test edit, and
nothing records the call.

Test changes are visible in two places, neither of which separates an added
test from an edited one. `review-level.sh facts` sets `tests_changed` when any
path falls in the `test` class of `references/review-level-rules.tsv`, and
that class floors a change at `standard` whatever the edit was;
`measure()` reads `git diff --numstat -M` and drops the status letters.
`record-changed-paths.sh` writes `git diff --name-status -M` lines into
`changed_paths.txt`, but nothing classifies them. `scripts/review-packet.sh
code` lists changed paths with their status letters and the full diff, and the
seat questions in `phase-4a-scrutiny.md`, `phase-4b-review.md`,
`phase-4c-qa.md` and `phase-4d-light.md` say nothing about tests.

There is no notion of acceptance anywhere: no identity for an acceptor, no
authority, no record of a judgment on a test edit. A run's only identity is
its koto session name (`issue_<N>` or `task_<slug>`); review seats carry run
ids of the form `<panel>-r<round>-<seat>`. koto can't route on a context key,
which is why the review level lives in a rebindable template variable that
`review-level.sh set` binds and a ledger mirrors; the same constraint applies
to anything the workflow must branch on.

The PRD (`docs/prds/PRD-red-first-fixes.md`) settles what has to change. A
run decides before implementation whether its unit is a fix, from a label
listed in a `## Fix Labels:` declaration (`bug` by default), a plan step's
`**Fixes**:` line, or its own declaration, and can never withdraw that (R1 to
R3). A fix records a red before implementation: the check command run against
the base code with the run's test files applied, failing, with a failure
marker that appears both in a verbatim passage of the report and in the
output; and a green after, the same command passing at the head (R4 to R7).
A bug no check can reproduce gets an observation pair instead, which counts
only once accepted (R8). Each time a unit's checks pass, its test files are
classified as added (new, or only gaining lines) or edited (losing a line, or
deleted), and an edited test or an observation holds the unit until a live
acceptance covers it (R9, R10). In a repository that isn't person-required, a
fresh acceptance seat judges the edit; in one that declares `## Test Change
Acceptance: person`, the run stops resumably for a person, whose acceptance is
recognised by an interactive terminal (R11, R12). Acceptances record identity,
kind, authority (`reviewer` below `coordinator` below `owner`), covered
digests, reason and time; refusals are recorded with the rule that refused
them; a higher authority can overrule; and one rule decides every attempt so a
later shared decision rule replaces it in one place (R14 to R17). One command
reads the record back, the pull request body carries it, review packets and
floors single out edited tests, and the guidance stops offering a free test
edit (R18 to R22). Autonomous runs never wait for a person unless the
repository requires one, and nothing depends on read-only tests (R23, R24).

## Decision Drivers

- **Order has to be shown, not asserted.** The red has to come before the
  correcting change and fail without it (R4, R6). A record the agent writes by
  hand proves nothing; the run has to produce it from the command's own exit
  and output.
- **koto routes on variables, not context.** Whatever decides whether a run
  enters the red-first states has to be a template variable bound by a script
  that also writes a ledger, the way `REVIEW_LEVEL` is, with a gate that holds
  when the variable and ledger disagree.
- **One definition of a test file.** Review's `test` class is the definition
  (PRD Definitions); classification for holding, for the review floor and for
  the packet must read the same rules copy, taken at the base so a unit can't
  narrow it.
- **The rule must be replaceable in one place** (R17). Every accept,
  overrule, refusal and status read asks one function; the shared decision
  rule for delegated decisions, when it lands, replaces that function's body.
- **The record must outlive the run without touching the branch** (R19).
  Measured on koto 0.21.0: a retained session at a terminal state still
  accepts `koto context add`, so a ledger kept in the run's session can take
  an overruling after the run finished. Nothing may be committed to the
  branch that points at scratch state.
- **Autonomous runs must not stop for a person** (R23), and a
  person-required repository must stop resumably (R12). The hold has to be a
  non-terminal state that parks on a failing gate, as `ci_monitor` does.
- **A person has to be distinguishable from an agent without a new identity
  system.** Measured in this environment: an agent's tool shell has no
  controlling terminal (`/dev/tty` can't be opened, stdin isn't a TTY).
- **Existing conventions bind every new script**: bash 3.2, a `_test.sh`
  beside it listed in a `scripts/bash-floor/*.list`, guarded `mktemp`, the
  `test -x ... || exit 2` gate form with `SHIRABE_GATE_*` variables, an
  `engine` class line in the rules file for any script a template gate names,
  a `references/rule-registry.json` entry per finding rule, evals, and a
  regenerated `work-on.mermaid.md`.
- **Lead-shape steps share a branch.** Under `/execute`'s lead shape, every
  step's diff must be measured from its own `impl_base`, never from the
  merge-base, or a late step is held for an earlier step's test edits.
- **No change to koto, niwa, or the coordinator's skill.** A coordinator
  accepts or overrules by running the same record command from its own
  session; nothing under `skills/coordinate/` changes.

## Considered Options

### Decision 1: Recognising a fix and recording red, green and observations

Resolved inline.

A fix has to be known before implementation, and its red has to be the
command's own result rather than the agent's account of it. The workflow can
only branch on a template variable, and `review-level.sh` already shows the
pattern for a variable that a script binds and a ledger mirrors.

Key assumptions:

- `gh issue view` is available in an issue-backed run, as it already is for
  `extract-context.sh`.
- A repository's checks can run from a temporary worktree of the same
  repository; one where they can't uses the observation route.

#### Chosen: a `UNIT_KIND` variable bound by `fix-kind.sh`, and a red run on the base code by `red-first.sh`

A rebindable template variable `UNIT_KIND` (`change` or `fix`) is bound only
by a new script, `skills/work-on/scripts/fix-kind.sh`, which appends every
determination to the context key `fix_kind.jsonl`. A new state,
`fix_determination`, between `review_level_choice` and `implementation`, runs
`fix-kind.sh resolve` as its default action. That reads the issue's labels
against the `## Fix Labels:` declaration in `CLAUDE.md` at the base (`bug`
when absent), and the new `FIX_REPORT` variable that a plan step's
`**Fixes**:` line supplies. The agent can add `fix-kind.sh declare --reason`
there. `fix-kind.sh` refuses any move from `fix` to `change`, naming the
recorded source, and a `kind_unchanged` gate holds when the variable and the
ledger disagree, so a hand rebind can't skip the red. A unit with no fix
determination owes nothing new: `change` routes straight to
`implementation`, as today.

`UNIT_KIND=fix` routes to a new state, `reproduce`, where
`skills/work-on/scripts/red-first.sh` records the red. `red-first.sh red`
builds a detached temporary worktree at `impl_base`, copies in the test files
the unit's diff touches at HEAD (or the existing tests named with `--tests`),
runs the command there under a wall-clock bound, and writes `red_first.json`
only when the command exits non-zero, its output holds the failure marker,
the marker is in the report passage, and the passage is verbatim in the
report (the issue body, the task text or `FIX_REPORT`). The record holds the
command, base, reproducing tests with blob ids, exit, the last 40 lines
capped at 4,096 bytes, passage, marker and time. Each failed condition exits
1 with a `refused:` line naming it, so a red that fails for a compile error
is never recorded. The marker must be at least 8 characters and the passage
at least 20, so a bare `error` can't stand in for the report. The command
runs with an allowlisted environment (no `GH_TOKEN`, `GITHUB_TOKEN` or
`GIT_*` variables reach it), in its own process group that the bound kills whole, and test
files that are symlinks are refused rather than copied. Paths the command
names that exist in the repository are recorded as the red's harness files,
classified with the reproducing tests afterwards. `red-first.sh observe --phase before|after` records an
observation pair when no check can reproduce the bug, and `red-first.sh
green` re-runs the red's command at HEAD after the change. `reproduce` leaves
only through a `red_recorded` gate. A run that returns to analysis and newly
declares a fix comes back through `fix_determination` to `reproduce`; because
the red always runs on the base code, it still proves the failure without the
unit's code changes.

#### Alternatives Considered

- **Add `fix` to the issue-type question.** `issue_type_routing` already asks
  `code`, `docs` or `task`. Rejected because it is asked after implementation,
  too late for anything to come first, and because it lets the author decide
  whether its own rule applies.
- **The label alone.** Rejected because issueless plan steps and unlabelled
  bug reports would never be fixes.
- **Record the red in the live work tree and police commit order.** Check that
  no non-test file changed before the red commit. Rejected because it needs
  commit-order checks that a rebase or a late fix declaration breaks, and an
  uncommitted change could shape the red. Running on the base code makes the
  order a property of the record instead.
- **Keep the determination in a context key.** Rejected because koto can't
  route on context, which is why `REVIEW_LEVEL` is a variable.

### Decision 2: Noticing a test change and where a pass is held

Resolved inline.

The hold, the review floor and the review packet all need to agree on which
test was edited, and the hold has to happen after a check passed, at every
point a run can pass: local verification, a deferral to hosted CI, and CI on
the open pull request.

Key assumptions:

- `git diff --numstat` reports `-` for a binary file; a binary test file with
  any change counts as edited.

#### Chosen: one diff-shape classifier, held at two counting states

One classifier, `scripts/lib/test-classify.sh`, sourced by every reader. It
diffs `impl_base` to HEAD (committed changes only; on a shared branch
`impl_base` is the only base, as `review-level.sh facts` already does), keeps
paths in the `test` class of the rules copy `review-level.sh init` stored at
the base, and labels each `added` (new, or removed-lines zero), `edited`
(deleted, or removed-lines above zero, renames included) or `unchanged` (a
rename with no line changed). A rename is judged on both its paths, so a
test moved out of the `test` class with edits is still `edited`. For a fix it
also labels `edited` every reproducing test and harness file whose blob id
differs from the red's. The counting gates refuse to count over uncommitted
changes to tracked files (held, `uncommitted changes`), since verification
runs on the work tree and finalization would commit what was never
classified, and `pr_precheck` re-runs `test-change.sh status`, so a commit
after counting is held again by digest.

Two new states hold the pass, both entered only after a check passed:
`pass_counting`, where `verification` exits 0 or `verification_deferred`
would go to `finalization`; and `ci_pass_counting`, where `ci_monitor`'s
passing edges would go to `cascade_entry` or `done`. Each has two gates:
`fix_green` (`red-first.sh check-green`: passes for a non-fix; for a fix needs
a green at HEAD with exit 0, or an `after` observation) and `tests_counted`
(`test-change.sh status`, Decision 3). A decline returns `pass_counting` to
`implementation` and `ci_pass_counting` to `ci_monitor`; the third decline of
the same path set ends at `done_blocked`.

#### Alternatives Considered

- **Classify inside `review-level.sh` only.** Rejected because the hold and the
  packet would each need a copy, and three copies of "edited" drift.
- **One shared counting state with a variable that remembers where the run
  came from.** Rejected because the variable's only job would be routing back,
  and a hand rebind of it could send a post-CI hold to `finalization`.
- **Hold at `changed_paths_record`, before the panels.** Rejected because it
  holds before any check has passed, so an edit the run later reverts would
  still cost an acceptance.

### Decision 3: Acceptances, refusals and overrulings under the interim rule

Delegated to /decision.

The PRD fixes the vocabulary (identities, the three authority levels, the five
refusal rules) and leaves open where the record lives, who writes it, how a
person is told from an agent, how the person-required declaration is read, and
how one rule decides every attempt. In the reference setup every agent runs
under one maintainer's GitHub login, so nothing GitHub records can separate
the run, its seat, a coordinator and a person. A coordinator must be able to
overrule after the run finished, from its own session, with no change to koto,
niwa or the coordinator's skill.

Key assumptions:

- A coordinator runs as the same user on the same machine as the run, so it
  reaches the run's session by name. Measured: `koto context add` and `get`
  address a session by name from any directory.
- Retained local sessions are removed only by an explicit prune.
- `CLAUDE.local.md` is generated and not committed, so it is read from the
  working tree once, at the snapshot.
- Opening `/dev/tty` is evidence of a terminal, not of a human; a tool that
  allocates a pseudo-terminal defeats it.
- Nothing authenticates a ledger line; a well-formed line the rule would allow
  counts. Every alternative shares this.

#### Chosen: a session ledger, one writer script, one sourced rule library

The record is one append-only JSONL key, `test_change_ledger.jsonl`, in the
run's own koto session, written only by `skills/work-on/scripts/test-change.sh`.
`test-change.sh init`, run in `fix_determination`'s default action once
`review_level_choice` has stored the rules copy, writes a
header line with the author (`agent:<session>`), `impl_base`, and whether the
repository is person-required, with its source. Every later attempt is judged
against that header, never against the caller's working tree; a ledger with
no header holds the unit. `accept`, `decline` and `overrule` take `--session`,
`--as <identity>`, `--authority`, the covered files or observation digests and
`--reason`; the script computes digests as blob ids at the run's head
(`deleted` for a deleted file), asks the rule, and appends the event or a
`refuse` line before exiting non-zero. Every line carries `ts`, `event`,
`identity`, `kind`, `authority`, `files`, `reason`, the rule's outcome and rule
id, `source` (`session` today, reserved for later sources) and the judging rule
(`interim`). `seat` mints the next seat identity, appends a `seat` event with
a fresh nonce, and prints the seat's fixed brief: the edited hunks, the notes
the run recorded and the unit's acceptance criteria, framed as data, so the
run passes the brief through rather than writing its own. `status` is the
gate, and `record` and `render` produce
R18's readout and R19's pull request section.

The header also records the repository (`owner/name`) and a run nonce, and
`init` refuses to run twice or with an `impl_base` other than the merge-base
of HEAD with the remote default branch (or, on a shared branch, the shared
branch's remote tip when the step started), so neither a later nor an older
base can narrow the `test` class or pick a different `CLAUDE.md`. The
person-required declaration is read both at `impl_base` and at the remote
default branch's tip, and `person` at either wins. Session names must match
`^[A-Za-z0-9_-]{1,64}$` before they reach a lock path, a key or a marker, and
every path argument must be repository-relative, with no `..` segment and no
leading `-`. An attempt from another session passes `--repo`, and a
mismatch with the header is refused before the rule is asked. An agent
acceptance at `reviewer` must name an unused minted seat (rule
`unminted-seat`), so the run can't accept its own edit by inventing a
reviewer's name. An agent at `coordinator` must name a koto session that
exists in the local store and is neither the run nor one of its seats (rule
`unknown-session`). Identities must match
`^(agent|person):[A-Za-z0-9._:/-]{1,128}$`; reasons and paths have control
characters stripped; every line is built with `jq --arg`, never by string
concatenation.

All allow-or-refuse logic lives in `scripts/lib/acceptance-rule.sh`, in two
functions. `acceptance_rule_decide` takes identity, kind, authority, action,
the header's author and person-required flag, and the terminal flag, and
returns `allow` or `refuse <rule> <reason>`. `acceptance_rule_live` folds the
ledger against the current digests into counted or held with every reason,
replaying `decide` over each stored line so a hand-written line the rule would
refuse never counts. It ends an acceptance when a covered digest changes or an
overrule lands, re-counts after an overrule only on an acceptance at no lower
authority than the overruling's, and counts declines per sorted path set. No
other script compares authorities or names a rule id as a decision.

A `person:` attempt sets the terminal flag only if the script can open
`/dev/tty`. It then prints the covered files and digests with a short code
derived from them and reads the code back from `/dev/tty`, never from stdin or
an argument; without a terminal, with stdin or stdout not on that terminal, or
with a wrong code, it is refused `no-terminal` and recorded. Before the code
prompt it prints the edited hunks themselves, so the person sees what they
accept; paths and hunks printed to the terminal have control characters
escaped, so a crafted file name or line can't rewrite what the person sees. A person line carries an integrity tag, a keyed
hash of the line under a per-user key file (mode 0600) the script creates, and
`acceptance_rule_live` counts a person line only when its tag checks. It never
trusts a stored terminal flag. That guards against a hand-written line or a
careless edit of the key, not against an agent running as the same user, which
can read the key. The person-required declaration is read by `init`
from `CLAUDE.md` at `impl_base` with a fence-aware header scan in
`scripts/lib/claude-md-header.sh`, and from the working tree's
`CLAUDE.local.md`; either saying `person` makes the repository
person-required, and an unrecognised value counts as `person` and is named in
the record. Writers hold a `mkdir` lock keyed by the session name, in a
per-user state directory (mode 0700, owner checked) outside the repository and
the koto store. The lock holds the owner's pid and start time and is broken
only when that process is gone; a writer that can't get it within a bound
exits 75 rather than writing unlocked. Writers re-read the key after writing
to confirm their line landed, because a lost overrule would leave a unit
counted. The script asserts the koto floor this relies on (retained sessions
accept context writes and are addressed by name from any directory), and a
test exercises both.

What `render` puts in the pull request body is trimmed and sanitised, since a
public repository publishes it. It shows the red's and green's output only as
the three lines either side of the marker, with home paths and common token
shapes redacted; the full tail stays in the session record. Free text has
newlines collapsed and comment and marker strings neutralised, so a reason
can't close the section or forge another. When the report passage comes from
an issue in a private repository and the pull request's repository is public,
the section omits the passage, the marker and the output lines, and says so.
Observation and note text gets the same redaction and omission. The section
labels every identity as a recorded claim and names the rule that judged it
(`interim`), so a reader doesn't take "accepted by reviewer" for independent
assurance. Reading the record back from the
pull request body, after a prune, is display-only and never yields `counted`.

#### Alternatives Considered

- **Pull request reviews and comments as the record**, read back with `gh`.
  Rejected because under one maintainer login it can't tell the run, the seat,
  a coordinator and a person apart; a pull request's author can't approve it;
  a permission lookup would read the agents' admin login as a person `owner`;
  there is nothing to attach to before a pull request exists; and refusals
  would be derived at read time rather than recorded at the attempt. Only the
  reserved `source` field survives from it.
- **Reuse the review panels' verdict ledger** (`verdict_ledger.json` through
  new `panel-scope.sh` modes). Rejected because that ledger is scoped by panel,
  round, seat and commit, and `panel-scope.sh --plan` writes the whole object
  with a bare put that skips its revision check, so an overrule landing during
  a plan pass would be lost with no error. It would also weld the acceptance
  rule to the review rule the shared decision record later replaces.
- **Git notes or a committed record file.** Rejected because a committed file
  breaks R19 and the rule that nothing committed points at scratch state, and a
  notes ref needs fetch and push refspecs that managed clones or branch
  protection may refuse while leaving a permanent public copy of a working
  ledger.

### Decision 4: Review tells an edited test from an added one

Resolved inline.

R20 and R21 ask for a separate packet section, a per-test judgment from every
seat, and a different floor. The judgment has to be something the run can't
skip, so it belongs in the verdict the panel script already checks.

Key assumptions:

- A seat can read a hunk well enough to judge whether it corrects the test or
  weakens it; that is the judgment the acceptance seat makes, made again by
  every reviewer.

#### Chosen: a `tests_edited` fact that floors at `full`, a packet section, and a required verdict field

`review-level.sh facts` gains a `tests_edited` boolean from the shared
classifier, carried into `review_facts.json` and the decider's slice, and
`review-level-rules.tsv` gains `rule full tests_edited`; `rule standard
class:test` stays, so an added-only change floors where it does today.
`scripts/review-packet.sh code` gains a `## Test changes` section between
"Changed paths" and "Diff": added tests by path, edited tests with their hunks.
Each seat's verdict gains `test_edits: [{path, judgment}]` with `judgment` in
`corrects` or `weakens`; `panel-scope.sh --record` refuses (exit 65, rule
`review/test-edit-judgment`) a round in which a seat lacks an entry for an
edited path, and records each `weakens` as a blocking finding raised by that
seat under rule `review/test-edit-weakens`. The four seat files each gain one
question, and the implementation and CI-fix guidance stop offering a free test
edit.

#### Alternatives Considered

- **A new review level above `full`.** Rejected because a fourth level for one
  fact changes every reader of the level order.
- **Keep the floor and rely on the packet.** Rejected because R21 asks for a
  different floor, and `full` adds the QA seat where an edited test most needs
  a second look.
- **Ask the seats in prose only.** Rejected because nothing could tell whether
  a seat answered.

### Decision 5: One increment or two

Resolved inline.

The strategy behind this feature expected it might split into the red-first
fix first and the held-back pass second. The pieces share a counting state and
a classifier, and the plan that executes this design runs its steps on one
branch.

Key assumptions:

- Under plan v2 the steps run in the lead shape on one branch, so step 1's
  placeholder hold is replaced by step 2 without a released gap.

#### Chosen: one feature, four ordered steps, red-first first

One feature, built in four ordered steps that each leave `/work-on` working: a
fix starts red; an edited test holds the unit until a seat accepts it; a
person-required repository, overruling and the pull request record; then
review tells edited from added. The red-first fix is step 1 and the held-back
pass is steps 2 and 3. The feature splits into two separately delivered pieces
of work only if the first step's run outgrows one session, and then between
step 1 and step 2.

#### Alternatives Considered

- **Two separately scoped features.** Rejected because they share the
  classifier, the counting state and the ledger, and splitting duplicates the
  design and its review for no gain.
- **Held-back pass first.** Rejected because the first held case is a
  reproducing test changed after the red, which needs the red to exist.

## Decision Outcome

A `/work-on` run decides at `fix_determination`, before implementation,
whether its unit is a fix, from a fix label, a plan step's `**Fixes**:` line or
its own declaration, and can't take that back. A fix records its red at
`reproduce` by running the check on the base code with its tests applied,
which shows the failure exists without any of the unit's code changes and ties
it to the report through a marker found in both the report passage and the
output. After any passing check (local verification, a deferral to hosted CI,
or CI on the open pull request) the run enters a counting state that needs the
fix's green at the head and classifies every test file in the diff by shape.
An edited test or an observation holds the unit until the session ledger shows
a live acceptance from someone other than the author, judged by one rule
library. In a repository that isn't person-required a fresh acceptance seat
judges the edit at once, so an autonomous run never waits for a person; in one
that is, the run parks at the counting state until a person accepts at a
terminal. A higher authority overrules by appending to the same ledger, before
or after the run finished, and the pull request's section is re-rendered.
Review floors an edited test at `full`, shows its hunks to every seat in their
own section, and refuses a seat verdict that doesn't judge each edited test.

### Answers to the questions this feature left open

- **How a fix is recognised.** A fix label (`## Fix Labels:`, default `bug`),
  a plan step's `**Fixes**:` line, or the run's own declaration, resolved at
  `fix_determination` and recorded with its source; a run can add the
  determination and never withdraw it. This feature owns it.
- **How a test change is noticed.** By the shape of the unit's committed diff
  from its `impl_base`, classified with review's `test` class read at the
  base, each time a check passes, plus a digest comparison against the red's
  reproducing tests. This feature owns it.
- **What "fails for the reason the report gives" asks of a bug no test can
  reproduce.** An observation pair (how the failure was produced, the
  environment, what was seen with the report passage and marker, why no check
  can reproduce it, and the same after the change), which stands in for a red
  only once someone other than the author accepts it under the same rule as a
  test edit. This feature owns it.
- **Whether a test edit is stopped or surfaced while the agent works.**
  Surfaced, after the fact, at each passing check; nothing here makes tests
  read-only or interrupts an edit. Stopping an edit while the agent works is
  the edit-time guardrail that separate delegated-authority work owns, and
  this design holds with a guardrail that only surfaces an edit.

### The interim acceptance rule and how it is replaced

Until a shared decision record for delegated decisions exists, every accept,
decline and overrule is decided by `scripts/lib/acceptance-rule.sh`:

- an acceptance is recorded with the accepting identity, its kind, its
  authority, the covered digests, a reason and a time;
- the author's own identity (`agent:<run session>`) can't accept or overrule
  (rule `author`);
- an agent can act only as `reviewer` or `coordinator`, a person only as
  `reviewer` or `owner` (rule `authority-kind`);
- an agent at `reviewer` must be an unused seat the run minted (rule
  `unminted-seat`), and an agent at `coordinator` must name an existing koto
  session other than the run and its seats (rule `unknown-session`);
- a repository that declares `## Test Change Acceptance: person` refuses every
  agent acceptance (rule `person-required`), and a person's attempt counts only
  from an interactive terminal (rule `no-terminal`);
- an overrule needs an authority strictly higher than the acceptance's (rule
  `not-higher`), and only an acceptance at no lower authority than the
  overruling's counts the unit again.

The rules are checked in that order, so an attempt that breaks several is
refused by the first: `author`, `authority-kind`, `person-required`,
`unminted-seat`, `unknown-session`, `no-terminal`, `not-higher`.

When the shared record lands, it replaces the bodies of
`acceptance_rule_decide` and `acceptance_rule_live` in that one file. The
callers (`test-change.sh`, the counting gates, `record` and `render`) pass the
same inputs and read the same `allow`, `refuse <rule> <reason>`, counted or
held answers, so nothing else changes. Each ledger line names the rule that
judged it (`interim`) and carries a `source` field, so the new rule can decide
for itself whether to re-judge history and can add a source without a change
to the ledger's writer.

## Solution Architecture

### Overview

Three new scripts under `skills/work-on/scripts/` (`fix-kind.sh`,
`red-first.sh`, `test-change.sh`), three shared libraries under `scripts/lib/`
(`claude-md-header.sh`, `test-classify.sh`, `acceptance-rule.sh`), two new
template variables (`UNIT_KIND`, `FIX_REPORT`) and four new states in
`work-on.md` (`fix_determination`, `reproduce`, `pass_counting`,
`ci_pass_counting`). Review changes extend three existing scripts
(`review-level.sh`, `scripts/review-packet.sh`, `panel-scope.sh`). Nothing
under `skills/coordinate/`, koto or niwa changes.

### Components

| Component | Kind | Role |
|-----------|------|------|
| `scripts/lib/claude-md-header.sh` | new library | fence-aware scan of one `## <Name>:` header in a `CLAUDE.md` read at a given commit, refusing duplicates; used for `## Fix Labels:` and `## Test Change Acceptance:` |
| `skills/work-on/scripts/fix-kind.sh` | new script | `resolve`, `declare`, `agree`; binds `UNIT_KIND`, appends `fix_kind.jsonl`, refuses withdrawal |
| `skills/work-on/scripts/red-first.sh` | new script | `red`, `observe`, `green`, `check-red`, `check-green`; writes `red_first.json` |
| `scripts/lib/test-classify.sh` | new library | rows of `added`, `edited` or `unchanged` with path and blob id for the unit's test files |
| `scripts/lib/acceptance-rule.sh` | new library | `acceptance_rule_decide`, `acceptance_rule_live`; the only allow-or-refuse logic |
| `skills/work-on/scripts/test-change.sh` | new script | `init`, `classify`, `note`, `seat`, `accept`, `decline`, `overrule`, `status`, `record`, `render`; the only writer of `test_change_ledger.jsonl` |
| `work-on.md` | changed template | new variables and states; `test-change.sh init` in `fix_determination`'s default action |
| `review-level.sh` | changed script | `tests_edited` fact and slice field |
| `scripts/review-packet.sh` | changed script | `## Test changes` section |
| `panel-scope.sh` | changed script | required `test_edits` judgments; `weakens` as blocking finding |
| `check-pr-output.sh` | changed script | the pull request section is present and matches `render` |
| `plan-to-tasks.sh` | changed script | forwards a step's `**Fixes**:` line as `FIX_REPORT` |

### Key Interfaces

```text
fix-kind.sh resolve <session> [--issue <n>] [--issue-repo <o/r>] [--fix-report <text>]
fix-kind.sh declare <session> --reason <text>
fix-kind.sh agree   <session>                    # gate: 0 variable matches ledger
  exits: 0 recorded, 1 refused (withdrawal), 64 usage, 66 koto read/write failed

red-first.sh red <session> --marker <text> --passage-file <file> [--tests <path>...] -- <argv...>
red-first.sh observe <session> --phase before|after --file <observation.md>
red-first.sh green <session>
red-first.sh check-red <session>                 # gate: 0 red or before-observation present
red-first.sh check-green <session>               # gate: 0 non-fix, or green at HEAD exit 0, or after-observation
  exits: 0 recorded, 1 refused (prints which condition), 2 could not decide, 64, 66

test-change.sh init <session>
test-change.sh classify <session>                # rows: class<TAB>path<TAB>digest
test-change.sh note <session> --file <path> --reason <text>
test-change.sh seat <session>                    # prints agent:<session>/accept-<n>
test-change.sh accept|decline <session> --as <identity> --authority <level> \
    (--files <path>... | --all) --reason <text> [--repo <owner/name>]
test-change.sh overrule <session> --as <identity> --authority <level> \
    --acceptance <id> --reason <text> [--repo <owner/name>]
test-change.sh status <session>                  # gate: 0 counted, 1 held (reasons), 2 undecided
test-change.sh record <session>                  # R18 readout
test-change.sh render <session> [--update]       # R19 pull request section; --update rewrites it on the PR
  exits: 0, 1 refused (refuse line written), 2, 64, 66, 75 lock busy (retryable)

acceptance_rule_decide <identity> <kind> <authority> <action> <author> \
    <person_required> <terminal> <seat_minted> <session_exists> [<target_authority>]
  -> "allow" | "refuse <rule-id> <reason>"
acceptance_rule_live <ledger-file> <current-digests-file>
  -> "counted" | "held<TAB><reason>..." one line per reason
```

Context keys the run gains: `fix_kind.jsonl`, `red_first.json`,
`test_change_ledger.jsonl`. The pull request section sits in Part 2 between
`<!-- shirabe-test-change:<session>:start -->` and the matching end marker,
one section per session, so lead-shape steps sharing a pull request each keep
their own.

### Data Flow

```text
analysis ── record-changed-paths --base
   │
offload_canary ── review_level_choice (stores the rules copy)
   │
fix_determination ── test-change.sh init (header); fix-kind.sh resolve [+ declare]
   │                  → UNIT_KIND, fix_kind.jsonl
   │ UNIT_KIND=change                 │ UNIT_KIND=fix
   │                                  ▼
   │                             reproduce ── red-first.sh red|observe → red_first.json
   │                                  │ gate red_recorded
   ▼                                  ▼
implementation ──► changed_paths_record ──► issue_type_routing ──► review_level_check
   ▲                                       (tests_edited floors at full)
   │                                              │
   │                                    panels (packet shows test changes;
   │                                     each seat judges each edited test)
   │                                              │
   │                         verification (0) / verification_deferred
   │                                              ▼
   └── decline ─────────────────────────── pass_counting
                                gates fix_green, tests_counted (test-change.sh status)
                                held: seat accepts or declines, or person accepts
                                              │ counted
                                              ▼
                     finalization ─ pre_pr_evidence ─ pr_precheck (status re-run; section matches render)
                                              │
                                       pr_creation ─ ci_monitor
                                              │ CI passes
   ci_monitor ◄── decline ────────────── ci_pass_counting (same gates)
                                              │ counted
                                              ▼
                                     cascade_entry / done
```

An overrule after `done` runs `test-change.sh overrule --session <run>` from
the overruling session: it appends to the retained session's ledger under the
lock, and `render` rewrites that session's section of the pull request body.

## Implementation Approach

The four steps run in order on one branch; each leaves `/work-on` working end
to end. The PLAN this design produces now is a placeholder; the execution
regenerates it as a step plan from these steps. Steps 1 and 2 are the
red-first fix; steps 3 and 4 are the held-back pass and review. If the work
splits into two separately delivered pieces, it splits between step 1 and
step 2.

Every step follows the same plumbing rules, and its file list includes them:
a new script or library gets a `_test.sh` beside it, an entry in
`scripts/bash-floor/work-on.list`, and a run step in
`.github/workflows/check-work-on-scripts.yml`; a new file under `scripts/lib/`
is added to both of that workflow's `paths:` lists, which must match; every
new script a template gate names, and every new library, gets a `class
engine` line in `skills/work-on/references/review-level-rules.tsv`, so a
change to the rule or the classifier floors at `full`; a template change
regenerates `work-on.mermaid.md` and updates the route tests that assert the
edges it moves; and each new finding rule gets a `references/rule-registry.json`
entry and an eval. Each step runs the whole `/work-on` suite and the
`/execute` template tests before its pull request, since other suites
(`pre-pr-evidence_test.sh`, `run-verification_test.sh`,
`terminal-retention_test.sh`, `work-on-open_test.sh`,
`check-branch-output_test.sh`, `skills/execute/scripts/shared-deferral-record_test.sh`)
read the states these steps touch; a suite that turns out to assert a moved
edge joins that step's file list. The walkthroughs need all four steps, since
they use step 3's `record` and `render`. `FIX_REPORT` needs no change to `/execute`: it is declared
in `work-on.md`, and `/execute` passes each task's variables to the child
unchanged.

### Step 1: A fix starts red

Adds fix recognition, the red-first state, the red, green and observation
records, the shared classifier the red uses to find its reproducing tests, and
`pass_counting` with only its `fix_green` gate. In this step `check-green`
refuses an `after` observation with a `refused:` line saying observations wait
for acceptance, so a unit recorded by observation stays held at
`pass_counting` until step 2 lands. `scripts/check-init-site-vars.sh` is run
for the new `FIX_REPORT` init-site variable; it shouldn't need a change.

New files:

- `scripts/lib/claude-md-header.sh`
- `scripts/lib/claude-md-header_test.sh`
- `scripts/lib/test-classify.sh`
- `scripts/lib/test-classify_test.sh`
- `skills/work-on/scripts/fix-kind.sh`
- `skills/work-on/scripts/fix-kind_test.sh`
- `skills/work-on/scripts/red-first.sh`
- `skills/work-on/scripts/red-first_test.sh`
- `skills/work-on/scripts/red-first-routes_test.sh`
- `skills/work-on/references/red-first.md`

Changed files:

- `skills/work-on/koto-templates/work-on.md`
- `skills/work-on/koto-templates/work-on.mermaid.md`
- `skills/work-on/SKILL.md`
- `skills/work-on/references/phases/phase-3-analysis.md`
- `skills/work-on/references/review-level-rules.tsv`
- `skills/work-on/scripts/offload-canary-routes_test.sh`
- `skills/work-on/scripts/review-level-routes_test.sh`
- `skills/work-on/scripts/verification-deferral_test.sh`
- `skills/work-on/scripts/output-gates-routing_test.sh`
- `skills/work-on/evals/evals.json`
- `skills/plan/scripts/plan-to-tasks.sh`
- `skills/plan/scripts/plan-to-tasks_test.sh`
- `skills/plan/references/plan-format.md`
- `skills/plan/references/templates/step.md`
- `references/fixes/claude-md-conventions.md`
- `references/rule-registry.json`
- `scripts/bash-floor/work-on.list`
- `.github/workflows/check-work-on-scripts.yml`

### Step 2: An edited test holds the unit until a seat accepts it

Adds the ledger and its writer, the rule library, `tests_counted` on
`pass_counting`, and the acceptance seat. `test-change.sh init` joins
`fix_determination`'s default action, after `review_level_choice` has stored
the rules copy the classifier reads. At `pass_counting`, when `status` holds
in a repository that isn't person-required, the directive has the run print
the seat's brief with `test-change.sh seat`, commission one seat with the
Agent tool on the same commissioning as the `light` panel's seat, and pass the
brief unchanged; the seat runs `test-change.sh accept` or `decline` itself
under its minted identity, and the run ticks again. Notes the run recorded
with `test-change.sh note` while implementing are what the brief carries as
each edit's reason. Observations become acceptable here, and `check-green`
stops refusing an `after` observation that a live acceptance covers.

New files:

- `scripts/lib/acceptance-rule.sh`
- `scripts/lib/acceptance-rule_test.sh`
- `skills/work-on/scripts/test-change.sh`
- `skills/work-on/scripts/test-change_test.sh`
- `skills/work-on/scripts/test-change-routes_test.sh`

Changed files:

- `skills/work-on/koto-templates/work-on.md`
- `skills/work-on/koto-templates/work-on.mermaid.md`
- `skills/work-on/SKILL.md`
- `skills/work-on/scripts/red-first.sh`
- `skills/work-on/scripts/red-first_test.sh`
- `skills/work-on/scripts/retry-clearing_test.sh`
- `skills/work-on/references/red-first.md`
- `skills/work-on/references/phases/phase-4-implementation.md`
- `skills/work-on/references/review-level-rules.tsv`
- `skills/work-on/evals/evals.json`
- `references/rule-registry.json`
- `scripts/bash-floor/work-on.list`
- `.github/workflows/check-work-on-scripts.yml`

### Step 3: A person-required repository, overruling and the pull request record

Adds the `## Test Change Acceptance:` declaration and the person path at a
terminal, `overrule` before and after the run finished, `record` and `render`,
the pull request section and its check at `pr_precheck` (with `status`
re-run there), and `ci_pass_counting` for a test edit made while fixing CI.

Changed files:

- `skills/work-on/koto-templates/work-on.md`
- `skills/work-on/koto-templates/work-on.mermaid.md`
- `skills/work-on/SKILL.md`
- `skills/work-on/scripts/test-change.sh`
- `skills/work-on/scripts/test-change_test.sh`
- `skills/work-on/scripts/test-change-routes_test.sh`
- `skills/work-on/scripts/check-pr-output.sh`
- `skills/work-on/scripts/check-pr-output_test.sh`
- `skills/work-on/scripts/ci-monitor-role_test.sh`
- `skills/work-on/scripts/cascade-chaining_test.sh`
- `skills/work-on/scripts/leg-result_test.sh`
- `skills/work-on/references/red-first.md`
- `skills/work-on/references/phases/phase-5-finalization.md`
- `skills/work-on/references/phases/phase-6-pr.md`
- `skills/work-on/evals/evals.json`
- `scripts/lib/acceptance-rule.sh`
- `scripts/lib/acceptance-rule_test.sh`
- `references/fixes/claude-md-conventions.md`
- `references/rule-registry.json`

### Step 4: Review tells an edited test from an added one

Adds the `tests_edited` fact and floor, the packet section, the required seat
judgment, and the remaining guidance changes. Depends on step 1's classifier.

Changed files:

- `skills/work-on/scripts/review-level.sh`
- `skills/work-on/scripts/review-level_test.sh`
- `skills/work-on/references/review-level-rules.tsv`
- `skills/work-on/references/review-levels.md`
- `scripts/review-packet.sh`
- `scripts/review-packet_test.sh`
- `skills/work-on/scripts/panel-scope.sh`
- `skills/work-on/scripts/panel-scope_test.sh`
- `skills/work-on/references/review-panel-orchestration.md`
- `skills/work-on/references/phases/phase-4a-scrutiny.md`
- `skills/work-on/references/phases/phase-4b-review.md`
- `skills/work-on/references/phases/phase-4c-qa.md`
- `skills/work-on/references/phases/phase-4d-light.md`
- `skills/work-on/references/phases/phase-6-pr.md`
- `skills/work-on/SKILL.md`
- `skills/work-on/evals/evals.json`
- `references/jev-criteria.md`
- `references/rule-registry.json`

The rules file and the workflow file put every step's own pull request at the
`full` review level. No file under `skills/coordinate/` is touched, and
nothing in koto or niwa changes.

### Walkthroughs a checker runs

Each walkthrough runs in a scratch GitHub repository the checker owns, cloned
locally, with this shirabe build installed as the plugin. The repository holds
`greet.sh` (prints `Hello, <name>!`), `tests/greet_test.sh` (asserts `Hello,
World!` for `World`), `tests/run.sh` (runs every `tests/*_test.sh`, exits
non-zero on any failure), a `CLAUDE.md` with `## Repo Visibility: Private`,
and `.claude/shirabe-extensions/verification-map.json` whose `default` runs
`bash tests/run.sh`. `R` below stands for the plugin's
`skills/work-on/scripts/test-change.sh`, and `<s>` for the run's session name
(`issue_<n>`). The checker acting as coordinator needs a koto session of its
own other than the run's: the dispatching coordinator's session when the run
was dispatched, otherwise any session the checker opens (`<c>` below).

**Walkthrough 1: red then green on a reported bug.** File issue 1 with the
`bug` label and the body "Running `./greet.sh ''` prints `Hello, !` instead of
`error: name required`." In a fresh session run `/work-on 1`.

1. The run reaches `fix_determination`, and `fix-kind.sh` (beside `R` in the
   plugin) records `fix` with source `label:bug`.
2. At `reproduce` the run adds and commits `tests/empty_name_test.sh` (the
   red copies only committed test files) and records a red with marker
   `error: name required`. Expect `red_first.json` to show a
   non-zero exit, the base equal to `impl_base`, the new test with its blob
   id, and an output tail containing the marker.
3. The run changes `greet.sh`; verification passes; at `pass_counting`
   `red-first.sh green` records exit 0 at the head.
4. `R record <s>` prints the fix source, the red (failing, marker found, report
   passage quoted) and the green (passing) with no edited test, and the unit
   counted. The pull request body's section shows the same red and green.
5. Confirm the red's test runs `./greet.sh ''`, the reported case.

**Walkthrough 2: an edited test held, accepted, then overruled.** File issue 2
(no label): "Drop the exclamation mark: `./greet.sh World` should print
`Hello, World`. Update the expected value in `tests/greet_test.sh` to match."
Run `/work-on 2`. The issue asks for the test edit, so every run makes it.

1. The run is not a fix. It changes `greet.sh`, edits the expected value in
   `tests/greet_test.sh` (one line removed, one added) and records why with
   `R note`.
2. Verification passes; at `pass_counting` `R status <s>` exits 1 with
   `held: unaccepted tests/greet_test.sh`.
3. The run prints the seat's brief with `R seat <s>`, commissions the seat
   with that brief, and the seat runs `R accept` as `agent:<s>/accept-1`.
   `R record <s>` shows the unit counted, accepted by `agent:<s>/accept-1` at
   `reviewer`, with the file's digest. The run goes on to its pull request.
   Run walkthrough 4 here, before step 4.
4. After the run finishes, as the dispatching coordinator, run
   `R overrule <s> --as agent:<c> --authority coordinator --acceptance <id>
   --reason "loosens the assertion"`. `R record <s>` shows the unit held
   (`overruled`), and the pull request section shows the overruling.
5. Mint a seat with `R seat <s>` and run `R accept <s> --as <that seat>
   --authority reviewer --all --reason x`: the record stays held
   (`overruled`). Run `R accept <s> --as agent:<c> --authority coordinator
   --all --reason x`: the record shows the unit counted.

**Walkthrough 3: the same under a repository that requires a person.** Add
`## Test Change Acceptance: person` to the scratch repository's `CLAUDE.md` on
its default branch, then repeat walkthrough 2 with issue 3.

1. At `pass_counting` the run doesn't commission a seat. It stops with a
   message naming `tests/greet_test.sh` and the exact `R accept` command a
   person runs.
2. The agent's own attempt, `R accept <s> --as agent:<s>/accept-1 --authority
   reviewer --all --reason x`, exits 1; `R record <s>` shows a `refuse` line
   with rule `person-required`.
3. In a real terminal, the checker runs `R accept <s> --as person:<name>
   --authority owner --all --reason "test was wrong"`, sees the file, digest
   and code, and types the code. `R record <s>` shows the unit counted with
   `person:<name>` at `owner`.
4. Resuming `/work-on 3` continues from `pass_counting` to finalization.

**Walkthrough 4: an agent's attempt to accept refused and recorded.** On
walkthrough 2's run, after its step 3 (the seat's acceptance, with identity
`agent:<s>/accept-1`, is the live one) and before its step 4. Each attempt is
refused before the unit's state matters, so the timing only fixes which
acceptance step 6 targets.

1. `R accept <s> --as agent:<s> --authority reviewer --all --reason x` exits 1
   with rule `author`.
2. `R accept <s> --as agent:other --authority reviewer --all --reason x`, a
   reviewer name the run never minted, exits 1 with rule `unminted-seat`.
3. `R accept <s> --as agent:other --authority owner --all --reason x` exits 1
   with rule `authority-kind`.
4. `R accept <s> --as agent:no-such-session --authority coordinator --all
   --reason x` exits 1 with rule `unknown-session`.
5. `R accept <s> --as person:<name> --authority owner --all --reason x`, run
   from the agent's tool shell, exits 1 with rule `no-terminal`.
6. Mint a second seat with `R seat <s>` (`agent:<s>/accept-2`) and run
   `R overrule <s> --as agent:<s>/accept-2 --authority reviewer --acceptance
   <the seat's acceptance id> --reason x`: it exits 1 with rule `not-higher`.
7. `R record <s>` lists all six refusals with identity, action, files, rule
   and time, and the unit is still counted. `R render <s> --update` rewrites
   the run's pull request section, whose history then shows the six
   refusals.

## Security Considerations

The threat that matters is not an outside attacker. It is the run's own agent,
or another agent running as the same user under the same GitHub login,
getting a test edit or an unreproduced fix counted, on purpose or by drift.
The controls below guard against drift, shortcuts and accidents. They don't
stop a same-user adversary, and the design says so rather than implying it.

**Untrusted inputs.** Issue bodies, labels, a plan step's `**Fixes**:` line,
the marker, reasons and observation files are all data. Scripts pass them with
`jq --arg` and quoted expansions, never `eval` or string-built JSON. A label
can only add the fix determination, never remove it, so a hostile label costs
extra work at most. `## Fix Labels:` and `## Test Change Acceptance:` are read
from `CLAUDE.md` at a base `init` has checked is reachable from the remote
default branch, so a unit's own diff can't relax them; `CLAUDE.local.md` can
only tighten, and an unknown value counts as `person`.

**Running the check.** The red runs an agent-chosen command on the base code
with the unit's tests applied. That is no new capability, since the agent can
already run anything, and the temporary worktree is not a sandbox: it shares
the repository's object store and has the network. The script runs the
command with an allowlisted environment (`PATH`, `HOME`, `LANG`, `TMPDIR` and
the variables the repository's verification map declares), so credential
variables such as `GH_TOKEN`, `GITHUB_TOKEN` and `GIT_*` never reach it; this
is an accident control, not containment, and credential files under `HOME`
stay reachable. It runs the command
in its own process group killed whole at the bound, refuses symlinked test
files, creates the worktree under a `mktemp -d` path it owns, and removes it in
a trap. The repository's checks may still fetch dependencies, exactly as its
verification already does.

**What the red proves.** It proves a failing check whose output carries a
marker of at least 8 characters taken from a verbatim passage of at least 20,
run without the unit's code changes. It doesn't prove the check reproduces the
bug: a test that prints the report and exits 1 would pass. Refusing a marker
that appears in the test's own source was considered and rejected, because a
real reproducing test usually asserts on exactly that text. The pull request
section shows the marker, the passage and the test path side by side so a
reviewer can judge it.

**Hiding an edited test.** The classifier judges a rename on both paths,
classifies the red's harness files with its tests, refuses to count over
uncommitted changes to tracked files or untracked files under a `test`-class
path, and is re-run at `pr_precheck`, so a commit after counting is held
again. The verification map is read at the merge-base, so editing it changes
nothing for this unit. Files that shape a check without being in the `test`
class are not covered until the repository widens the class: snapshots and
golden files, `testdata/` fixtures, test-runner configuration, and CI workflow
files. A unit that weakens a check through one of those passes the hold;
review still sees the diff.

**Identity and the record.** Identities are recorded claims, and the terminal
check is evidence of a terminal, not of a person; neither is authentication.
The rule refuses the author's identity, an agent at `reviewer` that isn't an
unused seat the run minted, an agent at `coordinator` that names no existing
session other than the run's, and a person attempt without stdin, stdout and
`/dev/tty` on one terminal. A person line carries a keyed hash under a
per-user key file, and the live fold never trusts a stored terminal flag. A
same-user agent can still read that key, write the session key directly, or
drive a pseudo-terminal, and then the hold can be defeated. Seat minting and
the coordinator-session check constrain names, not principals: the run itself
can mint a seat and accept as it, and any existing koto session passes the
coordinator check, including one the agent opens with `koto init` a moment
before accepting. They make an accidental self-acceptance visible in the
record as a named seat or session, nothing more; in an autonomous run the
control is close to self-attestation, which the pull request section says. The
seat's brief is fixed by the script, and the seat and a coordinator treat
everything it carries (the report passage, reasons, notes, hunks, file
contents and command output) as data, never as instructions. A team that needs
more than this should wait for the shared decision record, which replaces the
rule in one file. A repository-side CI check that reads only the pull request
was considered as an extra control and left out: judging a diff with no
record of who accepted what is a repository policy check that stops or flags
edits, which is the edit-time guardrail work this feature depends on rather
than owns. The terminal check also turns off silently under any harness that
allocates a pseudo-terminal; `red-first.md` records the environment it was
measured in.

**Concurrency.** A lost overrule would leave a unit counted, so writers hold a
lock in a 0700, owner-checked per-user directory, break it only when its
owner process is gone, fail with exit 75 rather than write unlocked, and
re-read the key to confirm their line landed. A writer that bypasses the
script also bypasses the lock; the koto floor the script relies on is asserted
and tested.

**Data exposure.** The pull request section is public in a public repository.
It carries only the output lines around the marker, with home paths and common
token shapes redacted; the full output tail stays in the session. Free text is
flattened and comment markers neutralised so a reason can't forge or close a
section. When the passage comes from a private repository's issue and the pull
request is public, the passage, the marker and the output lines around it are
all omitted, since any of them can quote the private report. Redaction is
best-effort pattern matching, not a guarantee. Person identities and reasons are published by design and
shouldn't contain email addresses. The ledger, key and lock live under the
user's own koto store and state directory with owner-only modes.

## Consequences

### Positive

- A fix's record shows the reported failure on the code as it was and gone
  after, tied to the report by a marker, without trusting the agent's account.
- A pass that came with an edited test is visibly held until someone else
  accepts it, and a coordinator can overrule with the same command a seat uses,
  even after the run finished.
- The hold, the review floor and the packet read one classifier, so they can't
  disagree about which test was edited.
- Replacing the interim rule is a one-file change with a ready refuse-all test.

### Negative

- Every edited test in a unit's diff holds the unit, even one its check never
  ran, and a test that only gains lines (including an early return) counts as
  added.
- The red runs the check in a temporary worktree, which costs one extra run of
  the check per fix and fails for a repository whose checks can't run there.
- Identities are recorded claims and the person check is a terminal check;
  neither is authentication.
- The ledger lives only as long as the retained session; after a prune, the
  pull request section is the final record and new overrules are refused.
- An edited test floors a change at `full`, adding the QA seat to every such
  change.

### Mitigations

- The packet shows added hunks too, and every seat judges edited tests, so a
  weakening that only adds lines still meets a reviewer.
- A repository whose checks can't run from a temporary worktree records an
  observation pair, which the same acceptance covers.
- Rule ids and the record name every refusal, and the interim rule is built to
  be replaced by the shared decision record when it lands.
- `record` falls back to the pull request section, labelled reconstructed.
- An added-only change keeps today's `standard` floor.
