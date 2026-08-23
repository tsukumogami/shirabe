# Phase Resume — Status-Aware Re-Entry, Partial-Child-Run, Feeder-Doc, Drift Detection

`/scope`'s resume ladder fills the parent-specific body slots (rows
5-7) of the universal meta-ladder at
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-resume-ladder-template.md`.
This reference enumerates the per-row prompts, the refuse-and-
redirect shape for PLAN's downstream-owned lifecycle states, the
Slot 7 clause consuming an `/explore` handoff, the re-validation
every value recovered from the workflow session passes at the
resume entry, and the dual-check drift-detection contract `/scope`
runs against `child_snapshots:` on every ladder match.

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
- **6.2 `wip/design_<topic>_coordination.json` exists.** Re-invoke
  `/design`.
- **6.3 `wip/prd_<topic>_decisions.md` exists.** Re-invoke `/prd`.
- **6.4 `wip/brief_<topic>_*` exists.** Re-invoke `/brief`.

**Why 6.2 and 6.3 name one file where 6.1 and 6.4 glob a prefix.**
A child's scoping artifact is the one file in its namespace that a
feeder doc imitates by construction. A feeder doc pre-supplies the
child's Phase 1 output so the child can skip Phase 1, which lands it
at the child's own scoping path: `wip/design_<topic>_summary.md` for
`/design`, `wip/prd_<topic>_scope.md` for `/prd`. Neither file proves
a `/design` or `/prd` run started, so neither can carry a row whose
action is to jump straight into that child.
`wip/design_<topic>_coordination.json` is `/design`'s decomposition
ledger, written by its Phase 1 and by nothing else.
`wip/prd_<topic>_decisions.md` is `/prd`'s autonomous-decision
ledger, written at context resolution under `--auto`. Both exist only
because the child itself ran. `/plan` and `/brief` write nothing at a
scoping path a feeder doc would reach for (their intermediates are
`wip/plan_<topic>_analysis.md`, `wip/brief_<topic>_discover.md`, and
their siblings), so 6.1 and 6.4 keep the prefix glob.

**The narrowing is defense in depth, not the live fix.** The
collision was real: the old 6.3 globbed `wip/prd_<topic>_*`, which
caught `wip/prd_<topic>_scope.md`, the file the pre-router
`/explore` wrote for `/prd`, so a router handoff read as an
interrupted `/prd` run and skipped `/brief`, Phase 1, and the chain
proposal. What closed that is the move of the handoff to
`wip/scope_<topic>_handoff.md`, which Slot 7 matches and no Slot 6
row can. The narrowing covers what the move does not reach: a
handoff left on disk by an older `/explore`, a hand-written feeder
doc, or a future producer that reaches for the child-namespaced
convention `/charter` still uses for its own pre-populated
`/roadmap` handoff.

**What it costs is one hop, in the safe direction.** An interactive
`/prd` interrupted after its own Phase 1 leaves only
`wip/prd_<topic>_scope.md`, so no Slot 6 row fires and the ladder
falls through to a normal start: Phase 0, Phase 1, the chain
proposal. The scoping work is not lost. `/prd` resumes at its own
Phase 2 off that same file when the chain reaches it, because that is
what `/prd`'s resume ladder does with it. All the row gives up is a
jump taken on evidence that cannot support it.

Slugs recovered from on-disk paths during Slot 6 matches and during
the Slot 7 feeder-doc match against `wip/scope_<topic>_handoff.md`
follow the slug re-validation rule documented in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-security.md`
(Slug Re-Validation on Resume section): re-validate against
`^[a-z0-9-]+$` before interpolation into any emitted shell command.
Slot 7 is covered for the same reason the wip partials above are:
the slug arrives from a filename found on disk, not from the
author's argument.

## Slot 7 — Feeder-Doc-Detected (the `/explore` handoff)

