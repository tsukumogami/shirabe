# Red-first fixes

A fix starts from a check that fails for the reported reason, recorded before
the correcting change, and ends with the same check passing. This file says
how a `/work-on` run knows its unit is a fix, what it records, and which gates
read the records. `docs/designs/current/DESIGN-red-first-fixes.md` has the reasoning.

## Which units are fixes

A run decides at `fix_determination`, after the review level is chosen and
before implementation. `scripts/fix-kind.sh resolve` runs there as the state's
action and records the unit as a fix when any of these holds:

| Source | Recorded as | Where it comes from |
|--------|-------------|---------------------|
| A fix label on the issue | `label:<name>` | The labels listed in the repository's `## Fix Labels:` declaration in `CLAUDE.md`, read at the run's base. `bug` when the repository declares none. Comma-separated; a label may contain spaces. |
| A plan step's Fixes line | `step` | A `**Fixes**:` line in the step, which `/execute` passes to the run as `FIX_REPORT`. |
| The run's own declaration | `declared` | `fix-kind.sh declare <session> --reason <why>`, at `analysis`, before the run submits its plan, when the report describes existing behaviour as wrong. `resolve` keeps a fix declared there. |

A unit none of these marks is a change. It goes from `fix_determination`
straight to `implementation` and owes nothing below.

