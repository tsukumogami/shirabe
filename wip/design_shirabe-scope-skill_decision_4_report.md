<!-- decision:start id="parent-skill-worktree-discipline-content" status="confirmed" -->
### Decision: Worktree-discipline reference content (`references/parent-skill-worktree-discipline.md`)

**Context**

PRD R21 requires `/scope` to run a worktree-staleness check before each
Phase 2 child invocation (equivalent to `git fetch && git status --branch
--short`) and, on detected upstream divergence, halt with a three-option
prompt: **rebase**, **proceed anyway**, or **bail**. AC28b requires the
discipline to land as a *top-level* reference at
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-worktree-discipline.md` so
both `/scope` (now) and `/charter` (back-edit) inherit it, with future
parents (`/work-on` migration, future tactical parents) also reading from
the same source. Per Questions Deferred Q4, R21/AC28/AC28b name only the
*trigger surface and observable*; the **detailed prose** -- rebase
mechanics, "proceed anyway" recording semantics, and the
chain-proposal-vs-Phase-2 invocation integration -- is design-team
territory.

Four surfaces have to be nailed down:

1. **Exact trigger condition.** R21 says "before each Phase 2 child
   invocation," not "every `/scope` invocation" and not "after each child
   completes." The reference has to spell out the fence-post: which clock
   tick fires the check, and which ones don't.
2. **The halt-vs-proceed decision flow.** Three options exist; each must
   route somewhere specific. Rebase has mechanical sub-steps; proceed
   anyway has recording semantics; bail routes per R8.
3. **State-file recording of "proceed anyway."** AC28b explicitly names
   "the state-file recording of 'proceed anyway' divergence" as a
   reference-surface requirement. The reference must specify the field
   name, its conditional-presence semantics under invariant I-5, and the
   shape of the recorded payload.
4. **The chain-proposal-vs-Phase-2 distinction.** `/scope`'s Phase 1 ends
   with a chain-proposal prompt (R7.5: Proceed / Adjust / Bail). The
   Phase 2 chain invokes children sequentially. The worktree-staleness
   check fires *inside Phase 2 before each child invocation* -- not at the
   chain proposal. The reference must say this directly so authors and
   future parents don't confuse the two prompts.

The reference also has to be parent-agnostic prose: `/scope` cites it
today, `/charter` cites it via the small back-edit PR, and `/work-on`
will cite it on the SE8 migration. The body therefore must NOT reference
`/scope`-specific phase numbers or `/scope`-specific exit shapes.

**Assumptions**

- The reference will be cited in `/scope`'s Phase 2 chain-orchestration
  reference file (`skills/scope/references/phases/phase-2-chain-orchestration.md`).
  If `/scope` later renames the phase, the citation surface is in the
  phase file, not in this top-level reference.
- `/charter`'s back-edit PR will add a row to its Reference Files table
  pointing at the same top-level reference. `/charter`'s `phase-2-chain-orchestration.md`
  picks up the trigger-condition citation in the same back-edit.
- `git fetch` is permitted at the workspace level (no network-restricted
  environments are in v1 scope). If a future deployment runs without
  network access, the trigger condition still applies -- the check
  produces a deterministic "unable to fetch" failure that routes through
  the same three-option prompt with rebase grayed out.
- Branch-coupling of state (the Known Limitation in PRD line 1483) is
  not in scope for this reference. The reference assumes the parent is
  resuming on the branch where the state file lives.

**Chosen: Substrate-agnostic top-level reference with four named
sections**

The reference file `references/parent-skill-worktree-discipline.md` has
the following structure. The body is parent-agnostic prose; per-parent
binding notes appear in a final "Binding Notes" section that names each
adopting parent (`/scope` in v1; `/charter` via back-edit; `/work-on`
flagged as future).

```markdown
# Parent-Skill Worktree Discipline

