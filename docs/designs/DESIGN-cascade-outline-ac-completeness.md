---
schema: design/v1
status: Accepted
upstream: docs/prds/PRD-cascade-outline-ac-completeness.md
problem: |
  The work-on cascade satisfies every chain-posture rule (L01-L05) and
  still ships work whose promised outline acceptance criteria were
  never ticked. The PRD pins the requirement; this design settles the
  implementation shape — the candidate-shape decision the PRD's R7
  left open, the Lnn code number, the parser location and tolerance,
  and the cascade script integration points.
decision: |
  Adopt the pure-doc shape (PRD R7a) under check code L06. Land a
  pure parser `parse_outline_acs` in shirabe-validate that walks the
  PLAN's `## Issue Outlines` section, finds every `- [ ]`
  checkbox line under each `### Issue N` outline, and returns the
  unticked set. Wire L06 into the existing `validate --lifecycle-chain`
  mode behind a flag `--allow-untracked-acs` (default off). The
  cascade script's pre-probe and post-verify both call
  `shirabe validate --lifecycle-chain <PLAN> --strict` and let the
  binary refuse on L06. The escape hatch is the same flag exposed to
  cascade-script callers via an environment variable
  `WORK_ON_ALLOW_UNTRACKED_ACS=1` the script forwards.
rationale: |
  The pure-doc shape is sufficient for the gap the PRD names: the
  cascade is the discipline-bearing surface and the checkbox is the
  author's claim. Diff-aware verification (R7b) introduces symbol-
  naming conventions not yet established in the corpus and a parser
  resolving "function X in file Y" to a diff hunk — heavy
  implementation cost for marginal value over reviewer discipline +
  the escape-hatch's visible signal. Pure-doc + strict parser + the
  escape-hatch flag closes the gap at the cost the gap warrants.
  Coupling to --lifecycle-chain reuses the cascade's existing single
  validator invocation; a parallel CLI mode would double the
  cascade's validator surface for no separation-of-concerns benefit
  (AC-completeness is conceptually a lifecycle property in the
  work-completeness sense the PRD pins).
---

# DESIGN: cascade-outline-ac-completeness

## Status

Accepted

This design settles the four implementation questions the PRD left
open: which candidate shape (R7), the Lnn code number (R5), parser
tolerance (R8), and the escape-hatch flag name (R4). The downstream
PLAN decomposes this design into atomic implementation issues.

**In-place correction (Accepted)**: this DESIGN originally referenced
the outline-bearing PLAN section as `## Implementation Issues`. The
correct section name for single-pr PLANs (per FC14's per-mode
required-sections shape) is `## Issue Outlines`; multi-pr PLANs use
`## Implementation Issues` and carry an issues table without per-AC
checkboxes. The rename was applied in-place. The AC-completeness
check therefore applies to single-pr PLANs only; multi-pr PLANs
return an empty unticked-set from the parser.

## Context and Problem Statement

The cascade script `skills/work-on/scripts/run-cascade.sh` invokes
`shirabe validate --lifecycle-chain <PLAN-DOC> --strict` at two
points: the pre-probe (before the cascade body executes) and the
post-verify (after the body executes). The lifecycle-chain mode
currently runs checks L01-L05 (chain-posture mismatch, orphan docs,
upstream cycles, missing chain members, defensive parsing fallbacks).
The exit code gates whether the cascade proceeds.

A PLAN's `## Issue Outlines` section enumerates per-outline
acceptance criteria as `- [ ]` Markdown checkboxes. The
lifecycle-chain mode does not parse these. An author can satisfy
every chain-posture rule (BRIEF at Accepted, PRD at Accepted, DESIGN
at Planned-or-Current, PLAN at Active for multi-pr) while every AC
checkbox is unticked. The cascade proceeds to delete the PLAN, the
squash-merge erases the staleness from history, and the discipline
the checkbox encodes fails silently at the moment it should be
enforced.

The PRD pins the requirement; this design settles the implementation
shape against the two candidate shapes named in PRD R7.

## Decision Drivers

Four drivers shape the decision space.

1. **Implementation cost matches gap severity.** The gap closes a
   posture-not-completeness failure mode. A discipline-forcing
   function suffices; real-correctness verification adds parser
   surface and corpus conventions that aren't established.

2. **The cascade is the single source of truth for pre/post
   verification.** Per `DECISION-cascade-trigger-mechanism-2026-06-06.md`.
   AC-completeness lands at the cascade, not a parallel CI step.

