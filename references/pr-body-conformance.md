# PR-body conformance: the mechanical rule

This reference is the single shirabe-owned authority for the **mechanical,
objectively-decidable** parts of the tsukumogami two-part PR convention. It is
what `shirabe validate --pr-body` enforces and what the PR-authoring skills
cite. State the rule here once; do not restate the checks inline in a skill or
a workflow. When the rule and the check disagree, the check
(`crates/shirabe-validate/src/pr_body.rs`) is the implementation of record and
this document describes it.

## Why a single source

PR-template conformance used to be stated inline in `/execute`'s
`pr_finalization` state and `/work-on`'s PR phase, with the canonical wording
living in a downstream consumer plugin's PR-creation skill. Two statements of
one rule drift, and a PR opened off the skill path (a manual `gh pr create`, a
dispatched worker) saw neither. Moving the mechanical rule into the validator
and pointing every consumer here makes conformance a property of the repo — a
path-independent CI gate enforces it — rather than a property of whichever code
path opened the PR.

## What the two-part convention is

The tsukumogami org squash-merges every PR. A PR body is two documents joined
by a single `---` separator:

- **Part 1** (above the separator) becomes the squash commit body that lands
  permanently on `main`. It is a factual description of the change.
- **Part 2** (from the `---` down) is reviewer context, deleted at merge.

The title must be [Conventional Commits](https://conventionalcommits.org/) so
the squashed commit reads cleanly.

## The gated checks (mechanical)

These checks are objective — a machine decides them with no judgment — so
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
  This moves one narrow, objective slice from advisory to gated: PB4 never
  inspects Part 2 section choice or Part 1 wording; it only rejects a commit
  body that was structured as a headed document. Like the other structural
  checks it scans the body with fenced code blocks removed, so a `##` shown
  inside an example fence does not trip it. It gates only ATX headings, the
  shape a template produces. A **setext** heading in Part 1 (a text line
  underlined by `===` or `---`) is an accepted residual: a `---` underline is
  parsed as the PB2 separator, so it cannot be gated as a heading without
  conflicting with PB2, and an `===` underline is left out to keep the check
  to the single common shape.
  Prose commit bodies essentially never use setext.
- **PB5 — no banned writing-style word (workflow gate only).** With
  `--writing-style <rules-file>`, the title and both parts of the body are
  checked against the banned words in `skills/writing-style/rules.yaml`, the
  list FC10 checks documents against, by the same matcher: inline and fenced
  code, table cells, link destinations, bare URLs and HTML comments are not
  prose; quoted text (a blockquote, or double quotes that pair on one line)
  isn't checked, since a verbatim quotation isn't the author's to reword;
  a title's `type(scope): ` prefix is skipped; and a term the
  repository declares under `## Prose Vocabulary:` is allowed. Each finding
  names the word, its body line or the title, and what the rules suggest
  instead. The /work-on and /execute pull request gate passes the flag with
  the plugin's own rules file and reports PB5 as `pr-body/banned-word`; CI
  and the PreToolUse hook below don't, so PB5 is enforced at the workflow
  gate only. The rule's one home is `rules.yaml`; it isn't restated here.

The structural checks (PB2, PB3) scan the body with fenced code blocks
removed, so a `---` or a `Co-Authored-By:` line shown inside an example
fence (as this document does) does not trip the check.

## Workflow content (workflow gate only)

No workflow records in a pull request body unless the repository opts in.
By default a body describes the change and how it was verified, in terms a
reader of the repository understands; the workflow's own records (the review
round, the run's record lines, pointers to PLAN and ROADMAP files, which are
deleted when the work completes) stay in the run's session. A repository opts
in with `## PR Workflow Content: include` in its `CLAUDE.local.md` or
`CLAUDE.md`, read by `scripts/pr-workflow-content.sh`, which a run records once
at its open and its gates read back (`--session`); with it, none of this
section applies, and a plan's run adds one Part 2 line naming its record,
`Run record: <session> (run <run_id>)`. Without it, the /work-on and /execute
pull request gate reports each of these, outside fenced code, as
`pr-body/workflow-content`: a `## Review panel` section title; a table whose
first row reads Seat, Model, Run, Verdict and Reviewed head; a line starting
`Plan:` or `Roadmap:`, or starting `Implements` and naming a `PLAN-` or
`ROADMAP-` file; and the run's own traces: a run marker comment, a run line
(`topic=`, `exit=`, `outcome=`, `intent=`, `mode=`, `store=`, `run=`), a
`## PR Index` or `## Merge Order` section title or a PR index line, a `Run record:`
line, and a `record:` or `unpinned` result line. The check
matches these shapes only, never words, so a body that discusses plans or
reviews in prose passes. CI and the PreToolUse hook don't run it.

## What stays advisory (subjective)

Everything else is judgment and is **not** gated:

- Which Part 2 sections a change needs (a test plan, an implementation note, a
  "what this enables") — reasoning-based, owned by the downstream PR-creation
  skill's framework, not this check.
- Whether Part 1 mentions an issue in prose, the exact wording of Part 1, and
  the shape of a minimal Part 2. A legitimate docs-only PR with a one-line
  Part 1 and a Part 2 that is only `Fixes #N` passes.

Gating any of these would fail correct PRs; the check deliberately confines
itself to the mechanical rules above so it never false-positives on a
well-formed minimal PR.

## Accepted residuals

The fenced-code exclusion covers the common false-positive source. Two residual
cases are accepted rather than handled, because PR bodies overwhelmingly use
fenced blocks:

- A body that places the literal footer text or a bare `---` at the top level,
  outside any fence, while not intending it structurally.
- The same content inside a 4-space **indented** code block, which the
  fenced-only scan does not strip.

Any of these is low-likelihood and resolved by rewording one line or fencing the
example.

## Consumers

- **CI** runs the mode on `pull_request` (`.github/workflows/pr-body.yml` and
  its self-caller), fetching the title and body via `gh` — the path-independent
  gate. Machine-authored PRs are exempt: a bot (dependabot, renovate, the
  Actions bot) emits a fixed body shape that cannot carry the two-part `---`
  convention, so gating it would false-positive every such PR. The reusable
  workflow skips the built-in bot set and any author a caller adds through its
  `exempt_authors` input; the rule itself is unchanged — only the set
  of PRs the CI surface applies it to.
- **`/execute`** (`pr_finalization`) and **`/work-on`** (PR phase) cite this
  reference for the mechanical rule while authoring the title and two-part
  body, so the body they produce and the rule CI enforces come from one source.
- **The client-side PreToolUse hook** (`shirabe pr-body-hook`, injected by niwa
  as a built-in default for shirabe adopters) runs the same `check_pr_body`
  engine against a `gh pr create` / `gh pr edit` command before it executes,
  catching a malformed PR at authoring time in any checkout. It reuses this
  rule, adding no checks of its own — the gated checks are stated here once and enforced
  by CI, the skills, and the hook alike.
