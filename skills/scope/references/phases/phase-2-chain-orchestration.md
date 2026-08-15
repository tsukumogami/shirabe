# Phase 2 — Child Invocation Loop

Phase 2 walks `planned_chain:` from Phase 1, invoking each
child in order. Before each invocation, Phase 2 runs the
worktree-staleness check from the canonical worktree-discipline
reference; immediately around the invocation, Phase 2 writes
and clears the `parent_orchestration:` sentinel; after each
invocation Phase 2 runs the R20 structural file-existence check,
captures the child snapshot, routes through the validator
pass-through, and runs the consolidation judgment against the
nearest surviving artifact above the one that just landed.
Phase-N Reject from `/prd` or `/design` is observed via
`git log` against the discard commit.

Two things make this phase different from the one it replaces.
Children are invoked with the artifact this chain produced above
them rather than with the bare topic slug, so each consumes its
upstream instead of re-deriving it. And the artifact set is
reduced *here*, after the artifacts exist, rather than at Phase 1
before any of them do.

## Table of Contents

- [Per-Child Invocation Loop Ordering](#per-child-invocation-loop-ordering)
- [Worktree-Staleness Check Before Each Child Invocation](#worktree-staleness-check-before-each-child-invocation)
- [`parent_orchestration:` Sentinel Write](#parent_orchestration-sentinel-write)
- [Child Invocation](#child-invocation)
- [R20 Structural File-Existence Check](#r20-structural-file-existence-check)
- [`parent_orchestration:` Cleanup](#parent_orchestration-cleanup)
- [Child-Snapshot Capture](#child-snapshot-capture)
- [Phase-N Reject Handling](#phase-n-reject-handling)
- [Validator Pass-Through](#validator-pass-through)
- [Consolidation Judgment](#consolidation-judgment)
- [Per-Child Gates from `planned_chain:`, Not Re-Walked](#per-child-gates-from-planned_chain-not-re-walked)
- [State-File Enum Re-Validation Before Path Interpolation](#state-file-enum-re-validation-before-path-interpolation)
- [References](#references)

## Per-Child Invocation Loop Ordering

For each child name in `planned_chain:` in order, Phase 2 runs
eight steps in sequence:

1. **Worktree-staleness check.** Run the three-phase flow
   (Rebase phase → Impact-analysis phase → Escalation phase)
   from
   `${CLAUDE_PLUGIN_ROOT}/references/worktree-discipline.md`.
2. **`parent_orchestration:` sentinel write.** Write the block
   to the state file immediately before invoking the child.
3. **Child invocation.** Invoke the child via its existing
   input mode: the topic slug for `/brief`, the nearest produced
   upstream artifact's path for every later child.
4. **R20 structural file-existence check.** Confirm the child's
   canonical durable artifact exists after the child returns.
5. **`parent_orchestration:` cleanup.** Remove the sentinel
   block from the state file (regardless of child outcome).
6. **Child-snapshot capture.** Record the child's status +
   content-hash dual-check pair in `child_snapshots:`.
7. **Validator pass-through.** Run `shirabe validate --format
   json` against the new intermediate, parse the envelope, and
   branch on the multi-level exit code; a `violations` or
   tool-error result halts the chain.
8. **Consolidation judgment.** Compare the artifact that just
   landed against the nearest surviving durable artifact this
   chain produced above it, and reach a `keep` or `absorb`
   verdict. Skipped when this chain produced no artifact above
   the current one.

The eight-step ordering is the contract. Steps that depend on
the state file (write/clear of `parent_orchestration:`, child-
snapshot capture) bracket the child invocation in a way that
keeps the sentinel ephemeral: present ONLY while a child is in
flight; cleared the moment the child returns.

## Worktree-Staleness Check Before Each Child Invocation

The check runs the three-phase flow defined in
`${CLAUDE_PLUGIN_ROOT}/references/worktree-discipline.md`:

- **Rebase phase.** Execute the equivalent of `git fetch && git
  rebase origin/<tracking-branch>`. Clean rebase proceeds to
  Impact-analysis with the list of upstream commits that
  landed. Conflicted rebase invokes the conflict-resolution
  sub-agent (or the parent itself in solo mode), resolving from
  artifact context where the chain's BRIEF / PRD / DESIGN
  citations make the correct resolution obvious; unresolved
  conflicts proceed to Impact-analysis carrying the unresolved
  diff for classification.
- **Impact-analysis phase.** Cross-reference the upstream
  commits against the chain's authored artifacts and the next
  child's expected inputs. Classify impact at one of three
  levels: `None` (changes touch no path, symbol, or contract
  the chain depends on), `Informational` (chain-referenced
  content was touched non-substantively — typo fix, comment
  addition, whitespace change), or `Intent-changing` (a
  contract, interface, or fact the chain has committed to was
  altered — child input format changed; cited file renamed or
  removed; doc cite no longer supports the chain's claim;
  expected recipe withdrawn).
- **Escalation phase.** None / Informational proceeds silently;
  the rebase is recorded in `worktree_rebases:` and Phase 2
  advances to step 2 (sentinel write). Intent-changing halts and
  routes to the team lead for an intent judgment. The team
  lead decides whether the original session intent still holds:
  yes routes to in-place resolution (update the affected
  citation or claim, then proceed; classification recorded as
  `intent-changing-resolved-in-place`); no escalates to the
  author with a three-option prompt (re-author affected
  artifacts; proceed against original intent — recorded in
  `worktree_divergences:`; bail per R8's bail-handling rule).

The check's recording fields follow the canonical schema:

```yaml
worktree_rebases:
  - phase: <next-child-name>
    upstream_commits: [<sha>, <sha>, ...]
    impact: none | informational | intent-changing-resolved-in-place
    rebased_at: <ISO-8601 timestamp>
    notes: <optional — e.g., which citation was updated>
```

```yaml
worktree_divergences:
  - phase: <next-child-name>
    affected_contracts: [<artifact + cite>, ...]
    upstream_commits: [<sha>, <sha>, ...]
    accepted_at: <ISO-8601 timestamp>
```

`worktree_divergences:` is the audit list — appended only when
the team lead escalated and the author chose "proceed against
original intent." It is absent in the common case per I-5.

Author-supplied prose (e.g., the team-lead's note about an
in-place resolution, or the author's reason for choosing to
proceed against original intent) is committed via the
`git commit -F` discipline documented in Phase 3, never
interpolated into `git commit -m "..."`.

## `parent_orchestration:` Sentinel Write

Immediately before invoking the child, Phase 2 writes the
sentinel block to the state file:

```yaml
parent_orchestration:
  invoking_child: brief | prd | design | plan
  suppress_status_aware_prompt: true
  rationale: fresh-chain | revise
```

The `invoking_child:` field names the child Phase 2 is about to
invoke; the `rationale:` field carries the upfront decision
about whether the run is a fresh chain or a revision (read by
the child to route its own Slot 2 behavior).

## Child Invocation

See [`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`](${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md) Dispatch Contract section for the mechanism that carries each child invocation.

Phase 2 invokes the child via the child's existing input mode.
Which mode depends on whether this chain produced an upstream
for that child:

- **`/brief`** — invoked with the topic slug,
  `/brief <topic-slug>`. It heads the chain, so this chain
  produces nothing above it to hand it. When the state file
  carries `consumed_upstream:` — the author supplied a ROADMAP
  this chain did not produce — the invocation is
  `/brief <topic-slug> --upstream <roadmap-path>` and the brief
  is **grounded** in that roadmap: it reads the feature entry and
  derives its problem and outcome from it. What it records is the
  roadmap's nearest durable ancestor, which `/brief` resolves for
  itself in one hop — the roadmap is never recorded.
- **Every later child** — invoked with the path of the nearest
  artifact this chain produced above it:

  | Child | Argument |
  |---|---|
  | `/prd` | `docs/briefs/BRIEF-<topic>.md` |
  | `/design` | `docs/prds/PRD-<topic>.md` |
  | `/plan` | `docs/designs/DESIGN-<topic>.md`, plus `--upstream <roadmap-path>` when the state file carries `consumed_upstream:` |

  When an artifact above the child was absorbed at an earlier
  hop, the argument is the surviving artifact's path — that is
  what "nearest artifact this chain produced" resolves to once
  an absorb has happened.

These are input modes each child already ships: `/prd`'s Input
Mode 2 takes a BRIEF path and transitions it Draft to Accepted,
`/design`'s PRD mode reads the accepted PRD and bumps it to In
Progress, `/plan` accepts a DESIGN path, and the `--upstream <path>`
flag is authored in `/brief`'s and `/plan`'s own SKILL.md input modes
and Phase 0 contracts, equally usable by an author invoking either
directly. Passing the path is choosing among a child's shipped modes,
not extending its input surface.

**The roadmap travels to two children, for two different reasons.**
`/scope` validates it once at Phase 0 and hands it to the first child
and the last one. `/brief` **grounds** on it: the feature entry and the
sequencing rationale supply the problem and outcome, and what the brief
records is the roadmap's own durable ancestor, resolved by `/brief` at
its Phase 0. `/plan` **records the roadmap itself**: the produced PLAN
names the design first and the roadmap second.

`/scope` hands over the roadmap path in both cases and resolves nothing
itself. The walk up from an ephemeral document to its nearest durable
ancestor is `/brief`'s own contract, so a standalone `/brief --upstream
<roadmap>` behaves identically to one under this parent.

Which child records is decided by the lifetime rule in
`${CLAUDE_PLUGIN_ROOT}/references/pipeline-model.md`, not by convenience.
A link runs from the shorter-lived document to the longer-lived one. A
ROADMAP is a working artifact the cascade deletes once its features
land, so no durable document may name it — a BRIEF that did would hold a
reference correct on the day it was written and dangling on the day the
cascade ran. The PLAN is working too, and the same cascade deletes it
first, so its link cannot outlive its target. The crossing from the
strategic chain into the tactical one is therefore recorded on the PLAN
and nowhere else.

**A chain that ends before `/plan` records the roadmap nowhere, and that
is the intended shape.** On a `re-evaluation` or `abandonment-forced`
exit there is no PLAN, so there is no legal node to carry the link — and
nothing downstream needs it, because the cascade only ever runs from a
PLAN. What the chain owes the author instead is the record in Phase 3's
durable artifact list (see `phase-3-exit-finalization.md`), so the
roadmap the chain consumed is not lost with the state file.

**Why the slug and the upstream travel separately.** `/brief`
derives its topic slug from the BASENAME of a positional path it
is handed. Handing it the ROADMAP positionally would therefore
name the produced document after the ROADMAP — a brief for
`payment-retries` under a `ROADMAP-billing.md` upstream would land
at `docs/briefs/BRIEF-billing.md`, under a slug `/scope` never
validated, and the R20 file-existence check that looks for
`docs/briefs/BRIEF-<topic>.md` would then fail against the
chain's own artifact. That has worked until now only because the
two slugs coincided by construction; consuming an upstream this
chain did not produce is defined by that coincidence not holding.
The flag decouples them: the slug is the parent's, the upstream is
a separate argument, and neither is derived from the other.

R14 child-isolation is preserved — `/scope` reads only the
child's durable artifact's frontmatter `status:` value plus the
artifact's git blob hash; `/scope` does NOT extend the child's
`$ARGUMENTS` parser, does NOT add env-var consumption, does NOT
add flags or arguments of its own invention per the L13 amendment
in `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`. The
sentinel is the pattern-level convention every child reads
identically; the child's input surface is untouched, and
`--upstream` is part of that surface rather than an addition to
it.

Invoking every child in its cold-start mode was the mechanical
cause of the duplication this skill's consolidation judgment
now reduces: a child handed a bare slug re-derives the framing
its upstream already settled. The paths above are what let each
artifact cite the one above it instead of repeating it.

## R20 Structural File-Existence Check

After the child returns, Phase 2 confirms the child's canonical
durable artifact exists at:

- `docs/briefs/BRIEF-<topic>.md` for `/brief`.
- `docs/prds/PRD-<topic>.md` for `/prd`.
- `docs/designs/DESIGN-<topic>.md` for `/design`, falling back to
  `docs/designs/current/DESIGN-<topic>.md`.
- `docs/plans/PLAN-<topic>.md` for `/plan`.

The DESIGN entry names two paths because `/design`'s own File
Location contract moves the artifact: an active DESIGN lives at
`docs/designs/DESIGN-<topic>.md` and a Current one at
`docs/designs/current/DESIGN-<topic>.md`. A freshly-produced
DESIGN is always at the first; the second is what a chain
re-entered against an already-Current DESIGN finds. Both count as
present for R20, and Phase 1's discovery globs the same pair.

When the artifact is present, Phase 2 proceeds to sentinel
cleanup and snapshot capture. When the artifact is absent —
PASS-with-no-artifact (the child reported success but the
canonical durable file does not exist on disk) — the outcome
is mapped to STALE and routed via R8's bail-handling using the
most-recently-running tie-break to resolve `triggering_child:`.

The structural check closes a class of silent failure where a
child reports success but does not actually write its terminal
artifact. R20's surface is the canonical path test, not a
content read.

## `parent_orchestration:` Cleanup

Phase 2 removes the entire `parent_orchestration:` block from
the state file immediately after the child returns —
regardless of the child's outcome (PASS / Reject via discard
commit / STALE). The block is ephemeral within a chain
instance; it MUST NOT persist into the next loop iteration or
into any post-chain state.

The cleanup is unconditional and silent. No prompt fires, no
warning surfaces. The sentinel's job is done the moment the
child returns.

## Child-Snapshot Capture

For each child that completed (the durable artifact exists
post-R20), Phase 2 records a snapshot in `child_snapshots:`:

```yaml
child_snapshots:
  <child>:
    status: <frontmatter-status>
    content_hash: <git-blob-hash>
    captured_at: <ISO-8601 timestamp>
```

The pair (status + content-hash) is the dual-check the resume
ladder consults on subsequent re-entries to detect drift between
the snapshot and the current artifact. Per Decision 5, the
snapshot stays frozen on a re-evaluation Decision Record write
— the existing upstream is the comparison point, not the
Decision Record's own path.

## Phase-N Reject Handling

When `/prd` Phase 4 Reject or `/design` Phase 6 Reject fires
in-chain, the child returns control to `/scope` after producing
a discard commit (per Component 7.7). The discard commit's
shape is canonical:

- `docs(prd): discard PRD draft for <topic>` for `/prd` Phase 4
  Reject.
- `docs(design): discard DESIGN draft for <topic>` for
  `/design` Phase 6 Reject.

The implementation pattern at the chain level:

1. Before each in-chain `/prd` or `/design` invocation, Phase 2
   records the current branch's HEAD SHA as `pre_invocation_sha`.
2. After the child returns, Phase 2 reads
   `git log <pre_invocation_sha>..HEAD` for any discard commit (a
   commit whose message conforms to the Reject contract shapes
   above). The commit's SHA is captured into
   `discard_commit_sha:` and the commit body's rejection-rationale
   prose is captured into `rejection_rationale:` in the state
   file.
3. If a discard commit is observed, Phase 2 SHALL advance the
   state file with:

```yaml
exit: re-evaluation
boundary: prd | design          # gated by which child rejected
decision_record_sub_shape: rejection
discard_commit_sha: <sha>
rejection_rationale: <free-text from commit body>
```

The R20 structural file-existence check post-Reject confirms
the durable artifact was removed (the discard commit's intent
was to delete the Draft from disk); the absence is expected,
not a STALE condition.

### In-Chain vs Out-of-Chain Reject

The `git log`-based observability mechanism preserves R13
manual-fallback parity: the discard commit is the durable signal
regardless of in-chain or out-of-chain invocation, so a child
that Rejects without `/scope` orchestrating still leaves a
re-grepable trace. The asymmetry is solely whether a Decision
Record gets written.

- **In-chain Reject** — `/prd` Phase 4 Reject or `/design`
  Phase 6 Reject fired while `/scope`'s `parent_orchestration:`
  sentinel was present. `/scope` writes a rejection-sub-shape
  Decision Record at
  `docs/decisions/DECISION-{prd|design}-<topic>-rejection-<YYYY-MM-DD>.md`
  immediately, observing the discard commit via the `git log
  <pre_invocation_sha>..HEAD` mechanism above.
- **Out-of-chain Reject** — `/prd` or `/design` Reject fired
  outside any `/scope` invocation. The discard commit is the
  durable trace; no retroactive Decision Record is written on a
  later `/scope` resume. A later `/scope` invocation against the
  same topic detects the discard commit but treats it as
  external context — manual-fallback parity preserves the
  contract that `/scope` does not modify state for runs it did
  not orchestrate.

The discard-commit observability mechanism is the same in both
cases — `git log` reads commit metadata regardless of who
invoked the child — so the manual-fallback parity is
mechanically symmetric.

## Validator Pass-Through

After the structural check passes, Phase 2 runs
`shirabe validate --format json --visibility=<repo-visibility>`
against the new intermediate. The `<repo-visibility>` value is
the one detected in Phase 0 from CLAUDE.md's `## Repo Visibility:`
header (default Private if absent).

The validator runs the `shirabe` binary at `cmd/shirabe/` —
the same binary humans invoke for ad-hoc validation. Phase 2
parses the `shirabe-validate/v1` JSON envelope from stdout and
branches on the multi-level exit code (the contract shared with
`transition` and `finalize-chain`; see
`docs/guides/multi-consumer-cli-contract.md`):

- **0 (clean)** — the iteration clears; the loop advances to the
  next child in `planned_chain:`.
- **2 (violations)** — the validator completed and found at least
  one error-level result. Halt the chain immediately and route to
  R8's bail-handling. Surface the parsed `findings` readably: for
  each error-severity finding, show
  `<message> (<file>:<line>)` rather than dumping the raw
  annotation text — the author sees *which* check failed in plain
  terms. The `message` field already embeds the check code (e.g.
  `[L05] ...`), so do NOT prepend `[<code>]` again; read the
  `code` field for any branching logic, not for the human-facing
  line.
- **1 (tool-error)** — the validator could not run (bad
  invocation, an unreadable or unparseable intermediate, an
  envelope that does not parse). Treat this as a tool failure
  DISTINCT from a content violation — surface it as such and halt;
  do NOT report it as a document violation.
- **4 (incomplete)** — the validator accepted the intermediate and
  then did not check it: the filename prefix routed it to a format
  but its `schema:` field is missing or out of range. Halt the
  chain and surface the envelope's `skipped` entries, naming the
  file and the reason. This is NOT a content violation — nothing
  is known to be wrong with the document, which is the problem: it
  was never examined. The fix is to add the `schema:` field to the
  intermediate and re-invoke, after which the real checks run.
  Advancing on a 4 would carry an unvalidated artifact into the
  next child.

`/scope` does NOT auto-fix validator failures, and only the
consumption mechanism changed (JSON parse plus multi-level exit
code) — `/scope` still does not re-implement the validator's
checks. The author is the validator-failure resolver; the chain
remains halted until the author addresses the failure (typically
by re-running the child with corrections, or by re-invoking
`/scope` from the beginning with a re-framed topic).

## Consolidation Judgment

Step 8 is where the artifact set shrinks. It runs after the
validator pass-through clears, and only when this chain produced
a durable artifact above the one that just landed.

**Why it exists.** Three documents restating one problem at three
altitudes cost a reader three reads for one idea, and an obvious
concept articulated three times reads as ceremony. Reducing the
set is worth doing for the reader. It is only honest to do it
*here* — against two bodies that exist, where the question "does
the upstream do work the downstream does not?" has an answer. The
same question asked at Phase 1, before either document is
written, has no answer, and answering it anyway is how content
gets lost.

### Stage 1 — Absorbability

Look the hop up in the mapping table. Absorption is available
only where the downstream type's required sections provide a home
for **every** required section of the upstream type, so an absorb
never has to discard content or invent somewhere to put it.

| Hop | Mapping | Absorbable |
|---|---|---|
| BRIEF to PRD | Problem Statement to Problem Statement; User Outcome to Goals; User Journeys to User Stories; Scope Boundary to Requirements (the in-list) and Out of Scope (the out-list) | Yes |
| PRD to DESIGN | Problem Statement to Context and Problem Statement; Goals, User Stories, Requirements, Acceptance Criteria and Out of Scope have no home | No |
| DESIGN to PLAN | Decision Drivers, Considered Options, Decision Outcome, Solution Architecture, Security Considerations and Consequences have no home | No |

The verdicts are derived from the per-type required-section
contracts in `crates/shirabe-validate/src/formats.rs`, not
enumerated by hand. If a format ever grows a section, re-derive
the table rather than trusting this snapshot.

When the mapping is not total, the only available verdict is
`keep`. Record it with the reason naming the unmapped sections
and stop.

### Stage 2 — Judgment

Read both bodies. The question is whether the upstream artifact
does work the downstream does not: does any required section of
the upstream carry content, detail, or framing the downstream
does not also carry?

- **No** — verdict `absorb`. Continue to stage 3.
- **Yes** — verdict `keep`, with a finding naming what the
  upstream holds that the survivor does not.

At the BRIEF-to-PRD hop the prior leans toward `absorb`: four of
the BRIEF's five required sections are renamed PRD sections with
equivalent content rules, so a BRIEF that fed one PRD and did no
independent framing work is a redundant document rather than a
redundant paragraph. A BRIEF whose journeys drove the requirement
set, or whose framing settled something contested, has earned its
own document and keeps it.

### Stage 3 — Carry check and absorb

On `absorb`, walk the upstream's required sections one at a time
and record where each landed. This is the receiving mechanism: an
absorb that is not itemized is a recommendation, and a
recommendation with nothing confirming the transfer is how
content goes missing.

```yaml
consolidation_judgments:
  - hop: brief->prd
    absorbable: true
    carry_check:
      Problem Statement: {target: Problem Statement, carried: true}
      User Outcome:      {target: Goals, carried: true}
      User Journeys:     {target: User Stories, carried: true}
      Scope Boundary:    {target: Requirements + Out of Scope, carried: true}
    verdict: absorb
    absorbed: docs/briefs/BRIEF-<topic>.md
    into: docs/prds/PRD-<topic>.md
```

Any `carried: false` **aborts the absorb**: the verdict is
downgraded to `keep`, the finding names the section that did not
arrive, and both artifacts stay on disk. Nothing is deleted on a
failed carry check.

When every section is carried, complete the absorb:

1. Read the absorbed artifact's own `upstream:` value.
2. Set the survivor's `upstream:` to that value, or remove the
   field when the absorbed artifact had none. This is the settled
   nearest-produced rule from
   `${CLAUDE_PLUGIN_ROOT}/references/pipeline-model.md`, not a
   new convention.
3. `git rm` the absorbed artifact.
4. Re-run `shirabe validate` on the survivor. A non-zero exit
   reverts the absorb (restore the artifact, restore the
   `upstream:` value) and routes to R8 bail-handling.

Step 4 is load-bearing: the validator's `R6` check requires an
`upstream:` value to resolve to a tracked file, so a survivor
whose re-point was missed fails validation and the absorb does
not land.

### Cascade across hops

There is no cascade to reason about. `absorb` means the upstream's
content is *in* the survivor, not annotated as living elsewhere,
so a later hop judging that survivor is judging a body that
already includes everything absorbed into it. Nothing rides along
separately and there is no chain of pointers to follow.

### Manual-fallback boundary

Step 8 lives here and nowhere else. A child invoked directly,
outside `/scope`, runs no consolidation judgment and writes no
`/scope` state — not because a code path is suppressed, but
because there is no consolidation code path inside a child. That
is the same reason the judgment is not implemented in one: a
child cannot see the chain, and a parent's invocation shape
decides whether the child's branch is reachable at all.

## Per-Child Gates from `planned_chain:`, Not Re-Walked

Phase 2 reads `planned_chain:` from the state file (populated
by Phase 1) and invokes the listed children in order. The
per-child re-entry protection is NOT re-walked at Phase 2 — it is
cached in Phase 1's verdicts. The state-file fields driving the
cache:

- `planned_chain:` — the whole tactical chain, minus any child
  held back by re-entry protection. `/brief` heads it, so `/brief`
  is the child that receives the topic slug and every other child
  receives an artifact path.
- `chain_skipped:` — children held back by re-entry protection
  (e.g. `/prd` against an Accepted PRD), carrying the reason
  `settled-artifact-at-canonical-path-reentry-protection`.
- `child_snapshots:` — initial snapshots of pre-existing
  durable artifacts Phase 1 discovered.

Phase 2's job is iterative invocation against the cached
chain shape, not re-evaluation of Phase 1's decisions.

## State-File Enum Re-Validation Before Path Interpolation

Before constructing any write path that interpolates a state-
file field (Decision Record path on Reject; force-
materialization path on STALE; `wip/` removal paths on chain
finalization), Phase 2 re-validates the field's value against
its declared enum:

- `boundary:` against `{prd, design}`.
- `decision_record_sub_shape:` against
  `{re-evaluation, rejection}`.
- `triggering_child:` against `{brief, prd, design, plan}`.
- `plan_execution_mode:` against
  `{single-pr, multi-pr, coordinated}`. `coordinated` is the
  multi-repo generalization of `multi-pr`; a coordinated chain
  records it, and omitting it from the enum would fail the
  re-validation on exactly the runs `/scope`'s coordination
  intent produces.

The chain shape itself needs no re-validation entry. `planned_chain:`
is a constant, the child names are fixed, and each child's argument
path is composed from the validated topic slug rather than from
state — so a tampered state file cannot redirect an invocation to
an unexpected child or an unexpected path.

Out-of-enum values fail the operation and route to R8 bail-
handling. The re-validation closes the state-file-tampering
surface where an attacker would otherwise inject a shell
metacharacter into a field that later becomes a path component.

## References

- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` —
  Gate Vocabulary; L13 amendment defining the
  `parent_orchestration:` sentinel as the pattern-level parent-
  orchestration primitive; semantic invariant I-7 (Team-Lead
  Operating Discipline) for the child-invocation task class
  (120s window, 10-cycle patience budget).
- `${CLAUDE_PLUGIN_ROOT}/references/worktree-discipline.md`
  — the three-phase Rebase / Impact-analysis / Escalation flow
  the per-child loop runs before each invocation, the
  `worktree_rebases:` and `worktree_divergences:` recording
  schema.
- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-child-inspection.md`
  — R14 widened isolation rule and the per-parent inspection
  surface table.
- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`
  — `child_snapshots:`, `parent_orchestration:`,
  `chain_ran:` semantics consumed by this phase.
- `${CLAUDE_PLUGIN_ROOT}/references/pipeline-model.md` — the
  settled `upstream:` rule the absorb's re-point applies.
- `crates/shirabe-validate/src/formats.rs` — the per-type
  required-section contracts the absorbability mapping is
  derived from.
- `skills/scope/references/state-schema.md` — `visibility:` and
  `consolidation_judgments:` field definitions.
