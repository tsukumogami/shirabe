# Red-first fixes

A fix starts from a check that fails for the reported reason, recorded before
the correcting change, and ends with the same check passing. This file says
how a `/work-on` run knows its unit is a fix, what it records, and which gates
read the records. `docs/designs/DESIGN-red-first-fixes.md` has the reasoning.

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

An observation pair counts only once someone other than the run accepts it.
This version can't record an acceptance yet, so a fix recorded by
observations stays held at `pass_counting`.

## The green

After a check passes (local verification, or a deferral to hosted CI), the run
enters `pass_counting`. For a fix with a red it re-runs the red's command at
HEAD, in a temporary worktree of the committed head:

```bash
red-first.sh green <session>
```

The fix is counted only when that green exited 0 at the current HEAD. A green
that exits non-zero is recorded too, and the run goes back to implementation.

## The gates and their rules

| Gate | State | Script | Rule |
|------|-------|--------|------|
| `kind_unchanged` | `fix_determination` | `fix-kind.sh agree` | none; it prints a `hold:` line |
| `red_recorded` | `reproduce` | `red-first.sh check-red` | `red-first/no-red` |
| `fix_green` | `pass_counting` | `red-first.sh check-green` | `red-first/no-green` |

| Rule | Holds when |
|------|------------|
| `red-first/no-red` | A fix has neither a red nor a before-observation, so it can't enter implementation. |
| `red-first/no-green` | A fix has no green that ran the red's command at HEAD and exited 0, or it is recorded by observations, which wait for an acceptance. |

A unit that isn't a fix passes both gates.