3. **No new external dependencies.** The check reuses the existing
   shirabe-validate crate, the existing bash cascade script, and
   the existing `--lifecycle-chain` CLI mode the cascade already
   invokes.

4. **Strictness tracks blast radius.** AC-completeness fires on the
   working tree at finalization time; mistakes are catchable by the
   author. Error-level firing is appropriate (a notice would
   degrade the discipline-forcing function the PRD's Goal 1
   requires).

## Considered Options

### Decision 1: Candidate shape — pure-doc vs diff-aware

**Chosen: Pure-doc AC-completeness check (PRD R7a).**

Parser walks the PLAN's `## Issue Outlines` section, finds
every `- [ ]` checkbox under each `### Issue N` outline, and returns
the unticked set. A non-empty unticked set fires L06. The check is
strictly textual; no diff inspection, no symbol parsing, no
external-tool subprocess.

**Why.** The PRD's Goal 1 names the cascade as the discipline-
bearing surface. A checkbox is the author's claim; the cascade's
job is to refuse PLAN deletion until the author has filed every
claim. Diff-aware verification (option B below) introduces symbol-
naming conventions in AC text and a parser resolving entity
references to diff hunks — implementation cost the PRD's
trade-off section flags as disproportionate to the marginal value
over reviewer discipline + the visible escape-hatch signal.

**Alternative considered: Diff-aware AC verification (PRD R7b).**
Parses ACs that name files or symbols, reads
`git diff <base>..HEAD`, and verifies the named entities are
touched. Rejected: (a) symbol-naming conventions in AC text are not
established in the current corpus and forcing them retroactively
breaks already-committed PLANs; (b) behavioral ACs ("the cascade
refuses to delete when ACs are unticked") name no file or symbol —
the parser would either silently pass them or false-positive on
them; (c) the gap is solvable by reviewer discipline plus a visible
escape signal. YAGNI: if author-lying becomes a real failure mode,
diff-aware is an additive change on top of pure-doc.

### Decision 2: Lnn check code number

**Chosen: L06.**

L01 (chain-posture mismatch), L02 (orphan docs), L03 (upstream
cycles), L04 (missing chain members), L05 (defensive parsing
fallbacks) are claimed by the parent DESIGN-roadmap-plan-
standardization's Decision 5. L06 is the next free integer.

**Why.** AC-completeness is conceptually a lifecycle property in
the work-completeness sense PRD R5 names. The Lnn family is the
right home; one prefix for downstream consumers to grep.

**Implementation note.** The code-name assignment is checked
against the live validator surface at implementation time. If L06
turns out to be claimed by a check that landed between this
design's drafting and the implementation PR, the PLAN's first
issue widens its acceptance criterion to "pick the next free code
in the Lnn family and document the renumbering."

### Decision 3: Parser location and tolerance

**Chosen: Parser lives in shirabe-validate; strict tolerance (`- [ ]`
only).**

The parser function `parse_outline_acs` lives in
`crates/shirabe-validate/src/table.rs` adjacent to the existing
`parse_issue_outlines` helper FC14 added. The strict tolerance:
the parser recognizes `- [ ]` (unticked) and `- [x]` / `- [X]`
(ticked) lines as AC checkboxes. ACs written as bare sentences,
nested checkboxes, indented continuation lines beyond the
checkbox line itself, or non-canonical bracket spacing
(`- [  ]`, `-[]`) are not recognized as AC lines and do not
contribute to the unticked count.

**Why.** PLAN-doc-structure.md and the FC14 work both
canonicalized `- [ ]` as the AC syntax. The corpus already uses
this shape exclusively (verified by grep against
`docs/plans/PLAN-*.md` at design time). A permissive parser would
absorb format drift and silently pass on it; the strict shape
surfaces drift as an FC04 / FC14 violation rather than a quiet
L06 pass.

**Implementation note.** The first PLAN issue's tests pin the
strict tolerance: tests for the recognized shapes, plus tests
asserting that non-canonical shapes are not counted (so a future
loosening surfaces as a test diff).

### Decision 4: Escape-hatch flag name and scoping

**Chosen: CLI flag `--allow-untracked-acs` on
`shirabe validate --lifecycle-chain`; environment variable
`WORK_ON_ALLOW_UNTRACKED_ACS=1` forwarded by the cascade script.**

The flag's default is OFF. When ON, L06 is suppressed (not fired)
while every other Lnn check remains active. The scope is per-
invocation (whole-cascade-call), not per-AC — granular
suppression adds parser surface for an edge case the corpus
hasn't shown.

**Why.** The CLI flag is the surface a human invokes when running
the validator directly. The environment variable is the surface
the cascade script forwards to the validator. A flag-only CLI
without an env-var pass-through would require the cascade script
to read the env var, conditionally append a flag, and re-quote —
the env var pass-through removes that friction.

**Reviewer visibility.** The cascade script logs the escape
hatch's invocation in its pre-probe output with a literal string
like `[L06-suppressed via WORK_ON_ALLOW_UNTRACKED_ACS=1]`. A
reviewer grep against that string surfaces every use across the
PR's CI logs.

### Decision 5: CLI integration shape — extend --lifecycle-chain vs add new mode

**Chosen: Extend `--lifecycle-chain` to include L06.**

The cascade script currently invokes
`shirabe validate --lifecycle-chain <PLAN> --strict` once at each
hook. L06 is added to the check set the lifecycle-chain mode
runs.

**Why.** A parallel CLI mode (`shirabe validate --check-outline-
acs <PLAN>`) would double the cascade's validator surface (two
invocations per hook) and split the shared chain-loading work
the lifecycle-chain mode already performs. AC-completeness is
conceptually a lifecycle property in the work-completeness sense
PRD R5 names; bundling under one CLI mode keeps the cascade's
surface area small.

