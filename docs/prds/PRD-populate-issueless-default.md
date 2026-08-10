---
schema: prd/v1
status: Done
problem: |
  `shirabe roadmap populate` files one GitHub issue per feature when invoked
  with no mode flag, so a mistaken invocation leaves a side effect on shared
  remote state. And `/roadmap` never populates at all -- the workflow ends at
  the Phase 4 jury, populate is reachable only by a human typing a second
  command, and FC16 is shape-gated, so an empty reserved-section skeleton
  validates at every lifecycle state and nothing ever complains.
goals: |
  The subcommand creates no issues and makes no `gh` call unless the caller
  names the issue-creating mode. `--issues` names it, `--no-issues` still names
  issueless, and passing both is an error. A `/roadmap` run fills both reserved
  sections issuelessly without a second human invocation. Filing issues is a
  separate explicitly-invoked action behind the existing approval gate that
  regenerates the table with issue links. No in-repo caller depends on the
  default.
upstream: docs/briefs/BRIEF-populate-issueless-default.md
motivating_context: |
  A maintainer decision on blast radius, not ergonomics. This supersedes
  decision driver D5 of DESIGN-roadmap-issueless-preference.md, which required
  the default to stay `required` for backward compatibility. A recommendation
  to fix this only at the skill layer was raised and overruled.
---

# PRD: Populate issueless by default

## Status

Done

Requirements for flipping the `shirabe roadmap populate` default to issueless
and making `/roadmap` populate its own reserved sections. The four open
questions the upstream brief left are settled in
`docs/designs/current/DESIGN-populate-issueless-default.md`, not here; this
document says what must be true, not how the workflow is wired.

## Problem Statement

`shirabe roadmap populate <path>` with no mode flag runs the issue-creating
path: one `gh issue create` per feature, then an issue-keyed table and diagram.
The issueless path exists and is complete — it makes no `gh` call at all — but
you only get it by knowing to pass `--no-issues`.

That default puts the expensive failure on the side you reach by accident.
Populating issuelessly by mistake produces a local file edit you notice
immediately and re-run past in a second. Populating issue-creatingly by mistake
produces issues on a repository other people share, which someone then has to
close by hand. Both mistakes are equally easy to make; only one of them leaves
a mess outside the working tree.

The second half of the problem is that the reserved sections usually don't get
filled at all. `/roadmap`'s workflow ends at Phase 4, the jury review. Populate
lives in input mode 3 and only runs when a human types `/roadmap populate
<path>`. FC16, the check that guards those sections, tests shape rather than
status: the empty skeleton the roadmap template ships passes at Draft, at
Active, and at Done. So the normal path through the tooling produces a roadmap
whose Implementation Issues table and Dependency Graph are empty placeholders,
carries it through jury review and activation and merge, and never once
surfaces the omission. Flipping the default without closing that hole would
make the tool safer at the one moment it is least often reached.

## Goals

- Make the unflagged invocation inert with respect to GitHub.
- Give the issue-creating path an explicit name of its own, so both modes are
  things you ask for rather than things you get.
- Fill the reserved sections as part of the workflow that creates the roadmap,
  rather than as a step a human has to remember.
- Keep issue creation deliberate, gated, and after approval rather than before.
- Leave no in-repo caller whose behaviour depends on which default is in force.
- Record the supersession of D5 where a future reader will find it, and warn
  direct CLI users that their invocation changed meaning.

## User Stories

**As a maintainer creating a roadmap,** I want the reserved sections filled by
the time I review the draft, so the document I approve is the document that
merges, and so I never approve a roadmap whose tables are empty placeholders.

**As a maintainer who has approved a roadmap,** I want to file its issues as a
separate deliberate step, so issue creation happens once I have decided the
feature list is right rather than while I am still editing it.

**As a contributor running the CLI directly,** I want an unflagged invocation
to touch only my working tree, so exploring what the command does cannot file
issues on a repository I share with other people.

