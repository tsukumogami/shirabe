# PR-body conformance: the mechanical rule

This reference is the single shirabe-owned authority for the **mechanical,
objectively-decidable** parts of the tsukumogami two-part PR convention. It is
what `shirabe validate --pr-body` enforces and what the PR-authoring skills
cite. State the rule here once; do not restate the checks inline in a skill or
a workflow. When the rule and the check disagree, the check
(`crates/shirabe-validate/src/pr_body.rs`) is the implementation of record and
this document describes it.

## What the two-part convention is

The tsukumogami org squash-merges every PR. A PR body is two documents joined
by a single `---` separator:

- **Part 1** (above the separator) becomes the squash commit body that lands
  permanently on `main`. It is a factual description of the change.
- **Part 2** (from the `---` down) is reviewer context, deleted at merge.

The title must be [Conventional Commits](https://conventionalcommits.org/) so
the squashed commit reads cleanly.

## The gated checks (mechanical)

These four checks are objective — a machine decides them with no judgment — so
they are gated. `shirabe validate --pr-body <file> [--pr-title <string>]`
enforces them offline (no `gh`, no network).

- **PB1 — Conventional Commits title** (checked when a title is supplied). The
  title is `<type>[optional scope][!]: <description>` where:
  - `<type>` is one of `feat`, `fix`, `docs`, `style`, `refactor`, `perf`,
    `test`, `chore`, `ci`, `build`, `revert`;
  - the description after `: ` is non-empty;
  - the optional scope is not an **issue-number scope**. Issue numbers are
    never a scope — `docs(issue-8):`, `chore(#8):`, and `fix(8):` all fail.
    The rejection is pinned to the numeric shape `^(issue[-_]?)?#?\d+$`
    (case-insensitive), so a legitimate word scope such as `issue-tracker` or
    `issues` is not over-matched. Put issue references (`Fixes #N`) in Part 2,
    not in the title.
- **PB2 — one separator, non-empty Part 1.** The body has exactly one
  top-level line that is a bare `---`, and the Part 1 above it contains
  non-whitespace text. Zero separators, more than one, or an empty Part 1 each
  fail. A second `---` is ambiguous because everything from the first `---`
  down is deleted at merge; use `***` or `___` for a horizontal rule in Part 2,
  or fence the example.
- **PB3 — no AI-attribution footer.** The body carries no `Co-Authored-By:`
  trailer attributing to an AI assistant (Claude/Anthropic) and no "Generated
  with Claude Code" line. The org convention forbids AI attribution and
  co-author lines.
- **PB4 — no markdown section heading in Part 1.** Part 1 (the prospective
  squash commit body) contains no markdown ATX heading line: a line whose first
  non-whitespace content is a run of one-to-six `#` followed by a space (or is
  the whole line), pinned to the CommonMark ATX shape. A clean commit message is
  prose; a `## Root cause` / `## Fix`-style heading above the separator means
  Part 1 was written as a template document rather than a commit body, and that
  heading structure lands permanently on `main`. The check runs only when Part 1
  is well-defined (exactly one separator, non-empty Part 1) and is scoped to the
  text above the separator — Part 2 is reviewer context and may use `## Section`
  headings freely. Why it is objective, not subjective: PB4 gates the *presence
  of a heading construct*, which a parser decides with no judgment, not *which
  sections Part 1 should have* or *how it should be worded* (those stay
  advisory). A `#` that is not a heading — an issue reference (`#123`), a shebang
  (`#!/bin/sh`), a preprocessor line (`#include`), or a run of seven or more `#` —
  is not matched, so a prose Part 1 that mentions one is never a false positive.

The structural checks (PB2, PB3, PB4) scan the body with fenced code blocks
removed, so a `---`, a `Co-Authored-By:` line, or a `##` shown inside an example
fence (as this document does) does not trip the check.

## What stays advisory (subjective)

Everything else is judgment and is **not** gated:

- Which Part 2 sections a change needs (a test plan, an implementation note, a
  "what this enables") — reasoning-based, owned by the downstream PR-creation
  skill's framework, not this check.
- Whether Part 1 mentions an issue in prose, the exact wording of Part 1, and
  the shape of a minimal Part 2. A legitimate docs-only PR with a one-line
  Part 1 and a Part 2 that is only `Fixes #N` passes.

Gating any of these would fail correct PRs; the check deliberately confines
itself to the four mechanical rules so it never false-positives on a
well-formed minimal PR.
