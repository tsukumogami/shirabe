---
schema: design/v1
status: Planned
problem: |
  The mechanical parts of PR-template conformance (Conventional Commits
  title; a two-part body with one `---` separator and a non-empty Part 1;
  no AI-attribution footer) are enforced only where a skill authors the PR,
  and are restated in two places single-sourced by neither. A manual or
  dispatched PR bypasses them, and the two statements can drift.
decision: |
  Add a `shirabe validate --pr-body <file> [--pr-title <string>]` offline
  mode that gates exactly three code-fence-aware mechanical checks, mirroring
  `--coordination-body`. State the rule once in a shirabe-owned reference the
  mode implements and the skills cite, replacing the dangling cross-plugin
  pointer. Wire a reusable `pr-body` CI workflow plus a self-caller on
  `pull_request` that fetches the PR title/body via `gh` and runs the mode.
rationale: |
  A validate mode is the established single-source shape for a
  path-independent check (`--coordination-body` static, `--merge-gate` live);
  reusing it keeps one authority both CI and skills consume, avoids a new
  renderer subcommand the CLI-surface policy forbids, and confines the gate
  to objectively-decidable rules so a legitimate minimal PR never fails.
upstream: docs/prds/PRD-pr-template-gate.md
user_visible_surface: true
---

# DESIGN: pr-template-gate

## Status

Planned

The design settles the two questions the PRD tagged for it: where the
mechanical/gated vs subjective/advisory boundary sits (exactly the three
checks R2–R4, nothing more), and the interface by which the title and body
reach the mode (`--pr-body <file>` for the body, an optional `--pr-title
<string>` companion for the title). The downstream PLAN owns the atomic
issue decomposition.

## Context and Problem Statement

shirabe ships a Rust validator, `shirabe validate`, whose correctness rules
live as modes: per-file document checks (positional files), the chain-aware
`--lifecycle`, the live coordination `--merge-gate`, and the offline
`--coordination-body` static check. The last is the closest precedent for
this work: it reads an authored coordination-PR body from a file and checks
it with no network access, giving an author feedback before the body is
posted. Its findings flow through a shared `ValidateOutcome` exit-code
contract (0 clean, 1 tool-error, 2 violations) and three `--format` values
(`human`, `json`, `annotation`).

PR-template conformance has no such mode. The tsukumogami org squash-merges
every PR, so a PR body is two documents joined by one `---`: Part 1 above
the separator becomes the permanent squash commit body on `main`, and Part 2
below it is reviewer context deleted at merge. The title must be Conventional
Commits. These mechanical facts are stated inline in `/execute`'s
`pr_finalization` state (`skills/execute/koto-templates/execute.md`) and in
`/work-on`'s PR phase, and the canonical wording lives in a PR-creation skill
shipped by a downstream consumer plugin — not in shirabe. `/execute`'s
template even cites a `skills/pr-creation/SKILL.md` that does not exist in
the shirabe repo: a dangling cross-plugin pointer.

The result is the defect the upstream PRD names: a PR opened by any path
other than an authoring skill — a manual `gh pr create`, a dispatched worker
— has nothing that states or checks the template, and the rule is
single-sourced by neither of the two places that state it. It already broke
on #220. The property the repo wants is a well-formed squash body regardless
of which path opened the PR (PRD goals; R7, R8).

## Decision Drivers

- **D1 — Path-independence.** The check must fire on any PR, not only
  skill-authored ones (PRD R7/R8). Only a CI gate on `pull_request` achieves
  this; a skill-side check cannot.
- **D2 — Single source of the mechanical rule, inside shirabe.** The rule CI
  enforces and the rule the skills author from must be one shirabe-owned
  authority (PRD R5/R6). The downstream consumer's PR-creation skill must not
  be modified — the logic is migrated into shirabe, not added downstream.
- **D3 — Gate only the objectively-decidable.** A gated check must be a
  machine-decidable fact with no judgment. Subjective Part 2 section
  selection stays advisory (PRD R5; Out of Scope). This is what guarantees
  "no false positives on a docs-only minimal Part 2" (PRD R10).
