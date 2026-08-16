# Phase Resume — Status-Aware Re-Entry, Partial-Child-Run, Drift Detection

`/scope`'s resume ladder fills the parent-specific body slots (rows
5-7) of the universal meta-ladder at
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-resume-ladder-template.md`.
This reference enumerates the per-row prompts, the refuse-and-
redirect shape for PLAN's downstream-owned lifecycle states, and
the dual-check drift-detection contract `/scope` runs against
`child_snapshots:` on every ladder match.

## Slot 5 — Status-Aware Re-Entry (9 rows, most-downstream-first)

The 9 rows are evaluated in first-match-wins order, most-downstream
first so a settled-downstream artifact's lifecycle dominates the
upstream re-entry:

- **5.1 PLAN-Active detected.** `docs/plans/PLAN-<topic>.md` exists
  with status Active. The PLAN's Active lifecycle is owned by
  `/work-on`, not by `/scope`. The prompt **refuses re-entry and
  emits a redirect to /work-on**: "/scope cannot resume against a
  PLAN already under implementation; redirect to /work-on
  <topic-slug>". The Re-evaluate / Revise / Bail triad MUST NOT
  appear here — refuse-and-redirect is not a re-evaluation exit;
  the downstream skill owns the artifact.
- **5.2 PLAN-Done detected.** `docs/plans/PLAN-<topic>.md` exists
  with status Done. The PLAN's Done lifecycle is owned by
  `/release`, not by `/scope`. The prompt **refuses re-entry and
  emits a redirect to /release**: "/scope cannot resume against a
  completed PLAN; redirect to /release <topic-slug>". Same triad
  rule — no Re-evaluate / Revise / Bail; refuse-and-redirect is
  not a re-evaluation exit.
- **5.3 PLAN-Draft detected.** A Draft PLAN exists. `/scope` offers
  a Continue / Discard / Bail prompt aligned with the chain's
  re-entry semantics; a Draft PLAN is the most-downstream
  intermediate `/scope` itself owns.
- **5.4 DESIGN-Accepted detected.** `docs/designs/current/DESIGN-<topic>.md`
  exists with status Accepted. This is a settled-upstream boundary;
  the prompt offers the **Re-evaluate / Revise / Bail** triad and
  identifies the boundary as the **DESIGN-boundary** so the
  resulting Decision Record (if Re-evaluate fires) attaches at
  `boundary: design`. This row MUST NOT contain a "Continue /
  Start fresh" prompt — that vocabulary belongs to a child's own
  resume ladder, not to `/scope`'s boundary re-evaluation.
- **5.5 DESIGN-Proposed detected.** A Proposed DESIGN exists.
  `/scope` offers the Continue / Discard / Bail prompt against the
  draft.
- **5.6 PRD-Accepted detected.** `docs/prds/PRD-<topic>.md` exists
  with status Accepted. This is the second settled-upstream
  boundary; the prompt offers the **Re-evaluate / Revise / Bail**
  triad and identifies the boundary as the **PRD-boundary** so the
  resulting Decision Record attaches at `boundary: prd`.
- **5.7 PRD-Draft detected.** A Draft PRD exists. `/scope` offers
  the Continue / Discard / Bail prompt against the draft.
- **5.8 BRIEF-Accepted (or BRIEF-Done) detected.** An Accepted (or
  Done) BRIEF exists. `/scope` proceeds with the BRIEF as the
  chain's anchor; no prompt fires.
- **5.9 BRIEF-Draft detected.** A Draft BRIEF exists. `/scope`
  offers the Continue / Discard / Bail prompt against the draft.

Row 5.4 fires before row 5.6 when both Accepted artifacts exist:
the most-downstream settled-upstream boundary wins (AC17b).

## Slot 6 — Partial-Child-Run (4 rows, most-downstream-first)

The 4 rows detect a child's wip-partial intermediate and re-invoke
the child against its own resume ladder, most-downstream first:

- **6.1 `wip/plan_<topic>_*` exists.** Re-invoke `/plan` against
  its own resume logic; do not re-run from scratch.
- **6.2 `wip/design_<topic>_*` exists.** Re-invoke `/design`.
- **6.3 `wip/prd_<topic>_*` exists.** Re-invoke `/prd`.
- **6.4 `wip/brief_<topic>_*` exists.** Re-invoke `/brief`.

Slugs recovered from on-disk paths during Slot 6 matches and during
the Slot 7 feeder-doc match against `wip/scope_<topic>_handoff.md`
follow the slug re-validation rule documented in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-security.md`
(Slug Re-Validation on Resume section): re-validate against
`^[a-z0-9-]+$` before interpolation into any emitted shell command.
Slot 7 is covered for the same reason the wip partials above are:
the slug arrives from a filename found on disk, not from the
author's argument.

## Slot 7 — Feeder-Doc-Detected (vacuous in v1)

No feeder defined in v1; reserved for future. The slot is named
explicitly here so future authors recognize the position rather
than re-invent it.

## Recorded-Upstream Re-Validation

When the state file carries `consumed_upstream:`, the ladder
re-validates that value on EVERY re-entry, before any slot's action
runs and before the path is interpolated into a child invocation.
The re-validation re-runs the whole battery from
`skills/scope/references/phases/phase-0-setup.md` — canonicalize
and bounds-check, `ROADMAP-` basename, not under `wip/`, tracked by
git, and the public-repo-to-private-upstream visibility check —
against the worktree as it is NOW, not as it was when the value was
recorded. A file tracked last week can be deleted or moved this
week, and a repo's `## Repo Visibility:` header can change between
sessions.

