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
| The run's own declaration | `declared` | `fix-kind.sh declare <session> --reason <why>`, at `fix_determination` or at `analysis` on a return there, when the report describes existing behaviour as wrong. |

A unit none of these marks is a change. It goes from `fix_determination`
straight to `implementation` and owes nothing below.

The determination only grows. A later `resolve` can turn a change into a fix
(a label added since), never the reverse: a fix stays a fix when its label is
removed, and `fix-kind.sh withdraw` is always refused, naming the recorded
source. The kind lives in the rebindable variable `UNIT_KIND`, which koto
routes on, and in the ledger `fix_kind.jsonl`; `fix-kind.sh` changes both
together. The `kind_unchanged` gate holds the run at `fix_determination` when
the two disagree, so a hand rebind of `UNIT_KIND` can't skip the red.

The report is stored once, as `fix_report.txt`: the plan step's Fixes line
when there is one, else the issue body, else the free-form task text, else the
step's context. It is what a red's passage is checked against.

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

An observation pair counts only once someone other than the run accepts it,
under the same rule as an edited test (below). Until a live acceptance covers
both observations' digests, `check-green` holds the fix at `pass_counting`.

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
not counted until someone other than the run accepts it. `pass_counting`'s
`tests_counted` gate (`test-change.sh status`) classifies the test files the
unit's committed diff touched since `impl_base`, with the `test` class of the
rules copy `review_level_choice` stored:

| Label | When |
|-------|------|
| `added` | The file is new, or its diff removes no line. |
| `edited` | The file is deleted, its diff removes a line, it is binary and changed, or it was renamed with a line changed. For a fix, also a reproducing test or harness file whose blob differs from the one the red ran. |
| `unchanged` | A rename that changes no line. |

Only `edited` files and observations need an acceptance. A unit with only
added tests is counted at once. The gate also holds over uncommitted changes
to tracked files and untracked files under a `test` path, since neither has
been classified.

The record is the context key `test_change_ledger.jsonl` in the run's own koto
session, written only by `test-change.sh`. Its first line, the header, is
written by `test-change.sh init` in `fix_determination`'s action: the author
(`agent:<session>`), `impl_base`, the work tree, the repository, the issue's
repository when it is another one, and whether the repository requires a
person (below), with the source of that answer. Every later attempt is judged
against it; a ledger with no header holds the unit, and `init` refuses to run
twice.

The same gate runs three times: at `pass_counting`, again at `pr_precheck`
(`tests_still_counted`, so a commit made after counting is held again before
the pull request opens), and at `ci_pass_counting` after CI passes on the open
pull request (below).

In a repository that is not person-required, a held run mints an acceptance
seat and hands it the seat's brief:

```bash
test-change.sh seat <session>     # prints agent:<session>/accept-<n>, then the brief
```

The seat runs one of the two commands the brief gives, under its minted
identity:

```bash
test-change.sh accept  <session> --as agent:<session>/accept-<n> --authority reviewer --all --reason '<why>'
test-change.sh decline <session> --as agent:<session>/accept-<n> --authority reviewer --all --reason '<why>'
```

An acceptance covers the items at the digests they have at the run's head (a
blob id, `deleted`, or an observation's digest). A commit that changes an
accepted file ends that acceptance: the unit is held again, `changed since
acceptance`, until a new seat accepts the new digest. A decline sends the run
back to implementation (`counting_status: declined`); the third decline of the
same set of paths ends the run at `done_blocked`. While implementing, record
why a test changed with `test-change.sh note <session> --file <path> --reason
'<why>'`; the brief carries each note to the seat.

### The interim rule

`scripts/lib/acceptance-rule.sh` decides every attempt, in this order, and
every refused attempt is recorded with the rule that refused it:

| Rule | Refuses |
|------|---------|
| `author` | The run's own identity (`agent:<session>`) accepting or overruling. |
| `authority-kind` | An agent acting as anything but `reviewer` or `coordinator`, or a person as anything but `reviewer` or `owner`. |
| `person-required` | Any agent acceptance in a repository that requires a person. |
| `unminted-seat` | An agent at `reviewer` that isn't an unused seat the run minted. |
| `unknown-session` | An agent at `coordinator` naming no existing koto session other than the run's. |
| `no-terminal` | A person's attempt without an interactive terminal. |
| `not-higher` | An overrule at an authority no higher than the acceptance's. |

Identities are recorded claims, not authentication: the run itself can mint a
seat and accept as it. The seat makes an accidental self-acceptance visible in
the record as a named seat; it doesn't stop a determined one.