- **D4 — Reuse the established CLI shape.** shirabe's CLI-surface policy
  forbids a subcommand that renders or creates an artifact body; correctness
  belongs in `shirabe validate` as a mode. The mode must mirror
  `--coordination-body`'s offline, mutually-exclusive, shared-exit-code shape
  (PRD R1).
- **D5 — Offline and deterministic validator.** The validator process makes
  no network or `gh` call; its findings depend only on its inputs (PRD R9).
  Fetching the PR body is the CI workflow's job, not the validator's.
- **D6 — Untrusted input.** A PR title and body are attacker-controlled. The
  title must never be interpolated into a CI shell script (GitHub Actions
  script injection), and body content shown in code fences must not trip the
  structural checks (false-positive avoidance).
- **D7 — Supply-chain parity.** The CI workflow must match the existing
  `lifecycle.yml` / `validate-docs.yml` pattern: build the binary from source
  at the called workflow's ref, SHA-pin every action, request least
  privilege.

## Considered Options

### The check's home: validate mode vs a bespoke CI script vs a new subcommand

A **standalone CI shell/Python script** embedded in the workflow could grep
the PR body directly. Rejected against D2 and D4: the rule would live in YAML,
unreachable by the skills, so the single-source property fails and the skills
would still restate the checks. It also duplicates the offline-check shape
`--coordination-body` already established.

A **new `shirabe pr-body` subcommand** (or a body renderer) was rejected
against D4: the CLI-surface policy is explicit that authoring belongs in
skills and correctness/feedback belongs in `shirabe validate`; a prior
`shirabe coordination create/status` subcommand was removed for exactly this
reason. A validate **mode** is the sanctioned shape.

The **chosen option** is a `shirabe validate --pr-body` mode, the offline
static analog for a PR body, structurally identical to `--coordination-body`.

### The mechanical/advisory boundary: tight three vs broader gate

A **broader gate** could also fail, e.g., a `Fixes #N` in Part 1, or a
missing Part 2, or filler sections. Rejected against D3 and PRD R10: each
extra gated check adds false-positive surface. `Fixes #N` can appear
legitimately in Part 1 prose ("this fixes the #220 regression"); a minimal
docs PR legitimately has a sparse Part 2. Gating these would fail correct
PRs, defeating the acceptance property.

The **chosen boundary** gates exactly three checks — title is Conventional
Commits (R2), one `---` separator with a non-empty Part 1 (R3), no
AI-attribution footer (R4) — and leaves everything else, including Part 2
section selection and Part 1 issue-reference placement, advisory. Advisory
guidance stays in the downstream PR-creation skill's reasoning framework;
shirabe owns only the three mechanical gates.

### Title/body interface: two args vs first-line vs split-to-workflow

**Title as the first line of the `--pr-body` file** was rejected against D5's
cleanliness and the `gh pr view` data shape: `gh` returns title and body as
distinct JSON fields, so conflating them forces the workflow to synthesize a
combined file and forces every caller to know the convention.

**Splitting the title check into the workflow's own step** (validator checks
only the body) was rejected against D2: it splits the single authority across
the validator and the YAML, the exact drift the design removes.

The **chosen interface** is `--pr-body <file>` for the body plus an optional
`--pr-title <string>` companion. When `--pr-title` is present the title check
(R2) runs; when absent the mode checks only body-level rules (R3–R4), so a
local caller can check a body-in-progress. CI always passes both, so the gate
always covers all three checks. The title arrives as a value argument (argv,
never shell-evaluated), and the workflow passes it through an environment
variable rather than direct expression interpolation (D6).

## Decision Outcome

Add `shirabe validate --pr-body <file> [--pr-title <string>]`: an offline
mode, mutually exclusive with `--lifecycle`, `--lifecycle-chain`,
`--merge-gate`, `--coordination-body`, and positional files, reporting
through the shared `ValidateOutcome` contract in all three `--format` values.
It runs exactly three code-fence-aware mechanical checks and emits actionable
findings in the `--coordination-body` finding shape (`line` + plain-language
`message`).