**Match condition.** `wip/scope_<topic>_handoff.md` exists on disk,
and no row above matched — no state file at
`wip/scope_<topic>_state.md`, no child doc at a status Slot 5
recognizes, and no child wip partial Slot 6 matches. Beyond the
rows above not matching, that one path is the whole condition: the
slot reads no other file to decide whether it fires, and it never
fires on a path in another skill's
namespace: `wip/scope_<topic>_handoff.md` is composed from
`/scope`'s own prefix and the validated topic slug, which is what
keeps it inside the closed write-target set enumerated in
`skills/scope/SKILL.md`.

**Action.** Run Phase 0's setup obligations against the current
worktree — slug validation, the slug-prefix convention check,
visibility detection, `--upstream` validation when the invocation
supplied one, and state-file creation — then enter Phase 1 with the
handoff pre-loaded as discovery input. Record `consumed_handoff:
wip/scope_<topic>_handoff.md` in the state file at the same write.

Phase 1 runs. The slot never skips it, and it never invokes a child
directly: a handoff is discovery material, not a resume point
inside the chain. `planned_chain:` is `[brief, prd, design, plan]`
on a handoff run exactly as on any other, and the chain proposal is
emitted and confirmed as always.

Four Phase 1 behaviors change, and the rest do not:

- **The framing-shift question is still surfaced**, as a
  confirmation rather than a fresh ask: the exploration concluded X;
  confirm or correct it. The author's response is what gets
  recorded. A pre-supplied answer is never accepted as recorded
  state — it is the one carried value that reaches a gate (a
  positive answer fires `/brief` against an Accepted BRIEF), so the
  confirmation is mandatory rather than a formality. Under `--auto`
  the pre-supplied answer is taken and announced rather than applied
  silently.
- **The child-doc globs are unchanged.** They are filesystem reads
  and they run on every invocation, handoff or not.
- **The cold-start projected-PRD evaluation is suppressed.** A
  handoff run is not a cold start; the projection exists to guess
  from a slug what the handoff states outright.
- **Two of the three R6 shape predicates accept the handoff's
  estimate** with the reasons it states — P1 (architectural
  alternatives) and P3 (Complex classification). **P2 is recomputed
  against the tree**, because it cross-references the repo's
  directory structure and the handoff carries no filesystem
  material for it. All three are re-derived against the real PRD by
  the post-`/prd` re-evaluation gate regardless, which is what makes
  accepting an estimate safe here.

**What the handoff carries.** Six sections shared with `/charter`'s
row 8.5, the parent-specific block, and one block only `/scope`
carries: provenance (which
exploration wrote it, when); the problem statement; the scope
boundary; the decisions the exploration already settled; coverage
notes on what it did and did not examine; observations about
upstream artifacts it found; the author's framing-shift answer with
the evidence behind it; and a shape-signals block carrying the
architectural alternatives left open and the complexity signals
surfaced — predicate inputs, never predicate verdicts.

**What it does not carry, and what that means here.** The handoff
carries conversation, never filesystem state. It states no
artifact's existence, no frontmatter `status:`, no content hash, no
repo visibility, and no upstream validation result. Every one of
those is re-read on every run: the child-doc globs establish what is
on disk, Phase 0's visibility detection reads CLAUDE.md's `## Repo
Visibility:` header, Phase 2 computes child snapshots itself, and a
`--upstream` value is validated from the invocation argument rather
than from this file. A handoff that carries such a value anyway is
ignored on that value, not trusted and not treated as malformation.

**A malformed handoff degrades to a cold start.** If the file is
truncated, unparseable, or missing the sections above, `/scope`
announces that it found a handoff it could not consume, names the
path, and proceeds as though none existed — cold-start projection
included. There is no partial consumption: a half-read handoff
would pre-supply some discovery inputs and not others with no way
for the author to tell which. `consumed_handoff:` is not written on
this path, because nothing was consumed.

**When a higher row fires first.** A settled artifact on disk wins.
The handoff has nothing to say about it — being barred from
carrying existence, status, or hashes, it cannot be the more
current evidence — so a Slot 5 or Slot 6 match takes its own
action, and Slot 7 is never reached. The handoff is not silently
dropped: the row that fires states that a router handoff exists at
`wip/scope_<topic>_handoff.md` and was not consumed, and offers its
problem statement as context for the choice the row is asking the
author to make. The file is left on disk, so a later Revise that
clears the way down the ladder reaches this slot on its own terms.

