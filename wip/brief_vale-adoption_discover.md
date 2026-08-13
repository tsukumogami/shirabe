# Discover: vale-adoption

Grounded in the round-1 exploration (`wip/explore_vale-adoption_findings.md`
and five research files under `wip/research/`). No upstream ROADMAP exists;
this brief is authored from a freeform topic, so `upstream:` is omitted.

## Feature under framing

Deterministic prose checking across the two places this workspace produces
prose: agent instructions (SKILL.md, CLAUDE.md, AGENTS.md, README.md) and
shirabe-drafted artifacts (BRIEF/PRD/DESIGN/PLAN).

## Problem/outcome pair

**Problem candidate.** The writing-style rulebook exists in four divergent
copies plus one dangling pointer, only one of which is mechanical; that
mechanical copy covers seven words, cannot see the files where most
agent-authored prose lives, and the one defect class that actually recurs in
the corpus is invisible to every copy.

**Outcome candidate.** One rule source, enforced the same way on both
surfaces, catching the defects a drafting model structurally cannot catch
itself.

## Grounding facts carried from exploration

Measured on this repo:

- FC10 (`crates/shirabe-validate/src/checks.rs:2572`) checks seven words.
  The SKILL.md rulebook has roughly 60 words plus phrase, structural,
  formatting, and cognitive rules.
- `detect_format` (`crates/shirabe-validate/src/formats.rs:248`) prefix-matches
  eight artifact types, so `shirabe validate` returns "All checks passed"
  on SKILL.md, CLAUDE.md, AGENTS.md, and README.md. 211 files and 197,538
  words under `skills/` are mechanically unchecked.
- Across 554k words of shirabe prose, the phrase and word rules the rulebook
  spends most of its lines on fire roughly two true positives. Raw word-rule
  precision measured 1.7%; the two highest-volume hits (`tier` at 147,
  `journey` at 112) are domain vocabulary, and `## User Journeys` is a
  required BRIEF section.
- Em dashes: 3,195 in `docs/`, 1,222 in `skills/` — 7.84 per thousand words,
  72% of files above 3/1000. Frequency is a document-level property a model
  composing one sentence cannot see.
- A fluent, entirely vacuous three-paragraph document linted against
  write-good + proselint + Microsoft produced 10 alerts, none about the
  vacuity; the only error-level alert was "Use 'we've' instead of 'we have'."

## What the framing must NOT decide

The brief frames the problem tool-neutrally. Whether the answer is Vale, a
widened native check, or a mix is a DESIGN decision — the exploration left
three architectural alternatives genuinely open (native vs shell-out;
validate vs hook vs CI job; replace FC10 vs fix it). Naming a tool in the
Problem Statement would smuggle the solution.

## Journey entry points identified

1. An author editing a SKILL.md — the uncovered surface.
2. A shirabe skill drafting an artifact at its validate phase — the covered
   surface, where FC10 runs today.
3. A downstream adopter repo (koto, niwa, tsuku) consuming the reusable
   `validate-docs.yml` workflow.
4. A maintainer changing a style rule and needing it to take effect
   everywhere.

## Deferred to the PRD

- Whether enforcement blocks or reports.
- Which rule classes are in the initial set.
- Whether FC10 is replaced or extended.
