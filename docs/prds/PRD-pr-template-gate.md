---
schema: prd/v1
status: Done
problem: |
  PR-template conformance (Conventional Commits title plus the two-part
  squash-merge body) is enforced only where an automated skill authors the
  PR. A manual `gh pr create` or a dispatched worker has no signal, so a
  malformed body reaches merge and pollutes squash history — it already
  happened on #220 and was caught only by a human running a repair skill.
  The mechanical rule is also duplicated across `/execute` and a downstream
  plugin skill and single-sourced by neither.
goals: |
  Add a `shirabe validate --pr-body` static mode that checks the mechanical,
  objective parts of a PR (Conventional Commits title; body with exactly one
  `---` and a non-empty Part 1; no AI-attribution footer), wire it into a
  path-independent CI gate on `pull_request`, and single-source the rule into
  one shirabe-owned authority that `/execute` and `/work-on` cite instead of
  restating. Subjective Part 2 section selection stays advisory.
upstream: docs/briefs/BRIEF-pr-template-gate.md
source_issue: 221
complexity: Complex
---

# PRD: pr-template-gate

## Status

Done

The PRD operationalizes the upstream BRIEF's framing. Two questions are
left open for the DESIGN to settle and are tagged in Decisions and
Trade-offs: exactly where the mechanical/gated vs subjective/advisory
boundary is drawn, and the interface by which the title and body reach the
validate mode. Both are deliberately expressed as alternatives in the
requirements below.

## Problem Statement

The tsukumogami org squash-merges every PR. A PR body is two documents
joined by a single `---`: Part 1 above the separator becomes the commit
body that lands permanently on `main`, and everything from `---` down is
reviewer context deleted at merge. The title must be Conventional Commits
so the squashed commit reads cleanly. A malformed Part 1 or a
non-conventional title pollutes `main`'s history irreversibly.

Today this convention is enforced only on the automated skill path. The
mechanical shape is stated inline in `/execute`'s `pr_finalization` state
and `/work-on`'s PR-creation phase, and the canonical wording lives in a
PR-creation skill shipped by a downstream consumer plugin — not in shirabe.
shirabe's `/execute` template even points at a `skills/pr-creation/SKILL.md`
that does not exist in the shirabe repo, a dangling cross-plugin reference.

The consequences compound. A contributor running `gh pr create` by hand, or
a dispatched worker handed a bare "open a PR" instruction, gets nothing that
states or checks the template. It already broke: the PR for #220 was opened
by a dispatched worker with a generic `## What / ## Changes / ## Scope` body
and no `---` separator, and the gap surfaced only because a human noticed and
ran a repair skill. And because the rule is stated in two places and
single-sourced by neither, the two statements can drift.

The property the repo wants — a well-formed squash commit body regardless of
which code path opened the PR — is undefended. This is the same structural
defect #220 corrected for the DRAFT-vs-READY discipline: a rule encoded on
the happy path is invisible to the manual, coordinated, and dispatched paths.

## Goals

Move mechanical PR-body conformance off the automated happy path and behind
a path-independent gate, with the rule single-sourced inside shirabe, so
that:

- The mechanical, objective parts of a PR — the title format, the single
  separator with a non-empty Part 1, and the absence of an AI-attribution
  footer — are checked by an offline `shirabe validate` mode that both CI
  and the skills consume, mirroring how `--coordination-body` /
  `--merge-gate` already work.
- A CI check on `pull_request` runs that mode against the PR, catching a
  manual or dispatched PR, not only a skill-authored one — the check that
  would have failed #220 immediately.
- The mechanical rule lives in one shirabe-owned authority; `/execute` and
  `/work-on` cite it rather than each restating the checks, and the dangling
  cross-plugin reference is replaced with the shirabe authority.
- Subjective judgment — which Part 2 sections a change needs — stays with
  the author and is never gated. A legitimate minimal PR does not fail.
- *(Increment)* The same mechanical rule is also enforced at authoring time
  by an optional client-side hook, so a malformed PR is caught before it is
  created — in any checkout, even one with no CI wired — turning a reactive
  CI red into instant local feedback without a second copy of the rule.

## User Stories

- **As a contributor opening a PR by hand**, I want CI to tell me my title
  is not Conventional Commits or my body is missing its `---` separator, so
  a malformed squash body is caught before merge rather than after a human
  notices.
- **As a maintainer of a repo that receives dispatched-worker PRs**, I want
  the gate to fire on any PR regardless of who opened it, so the #220
  regression cannot recur silently.
