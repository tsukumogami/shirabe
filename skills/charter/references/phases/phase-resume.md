# Phase: Resume Ladder

The resume ladder is `/charter`'s entry-point decision logic for any
invocation that finds prior state on the topic. It runs on every
invocation against an existing topic: a state file in `wip/`, an
upstream STRATEGY at the published path, a child's partial-run
artifact, or just a branch related to the topic — any of these means
the topic is not fresh, and the ladder decides where re-entry lands.

The ladder is **first-match-wins, top-to-bottom**: it tests row 1's
condition first, and the first row whose condition matches takes the
row's action; the remaining rows are not consulted. When no row
matches, control falls through to row 10's start-fresh path.

Rows 1-4 and 9-10 inherit the universal meta-ladder from the
pattern-level template at
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-resume-ladder-template.md`.
Rows 5-8 are `/charter`'s parent-specific body slots: rows 5-6 fill
the status-aware re-entry slot against an upstream STRATEGY; rows 7-8
fill the partial-child-run slots against `/strategy` and `/vision`
wip/ artifacts.

The contract framing for drift detection plus the R14-widened
child-internals isolation rule is cited from
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-child-inspection.md`.

## The 10-Row Ladder

```
1.  state file malformed                                  -> Hard error naming malformation + offer Discard
2.  state file has exit field set                         -> Exit-value-specific re-entry prompt
3.  state file exists, last_updated < 7d                  -> Resume at recorded phase_pointer (no prompt)
4.  state file exists, last_updated >= 7d                 -> Resume / Force-materialize / Discard prompt
5.  STRATEGY-<topic>.md Accepted/Active                   -> "Re-evaluate" / "Revise" / "Bail" prompt
6.  STRATEGY-<topic>.md Draft                             -> continue-or-start-fresh prompt
7.  wip/strategy_<topic>_discover.md exists               -> Resume into /strategy
8.  wip/vision_<topic>_scope.md exists                    -> Resume into /vision
9.  On branch related to topic                            -> Resume at Phase 1
10. On main or unrelated branch                           -> Start at Phase 0
```

Each row is documented below with its match condition and the
specific action `/charter` takes when the row fires.

## Row 1 — Malformed State File

**Match condition.** `wip/charter_<topic>_state.md` exists but cannot
be parsed as YAML, is missing required fields for the recorded
`phase_pointer`, or has an inconsistent combination of `exit:` and
gated fields (e.g., `exit: re-evaluation` with no
`decision_record_sub_shape:` set; `decision_record_sub_shape:` set
without `exit: re-evaluation`; any conditional-field present-when-
ungated case per the conditional-field gating discipline in
`skills/charter/references/phases/phase-state-management.md`).

