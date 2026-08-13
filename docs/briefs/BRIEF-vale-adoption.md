---
schema: brief/v1
status: Draft
problem: |
  The writing-style rulebook lives in four divergent copies, only one of
  which is mechanical. That copy checks seven words, cannot see the files
  where most agent-authored prose lives, and misses the one defect class
  that actually recurs in the corpus.
outcome: |
  One rule source enforced the same way on both prose surfaces (agent
  instructions and drafted artifacts), reporting the defects a drafting
  model structurally cannot catch in itself, and staying quiet about the
  ones it already avoids.
motivating_context: |
  A round-1 exploration measured the corpus rather than reasoning about
  it, and inverted the premise it started from: mechanical prose checking
  already ships here, and the rules it does not cover are mostly rules
  the model already obeys. What it does not cover, and what nothing
  covers, is document-level frequency.
---

## Status

Draft

The framing is tool-neutral by construction. The answer might be an
external linter, a widened native check, or a mix; that choice is a DESIGN
decision. The exploration left three architectural alternatives open and
this brief does not settle them.

## Problem Statement

This workspace produces prose in two places and governs it in neither
consistently.

The governing rules live in `skills/writing-style/SKILL.md`: roughly 60
banned words plus phrase patterns, structural patterns, formatting tells,
over-formality substitutions, and four cognitive tells. That rulebook has
been copied three more times: into a seven-word constant behind the
validator's FC10 check
(`crates/shirabe-validate/src/checks.rs:2551`), into a five-word quick
reference in the workspace CLAUDE.md, and into a five-word instruction
inside the BRIEF jury's structural reviewer. A fifth pointer, from
CLAUDE.md to `.claude/helpers/writing-style.md`, resolves to nothing. The
design that specified the validator check required it read the list from
the SKILL.md at validate time so updates would propagate; the shipped code
hardcodes it, and the four-way divergence is the direct consequence.

Three of those four copies are applied by model judgment. The fourth,
FC10, is deterministic but narrow, and it cannot see most of the prose it
would govern: `detect_format` prefix-matches eight artifact types, so
`shirabe validate` reports "All checks passed" on every SKILL.md,
CLAUDE.md, AGENTS.md, and README.md in the repo. That leaves 211 files and
197,538 words under `skills/` alone entirely unchecked, and it is exactly
the prose that instructs every future agent run.

The harder half of the problem is that widening the word list would buy
almost nothing. The phrase apparatus produces roughly two true positives
across 554,000 words of this workspace's prose, and raw word-rule
precision measures 1.7%, rising to about 16% once the domain terms and the
one document that quotes the rulebook are excluded. The two highest-volume
matches are that domain vocabulary: `tier` accounts for 128 of 156 alerts
in a `docs/` run and is the Tier 1–4 decision-complexity vocabulary, and
`journey` at 112 hits is a required BRIEF section heading. A drafting
model reliably avoids the words already on the seven-word list. The rules
it obeys are the mechanizable ones.

What no copy of the rulebook catches is frequency. Counting body prose
only, em dashes run 3,114 in `docs/` and 1,188 in `skills/`. In `docs/`
that is 7.84 per thousand words, with 72% of files above 3 per thousand
and the worst at 28.5; `skills/` runs a comparable 7.59. The rulebook
names em
dash overuse as a formatting tell and the corpus it governs is saturated
with it, because frequency is a document-level property and a model
composing one sentence at a time cannot see it. Bold density and
sentence-length uniformity have the same shape: real, measurable, and
structurally outside what self-review can reach.

## User Outcome

A maintainer changes a prose rule once and it takes effect everywhere the
workspace writes prose, in the skills that instruct agents and in the
artifacts those agents draft, without hunting for four copies that have
drifted apart.

An author editing a SKILL.md gets the same prose feedback a drafted DESIGN
gets, on the file they are actually editing, instead of the silence that
surface returns today.

And the feedback is worth reading. It reports the frequency defects that
accumulate invisibly across a document rather than re-flagging words the
drafting model already avoids, so the signal stays high enough that
nobody learns to ignore it. Domain vocabulary that happens to appear on a
banned list (`tier`, `journey`) does not generate noise against the
workspace's own terms of art.

## User Journeys

### An author edits a skill and gets prose feedback on it