- **As a skill author working in `/execute` or `/work-on`**, I want one
  shirabe authority stating the mechanical rule so the body I author and the
  rule CI enforces come from the same source and cannot drift.
- **As a contributor opening a legitimate docs-only PR**, I want a one-line
  Part 1 with a minimal Part 2 to pass, so a correct sparse PR is not a
  false positive.
- **As a maintainer reading a failing check**, I want the annotation to name
  the specific mechanical violation in plain terms, so I can tell what needs
  fixing without opening an out-of-band spec.

## Requirements

### Functional

**R1.** `shirabe validate` SHALL gain a `--pr-body <file>` static mode that
reads a PR body from FILE and checks it **offline** (no `gh`, no network),
mirroring the existing `--coordination-body` static mode. The mode SHALL be
mutually exclusive with `--lifecycle`, `--lifecycle-chain`, `--merge-gate`,
`--coordination-body`, and positional file arguments, and SHALL report
through the shared `ValidateOutcome` exit-code contract (0 clean, 1
tool-error, 2 violations) in all three `--format` values (`human`, `json`,
`annotation`).

**R2.** The mode SHALL check the **title is Conventional Commits**:
`<type>[optional scope]: <description>` where `<type>` is one of the
accepted types (`feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`,
`chore`, `ci`, `build`), the description is non-empty, and the scope, when
present, is NOT an issue-number scope (e.g. `docs(issue-8):` fails). The
interface by which the title reaches the mode is settled by the DESIGN
(see Decisions and Trade-offs); a PR has a title distinct from its body, so
the mode MUST have access to both.

**R3.** The mode SHALL check the **body separator**: the body contains
exactly one line that is a bare `---` Part-1/Part-2 separator, and the
Part 1 above it (the prospective squash commit body) is non-empty
(non-whitespace). A body with zero separators fails; a body with more than
one bare `---` separator fails; a body whose Part 1 is empty fails.

**R4.** The mode SHALL check for **no AI-attribution / co-author footer**:
the body carries no "Generated with Claude Code" line, no
"Co-Authored-By: Claude" trailer, and no equivalent AI-authorship
attribution, matching the org convention that forbids AI attribution and
co-author lines.

**R5.** The set of mechanical checks in R2–R4 is the **gated** set; it is
the single source both CI and the skills consume. The precise boundary
between mechanical/gated checks and subjective/advisory guidance — for
instance whether Part 1 must avoid `Fixes #N`, or whether a minimum Part 2
shape is required — SHALL be settled by the DESIGN. Any check the DESIGN
classifies as subjective stays advisory and is NOT gated.

**R6.** A **shirabe-owned reference** SHALL state the mechanical rule as the
single authority (for example `references/pr-body-conformance.md`). The
validate mode implements that reference; `/execute`'s `pr_finalization`
state and `/work-on`'s PR-creation phase SHALL cite it rather than restating
the mechanical checks inline, and the dangling
`skills/pr-creation/SKILL.md` reference in `skills/execute/koto-templates/execute.md`
SHALL be replaced with the shirabe authority. The downstream consumer's
PR-creation skill SHALL NOT be modified — the logic is migrated into
shirabe, not added to the downstream skill.

**R7.** A **reusable CI workflow** SHALL be added (for example
`.github/workflows/pr-body.yml`) that runs the `--pr-body` mode against a
PR. The workflow SHALL build the `shirabe` binary from source at the called
workflow's ref (matching the `validate-docs.yml` / `lifecycle.yml`
supply-chain pattern), obtain the PR title and body, and run the mode. Its
`permissions:` block SHALL grant only what reading the PR requires
(`contents: read`, plus `pull-requests: read` if the body is fetched via
`gh`). All actions SHALL be SHA-pinned; no floating tags.

**R8.** A **self-caller workflow** SHALL invoke the reusable workflow on
this repo's own PRs, triggering on `pull_request` with the event types that
cover body/title edits — at least `[opened, edited, reopened,
synchronize, ready_for_review]` — so a body edited after opening is
re-checked. The gate SHALL be path-independent (no `paths:` filter that
would let a malformed PR through based on which files it touches).

### Non-functional

**R9.** The `--pr-body` mode SHALL be fully offline and deterministic: it
reads only the provided title and body, performs no network or `gh` call,
and its findings depend only on its inputs. (The CI workflow may use `gh`
to fetch the PR body, but the validator process itself does not.)

**R10.** The mode SHALL produce **no false positives on a legitimate
docs-only PR** with a minimal Part 2: a `docs:` title, a one-line non-empty
Part 1, a single `---`, and a Part 2 that is only `Fixes #N` SHALL pass.

