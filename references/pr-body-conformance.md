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

These three checks are objective — a machine decides them with no judgment — so
they are gated. `shirabe validate --pr-body <file> [--pr-title <string>]`
enforces them offline (no `gh`, no network).

- **PB1 — Conventional Commits title** (checked when a title is supplied). The
  title is `<type>[optional scope][!]: <description>` where:
  - `<type>` is one of `feat`, `fix`, `docs`, `style`, `refactor`, `perf`,
    `test`, `chore`, `ci`, `build`;
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

The structural checks (PB2, PB3) scan the body with fenced code blocks
removed, so a `---` or a `Co-Authored-By:` line shown inside an example fence
(as this document does) does not trip the check.

## What stays advisory (subjective)

Everything else is judgment and is **not** gated:

- Which Part 2 sections a change needs (a test plan, an implementation note, a
  "what this enables") — reasoning-based, owned by the downstream PR-creation
  skill's framework, not this check.
- Whether Part 1 mentions an issue in prose, the exact wording of Part 1, and
  the shape of a minimal Part 2. A legitimate docs-only PR with a one-line
  Part 1 and a Part 2 that is only `Fixes #N` passes.

Gating any of these would fail correct PRs; the check deliberately confines
itself to the three mechanical rules so it never false-positives on a
well-formed minimal PR.

## Accepted residuals

The fenced-code exclusion covers the common false-positive source. Two residual
cases are accepted rather than handled, because PR bodies overwhelmingly use
fenced blocks:

- A body that places the literal footer text or a bare `---` at the top level,
  outside any fence, while not intending it structurally.
- The same content inside a 4-space **indented** code block, which the
  fenced-only scan does not strip.

Either is low-likelihood and resolved by rewording one line or fencing the
example.

## Consumers

- **CI** runs the mode on `pull_request` (`.github/workflows/pr-body.yml` and
  its self-caller), fetching the title and body via `gh` — the path-independent
  gate. Machine-authored PRs are exempt: a bot (dependabot, renovate, the
  Actions bot) emits a fixed body shape that cannot carry the two-part `---`
  convention, so gating it would false-positive every such PR. The reusable
  workflow skips the built-in bot set and any author a caller adds through its
  `exempt_authors` input; the rule itself (PB1–PB3) is unchanged — only the set
  of PRs the CI surface applies it to.
- **`/execute`** (`pr_finalization`) and **`/work-on`** (PR phase) cite this
  reference for the mechanical rule while authoring the title and two-part
  body, so the body they produce and the rule CI enforces come from one source.
