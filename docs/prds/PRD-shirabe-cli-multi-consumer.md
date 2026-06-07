---
schema: prd/v1
status: In Progress
problem: |
  The shirabe `validate` command serves CI and only CI: it emits GitHub
  Actions annotations as its sole output, runs every applicable check as
  one monolithic pass with no way to select an individual check, and
  returns a 0/1 exit code that cannot tell "found violations" apart from
  "the tool could not run". The workflow skills that shell out to it and
  the contributors who would run it locally have no surface they can rely
  on, so the checks stay CI-only.
goals: |
  Widen `validate` into the surface three consumers share -- CI, the
  workflow skills, and local pre-commit hooks -- by adding a
  machine-readable output mode and a human-readable mode alongside the
  preserved annotation mode, per-check selection over the check codes
  that already exist, a multi-level exit-code contract that matches the
  scheme `transition` and `finalize-chain` already use, and a command
  that scaffolds a local hook. The existing CI annotation output stays
  byte-for-byte identical.
upstream: docs/briefs/BRIEF-shirabe-cli-multi-consumer.md
---

# PRD: Multi-consumer CLI contract and UX

## Status

In Progress

## Problem Statement

The `shirabe validate` command was built for one caller and shows it. It
emits GitHub Actions annotations (`::error file=...,line=...::message`)
as its only output mode; it runs every applicable check for a document as
a single monolithic pass with no way to ask for one check; and it returns
a two-value exit code, success or failure.

That shape fits CI, where a job wants annotations inline on a pull request
and a binary pass/fail gate. It fits no other caller of the same checks:

- **The workflow skills** shell out to `validate` and read the exit code
  as the verdict, surfacing stdout verbatim. Because the only output is
  GitHub Actions annotation text, a skill cannot reliably learn *which*
  check failed or read a structured reason -- it can only echo annotation
  lines a human then reads. And because the exit code is 0/1, a skill
  cannot distinguish "the document has violations" from "the tool itself
  could not run" (a missing file, a bad invocation, a parse failure).
  Those demand different handling, and the current contract collapses
  them into one non-zero code. The codebase already proves the better
  shape elsewhere: `transition` and `finalize-chain` return a multi-level
  exit code (clean / tool-error / lifecycle-violation / I/O), but
  `validate` does not share it.

- **Local pre-commit hooks** would let a contributor catch a frontmatter
  or lifecycle violation before pushing, running the same checks CI runs.
  No command scaffolds such a hook today, so contributors find violations
  only after a CI round-trip.

- **Ad-hoc local runs** -- a developer debugging one rule against one file
  -- cannot ask for a single check, and have no terminal-shaped output;
  they get CI annotation syntax in their terminal.

The named checks already exist as addressable codes (the FC-family, the
R-family, the L-family, SCHEMA, FC-CONVENTIONS), and the orchestrator
contract is already right -- CI computes the changed-file set and passes
paths in; the CLI does not own git-diff. What is missing is the consumer-
facing surface on top of that: output modes, per-check selection, an
exit-code contract that carries more than pass/fail, and hook scaffolding.
Until that surface exists, every non-CI caller either reimplements the
checks or does without.

## Goals

- A caller can choose its output mode: a machine-readable mode the skills
  parse, a human-readable mode for terminal use, and the existing GitHub
  Actions annotation mode, which CI keeps getting unchanged.
- A caller can run a single named check (or a named subset) instead of
  the whole pass, addressing the check codes that already exist.
- A caller can read an exit code that distinguishes a clean run, a run
  that found violations, and a run where the tool could not complete --
  the same multi-level shape `transition` and `finalize-chain` use.
- A contributor can scaffold a local pre-commit hook with one command.
- The three consumers' reliance on the command is written down as an
  explicit per-consumer contract, not left implied.
- None of this changes the annotation output CI depends on: it stays
  byte-for-byte identical, verified by a parity corpus.

## User Stories

- As a **CI workflow**, I run `validate` over the paths a pull request
  changed and get GitHub Actions annotations and a pass/fail gate exactly
  as I do today, so my behavior does not change when the surface widens.

- As a **workflow skill shelling out to `validate`**, I select the
  machine-readable output mode and parse a structured result to learn
  which checks ran, which failed, and why, then read a multi-level exit
  code so I can proceed on a clean run, surface named violations on a
  violations run, and escalate differently when the tool could not run at
  all.

- As a **contributor**, I run one command to install a local pre-commit
  hook that runs `validate` over my staged documents, so violations
  surface at commit time on my machine instead of after CI fails.

- As a **developer debugging one rule**, I run a single named check
  against a single file and read the result in a terminal-shaped output
  mode, so I can iterate on that one rule without the whole pass or CI
  annotation syntax.