- **PB1 — Conventional Commits title (R2), when `--pr-title` is given.** The
  title matches `<type>[optional scope][!]: <description>` where `<type>` is
  one of `feat, fix, docs, style, refactor, perf, test, chore, ci, build`,
  the description after `: ` is non-empty, and the scope, when present, is
  not an issue-number scope. The issue-number match is pinned to a numeric
  pattern — case-insensitive `^(issue[-_]?)?#?\d+$` (rejects `issue-8`, `#8`,
  `8`) — so a legitimate word scope like `issue-tracker` or `issues` is not
  over-matched. A non-conforming title is one finding naming the specific
  failure.
- **PB2 — Separator and non-empty Part 1 (R3).** Scanning the body with
  fenced code blocks excluded, there is exactly one top-level line that is a
  bare `---` separator, and the Part 1 above it (the prospective squash
  commit body) contains non-whitespace text. Zero separators, more than one,
  or an empty Part 1 each produce a finding. "Fenced code block" is
  CommonMark-shaped: a fence opener is a line whose first non-indent run is
  three or more backticks or tildes, optionally followed by an info string
  (```` ```rust ````, `` ```yaml ``); it closes only on a bare same-marker
  line of at least the opener's length, so a ` ``` ` shown as content inside
  a `~~~` block does not toggle state. This is what stops a `---` shown
  inside a YAML/text example from being counted (D6, PRD R10).
- **PB3 — No AI-attribution footer (R4).** The body (code fences excluded)
  carries no AI co-author trailer (a `Co-Authored-By:` line attributing to
  Claude/Anthropic/an AI assistant) and no "Generated with Claude Code" /
  robot-emoji generation line.

The single authority is a new `references/pr-body-conformance.md` stating
PB1–PB3 as the mechanical rule and naming the validator as its enforcement.
`/execute`'s `pr_finalization` and `/work-on`'s PR phase cite that reference
for the mechanical rule (keeping their own Part 1/Part 2 assembly prose), and
the dangling `skills/pr-creation/SKILL.md` pointer in `execute.md` is replaced
with it. The downstream PR-creation skill is untouched; its reasoning
framework remains the authority for advisory Part 2 selection.

