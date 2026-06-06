# Phase: State Management

`/charter`'s durable state lives in a single file per topic at
`wip/charter_<topic>_state.md`. This document specifies the full schema
the file carries, the conditional-field gating discipline that controls
which fields MUST be present versus MUST be absent at each exit, and the
R9 hard finalization check that surfaces a contract violation when the
chain terminates without recording a valid exit.

This file is documentation only — the runtime that READS the state file
lives in the resume ladder (a companion outline owns the implementation)
and the runtime that WRITES the exit fields and runs the R9 finalization
check lives in the exit-path orchestration (another companion outline
owns that implementation). The spec here is the contract surface both
runtimes bind to.

## Table of Contents

- [Pure YAML With `.md` Extension](#pure-yaml-with-md-extension)
- [5-Field Minimum and Pattern-Level Invariants](#5-field-minimum-and-pattern-level-invariants)
- [Topic-Slug Constraint](#topic-slug-constraint)
- [Full Field Schema](#full-field-schema)
  - [Always-Present Fields](#always-present-fields)
  - [Conditional Fields](#conditional-fields)
  - [Schematic YAML Example](#schematic-yaml-example)
- [Conditional-Field Gating Discipline](#conditional-field-gating-discipline)
- [R9 Hard Finalization Check](#r9-hard-finalization-check)
- [Security Considerations](#security-considerations)

## Pure YAML With `.md` Extension

The state file at `wip/charter_<topic>_state.md` is **pure YAML**
despite the `.md` extension. The body contains no markdown — no
headings, no prose, no code fences, no front-matter delimiters. A YAML
parser reads the file end-to-end; any markdown rendering of the file is
incidental.

The `.md` extension matches shirabe's existing `wip/` convention for
committed intermediates (every other `wip/<skill>_<topic>_*.md` shipped
by other shirabe skills uses the same extension). Authors and tooling
SHOULD NOT parse the file as markdown — load it as YAML, not as a doc
with frontmatter. The convention is documented here so downstream
tooling does not confuse the extension with the file format.

The substrate that materializes this serialization is the v1 core-layer
`storage_substrate = wip-yaml-md` named in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`. The
substitution surface lets the amplifier layer ship a different
serialization (e.g., a context-store key-value layout) without changing
this document's field semantics.

## 5-Field Minimum and Pattern-Level Invariants

The schema below extends the pattern-level 5-field minimum. The
minimum is **cited**, not re-derived, from
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`
(Minimum Required Fields section). The five required-of-every-parent
fields are `topic`, `last_updated`, `phase_pointer`, `exit`, and
`exit_artifacts`. Every conforming `/charter` state file satisfies the
minimum; the additional fields below are `/charter`'s parent-specific
extension.

The four pattern-level invariants the schema satisfies are also cited
from `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`:
per-child snapshot dual-check, conditional-field gating, chain-tracking,
and status-aware re-entry control. The `/charter` binding for each is
spelled out in the field-by-field semantics below — the `child_snapshots`
field carries the dual-check; the conditional-field gating rules
(below) carry the gating invariant; the `planned_chain` / `chain_ran` /
`chain_skipped` triple carries the chain-tracking invariant; and the
resume ladder's parent-specific status-aware re-entry slot (owned by a
companion outline) carries the re-entry control invariant against the
fields recorded here.

## Topic-Slug Constraint

The `topic` field's value matches the regex `^[a-z0-9-]+$` cited from
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`
(Topic-Slug Regex section). The regex is the single source of truth;
SKILL.md, Phase 0 setup, this schema spec, and every parent skill all
reference the same constraint. The schema does NOT re-assert or
re-derive the regex — it is cited so the constraint cannot drift
between surfaces.

The topic slug also appears in the state-file path
(`wip/charter_<topic>_state.md`), the terminal artifact filename
(`docs/strategies/STRATEGY-<topic>.md`), and downstream child wip/
paths. The Phase 0 setup procedure (see
`skills/charter/references/phases/phase-0-setup.md`) rejects any
non-conforming `$ARGUMENTS` before the state file is created, so a
state file on disk has a topic that already satisfies the regex.

## Full Field Schema

The schema has 17 fields total: 11 always-present, plus 6 conditional
fields whose presence is gated by a specific `exit:` or
`decision_record_sub_shape:` value. Each field is documented below
with its type, semantics, and gating condition (where applicable).

### Always-Present Fields

These 11 fields are present in every well-formed `/charter` state
file at every phase pointer.

- **`topic`** — string matching `^[a-z0-9-]+$`. The topic slug; set
  at Phase 0 and never modified afterward. Cited from the pattern-
  level regex source above.
- **`phase_pointer`** — parent-phase enum string. Names which phase
  `/charter` is in when interrupted; the resume ladder consumes this
  field to decide where to re-enter. Allowed values are
  `/charter`'s named phases drawn from SKILL.md's Phase Execution
  list: `0` (Phase 0 setup), `1` (Phase 1 discover), `2` (Phase 2
  chain orchestration), `N` (Phase N finalize). Written at Phase 0
  entry with the initial value `0` (see
  `skills/charter/references/phases/phase-0-setup.md` step 0.3) and
  advanced on every phase transition.
- **`chain_started`** — ISO-8601 timestamp string. The wall-clock
  time of the first Phase 0 write for this topic. Set once; never
  modified.
- **`chain_completed`** — ISO-8601 timestamp string. The wall-clock
  time of finalization (the moment `exit:` is set to one of
  `full-run`, `re-evaluation`, or `abandonment-forced`). Absent
  while the chain is in progress; required at finalization.
- **`last_updated`** — ISO-8601 timestamp string. Written on every
  state-file modification. Used by the resume-ladder stale-session
  check.
- **`planned_chain`** — ordered list of child-name strings naming
  which children are in scope for this run. Values are drawn from
  `{vision?, comp?, strategy, roadmap?}` (children with `?` are
  conditional on Phase 1 signals; `strategy` is unconditional). Set
  at Phase 1 chain-proposal acceptance; modified only if the author
  re-proposes the chain.
- **`chain_ran`** — ordered sub-list of `planned_chain` naming the
  children whose invocations completed (the child wrote its durable
  artifact and `/charter` recorded the result). Appended-to as each
  child completes; never overwritten.
- **`chain_skipped`** — list of `{child, reason}` entries. The
  child name plus the free-text human-readable reason the chain
  skipped the child. The reasons are NOT parsed by tooling — they
  are durable evidence for human readers reviewing the chain.
- **`exit`** — string from `{full-run, re-evaluation, abandonment-
  forced}`. UNSET while the chain is in progress; SET to one of the
  three values at finalization. The R9 hard finalization check (see
  below) fires when this field is unset or invalid at termination.
- **`exit_artifacts`** — list of `{path, status}` entries. Each
  entry records a durable file the chain produced; `path` is a
  string pointing at the file (e.g.,
  `docs/strategies/STRATEGY-<topic>.md`); `status` is drawn from
  `{Draft, Accepted, Active}` (the durable artifact's frontmatter
  status value at the moment of finalization). For `exit:
  full-run` the list may be one entry (STRATEGY only) or two
  entries (STRATEGY + ROADMAP) depending on the chain shape.
- **`child_snapshots`** — mapping from child-name to a `{path,
  status, content_hash}` block, with one entry per child in
  `planned_chain`. The `path` is the child's durable doc path;
  `status` is the frontmatter `status:` value at last `/charter`
  exit; `content_hash` is the git blob hash of the durable doc at
  that time. The dual-check drift detection rides on these fields
  (drift fires when EITHER `status` OR `content_hash` differs from
  live on the next `/charter` resume).

### Conditional Fields

These 6 fields are present iff a specific `exit:` or
`decision_record_sub_shape:` value triggers them. When their
triggering condition does not hold, the field MUST be absent from
the state file — not set to null, not set to an empty string, not
set to a placeholder value. Absence-when-not-applicable is the R9
gating discipline (see Conditional-Field Gating Discipline below).

- **`decision_record_sub_shape`** — string from `{re-evaluation,
  rejection}`. The sub-shape identifies which Decision Record body
  shape the chain produced.
  - **Required iff** `exit: re-evaluation`.
  - **MUST be absent otherwise** (for `exit: full-run` and `exit:
    abandonment-forced`, this field does not appear in the state
    file).
- **`referenced_strategy`** — path string pointing at the existing
  STRATEGY the Decision Record's re-evaluation references (e.g.,
  `docs/strategies/STRATEGY-<topic>.md`).
  - **Required iff** `decision_record_sub_shape: re-evaluation`.
  - **MUST be absent otherwise** (when `exit:` is not
    `re-evaluation`, or when `decision_record_sub_shape:` is
    `rejection`, this field does not appear).
- **`discard_commit_sha`** — git SHA string identifying the commit
  in which the Draft STRATEGY was discarded.
  - **Required iff** `decision_record_sub_shape: rejection`.
  - **MUST be absent otherwise**.
- **`rejection_rationale`** — free-text string capturing the
  author's stated rejection rationale (durable evidence for human
  readers).
  - **Required iff** `decision_record_sub_shape: rejection`.
  - **MUST be absent otherwise**.
- **`triggering_child`** — child-name string identifying which
  invoked child triggered the abandonment-forced exit (the child
  the chain could not finish past).
  - **Required iff** `exit: abandonment-forced`.
  - **MUST be absent otherwise** (for `exit: full-run` and `exit:
    re-evaluation`, this field does not appear).
- **`partial_phase_reached`** — phase-name string identifying the
  parent-phase pointer the chain reached before the
  abandonment-forced exit fired.
  - **Required iff** `exit: abandonment-forced`.
  - **MUST be absent otherwise**.

### Schematic YAML Example

The following YAML body illustrates the always-present fields plus
the conditional fields that fire on a `re-evaluation` exit. Other
exit shapes (full-run, abandonment-forced) omit the
`decision_record_sub_shape` / `referenced_strategy` /
`discard_commit_sha` / `rejection_rationale` / `triggering_child` /
`partial_phase_reached` fields per their gating rules.

```yaml
topic: <topic-slug>
phase_pointer: N
chain_started: <ISO-8601 timestamp>
chain_completed: <ISO-8601 timestamp>
last_updated: <ISO-8601 timestamp>
planned_chain: [vision?, comp?, strategy, roadmap?]
chain_ran: [<sub-list of completed children>]
chain_skipped:
  - child: <name>
    reason: <free text>
exit: re-evaluation
decision_record_sub_shape: re-evaluation
exit_artifacts:
  - path: <decision-record-path>
    status: Accepted
child_snapshots:
  strategy:
    path: docs/strategies/STRATEGY-<topic>.md
    status: Accepted
    content_hash: <git-blob-hash>
referenced_strategy: docs/strategies/STRATEGY-<topic>.md
```

The shape of `exit_artifacts` for a STRATEGY-only full-run is one
entry (the STRATEGY path). The shape for a STRATEGY + ROADMAP
full-run is two entries (the STRATEGY path and the ROADMAP path,
each with its own status). The shape for re-evaluation is one
entry (the Decision Record path). The shape for
abandonment-forced is one entry (the schema-compliant partial
artifact path).

## Conditional-Field Gating Discipline

The six conditional fields above are gated by R9 (invariant I-5 of
the pattern). Each conditional field carries a "required iff
<condition>; MUST be absent otherwise" rule documented above.

The discipline has two halves and BOTH bind:

1. **Required when the triggering condition holds.** A state file
   with `exit: re-evaluation` MUST have
   `decision_record_sub_shape:` set; a state file with
   `decision_record_sub_shape: re-evaluation` MUST have
   `referenced_strategy:` set; and so on.
2. **Absent when the triggering condition does not hold.** A
   conditional field MUST NOT appear in the state file when its
   trigger does not fire. It MUST NOT be set to null, MUST NOT be
   set to an empty string, MUST NOT be set to a placeholder value
   like `"TBD"` or `"<unset>"`. The field is simply not in the
   YAML body.

The absence-when-not-applicable half is the load-bearing one. A
`referenced_strategy:` set under `exit: full-run` is NOT a no-op
write — it is a contract violation. A `triggering_child: null`
under `exit: re-evaluation` is NOT "field present but unset" —
it is a contract violation. The R9 hard finalization check (see
below) surfaces these violations as clear errors at finalization;
the resume ladder (a companion outline) surfaces them as clear
errors at re-entry.

The discipline composes with the pattern-level conditional-field
gating invariant cited from
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`
(Conditional-field gating section). `/charter`'s six conditional
fields are the parent-specific instantiation.

## R9 Hard Finalization Check

R9 is the contract enforcement mechanism for the parent-skill
pattern. A `/charter` run that completes without recording a valid
`exit:` is a contract violation; the R9 check is the surface that
makes it so.

### When the Check Runs

The R9 check is a **finalization-time** procedure. It runs when the
chain reaches finalization (the moment `exit:`,
`decision_record_sub_shape:` if applicable, `chain_completed:`, and
`exit_artifacts:` are written). The check does NOT run at resume
time — the resume ladder has its own malformed-state-file detection
(see the resume-ladder reference owned by a companion outline). The
check does NOT run at every state-file write — the intermediate
writes legitimately have `exit:` unset.

### What the Check Verifies

The check has four failure modes. Any of the four fires the check;
the check passes only when none of them does.

1. **Failure mode 1 — `exit:` unset or invalid.** The `exit:` field
   is unset, or its value is not in `{full-run, re-evaluation,
   abandonment-forced}`. A finalization-time state file with `exit:
   UNSET`, `exit: null`, `exit: ""`, or `exit: <typo>` fails the
   check.
2. **Failure mode 2 — sub-shape unset or invalid for re-evaluation
   exit.** `exit: re-evaluation` AND `decision_record_sub_shape:`
   is unset or not in `{re-evaluation, rejection}`. A finalization
   with `exit: re-evaluation` and no `decision_record_sub_shape:`
   field, or with `decision_record_sub_shape: <typo>`, fails the
   check.
3. **Failure mode 3 — conditional field present when ungated.** A
   conditional field is present in the state file when its
   triggering condition does not hold. Example: `referenced_strategy:
   docs/strategies/STRATEGY-<topic>.md` set when `exit: full-run`,
   or `triggering_child: /strategy` set when `exit: re-evaluation`.
   The field MUST be absent; presence-when-ungated fails the check.
4. **Failure mode 4 — conditional field set to null/empty/
   placeholder when ungated.** A conditional field is present with
   a "falsy" value (null, empty string, placeholder like `"TBD"`)
   under the same ungated condition as failure mode 3. The field
   MUST be ABSENT, not falsy. `referenced_strategy: null` under
   `exit: full-run` fails the check; the correct shape is to omit
   the field entirely.

### How the Check Surfaces Violations

On any failure mode firing, the check surfaces a **clear error**
naming the specific failure mode, the offending field (or its
absence), and the gating condition the field violates. The error
is NOT a soft warning that the run absorbs and continues past; it
is NOT a silent no-op that lets finalization proceed; it is NOT
skipped under `--auto` mode. The check fails closed.

Example error wording:

> *"R9 finalization check failed: `exit: re-evaluation` requires
> `decision_record_sub_shape:` to be set to one of
> `{re-evaluation, rejection}`, but the field is unset. Set the
> sub-shape explicitly before completing finalization."*
>
> *"R9 finalization check failed: `referenced_strategy:` is set
> in the state file but `exit:` is `full-run` (gating condition
> `decision_record_sub_shape: re-evaluation` does not hold).
> Conditional fields MUST be absent when their triggering
> condition does not hold; remove `referenced_strategy:` from the
> state file."*

The clear-error surfacing is the load-bearing behavior. Silent
absorption would let a malformed state file persist as durable
evidence (under the v1 `wip-yaml-md` substrate the file lives on
the feature branch; under any amplifier-layer substrate the
malformed record is similarly durable); the malformed record then
breaks the resume ladder's contract surface on the next re-entry.
Failing closed at finalization makes the malformation surface at
write time, not at the next read.

### Why the Check Is the Contract

The pattern-level invariant the check enforces is I-1 (recorded
exit) plus I-5 (conditional fields absent when ungated). Without
the check, a `/charter` run that terminates without recording a
valid exit, or that records an inconsistent combination of `exit:`
and conditional fields, would silently accept the malformed
record. The check turns "I-1 and I-5 hold for every conforming
state file" into a verifiable, eval-able assertion at finalization
time.

## Security Considerations

The state file at `wip/charter_<topic>_state.md` is a **public-repo
durable-evidence surface** in repos with Public visibility. Two
properties matter:

### Pre-Merge Feature-Branch Exposure

The `wip/` artifact is committed to the feature branch during the
run; on push, the branch is publicly visible (in public repos),
and the state file's content is durably part of the branch's
pre-merge history. Squash-merge to main removes the `wip/` files
from main's history, but it does NOT remove them from the feature
branch's pre-merge commits — the durable evidence persists on the
feature branch as long as the branch exists, even after the
squash-merged main no longer carries the file.

The free-text fields are the exposure surface. Authors should
treat these fields as durably public from the moment the feature
branch is pushed:

- **`rejection_rationale`** — the author's prose explaining why a
  Draft STRATEGY was rejected. Durable on the feature branch
  pre-merge; public.
- **`referenced_strategy`** — a path string. The path itself is
  unlikely to be sensitive, but it points at a STRATEGY whose body
  is also durably public on the feature branch.
- **`chain_skipped[].reason`** — free-text reasons for skipping
  children. Durable on the feature branch pre-merge; public.

The same property applies to other free-text fields the schema
might gain later through extension. Treat the entire state file as
durably public from feature-branch push time.

### Free-Text Content Discipline

Authors MUST NOT paste any of the following into the free-text
fields above:

- Secrets (API keys, passwords, tokens, credentials of any kind).
- Customer-identifiable context (customer names, contract terms,
  identifying transcripts).
- Unpublished competitive positioning (pre-announcement product
  framings, deal pricing, internal-only positioning prose).
- Anything else that would not be safe to publish on the feature
  branch's public history.

The discipline is the same as any other public-repo durable
artifact (committed docs, committed code). The schema spec names
it explicitly so authors do not assume `wip/` content is hidden by
the eventual cleanup commit.

### Fail-Closed R9 Check

The R9 hard finalization check fails closed (the chain's
finalization fails with a clear error rather than silently
absorbing the malformation). The fail-closed posture is a
security property as well as a correctness property: it prevents
silent state loss across `storage_substrate` substitutions when
the amplifier layer lands. A core-layer parent that silently
accepts a malformed exit record cannot guarantee the amplifier
layer would surface the same record; failing closed at write time
keeps the contract intact across substrates.

### Topic-Slug Input Validation

The topic slug is the only state-file field whose value is
author-supplied and appears in filesystem paths. The pattern-level
regex `^[a-z0-9-]+$` (cited above) prevents path traversal via
slug: slashes, dots, and any other path-separator characters are
hard-rejected at Phase 0 before the state file is created. The
regex source lives in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`;
this schema spec cites that source rather than re-asserting the
regex, so the constraint cannot drift between SKILL.md, Phase 0,
and the state-file schema.

### Conditional-Field Discipline as a Contract-Confusion Defense

The conditional-field absence-when-not-applicable rule is also a
contract-confusion defense. A `referenced_strategy:` set under
`exit: full-run` is not a no-op; it would be interpreted by a
downstream reader (or by a future amplifier-layer migration tool)
as a legitimate field, and the migration would have to make an
inference about what the field means in an unrelated exit shape.
The R9 hard finalization check eliminates this inference surface
by failing closed on presence-when-ungated.

### No Executable Code, No Third-Party Dependencies

This file is documentation only. No third-party dependencies are
introduced by the schema spec, and no executable validation logic
is added in this issue. The validation execution lives in the
resume ladder (malformed-state detection at re-entry, owned by a
companion outline) and the exit-path orchestration (R9 check at
finalization, owned by another companion outline). The schema spec
is the contract surface those implementations bind to.