## Requirements

### Functional

- **R1 -- Machine-readable output mode.** `validate` SHALL offer a
  machine-readable output mode that emits, for each document validated, a
  structured record of every check result: the check code, its severity
  (error or notice), the human-readable message, and the file and line it
  applies to. The structure SHALL be parseable by a consumer without
  scraping annotation text.

- **R2 -- Human-readable output mode.** `validate` SHALL offer a
  human-readable output mode shaped for a terminal (not GitHub Actions
  annotation syntax), summarizing the checks that ran and the violations
  found.

- **R3 -- Preserved annotation mode.** `validate` SHALL retain the
  existing GitHub Actions annotation output as a selectable mode. When
  that mode is in effect, the bytes emitted for a given set of inputs
  SHALL be identical to what the current command emits for the same
  inputs.

- **R4 -- Output-mode selection.** A caller SHALL be able to select which
  of the three output modes (machine-readable, human-readable, annotation)
  a run uses. The default mode SHALL be chosen so that existing CI
  invocations continue to receive annotation output without changing their
  invocation. (The exact flag grammar is a design decision; see Out of
  Scope.)

- **R5 -- Per-check selection.** A caller SHALL be able to restrict a run
  to one named check, or a named subset of named checks, addressing the
  check codes that already exist. When a subset is selected, only those
  checks run and only their results are reported. When no selection is
  given, the full applicable pass runs as it does today, where
  "applicable" means the checks that apply to each document's detected
  format (the same set the command runs for that format today). A
  selection that names a check code that does not exist SHALL be reported
  as a tool error rather than silently ignored.

- **R6 -- Multi-level exit-code contract.** `validate` SHALL return an
  exit code that distinguishes at least three outcomes: a clean run (no
  violations), a run that completed but found violations, and a run that
  could not complete because of a tool error (unreadable file, bad
  invocation, parse failure). The scheme SHALL be consistent with the
  multi-level exit codes `transition` and `finalize-chain` already use.
  A clean run SHALL exit zero and any non-clean outcome SHALL exit
  non-zero, so existing pass/fail gates keep working. Only error-level
  check results constitute violations for the exit code; notice-level
  results SHALL NOT by themselves make a run non-clean, preserving the
  current behavior where notices are reported but do not fail the run.
  When a single run validates multiple documents, the exit code SHALL
  reflect the most severe outcome across all of them (tool-error
  outranks violations, which outranks clean). (The exact numeric
  assignments are a design decision; see Out of Scope.)

- **R7 -- Hook-scaffolding command.** The CLI SHALL provide a command that
  installs a local pre-commit hook. Once installed, the hook SHALL run
  `validate` over the staged documents at commit time. When a pre-commit
  hook is already present, the command SHALL leave it unmodified and
  report that an existing hook was found (a checkable observable: the
  on-disk hook is byte-unchanged and the command signals the collision),
  and SHALL offer an explicit opt-in to overwrite, so a contributor with
  a pre-existing hook still has a path to adopt.

- **R8 -- Per-consumer contract documented.** The repository SHALL carry
  written documentation of what each of the three consumers (CI, the
  skills, local hooks) relies on from `validate`: which output mode, how
  the exit code is interpreted, and how paths are supplied.

### Non-functional

- **R9 -- Orchestrator owns path selection.** `validate` SHALL NOT compute
  which files changed. Callers continue to pass document paths as
  arguments; the CI workflow and the pre-commit hook compute the file set
  and hand paths in. This preserves the current contract.

- **R10 -- Backward-compatible CI invocations.** The existing CI workflow
  invocations of `validate` (the changed-files mode and the lifecycle
  modes) SHALL continue to work without modification: same default output,
  same pass/fail behavior at the exit-code level.

- **R11 -- Versioned machine-readable schema.** The machine-readable
  output SHALL carry a version identifier so a consumer can pin the shape
  it parses and detect when the shape changes. (How the version is encoded
  and evolved is a design decision; see Out of Scope.)

- **R12 -- Architectural design required.** This feature changes the
  command's output surface, exit-code contract, and subcommand set, and
  leaves several architectural choices open (flag grammar, machine-output
  schema and versioning, exit-code numerics, hook-install mechanism). It
  therefore warrants a downstream DESIGN before implementation.

## Acceptance Criteria

- [ ] Running `validate` in machine-readable mode over a document with
      known violations emits a structured, parseable record listing each
      violation's check code, severity, message, file, and line.
- [ ] Running `validate` in human-readable mode over the same document
      emits a terminal-shaped summary and no GitHub Actions annotation
      syntax.
- [ ] Running `validate` in annotation mode over a corpus of inputs emits
      bytes identical to the pre-change command for the same inputs (a
      parity corpus passes).
