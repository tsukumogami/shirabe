# Parent-Skill State-File Schema

The state-file vocabulary every parent skill SHALL use. This document names
the 5-field minimum required of every conforming parent, the four
pattern-level invariants the schema enforces, the extension discipline for
parent-specific additions, and the R9 hard-finalization check spec that
catches state drift at termination time.

The schema sits at Layer 2 of the two-layer contract (see
[`parent-skill-pattern.md`](parent-skill-pattern.md)). Field names and
serialization details are substrate-bound — the v1 core layer materializes
them as a YAML document with the `.md` extension at
`wip/<parent>_<topic>_state.md`. Amplifier-layer substrates supply their
own serialization that satisfies the same field semantics and invariants.

## Minimum Required Fields

Every parent's state file SHALL carry the following five fields. Names are
fixed; semantics are pattern-level; serialization is substrate-bound.

- **`topic`** — string matching the regex `^[a-z0-9-]+$`. The topic slug
  is the state's key; concurrent invocations against different topics
  never interfere (invariant I-4).
- **`last_updated`** — ISO-8601 timestamp. Written on every state-file
  modification. Used by the resume ladder's stale-session check.
- **`phase_pointer`** — parent-phase enum string. Names which phase the
  parent is in when interrupted; consumed by the resume ladder to decide
  where to re-enter.
- **`exit`** — parent-exit enum string from
  `{full-run, re-evaluation, abandonment-forced}` (the three pattern-level
  exit paths). UNSET while the chain is in progress; SET at finalization.
  The R9 hard-finalization check fires when this field is unset or
  invalid at termination.
- **`exit_artifacts`** — list of `{path, status}` entries. The durable
  files this chain produced (full-run produces the terminal artifact;
  re-evaluation produces a Decision Record; abandonment-forced produces a
  schema-compliant partial artifact).

## Field Semantics

The five fields above are the floor. Every parent's state file extends the
floor with parent-specific fields keyed by the parent's chain shape and
exit-path bindings — see Extension Discipline below.

The `topic` field is the file's identifying handle. Two parent runs against
different topic slugs MUST never write to the same state file; the topic
slug appears in the substrate's storage key (under `wip-yaml-md`, the file
path is `wip/<parent>_<topic>_state.md`).

The `last_updated` field is a monotonic write-time signal. Resume-ladder
stale-session checks compare the field against a parent-defined threshold;
each parent picks the numeric threshold based on its expected interruption
profile.

The `phase_pointer` field is a parent-phase enum, not a free-text string.
Each parent's SKILL.md names its phases; the field's allowed values are the
parent's named phase identifiers.

The `exit` field is conditional in a strict sense: UNSET while the chain is
in progress, SET to a valid enum value at finalization. The R9
hard-finalization check makes the conditional explicit (see R9 Hard-
Finalization Check Spec below).

The `exit_artifacts` field captures the durable files the chain produced.
Each entry records `path` and `status` (the durable artifact's frontmatter
status value). For full-run exits, the list contains the terminal
artifact's path; for re-evaluation, the Decision Record path; for
abandonment-forced, the schema-compliant partial artifact's path.

### Parent-specific conditional fields

Beyond the 5-field minimum, parents extend the schema with conditional
fields keyed by their own chain-shape and exit-path bindings (see
Extension Discipline below). Two such fields recur often enough to
document at the pattern-doc layer so multiple parents adopt them
identically rather than reinventing the vocabulary.

- **`boundary:`** — gated by `exit: re-evaluation`. Valid values:
  `prd | design`. The field discriminates which upstream boundary the
  re-evaluation Decision Record attaches to when a parent's chain has
  more than one settled-upstream boundary. Parents with multiple
  settled-upstream boundaries (e.g., `/scope`, whose chain settles at
  PRD-Accepted and again at DESIGN-Accepted) SHALL set `boundary:`
  when `exit: re-evaluation` fires; parents with one boundary (e.g.,
  `/charter`, which settles at a single STRATEGY-Accepted boundary)
  MAY omit it. The field is a discriminator within the re-evaluation
  exit path, not a fourth exit path.