A reusable `.github/workflows/pr-body.yml` (`workflow_call`) builds `shirabe`
from source at the called workflow's ref, fetches the PR title and body via
`gh pr view --json title,body`, writes the body to a temp file, passes the
title via an env var, and runs the mode with `--format annotation`. A
self-caller `.github/workflows/validate-pr-body.yml` invokes it on this
repo's PRs on `pull_request` with `types: [opened, edited, reopened,
synchronize, ready_for_review]` and no `paths:` filter. Permissions are
`contents: read` + `pull-requests: read`.

## Solution Architecture

### CLI surface and dispatch

`crates/shirabe/src/main.rs` gains two `ValidateArgs` fields mirroring
`coordination_body`:

```
--pr-body  <FILE>    Option<String>   // mode trigger; conflicts_with the other modes
--pr-title <STRING>  Option<String>   // optional title companion
```

`--pr-body` declares its `conflicts_with` set **explicitly on its own field**
— `lifecycle`, `lifecycle_chain`, `merge_gate`, **and `coordination_body`** —
not by assuming symmetry from `coordination_body`'s existing declaration
(clap needs the new edge declared on the new field, or `--pr-body
--coordination-body` slips through and the dispatch runs coordination mode
first, silently ignoring `--pr-body`). A run-time guard rejects positional
files (the same shape as the `coordination_body` guard). `--pr-title` without
`--pr-body` is a tool-error ("`--pr-title` requires `--pr-body`"). A new
`run_pr_body_mode(file, title, format)` reads the file (I/O error →
tool-error), calls the library check, and renders findings through the
`human`/`json` arms `run_coordination_body_mode` uses (the JSON schema string
is `shirabe-pr-body/v1`). The `annotation` arm emits the **fileless**
`::error::<message>` form rather than `::error file=…,line=…::`, because the
body lives in a temp file with no path in the checked-out tree — a
file-anchored annotation would point at a nonexistent source line, so a
fileless workflow error is the honest surface.

### Library check

A new `crates/shirabe-validate/src/pr_body.rs` exposes:

```
pub struct PrBodyFinding { pub line: usize, pub message: String }
pub fn check_pr_body(body: &str, title: Option<&str>) -> Vec<PrBodyFinding>
```

`check_pr_body` runs PB1 (only when `title` is `Some`), PB2, and PB3, in
source order, returning an empty vec for a clean PR. A shared helper yields
the body's top-level lines with fenced code blocks removed, so PB2's
separator count and PB3's footer scan see only top-level content — the
false-positive mitigation for D6. The helper's fence rule is the CommonMark
shape stated in PB2: an opener is `^\s*(`{3,}|~{3,})` with an optional info
string; the block closes only on a bare same-marker line of at least the
opener length, and the two marker families do not cross-toggle. `lib.rs`
re-exports `check_pr_body` and `PrBodyFinding` alongside
`check_coordination_body`.

The helper strips **fenced** blocks only, not 4-space-indented code blocks.
A `---` or attribution footer placed inside indented code would still be
seen at top level; this is an accepted residual (see Security
Considerations), because PR bodies overwhelmingly use fenced blocks and the
convention's own examples are fenced. `references/pr-body-conformance.md`
records the same carve-out.

Title parsing for PB1 is a small hand-written scan (find the first `:`,
split the `type[scope][!]` head from the description, validate each part)
rather than a dependency, matching the crate's no-new-runtime-dependency
posture.

### Single-source reference and skill citations

`references/pr-body-conformance.md` is the authored authority: it states
PB1–PB3 in prose, names `shirabe validate --pr-body` as the enforcement, and
scopes itself to the mechanical rule (pointing at the downstream skill's
reasoning framework for advisory Part 2). `execute.md` and
`phase-6-pr.md` cite it by path for the mechanical checks; the inline
title/body assembly guidance stays, now framed as "author to satisfy
`references/pr-body-conformance.md`, enforced by the validator."

### CI data flow

```
pull_request (self-caller)
  -> pr-body.yml (workflow_call)
       checkout caller repo  ->  checkout shirabe @ workflow_sha (.shirabe-src)
       cargo build --release --bin shirabe
       gh pr view <number> --json title,body   (GH_TOKEN, read-only)
         -> body to $RUNNER_TEMP/pr-body.txt ; title to $PR_TITLE env
       shirabe validate --pr-body "$BODY_FILE" --pr-title "$PR_TITLE" --format annotation
         -> exit 2 fails the check; annotations surface each finding on the PR
```

The PR number is a safe integer from the event payload; the title never
enters the run script as an expression — it is read from the environment,
closing the script-injection vector (D6).

## Implementation Approach

Three batches, sequenced so each is independently reviewable and the gate is
never half-wired:

- **Batch 1 — validator mode.** `pr_body.rs` (`check_pr_body` + fence-strip
  helper + PB1/PB2/PB3), the `lib.rs` re-export, the `main.rs` args, guards,
  and `run_pr_body_mode`, plus unit tests for every PRD R12 case (well-formed
  pass; non-conventional title; issue-number scope; missing separator; double
  separator; empty Part 1; attribution footer; docs-only minimal Part 2 pass;
  a `---`-in-code-fence body that still passes). This batch is the single
  source; it lands first because everything else consumes it.
- **Batch 2 — reference + skill single-sourcing.** Author
  `references/pr-body-conformance.md`; update `execute.md` (replace the
  dangling pointer, cite the reference) and `phase-6-pr.md` (cite the
  reference for the mechanical rule); update the affected `/execute` evals
  that assert the old `skills/pr-creation/SKILL.md` citation. Depends on
  Batch 1 only for the mode name it cites.
- **Batch 3 — CI workflows.** The reusable `pr-body.yml` and the self-caller
  `validate-pr-body.yml`, SHA-pinned and least-privilege, mirroring
  `lifecycle.yml`/`validate-lifecycle.yml`. Lands last so the gate goes live
  once the mode and reference exist; the PR shipping this design self-tests
  the gate on its own body.

## Security Considerations

- **GitHub Actions script injection (D6).** A PR title/body is
  attacker-controlled. The title is never interpolated into a `run:` script
  as a `${{ }}` expression; it is fetched via `gh pr view` and passed through
  an environment variable referenced as `"$PR_TITLE"`, and to the validator
  as an argv value (never `eval`-ed). The body reaches the validator only as
  a file path. This is the standard injection mitigation and matches how
  `lifecycle.yml` handles PR-derived data.
- **Least privilege.** The workflow grants `contents: read` (checkout) and
  `pull-requests: read` (`gh pr view`) only — no write token, no PR-edit, no
  branch push. The gate is read-only; a red check blocks nothing but the
  merge signal.
- **Supply chain (D7).** Every action is SHA-pinned; the binary is built from
  source at the called workflow's `job.workflow_sha`, so the checked binary
  matches the workflow contract rather than a downloaded artifact.
- **Offline validator (D5).** `check_pr_body` and `run_pr_body_mode` perform
  no network or `gh` call; the validator's output is a pure function of its
  file and title inputs, so it cannot be steered by anything but the PR
  content it is handed.
- **Denial-of-input false positives.** The code-fence-exclusion in PB2/PB3 is
  a correctness-and-safety measure: without it, a PR whose Part 2 shows a
  YAML `---` or discusses a `Co-Authored-By:` line (as this very design does)
  would fail spuriously. Two residuals are accepted and documented in
  `references/pr-body-conformance.md`: (a) a body that places the literal
  footer text or a bare `---` at top level outside any fence while not
  intending it structurally; and (b) the same content inside a
  4-space-**indented** code block, which the fenced-only helper does not
  strip. Both are low-likelihood — the convention's bodies use fenced blocks
  — and the author rewords one line or fences the example to resolve either.

## Consequences

**Positive.**

- The #220 regression is caught at PR-open time on every path — manual,
  dispatched, or skill — not after a human runs a repair skill.
- The mechanical rule has one home inside shirabe; the skills cite it and the
  dangling cross-plugin pointer is gone, so the authored body and the gated
  body cannot drift.
- The mode reuses the `--coordination-body` shape, so it inherits the shared
  exit-code contract, the three formats, and the finding style with no new
  CLI concepts for a maintainer to learn.
- A downstream repo can adopt the gate by calling the reusable workflow, the
  same way `lifecycle.yml` is consumed.

**Negative, with mitigations.**

- *The title check needs the title threaded through CI.* Mitigated by
  fetching it via `gh pr view` and the env-var hand-off, which is also the
  injection mitigation — one mechanism serves both.
- *The "exactly one separator" rule could false-positive on a legitimate
  second `---`.* Mitigated by excluding fenced code blocks (the common case)
  and by keeping the rule mechanical and documented in
  `references/pr-body-conformance.md`; a top-level horizontal rule in Part 2
  is asked to use `***`/`___` instead.
- *The attribution check is a heuristic.* Mitigated by matching the specific
  trailer/footer shapes rather than any mention of the words, and by
  documenting the accepted residual false-positive in this section.
- *A second CI workflow adds build time.* Mitigated by the same Cargo cache
  the sibling workflows use; the check itself is trivial (one binary run on
  two short strings).

## References

- `docs/prds/PRD-pr-template-gate.md` — the upstream PRD this design
  operationalizes (R1–R12).
- `docs/briefs/BRIEF-pr-template-gate.md` — the framing.
- `references/coordination-strategy.md` and
  `crates/shirabe-validate/src/coordination.rs` — the `--coordination-body`
  static-check precedent whose shape (`check_coordination_body`,
  `CoordinationBodyFinding`, `run_coordination_body_mode`) this mode mirrors.
- `.github/workflows/lifecycle.yml` and
  `.github/workflows/validate-lifecycle.yml` — the reusable + self-caller
  workflow pattern, SHA-pinning, source-build, and PR-data handling this work
  mirrors.
- `skills/execute/koto-templates/execute.md` — the `pr_finalization` state
  carrying the inline mechanical rule and the dangling
  `skills/pr-creation/SKILL.md` pointer this design single-sources.