**R11.** Each finding SHALL be an actionable, plain-language "what to fix and
why" message in the same shape as the `--coordination-body` findings, so a
maintainer reading a CI annotation needs no out-of-band spec lookup.

**R12.** Test coverage SHALL include: a well-formed PR (pass); a
non-conventional title (fail R2); an issue-number scope (fail R2); a missing
`---` separator (fail R3); more than one `---` separator (fail R3); an empty
Part 1 (fail R3); an AI-attribution footer (fail R4); and the docs-only
minimal Part 2 (pass, R10). Skill-reference single-sourcing SHALL be covered
by the relevant skill evals.

### Client-side enforcement (increment)

Added after the CI gate (R1–R12) shipped. These requirements bring the local
PreToolUse hook — originally deferred in Out of Scope — into scope as a second
enforcement surface that reuses the R1 engine.

**R13.** shirabe SHALL provide a **PreToolUse hook adapter** that reuses the
R2–R4 checks (the `check_pr_body` engine, NOT a reimplementation) to evaluate
a `gh pr create` / `gh pr edit` command before it runs. The adapter SHALL be
a fail-safe binary entrypoint (following the `work-summary` hook precedent):
it reads a Claude Code hook JSON on stdin, always exits 0, and never aborts a
turn with a non-zero code. It performs no network or `gh` call.

**R14.** The adapter SHALL extract the submitted title and body from the
command's argv — `--title`, `--body`, and `--body-file <path>` — by scanning
argv tokens, never by shell-evaluating the command. A `--body-file` path is
read from disk; `--fill`, `--web`, `--body-file -`, an unreadable file, or a
command that is not a recognized `gh pr create`/`edit` SHALL be treated as
"nothing to check" and allowed.

**R15.** When a title and/or body is extractable and the R2–R4 checks return
findings, the adapter SHALL **deny** the tool call and return the findings as
the decision reason, so the agent sees what to fix and can re-issue a
corrected command. When the checks are clean, or in any ambiguous case in
R14, the adapter SHALL **allow** (fail-open). The choice of deny over
advisory-warn, and of fail-open on ambiguity, SHALL be recorded in the
DESIGN. The attacker-controlled title/body SHALL reach the decision reason
only as a structured (JSON-encoded) value, never string-concatenated.

**R16.** The hook **registration** (the settings wiring that installs the
PreToolUse hook) SHALL be **delegated to `tsukumogami/dot-niwa`**, following
the `work-summary` wiring precedent (`tsukumogami/dot-niwa#4`): shirabe owns
the binary subcommand and the rule; dot-niwa owns the pass-through hook script
and the `workspace.toml` registration that `niwa apply` projects into each
repo. This PRD's implementation opens the dot-niwa issue/PR; the shirabe side
builds and tests without it.

## Acceptance Criteria

- [ ] `shirabe validate --pr-body <file>` exists, is offline, and is
  mutually exclusive with the other validate modes and positional files.
- [ ] A PR whose title is not Conventional Commits fails the check.
- [ ] A PR whose title uses an issue-number scope (e.g. `docs(issue-8):`)
  fails the check.
- [ ] A PR body with no `---` separator fails the check.
- [ ] A PR body with more than one bare `---` separator fails the check.
- [ ] A PR body whose Part 1 is empty fails the check.
- [ ] A PR body carrying an AI-attribution or co-author footer fails the
  check.
- [ ] A well-formed PR (Conventional Commits title, one `---`, non-empty
  Part 1, no attribution footer) passes.
- [ ] A docs-only PR with a `docs:` title, a one-line Part 1, one `---`, and
  a Part 2 that is only `Fixes #N` passes (no false positive).
- [ ] The mode reports through the shared exit-code contract (0/1/2) and
  supports `--format human|json|annotation`.
- [ ] A reusable CI workflow builds the binary from source and runs the
  `--pr-body` mode against a PR; a self-caller runs it on this repo's PRs on
  `pull_request` with an event surface that re-checks edited bodies, with no
  `paths:` filter.
- [ ] All workflow YAML uses SHA-pinned actions and grants read-only
  permissions.
- [ ] A shirabe-owned reference states the mechanical rule; `/execute` and
  `/work-on` cite it, and the dangling `skills/pr-creation/SKILL.md`
  reference is replaced. The downstream consumer's PR-creation skill is
  unchanged.
- [ ] `cargo build` and `cargo test` pass; new unit tests cover the R12
  cases.
- [ ] All edits are public-visibility clean and use no banned writing-style
  words.