- **`plan_execution_mode:`** — gated by `/plan` appearing in
  `chain_ran`. Valid values: `single-pr | multi-pr`. The field
  records the output-mode selection of a terminal child that exposes
  two distinct output modes (in v1 only `/plan` does; the field is
  therefore parent-specific to chains that include `/plan` as a
  terminal child). Recording the selection in the state file is what
  lets downstream consumers — Decision Records, finalization
  artifacts, future-resume detection — observe which output shape
  the chain produced without re-reading the terminal artifact.

Both fields satisfy invariant I-5: each is ABSENT from the state
file when its triggering condition does not hold, never set to null,
empty string, or placeholder. R9 Parts 2 and 3 (see R9 Hard-
Finalization Check Spec below) enforce this.

## Pattern-Level Invariants

The schema enforces four pattern-level invariants that every conforming
parent SHALL satisfy. The four are: per-child snapshot dual-check,
conditional-field gating, chain-tracking, and status-aware re-entry
control.

### Per-child snapshot dual-check

For each child the parent invokes, the state captures both the child's
durable status AND a content-fingerprint of the child's durable artifact.
Drift fires when EITHER changes between parent resumes. For doc-emitting
children the fingerprint is the git blob hash; for non-doc children the
fingerprint binding is parent-specific (see
[`parent-skill-child-inspection.md`](parent-skill-child-inspection.md) for
the per-parent surface table).