The parent-skill worktree-staleness check is a shared discipline every
parent skill SHALL run before invoking each chain child. The discipline
protects the parent's resume contract from a class of silent-divergence
failures: a child invocation operating on stale worktree state can
produce an artifact that conflicts with upstream work the parent has
not seen, and the conflict will not surface until the merge attempt
much later.

This document is the contract surface for the discipline -- when it
fires, what it does, what it records, where it integrates into a
parent's phase ordering. Per-parent binding details (which reference
file in each parent's skill cites it; which phase the citation lives
in) appear in the Binding Notes section.

## Trigger Condition

The check SHALL fire **before each child invocation in the parent's
chain-execution phase** (the phase where the parent dispatches children
sequentially per its chain plan). The check fires:

- Before the FIRST child of the chain (after chain-proposal acceptance,
  before the first dispatch).
- Before EVERY SUBSEQUENT child, between completion of child N and
  dispatch of child N+1.

The check SHALL NOT fire:

- During the parent's discovery phase (the phase that produces the
  chain proposal).
- During the chain-proposal prompt itself (the proposal is a
  conversational artifact; no child is yet dispatched).
- After a child completes and before the parent updates its state file
  (the post-completion bookkeeping is a parent-internal step, not a
  child invocation).
- During resume-ladder evaluation (resume reads state and routes; it
  does not dispatch).

The fence-post is **the moment immediately preceding the child
dispatch**, after the parent has resolved which child to invoke next
and before any child-side work starts. This placement bounds the check
to N firings per chain (where N is the number of children that actually
run) and avoids both over-fire (every parent operation) and under-fire
(only once at the chain entry).

The check is mechanically equivalent to:

```bash
git fetch <remote> <branch> && git status --branch --short
```

The parent reads the `## [branch...remote/branch]` header line from
`git status --branch --short`. The presence of an `[ahead N, behind M]`
or `[behind M]` annotation with `M >= 1` is the staleness signal.

## Decision Flow on Staleness

When the trigger fires and the worktree is NOT stale (the status line
shows no behind-count, or shows only an ahead-count), the parent
proceeds with the child invocation. No prompt, no state-file write.

When the worktree IS stale (behind-count >= 1), the parent SHALL halt
the chain and surface a three-option prompt to the author. The prompt
MUST identify itself as the **worktree-staleness prompt** (a stable
literal label) and MUST contain the three option labels: `rebase`,
`proceed anyway`, `bail` (case-insensitive, as literal substrings).

The three options route as follows:

### Option 1: rebase

The parent SHALL invoke the rebase sub-flow:

1. **Confirm clean working tree.** Run `git status --short` and verify
   no uncommitted changes exist outside the parent's expected `wip/`
   surface. If uncommitted non-wip changes are present, surface them to
   the author and route back to the three-option prompt with `rebase`
   no longer offered (only `proceed anyway` and `bail` remain).
2. **Fetch and rebase.** Run `git fetch <remote>` followed by `git
   rebase <remote>/<branch>` against the tracking branch.
3. **On rebase success**, re-run the staleness check (a second fetch is
   not required; the freshly-rebased local branch is now even with
   upstream). The check now passes; the parent proceeds with the
   originally-planned child dispatch.
4. **On rebase conflict**, the parent SHALL NOT attempt automatic
   conflict resolution. The parent halts and surfaces the conflict to
   the author with two options: `bail` (route per the parent's
   bail-handling rule), or `resume after manual resolution` (the
   author resolves conflicts off-band and re-invokes the parent; the
   resume ladder picks up where the chain halted).

The rebase sub-flow is the discipline's "make it safe" option: divergence
is resolved before the child runs, so the child operates on
non-stale state.

### Option 2: proceed anyway

The parent SHALL proceed with the child invocation WITHOUT rebasing,
BUT MUST record the divergence in the state file before dispatching.
The recording is load-bearing: it is the durable evidence that the
author accepted the staleness risk on this run, and it is what a future
audit reads to reconstruct "why did this chain run produce a
conflicting artifact?".

