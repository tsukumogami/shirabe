# Decision 3: Lifecycle file management for STRATEGY documents

## Question

How does STRATEGY's `skills/strategy/scripts/transition-status.sh`
behave, and where do Sunsetted STRATEGY documents live? Specifically:

1. **Sunset directory mapping.** Move to `docs/strategies/sunset/`
   (VISION-style), stay in `docs/strategies/` (ROADMAP-style), or
   something else?
2. **Script behavior contract.** What arguments does the script accept,
   what transitions are valid, what file movement does it perform, and
   how is the Sunset reason captured?

Two sub-questions, each evaluated independently below, then composed
into a single contract.

---

## Sub-Question A: Sunset directory mapping

### Considered Options

**A1. Move to `docs/strategies/sunset/` (VISION-style).** Sunset
documents leave the main directory. Working set for active strategies
is the bare `docs/strategies/` listing. Implements directory-as-state
for the terminal status.

**A2. Stay in `docs/strategies/` (ROADMAP/PRD-style).** No directory
movement. Status is read from frontmatter only. Sunsetted documents
share the directory with Draft / Accepted / Active siblings.

**A3. Hybrid — move only when superseded by a successor.** Stay-put
for plain Sunset; move to `docs/strategies/sunset/` only when a
superseding STRATEGY is recorded.

### Decision Outcome

**Adopt A1: Sunset moves to `docs/strategies/sunset/`.**

This is the position the PRD's Decision 2 implies and the design
frontmatter already commits to ("Sunset moves files to
`docs/strategies/sunset/` matching VISION's directory-as-state
convention"). The rationale chain is:

- **Falsifiability semantics drive directory semantics.** PRD
  Decision 2 chose Sunset (VISION-style) over Done (ROADMAP-style)
  because STRATEGY makes a falsifiable bet. The bet's terminal state
  is "the bet failed / was abandoned / was invalidated" — categorically
  different from ROADMAP's "all the features shipped." Mirroring
  VISION's directory contract preserves that distinction at the
  filesystem level: a reader scanning `docs/strategies/` sees the
  currently-believed bets; `docs/strategies/sunset/` is the graveyard
  of invalidated bets.

- **Read-time discoverability.** Future authors learning the
  convention diff `skills/strategy/` against `skills/vision/`. Matching
  the directory-as-state pattern reduces cognitive surface area.
  Diverging would force a justification for every reader who notices.

- **ROADMAP's stay-put precedent is grounded in different semantics.**
  ROADMAP's Done is an achievement record; the artifact's value
  increases at Done because it documents what shipped. STRATEGY's
  Sunset is the opposite: the document's value decreases (the bet was
  wrong / no longer applies); moving it out of the active surface
  matches its diminished standing.

### Rejected Alternatives

- **A2 (stay-put)** — Wrong semantic match. ROADMAP's stay-put rule
  exists because Done is celebratory and the doc remains a reference
  for what was built. STRATEGY's Sunset is closer to VISION's Sunset
  (bet invalidated) than to ROADMAP's Done.
- **A3 (hybrid)** — Introduces a third pattern not present in any
  existing skill. Violates the design's pattern-fidelity principle.
  Adds branching in the script with no offsetting benefit.

---

## Sub-Question B: Script behavior contract

### Considered Options

**B1. Copy VISION's script verbatim, retargeted to `docs/strategies/`.**
Same argument shape (`<doc-path> <target-status> [superseding-doc]`),
same valid-transitions set (forward-only, Sunset terminal), same
movement-on-Sunset behavior. The "reason" surface is the existing
body `## Status` text + the optional superseding-doc argument.

**B2. Add explicit `--reason` flag to the CLI.** Make the Sunset
reason a required CLI argument (e.g., `--reason=abandoned|pivoted|
invalidated|superseded`). Persist it into a new frontmatter field
`sunset_reason:` or into the body Status section.

**B3. Permit downgrade transitions (e.g., Accepted → Draft).** Allow
authors to walk a STRATEGY backwards if it was prematurely accepted.

### Decision Outcome

**Adopt B1, with one explicit addition: Sunset records the reason via
the `## Status` body section text (authored before invoking the
script).** The CLI surface stays at three positional arguments,
matching VISION verbatim. No `--reason` flag.

#### Function signature

