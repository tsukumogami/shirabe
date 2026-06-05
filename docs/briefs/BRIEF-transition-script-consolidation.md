---
schema: brief/v1
status: Done
problem: |
  The seven artifact-lifecycle skills (vision, strategy, roadmap, brief, prd,
  design, comp) each ship a `transition-status.sh` script that advances a
  document from one lifecycle status to the next. Together they are roughly
  2,250 lines of bash that reimplement one workflow by copy-paste, and they have
  drifted: the shared logic is maintained seven times, the per-skill behaviors
  that legitimately differ are tangled together with the shared spine, and a fix
  in one script does not reach the other six.
outcome: |
  A caller — a skill author at a terminal, or a skill invoking it
  programmatically — advances any document by running
  `shirabe transition <status> <file>` against the shirabe binary the workflow
  already depends on. shirabe recognizes the document's type itself, applies
  that type's existing transition behavior, and returns the same
  machine-readable result the skill consumes. The behavior each artifact type
  has today is preserved, but defined in one place instead of six drifting
  scripts.
---

# BRIEF: transition-script consolidation

## Status

Done

This brief frames a developer-tooling consolidation on the shirabe CLI. It
follows the byte-faithful Go-to-Rust rewrite of the `validate` subcommand:
the CLI now exists as a Rust binary that skills can call, which makes folding
the per-skill transition scripts into a subcommand worthwhile.

## Problem Statement

Each of the seven artifact-lifecycle skills ships its own
`skills/<skill>/scripts/transition-status.sh`. The scripts advance a document
through that skill's lifecycle: they read the current status from frontmatter
and the body `## Status` line, decide whether the requested transition is
allowed, rewrite the frontmatter status, move the file into a status
subdirectory for the skills that require it, and print a machine-readable JSON
result the calling skill consumes.

The seven scripts total roughly 2,250 lines of bash (vision 431, strategy 445,
design 389, roadmap 285, comp 249, brief 245, prd 199). They share a spine —
argument handling, the frontmatter-and-body status detection, the frontmatter
rewrite, and the JSON result assembly — but only by copy-paste, so the spine is
maintained in seven places and has drifted. They also legitimately differ in
ways that are tangled into each copy rather than expressed against a common
core: each skill has its own status set; some enforce an ordered transition
graph (vision, strategy, roadmap, brief, comp) while others only check that the
target is a known status (design, prd); three move the file into a status
directory (design, vision, strategy) and four do not; and a few carry
content preconditions and per-type output fields described in Scope below.

Two costs follow. Maintenance: a change to the shared behavior has to be made
six times and in practice gets made in one and forgotten in the others.
Correctness: nothing enforces that the shared spine stays identical across the
copies, so it diverges silently. The per-skill differences are real and should
be preserved; the machinery that reads, validates, rewrites, and reports
status should not be six hand-maintained copies.

## User Outcome

A caller advances a document with one command —
`shirabe transition <status> <file>` — using the shirabe binary the workflow
already depends on. The caller does not tell the command what kind of document
it is: shirabe recognizes the artifact type itself, the way `validate` already
recognizes a document it is asked to check.

Whatever the type, the command applies that type's existing transition
behavior — its status set and any ordered-transition rules, its content
preconditions, its frontmatter and body edits, its directory move if it has
one, and the machine-readable result the calling skill parses — and that
behavior now lives in one implementation instead of six scripts. The common
caller is often a skill invoking the command and reading its result, not a
human typing it. When a transition rule needs to change, it changes once and
every skill picks it up, and the six scripts go away.

## User Journeys

### Accept a brief

An author accepts a draft brief with
`shirabe transition accepted docs/briefs/BRIEF-foo.md`. shirabe recognizes the
document as a brief, confirms a brief is allowed to go from Draft to Accepted,
rewrites the frontmatter and body status, and prints the result the brief
skill consumes — the same result today's script prints.

### Promote with a directory move

An author promotes a design to Current with
`shirabe transition current docs/designs/DESIGN-foo.md`. shirabe recognizes the
design, rewrites the status, and moves the file into `docs/designs/current/`
with `git mv` as part of the same operation — the move the per-skill script
performs today.

### Reject an out-of-order transition

An author runs `shirabe transition done docs/roadmaps/ROADMAP-foo.md` on a
Draft roadmap. shirabe rejects it, because a roadmap advances Draft → Active →
Done and cannot jump straight to Done — the same ordered-transition rule the
roadmap script enforces today, with the same error and exit code.

### Supersede a design

An author supersedes a design, providing the document that replaces it. shirabe
requires that pointer (a superseded design must name its successor), records it
in the design's frontmatter and in the result, rewrites the status, and moves
the old design into `docs/designs/archive/`. This is the richest path: it takes
an input beyond `<status> <file>`, writes a type-specific extra field, and
moves the file. Strategy's Sunset (which requires a reason) and vision's Sunset
(which optionally takes a superseding document) are variants of the same shape.