The state-file recording uses a conditional field named
`worktree_divergence_acknowledged`. The field is a YAML list (each
chain may accumulate multiple acknowledgements across child boundaries
if upstream advances repeatedly). Each entry has the shape:

```yaml
worktree_divergence_acknowledged:
  - before_child: <child-name>
    behind_count: <integer N from git status>
    upstream_sha: <full sha of remote/branch HEAD at check time>
    local_sha: <full sha of local HEAD at check time>
    acknowledged_at: <ISO-8601 timestamp>
```

The field is conditional under invariant I-5: it is ABSENT when no
`proceed anyway` has fired on the run (never `null`, never empty list).
The field is APPENDED to (not overwritten) on each subsequent `proceed
anyway` -- a chain may run four children and acknowledge divergence
before two of them; the list ends up with two entries in dispatch
order.

The field is parent-agnostic: every parent that runs the discipline
uses the same field name and the same entry shape. The extension
discipline in `parent-skill-state-schema.md` (rule 1: no shadowing,
rule 2: conditional under I-5) is satisfied -- the field is
parent-specific in the sense that not every parent runs the discipline
in v1, but the field NAME is reserved at the pattern level so two
parents adopting the discipline do not collide on differently-shaped
fields with the same name.

The post-recording dispatch proceeds normally. The child invocation
sees the same worktree state it would have seen without the
acknowledgement; the recording does not change child behavior, only
the audit trail.

### Option 3: bail

The parent SHALL route per its own bail-handling rule. For `/scope`,
this is R8: route to `abandonment-forced` if any wip state exists,
otherwise clean cancel. For `/charter` and future adopters, the
parent's bail-handling rule governs.

The discipline does NOT mandate a specific bail destination; it only
mandates that the bail option routes through the parent's existing bail
path. This keeps the discipline orthogonal to per-parent exit-shape
semantics.

## Default Option Wording

The three-option prompt's default option is `rebase`. The parent's
SKILL.md and phase reference SHALL surface the three options in the
literal ordering `rebase / proceed anyway / bail`, with `rebase`
identified as the default. This default-option ordering is part of the
discipline's contract surface, not a UX detail (matching the pattern's
treatment of default-option wording at status-aware re-entry prompts).

The default is `rebase` because it is the only option that resolves
the divergence without recording a risk acknowledgement; `proceed
anyway` and `bail` both leave a durable trace of the staleness
(acknowledgement or partial-artifact-with-abandonment marker
respectively). The parent picks the "make it clean" option first; the
author overrides explicitly if they have reason to.

## Chain-Proposal Integration (Not the Trigger)

The chain-proposal prompt (the prompt that lists the planned chain
shape and offers Proceed / Adjust / Bail) is NOT a trigger surface for
the worktree-staleness check. The two prompts are sequenced and
distinct:

1. **Chain-proposal prompt** fires at the end of the parent's discovery
   phase, BEFORE any child is dispatched. It establishes what the
   chain shape will be. It does NOT run `git fetch`.
2. **Worktree-staleness prompt** fires inside the chain-execution
   phase, IMMEDIATELY before each child dispatch. It establishes
   whether the worktree is fresh enough to dispatch that specific
   child. It runs `git fetch` every time.

The reason the check is NOT folded into the chain-proposal prompt: the
gap between "author accepts the chain shape" and "the last child of the
chain dispatches" can span minutes to hours for tactical chains (four
children, each with its own sub-conversation). Running the check once
at chain-proposal time would miss divergence that arrives during the
chain run. Running it before each child invocation bounds the
staleness window to "since the previous child completed," which is the
operationally relevant interval.

The chain-proposal prompt remains the canonical surface for
chain-shape decisions; the worktree-staleness prompt is the canonical
surface for chain-execution-time freshness decisions. The two are
non-overlapping by design.

## Resume Semantics

