---
schema: brief/v1
status: Accepted
problem: |
  The completion cascade re-implements in bash three things the Rust
  transition engine already owns: frontmatter parsing, per-artifact-type
  dispatch, and the per-type terminal-transition decision. Two copies of the
  same lifecycle knowledge in two languages drift, and the bash copy cannot
  explain the engine's decisions.
outcome: |
  A skill maintainer changes lifecycle behavior once, in the engine, and the
  cascade inherits it with no parallel bash edit. A cascade that hits an
  illegal transition surfaces a typed, type-aware reason instead of a bare
  brace of JSON noise.
---

# BRIEF: finalize-chain

## Status

Accepted

The downstream PRD owns the requirements: the subcommand's exact input and
output contract, the typed-error shape, and which behaviors must be preserved
byte-for-byte against the bash cascade it replaces.

## Problem Statement

The post-implementation completion cascade (`skills/work-on/scripts/run-cascade.sh`)
walks a finished PLAN's `upstream` frontmatter chain and brings each node to its
terminal lifecycle state: the PLAN is deleted, a DESIGN moves to Current, a PRD
and a BRIEF move to Done. To do that, the bash script re-implements logic the
Rust transition engine already owns:

- **Frontmatter parsing.** An inline awk routine (`get_frontmatter_field`) reads
  the `upstream` field at each node -- a second, hand-rolled frontmatter reader
  living beside the engine's.
- **Per-artifact-type dispatch.** Two `case` statements branch on the filename
  prefix (`DESIGN-*`, `PRD-*`, `BRIEF-*`, `ROADMAP-*`, `VISION-*`) -- a bash
  mirror of the engine's own format detection.
- **The per-type terminal-transition decision.** Each branch hardcodes the legal
  target status for that type (DESIGN to Current, PRD to Done, BRIEF to Done).
  That decision is exactly what the engine's transition spec table encodes.

Two copies of the same lifecycle knowledge, in two languages, are free to drift
apart -- the precise failure this change exists to remove. The drift is not
hypothetical. When the engine rejects a transition, every
handler captures only the first line of the engine's output (`head -1`) and
surfaces it as the failure detail. The engine reports rejections as JSON, so the
first line is a bare `{` -- the cascade emits a brace as its error message, with
no awareness that, for example, the rejected artifact is a graph-type whose
states are ordered (so skipping a state is illegal) rather than a membership-type
where any state is reachable. The engine holds that distinction; the bash glue
structurally cannot, because it does not share the engine's model of types and
transitions. A maintainer who later adds an artifact type, or changes a type's
terminal state, must remember to edit both the engine and the bash, or the
cascade silently diverges from the authority.

## User Outcome

A skill maintainer who changes lifecycle behavior -- adds an artifact type,
retargets a type's terminal state, tightens a transition rule -- makes that
change once, in the engine, and the cascade inherits it. There is no second
bash copy to keep in sync, so the two cannot drift.

An engineer whose cascade hits an illegal or unexpected transition reads a typed,
type-aware explanation -- which node, which type, which transition, and why it
was refused -- instead of a bare brace of JSON. The person debugging a stuck
cascade learns what went wrong from the error itself rather than from re-reading
the engine's source to decode a one-character message.

## User Journeys

### Maintainer changing a type's terminal lifecycle behavior

A skill maintainer decides a given artifact type should finalize to a different
terminal state. They edit the engine's transition spec once. The next cascade
run resolves that type and applies the new terminal transition without any change
to the cascade script, because the cascade asks the engine for the decision
rather than carrying its own copy. The maintainer never touches bash, and no
drift between the two is possible.

### Engineer debugging a refused transition

An engineer runs a cascade against a chain that contains a node whose current
status cannot legally reach its terminal state (an ordered, graph-type artifact
asked to skip an intermediate state). Instead of a bare `{`, the cascade reports
a typed error naming the node, its artifact type, the attempted transition, and
the reason the engine refused it. The engineer fixes the offending document's
status and re-runs, guided by the message rather than blocked by it.

### Contributor finalizing a completed PLAN's chain

A contributor finishes implementing a PLAN and triggers the cascade. The chain
walk and the per-node type resolution happen inside the binary, which returns a
typed record of every node and the terminal transition decided for it (including
that the PLAN is to be deleted, not transitioned, because the engine carries no
PLAN type). The cascade script reads that record and performs only the git steps
-- remove, move, stage, commit, push -- so the lifecycle decisions and the
version-control actions are cleanly separated.

## Scope Boundary

**IN:**

- Moving the `upstream`-chain walk from bash into the engine: reading each node's
  `upstream` field and following it to the next node, using the engine's own
  frontmatter parser.
- Moving per-node artifact-type resolution into the engine, reusing its existing
  format detection rather than a parallel filename-prefix `case`.
- Moving the per-type legal terminal-transition decision into the engine: the
  target status for each chain artifact type, and the rule that a PLAN is deleted
  (the engine carries no PLAN type) rather than transitioned.
- A typed result describing the planned or applied per-node transitions, and
  typed, type-aware errors that replace the first-line-of-JSON failure detail.

**OUT:**

- Git operations -- remove, move, stage, commit, push. These stay in the
  skill/bash layer; the CLI deliberately does not own version control.
- Workflow orchestration -- when the cascade runs, the dry-run-versus-push
  behavior, and how it is wired into the surrounding skill. The skill keeps that.
- ROADMAP feature-status surgery and the "all features done plus all referenced
  issues closed" completion guard. That work edits roadmap body content and
  consults external issue-tracker state, which is not a deterministic single-doc
  transition; whether any of it moves into the engine is left to the downstream
  PRD and design, not assumed here.
- The transition engine's existing per-document mutation behavior (frontmatter
  and body edits, and the Current directory move for designs). The engine already
  owns that; this feature reuses it and does not re-litigate it.