## Scope Boundary

**In scope** — the consolidated `shirabe transition` subcommand reproduces the
full behavior the seven scripts have today:

- All seven artifact-lifecycle skills: vision, strategy, roadmap, brief, prd,
  design, comp.
- Each skill's status handling exactly as it is today: the skills that enforce
  an ordered transition graph (vision, strategy, roadmap, brief, comp) keep it,
  and the skills that only check status membership (design, prd) keep that. This
  is a faithful port; it does not add or remove transition legality. comp shares
  brief's Draft/Accepted/Done lifecycle but additionally permits the
  Draft → Done shortcut, and emits a bare `moved: false` result field (no
  `new_path`).
- The content preconditions some skills run: vision and strategy block
  Draft → Accepted when the document still has unresolved Open Questions;
  roadmap blocks Draft → Active without at least two features.
- The per-type inputs beyond `<status> <file>`: a superseding-document pointer
  (required for design's Superseded, optional for vision's Sunset) and
  strategy's Sunset reason, including strategy's sanitization of that reason.
- The per-type edits and outputs: the type-specific extra frontmatter fields
  (`superseded_by`, `sunset_reason`) and body lines, the directory move via
  `git mv` for the three skills that move (design, vision, strategy) with their
  target directories, and each skill's JSON result shape.
- Migrating every caller and then deleting the seven scripts: each skill's own
  `SKILL.md` invocation, the `work-on` skill's `run-cascade.sh` (which calls the
  scripts programmatically and parses their JSON) and its test, and the prd
  skill's direct call to the brief script. The scripts are deleted only after
  the subcommand is shown to reproduce their behavior and the callers are moved
  over.

**Out of scope:**

- The `validate` subcommand and other shirabe behavior — unchanged.
- Redesigning any lifecycle: no new statuses, no changes to which transitions
  are legal, no unifying of the per-skill status sets or transition graphs.
- Cross-repo reference resolution and library-crate packaging — separate
  efforts that build on the CLI independently.

## Open Questions

Deferred to the PRD and DESIGN:

- **CLI surface.** Argument order (the scripts take `<file> <status>`; the
  command here is written `<status> <file>` — confirm or align), whether the
  command accepts lifecycle verbs (`accept`, `sunset`), capitalized statuses
  (`Accepted`, `Sunset`), or both, and how the per-type extra inputs
  (superseding-document, reason) are passed — positional or flag — given their
  requiredness depends on the (type, target) pair.
- **Type detection.** `validate` recognizes a document's type from its filename
  prefix (`DESIGN-`, `PRD-`, …) via `detect_format`; confirm transition uses the
  same key, and decide what happens when the type cannot be determined (today
  `validate` skips an unrecognized file; transition more likely should error).
  A misnamed file (prefix says one type, `schema:` says another) is already
  caught by validate's schema-consistency check, so a separate `--type` flag is
  probably unnecessary.
- **Result parity.** The seven JSON results are not identical today: brief and
  prd emit four fields; comp emits those four plus a bare `moved: false` (it
  never moves, and unlike roadmap it reports no `new_path`); roadmap, design, and
  vision add `new_path`/`moved` (roadmap emits them even though it never moves);
  design and vision add `superseded_by`; strategy adds `reason`. Decide whether
  to preserve each type's shape (and to
  what fidelity — byte-for-byte vs structural) or converge them, and note what
  breaks: `run-cascade.sh` keys off `new_path`. The exit-code contract (0
  success, non-zero with a reason on stderr) is part of this surface, because
  programmatic callers depend on it.
- **Per-skill rules representation.** Whether each skill's status set,
  transition graph, directory rules, and preconditions are a hardcoded table or
  a declarative configuration. A declarative table is friendlier to a later
  effort that makes the CLI the single authority for deterministic checks.
- **Directory-move semantics.** Folding `git mv` into the binary raises cases
  the scripts already handle: tracked vs untracked file, target already exists,
  the result staged vs committed, behavior outside a git repository, and
  idempotency on re-run.
- **Body `## Status` rewrite.** Whether the subcommand rewrites the body status
  line or leaves it to the skill, including the type-specific formats (design,
  vision, and strategy write a superseded-by / sunset link or reason line, not
  just the bare status word).

## Downstream Artifacts

- A PRD capturing the requirements: the per-skill behaviors to preserve, the
  caller migration, and the parity bar.
- A DESIGN settling the CLI surface, the table-versus-config decision, the
  result-parity mechanism, and the directory-move semantics.

## References

- The seven scripts under `skills/<skill>/scripts/transition-status.sh`.
- The programmatic caller `skills/work-on/scripts/run-cascade.sh` and its test.