**Trade-off.** Authors running `shirabe validate --lifecycle`
(the whole-tree variant) get AC-completeness checked across the
whole tree. This is the right outcome — whole-tree scans want to
surface every Lnn failure — but it means a CI lifecycle job will
fail on any in-progress PLAN with unticked ACs, not just at
cascade time. Mitigated by the same escape-hatch flag.

## Decision Outcome

### Summary

| Question | Outcome |
|----------|---------|
| Candidate shape (PRD R7) | Pure-doc check |
| Lnn code number (PRD R5) | L06 |
| Parser location (PRD R8) | `crates/shirabe-validate/src/table.rs` |
| Parser tolerance (PRD R8) | Strict (`- [ ]` and `- [x]/[X]` only) |
| Escape-hatch flag (PRD R4) | `--allow-untracked-acs` CLI; `WORK_ON_ALLOW_UNTRACKED_ACS=1` env |
| CLI mode (implicit) | Extend `--lifecycle-chain`, not a new mode |

### Rationale

The five decisions form a coherent shape: a pure-doc check (Decision
1) lives in the validator crate (Decision 3), fires under L06
(Decision 2), bundles with the existing lifecycle-chain mode
(Decision 5), and exposes one opt-out surface across CLI and env
(Decision 4). Implementation cost matches the gap's severity. No
new external dependencies. The cascade contract is preserved.

## Solution Architecture

### Overview

Three surfaces change.

1. **`shirabe-validate` crate.** Add `parse_outline_acs` in
   `table.rs` and `check_l06` in `checks.rs`. Wire L06 into the
   `validate.rs` dispatch for the `Plan` arm under the
   `--lifecycle-chain` mode.
2. **`shirabe` CLI.** Add the `--allow-untracked-acs` flag to the
   `validate` subcommand. The flag's value is plumbed through the
   `cfg` config struct to `check_l06`.
3. **`skills/work-on/scripts/run-cascade.sh`.** Detect
   `WORK_ON_ALLOW_UNTRACKED_ACS=1`; conditionally append
   `--allow-untracked-acs` to both the pre-probe and post-verify
   validator invocations; emit the literal log line
   `[L06-suppressed via WORK_ON_ALLOW_UNTRACKED_ACS=1]` when the
   env var is set.

### Components

- **`parse_outline_acs(doc: &Doc) -> Vec<OutlineAc>`** (new).
  Returns the AC entries grouped by outline. Each `OutlineAc`
  carries `outline_key: String` (the `Issue N` token from the
  outline heading), `ac_text: String` (the verbatim checkbox-line
  text minus the `- [ ]` / `- [x]` prefix), `ticked: bool`,
  `line: usize`. Operates on the body slice between the
  `## Issue Outlines` heading and the next `##` heading,
  walking each `### Issue N` block.