**The topic-branch row below, and why it does not collide.**
`/explore` Phase 0 creates a `docs/<topic>` branch, so an author
arriving from an exploration is usually standing on a branch the
meta-ladder's on-topic-branch row matches — and that row resumes at
Phase 1, skipping Phase 0, on what the author experiences as a
first invocation. It never fires on a handoff run: the meta-ladder
tail sits below every body slot, so Slot 7 is evaluated first and
takes its action, which runs Phase 0's setup obligations before
Phase 1 rather than skipping them. What the branch row is left
holding is the residual case — an exploration that routed here but
wrote no handoff, or one whose handoff was already consumed and
cleaned up. Resuming at Phase 1 on an existing topic branch is the
behavior that row was written for, so it stays as it is.

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

## Session-Recovered Value Re-Validation

Every value this ladder recovers from the workflow session is
re-validated before it is used, on the same grounds the recorded
upstream is: koto does not constrain a string-typed evidence field
at all, so a value coming back out of a session is untrusted input
exactly as a state-file field read from disk is. The rule is the one
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-security.md` states
for state-file fields, applied at a second site rather than a new
rule — enums against their enum, path-valued fields against the
anchored pattern for their type.

- **The session's position** — the state name reported by the probe
  — is matched against the state set in
  `skills/scope/koto-templates/scope.md`. A name that is not one of
  them yields no `phase_pointer:` derivation; the ladder reports it
  and falls back to the recorded pointer rather than guessing a
  phase from a string.
- **Enum-valued evidence** (`exit`, `boundary`,
  `decision_record_sub_shape`, `plan_execution_mode`,
  `triggering_child`, each hop's `outcome`, the fold's `verdict`)
  is re-validated against the values that state's `accepts` block
  declares, before the value reaches a state-file write or a
  constructed path.
- **Path-valued evidence** (`exit_artifacts`, and any recovered
  field naming a document) is re-validated against the anchored
  canonical path for its type, composed from the validated slug.
  Several exit-path required fields are path-valued strings and
  several of them reach a write path, which is what makes this limb
  load-bearing rather than defensive.
- **The origin record** is not parsed and not interpolated. Its
  session name is recomputed from the validated slug and compared
  for equality; its worktree and store are compared against the
  values this invocation computes for itself.

Out-of-pattern values are refused with a diagnostic naming the field
and route to R8 bail-handling, which is what the equivalent
state-file check does.

**The ladder evaluates without a session, and that is the ordinary
case.** Its rows key on artifact status, child intermediates, the
handoff and the branch — none of which the session holds. A topic
with an Accepted PRD at `docs/prds/PRD-<topic>.md`, no state file
and no session still reaches row 5.6 and offers that row's triad at
the PRD boundary, because nothing above it matched and the row's
condition is a file on disk. The probe's finding changes what the
run reattaches to, never which row fires.

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

**This trigger is preserved as it stands, not repaired here.** It is
unsatisfiable as written: its condition wants an existing state
file, and the rows that could match it are reached only when the
universal rows above them did not fire — which, for every shape of
state file, is a case those upper rows take. So no Slot 5 or Slot 6
match arrives carrying the state file this condition asks for, and
the walk below it never runs. Moving `/scope` onto a workflow
session touches none of that: the session holds position and the
snapshots stay where they are, so the defect is neither introduced
nor worsened by this work, and it is left exactly as found rather
than fixed on a branch that changes the substrate underneath it.
Repairing it means deciding what a drift check should compare
against when there is no state file to hold the frozen pair, which
is its own question and its own change.

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
  Slug re-validation on resume; State-file enum re-validation, the
  rule the session-recovered values above are validated under.
- `skills/scope/references/phases/phase-0-setup.md` — the Workflow
  Session section, which states the probe, the origin check and the
  naming rule this ladder's re-validation assumes.
- `skills/scope/references/state-schema.md` — the
  `child_snapshots:`, `drift_acknowledged:`, and `worktree_rebases:`
  fields the drift-detection prompt writes against, and the
  `consumed_handoff:` field Slot 7 writes and this ladder reads.