When the parent's resume ladder routes back into the chain-execution
phase mid-run (e.g., the chain was interrupted between children and a
later invocation resumes), the worktree-staleness check fires before
the next child dispatch as if the chain were continuing normally. A
`worktree_divergence_acknowledged` field from an earlier run-segment
remains in the state file (it is part of the durable audit trail) and
the next entry, if any, appends to the existing list.

A resume that arrives more than the stale-session threshold after the
last `acknowledged_at` is still subject to the parent's stale-session
ladder rule (parent-specific); the discipline does not override
stale-session semantics.

## Binding Notes

The following parents bind the discipline in v1:

- **`/scope`** (primary v1 adopter). Cites this reference from
  `skills/scope/references/phases/phase-2-chain-orchestration.md`. The
  trigger fires before each of `/brief`, `/prd`, `/design`, `/plan`
  dispatch (children that are skipped per chain shape do not trigger
  the check -- "before each child invocation" means before each child
  that actually runs).
- **`/charter`** (back-edit adopter). A separate small back-edit PR
  adds a row to `skills/charter/SKILL.md`'s Reference Files table
  pointing at this file and adds the citation to
  `skills/charter/references/phases/phase-2-chain-orchestration.md`.
  The trigger fires before each of `/vision`, `/strategy`, `/roadmap`
  dispatch.
- **`/work-on`** (future, flagged). SE8's parent-skill-pattern
  migration of `/work-on` will adopt this reference at migration time;
  the trigger condition specializes to "before each implementation
  task dispatch."