- **`check_l06(doc: &Doc, cfg: &Config) -> Vec<ValidationError>`**
  (new). Calls `parse_outline_acs`; collects entries with
  `ticked == false`; returns one `ValidationError` per unticked
  AC with code `L06` and message
  `[L06] outline '<outline_key>' has unticked acceptance criterion: '<ac_text>' (line <line>)`.
  When `cfg.allow_untracked_acs == true`, returns an empty
  vector (L06 suppressed at the check level).

- **`validate.rs::validate_file`** dispatch update. The `Plan`
  arm's chain-targeted check set gains L06 alongside the existing
  L01-L05 lifecycle checks. The `is_notice` registration for L06
  is `false` — L06 is error-level (the discipline-forcing
  function requires it).

- **`Config::allow_untracked_acs: bool`** (new). Parsed from the
  `--allow-untracked-acs` CLI flag. Default `false`.

- **`shirabe::cli::validate_cmd`** flag wiring. Adds the
  `--allow-untracked-acs` flag (boolean, default false) to the
  `validate` subcommand's argument parser. Sets
  `cfg.allow_untracked_acs` from the parsed value.

- **`skills/work-on/scripts/run-cascade.sh`** integration. Two
  call sites — the pre-probe (around line 185 / 553 in the
  current source) and the post-verify (around line 759). Each
  call site reads `WORK_ON_ALLOW_UNTRACKED_ACS`; when the value
  is `1` the script appends `--allow-untracked-acs` to the
  validator argv and emits the documented log line. The
  `add_step` calls for the lifecycle hooks log the suppression
  state for traceability.

### Key Interfaces

- **`parse_outline_acs(doc: &Doc) -> Vec<OutlineAc>`** — pure
  function over the parsed `Doc` IR. No I/O. Returns empty
  vector when the doc has no `## Issue Outlines`
  section or no `### Issue N` blocks.

- **`check_l06(doc: &Doc, cfg: &Config) -> Vec<ValidationError>`**
  — pure function, same signature shape as the existing L01-L05
  check functions. Empty return on no failures.

- **CLI:**
  `shirabe validate --lifecycle-chain <PLAN-PATH> --strict [--allow-untracked-acs]`
  — exit non-zero on any of L01-L06 failing. The
  `--allow-untracked-acs` flag suppresses L06 only.

- **Cascade script env:** `WORK_ON_ALLOW_UNTRACKED_ACS=1`
  causes the cascade to invoke the validator with
  `--allow-untracked-acs` at both hooks and to log the
  suppression.

### Data Flow

Cascade pre-probe runs:

1. Read `WORK_ON_ALLOW_UNTRACKED_ACS`. If set to `1`, set
   `extra_args=(--allow-untracked-acs)`; else
   `extra_args=()`.
2. Invoke
   `shirabe validate --lifecycle-chain "$PLAN_DOC" --strict "${extra_args[@]}"`.
3. On non-zero exit, record `add_step "lifecycle_pre_probe"
   "$PLAN_DOC" "null" "failed" "$validator_output"` and halt
   the cascade.
4. On zero exit, record `add_step "lifecycle_pre_probe"
   "$PLAN_DOC" "null" "ok" ""` (with the suppression marker
   appended to the third positional argument when the env var
   was set).

The post-verify call mirrors the pre-probe with the symmetric
`lifecycle_post_verify` step name.

Inside the validator:

1. `validate_file` enters the `Plan` arm for the chain-targeted
   mode.
2. The existing L01-L05 checks run.
3. `check_l06(doc, cfg)` runs; appends any errors to the
   collected list.
4. Errors are emitted in the configured format (`--format json`
   or default human-readable). Exit code = number of error-
   level diagnostics emitted.

## Implementation Approach

### Phase 1: Parser + check function

Add `OutlineAc` struct and `parse_outline_acs` to `table.rs`.
Walk the body between `## Issue Outlines` and the next
`##` heading; for each `### Issue N` block, scan its lines for
`- [ ]` / `- [x]` / `- [X]` prefixes; emit one `OutlineAc` per
match. Unit tests cover: zero outlines (empty section); one
outline with all-ticked ACs; one outline with mixed; many
outlines with mixed; outlines with no ACs (header-only); ACs
that span multiple lines (only the checkbox line counts).

Add `check_l06` to `checks.rs`. Honor `cfg.allow_untracked_acs`.

### Phase 2: CLI flag + validate dispatch

Add `allow_untracked_acs: bool` to `Config` (or the existing
config struct shape). Wire `--allow-untracked-acs` in the
`validate` subcommand's argument parser. Add `check_l06` to the
`Plan` arm's check set under the `--lifecycle-chain` mode.
Register `L06` in `is_notice` as `false` (error-level).

