---
status: Draft
problem: |
  The six artifact-lifecycle skills (vision, strategy, roadmap, brief, prd,
  design) each ship a copy-pasted `transition-status.sh` (~2,000 lines of bash
  total) that advances a document through its lifecycle. The shared spine is
  maintained six times and has drifted, while the genuine per-skill differences
  are tangled into each copy. There is no single place to fix a bug or change a
  rule.
goals: |
  Consolidate the six scripts into one `shirabe transition` subcommand on the
  shirabe CLI that reproduces each artifact type's existing behavior faithfully,
  defines the per-skill rules in one place, migrates every caller, and deletes
  the scripts.
upstream: docs/briefs/BRIEF-transition-script-consolidation.md
---

# PRD: transition-script consolidation

## Status

Draft

## Problem statement

Each artifact-lifecycle skill ships its own
`skills/<skill>/scripts/transition-status.sh`. The six scripts advance a
document through that skill's lifecycle: read the current status from
frontmatter and the body `## Status` line, decide whether the requested
transition is allowed, rewrite the frontmatter (and body) status, move the file
into a status subdirectory for the skills that require it, and print a
machine-readable JSON result the calling skill consumes.

The six total roughly 2,000 lines of bash (vision 431, strategy 445, design
389, roadmap 285, brief 245, prd 199). They share a spine — argument handling,
status detection, frontmatter rewrite, JSON result assembly — only by
copy-paste, so it is maintained in six places and has drifted. The genuine
per-skill differences (distinct status sets; ordered transition graphs in some,
membership-only checks in others; directory moves in three; content
preconditions and per-type output fields in a few) are tangled into each copy
rather than expressed against a shared core. A fix to the shared behavior must
be made six times and in practice is made once and forgotten elsewhere; nothing
keeps the copies in step.

SR1 of the broader CLI effort already rewrote `shirabe validate` from Go to
Rust, so a Rust shirabe binary that skills call now exists. That makes folding
the transition workflow into a `shirabe transition` subcommand the natural next
consolidation.

## Goals

- One `shirabe transition` subcommand handles lifecycle transitions for all six
  artifact types.
- It reproduces each type's current behavior faithfully — same validation,
  edits, moves, results, and exit codes — so callers see no behavior change.
- Each skill's lifecycle rules live in one place in the binary instead of six
  drifting scripts.
- Every caller is migrated to the subcommand and the six scripts are deleted, so
  the duplication is actually removed.

## User stories

- As a skill author, I accept a draft document by running the transition
  command, and the document's status advances with the same validation and
  result the per-skill script gave me.
- As a skill author promoting a design to Current (or sunsetting a vision), the
  command moves the file into the right status directory as part of the
  transition, the way the script did.
- As a skill author who requests an out-of-order transition (e.g. a roadmap
  Draft straight to Done), I get the same rejection and exit code the script
  produced, so my mistake is caught.
- As a skill author superseding a design (or sunsetting a strategy), I provide
  the required extra input — the superseding document, or the sunset reason —
  and the command records it and moves/edits the file accordingly.
- As a skill invoking the command programmatically (for example the work-on
  cascade), I parse the same machine-readable result and rely on the same exit
  codes I relied on from the script.

## Requirements

**R1 — Single subcommand, all six types.** `shirabe transition` handles
lifecycle transitions for vision, strategy, roadmap, brief, prd, and design.

**R2 — Type is inferred, not passed.** The command determines the artifact type
itself, using the same filename-prefix recognition `validate` uses
(`detect_format`). The caller does not pass the type. When the type cannot be
determined from the filename, the command fails with a clear "cannot determine
artifact type" message and a non-zero exit code; it does not silently no-op.

**R3 — Per-type status rules preserved exactly.** Each type keeps its current
status set and transition behavior: the types that enforce an ordered
transition graph (vision, strategy, roadmap, brief) keep it; the types that only
check that the target is a known status (design, prd) keep that. The command
adds no new statuses and changes no transition's legality.

**R4 — Content preconditions preserved.** The command preserves the
content-precondition gates the scripts run: vision and strategy block
Draft → Accepted when the document's Open Questions are unresolved; roadmap
blocks Draft → Active without at least two features.

**R5 — Per-type extra inputs preserved.** The command accepts and validates the
per-type inputs the scripts require: a superseding-document pointer (required
for design's Superseded, optional for vision's Sunset) and strategy's Sunset
reason, including strategy's sanitization of that reason.

**R6 — Per-type edits preserved.** The command makes the same document edits per
type: the frontmatter `status:` rewrite; the body `## Status` rewrite, including
the type-specific forms — design/vision/strategy write a superseded-by or sunset
line rather than the bare status word, and prd rewrites the entire status line
(it does not truncate to the first word, because its status set includes the
multi-word `In Progress`); and the type-specific extra frontmatter fields
(`superseded_by`, `sunset_reason`).

**R7 — Directory moves preserved.** For the three types that move on transition
(design, vision, strategy), the command moves the file into the same target
directory using `git mv`, as the scripts do — design Current →
`docs/designs/current/`, design Superseded → `docs/designs/archive/`, vision
Sunset → `docs/visions/sunset/`, strategy Sunset → `docs/strategies/sunset/`;
the other three types never move.

