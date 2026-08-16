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
- [State-File Enum Re-Validation](#state-file-enum-re-validation)
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
   content-hash dual-check pair in `child_snapshots:`, and append
   the child to `chain_ran:` with a started-at timestamp.
7. **Validator pass-through.** Run `shirabe validate --format
   json` against the new intermediate, capturing stdout and
   stderr. Parse the envelope first — no envelope is a tool-error
   whatever the exit code — and branch on the multi-level exit
   code only once it parses; a `violations` or tool-error result
   halts the chain.
8. **Consolidation judgment.** Compare the artifact that just
   landed against the artifact this run handed it as its
   invocation argument, and reach a `keep` or `absorb` verdict.
   Does not fire unless both endpoints of that edge appear in
   `chain_ran:` — see the firing condition below, which is
   stricter than "this chain produced something above the current
   artifact" and deliberately so.

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

In the same step, append the child to `chain_ran:`:

```yaml
chain_ran:
  - name: <child>
    started_at: <ISO-8601 timestamp>
```

**This is the field's only write site.** Phase 3 reads
`chain_ran:` in four places — R9 Part 3's chain-membership gate,
the PR-body record that copies every artifact in it, the R8
tie-break that resolves the most-recently-running child from its
per-entry timestamps, and the `plan_execution_mode:` presence
check — and nothing wrote it. The timestamp is not decoration:
Phase 3's tie-break already claims to read it, and without it that
claim is contradicted by the schema.

The consolidation judgment's firing condition also reads this
field, which promotes it from bookkeeping to a gate on a
destructive operation. That is why entry names are re-validated
before use (see State-File Enum Re-Validation below).

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
captures BOTH stdout and stderr from the sub-process; stderr is
never discarded, because in the no-envelope case it is the entire
diagnostic.

**Precedence: the envelope decides before the exit code does.**
Phase 2 parses stdout for the `shirabe-validate/v1` envelope
FIRST. Absence of a parseable envelope means the validator never
reached a verdict, whatever the exit code: treat the run as a
tool-error, surface the captured stderr verbatim, and halt WITHOUT
reporting a document violation. A `shirabe` too old to recognize a
flag Phase 2 passes rejects it as a usage error and exits 2, and
without this rule that reads as "violations" and sends the author
to fix an intermediate that is not broken.

With a parsed envelope, Phase 2 branches on the multi-level exit
code (the contract shared with `transition` and `finalize-chain`;
see `docs/guides/multi-consumer-cli-contract.md`):

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
- **1 (tool-error)** — the validator ran but could not complete
  (an unreadable or unparseable intermediate, an unknown `--check`
  code, a bad invocation). Treat this as a tool failure DISTINCT
  from a content violation — surface it with the captured stderr
  and halt; do NOT report it as a document violation. A run with
  no parseable envelope lands here too, via the precedence rule
  above, whatever its exit code.
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
consumption mechanism changed (envelope-presence precedence, then
the multi-level exit code) — `/scope` still does not re-implement
the validator's
checks. The author is the validator-failure resolver; the chain
remains halted until the author addresses the failure (typically
by re-running the child with corrections, or by re-invoking
`/scope` from the beginning with a re-framed topic).

## Consolidation Judgment

Step 8 is where the artifact set shrinks.

**Why it exists.** Three documents restating one problem at three
altitudes cost a reader three reads for one idea, and an obvious
concept articulated three times reads as ceremony. Reducing the
set is worth doing for the reader. It is only honest to do it
*here* — against two bodies that exist, where the question "does
the upstream do work the downstream does not?" has an answer. The
same question asked at Phase 1, before either document is
written, has no answer, and answering it anyway is how content
gets lost.

### Firing condition

The judgment fires only when **both endpoints of the edge this run
drew were produced by this run**. Concretely: the upstream is the
artifact path this run handed the child as its invocation argument,
and the judgment fires only if that artifact appears in
`chain_ran:`.

When it does not hold there is no hop, no `consolidation_judgments:`
entry, and no verdict. A held-back artifact was never a party to a
judgment, and `chain_skipped:` already records why it was held back.

This is **stricter than "this run produced both documents"**, and
the difference is deliberate rather than a restatement. Re-entry
protection can hold a middle child back, which makes
`brief->design`, `prd->plan` and `brief->plan` reachable; the
first of those is produced by a shipped eval. Under the looser
reading those hops compose and reach the content question. Under
this one they never compose at all.

The justification is not caution about content loss but that the
alternative question is **ill-posed**. Stage 2 asks whether the
upstream does work the downstream does not, which presupposes the
downstream could have incorporated it. Where the downstream never
read the upstream, absence is evidence of nothing and `absorb`
would be reached on a false inference. Non-adjacent hops therefore
never compose, rather than composing and being refused — which is
what keeps this rule clear of the requirement that no hop be
unabsorbable because of the types involved.

### Two clauses bound the whole judgment

**The ceiling.** The preflight below cannot reach any outcome
stronger than `keep`. It refuses or it defers; it never decides to
absorb.

**The input restriction.** *No check in this judgment may read
either type's required-section list, or compare the two types'
section sets.* Chain position and provenance are admissible inputs;
a type's content contract is not.

The test for a violation: **a condition that refuses one pair while
permitting its structural twin under identical repository state is
a type rule.** If two hops differ only in which types they join and
the check answers differently, the check is reading the types.

The restriction is repeated at the head of Stage 2 rather than
stated once here, because Stage 2 is the stage that can return
`absorb` and no ceiling applies there. A type-shaped shortcut is
worse at that position, not better — which is the reason this
position survives at all rather than the stage being deleted.

### Stage 1 — Citation preflight

Run the guard before anything is composed, written, or deleted,
passing the artifact this hop would delete and the artifact
absorbing it:

    skills/scope/scripts/check-citations.sh --target <deleted> --survivor <survivor>

Route on its exit status:

| Status | Meaning | Action |
|---|---|---|
| 0 | clean | proceed to Stage 2 |
| 2 | bare-name mentions only | proceed to Stage 2, carrying the output as a finding |
| anything else | path citations, or the search did not complete | verdict `keep`, record the finding, stop |

**The routing default is deny.** Any status other than 0 or 2 routes
to `keep`, including statuses the script does not define. Do not
enumerate the failure codes and assume the rest are success — the
script's own contract inverts `git grep`'s convention precisely
because the naive reading of a search's exit status gets this
backwards.

A refusal here is a pure abort: nothing has been mutated, so there
is nothing to undo. That is why the guard runs first rather than
beside the deletion.

**What this buys, stated because the guard's reach is narrower than
its description suggests.** It protects citers that *pre-existed*
the run, and structurally cannot protect a deletion target the run
*created* — a document written before the run cannot cite one
created during it. Under the firing condition every hop the
judgment reaches has a run-produced upstream, so the live coverage
is same-run citers: `/scope`'s own Decision Record templates, which
write durable files citing artifact paths, and anything a child
skill wrote naming the artifact. The check is required regardless;
this states what it actually catches.

### Stage 2 — Judgment

*The input restriction above applies here in full. This is the
stage that can return `absorb`, and no ceiling protects it.*

Read both bodies. The question is whether the upstream artifact
does work the downstream does not: does the upstream hold anything
beyond its contribution that compression into a contribution
section would lose?

- **No** — verdict `absorb`. Continue to Stage 3.
- **Yes** — verdict `keep`, with a finding naming what the
  upstream holds that the survivor does not.

Weigh any bare-name finding from Stage 1 here. It does not decide
anything by itself; it is context for a judgment made against the
two documents.

The verdict is yours. There is no reviewer, no confirmation prompt,
and no mode-conditional gate on it at any hop, including the
terminal one.

### Stage 3 — Compose, verify, move, re-validate

Eight steps. Steps 1 and 2 are Stages 1 and 2 above; the rest run
only on `absorb`.

3. **Compose the contribution, in memory.** Write the ancestor's
   contribution section from the **survivor's own body**, not from
   the document about to be deleted. Nothing is written to disk at
   this step.

   Sourcing from the survivor is what makes a single unreviewed
   authoring site tolerable: that material was already reviewed
   when it landed in the survivor's ordinary sections, and an
   under-distillation leaves the omitted content still visible in
   the survivor rather than gone at the delete.

4. **Carry check.** Itemize the ancestor's required sections *and*
   every contribution the ancestor itself carries — its own and any
   it inherited, read from the ancestor's `absorbed:` list and its
   contribution sections. A survivor absorbing a document that
   already carried two contributions must confirm three things
   carried.

   Any `carried: false` **aborts the absorb**: the verdict is
   downgraded to `keep`, the finding names what did not arrive, and
   both artifacts stay on disk. Nothing has been written yet, so
   this is still a clean abort.

5. **Snapshot, then write the survivor.** Capture the survivor's
   pre-fold bytes first — nothing has committed them, and
   `git checkout HEAD --` is not guaranteed to resolve to them.
   Then, in one pass:

   - splice `upstream:`, **preserving sibling and cross-repo
     parents** rather than replacing the list;
   - write the `absorbed:` declaration;
   - write the `## Status` absorption line, one per absorbed entry,
     in the pinned shape
     `Absorbed [<name>](<path>); carried in <Heading>.`;
   - write the contribution section immediately after `## Status`,
     in chain order;
   - rewrite the survivor's own prose citations of the absorbed
     path. The preflight deliberately excludes the survivor, so
     nothing else protects these and they dangle the moment the
     fold lands.

   **Visibility:** when this repository is Public and a spliced
   parent resolves to a private artifact, drop the entry and report
   the omission rather than writing it. This is the `--upstream`
   check's third ordered condition applied at a second site; a
   public document naming a private one is the same violation
   whichever field carries it.

6. **Delete the absorbed artifact** with `git rm`.

7. **Re-validate the survivor.** Run `shirabe validate` against it.
   A non-zero exit triggers the rollback below.

8. **Commit** the deletion, the re-point and the survivor's edits
   together.

### Rollback

Steps 1 through 4 mutate nothing; a failure there is already a
clean abort. Every step from 5 onward writes, so a failure at any
of them reverts everything written since, in reverse:

| Failing step | Undo |
|---|---|
| 5 write | restore the survivor from the step-5 snapshot |
| 6 delete | restore the deleted artifact; restore the survivor |
| 7 re-validate | restore the deleted artifact; restore the survivor |
| 8 commit | as step 7 |

Then downgrade the verdict to `keep`, record the revert in the
judgment entry, and route to R8 bail-handling.

**A partial absorb is never resumed across sessions.** If a resume
finds a chain interrupted between steps 5 and 8, restore the
survivor, delete nothing, and leave the hop at `keep`.
**No path is ever read back from `consolidation_judgments:` for
interpolation** — state-file strings reaching a deletion is exactly
the surface the enum re-validation contract exists to close.

### The judgment entry

```yaml
consolidation_judgments:
  - hop: brief->prd
    stage: carry
    carry_check:
      Problem Statement: {target: Problem Statement, carried: true}
      User Outcome:      {target: Goals, carried: true}
      User Journeys:     {target: User Stories, carried: true}
      Scope Boundary:    {target: Requirements + Out of Scope, carried: true}
    verdict: absorb
    absorbed: docs/briefs/BRIEF-<topic>.md
    into: docs/prds/PRD-<topic>.md
```

`stage:` names where the verdict settled — `preflight`, `judgment`
or `carry`. It replaces the retired `absorbable:` boolean, which
asked whether the required-section mapping was total: the question
this judgment no longer asks.

### There is no durable-artifact floor

A run can absorb its way down to a single surviving artifact, or to
none once the PLAN is implemented, and that is a reachable outcome
rather than a defect.

**Do not add a guard that forces `keep` on the ground that the
survivor would be the last artifact.** The single-mechanism rule
will not catch such a guard — a mechanism whose only possible
effect is to force `keep` does not count as a second reduction
mechanism — so this prohibition has to be written down rather than
derived.

It is wrong for two reasons. It would decide a fold from the
artifact *set* rather than from the two documents at the hop, which
is what this judgment moved the verdict away from. And it would
fire at exactly the DESIGN-to-PLAN hop that must be absorbable,
closing by a second route the floor this work opened.

A chain that folds everything away is handled downstream by
`/execute`'s finalization guard, not prevented here.

### Cascade across hops

There is no cascade to reason about. `absorb` means the upstream's
content is *in* the survivor, not annotated as living elsewhere,
so a later hop judging that survivor is judging a body that
already includes everything absorbed into it. What does ride
along is the `absorbed:` declaration, which accumulates: a
survivor's list is its ancestor's list plus the ancestor.

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

- `planned_chain:` — the whole tactical chain, including any child
  held back by re-entry protection, because membership records the
  plan rather than the outcome. `/brief` heads it, so `/brief` is
  the child that receives the topic slug and every other child
  receives an artifact path.
- `chain_skipped:` — `{child, reason}` entries for the children
  held back by re-entry protection (e.g. `/prd` against an Accepted
  PRD), carrying the reason
  `settled-artifact-at-canonical-path-reentry-protection`. Phase 2
  skips the children this list names; `planned_chain:` alone does
  not tell it which children to invoke.
- `child_snapshots:` — initial snapshots of pre-existing
  durable artifacts Phase 1 discovered.

Phase 2's job is iterative invocation against the cached
chain shape, not re-evaluation of Phase 1's decisions.

## State-File Enum Re-Validation

Every enum-typed or closed-domain field is re-validated against
its domain at **the read that precedes its use**, where a *use* is
any of:

- interpolation into an emitted command,
- construction of a write or delete path,
- a decision that gates a destructive operation,
- serialization into a durable artifact.

The scope sentence is stated this way deliberately. An earlier
version reached only path interpolation, which meant each new
consumer needed its own argument for why it counted — and the
first field to gate a deletion rather than name a path slipped
through on a paragraph that had been written about something else.
One rule covers the category instead of six.

The fields:

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
- `chain_ran:` entry names against `{brief, prd, design, plan}`.
- `verdict:` against `{absorb, keep}` and `stage:` against
  `{preflight, judgment, carry}` — both are read back from the
  state file and drive the absorb's control flow, and `verdict:`
  decides whether a deletion happens at all, so a tampered value
  reaches a `git rm`.
- `visibility:` against `{Public, Private}`. It is read back from
  the state file and interpolated into
  `shirabe validate --format json --visibility=<value>`, so a
  tampered value crosses the interpolation surface and the
  visibility surface at once.

**`chain_ran:` is the reason the previous paragraph here had to
go.** It used to read that the chain shape needs no entry, because
`planned_chain:` is a constant and each child's argument path is
composed from the validated slug rather than from state — so a
tampered file could not redirect an invocation. Every word of that
is about *invocation redirection*, and it is still true about
invocation redirection. It does not extend to this field's new job.
The consolidation judgment's firing condition reads `chain_ran:`
membership, and it is the only thing standing between the judgment
and a document this run did not produce; a tampered entry puts a
pre-existing document on the deletion path, where the citation
preflight cannot help either, because that guard protects citers of
targets that pre-existed the run. Leaving the old paragraph would
have been worse than saying nothing: it read as a considered
exemption for exactly the field that had stopped qualifying.

Out-of-enum or unparseable values fail the operation closed — for
the firing condition that means no hop, no verdict, and `keep` —
and route to R8 bail-handling.

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