Update CLI tests: `--lifecycle-chain` exits 0 on all-ticked
plans; non-zero on any-unticked; `--allow-untracked-acs`
overrides; the L06 message format matches the documented shape.

### Phase 3: Cascade script integration

Update `skills/work-on/scripts/run-cascade.sh`. Read
`WORK_ON_ALLOW_UNTRACKED_ACS` once at script start; build the
shared `extra_args` array used by both call sites. Both the
pre-probe and post-verify invocations get the same flag
treatment. Emit the suppression log line when the env var is
set. Add the `add_step` instrumentation to record the
suppression state.

Update `run-cascade_test.sh` to exercise: a clean PLAN passes
both hooks; an unticked-AC PLAN fails pre-probe with L06;
setting `WORK_ON_ALLOW_UNTRACKED_ACS=1` overrides; the post-
verify mirrors the pre-probe outcome.

### Phase 4: Self-check on the parent corpus

Run `shirabe validate --lifecycle . --strict` on the live
shirabe repo after Phase 2 lands. Any pre-existing PLAN with
unticked ACs surfaces. If the live corpus has PLANs with stale
unticked ACs (likely — the gap this work closes is the reason
those exist), the implementing PR either ticks them or
descopes them as part of the same PR. This is the corpus-
migration phase analogous to Slice A of the parent PLAN.

## Security Considerations

The new code paths process trusted in-repo content (the PLAN
markdown). No new external input is read; no new subprocess is
spawned; no network call is added. The `WORK_ON_ALLOW_UNTRACKED_ACS`
env var is consumed at the cascade-script layer; the env's
expected values are `1` (escape on) or unset/anything-else (escape
off). The cascade script does not interpolate the env-var value
into any shell command beyond appending the literal
`--allow-untracked-acs` flag when the value is exactly `1`.

The parser is total over arbitrary doc bodies — no panics, no
infinite loops, no path traversal (the function takes a parsed
`Doc` IR, not a filesystem path).

The L06 error message includes the verbatim AC text from the doc.
The error message is emitted to stdout / stderr in shell or JSON
shape; downstream consumers (CI log viewers, agent prose) should
treat the AC text as untrusted content if rendered in HTML
contexts. The current callers (cascade-script bash, CI log
viewers) render plain text, so the surface is not an immediate
concern.

## Consequences

### Positive

- The cascade refuses PLAN deletion when outline ACs are unticked.
  The checkbox discipline gets a load-bearing forcing function.

- The Lnn check-code family grows by one entry under the existing
  prefix. Downstream consumers grep one prefix to find every
  lifecycle-class failure.

- The escape-hatch flag preserves author agency for legitimate
  out-of-scope ACs without weakening the default.

- No new external dependencies. The cascade's existing single
  validator-invocation surface stays intact.

### Negative

- Whole-tree `shirabe validate --lifecycle .` runs surface L06 on
  every in-progress PLAN with unticked ACs. CI jobs running the
  whole-tree mode will fail on every chain in flight until each
  PLAN's ACs are ticked. Mitigated by the escape-hatch flag.

- The strict parser tolerance means non-canonical AC syntax
  silently passes L06 (the parser doesn't recognize the lines, so
  they don't count as unticked). Mitigated by the existing FC04 /
  FC14 checks surfacing non-canonical PLAN structure as a
  separate failure.

- Author-lying (ticking a box without doing the work) is not
  detected. This is the explicit trade-off Decision 1 names.
  Mitigated by the escape hatch's visible signal and reviewer
  discipline; diff-aware verification remains as an additive
  future increment if the failure mode emerges in practice.

### Mitigations

- The corpus-migration phase (Phase 4 of Implementation Approach)
  catches existing PLANs with stale unticked ACs before the
  check goes live on CI. The implementing PR either ticks them
  or descopes them in the same commit.

- The `is_notice` registration is reviewed against the existing
  pattern: notice-level codes (SCHEMA, FC07-FC14, FC-CONVENTIONS)
  do not contribute to exit code. L06 is registered as
  error-level (`false` in `is_notice`) because the PRD Goal 1
  requires the cascade to refuse, not just warn.

- The escape-hatch flag's log-line shape is documented so
  reviewer scripts can grep for it. Misuse (routine
  invocation without justification) is a reviewer-discipline
  concern the PRD's Known Limitations section names.