- [ ] *(Increment)* A `shirabe pr-body-hook` PreToolUse adapter exists, reads
  hook JSON on stdin, always exits 0, and reuses `check_pr_body` (no second
  copy of PB1–PB3).
- [ ] *(Increment)* A `gh pr create` with a malformed title or body is denied
  with a reason naming the finding; a clean one is allowed with no output.
- [ ] *(Increment)* A `gh pr edit` setting only a title runs PB1; setting only
  a body runs PB2–PB3; a `gh pr edit` that changes neither is allowed.
- [ ] *(Increment)* `--fill`/`--web`, an unreadable or `-` `--body-file`, a
  non-`gh` command, and malformed stdin all fail open (allow, no output).
- [ ] *(Increment)* The hook registration is delegated to `tsukumogami/dot-niwa`
  via an opened issue/PR; the shirabe change builds and tests independently.

## Out of Scope

- Changing the PR template itself. The two-part body and the Conventional
  Commits title stay exactly as they are; this work enforces the existing
  convention, it does not redesign it.
- Gating Part 2 section selection. Which reviewer-context sections a change
  needs stays reasoning-based per the downstream PR-creation guidance; the
  gate never inspects Part 2 section choice.
- Modifying the downstream consumer's PR-creation skill. The mechanical
  logic is migrated into shirabe; the downstream skill is left untouched.
- ~~The optional local PreToolUse hook matching `gh pr create` / `gh pr edit`.~~
  **Now in scope** as the R13–R16 increment: the hook was originally deferred
  here as a follow-up, and this PRD was extended to specify it once the CI
  gate had shipped. It remains a convenience layer over the same rule, not a
  replacement for the path-independent CI gate.
- Closing the dispatch gap (routing dispatched PR-opening work through a
  template-applying skill or loading the PR-creation guidance in the brief).
  This is a workflow-authoring change orthogonal to the gate.
- Live PR-state validation via `gh` inside the validator. The mechanical
  checks are offline; anything needing live PR state stays in `--merge-gate`.

## Decisions and Trade-offs

The DESIGN owns two questions, left as alternatives above so the DESIGN can
pick the option matching shirabe's existing tooling patterns.

**Mechanical/advisory boundary (R5).** The gate must check only what a
machine can decide objectively. The tight reading gates exactly R2–R4
(title, separator + non-empty Part 1, attribution footer). A broader reading
could also gate, e.g., "Part 1 contains no `Fixes #N`" or "Part 2 is
present". Trade-off: each additional gated check risks a false positive on a
legitimate PR (the #220 acceptance property is "no false positives on
docs-only minimal Part 2"), while too tight a gate lets a stylistic problem
through to advisory-only. The DESIGN draws the line and records which checks
are gated vs advisory.

**Title/body interface to the mode (R2).** A PR title is distinct from its
body, so the `--pr-body <file>` mode needs the title too. Alternatives:

- A separate `--pr-title <string>` argument alongside `--pr-body <file>` —
  explicit, but the CI workflow must pass two inputs and the local caller
  must supply the title.
- A convention where the title is the first line of the `--pr-body` file
  (blank line, then the body) — one input, but conflates two artifacts and
  diverges from how `gh pr view` returns them.
- Title check optional: `--pr-body` checks only body-level rules (R3–R4)
  and the title (R2) is checked by the CI workflow's own step. Trade-off:
  splits the single-source authority across the validator and the workflow.

The DESIGN evaluates these against the `--coordination-body` precedent (a
single `<file>` input) and the way the CI workflow obtains the PR title and
body.

## References

- `docs/briefs/BRIEF-pr-template-gate.md` — the upstream BRIEF; this PRD
  operationalizes its framing.
- `docs/briefs/BRIEF-lifecycle-draft-ready-discipline.md` and
  `docs/prds/PRD-lifecycle-draft-ready-discipline.md` — the #220 sibling
  work that fixed the same happy-path defect for the lifecycle discipline;
  the CI-wiring and single-sourcing patterns mirror it.
- `references/coordination-strategy.md` — the coordination-PR body is the
  worked precedent for a skill-authored body checked statically by
  `shirabe validate --coordination-body`; the `--pr-body` mode follows the
  same static-check shape.
- `.github/workflows/lifecycle.yml` and `.github/workflows/validate-docs.yml`
  — the existing reusable validator workflows whose SHA-pinning and
  binary-build patterns the PR-body workflow mirrors.
- `skills/execute/koto-templates/execute.md` — the `pr_finalization` state
  carrying the inline mechanical rule and the dangling
  `skills/pr-creation/SKILL.md` reference this work single-sources.
