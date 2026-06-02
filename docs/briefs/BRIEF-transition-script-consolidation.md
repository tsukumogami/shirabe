---
schema: brief/v1
status: Draft
problem: |
  The six artifact-lifecycle skills (vision, strategy, roadmap, brief, prd,
  design) each ship a `transition-status.sh` script that advances a document
  from one lifecycle status to the next. Together they total roughly 1,994
  lines of bash that reimplement one workflow, and they have already drifted:
  three grew extra mutation logic for directory moves, the per-skill status
  rules are hand-maintained in each copy, and a fix in one script does not
  reach the other five.
outcome: |
  A skill author advances any document by running
  `shirabe transition <status> <file>` against the shirabe binary they
  already have installed. Behavior is identical across all six artifact types
  because there is one implementation, and each skill's status rules live in a
  single place instead of six drifting scripts.
---

# BRIEF: transition-script consolidation

## Status

Draft

This brief frames a developer-tooling consolidation on the shirabe CLI. It
follows the byte-faithful Go-to-Rust rewrite of the `validate` subcommand:
the CLI now exists as a Rust binary that skills can call, which makes folding
the per-skill transition scripts into a subcommand worthwhile.

## Problem Statement

Each of the six artifact-lifecycle skills ships its own
`skills/<skill>/scripts/transition-status.sh`. The scripts advance a document
through that skill's lifecycle: they read the current status from frontmatter
and the body `## Status` line, validate the requested transition against the
skill's status state machine, rewrite the frontmatter status, move the file
into a status subdirectory where the skill requires it, and print a
jq-assembled JSON envelope describing what changed.

The six scripts total about 1,994 lines of bash (vision 431, strategy 445,
design 389, roadmap 285, brief 245, prd 199). They share a spine — argument
parsing, the frontmatter-and-body status sniff, sed-based frontmatter
mutation, and the jq JSON envelope — but only by convention, because the spine
is copy-pasted rather than shared. The copies have measurably drifted: design,
vision, and strategy carry extra awk-based mutation to support directory moves
that the other three do not perform.

Two costs follow. First, maintenance: any change to the shared behavior — a
fix to the status sniff, a tweak to the envelope shape — has to be made six
times, and in practice gets made in one and forgotten in the others. Second,
correctness: the scripts are supposed to behave identically on their shared
surface, but nothing enforces that, so they diverge silently. The per-skill
status enums genuinely differ and should stay distinct; the machinery that
reads, validates, and rewrites status should not.

## User Outcome

A skill author advances a document with one command —
`shirabe transition <status> <file>` — using the shirabe binary the
workflow already depends on. shirabe infers the artifact type from the
document's `schema:` frontmatter, the same way `validate` does, so the type
is never passed as an argument. The result is the same regardless of artifact
type: the same status validation, the same frontmatter rewrite, the same JSON
envelope, and the same directory move for the artifact types that require one,
because all of it runs through a single implementation.

Each skill's lifecycle — its valid statuses, allowed transitions, and whether
a given status implies a directory move — is declared in one place inside the
binary rather than re-encoded in a per-skill script. When a transition rule
changes, it changes once and every skill picks it up. The six scripts go away.

## User Journeys

### Accept a draft

An author finishes a design and runs
`shirabe transition accepted docs/designs/DESIGN-foo.md`. shirabe reads the
file's `schema:` frontmatter to recognize it as a design, confirms the
document's current status permits the move to Accepted, rewrites the
frontmatter, and prints the JSON envelope the skill consumes — the same
envelope today's script prints.

### Promote with a directory move

An author promotes a design to Current with
`shirabe transition current docs/designs/DESIGN-foo.md`. The command
validates the transition, rewrites the status, and moves the file into
`docs/designs/current/` as part of the same operation — the move the per-skill
script used to perform with bespoke awk, now handled uniformly.

### Reject an invalid transition

An author runs `shirabe transition done docs/prds/PRD-foo.md` against a
Draft PRD. shirabe recognizes the PRD from its `schema:` and rejects the
move because the PRD state machine does not allow
Draft → Done, with the same error contract it would give for any skill — one
place to reason about transition errors.

## Scope Boundary

**In scope:**

- All six artifact-lifecycle skills: vision, strategy, roadmap, brief, prd,
  design.
- The full transition behavior the scripts perform today: status validation
  against each skill's state machine, frontmatter status rewrite, body
  `## Status` handling, the JSON envelope output, and the directory move for
  the skills that require one (design, vision, strategy).
- Replacing the six `transition-status.sh` scripts: updating each skill to
  call the subcommand and deleting the scripts, after verifying the subcommand
  reproduces their behavior.

**Out of scope:**

- The `validate` subcommand and any other shirabe behavior — unchanged.
- Redesigning any lifecycle: this consolidates existing status machines and
  directory rules; it does not add states or change which transitions are
  legal.
- The JSON envelope's consumers: callers see the same envelope, so no skill
  logic downstream of the transition changes.
- Cross-repo reference resolution and library-crate packaging — separate
  efforts that build on the CLI independently.

## Open Questions

Deferred to the PRD and DESIGN:

- The exact CLI contract: argument order, which flags exist (`--json`,
  `--dry-run`), and whether to add an optional `--type` override that asserts
  the expected artifact type for safety. The artifact type itself is inferred
  from the document's `schema:` frontmatter (matching `validate`), not passed
  as a required argument; a doc with missing or unrecognized `schema:` fails
  with a clear "cannot determine artifact type" error.
- Whether the per-skill status machines and directory rules are a hardcoded
  table or a declarative configuration.
- The parity bar: the `validate` rewrite held a byte-for-byte output contract;
  transition needs to settle whether the JSON envelope must match
  byte-for-byte or behaviorally, and how the directory-move and git
  interactions are verified.
- Whether the subcommand rewrites the body `## Status` line or leaves that to
  the calling skill.

## Downstream Artifacts

- A PRD capturing the requirements: the CLI contract, the per-skill rules to
  preserve, the parity bar, and the migration/deletion expectation.
- A DESIGN settling the table-versus-config decision and the parity mechanism.

## References

- The six scripts under `skills/<skill>/scripts/transition-status.sh`.