**As a contributor who mistyped,** I want passing both mode flags to fail
loudly, so I never discover months later that one half of my command line was
silently discarded.

**As a future maintainer,** I want to find a written record of why the default
inverted, so the reversal of a documented decision driver does not read as an
unexplained regression.

## Requirements

### Subcommand behaviour

- **R1.** `shirabe roadmap populate <path>` invoked with neither `--issues` nor
  `--no-issues` SHALL run the issueless render path. It SHALL create no GitHub
  issues and SHALL make no `gh` invocation of any kind, including the `gh repo
  view` call used to resolve the owner/repo for issue links.
- **R2.** `shirabe roadmap populate <path> --issues` SHALL run the
  issue-creating path with behaviour identical to today's unflagged
  invocation, including `--milestone`, `--milestone-description`, `--mapping`,
  `--output-map`, and `--repo`.
- **R3.** `shirabe roadmap populate <path> --no-issues` SHALL continue to run
  the issueless render path with unchanged behaviour. The spelling is retained,
  not deprecated, and remains an explicit opt-out.
- **R4.** Passing both `--issues` and `--no-issues` in the same invocation
  SHALL be rejected with a non-zero exit and a message naming both flags as
  mutually exclusive. The invocation SHALL NOT resolve to either mode, SHALL
  NOT mutate the roadmap, and SHALL NOT call `gh`.
- **R5.** `shirabe roadmap populate --help` SHALL document both mode flags and
  SHALL state which mode runs when neither is given.

### Workflow behaviour

- **R6.** A `/roadmap` run that creates a roadmap SHALL fill both the
  Implementation Issues and Dependency Graph reserved sections before the run
  ends, without a separate human invocation.
- **R7.** The automatic population in R6 SHALL run issuelessly. It SHALL create
  no issues and SHALL NOT present the approval gate, because no gated action
  occurs.
- **R8.** The automatic population SHALL happen early enough that the roadmap
  the author reviews and approves is the populated one, not an empty skeleton
  the tool fills afterwards.
- **R9.** Filing issues SHALL be a separate action a human invokes explicitly.
  It SHALL NOT be folded into the automatic workflow run and SHALL NOT run
  before the roadmap is approved.