```

**Rationale**

The four-section structure (Trigger Condition / Decision Flow / Chain-
Proposal Integration / Resume Semantics) maps 1:1 to the four surfaces
the deferred question names. Each section is parent-agnostic prose with
a single Binding Notes section at the end that lists per-parent
specializations, which mirrors how `parent-skill-pattern.md` itself is
structured (substrate-agnostic body + per-parent binding notes for
`/charter`).

The `worktree_divergence_acknowledged` field design satisfies three
constraints simultaneously:

1. **Invariant I-5 conditional-field semantics** -- absent when no
   acknowledgement has fired, never null or empty list.
2. **Audit-trail completeness** -- captures both SHAs (local and
   upstream at acknowledgement time), the child being dispatched, and
   the timestamp, so a future reader can reconstruct exactly what was
   acknowledged when.
3. **Multi-acknowledgement durability** -- the list shape lets a single
   chain accumulate multiple acknowledgements across child boundaries
   without overwriting earlier ones, which matches the reality that
   upstream can advance multiple times during a long tactical chain.

The chain-proposal-vs-Phase-2 distinction is given its own section
(rather than buried in the trigger condition) because the deferred
question singles it out as a likely confusion surface. Future readers
of the reference -- including authors writing `/work-on`'s migration and
authors back-editing `/charter` -- get a direct "these are two different
prompts, here is why they are separate" answer rather than having to
infer it.

The default option of `rebase` is named explicitly because the parent-
skill-pattern reference treats default-option wording as contract surface
(not a UX detail), and the discipline's two non-default options both
have asymmetric durable-trace consequences (one records an
acknowledgement, one bails). Picking the "make it clean" option as
default keeps the discipline's bias toward fresh state.

Rebase mechanics are spelled out in four sub-steps because the rebase
sub-flow has two failure surfaces (uncommitted non-wip changes,
rebase conflicts) that are easy to handle wrong if left implicit. The
"clean working tree" precondition is named explicitly because the
parent's `wip/` surface IS expected to have uncommitted edits during a
run; the precondition has to discriminate `wip/` activity (expected)
from other unstaged work (not expected). The conflict path forbids
automatic resolution because conflict resolution is human-judgment
territory; mandating manual resolution preserves the parent's
non-destructive contract.

**Alternatives Considered**

- **Place at `skills/scope/references/operational-runbook.md`**.
  Rejected by PRD Decision 4 ahead of this report. Faster to ship for
  `/scope` v1, but creates known re-home work in SE12 and forces
  `/charter` to re-derive the discipline rather than inherit it.
- **Fold the check into the chain-proposal prompt as a fourth
  option**. Considered and rejected. The chain-proposal prompt would
  grow from three options (Proceed/Adjust/Bail) to seven
  (Proceed/Adjust/Bail × clean-or-rebase × proceed-anyway-or-bail), and
  the once-per-chain firing would miss mid-chain divergence on tactical
  chains. The two-prompt design preserves the chain proposal's
  three-option contract and gets the trigger interval right.
- **Record `worktree_divergence_acknowledged` as a single field
  (string or boolean) instead of an appended list**. Considered and
  rejected. A boolean loses the per-child specificity needed for audit
  trails. A single-entry string overwrites prior acknowledgements when
  the chain accumulates multiple. The list shape costs three extra
  lines per state file and gains durable per-acknowledgement detail.
- **Inline the discipline in `parent-skill-pattern.md` rather than a
  separate reference**. Considered and rejected. The pattern reference
  is the contract surface for invariants the pattern names; the
  worktree discipline is an operational concern that not every parent
  necessarily adopts (e.g., a parent with no chain-execution phase
  would not need the discipline). Separate-file placement matches the
  pattern of `parent-skill-resume-ladder-template.md` and
  `parent-skill-child-inspection.md` -- shared-but-not-universal
  operational references next to the contract reference.
- **Make `rebase` the only option (force-rebase semantics)**.
  Considered and rejected. Forcing rebase removes author agency in
  cases where the divergence is known-benign (e.g., upstream has only
  documentation commits that don't affect the chain's working set). The
  `proceed anyway` option with durable acknowledgement preserves the
  agency without losing the audit trail.

**Consequences**

What becomes easier:

- `/scope` ships with a clear, single-source trigger condition that
  reviewers can grep-check against the eval surface (AC28: "the SKILL.md
  / phase-2 reference documents the trigger condition; an eval scenario
  verifies the halt fires when upstream divergence is simulated").
- `/charter`'s back-edit PR is mechanical: add one Reference Files row
  and one citation in the phase-2 reference; the discipline body is
  already authored.
- `/work-on`'s SE8 migration inherits the discipline by adding a single
  citation, with no re-derivation work.
- The audit trail for "why did this chain ship a conflict?" becomes
  reconstructable from the state file: each `worktree_divergence_acknowledged`
  entry names the child, the SHAs, and the timestamp.

What becomes harder:

- The state schema gains a new conditional field
  (`worktree_divergence_acknowledged`) that R9's hard-finalization check
  has to be aware of (the field MUST satisfy I-5: absent when no
  acknowledgement has fired). This is a small extension to the existing
  check spec, not a new check.
- `/charter`'s back-edit PR is now a required follow-on (not optional)
  because the discipline has moved from `/scope`-specific to top-level.
  The PRD already names this as planned work (Decision 4 final
  paragraph); the design ratifies it.
- Per-chain operational latency increases by one `git fetch` per child
  dispatch (four `fetch` calls per full-run tactical chain; three per
  full-run strategic chain). The PRD's Known Limitation acknowledges
  this; the discipline does not introduce additional latency beyond
  what R21 already named.
- The author has a new prompt surface (the worktree-staleness prompt)
  that they will encounter during normal chain runs whenever upstream
  advances. The prompt is bounded (three options, default `rebase`,
  literal substrings for eval matching) but is a new conversational
  artifact authors learn.

What this enables downstream:

- Future amplifier-layer substrates that satisfy invariant I-6
  (cross-branch resume) can extend the field shape -- e.g., to record
  per-branch acknowledgement trails -- without breaking the v1 field
  semantics. The list-of-entries shape is forward-compatible with
  multi-branch chains.
- The discipline is the first operational reference that explicitly
  binds itself to multiple parents in the Binding Notes section,
  establishing a precedent for future shared-but-not-universal
  operational references (e.g., a future "parent-skill-network-failure-handling.md"
  or similar).
<!-- decision:end -->
