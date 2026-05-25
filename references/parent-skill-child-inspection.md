# Parent-Skill Child Inspection

The rule every parent skill follows when reading from its invoked
children: a parent SHALL read only the child's *durable externally-visible
status surface*; the parent SHALL NOT read child internals. This document
names the rule, enumerates the per-parent surface table, defines the
drift-detection semantics that ride on top, and lists what counts as
"internals" with negative examples.

The rule is the pattern's R14 widened. The PRD-level R14 phrasing ("parent
reads only child doc frontmatter `status:` and topic slug; never
internals") assumed every child emits a doc with frontmatter; the widened
rule generalizes to non-doc-emitting children (issues, PRs) without
forcing carve-outs.

Companion references:

- [`parent-skill-pattern.md`](parent-skill-pattern.md) — the contract surface
  this rule sits inside.
- [`parent-skill-state-schema.md`](parent-skill-state-schema.md) — the
  per-child snapshot dual-check this rule's drift detection rides on.

## The Isolation Rule

> A parent SHALL read only the child's *durable externally-visible status
> surface*; the parent SHALL NOT read child internals.

The rule has two halves and both bind.

**Half 1: durable externally-visible status surface.** The parent's read
target is whatever the child publishes as its durable, externally-visible
status — a frontmatter field on a committed doc, an issue state, a PR
state with its labels and CI rollup. The surface is what a human reviewer
or another tool would consult to learn whether the child completed and
how.

**Half 2: never internals.** The parent's read target SHALL NOT include
the child's intermediate workings — research notes, scratch state,
ephemeral coordination files, internal phase pointers, log streams,
comment threads, or anything else the child uses to drive its own
execution. Internals are off-limits even when reading them would be
operationally convenient.

The rule's purpose: a child's internal structure is the child's
implementation detail. A parent that reads internals couples to those
details and breaks the moment the child reorganizes them; a parent that
reads only the externally-visible surface stays stable across child
refactors. The rule also preserves R13 manual-fallback non-interference
(see Manual-Fallback Non-Interference below): a child invoked directly
outside the parent leaves the same externally-visible surface a child
invoked through the parent leaves, so the parent's resume ladder
inspects the same fields regardless of invocation path.

## Per-Parent Surface Table

The status surface is parent-specific because different parents invoke
different shapes of child. The table below names the surface for each
recognized child shape.

| Child shape | Status surface (read by parent) |
|---|---|
| doc-emitting (committed doc with frontmatter) | child doc's frontmatter `status:` value + the doc's content fingerprint (git blob hash) |
| issue or PR (no doc) | issue/PR state + labels + CI check rollup |

The table grows as new parents land children with new shapes. Each parent
that invokes a new child shape adds a row; new rows go through the
parent's own PR review.

**Doc-emitting children.** The status surface is two fields: the
frontmatter `status:` (e.g., Draft, Accepted, Active) and the git blob
hash of the durable doc file. The blob hash is the content fingerprint —
two commits of the same file with different bodies produce different blob
hashes, even when the frontmatter status is unchanged.

**Issue or PR children.** The status surface is three fields: the
issue/PR's state (Open, Closed, Merged), the set of labels attached, and
the CI check rollup (the durable terminal verdict of the PR's checks —
green, red, or pending). The CI check rollup is the externally-visible
durable terminal state; individual check logs are internals.

## Drift Detection

The per-child snapshot dual-check (see
[`parent-skill-state-schema.md`](parent-skill-state-schema.md)) rides on
the per-parent surface table. The state file records both fields of the
surface at the parent's last exit; on re-entry, the parent compares both
fields against live values, and **drift fires when EITHER field differs
from live**.

For doc-emitting children, drift fires when the status flipped
(Draft → Accepted) OR when the blob hash differs (the body was edited).

For issue or PR children, drift fires when the state flipped (Open →
Closed) OR when the label set differs OR when the CI check rollup
differs.

The dual (or multi) check is load-bearing. A single-field check would
miss the common case where a sibling status stays the same but its
content changed (a STRATEGY Draft → Draft with a rewritten Building
Blocks section, a PR Open → Open with new commits that flipped CI from
green to red). The dual-check makes both flips visible.

Drift detection is a signal, not a unilateral action. When drift fires,
the parent's resume ladder surfaces a parent-specific prompt (commonly:
re-run the downstream child, accept the downstream as still-valid,
proceed without the downstream); the parent does NOT act on drift
without author confirmation.

## Manual-Fallback Non-Interference

R13 manual-fallback is the discipline that pairs with R14 isolation. A
parent SHALL treat direct invocation of any of its children outside the
parent as first-class steady-state behavior — not as a degraded path,
not as a workaround. The parent MUST NOT detect, warn against, or
otherwise interfere with manual invocation.

The non-interference framing is what makes R14 isolation sustainable. If
the parent inspected child internals, those internals would carry
within-parent context that direct invocation lacks, and the parent would
either need to fall back to a degraded resume path (couplng on
within-parent context) or warn against manual invocation (interference).
By inspecting only the durable externally-visible status surface, the
parent reads identical signals whether the child ran inside the parent or
outside it — non-interference is structural, not a behavioral exception.

The resume ladder's drift-detection semantics (above) handle the case
where manual invocation produced an out-of-chain edit: the parent reads
the same status surface fields, computes drift the same way, and surfaces
the same prompt. Direct invocation leaves the same fingerprint a
chain-run invocation leaves; the surface IS the contract.

## What Counts as Internals (Negative Examples)

The list below names artifacts the parent SHALL NOT read. The list is
not exhaustive — anything not on the per-parent surface table is
internals — but the examples cover the common temptations.

- **`wip/research/<child>_*.md`** — research notes and scratch files the
  child writes during its own execution. Off-limits whether or not they
  exist on the branch; the parent's resume ladder NEVER consults them.
- **CI logs** — the body of CI check logs (the output of each individual
  job, error messages, stack traces). The CI check rollup (green / red /
  pending) is on the surface for issue/PR children; the per-log body is
  internals.
- **Comment threads** — review comments, issue comments, discussion
  threads attached to the child. The parent does NOT mine comment
  threads for status signals.
- **Internal phase-pointer state** — a child's own state file (e.g., a
  child skill's wip-state file under the same substrate convention). The
  child's state file is the child's internals; the parent reads only the
  child's durable artifact (doc / issue / PR).
- **Child's resume-ladder choices** — if a child's resume ladder
  decided to skip a sub-step, that choice lives in the child's
  internals. The parent reads only the durable output the child
  produced.

The list grows when a new internal surface becomes operationally
tempting; adding a row reaffirms the rule rather than amending it.
