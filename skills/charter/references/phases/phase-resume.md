# Phase: Resume Ladder

The resume ladder is `/charter`'s entry-point decision logic for any
invocation that finds prior state on the topic. It runs on every
invocation against an existing topic: a `work/state.md` key in
`charter-<topic>`, an upstream STRATEGY at the published path, a
child's partial-run session, or just a branch related to the topic —
any of these means the topic is not fresh, and the ladder decides
where re-entry lands.

The ladder is **first-match-wins, top-to-bottom**: it tests row 1's
condition first, and the first row whose condition matches takes the
row's action; the remaining rows are not consulted. When no row
matches, control falls through to row 10's start-fresh path.

Rows 1-4 and 9-10 inherit the universal meta-ladder from the
pattern-level template at
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-resume-ladder-template.md`.
Rows 5-8.5 are `/charter`'s parent-specific body slots: rows 5-6 fill
the status-aware re-entry slot against an upstream STRATEGY; rows 7-8
fill the partial-child-run slots against `/strategy`'s and `/vision`'s
live sessions (`skill-session.sh has-work`); row 8.5 fills the
feeder-doc slot against an `/explore` handoff.

The contract framing for drift detection plus the R14-widened
child-internals isolation rule is cited from
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-child-inspection.md`.

## Table of Contents

