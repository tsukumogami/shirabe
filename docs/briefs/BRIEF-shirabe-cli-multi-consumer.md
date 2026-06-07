---
schema: brief/v1
status: Accepted
problem: |
  The shirabe CLI was shaped for one caller, CI: a single GitHub Actions
  annotation output mode, no way to select an individual check, and a
  0/1 exit code. The skills and local hooks that also want to run the
  checks have no surface they can rely on.
outcome: |
  Whoever runs the CLI -- CI, a workflow skill, or a local hook -- gets
  the output mode and exit-code contract their context needs, can select
  a single check, and the existing CI annotation output keeps working
  unchanged.
---

# BRIEF: Multi-consumer CLI contract and UX

## Status

Accepted

Drafted under the tactical chain. The downstream PRD owns the
requirements; the DESIGN owns the flag grammar, the machine-output
schema and its versioning, and the exit-code numerics.

## Problem Statement

The shirabe CLI grew up serving exactly one caller. Today `shirabe
validate` emits GitHub Actions annotations on stdout, offers no way to
run one check instead of the whole set, and signals its result with a
two-value exit code: zero or non-zero. That shape is a clean fit for the
one place it runs -- a CI job that wants annotations inline on a pull
request and a pass/fail gate.

It is a poor fit for every other caller that wants the same checks. Two
of them already exist and one is latent:

- **The workflow skills** already shell out to `shirabe validate` and
  treat the exit code as the verdict, surfacing stdout verbatim. They
  have no machine-readable output to parse, so they cannot distinguish
  *which* check failed or read a structured reason -- they can only show
  the human the annotation text. And because the exit code is 0/1, a
  skill cannot tell "the document has violations" apart from "the tool
  itself broke" (a missing file, a parse error, a bad invocation). Those
  are different situations a caller must handle differently, and the
  current contract collapses them.

- **Local pre-commit hooks** would let a contributor catch a lifecycle
  or frontmatter violation before pushing, running the same authority CI
  runs. There is no scaffolding to set one up, so contributors discover
  violations only after CI fails.

- **Ad-hoc local runs** -- a developer debugging one rule against one
  file -- have no way to ask for just that check, and no human-readable
  mode tuned for a terminal rather than a CI annotation stream.

The gap is not a missing check. It is that the CLI speaks only CI's
dialect, so it cannot become the single shared authority the other
callers need. Until the surface widens, every non-CI caller either
reimplements the checks or does without.

## User Outcome

A person or process running shirabe gets the contract their context
needs from the same binary. A CI job still gets inline annotations and a
pass/fail gate, byte for byte what it gets today. A workflow skill gets
a machine-readable result it can parse to learn which check failed and
why, and an exit code that separates a clean run, a run that found
violations, and a run where the tool itself could not complete. A
contributor gets a command that scaffolds a local hook, so the checks
run before a push instead of after CI. A developer debugging one rule
asks for that one check and reads output shaped for a terminal.

The change the user feels: the checks stop being CI-only. The same
authority is now usable wherever the user works -- the editor loop, the
commit hook, the skill that shells out -- without anyone reimplementing
what CI already enforces.

## User Journeys

### A CI job gates a pull request

CI runs `shirabe validate` over the files a pull request changed, with
the paths handed in by the workflow. The CLI emits GitHub Actions
annotations on the changed files exactly as it does today, and exits
with a pass/fail code the job uses as its gate. Nothing about this path
changes -- the preserved annotation mode is the contract this journey
already depends on.

### A workflow skill reads a structured verdict

A workflow skill shells out to `shirabe validate` in its machine-
readable mode and passes the document paths it cares about. It parses
the structured output to learn which checks ran, which failed, and the
reason for each, then reads the exit code to decide its next move:
proceed on a clean run, surface the named violations on a violations
run, and escalate differently when the exit code says the tool could
not complete at all. The skill no longer has to scrape annotation text
to find out what went wrong.

### A contributor scaffolds a local hook

A contributor wants the checks to run before they push. They invoke the
CLI's hook-scaffolding command once; it installs a local pre-commit hook
that runs `shirabe validate` against the staged documents. From then on
a frontmatter or lifecycle violation surfaces at commit time, on the
contributor's machine, instead of after a CI round-trip.

### A developer debugs one rule

A developer is iterating on a single document and wants to check just
one rule without running the whole set. They invoke the CLI selecting
that one check, against that one file, and read the result in a human-
readable mode shaped for the terminal. They tighten the document and
re-run the single check until it passes.

## Scope Boundary

**In:**

- A machine-readable output mode the skills can parse, alongside a
  human-readable mode for terminal use.
- Preservation of the existing CI annotation output as one of the modes,
  unchanged from today's output (a parity corpus stays green).
- Per-check selection, so a caller can run one named check instead of
  the whole set.
- A multi-level exit-code contract that distinguishes a clean run, a run
  that found violations, and a run where the tool could not complete.
- A command that scaffolds a local pre-commit hook.
- The explicit per-consumer contract for the three callers (CI, the
  skills, local hooks), written down rather than implied.

**Out:**

- The exact flag grammar, the machine-output schema and how it is
  versioned, and the specific exit-code numbers. These are design
  decisions the downstream DESIGN settles, not framing the brief fixes.
- Computing which files changed. The CLI does not own git-diff;
  orchestrators (the CI workflow, the pre-commit hook) compute the file
  set and pass paths in, the way the CI workflow already does.
- Porting additional deterministic checks into the CLI so it can replace
  checks that still live outside it. Widening the consumption surface is
  this feature; growing the check set behind it is separate downstream
  work.
- Distributing the binary so non-CI callers can install a pinned version
  on their PATH. The skills and hooks need that to adopt the surface, but
  publishing and distribution is separate downstream work.