- [ ] A caller that does not select an output mode receives annotation
      output, so an unchanged CI invocation behaves as before.
- [ ] Selecting a single named check runs only that check and reports only
      its results; selecting a named subset of more than one check runs
      exactly those checks; selecting no check runs the full applicable
      pass.
- [ ] Selecting a check code that does not exist exits with the tool-error
      code rather than running silently or reporting clean.
- [ ] A clean run exits zero; a run that finds violations exits with the
      violations code; a run that cannot complete (unreadable file, bad
      invocation, parse failure) exits with the tool-error code; the codes
      are distinct and consistent with the `transition`/`finalize-chain`
      scheme.
- [ ] Any non-clean outcome exits non-zero, so a pass/fail gate that only
      checks zero-vs-non-zero still gates correctly.
- [ ] A run over a document that produces only notice-level results (no
      error-level results) exits zero (clean), preserving the current
      notice behavior.
- [ ] A single run over multiple documents that mixes clean, violations,
      and a tool-error file exits with the tool-error code (most-severe
      outcome wins); a run mixing clean and violations exits with the
      violations code.
- [ ] `validate` is never given a git ref or diff range and never reads
      git history to discover files: given an explicit path list it
      validates exactly those paths and nothing else.
- [ ] Running the hook-scaffolding command installs a working pre-commit
      hook that runs `validate` over staged documents; re-running it with a
      hook already present leaves that hook byte-unchanged and reports the
      collision; running it with the explicit overwrite opt-in replaces the
      hook.
- [ ] The repository contains documentation stating, per consumer (CI,
      skills, hooks), which output mode it uses, how it reads the exit
      code, and how paths are supplied.
- [ ] The machine-readable output carries a version identifier.
- [ ] The existing CI workflow invocations of `validate` run unchanged and
      gate as before.

## Out of Scope

- **The exact flag grammar.** Which flags name the output modes and the
  per-check selection, and their spellings, are design decisions for the
  downstream DESIGN, not requirements fixed here.
- **The machine-output schema shape and its versioning mechanism.** That
  the output is structured, parseable, and versioned is required (R1,
  R11); the concrete schema and how the version is encoded and evolved are
  design decisions.
- **The exact exit-code numbers.** That the scheme is multi-level,
  zero-for-clean, non-zero-for-not-clean, and consistent with the existing
  commands is required (R6); the specific integers are a design decision.
- **Computing changed files.** The CLI does not own git-diff (R9);
  building a `--changed-only` mode into the binary is explicitly excluded.
- **Porting additional deterministic checks into the CLI.** Growing the
  set of checks behind this surface so the CLI can replace checks that
  still live outside it is separate downstream work. This PRD widens the
  consumption surface over the checks that exist; it does not add checks.
- **Distributing the binary to non-CI consumers.** Publishing a pinned,
  installable build so skills and hooks can resolve the binary on a
  contributor's PATH is separate downstream work. This PRD defines the
  surface those consumers install against; it does not ship the
  distribution.

## Decisions and Trade-offs

- **Align validate's exit codes with the existing commands rather than
  inventing a new scheme.** `transition` and `finalize-chain` already
  return a multi-level exit code (clean / tool-error / lifecycle-violation
  / I/O). Reusing that shape for `validate` keeps the CLI's exit-code
  contract coherent across commands and lets a consumer learn one scheme.
  The alternative -- a validate-specific scheme -- was rejected because it
  would force consumers to special-case per command. The exact numeric
  mapping (where "violations found" sits relative to "tool error") is left
  to the DESIGN, since validate's normal failure mode (violations) differs
  from transition's (a refused edge).

- **Preserve the annotation mode byte-for-byte rather than regenerating
  it.** CI depends on the current annotation bytes. The annotation output
  is held to an identical-bytes parity bar (R3) rather than a "looks
  equivalent" bar, so a consumer that parses annotation text sees no
  change. The trade-off is reduced freedom to tidy the annotation format;
  that freedom is deliberately given up to protect the live consumer.

- **Keep path selection with the orchestrator.** The current contract --
  CI and hooks compute the file set, the CLI validates the paths handed in
  -- is kept rather than absorbing git-diff into the binary (R9). This
  keeps the CLI a pure function of its inputs and avoids coupling it to any
  one VCS layout.

## Known Limitations

- The machine-readable schema, once consumers pin it, becomes a contract
  whose evolution is constrained by R11's versioning. Early schema churn
  is cheaper than late churn; the DESIGN should weigh how much to stabilize
  before the skills adopt it.
- Per-check selection is bounded to the checks that already exist. A
  consumer cannot select a check that has not yet been ported into the
  CLI; that porting is out of scope here.
