# Parent-Skill Pattern: Security Envelope

The security envelope every shirabe parent skill SHALL satisfy. This
document names the six contract surfaces every conforming parent
binds, regardless of which children it chains, which storage
substrate it runs on, or which team primitive it materializes. The
surfaces below are pattern-level — they are written parent-agnostic
so a new parent can cite this reference verbatim rather than re-
deriving the envelope.

The companion references fill in the details this document points at:

- [`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`](parent-skill-pattern.md) —
  the two-layer contract, semantic invariants, exit paths, and
  substitution surfaces.
- [`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`](parent-skill-state-schema.md) —
  the 5-field minimum, conditional-field gating, R9 hard-finalization
  check, and the topic-slug regex this document cites.

## Slug Re-Validation on Resume

The topic-slug regex `^[a-z0-9-]+$` is the pattern-level constraint
sourced from `parent-skill-state-schema.md` (Topic-Slug Regex
section). Every parent validates `$ARGUMENTS` AS PROVIDED at Phase 0
against this regex.

On resume — when the parent's resume ladder recovers a slug from an
on-disk artifact path (a Slot 5 file-glob match against
`docs/<type>/<TYPE>-<topic>.md` or a Slot 6 match against
`wip/<child>_<topic>_*`) — the recovered slug MUST be re-validated
against `^[a-z0-9-]+$` BEFORE interpolation into any emitted shell
command or state-file write path. The re-validation closes the
path-traversal surface that would otherwise open if an attacker
placed a maliciously-named artifact under `docs/` to be discovered
by the ladder match.

An unparseable slug rejects the resume entry, surfaces a diagnostic
naming the offending path, and routes to the parent's bail-handling
rule. The resume MUST NOT silently proceed with an unvalidated slug.

## Closed Write-Target Set

A parent's filesystem writes are confined to an enumerated set
declared in the parent's SKILL.md. Writes outside this set fail the
R9 hard-finalization check. Future implementors adding a write
target outside the declared set hit a documented enforcement
boundary rather than silently expanding the write surface.

The pattern-level shape of every parent's write-target enumeration:

- Durable artifact paths under `docs/<type>/<TYPE>-<topic>.md` for
  the chain's terminal artifact and any force-materialized partial.
- Decision Record paths under
  `docs/decisions/DECISION-<sub-shape>-<topic>-<YYYY-MM-DD>.md` on
  `re-evaluation` exits.
- State-file path `wip/<parent>_<topic>_state.md` and ancillary
  scratch under the same `wip/<parent>_<topic>_*` prefix.
- Removals of `wip/<child>_<topic>_*` and any matching
  `wip/research/<child>_<topic>_*` during chain cleanup (preserved
  on `abandonment-forced` exits per each parent's cleanup carve-
  out).

The per-parent SKILL.md names the concrete paths against the parent's
chain shape; the pattern-level rule is that the set SHALL be
enumerable and the R9 check SHALL enforce membership.

## State-File Enum Re-Validation

On resume, every state-file field whose declared type is an enum
MUST be re-validated against its enum BEFORE being used to construct
write paths or interpolate into shell commands. State-file tampering
between sessions is closed: an attacker cannot inject a shell
metacharacter via the state file because every value that reaches a
shell command path goes through enum re-validation first.

The pattern-level rule applies to all enum-typed state-file fields:
discriminators that select Decision Record sub-shapes (`boundary:`,
`decision_record_sub_shape:`), exit-conditioned fields naming a
child (`triggering_child:`), execution-mode selectors
(`plan_execution_mode:` or equivalents), and any parent-specific
enum the state schema declares.

Out-of-enum values fail the resume ladder and route to the parent's
bail-handling rule. The re-validation point is the resume entry; a
parent's mid-chain writes from validated inputs do not need a second
check because the write came from validated state.

## Stale `parent_orchestration:` Self-Heal

The `parent_orchestration:` block is ephemeral within a chain
instance: every parent writes it immediately before invoking a child
and clears it immediately after the child returns. The block's
presence at session start (when a fresh parent invocation opens
against a topic with an existing state file) is by definition stale
— the chain that wrote the block is no longer in flight.

Phase 0 SHALL unconditionally clear any `parent_orchestration:`
block found at session start. The self-heal MUST NOT prompt the
author about the stale block, MUST NOT surface a warning, and MUST
NOT treat the block as authoritative on the resume. The clear is
the contract.

The unconditional shape rules out any conditional behavior — no
"if author confirms", no "if last_updated is recent", no
prompt-on-clear. The block is removed from the state file silently,
the rest of the state file is left untouched, and the resume ladder
proceeds against the cleaned state.

## Visibility Boundary

Each parent declares the repo-visibility set it binds to in its
SKILL.md. The pattern-level rule is that cross-visibility extension
of an existing parent (e.g., adding private-repo support to a
parent originally scoped to public-repo chains, or vice versa)
SHALL re-state placement discipline in its own PR with explicit
public-vs-private content-governance review.

The visibility binding is a contract surface because the validator
pass-through (`shirabe validate --visibility=<repo-visibility>`) is
governance-aware: the visibility flag routes the validator's
governance rules, and a parent crossing the visibility boundary
without governance review would slip private content into a public
chain (or vice versa) without surfacing the violation.

## No Untrusted-Input Interpolation Surface

A parent's prose MUST NOT name any pattern that interpolates author-
supplied content directly into `-m "<string>"` shell arguments.
Author-supplied content (rejection rationale, divergence notes,
manual-fallback prose) lives in child skills' Phase-N contracts and
is committed via `git commit -F -` stdin per each child's Security
Considerations.

The parent itself only consumes externally-visible signals from
child invocations — frontmatter `status:` values, git blob hashes,
discard-commit metadata observed via `git log`. These are all
metadata reads, not author-supplied content interpolations. The
parent's `git log` reads commit metadata; commit bodies that name
rejection rationale are pre-committed by the child via the stdin
discipline, so the parent's read surface is metadata-only.

The pattern-level rule binds parents to the metadata-read surface
and assigns interpolation discipline to children. Future parents
adding direct author-input handling SHALL re-state the
interpolation contract explicitly rather than silently broadening
the surface.