- **R10.** The issue-filing action SHALL run behind the existing approval gate
  (R14 in the roadmap skill's requirements), which SHALL continue to live in
  the calling skill and SHALL NOT move into the subcommand.
- **R11.** The issue-filing action SHALL regenerate both reserved sections, so
  the Implementation Issues table it leaves behind carries issue links rather
  than the labels the issueless render wrote.

### Mode resolution

- **R12.** The mode SHALL resolve on the `flag > CLAUDE.md-header > default`
  stack the repo already uses for its other convention headers, with the
  `## Roadmap Issues:` header as the middle layer.
- **R13.** The default layer SHALL be issueless. A repo with no `## Roadmap
  Issues:` header and an invocation with no flag SHALL get the issueless path.
- **R14.** Every invocation of the subcommand originating in this repository —
  skill prose, documentation examples, and tests — SHALL name its mode
  explicitly. After this change no in-repo code path SHALL reach populate
  without a mode flag. The CLI default is a backstop for a human at a shell; it
  SHALL NOT be the mechanism any workflow depends on.

### Record-keeping

- **R15.** A decision record SHALL supersede decision driver D5 of
  `DESIGN-roadmap-issueless-preference.md` and SHALL state the blast-radius
  reasoning behind the inversion.
- **R16.** A release note SHALL name the default flip as a breaking change for
  anyone invoking `shirabe roadmap populate` directly.

### Constraints

- **R17.** Existing tests SHALL be updated to name their mode rather than
  deleted. Coverage of the issue-creating path SHALL NOT decrease.
- **R18.** `crates/shirabe-validate/src/checks.rs` SHALL NOT change. FC16
  staying shape-gated is a constraint on this work, not a target of it.

## Acceptance Criteria

- [ ] **AC1 (R1).** `shirabe roadmap populate <roadmap>` on a roadmap with
      features exits 0, fills both reserved sections in issueless form, and
      makes no `gh` invocation — verified by the PATH-injection harness the
      existing suite already uses to detect `gh` calls.
- [ ] **AC2 (R2).** `shirabe roadmap populate <roadmap> --issues` produces
      byte-identical output to what the unflagged invocation produced before
      this change, for the same roadmap and the same mapping input.
- [ ] **AC3 (R3).** Every existing `--no-issues` test passes unchanged.
- [ ] **AC4 (R4).** `shirabe roadmap populate <roadmap> --issues --no-issues`
      exits non-zero, names both flags in the message, and leaves the roadmap
      file byte-identical to its pre-invocation content.
- [ ] **AC5 (R5).** `shirabe roadmap populate --help` output contains both
      `--issues` and `--no-issues` and states the no-flag behaviour.
- [ ] **AC6 (R6, R7).** A `/roadmap` run started from an unpopulated roadmap
      ends with both reserved sections carrying rendered content and the
      repository's issue list unchanged.
- [ ] **AC7 (R8).** The populated sections are present in the document at the
      point the approval walkthrough presents it to the author.
- [ ] **AC8 (R9, R10).** The issue-filing action is reachable only by explicit
      invocation, and presents the approval gate before any `gh issue create`
      runs.
- [ ] **AC9 (R11).** After the issue-filing action completes, the
      Implementation Issues table's Issues column carries issue links, not
      `needs-*` labels.
- [ ] **AC10 (R12, R13).** With no `## Roadmap Issues:` header present and no
      flag passed, the resolved mode is issueless; a `## Roadmap Issues:
      required` header resolves the skill's populate invocation to the
      issue-creating mode; a flag overrides the header in both directions.
- [ ] **AC11 (R14).** A repository-wide search for `roadmap populate`
      invocations finds no call site — in `skills/`, `docs/`, `references/`, or
      `crates/*/tests/` — that omits a mode flag. Prose that merely names the
      subcommand without invoking it is exempt.
- [ ] **AC12 (R15).** A decision record exists under `docs/decisions/` that
      names D5, states it is superseded, and gives the reasoning.
- [ ] **AC13 (R16).** The release notes for the shipping version name the
      default flip and describe what a direct CLI caller must change.
- [ ] **AC14 (R17).** `cargo test --workspace` is green, and the count of tests
      exercising the issue-creating path is no lower than before the change.
- [ ] **AC15 (R18).** `git diff` touches no file under
      `crates/shirabe-validate/src/checks.rs`.
- [ ] **AC16.** `shirabe validate` runs clean over the repository's own docs
      after the change.

## Out of Scope

- Dropping or deprecating `--no-issues`. Both spellings stay.
- The issueless table's rendering, which shipped in #262.
- Issue #263, the FC06 `F<n>` index alias.
- What the `Issues` column carries in issueless mode. Carrying a `needs-*`
  label in a column the shared spec describes as an issue fan-out is a known
  divergence, deliberately left alone.
- Teaching FC16 to be status-gated, or any other validator check change. The
  empty-skeleton-validates-everywhere behaviour is why this work matters, but
  changing it is a validation-surface question and a different feature.
- Moving the approval gate into the subcommand.
- Backfilling reserved sections on roadmaps that already exist and already
  merged empty.

## References

- `docs/briefs/BRIEF-populate-issueless-default.md` — the upstream framing.
- `docs/designs/current/DESIGN-roadmap-issueless-preference.md` — introduced
  issueless mode; decision driver D5 is what R15 supersedes.
- `docs/prds/PRD-roadmap-issueless-table-rendering.md` — the sibling PRD that
  specified what the issueless table renders.
- `skills/roadmap/references/roadmap-format.md` — Reserved Sections, and the
  FC16 shape-gating that lets an empty skeleton validate at every state.
- `references/fixes/claude-md-conventions.md` — the `## Roadmap Issues:` header
  format the R12 resolution stack uses.