```bash
# transition-status.sh <strategy-doc-path> <target-status> [superseding-doc]
#
# Arguments:
#   strategy-doc-path  Path to strategy document
#                      (e.g., docs/strategies/STRATEGY-foo.md)
#   target-status      One of: Draft | Accepted | Active | Sunset
#   superseding-doc    Optional, only meaningful when target is Sunset:
#                      path to the successor STRATEGY (records
#                      superseded_by in frontmatter and a link in body
#                      Status)
#
# Exit codes:
#   0 - Success (writes JSON result to stdout)
#   1 - Invalid arguments or file not found
#   2 - Invalid status transition
#   3 - File operation failed (sed / git mv / mkdir)
#
# Behavior:
#   - Updates `status:` in YAML frontmatter
#   - Updates the body `## Status` section keyword to match
#   - If target == Sunset: moves the file from docs/strategies/ to
#     docs/strategies/sunset/ using `git mv` (falls back to `mv` if
#     not in a git repo)
#   - If target == Sunset and superseding-doc is given: writes
#     `superseded_by: <path>` into frontmatter and rewrites the body
#     Status line to `Sunset: superseded by [<basename>](<path>)`
#   - Emits a JSON object: { success, doc_path, old_status, new_status,
#     new_path, moved, superseded_by? }
```

#### Valid transitions

| From → To | Allowed | Precondition |
|-----------|---------|--------------|
| Draft → Accepted | yes | Open Questions section empty or removed; jury PASS recorded (enforced by skill, not script) |
| Draft → Active | no | Must transit through Accepted |
| Draft → Sunset | no | Delete the draft instead — unendorsed drafts don't need a paper trail |
| Accepted → Active | yes | At least one Downstream Artifact entry present |
| Accepted → Draft | no | No regression |
| Accepted → Sunset | yes | Body Status section records reason; optional superseding-doc |
| Active → Sunset | yes | Body Status section records reason; optional superseding-doc |
| Active → Accepted | no | No regression |
| Active → Draft | no | No regression |
| Sunset → any | no | Terminal, irreversible |

This matches VISION's table exactly, with one explicit addition:
Accepted → Sunset is allowed (not just Active → Sunset). VISION's
script today rejects Accepted → Sunset by omission; STRATEGY adds it
because a strategic bet can be invalidated by external events before
any downstream artifact ever consumes it (e.g., a competitor ships
the same wedge while the strategy is still Accepted-but-not-Active).
The PRD's Decision 2 framing — "bet invalidated, pivoted, or
abandoned" — does not require Active status to apply.

#### Downgrade transitions

**Not permitted.** Forward-only, matching every other shirabe artifact
type. Rationale: authorship discipline. If a STRATEGY was prematurely
Accepted, the corrective action is to Sunset it (with reason
`pivoted` and a superseding STRATEGY) rather than rewind history.
This keeps the Status section trustworthy as an audit signal.

#### Sunset reason capture

**Captured in the body `## Status` section text, authored by the user
before script invocation.** The script does not take a `--reason`
flag. Three reasons inherited from VISION + PRD Decision 2:
`abandoned`, `pivoted`, `invalidated`. Format reference will require
the Sunset Status section to contain one of those keywords; the
custom check `checkStrategySunsetReason` (introduced as a sibling of
the Decision 4 R7 check) enforces it during `shirabe validate`.

When `superseding-doc` is passed, the script additionally rewrites
the Status body line to include the link — matching VISION's
behavior exactly.

This avoids two failure modes a `--reason` flag would introduce:
the reason being recorded only in script invocation history (lost),
and the script's CLI surface diverging from VISION's three-arg shape
without offsetting benefit.

### Rejected Alternatives

- **B2 (`--reason` flag).** Introduces CLI surface divergence from
  VISION with no information-density gain — the body Status section
  already carries the reason and is the user-facing record. A flag
  would either duplicate that record (drift risk) or replace it
  (loses prose context). The format-reference + validation-check
  approach is the precedent set across the existing skills.
- **B3 (downgrade transitions).** Conflicts with the forward-only
  discipline every other shirabe artifact type enforces. The use
  case (prematurely-accepted STRATEGY) is better served by the
  Sunset-with-superseding-doc path, which preserves history.

---

## Composed Decision

1. Sunset moves files to `docs/strategies/sunset/`. Draft / Accepted
   / Active live in `docs/strategies/`.
2. Script CLI is `transition-status.sh <doc-path> <target-status>
   [superseding-doc]`. Three positional arguments. No flags.
3. Valid transitions are forward-only: Draft → Accepted,
   Accepted → Active, Accepted → Sunset, Active → Sunset.
4. Sunset is terminal. No reverse transitions from any state.
5. Sunset reason is captured in the body `## Status` section (one of
   `abandoned`, `pivoted`, `invalidated`), authored before invocation
   and enforced by a `checkStrategySunsetReason` custom check.
6. Optional `superseding-doc` argument writes `superseded_by:` to
   frontmatter and an inline link to the body Status section.

## Assumptions

- **A custom validation check enforces Sunset reason wording.** The
  Decision 4 R7 dispatch surface in `internal/validate/checks.go`
  hosts a sibling check (`checkStrategySunsetReason`) that the
  Sunset-state validation rule activates. Without this, the
  reason-in-body convention is unenforced.
- **`docs/strategies/sunset/` is a permitted location in shirabe
  validate's path scanning.** The Formats-map entry uses the
  longest-prefix `STRATEGY-` filename match, so the directory itself
  doesn't need special routing logic.
- **Accepted → Sunset (without ever reaching Active) is a real
  scenario worth supporting.** Strategies can be invalidated by
  external events before any downstream artifact references them;
  the lifecycle table accommodates this explicitly.

## Rejected Alternatives Summary

| Alternative | Why rejected |
|-------------|--------------|
| Stay-put on Sunset (ROADMAP-style) | Wrong semantic match — STRATEGY's Sunset is bet-invalidation, not feature-completion. |
| Hybrid (move only when superseded) | Third pattern not present in any existing skill; no offsetting benefit. |
| `--reason` CLI flag | Diverges from VISION's three-arg shape; duplicates the body Status record. |
| Permit downgrade transitions | Conflicts with forward-only discipline; better served by Sunset-with-superseding-doc. |
| Reject Accepted → Sunset | Excludes a real failure mode (strategic bet invalidated before downstream work begins). |