- [The 10-Row Ladder](#the-10-row-ladder)
- [Row 1 — Malformed State](#row-1--malformed-state)
- [Row 2 — Exit Field Already Set](#row-2--exit-field-already-set)
- [Row 3 — State Fresh (< 7 days)](#row-3--state-fresh--7-days)
- [Row 4 — State Stale (≥ 7 days)](#row-4--state-stale--7-days)
- [Row 5 — Accepted/Active STRATEGY Exists](#row-5--acceptedactive-strategy-exists)
- [Row 6 — Draft STRATEGY Exists](#row-6--draft-strategy-exists)
- [Row 7 — `/strategy` Partial Run](#row-7--strategy-partial-run)
- [Row 8 — `/vision` Partial Run](#row-8--vision-partial-run)
- [Row 8.5 — `/explore` Handoff Detected](#row-85--explore-handoff-detected)
- [Row 9 — On Topic-Related Branch](#row-9--on-topic-related-branch)
- [Row 10 — On Main or Unrelated Branch](#row-10--on-main-or-unrelated-branch)
- [Recorded-Upstream Re-Validation](#recorded-upstream-re-validation)
- [Drift Detection (Child-Snapshot Dual Check)](#drift-detection-child-snapshot-dual-check)
- [Status-Aware Re-Entry Suppression](#status-aware-re-entry-suppression)
- [R14 Child-Internals Isolation](#r14-child-internals-isolation)
- [Manual-Fallback Rejection Is Not Retroactive](#manual-fallback-rejection-is-not-retroactive)
- [Out-of-Chain Hand-Edit Detection](#out-of-chain-hand-edit-detection)
- [Security Considerations](#security-considerations)

## The 10-Row Ladder

```
1.   work/state.md malformed                              -> Hard error naming malformation + offer Discard
2.   work/state.md has exit field set                     -> Exit-value-specific re-entry prompt
3.   work/state.md exists, last_updated < 7d              -> Resume at recorded phase_pointer (no prompt)
4.   work/state.md exists, last_updated >= 7d             -> Resume / Force-materialize / Discard prompt
5.   STRATEGY-<topic>.md Accepted/Active                  -> Re-evaluate / Revise / Bail prompt
6.   STRATEGY-<topic>.md Draft                            -> continue-or-start-fresh prompt
7.   skill-session.sh has-work strategy <topic> exits 0   -> Resume into /strategy
8.   skill-session.sh has-work vision <topic> exits 0     -> Resume into /vision
8.5  key handoff/charter.md in explore-<topic> exists     -> Phase 0 setup, then Phase 1 with the handoff pre-loaded
9.   On branch related to topic                           -> Resume at Phase 1
10.  On main or unrelated branch                          -> Start at Phase 0
```

Each row is documented below with its match condition and the
specific action `/charter` takes when the row fires.

**Why row 8.5 carries a fractional number.** The number is an
ordering position and nothing else: row 8.5 is evaluated after row
8 and before row 9, and it is an ordinary row in every other
respect. It is numbered fractionally because rows 9 and 10 are the
shared meta-ladder tail that `/scope` uses too, and because both
are cited by ordinal in this file, in `skills/charter/SKILL.md`,
and in the eval suite. Renumbering them to make room would disturb
`/charter` and `/scope` alike and falsify every one of those
citations — the same constraint row 6 states as its reason for
putting the mid-roadmap disambiguation inside an existing row. The
pattern-level license for a body slot to expand this way, and for
the tail to be identified by role rather than by ordinal, is in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-resume-ladder-template.md`
(Body-Slot Expansion).

## Row 1 — Malformed State

**Match condition.** Key `work/state.md` exists in session
`charter-<topic>` but its content cannot
be parsed as YAML, is missing required fields for the recorded
`phase_pointer`, or has an inconsistent combination of `exit:` and
gated fields (e.g., `exit: re-evaluation` with no
`decision_record_sub_shape:` set; `decision_record_sub_shape:` set
without `exit: re-evaluation`; any conditional-field present-when-
ungated case per the conditional-field gating discipline in
`skills/charter/references/phases/phase-state-management.md`).

**Action.** Surface a **hard error** that names the specific
malformation (not "the state is malformed" — name what is
wrong: "unparseable YAML at line N"; "missing required field
`phase_pointer`"; "`exit: re-evaluation` requires
`decision_record_sub_shape:` but it is unset"). Then offer
**Discard** as the recovery path. Discard removes key `work/state.md`
from `charter-<topic>` (`koto context remove`) and allows the author
to restart the chain at Phase 0.

**The ladder MUST NOT silently fall through to row 10 (Phase 0
start) when row 1 fires.** Malformed state is a contract violation
surface, not a missing-state surface — silently starting fresh
would hide upstream chain corruption and risk wedging the topic
across invocations. The author confirms Discard explicitly; row 1
is terminal.

## Row 2 — Exit Field Already Set

**Match condition.** `work/state.md` exists, is well-formed, and has
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

## Row 3 — State Fresh (< 7 days)

**Match condition.** `work/state.md` exists, is well-formed, has
`exit:` UNSET, and `last_updated` is strictly less than 7 days
old relative to the current wall-clock time.

**Action.** Resume at the recorded `phase_pointer` without any
intervention prompt. The author sees `/charter` continue where it
left off; no Force-materialize prompt, no Discard prompt, no
acknowledgment dialog. The chain advances.

## Row 4 — State Stale (≥ 7 days)

**Match condition.** `work/state.md` exists, is well-formed, has
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
- **Discard** — remove key `work/state.md` and restart the chain at
  Phase 0.

The prompt fires on **every invocation** while the state remains
stale (i.e., until the author chooses one option or the state
advances). Repeated invocations against a stale `work/state.md`
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

**Match condition.** No `work/state.md` key exists in
`charter-<topic>`, AND the STRATEGY at
`docs/strategies/STRATEGY-<topic>.md` has frontmatter `status:` of
`Accepted` or `Active`. The author has invoked `/charter <topic>`
against a settled upstream.

**Action.** Surface a three-option entry prompt that CLOSES with the
contiguous literal option line `Re-evaluate / Revise / Bail`
(case-insensitive, separator ` / ` exactly). The bullets below are
explanatory gloss, not the option surface — the closing line is what
offers the options, and it is what the eval greps.

The three options are co-equal — there is no recommended default, and
the contiguous line is how that co-equality is made checkable. A
single option line cannot rank or bury its options; prose can. See the
Gate Vocabulary companion note on prompt vocabulary in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` for the rule
that scopes contiguity to co-equal, default-free prompts.

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

**Match condition.** No `work/state.md` key exists in
`charter-<topic>`, AND the STRATEGY at
`docs/strategies/STRATEGY-<topic>.md` has frontmatter `status:` of
`Draft`. The author has invoked `/charter <topic>` against a draft
that did not finish through to acceptance.

**Action.** Surface a two-option prompt offering the author to
continue from the existing draft or to start a fresh chain that
supersedes it. The two options are:

- **Continue draft** — resume into the phase ladder of whichever
  child the chain was inside when it stopped (see the mid-roadmap
  disambiguation below). The child's own resume logic detects its
  draft and routes to the appropriate continuation phase.
- **Start fresh** — discard the Draft STRATEGY (the discard is
  recorded as a commit) and begin a new chain from Phase 0.

The two-option shape follows the pattern-level meta-ladder body
slot for partial-child-run plus draft-upstream cases. The
specific prompt wording uses the row's two options as named above
(neither is the literal phrase that row 5 explicitly excludes —
see the negative-vocabulary rule documented under row 5).

**Mid-roadmap disambiguation.** A Draft STRATEGY on disk no longer
implies `/strategy` is the child to resume into, because `/roadmap`
fires on every full-run chain (R7) and can be interrupted with the
STRATEGY already written.

This row is the only place the ambiguity bites. A `/charter` chain
interrupted mid-`/roadmap` normally still has its `work/state.md`, so
rows 3-4 match first and resume at the recorded `phase_pointer`
(`2`, chain orchestration), with `chain_ran` already naming
`/strategy` as complete — that is enough to route to `/roadmap`
without inspecting the filesystem. Row 6 is the case where no state
key survives, so there is no `phase_pointer` and no `chain_ran` to
consult and the on-disk artifacts are the only evidence.
"Continue draft" resolves the target this way:

1. If no ROADMAP exists at `docs/roadmaps/ROADMAP-<topic>.md` AND
   either `has-work roadmap <topic>` exits 0 or key
   `chain/roadmap-scope` exists in `charter-<topic>` (`koto context
   exists charter-<topic> chain/roadmap-scope`), the chain got at
   least as far as `/charter`'s roadmap-scope write and `/roadmap`
   was mid-run. The no-ROADMAP guard covers both clauses: a
   `roadmap-<topic>` session stays live with its keys until the
   parent's `close-children`, so after a clean `/roadmap` return
   the published ROADMAP, not the session, is what says the hop is
   done. Resume into `/roadmap`, passing
   `--upstream docs/strategies/STRATEGY-<topic>.md`; `/roadmap`'s
   own resume logic reads its keys, and the dispatch key it
   matches points it back at `chain/roadmap-scope`.
2. Otherwise, resume into `/strategy`'s phase ladder against the
   existing Draft STRATEGY, as before.

Resuming into `/strategy` in case 1 would re-run a child that
already finished, so the handoff-artifact check runs first. The
check lives in this row rather than in a new ladder row because
rows 7-8 both require *no* STRATEGY at the published path and so
can never match, rows 3-4 already cover the state-key case through
`phase_pointer`, and rows 9-10 are pattern-level meta-ladder rows
that renumbering would disturb for `/scope` as well as `/charter`.

## Row 7 — `/strategy` Partial Run

**Match condition.** No `work/state.md` key exists in
`charter-<topic>`, no STRATEGY exists at the
published path, AND
`"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" has-work
strategy <topic>` exits 0: `strategy-<topic>` is live, belongs to
this branch, and holds a key under `work/`
(`${CLAUDE_PLUGIN_ROOT}/references/skill-session-convention.md`).

**Action.** Resume into `/strategy`, passing the topic slug and
letting `/strategy`'s own resume logic read its keys and continue
from the appropriate phase.

## Row 8 — `/vision` Partial Run

**Match condition.** No `work/state.md` key exists in
`charter-<topic>`, no STRATEGY exists at the
published path, row 7 did not match, AND `has-work vision <topic>`
exits 0.

**Why a session key can carry the row a staging file could not.**
Only `/vision` writes `work/` keys in its own session, so a match
always means `/vision` itself ran. A feeder document — a
pre-supplied Phase 1 output that lets the child skip Phase 1 —
lands on disk, not in the child's session, so no feeder can
imitate a mid-flight child the way `/vision`'s on-disk scoping
file once imitated an interrupted `/vision` run. The old rows'
narrowed filenames (the decisions ledger for `/vision`, the
discover output for `/strategy`) were defense in depth against
exactly that collision; the session check removes the surface they
defended, and the `_discover.md`-versus-`_scope.md` naming
asymmetry the old row 7 had to accommodate is gone with the files.

**A finished session is not a partial.** `has-work` matches only a
live session on this branch, so a child whose direct run finished
and closed its session falls through to rows 9 and 10. A session
koto cannot report is a cannot-tell, surfaced to the author rather
than read either way; koto absent from `PATH` means no child
session can exist, so rows 7 and 8 match nothing and the ladder
falls through.

**Action.** Resume into `/vision`, passing the topic slug and
letting `/vision`'s own resume logic read its keys and continue.

## Row 8.5 — `/explore` Handoff Detected

**Match condition.** No `work/state.md` key exists in
`charter-<topic>`, no STRATEGY exists at the published
path, no child partial-run session matched rows 7-8, AND key
`handoff/charter.md` exists in session `explore-<topic>`. Beyond the
rows above not matching, that one key is the whole condition: the
row reads no other key to decide whether it fires, and an absent
handoff (no `explore-<topic>` session, or one without the key) is no
row. It never fires on a key in another skill's area: the session
name is composed from the validated topic slug and the key name is
the constant `handoff/charter.md`, read by name, never discovered by
listing.

**Action.** Run Phase 0's setup obligations against the current
worktree — slug validation (step 0.3), `--upstream` validation when
the invocation supplied a value (step 0.4), and the `work/state.md`
key write (step 0.5) — then enter Phase 1 with the handoff pre-loaded
as discovery input. Repository visibility is detected in Phase 1.1 as
on any other run. Record `consumed_handoff: handoff/charter.md` in
`work/state.md` at the same write. Once the handoff is consumed,
remove key `handoff/charter.md` from `explore-<topic>` (`koto context
remove`), and close `explore-<topic>` when it holds nothing else. An
early exit before the consumption leaves the key in place for the
next run.

Phase 1 runs. The row never skips it and never resumes into a
child: a handoff is discovery material, not a resume point inside
the chain. The chain proposal is emitted and confirmed as always.

Two Phase 1 behaviors change, and the rest do not:

- **The thesis-shift question is still surfaced**, verbatim as
  Phase 1.4 requires, but as a confirmation rather than a fresh
  ask: the exploration concluded X; confirm or correct it. The
  author's response is what gets classified and recorded. A
  pre-supplied answer is never accepted as recorded state — a
  positive signal overrides the `/vision` auto-skip against an
  Accepted or Active VISION, so it is the one carried value that
  reaches a gate and the confirmation is mandatory rather than a
  formality. Under `--auto` the pre-supplied answer is taken and
  announced rather than applied silently.
- **The child-doc globs are unchanged.** They are filesystem reads
  and they run on every invocation, handoff or not.

`/charter` runs no shape-predicate walk, so the shape-signals block
`/scope`'s handoff carries has no analogue here and no reader in
this row.

**What the handoff carries.** Six sections shared with `/scope`'s
Slot 7, plus the parent-specific block: provenance (which
exploration wrote it, when); the theme statement; the scope
boundary; the decisions the exploration already settled; coverage
notes on what it did and did not examine; observations about
upstream artifacts it found; and — the parent-specific one — the
author's thesis-shift answer with the evidence behind it.

**What it does not carry, and what that means here.** The handoff
carries conversation, never filesystem state. It states no
artifact's existence, no frontmatter `status:`, no content hash, no
repo visibility, and no upstream validation result. Every one of
those is re-read on every run: the Phase 1 globs establish what is
on disk, Phase 1.1 reads CLAUDE.md's `## Repo Visibility:` header,
Phase 2 computes child snapshots itself, and a `--upstream` VISION
is validated from the invocation argument by step 0.4 rather than
from this file. A handoff that carries such a value anyway is
ignored on that value, not trusted and not treated as
malformation.

**A malformed handoff degrades to a cold start.** If the key's
content is truncated, unparseable, or missing the sections above,
`/charter` announces that it found a handoff it could not consume,
names the key, leaves it in place, and proceeds as though none
existed. There is no partial consumption: a half-read handoff would
pre-supply some discovery inputs and not others with no way for the
author to tell which. `consumed_handoff:` is not written on this
path, because nothing was consumed.

**When a higher row fires first.** A settled artifact on disk wins.
The handoff has nothing to say about it — being barred from
carrying existence, status, or hashes, it cannot be the more
current evidence — so a row 5-8 match takes its own action and row
8.5 is never reached. The handoff is not silently dropped: the row
that fires states that a router handoff exists at key
`handoff/charter.md` and was not consumed, and offers
its theme statement as context for the choice the row is asking the
author to make. The key is left in `explore-<topic>`, so a later
Revise that clears the way down the ladder reaches this row on its
own terms.

## Row 9 — On Topic-Related Branch

**Match condition.** No `work/state.md` key exists, no upstream
STRATEGY exists, no child partial-run session matches, no `/explore`
handoff key exists at `handoff/charter.md` in `explore-<topic>`, AND
the current git branch name is related to the topic (typically the
branch name contains the topic slug, or a workflow-naming convention
links the branch to the topic).

**Action.** Resume at `/charter`'s Phase 1 (Discovery). The branch
context provides enough signal to skip Phase 0 setup; the parent
uses Phase 1 discovery prompts to ground the chain shape.

**Why this does not collide with `/explore`'s topic branch.**
`/explore` Phase 0 creates a `docs/<topic>` branch, so an author
arriving from an exploration is usually standing on a branch this
row matches — and this row skips Phase 0 setup on what the author
experiences as a first invocation. It never fires on a handoff run:
row 8.5 sits above it and takes its own action, which runs Phase 0's
setup obligations before entering Phase 1. What this row is left
holding is the residual case — an exploration that routed here but
wrote no handoff, or one whose handoff was already consumed and
cleaned up. Resuming at Phase 1 on an existing topic branch is the
behavior the row was written for, so it stays as it is.

## Row 10 — On Main or Unrelated Branch

**Match condition.** No `work/state.md` key, no upstream STRATEGY, no
child partial-run session, no `/explore` handoff key, and the current
branch is not topic-related (main, an unrelated feature branch, or a
detached HEAD).

**Action.** Start fresh at Phase 0 — the entry-point guard rail
that validates the topic slug, writes the `work/state.md` key, and
routes to Phase 1.

## Recorded-Upstream Re-Validation

When `work/state.md` carries `consumed_upstream:`, the ladder
re-validates that value on EVERY re-entry, before any row's action
runs and before the path is interpolated into a child invocation.
The re-validation re-runs the whole step-0.4 battery from
`skills/charter/references/phases/phase-0-setup.md` — canonicalize
and bounds-check, `VISION-` basename, not under `wip/`, tracked by
git, and the public-repo-to-private-upstream visibility check —
against the worktree as it is NOW, not as it was when the value was
recorded. A file tracked last week can be deleted or moved this
week, and a repo's `## Repo Visibility:` header can change between
sessions.

**A recorded upstream that no longer resolves is surfaced, never
silently ignored.** Silently dropping it would hand `/strategy` a
chain with no upstream and produce a STRATEGY whose missing
`upstream:` field looks like a document that never had one; silently
keeping it would carry a dangling path into committed frontmatter.
The ladder surfaces what failed — the recorded path and which check
it now fails — and offers three options:

- **Re-supply** — stop and ask the author to re-invoke
  `/charter <topic> --upstream <path>` with a working path. The
  recorded value is cleared from state so the next invocation
  starts from the author's new one. This is the interactive
  default.
- **Continue without** — remove `consumed_upstream:` from
  `work/state.md` and resume with no upstream. The produced STRATEGY omits
  `upstream:`, which the run states plainly rather than leaving the
  author to notice later.
- **Bail** — route to the abandonment-forced exit path.

Under `--auto` the ladder takes **Continue without** and announces
it, because a blocking prompt has no place in a non-interactive
run. Announcing is the load-bearing half: the auto default drops a
link the author asked for, so the drop is reported in the run
output whether or not anyone is watching.

The visibility check deserves its own note. It can fail on a
resume that had passed at Phase 0 — the repo went public, or the
upstream moved into a private repo — and the outcome is the same as
Phase 0's: the field is removed rather than carried, and the chain
continues without it.

## Drift Detection (Child-Snapshot Dual Check)

`/charter`'s `work/state.md` records a `child_snapshots` block with
one entry per child in `planned_chain`. Each entry has three fields:

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
  modify anything outside `/charter`'s own `work/state.md` key.

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
  `/charter` invokes the child under the dispatch key. Immediately
  before the invocation it writes `chain/dispatch` into its own
  session with `skill-session.sh dispatch write charter <topic>
  <child> <revise|fresh-chain>` (`revise` for row 5, `fresh-chain`
  for row 6), which records `suppress_status_aware_prompt: true`.
  The child finds the key with `skill-session.sh dispatch read
  <child> <topic>`, suppresses its own status-aware re-entry
  prompt, and treats the run as a fresh invocation from the
  parent's perspective, even if the published artifact would
  normally trigger the child's own resume prompt. `/charter`
  removes the key with `dispatch clear charter <topic>` immediately
  after the child returns, whatever its outcome.

The signal adds nothing to the child's arguments: the child is
invoked with the topic slug alone (plus `--upstream` where Phase 2
says so), and no flag or environment marker carries the
suppression. The key's write, clear and read are specified in
Phase 2's dispatch key section and in
`${CLAUDE_PLUGIN_ROOT}/references/skill-session-convention.md`.

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
3. `/charter`'s own `work/state.md` key in session
   `charter-<topic>`.

Row 8.5 reads a fourth source, key `handoff/charter.md` in
`explore-<topic>`, and it is outside this rule rather than an
exception to it. The handoff is not a child internal: it is the
router's output addressed to `/charter`, is written by the router
rather than by any child of the chain, and carries conversation
rather than filesystem state. Reading it consults no chain child's
surface, so the three-source enumeration above stands as written.

**Prohibited sources** (the ladder MUST NEVER read these):

- **Child internal phase pointers** — `/strategy`, `/vision`,
  `/roadmap`, and any other child each have their own state surface
  or phase-pointer mechanism for their own resume logic. `/charter`
  does NOT read these.
- **Child research artifacts** — the `research/` keys in a child's
  session and any other child-internal research notes. These are
  the child's scratch surface; `/charter` does not consult them.
- **Any other child session key** beyond the partial-run detection
  in rows 7-8 of the ladder, which asks only `skill-session.sh
  has-work <child> <topic>` — a read-only liveness-and-work check
  that opens nothing and reads no key content. That check is the
  only `/charter`-side knowledge of a child's state surface.
- **Any other child-private state** — log files, comment threads,
  CI output, any other internal-only surface the child might
  produce.

The R14-widened isolation rule is documented at the pattern level
in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-child-inspection.md`
(see the R14-widened rule section and the per-parent surface
table). `/charter`'s binding is the doc-emitting-children row of
the surface table (frontmatter `status:` + git blob hash); the
read-only `has-work` session check in rows 7-8 is the documented
exception for partial-run detection, and it reads liveness and the
presence of a `work/` key, never key content.

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
row 10 (no state key) paths apply normally — nothing in the
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
does NOT modify anything outside `/charter`'s own `work/state.md`. The
ladder MUST NOT use `git hash-object -w` (which would create a
blob object in `.git/objects/`) — the plain read-only form is
sufficient for drift detection.

### Bounded Read Surface

The ladder reads only the documented sources (the three permitted
sources in the R14 Child-Internals Isolation section above, plus
the `has-work` session check rows 7-8 run against `/strategy` and
`/vision`, plus the `/explore` handoff at key
`handoff/charter.md` in `explore-<topic>` that row 8.5 reads, plus the
existence and git-tracked status of the path in
`consumed_upstream:` — metadata about that file, never its body).
No other child internals are consulted. The bounded read
surface is the R14-widened isolation rule's defense against
contract drift — adding a new "permitted source" without revising
this prose is itself a violation.

### Slug Re-Validation on Resume

A row that recovers the topic slug from a path on disk rather than
from `$ARGUMENTS` re-validates it against `^[a-z0-9-]+$` before the
slug reaches any emitted command or state-key write. This covers
the published-STRATEGY rows and the child partial-run rows: each
finds its slug by a filesystem match, so each carries the
path-traversal surface a maliciously-named file placed under `docs/`
would otherwise open. Row 8.5 carries no such surface the other way
around: the `explore-<topic>` session name and the constant key name
are composed from the already-validated slug, never read back from a
key or recovered from a filesystem match. An unparseable slug rejects the
resume entry, surfaces a diagnostic naming the offending path, and
routes to `/charter`'s bail handling; the ladder never proceeds on
an unvalidated slug. The pattern-level rule and its wording live in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-security.md` (Slug
Re-Validation on Resume section).

### Recorded-Upstream Re-Validation Is a Second Interpolation Site

The `consumed_upstream:` re-validation above is not a repeat of
Phase 0's check on the same value — it is a second place where an
author-supplied path enters the run, and it carries the same
discipline. The recorded value is canonicalized to an absolute
path, rejected if it resolves outside the working tree, and quoted
and passed after `--` in any command the ladder emits (`git
ls-files -- <path>`) and in the `/strategy` invocation it feeds. A
session key is data that an edit can change between sessions, so
the value read back is treated as untrusted input exactly as the
flag's original value was.

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
override the parent's intended re-entry shape. The dispatch key's
`suppress_status_aware_prompt` eliminates this ambiguity at the
contract layer.

### No Third-Party Dependencies

The ladder uses only filesystem reads, read-only koto session
reads (`koto context exists`, `koto context get`, `has-work` — koto
is already required by the shirabe workspace), and `git hash-object`
(a read-only invocation of the git binary). No third-party
libraries, no external API calls beyond koto's own storage, no
other network surface.

### Metadata-Only Child-Snapshot Storage

The `child_snapshots` block in `work/state.md` stores
`path + status + content_hash` per child — METADATA only.
The block MUST NOT copy child-doc body content into the state
key. Key content is readable by anything that can read the
session; copying body content into the state key would carry
pre-publication wording outside the doc's own review surface. The
hash serves as the body fingerprint without exposing the body
itself.

### Bounded Concurrent-Edit Surface via the 7-Day Threshold

The 7-day stale-session threshold bounds the surface area for
any concurrent edits. State older than 7 days requires explicit
author intent (Resume / Force-materialize / Discard at row 4)
before the chain advances. The threshold prevents indefinite
resume on long-abandoned state, which would otherwise let
concurrent edits accumulate silently against the state key's
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