**R8 — Result and exit-code parity, per type.** The command emits each type's
existing machine-readable result shape (brief and prd emit four fields; roadmap,
design, and vision add `new_path`/`moved`; design and vision add
`superseded_by`; strategy adds `reason`) on success to stdout, and errors to
stderr. Parity is per type and structural: the same JSON keys with the same
values (key order and whitespace need not match), not a unified shape. The
command preserves the specific exit-code contract the scripts advertise — `1`
for bad arguments / file-not-found / unparseable status, `2` for an illegal
transition, invalid status, failed precondition, or rejected sanitization, and
`3` for a file-operation failure — and the matching `code` field in the JSON
error object.

**R9 — Idempotent no-op.** Re-requesting a document's current status succeeds as
a no-op: exit 0, the success result with `moved: false` and the path unchanged,
no edits and no move, and neither the transition graph nor the content
preconditions run — even when the current status is terminal (Sunset / Done).
This preserves the cascade's ability to re-run after a partial failure.

**R10 — Full cutover.** Every caller is migrated to the subcommand: each skill's
own `SKILL.md` invocation, the work-on skill's `run-cascade.sh` (which calls the
scripts programmatically and parses their JSON) and its test, and the prd
skill's direct call to the brief script. The six scripts are deleted once the
subcommand reproduces their behavior and the callers are moved over.

Deferred to the DESIGN (interface and implementation mechanics, not
requirements): the exact CLI surface (argument order, whether the target is a
lifecycle verb or a capitalized status, how the per-type extra input is passed),
whether the per-skill rules are a hardcoded table or a declarative
configuration, and the `git mv` mechanics.

## Acceptance criteria

- [ ] For each of the six types, the subcommand produces the same frontmatter and
  body edits, the same file move (or none), the same per-type JSON result
  (same keys and values), and the same exit code as the script it replaces —
  verified across that type's legal transitions, at least one rejected
  transition where the type has a graph, and its content preconditions where it
  has them.
- [ ] Idempotency: re-running a transition that targets a document's current
  status — including a terminal status (Sunset / Done) — exits 0 with
  `moved: false` and makes no edit or move, for each type.
- [ ] prd's multi-word status: transitioning a PRD into or out of `In Progress`
  rewrites the full body `## Status` line correctly (not truncated to the first
  word).
- [ ] The per-type extra inputs work: superseding a design records
  `superseded_by` and archives the file; a design Superseded without the pointer
  fails; a strategy Sunset requires its reason and rejects an unsafe one.
- [ ] Exit-code classes are preserved: a representative failure of each class
  returns its specific code (`1` bad args / not-found, `2` illegal
  transition / invalid status / precondition / sanitization, `3` file-op
  failure) and the JSON error object's `code` field matches.
- [ ] A document whose type cannot be determined from its filename fails with a
  non-zero exit and a non-empty error message on stderr.
- [ ] Every caller invokes `shirabe transition`; the six `transition-status.sh`
  scripts are deleted and no committed file references them; the work-on
  cascade test passes against the subcommand.
- [ ] `cargo test` and the repo's doc-validation CI pass.

## Out of scope

- The `validate` subcommand and other shirabe behavior — unchanged.
- Any lifecycle redesign: no new statuses, no changed transition legality, no
  unifying of the per-skill status sets, and no unifying of the per-type result
  shapes (that is a separate later effort).
- Cross-repo reference resolution and library-crate packaging — separate efforts
  on the CLI.

## Decisions and trade-offs

- **Faithful per-type parity over unification.** The six result shapes differ
  today; this feature preserves each rather than converging them. Converging
  would change what brief/prd/roadmap consumers see and break the work-on
  cascade's `new_path` parsing unless migrated in lockstep — a larger, separate
  change. Preserving keeps the consolidation behavior-neutral; unification can
  follow.
- **Error, not skip, on unknown type.** `validate` skips a file it does not
  recognize because it is a read-only sweep over many files; `transition`
  mutates one named file, so silently doing nothing is a footgun. The command
  errors.
- **Full cutover in this feature.** Building the subcommand without migrating
  callers and deleting the scripts would leave the duplication — the actual
  problem — in place. The cutover is part of the feature; the PLAN sequences it
  so the scripts are deleted only after parity is shown and callers are moved.

## Open questions

Carried to the DESIGN:

- CLI surface: argument order, lifecycle-verb vs capitalized-status target form,
  and how the per-type extra input (superseding document, reason) is passed
  given its requiredness depends on the (type, target) pair.
- Whether the per-skill rules (status sets, graphs, directory rules,
  preconditions) are a hardcoded table or a declarative configuration — kept
  compatible with a later effort that makes the CLI the single authority for
  deterministic checks.
- `git mv` semantics: tracked vs untracked file, target already exists, staged
  vs committed result, behavior outside a git repository, idempotency on re-run.
- Body `## Status` rewrite ownership and the per-type body templates.

## Related

- Upstream framing: `docs/briefs/BRIEF-transition-script-consolidation.md`.
- The six scripts under `skills/<skill>/scripts/transition-status.sh`.
- The programmatic caller `skills/work-on/scripts/run-cascade.sh` and its test.