**A recorded upstream that no longer resolves is surfaced, never
silently ignored.** Silently dropping it would hand `/brief` a
chain with no upstream and produce a BRIEF whose missing
`upstream:` field looks like a document that never had one;
silently keeping it would carry a dangling path into committed
frontmatter. The ladder surfaces what failed — the recorded path
and which check it now fails — and offers three options:

- **Re-supply** — stop and ask the author to re-invoke
  `/scope <topic> --upstream <path>` with a working path. The
  recorded value is cleared from state so the next invocation
  starts from the author's new one. This is the interactive
  default.
- **Continue without** — remove `consumed_upstream:` from the state
  file and resume with no upstream. The produced BRIEF omits
  `upstream:`, which the run states plainly rather than leaving the
  author to notice later.
- **Bail** — route to R8 bail-handling.

Under `--auto` the ladder takes **Continue without** and announces
it, because a blocking prompt has no place in a non-interactive
run. Announcing is the load-bearing half: the auto default drops a
link the author asked for, so the drop is reported in the run
output whether or not anyone is watching.

The re-validation is a second interpolation site, not a repeat of
the first, and carries the same discipline: the recorded value is
canonicalized, bounds-checked, and quoted and passed after `--` in
every command the ladder emits with it. A state file is a file on
disk that a hand-edit can change between sessions, so the value
read back is treated as untrusted input exactly as the flag's
original value was.

The visibility check deserves its own note. It can fail on a resume
that had passed at Phase 0 — the repo went public, or the upstream
moved into a private repo — and the outcome is the same as Phase
0's: the field is removed rather than carried, and the chain
continues without it.

## Drift Detection

When `/scope` re-enters a chain (any Slot 5 or Slot 6 ladder match
against a topic with an existing state file), it walks
`child_snapshots:` and compares each child's frozen
`{status, content_hash}` against the live child doc at the
canonical durable path. Drift fires when EITHER the live
frontmatter `status:` differs from the snapshot's `status` OR the
live git blob hash (`git hash-object` against the child's durable
artifact) differs from the snapshot's `content_hash` — the dual
check is load-bearing per R10's snapshot semantics, and either
direction alone is sufficient to trigger the staleness prompt.

The inspection surface is intentionally narrow: `/scope` reads only
the child doc's frontmatter `status:` and computes the doc's git
blob hash. It does NOT read child internals, does NOT read
`wip/research/<child>_*.md`, and does NOT consult any other
child-private state per the R14-widened isolation rule. The drift
check uses the same externally-visible surface the initial snapshot
capture used in Phase 2, so the comparison is symmetric.

When drift is detected, `/scope` surfaces a three-option staleness
prompt and the author chooses the path. `/scope` does NOT act on
drift unilaterally — the prompt is mandatory in `--interactive`
mode and the recommended default in `--auto` mode is `Re-run`. The
three options are part of the contract surface (the eval grades
against the literal substrings) and appear verbatim:

- **Re-run** — re-invoke the affected child against the new
  upstream state. The child runs its standalone resume ladder
  against the current live artifact; on completion, `/scope`
  replaces the frozen entry in `child_snapshots:` with the new
  `{status, content_hash}` pair captured post-invocation.
- **Accept** — accept the drift as intentional (e.g., a manual
  fallback applied between sessions, where the reviewer knowingly
  revised the child's durable artifact). `/scope` updates the
  `child_snapshots:` entry to the new `{status, content_hash}`
  WITHOUT re-invoking the child. The snapshot now reflects the
  manual-fallback edit as the authoritative baseline for subsequent
  re-entries.
- **Proceed-without** — keep the original frozen snapshot in
  `child_snapshots:` (the snapshot is NOT updated) and proceed
  against the original chain intent, recording the drift in
  `drift_acknowledged:`. The audit field mirrors the
  `worktree_rebases:` shape with one entry per acknowledged drift:
  `{child, original_status, original_content_hash, observed_status,
  observed_content_hash, acknowledged_at}`. This is the audit
  surface for "I knowingly kept going against the original snapshot
  even though upstream changed" — the divergence is recorded, not
  hidden, and a future reviewer can grep the state file for
  `drift_acknowledged:` to find every intentional divergence.

The drift-detection contract preserves R13 manual-fallback
non-interference: the prompt fires on `/scope` re-entry, NOT on the
manual child invocation itself. A reviewer running `/prd
docs/prds/PRD-<topic>.md` directly outside `/scope` triggers no
warning, no state-file write, and no block against the manual
invocation. The drift is observed only when `/scope` re-enters and
walks its own `child_snapshots:` — the state file is internal to
`/scope`'s chain, and the manual invocation does not modify it.

## References

- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-resume-ladder-template.md`
  — the universal meta-ladder rows 1-4 and 8-9 framing this slot
  body fits into.
- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-child-inspection.md`
  — R14-widened isolation rule and the dual-check inspection
  surface.
- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-security.md` —
  Slug re-validation on resume; State-file enum re-validation.
- `skills/scope/references/state-schema.md` — the
  `child_snapshots:`, `drift_acknowledged:`, and `worktree_rebases:`
  fields the drift-detection prompt writes against.