The run doesn't stop at `fix_determination`. koto resolves a tick's routes with
the variables as the tick started, so a `UNIT_KIND` the action has just bound
can't route that tick. The routes test the `kind_route` gate instead,
`fix-kind.sh kind <session> --exit --current "$UNIT_KIND"`, which reads the
kind the action has just written to the ledger: exit 0 for a change goes to
`implementation`, exit 3 for a fix to `reproduce`, in the tick that entered
the state. Any other exit holds the run there: 4 (no kind recorded, because
the action failed), 1 (a non-empty `UNIT_KIND` that disagrees with the
ledger), 66 (a koto read failed) or 2 (`PLUGIN_ROOT` doesn't reach the plugin).

The determination only grows. A later `resolve` can turn a change into a fix
(a label added since), never the reverse: a fix stays a fix when its label is
removed, and `fix-kind.sh withdraw` is always refused, naming the recorded
source. The kind lives in the rebindable variable `UNIT_KIND`, which koto
routes on, and in the ledger `fix_kind.jsonl`; `fix-kind.sh` changes both
together. A hand rebind of `UNIT_KIND` away from the ledger, made before the
run enters `fix_determination`, holds the run there: `kind_route` exits 1 and
the `kind_unchanged` gate prints a `hold:` line naming both, so the rebind
can't skip the red. `fix-kind.sh declare` puts a fix back.

The report is stored once, as `fix_report.txt`: the plan step's Fixes line
when there is one, else the issue body, else the free-form task text, else the
step's context. It is what a red's passage is checked against. A plan-backed
child taken from a PLAN outline (`ISSUE_SOURCE=plan_outline`) has no issue
body: its issue number is the outline's, so no GitHub issue is read for its
report or its labels. A fix round started with `fix-round.sh start --fix-report
<text>` has that text as its Fixes line, so the round's red can cite the CI
failure or review finding that caused it.

## The red

At `reproduce` the run writes the test that reproduces the bug, commits it,
and records the red:

```bash
red-first.sh red <session> --marker '<text>' --passage-file <file> -- <command> [<arg>...]
```

The red runs the command on the base code (`impl_base`) in a temporary
worktree, with every test file the unit's committed diff touched copied in from
HEAD and nothing else of the unit's. So it fails without the correcting change
even when that change is already committed. Only committed test files are
copied. When an existing, untouched test reproduces the bug, name it with
`--tests <path>...`.

It is recorded only when every one of these holds; otherwise it prints a
`refused:` line naming the first that fails and records nothing:

- the unit is recorded as a fix;
- the marker is at least 8 characters and the passage at least 20;
- the marker is in the passage, and the passage is verbatim in the report;
- the command exits non-zero;
- its output holds the marker. A check that fails for another reason, a
  compile error say, is refused here.

The record keeps the command, the base, the reproducing tests and any harness
files the command names with their blob ids, the exit, the last 40 lines of
output (at most 4,096 bytes), the lines around the marker, the passage, the
marker and the time. The command gets only `PATH`, `HOME`, `LANG` and `TMPDIR`
from the environment, runs in its own process group, and is killed after
`--timeout` seconds (600 unless given). That keeps credential variables out
by accident; it is not a sandbox, and the agent could run the command anyway.

The marker shows the check failed with the reported symptom, not that it
failed for the reported cause. A test that prints the report and exits 1
would pass; review still judges whether the red exercises the reported case.

## Observations

When no automated check can reproduce the bug (a terminal-only or timing
failure), the run records an observation instead of the red:

```bash
red-first.sh observe <session> --phase before --file <observation.md>
```

The file is markdown with these `## ` sections: `Produced` (how the failure
was produced), `Environment`, `Seen` (what was seen, with the marker), `Why no
check`, `Passage` and `Marker`. The passage and marker meet the red's rules.
After the change, `--phase after` records the failure gone, with `Produced`,
`Environment` and `Seen`. A missing section is refused, naming it.

An observation pair counts only once the review panels have judged it. Every
seat's packet carries both observations and the report passage, and every seat
judges the pair `shown` or `not_shown`; the judgment is keyed by the pair's two
digests, so re-recording either observation makes the pair due for the panel's
re-verifier (`review-panel-orchestration.md`, "Observations"). Until a panel
has judged the pair as it is now, with no open `not_shown` finding,
`check-green` and `test-change.sh status` hold the fix at `pass_counting`,
naming `observation`.

## The green

After a check passes (local verification, or a deferral to hosted CI), the run
enters `pass_counting`. For a fix with a red it re-runs the red's command at
HEAD, in a temporary worktree of the committed head:

```bash
red-first.sh green <session>
```

The fix is counted only when that green exited 0 at the current HEAD. A green
that exits non-zero is recorded too, and the run goes back to implementation.

## Held test changes

A pass that came with an edited test, or a fix that rests on observations, is
not counted until the review panels have judged each such item as it is now.
`pass_counting`'s `tests_counted` gate (`test-change.sh status`) classifies the
test files the unit's committed diff touched since `impl_base`, with the `test`
class of the rules copy `review_level_choice` stored:

| Label | When |
|-------|------|
| `added` | The file is new, or its diff removes no line. |
| `edited` | The file is deleted, its diff removes a line, it is binary and changed, or it was renamed with a line changed. For a fix, also a reproducing test or harness file whose blob differs from the one the red ran. |
| `unchanged` | A rename that changes no line. |

Only `edited` files and the observation pair need a judgment. A unit with only
added tests is counted at once. The gate also holds over uncommitted changes
to tracked files and untracked files under a `test` path, since neither has
been classified.

### The panels judge, and the due rule

Every panel seat that runs judges each edited test `corrects` or `weakens`, and
the observation pair `shown` or `not_shown`; `panel-scope.sh --record` refuses
a round that skips one, and a `weakens` or `not_shown` is a blocking finding
(`review-panel-orchestration.md`). Each judgment is kept in the panels' record,
`verdict_ledger.json`, keyed by the item's content: a test's blob (or
`deleted`) and the pair's two digests.

An item is **due** for a panel when no seat or re-verifier of that panel judged
it at its content now. A judgment at other content doesn't count, whichever
seat made it, and only a judgment at a commit in HEAD's history counts. Before
any panel has recorded, every edited test and the pair are due: no panel has
judged them. `test-change.sh status` asks `panel-scope.sh --due-items` and
holds the unit, one `held:` line each, while any item is due for a panel
(`<path> due for <panel>`, `observation due for <panel>`, or `<item> due: no
panel has judged it`) or carries an open adverse finding (`<path> weakens: an
open finding of <panel>`, `observation not shown: ...`).

### The re-verifier

A commit that changes a judged test, or a re-recorded observation, makes the
item due again. The next round of that panel that would otherwise keep every
seat's verdict plans the panel's re-verifier for it
(`panel-scope.sh --plan`, reason `items-due`). Its packet carries each due
test's hunks with the run's note on why it edited the test, or the observation
pair, and it judges each one with the same verdicts the seats use; a
re-verifier that returns no judgment for a due item leaves it due. While
implementing, record why a test changed with `test-change.sh note <session>
--file <path> --reason '<why>'`; every packet that shows the test carries the
note, labelled as the run's claim.

A note's `--reason` is at most 300 bytes. A longer one is a usage error
(exit 64) that names the limit and the reason's length, and nothing is
recorded, so shorten it and run the command again. A reason is stored whole
or not at all.

A held run submits `counting_status: declined`: it returns to implementation,
where a weakening edit is reworked or reverted, and goes through the panels
again, whose re-verifier judges what is due. A unit routed as `docs` or `task`
runs no panel, so an edit it makes to a test is held as due until the run is
routed as `code`. Nothing waits for a person. `status` exits 3 when an item is
held and no further lap can clear it, and the run ends at `done_blocked`: when
`panel-retry-budget.sh --remaining` reports no retry left, and when the run
already went back once (`counting_status: declined`, read from koto's log of
the session) and still no panel has recorded, the docs or task route that
never reaches one.

### The ledger

The context key `test_change_ledger.jsonl` in the run's own koto session is
written only by `test-change.sh`. Its first line, the header, is written by
`test-change.sh init` in `fix_determination`'s action: the author
(`agent:<session>`), `impl_base`, the work tree and the repository. A ledger
with no header holds the unit, and `init` refuses to run twice. After the
header come the run's notes and relocate lines. No line but the header changes
whether the unit counts: the only ways past a hold are a judgment the run
records from a panel or re-verifier, or a change to the code or tests that
removes the item. A ledger from a run started before the panels took over may
hold the acceptance lines that version wrote; the gate never reads them, and
`record` lists them as legacy history.

The header's work tree can move: a run handed over to a new checkout is
rebound there (`koto session rebind`), and the old directory may or may not
still exist. Every call that reads the work tree to decide (`classify`,
`status` and `covered`) asks `koto session list` where the run's session is
bound. When that directory is in another work tree than the recorded one, the
run is classified against it, whether or not the old tree still exists,
provided it is the same work: its origin names the header's repository when
the header records one, and its HEAD has `impl_base` in its history. A bound
tree that isn't the same work stops the call (exit 2) naming both trees, and
so does a listing that fails or doesn't parse; nothing falls back to the
recorded tree then. When the listing gives the session no directory, or its
directory is gone, the older rule holds: a gone recorded work tree is followed
to the one the gate runs in when that is the same work, and any other case
stops the gate on the gone work tree.

A followed tree is used by `status`, which appends one `relocate` line naming
both paths and the HEAD moved to; every later call reads it in place of the
header's. `classify` and `covered` use it without writing anything, and
`record` reads only the relocate lines, each with its HEAD, never the
directory it's run from.

The same gate runs three times: at `pass_counting`, again at `pr_precheck`
(`tests_still_counted`, so a commit made after counting is held again before
the pull request opens), and at `ci_pass_counting` after CI passes on the open
pull request (below).

### The record

Nothing here writes to a pull request, its body or its comments. The record
reads back through `test-change.sh record <session>`, which prints, for a
person or a coordinator, the fix source, the red and green or the
observations, each test file as added or edited, every note and relocation
with its time, any legacy lines, and the unit's state as the panels' record
gives it. It works while the unit is held and after the run finished, and says
the state is undecided when the run's work tree is gone.

### After CI: `ci_pass_counting`

A commit that edits a test while fixing CI on the open pull request is held
too. When CI passes, `ci_monitor` goes to `ci_pass_counting`, which runs the
same `fix_green` and `tests_counted` gates before the run goes on to
`cascade_entry` (a root) or `done` (a child of `/execute`). A held unit is
counted there from the panels' record, as at `pass_counting`; `declined`
returns the run to `ci_monitor`, where the edit is reverted and pushed. A
fix's green recorded before the CI fix no longer matches HEAD: record it
again.

## The gates and their rules

| Gate | State | Script | Rule |
|------|-------|--------|------|
| `kind_route` | `fix_determination` | `fix-kind.sh kind --exit` | none; a routing gate (0 a change, 3 a fix, 4 no kind, 1 a disagreeing `UNIT_KIND`) |
| `kind_unchanged` | `fix_determination` | `fix-kind.sh agree` | none; it prints a `hold:` line |
| `red_recorded` | `reproduce` | `red-first.sh check-red` | `red-first/no-red` |
| `fix_green` | `pass_counting`, `ci_pass_counting` | `red-first.sh check-green` | `red-first/no-green` |
| `tests_counted` | `pass_counting`, `ci_pass_counting` | `test-change.sh status` | `test-change/held` |
| `tests_still_counted` | `pr_precheck` | `test-change.sh status` | `test-change/held` |

| Rule | Holds when |
|------|------------|
| `red-first/no-red` | A fix has neither a red nor a before-observation, so it can't enter implementation. |
| `red-first/no-green` | A fix has no green that ran the red's command at HEAD and exited 0, or it is recorded by observations the review panels have not judged `shown` as they are now. |
| `test-change/held` | A pass came with an edited test or an observation pair that is due for a review panel or carries an open `weakens` or `not_shown` finding, the ledger has no header, or the work tree has uncommitted changes. |

A unit that isn't a fix passes `red_recorded` and `fix_green`.
