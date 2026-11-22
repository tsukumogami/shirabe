# Document Check Steps

The seven document skills (/brief, /prd, /design, /plan, /vision, /strategy,
/roadmap) and /review-plan run the document checks from their own phase
files, so a standalone run and the same skill under /scope or /charter do the
same thing and record the same telemetry. This file says what each call does
and how the steps around it go; each phase file carries its own commands,
with its document, format, skill and a fixed `--phase`.

Three scripts do the work:

- `scripts/doc-check.sh` runs `shirabe validate` on the document and gives
  every check-held rule an outcome: `pass`, `fail`, `not_ready` (the input
  isn't written yet) or `error`. It exits 1 only when a rule at the `block`
  stage fails, and then prints one `::koto-finding::` line per failure; every
  other outcome exits 0, so a check never holds the skill on something that
  isn't written yet.
- `scripts/doc-events.sh sections` records which required sections the last
  document commit wrote for the first time or rewrote.
- `scripts/doc-events.sh fix` records which rules a fix answered:
  `--answers check_fail` for the last failing check, `--answers jury_fail` for
  the FAIL verdicts of the jury round the skill's session holds.

Recording is best effort: a koto without `koto review record`, a missing
session or a refused batch prints one line on stderr and the step goes on.
The records land on the session the skill already uses (its parent's under
/scope or /charter, else `<skill>-<topic>`). They are telemetry: nothing a
script records changes what the skill does next. Only `doc-check.sh`'s exit
code does.

## Committing a partial document

Every commit a document skill makes before the document is finished follows
one rule:

- **Commit a partial document only in a shape `shirabe validate` accepts.**
  For a design that is `status: Draft` with `problem` set and all nine
  required sections present, each one the run hasn't reached holding only the
  stub marker line `skills/design/references/design-format.md` defines. A
  validating pre-commit hook then takes the commit on the first try.
- **Make no commit when there is nothing new.** Before a commit, run
  `git status --porcelain -- <document>`; when it prints nothing, skip the
  commit. The calls that follow a commit (the sections call, a check) still
  run.
- Never pass `--no-verify`, and never write a field the document doesn't hold
  yet (a placeholder `decision`, an early `Proposed`) to get past the hook.
  When the hook refuses, fix what its findings name in the document and commit
  again.

## After a document commit

Each drafting commit, and each fix commit, is followed by the sections call:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/doc-events.sh" sections --doc <document> --format <format> --skill <skill>
```

## Before the jury

Just before the seats are spawned, and before `review-events.sh
round-started`, run the pre-jury check:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/doc-check.sh" --doc <document> --format <format> --moment pre_jury --phase <phase> --topic <topic> --skill <skill>
```

- **Exit 0**: spawn the jury. A pre-jury check that follows a clean post-fix
  check of the same commit records nothing and exits 0 at once: that check
  already serves as this round's pre-jury check.
- **Exit 1**: a block-stage rule failed. Fix what the findings name in the
  document, commit under the rule above, and run the fix loop below before
  spawning the jury.
- **Exit 2**: the call was refused (a wrong path or argument). Fix the call;
  it is never a verdict on the document.

## The fix loop

After every fix to the document, whether it answers a failing check or a
jury's FAIL verdicts, commit it under the rule above and record what it
answered, then check again
at the `post_fix` moment:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/doc-events.sh" fix --doc <document> --format <format> --answers <check_fail|jury_fail> --skill <skill>
"${CLAUDE_PLUGIN_ROOT}/scripts/doc-events.sh" sections --doc <document> --format <format> --skill <skill>
"${CLAUDE_PLUGIN_ROOT}/scripts/doc-check.sh" --doc <document> --format <format> --moment post_fix --phase <phase> --topic <topic> --skill <skill>
```

`--answers jury_fail` for a fix made after the jury, which reads the round's
FAIL verdicts from the seats' ingested keys; `--answers check_fail` for a fix
made after a failing check. While the post-fix check exits 1, fix what it
names, commit, and run the three calls again with `--answers check_fail`. A
failure only at the `warn` or `shadow` stage exits 0 and the run goes on with
that outcome recorded.

When a check prints `doc-check: unresolved after 3 cycles`, stop fixing: the
same moment has failed four times in a row. Take the skill's existing escape
for a significant issue: in an interactive run, present the findings to the
user with AskUserQuestion as the jury reference does for a significant FAIL;
under `--auto` (or an unattended parent), stop the run and report the
findings, as the skill's significant-issue bail does.

## What the phases mean

`--phase` selects which required sections count as written
(`references/doc-check-phases.json`). A rule whose section that phase hasn't
reached is `not_ready`, never `fail`. Each call site passes the phase it sits
in, fixed in its phase file; `scripts/doc-check-wiring_test.sh` holds every
call site to its phase.