A maintainer opens `skills/execute/SKILL.md` to revise a phase
description. Today `shirabe validate` on that path prints "All checks
passed" because the file's name does not start with one of the eight
artifact prefixes, so nothing has ever checked it. The trigger is the
edit itself; the outcome shape is that the author sees the same prose
findings on an instruction file that a drafted artifact would produce,
scoped so that imperative voice and bold labels, which are load-bearing in
a file that instructs a model, do not register as defects.

### A drafting skill checks its own artifact before the jury sees it

`/design` finishes drafting `DESIGN-<topic>.md` and reaches its validate
phase. The trigger is the artifact landing on disk. Today FC10 runs and
reports seven words against the body, including matches inside fenced code
blocks and URLs, at line numbers offset by the length of the frontmatter.
The outcome shape is that the phase gets accurate findings (right line,
prose only) and that those findings name the document-level properties the
drafting model could not observe about its own output.

### An adopter repo inherits the checking without configuring it

koto, niwa, and tsuku each call shirabe's reusable `validate-docs.yml`
from their own workflows, pinned at `@main`. The trigger is a PR in one of
those repos touching a doc. The outcome shape is that whatever prose
checking shirabe settles on arrives through the channel already wired,
without each adopter hand-installing a tool or copying a rule file, and
that the arrival does not require every adopter's CI to grow a dependency
it cannot satisfy.

### A maintainer changes a rule once

A maintainer decides `tier` should stop being flagged, because it is this
workspace's own vocabulary. The trigger is the edit. Today that means
finding four copies (a SKILL.md table, a Rust constant behind a binary
release, a CLAUDE.md quick reference, and a jury reviewer's prose
instruction) and keeping them consistent by hand. The outcome shape is
one edit in one place, with the change reaching every surface that
enforces it.

## Scope Boundary

**In scope:**

- Consolidating the writing-style rules to a single source that every
  enforcing surface reads, replacing the current four divergent copies.
- Prose checking on agent instructions: SKILL.md, CLAUDE.md, AGENTS.md,
  and README.md, which no mechanical check reaches today.
- Prose checking on shirabe-drafted artifacts, where FC10 currently runs.
- Rules for document-level frequency properties (em dash density, bold
  density, sentence-length uniformity) that a drafting model cannot
  observe about its own output.
- Suppressing the workspace's domain vocabulary (`tier`, `journey`) so it
  does not fire against the terms of art the repo defines.
- Whether findings block or report, and at which severity.

**Out of scope:**

- Choosing the mechanism. Whether this is an external linter, a widened
  native check in `shirabe validate`, a Claude Code hook, a CI job, or a
  combination is left to the DESIGN. The exploration found three
  alternatives genuinely open and naming one here would smuggle the
  answer into the framing.
- Detecting the cognitive tells. Low information density, empty
  conclusions, unresolved demonstratives, and uncited attribution stay
  with model judgment and the jury reviewers. A fluent, entirely vacuous
  document produced ten alerts under three off-the-shelf style packages
  and not one was about the vacuity; no token matcher reaches this, so
  the feature does not promise it.
- Rewriting the writing-style rules themselves. Their content is settled;
  only where they live and what enforces them is in question.
- Cleaning the existing corpus. Bringing 3,114 em dashes under whatever
  threshold gets chosen is follow-on work, and it is the reason a
  threshold rule cannot ship enabled-and-blocking on day one.
- Repairing three defects in the existing check, as defects of that
  check: FC10's frontmatter line-number offset, FC10's matches inside code
  fences and URLs, and `check_claude_md_conventions` being unreachable
  because `detect_format` never routes CLAUDE.md to it. Each is
  independently fileable. Note the boundary carefully: whatever checking
  this feature settles on must report correct line numbers and skip code
  fences, inline code, and URLs by construction, and that property is IN
  scope. Repairing today's FC10 so that it has those properties is not.
- Prose checking on commit messages, issue bodies, and PR descriptions.
  That prose never lands on disk in a checkable location, and the
  plumbing to reach it is disproportionate to the value.

## Open Questions

- Must an adopter repo be able to read the single rule source without
  installing shirabe? The answer bounds where that source can live, and
  the PRD can settle the requirement even though the location is a DESIGN
  choice.
- Is FC10 replaced or extended? The answer follows from the mechanism
  choice, but the PRD should state which outcome counts as success so the
  DESIGN is not free to leave two overlapping checks in place.
- What severity does a frequency finding carry on first release, given
  that the corpus does not currently satisfy any threshold worth setting?