**Action.** Surface a **hard error** that names the specific
malformation (not "the state file is malformed" — name what is
wrong: "unparseable YAML at line N"; "missing required field
`phase_pointer`"; "`exit: re-evaluation` requires
`decision_record_sub_shape:` but it is unset"). Then offer
**Discard** as the recovery path. Discard removes the state file
and allows the author to restart the chain at Phase 0.

**The ladder MUST NOT silently fall through to row 10 (Phase 0
start) when row 1 fires.** Malformed state is a contract violation
surface, not a missing-state surface — silently starting fresh
would hide upstream chain corruption and risk wedging the topic
across invocations. The author confirms Discard explicitly; row 1
is terminal.

## Row 2 — Exit Field Already Set

**Match condition.** The state file exists, is well-formed, and has
`exit:` set to one of the valid pattern-level exit values
(`full-run`, `re-evaluation`, or `abandonment-forced`). The chain
has already finalized; this re-entry is against a settled state.

**Action.** Surface an exit-value-specific re-entry prompt:

- `exit: full-run` — offer the row-5 "Re-evaluate / Revise /
  Bail" prompt. The chain's terminal artifact is the STRATEGY, now
  Accepted or Active (or about to be on the next commit). The
  author is implicitly re-entering against the STRATEGY's status-
  aware re-entry surface.
- `exit: re-evaluation` — offer "Revise / Bail" (a second
  re-evaluation would write a duplicate Decision Record; Revise
  starts a fresh chain that may produce a superseding STRATEGY).
- `exit: abandonment-forced` — offer "start fresh" (the chain
  abandoned without producing a terminal STRATEGY; the
  schema-compliant partial artifact is the durable trace of the
  prior run).

The Re-evaluate routing forward-references the exit-path
orchestration owned by a companion outline (the re-evaluation
Decision Record body authoring also belongs downstream); the
abandonment-forced artifact authoring forward-references the
exit-artifact authoring outline.

## Row 3 — State File Fresh (< 7 days)

**Match condition.** The state file exists, is well-formed, has
`exit:` UNSET, and `last_updated` is strictly less than 7 days
old relative to the current wall-clock time.

**Action.** Resume at the recorded `phase_pointer` without any
intervention prompt. The author sees `/charter` continue where it
left off; no Force-materialize prompt, no Discard prompt, no
acknowledgment dialog. The chain advances.

## Row 4 — State File Stale (≥ 7 days)

**Match condition.** The state file exists, is well-formed, has
`exit:` UNSET, and `last_updated` is 7 days old or more relative
to the current wall-clock time.

**Action.** Surface a **three-option prompt** to the author:

- **Resume** — continue at the recorded `phase_pointer`. The
  ladder advances as in row 3.
- **Force-materialize** — route into the abandonment-forced exit
  path. The chain materializes a schema-compliant partial artifact
  for whatever phase `/charter` reached, then terminates with
  `exit: abandonment-forced`. The routing is owned by the
  companion outline implementing the exit-path orchestration; the
  partial-artifact authoring is owned by the exit-artifact
  authoring outline.
- **Discard** — remove the state file and restart the chain at
  Phase 0.

The prompt fires on **every invocation** while the state remains
stale (i.e., until the author chooses one option or the state
advances). Repeated invocations against a stale state file
repeatedly surface the prompt — the system does not silently
absorb staleness.

The 7-day boundary is the **7-day stale-session threshold**. It is
fixed in v1 and not configurable; the value is a pattern-level
parametric concept (see
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-resume-ladder-template.md`,
Stale-Session Threshold section). The boundary fires at `≥ 7d`
(inclusive); 7 days exactly is stale, six-days-and-23-hours is
fresh.

## Row 5 — Accepted/Active STRATEGY Exists

**Match condition.** No state file exists at
`wip/charter_<topic>_state.md`, AND the STRATEGY at
`docs/strategies/STRATEGY-<topic>.md` has frontmatter `status:` of
`Accepted` or `Active`. The author has invoked `/charter <topic>`
against a settled upstream.

**Action.** Surface a three-option entry prompt with the literal
substrings "Re-evaluate", "Revise", and "Bail" (case-insensitive
match). The three options are co-equal — there is no recommended
default.

- **Re-evaluate** — `/charter` writes a re-evaluation Decision
  Record stating the bet still holds; the existing STRATEGY stays
  Accepted/Active. The child `/strategy` is NOT invoked; the
  Decision Record is authored by `/charter` directly. The routing
  forward-references the exit-path orchestration outline; the
  Decision Record body authoring forward-references the
  exit-artifact authoring outline.
- **Revise** — `/charter` starts a fresh chain that may produce a
  superseding STRATEGY. The chain runs `/strategy` (with status-
  aware re-entry suppressed; see below) and proceeds through Phase
  2 chain orchestration normally.
- **Bail** — `/charter` exits without invoking any child or
  writing any artifact. No-op for the topic; the existing STRATEGY
  is unaffected.

The vocabulary is load-bearing. PRD US-2 explicitly rejects the
default phrasing "Do you want to revise?" — that default biases
every chain toward STRATEGY revision and destroys the discipline-
vs-artifact decoupling that motivates `/charter`. The three
options are presented as co-equal; the author chooses based on
the chain's intent, not on a leading question.

This row's prompt vocabulary is `/charter`'s. The child's own
status-aware re-entry vocabulary MUST NOT appear here — see
**Status-Aware Re-Entry Suppression** below for the contract that
prevents the child's prompts from hijacking `/charter`'s flow.

## Row 6 — Draft STRATEGY Exists

**Match condition.** No state file exists at
`wip/charter_<topic>_state.md`, AND the STRATEGY at
`docs/strategies/STRATEGY-<topic>.md` has frontmatter `status:` of
`Draft`. The author has invoked `/charter <topic>` against a draft
that did not finish through to acceptance.

**Action.** Surface a two-option prompt offering the author to
continue from the existing draft or to start a fresh chain that
supersedes it. The two options are:

- **Continue draft** — resume into `/strategy`'s phase ladder
  against the existing Draft STRATEGY. `/strategy`'s own resume
  logic detects the draft and routes to the appropriate
  continuation phase.
- **Start fresh** — discard the Draft STRATEGY (the discard is
  recorded as a commit) and begin a new chain from Phase 0.

The two-option shape follows the pattern-level meta-ladder body
slot for partial-child-run plus draft-upstream cases. The
specific prompt wording uses the row's two options as named above
(neither is the literal phrase that row 5 explicitly excludes —
see the negative-vocabulary rule documented under row 5).

## Row 7 — `/strategy` Partial Run

**Match condition.** No state file exists at
`wip/charter_<topic>_state.md`, no STRATEGY exists at the
published path, AND `wip/strategy_<topic>_discover.md` exists on
disk.

**Action.** Resume into `/strategy`, passing the topic slug and
letting `/strategy`'s own resume logic detect the partial-run
artifact and continue from the appropriate phase.

**Known `/strategy` asymmetry — the filename `_discover.md`, NOT
`_scope.md`.** `/charter` reads `wip/strategy_<topic>_discover.md`
because that is the filename `/strategy`'s phase files actually
write when the discover phase runs. `/strategy`'s SKILL.md
documents `_scope.md` as the Phase 1 scoping artifact name, but
the phase files write `_discover.md`. The ladder accommodates the
asymmetry by reading the artifact that exists on disk, not the
artifact the documentation claims exists. Fixing `/strategy`'s
documentation versus its phase-file behavior is out of scope; the
PRD explicitly accommodates the asymmetry here.

## Row 8 — `/vision` Partial Run

**Match condition.** No state file exists at
`wip/charter_<topic>_state.md`, no STRATEGY exists at the
published path, no `/strategy` partial-run artifact exists, AND
`wip/vision_<topic>_scope.md` exists on disk.

**Action.** Resume into `/vision`, passing the topic slug and
letting `/vision`'s own resume logic detect the partial-run
artifact and continue.

## Row 9 — On Topic-Related Branch

**Match condition.** No state file exists, no upstream STRATEGY
exists, no child partial-run artifacts exist, AND the current git
branch name is related to the topic (typically the branch name
contains the topic slug, or a workflow-naming convention links the
branch to the topic).

**Action.** Resume at `/charter`'s Phase 1 (Discovery). The branch
context provides enough signal to skip Phase 0 setup; the parent
uses Phase 1 discovery prompts to ground the chain shape.

## Row 10 — On Main or Unrelated Branch

**Match condition.** No state file, no upstream STRATEGY, no child
partial-run artifacts, and the current branch is not topic-related
(main, an unrelated feature branch, or a detached HEAD).

**Action.** Start fresh at Phase 0 — the entry-point guard rail
that validates the topic slug, creates the state file, and routes
to Phase 1.

## Drift Detection (Child-Snapshot Dual Check)

`/charter`'s state file records a `child_snapshots` block with one
entry per child in `planned_chain`. Each entry has three fields:

- `path` — the absolute or repo-relative path to the child's
  durable doc.
- `status` — the frontmatter `status:` value of the child doc at
  the snapshot moment (the last time `/charter` exited or advanced
  past the child).
- `content_hash` — the git blob hash of the child doc body at
  the snapshot moment, computed via `git hash-object` (or
  equivalent). **Computation is READ-ONLY** — `git hash-object`
  computes the hash from the file's contents on disk; it does NOT
  write to git history, does NOT modify the child doc, and does NOT
  modify any path outside `/charter`'s own state file.

### The Dual Check

On every resume, the ladder compares both fields against live
values before consulting the next ladder row:

1. Read the child doc's current frontmatter `status:` at the
   recorded `path`.
2. Compute the child doc's current `git hash-object` against the
   recorded `path`.
3. **Drift fires when EITHER differs from the snapshot.**

The dual check is the load-bearing part. A single-field check
against `status:` alone would miss the case where a child doc's
frontmatter stays at the same status (e.g., `Draft → Draft`) but
the body was edited by hand outside the chain — the R13 manual-
fallback case. A single-field check against `content_hash:` alone
would miss the case where the child doc was force-transitioned by
a lifecycle verb (e.g., `Draft → Accepted` via
`/strategy <strategy-path> accept`) while the body stayed
identical. The dual check catches both: either field flipping
fires drift.

### Drift Surface — Three-Option Staleness Prompt

When drift fires for any child in `planned_chain`, the ladder
surfaces a **three-option staleness prompt**. The author chooses
the path:

- **Re-run** — re-invoke the affected child. The chain treats the
  upstream change as material and reproduces the downstream from
  the changed upstream.
- **Accept** — record acknowledgment in `child_snapshots` (update
  the snapshot to match the live values) and proceed. The author
  asserts the downstream remains valid despite the upstream
  change.
- **Proceed without** — skip the affected child for this chain.
  The chain advances without re-invoking; the child's drift is
  acknowledged but not acted on for the current run.

The three-option staleness prompt is `/charter`'s response to
drift; the user-facing prose that explains "drift detection fires
when manual edits occur out-of-chain" lives in section 1.2 of
`skills/charter/references/phases/phase-1-discovery.md` (the
manual-fallback non-interference rule and the forward-reference
to this implementation).

The contract framing for both halves — the R14-widened isolation
rule that the dual check sits inside, and the per-parent surface
binding for doc-emitting children (frontmatter `status:` + git
blob hash) — is documented in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-child-inspection.md`.

## Status-Aware Re-Entry Suppression

When `/charter` invokes a child whose durable doc is already
Accepted, the next prompt the author sees MUST be from
`/charter`'s prompt vocabulary, NOT the child's own status-aware
re-entry vocabulary. The child's prompts MUST NOT hijack the
parent's flow — the parent decides the re-entry shape, and the
child accepts the parent's decision without surfacing a competing
prompt.

Two cases bind the contract:

- **Re-evaluation exit chosen** (row 5 "Re-evaluate"): `/charter`
  writes the re-evaluation Decision Record WITHOUT invoking the
  child at all. The child's status-aware re-entry prompt never
  fires because the child is never invoked; `/charter` synthesizes
  the Decision Record from its own context.
- **Fresh chain chosen** (row 5 "Revise" or row 6 start-fresh):
  `/charter` invokes the child with a suppression signal. The
  signal mechanism is a parent-orchestration flag passed alongside
  the topic slug — concretely, `/charter` invokes the child with
  the topic plus a `--parent-orchestrated` flag (or an equivalent
  environment marker the child's SKILL.md recognizes). When the
  child sees the flag, it suppresses its own status-aware re-entry
  prompt and treats the run as a fresh invocation from the
  parent's perspective, even if the published artifact would
  normally trigger the child's own resume prompt.

When Revise (or the fresh-chain alternative) is selected,
`/charter`'s child-invocation logic passes the
`--parent-orchestrated` flag (or an equivalent environment marker
the child's SKILL.md recognizes) alongside the topic slug. Future
child-side adoption — when `/strategy`, `/vision`, and `/roadmap`
SKILL.md updates land — binds to the same flag name; this file is
the canonical contract surface for the flag's meaning. The
parent-orchestration contract is documented here so the child-
side and parent-side bind to the same name once the child-side
migration ships.

## R14 Child-Internals Isolation

`/charter`'s decision logic depends ONLY on the three sources
below. These three sources are exhaustive — the ladder consults no
other child internals to make resume decisions.

**Permitted sources** (the only three):

1. The child doc frontmatter `status:` value, read from the
   published path (`docs/strategies/STRATEGY-<topic>.md`,
   `docs/visions/VISION-<topic>.md`,
   `docs/roadmaps/ROADMAP-<topic>.md`).
2. The child doc git blob hash, computed via `git hash-object`
   against the same published path (READ-ONLY, no writes).
3. `/charter`'s own state file at
   `wip/charter_<topic>_state.md`.

**Prohibited sources** (the ladder MUST NEVER read these):

- **Child internal phase pointers** — `/strategy`, `/vision`,
  `/roadmap`, and any other child each have their own state file
  or phase-pointer mechanism for their own resume logic. `/charter`
  does NOT read these.
- **Child research artifacts** — `wip/research/<child>_<topic>_
  phase<N>_*.md` files and any other child-internal research
  notes. These are the child's scratch surface; `/charter` does
  not consult them.
- **Any other child `wip/` intermediate** beyond the partial-run
  detection patterns explicitly listed in rows 7-8 of the ladder
  (`wip/strategy_<topic>_discover.md` and
  `wip/vision_<topic>_scope.md`). The two filenames in rows 7-8
  are the minimum surface needed for partial-run detection and are
  the only `/charter`-side knowledge of child `wip/` paths.
- **Any other child-private state** — log files, comment threads,
  CI output, any other internal-only surface the child might
  produce.

The R14-widened isolation rule is documented at the pattern level
in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-child-inspection.md`
(see the R14-widened rule section and the per-parent surface
table). `/charter`'s binding is the doc-emitting-children row of
the surface table (frontmatter `status:` + git blob hash); the
two `wip/` partial-run filenames in rows 7-8 are the documented
exception for partial-run detection.

R14 isolation is enforced as a manual-review acceptance criterion:
the reviewer verifies by code-path inspection that the ladder's
implementation reads only the three permitted sources and never
the prohibited ones.

## Manual-Fallback Rejection Is Not Retroactive

`/strategy`'s Phase 5 Reject path is a `/strategy`-internal
mechanism that discards a Draft STRATEGY when the author rejects
it at finalization. When `/strategy` Phase 5 Reject fires OUTSIDE
a `/charter` chain (the author invoked `/strategy` directly and
the strategy was rejected), `/charter` MUST NOT retroactively
write a rejection Decision Record on a later `/charter` resume
against the same topic.

The US-3a manual-fallback rejection contract is: the rejection
sub-shape of the Decision Record is `/charter`-orchestrated only.
Manual-fallback rejection leaves only the discard commit as the
durable trace, by design. The ladder's row 1 (malformed state) and
row 10 (no state file) paths apply normally — nothing in the
resume path attempts to reconstruct a Decision Record from
external evidence (the discard commit SHA, the absence of a
STRATEGY at the published path, or any other inferred signal).

This is a non-retroactivity rule: `/charter` does not synthesize
Decision Records from inferred signals. Doing so would fabricate
an audit trail for an action the author did NOT take through
`/charter`. The discard commit stands as the durable record on
its own.

## Out-of-Chain Hand-Edit Detection

Out-of-chain hand edits to any child doc — the author opens
`docs/strategies/STRATEGY-<topic>.md` and rewrites the Building
Blocks section by hand between two `/charter` resumes, or the
author runs `/strategy <strategy-path> accept` outside `/charter`
to transition a Draft to Accepted — trigger drift detection on
the next `/charter` resume per the dual-check rule documented in
Drift Detection above.

The user-facing prose that names this behavior to the author
("when you edit a downstream child by hand, `/charter` will flag
the drift on the next resume") lives in section 1.2 of
`skills/charter/references/phases/phase-1-discovery.md` (the
manual-fallback non-interference rule plus the forward-reference
to the drift detection here). This implementation file is the
home of the detection mechanism; the discovery prelude is the
home of the user-facing framing.

## Security Considerations

The resume ladder runs on every `/charter` invocation against an
existing topic and reads from durable evidence surfaces in the
worktree. The security properties below bound the ladder's
permitted behavior.

### Read-Only Hash Computation

The `git hash-object` invocations used to compute child-doc
content fingerprints are **read-only**. `git hash-object` (without
`-w`) reads the file from disk and prints the hash to stdout; it
does NOT write to git history, does NOT modify the child doc, and
does NOT modify any path outside `/charter`'s own state file. The
ladder MUST NOT use `git hash-object -w` (which would create a
blob object in `.git/objects/`) — the plain read-only form is
sufficient for drift detection.

### Bounded Read Surface

The ladder reads only the documented sources (the three permitted
sources in the R14 Child-Internals Isolation section above, plus
the two child `wip/` artifact filenames explicitly named in rows
7-8). No other child internals are consulted. The bounded read
surface is the R14-widened isolation rule's defense against
contract drift — adding a new "permitted source" without revising
this prose is itself a violation.

### Malformed State Fails Closed

Row 1's malformed-state hard error fails closed: the ladder
surfaces the error and refuses to advance until the author
chooses Discard. The fail-closed posture prevents corrupt state
from silently propagating into a fresh chain, which would mask
the upstream chain corruption and risk wedging the topic across
invocations. Silently falling through to row 10 (Phase 0) on
malformed state is explicitly forbidden.

### Status-Aware Re-Entry Suppression Is a Security Property

Status-aware re-entry suppression prevents the child's prompt
vocabulary from hijacking `/charter`'s flow. Without the
suppression contract, an author re-entering against an Accepted
STRATEGY would see `/strategy`'s own resume prompts (e.g.,
"continue from the existing artifact" or similar status-aware
phrasing) instead of `/charter`'s "Re-evaluate / Revise / Bail"
prompt. The ambiguity would let the child's defaults silently
override the parent's intended re-entry shape. The suppression
flag eliminates this ambiguity at the contract layer.

### No Third-Party Dependencies

The ladder uses only filesystem reads and `git hash-object` (a
read-only invocation of the git binary already required by the
shirabe workspace). No third-party libraries, no external API
calls, no network surface.

### Metadata-Only Child-Snapshot Storage

The `child_snapshots` block in `wip/charter_<topic>_state.md`
stores `path + status + content_hash` per child — METADATA only.
The block MUST NOT copy child-doc body content into the state
file. Feature branches with the state file on disk are visible
during PR review; copying body content into the state file would
leak pre-publication wording across review surfaces. The hash
serves as the body fingerprint without exposing the body itself.

### Bounded Concurrent-Edit Surface via the 7-Day Threshold

The 7-day stale-session threshold bounds the surface area for
any concurrent edits. State older than 7 days requires explicit
author intent (Resume / Force-materialize / Discard at row 4)
before the chain advances. The threshold prevents indefinite
resume on long-abandoned state, which would otherwise let
concurrent edits accumulate silently against the state file's
recorded snapshots.

### Non-Retroactive Decision Records

The US-3a manual-fallback rejection contract (above) is also a
security property: `/charter` does not synthesize Decision
Records from external evidence. Doing so would fabricate an
audit trail for an action the author did NOT take through
`/charter`, which would mislead future readers reviewing the
chain's durable evidence. The discard commit stands as the
durable record on its own; `/charter` does not retroactively
narrate it.