The dual-check catches both kinds of drift: a status flip (e.g., Draft →
Accepted) that a single-field check would catch, and a body edit (the
child doc's status stays Draft but its prose was rewritten) that only a
fingerprint comparison catches.

### Conditional-field gating

Fields whose presence is gated by a specific `exit:` value (or other
triggering condition) MUST be absent when the triggering condition does
not hold; they MUST NOT be set to null, empty string, or placeholder
value. This is invariant I-5 of the pattern.

Example: a state file with `exit: full-run` MUST NOT carry a
`triggering_child:` field (that field is gated on `exit:
abandonment-forced`). Setting it to `null` or `""` is a violation; the
field SHALL be absent.

### Chain-tracking

Parents whose run invokes a sequence of children record the chain
explicitly using three fields:

- **`planned_chain`** — the children the parent intended to invoke at the
  start of the chain.
- **`chain_ran`** — the children whose invocations completed.
- **`chain_skipped`** — children the chain decided to skip, with free-text
  reasons.

The three chain-tracking fields are conditional on chain-shaped parents.
Non-chain-shaped parents (e.g., an implementation-loop parent that runs a
single recurring inner phase rather than a sequence of distinct children)
MAY omit them. When omitted, invariant I-5 (conditional fields absent when
ungated) is satisfied; when present, the dual-check and resume-ladder
machinery consumes them.

Output-mode selection — when a chain's terminal child exposes more
than one output mode — is recorded SEPARATELY from `chain_ran` and
`chain_skipped` because the chain-tracking triad captures chain
MEMBERSHIP, not output mode. A child that completed both single-mode
and multi-mode runs would appear identically in `chain_ran` either
way; only a separate field carries the selection. `plan_execution_mode:`
(see Parent-specific conditional fields above) is the canonical
example: gated by `/plan` appearing in `chain_ran`, with valid values
`single-pr | multi-pr`, the field records the output-mode selection
without collapsing the chain-tracking triad's membership semantics.

### Status-aware re-entry control

When a parent invokes a child whose durable doc would trigger that child's
own resume prompt, the parent MUST decide upfront whether the re-entry is
a parent-resume (continue the parent's chain) or a fresh chain (signal
the child to suppress its status-aware re-entry). The parent's flow MUST
NOT be hijacked by a child's status-aware re-entry prompt.

The signaling mechanism between parent and child is parent-specific; the
invariant is that the parent decides, not the child.

#### `parent_orchestration:` block

The `parent_orchestration:` block is the pattern-level convention every
parent writes and every child reads identically; the block is the
**pre-dispatch state element of the dispatch contract** named in
[`parent-skill-pattern.md`](parent-skill-pattern.md) under
`## Dispatch Contract`'s Pre-Dispatch State sub-section. The parent
writes the block to its state file immediately before invoking the
child via the Skill tool; the child reads it at its own Phase 0 to
route Slot 2 behavior (suppress its status-aware re-entry prompt) and
the parent clears it on hand-back per the Dispatch Contract's
`parent_orchestration:` cleanup step. The block's fields are fixed at
the pattern layer (no parent extends or omits any field):
`invoking_child:` names the child the parent is about to invoke;
`suppress_status_aware_prompt:` carries the upfront decision to
silence the child's status-aware re-entry; `rationale:` carries the
`fresh-chain | revise` framing the child reads to route its own Slot 2
behavior.

## Extension Discipline

Every parent extends the 5-field minimum with parent-specific fields keyed
by its chain shape, exit-path bindings, and child set. Three rules
constrain extensions.

1. **No re-use of pattern-level names with different semantics.** A
   parent-specific field MUST NOT shadow a pattern-level field. A field
   named `exit` is the pattern-level exit; a parent that wants a
   parent-specific exit-related field SHALL choose a distinct name.
2. **Conditional fields satisfy I-5.** Parent-specific conditional fields
   (fields whose presence is gated by a specific `exit:`,
   chain-position, or other triggering value) MUST be absent when their
   triggering condition does not hold (per invariant I-5; see
   Conditional-field gating above).
3. **Chain-tracking fields stay together.** A parent that uses
   `planned_chain` SHALL also use `chain_ran` and `chain_skipped`
   (they form a unit). A parent that omits chain-tracking omits all three;
   no half-set.

Parent-specific fields land in the same state file as the pattern-level
fields; the substrate's serialization mechanically accommodates them. Under
`wip-yaml-md`, parent-specific fields are additional top-level YAML keys.

## R9 Hard-Finalization Check Spec

R9 is the source requirement for the hard-finalization check (see
`PRD-shirabe-charter-skill.md` for the original R9 prose). The check fires
at parent finalization and verifies the state file is consistent before
the parent terminates. A run that completes without recording a valid
exit is a violation surface, not silently absorbed.

The check has three parts. All three SHALL pass for finalization to
succeed.

1. **`exit:` valid.** The `exit:` field is set to one of the three
   pattern-level exit-path values (`full-run`, `re-evaluation`,
   `abandonment-forced`). UNSET or out-of-enum values fail the check.
2. **Sub-shape valid when applicable.** If the parent defines a sub-shape
   field (e.g., a Decision Record's `re-evaluation` vs `rejection`
   sub-shape) gated on a specific `exit:` value, the sub-shape field is
   set to one of its valid values when the gating `exit:` fires. UNSET or
   out-of-enum sub-shape values fail the check.

   When a parent has more than one sub-shape discriminator gating the
   same `exit:` value, ALL discriminators MUST be set when the gating
   `exit:` fires. `/scope`'s `boundary:` plus `decision_record_sub_shape:`
   is the canonical example: the two discriminators together gate the
   four re-evaluation Decision Record combinations (prd-re-evaluation,
   prd-rejection, design-re-evaluation, design-rejection); both must
   be set when `exit: re-evaluation` fires. UNSET or out-of-enum
   discriminator values fail R9 Part 2 the same way single-discriminator
   parents do — the multi-discriminator framing extends the rule, not
   replaces it.
3. **Conditional fields absent when ungated.** Fields whose presence is
   gated by a specific `exit:` or sub-shape value are ABSENT from the
   state file when their triggering condition does not hold (invariant
   I-5). Null, empty-string, or placeholder values fail the check.

   Conditional fields whose triggering condition is chain-position
   rather than `exit:` follow the same I-5 absent-when-ungated rule.
   `plan_execution_mode:` (gated by `/plan` appearing in `chain_ran`)
   is the canonical example: when `/plan` is not in `chain_ran`, the
   field MUST be absent from the state file; null, empty-string, or
   placeholder values fail R9 Part 3 identically to the `exit:`-gated
   case. The chain-membership-gated framing extends the rule's reach
   without changing its mechanics.

When the check fails, the parent SHALL surface the specific violation
(naming the offending field and the failing rule) and refuse to record
finalization. The check is the contract enforcement mechanism: silent
absorption is a contract violation in its own right.

## Topic-Slug Regex

The topic-slug regex `^[a-z0-9-]+$` is the pattern-level constraint cited
by every parent's SKILL.md. Slugs that fail the regex are hard-rejected at
Phase 0 (no normalization, no automatic suggestion). The regex is referenced
from each parent's SKILL.md topic-slug constraint statement (R1 structural
element 3 in `parent-skill-pattern.md`).