The status gate replays the rule over every stored line each time it runs, and
never trusts a flag a line stores. A coordinator's acceptance counts only while
its koto session still exists: once that session is cleaned up, the acceptance
stops counting, so a coordinator that accepts keeps its session for as long as
that acceptance should stand. A coordinator's overrule or decline stays in
force after its session is cleaned up, since either one only holds the unit;
only a later acceptance lifts it, at the overruling's authority or above for an
overrule.

### A repository that requires a person

A repository declares in its `CLAUDE.md`:

```markdown
## Test Change Acceptance: person
```

`init` reads the declaration from `CLAUDE.md` at `impl_base` and at the remote
default branch's tip, so the unit's own diff can't relax it, and from the work
tree's `CLAUDE.local.md`. `person` at any of them wins, so a local file can only
tighten. A value that is neither `person` nor `agent`, or a header declared
twice, reads as `person`, and the header's `person_required_source` names it.

In such a repository no agent can accept (rule `person-required`), and `seat`
refuses to commission one. A held run stops at `pass_counting`: `status` names
each held file and prints the exact command a person runs in a terminal:

```bash
test-change.sh accept <session> --as person:<name> --authority owner --files <path>... --reason '<why>'
```

A person's attempt counts only from a terminal: stdin and stdout must be one
terminal, the process's controlling terminal. The script prints the covered
files, their digests and the edited hunks there, with control characters
escaped, and a six-character code derived from them and a fresh nonce, and
reads the code back from `/dev/tty`. Run without a terminal, or with a wrong
code, the attempt is refused `no-terminal` and recorded. An allowed person line
carries an integrity tag: a SHA-256 over the line keyed with a per-user key
file, `test-change.key` in the state directory (mode 0600). The status gate
counts a person line only when its tag checks, so a hand-written or edited
line never counts. That guards against accidents, not against an agent running
as the same user, which can read the key or drive a pseudo-terminal. The
terminal check was measured in a macOS shell and under a Python `pty` in the
test suite, which is the point: it shows a terminal, not a person.

### Overruling an acceptance

A higher authority can end an acceptance, before or after the run finished:

```bash
test-change.sh overrule <session> --as agent:<coordinator-session> --authority coordinator \
    --acceptance accept-<n> --reason '<why>'
```

`test-change.sh record <session>` lists acceptance ids. The overrule needs an
authority strictly higher than the acceptance's (rule `not-higher`):
`coordinator` over a `reviewer`, a person at `owner` over either. It covers the
items the acceptance covered, which are then held, `overruled <path> by
<identity>`. From then on an acceptance of those items counts only at or above
the overruling's authority: a fresh seat at `reviewer` leaves them held, a
coordinator or a person at `owner` counts them again.

An overrule writes to the run's retained session under the same lock, from any
directory, so it works after the run reached `done`.

### The record

Acceptances, refusals and overrulings live in the session ledger and nowhere
else: nothing here writes to a pull request, its body or its comments. They
read back through `test-change.sh record <session>`, which prints, for a
person or a coordinator, the fix source, the red and green or the
observations, each test file as added or edited, every acceptance, decline,
refusal, overrule and note with its time, and the unit's state. It works while
the unit is held and after the run finished, and says the state is undecided
when the run's work tree is gone.

### After CI: `ci_pass_counting`

A commit that edits a test while fixing CI on the open pull request is held
too. When CI passes, `ci_monitor` goes to `ci_pass_counting`, which runs the
same `fix_green` and `tests_counted` gates before the run goes on to
`cascade_entry` (a root) or `done` (a child of `/execute`). A seat, or a person
in a person-required repository, accepts there as at `pass_counting`; a decline
returns the run to `ci_monitor`, where the edit is reverted and pushed. A fix's
green recorded before the CI fix no longer matches HEAD: record it again.

## The gates and their rules

| Gate | State | Script | Rule |
|------|-------|--------|------|
| `kind_unchanged` | `fix_determination` | `fix-kind.sh agree` | none; it prints a `hold:` line |
| `red_recorded` | `reproduce` | `red-first.sh check-red` | `red-first/no-red` |
| `fix_green` | `pass_counting`, `ci_pass_counting` | `red-first.sh check-green` | `red-first/no-green` |
| `tests_counted` | `pass_counting`, `ci_pass_counting` | `test-change.sh status` | `test-change/held` |
| `tests_still_counted` | `pr_precheck` | `test-change.sh status` | `test-change/held` |

| Rule | Holds when |
|------|------------|
| `red-first/no-red` | A fix has neither a red nor a before-observation, so it can't enter implementation. |
| `red-first/no-green` | A fix has no green that ran the red's command at HEAD and exited 0, or it is recorded by observations that no live acceptance covers yet. |
| `test-change/held` | A pass came with an edited test or an observation that has no live acceptance, the ledger has no header, or the work tree has uncommitted changes. |

A unit that isn't a fix passes `red_recorded` and `fix_green`.
