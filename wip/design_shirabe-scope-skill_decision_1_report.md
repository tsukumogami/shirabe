# Decision 1: Phase-N Reject Contract Placement on /prd and /design

## Context

PRD R23 requires `/prd` and `/design` to ship a Phase-N Reject finalization
contract before `/scope` v1 can invoke them, with three observable surface
properties: a final-confirmation gate offering Accept/Reject/Continue-revising,
a `git rm` + wip cleanup + discard-commit sequence on Reject
(`docs({prd|design}): discard {PRD|DESIGN} draft for <topic>`), and identical
behavior in-chain vs out-of-chain (the contract is the child's own; `/scope`
records the rejection-sub-shape Decision Record only when in-chain per AC12a/b
and AC12c). Questions Deferred to Design Q1 explicitly hands the design team
*where* in each child's existing finalization the gate inserts (Phase 4 for
`/prd`, Phase 6 for `/design`), whether the new gate replaces or augments
existing prompts, and how `/design`'s gate orders against the
`docs/designs/` → `docs/designs/current/` directory move. The placement
decision matters because it determines whether the new contract reads as a
clean delta on top of shipped behavior (low-risk extension), a re-architecting
of the existing finalize step (higher-risk replacement), or something that
clashes with downstream lifecycle transitions like the directory move.

## Decision Drivers

- **R23 contract surface MUST hold** — Accept/Reject/Continue-revising at the
  named phase (4 for `/prd`, 6 for `/design`); `git rm` of the durable
  artifact; wip cleanup; commit message format
  `docs({prd|design}): discard {PRD|DESIGN} draft for <topic>`; identical
  in-chain and out-of-chain behavior.
- **AC30a/AC30b name the phase explicitly** — `/prd` Phase 4, `/design`
  Phase 6. Placement at a different phase is not on the table.
- **AC30c requires symmetry between in-chain and out-of-chain** — the
  contract is the child's own; `/scope` adds the orchestration layer
  (Decision Record write) without altering child behavior.
- **The directory move is NOT a Phase 6 concern.** `docs/designs/` →
  `docs/designs/current/` is the Planned → Current transition (all issues
  closed); it fires far after Phase 6. The PRD's Q1 mention of "ordering vs
  the directory move" is a question to verify the placement does not
  conflict with downstream lifecycle, not to interleave with it. Phase 6 only
  deals with `docs/designs/DESIGN-<topic>.md` (Proposed → Accepted, file
  stays in `docs/designs/`).
- **`/strategy` Phase 5 is the load-bearing precedent.** Already-shipped:
  three-option AskUserQuestion (Approve / Request changes / Reject); Reject
  branch runs `git rm` + cleanup + discard commit. `/charter`'s Reject-vs-Bail
  discussion confirms this is the intended pattern for the Phase-N Reject
  contract surface across parent-orchestrated children.
- **Continue-revising must map cleanly to existing "Request changes"
  semantics.** Both `/prd` Phase 4 step 4.6 and `/design` Phase 6 step 6.8
  already have a "Request changes / Needs iteration" branch that loops back
  to an earlier phase. The Phase-N Reject contract's third option (Continue-
  revising) is the same branch, renamed for symmetry with `/strategy`.

## Considered Options

### Option A: Augment Existing Gates (Replace 2-option AskUserQuestion with 3-option)

**Mechanism**: At `/prd` Phase 4 step 4.5 (Present to User) and `/design`
Phase 6 step 6.7 (Present for Approval), replace the current 2-option
AskUserQuestion (Approve / Request changes — Approve / Needs iteration) with
a 3-option AskUserQuestion mirroring `/strategy` Phase 5.2:
1. **Approve** — existing happy-path semantics (step 4.6 / step 6.8 If
   approved branch).
2. **Reject** — NEW branch; runs the discard procedure
   (`git rm docs/{prds,designs}/{PRD,DESIGN}-<topic>.md`, cleans up
   `wip/{prd,design}_<topic>_*.md`, commits the discard).
3. **Continue revising** — renames the existing "Request changes / Needs
   iteration" branch; loops back to the relevant earlier phase.

The new Reject branch is added as a new sub-step (step 4.6.5 / step 6.8.5 or
equivalent) parallel to the existing If-approve / If-needs-iteration branches.
The existing approval step is preserved as-is. For `/design`, Phase 6's
"Commit and PR" step (6.6) executes BEFORE the approval gate today — meaning
on Reject, the discard commit removes a file that has already been pushed.
This is acceptable: the discard commit is the durable trace; the PR captures
the entire history including the discard. (Mirrors `/strategy` Phase 5.5
sequence where the PR is created after the approval branch routes.)

**Pros**:
- Single-edit change: rename existing question, add one new branch, no
  structural reordering.
- Preserves all existing step numbering downstream; minimal diff.
- Symmetry with `/strategy` Phase 5.2's already-shipped pattern; future
  readers see one consistent shape across all three (`/strategy`, `/prd`,
  `/design`).
- "Continue revising" naming aligns across all three Phase-N Reject contracts
  (R23 surface vocabulary).
- AC30c trivially satisfied — the gate is the same code path whether invoked
  in-chain (where `/scope` later writes the Decision Record) or out-of-chain
  (where the discard commit stands alone).

**Cons**:
- The existing "Request changes" / "Needs iteration" wording in `/prd` and
  `/design` carries domain-specific connotations the renaming may flatten;
  reviewers will need to confirm Continue-revising covers all the
  loop-back scenarios the existing wording covered.
- For `/design`: Phase 6 already has its commit + PR sequence (step 6.6)
  BEFORE step 6.7's approval gate. Adding Reject means the discard commit
  follows an initial commit + PR push — the PR ends up with two commits
  (the design + the discard) which is the desired durable trace but means
  reviewers will see a "design + immediate discard" sequence.
- No re-validation of the existing step 4.4 (finalize PRD) and step 6.4
  (validate document structure) prior to Reject — the contract assumes the
  PRD/DESIGN has reached the approval surface, but a Reject after validation
  spends those validation cycles. (Cheap; not load-bearing.)

**Rejection rationale** (if not recommended): N/A — recommended.

### Option B: Insert a New Standalone Phase-N Reject Gate Step BEFORE the Existing Approval Step

**Mechanism**: Add a brand-new step (e.g., step 4.4.5 in `/prd` Phase 4
between "Finalize PRD" and "Present to User", and step 6.6.5 in `/design`
Phase 6 between "Commit and PR" and "Present for Approval") that fires a
dedicated AskUserQuestion asking "Should this draft proceed to approval, or
should it be rejected outright?" Two options: **Proceed to approval** (falls
through to the existing 4.5 / 6.7 approval flow unchanged) and **Reject**
(runs the discard procedure).

The existing 2-option approval gates at step 4.5 / step 6.7 remain
unchanged (Approve / Request changes). The Reject path branches off before
those gates fire.

**Pros**:
- Existing approval gates remain literally untouched; no risk of behavioral
  regression on the Approve / Request-changes paths.
- Reject is structurally surfaced as a distinct decision point — clear in
  prose that Reject is a deliberate finalization judgment, separate from
  Request-changes.
- For `/design`: the new step 6.6.5 fires BEFORE the commit + PR sequence
  could be reordered (see Option C), giving the implementer flexibility.

**Cons**:
- Two AskUserQuestion prompts back-to-back — the author sees "Proceed or
  Reject?" then "Approve or Request changes?" — which clashes with R23's
  contract surface (a single three-option gate, not two two-option gates).
- Diverges from `/strategy` Phase 5.2's already-shipped shape. Future
  readers comparing `/strategy`, `/prd`, and `/design` will see two
  different shapes for the same R23 contract, increasing cognitive load.
- More moving parts: a new step + a preserved existing step instead of a
  single rewrite of the existing step.

**Rejection rationale**: R23 names the contract surface as a single
final-confirmation gate offering all three options. Splitting into two
sequential gates technically meets each individual sub-property (Accept and
Reject options exist; Continue-revising exists) but does so with extra
ceremony the PRD does not request and that breaks symmetry with
`/strategy`'s already-shipped precedent. AC30a/AC30b name the contract as
ONE gate, not two.

### Option C: Reorder /design Phase 6 — Move Commit/PR AFTER the Approval Gate, Then Augment

**Mechanism**: For `/design` specifically (the asymmetry with `/prd` is in
Q1 by name), restructure Phase 6 so that the current step 6.6 (Commit and
PR) moves to AFTER step 6.7 (Present for Approval) — i.e., the design doc
is NOT committed or pushed until the author approves. Then apply Option A's
augmentation pattern: step 6.7 becomes a 3-option gate (Approve / Reject /
Continue-revising); the Approve branch flows into the now-moved Commit and
PR step; the Reject branch runs `git rm` on the un-committed file (which is
just an `rm`), cleans up wip, and commits the discard. (`/prd` keeps Option
A's shape unchanged — its existing Phase 4 step 4.4 already commits
"finalize PRD" BEFORE the approval gate, so the Reject path uses `git rm`.)

**Pros**:
- On `/design` Reject, no orphan commit pushed to the PR — the design doc
  never lands on the branch at all. The discard commit becomes the only
  trace of the design having been attempted, which some reviewers may
  prefer.
- Aligns `/design`'s commit timing with `/strategy`'s (Strategy commits the
  acceptance only after approval; the design doc would similarly only land
  on approval).

**Cons**:
- Breaks AC30b's durable-trace pattern. AC30b reads "on Reject, `/design`
  runs `git rm docs/designs/DESIGN-<topic>.md`" — the `git rm` framing
  presupposes the file is tracked. Restructuring to "never commit until
  approved" means Reject is an `rm` (not `git rm`), and the discard commit
  has nothing to remove. The commit becomes purely a marker commit (e.g.,
  empty commit with the discard message). This is observably different
  from `/strategy`'s pattern and from `/prd`'s pattern under Option A.
- Asymmetric treatment of `/prd` vs `/design` — `/prd`'s discard is a
  `git rm` of a tracked file; `/design`'s discard is a marker commit with
  no file removal. AC30c requires identical out-of-chain and in-chain
  behavior; the asymmetry between the two children's discard procedures
  makes the AC23 / AC30 contract surface harder to reason about.
- Significantly larger blast radius — reordering Phase 6's commit/PR
  sequence touches the resume check (step 6.7's resume-if-frontmatter-
  Proposed assumes the doc is already committed), the strawman check
  ordering, the validate-document-structure step, and the parent design
  doc update flow (step 6.8.4). Each touched surface needs re-testing.
- The directory move `docs/designs/` → `docs/designs/current/` is the
  Planned → Current transition; it fires much later than Phase 6 and is
  unaffected by Phase 6's commit timing. The "ordering vs the directory
  move" concern in Q1 is satisfied by Phase 6 not touching directory
  movement at all (the move only happens on Planned → Current, when all
  issues close). Reordering Phase 6's commit timing does not resolve any
  conflict with the directory move — there is no conflict to resolve.

**Rejection rationale**: AC30b's `git rm` framing presupposes the file is
tracked at Reject time. Reordering Phase 6 to commit-after-approval means
the Reject discard commit has no file to remove, breaking the contract's
durable-trace shape. The asymmetry between `/prd` (true `git rm`) and
`/design` (marker commit only) violates the symmetric-contract spirit of
R23 — both children should produce the same shape of discard commit so
`/scope`'s orchestration (and downstream readers' mental models) can treat
the two children identically. The Q1 concern about the directory move is a
false-positive: the move is the Planned → Current transition, not the
Proposed → Accepted transition Phase 6 governs.

## Recommended Choice

**Option A: Augment Existing Gates** — replace the 2-option AskUserQuestion at
`/prd` Phase 4 step 4.5 and `/design` Phase 6 step 6.7 with a 3-option gate
(Approve / Reject / Continue-revising); add a new If-rejected branch parallel
to the existing If-approved / If-needs-iteration branches; run the discard
procedure on Reject.

This option ties directly to R23's contract surface ("a final-confirmation
gate at the child's Phase 4 / Phase 6 that offers Accept/Reject/Continue-
revising as options" — singular gate) and to AC30a/AC30b's `git rm` framing
(the durable artifact is committed before the gate fires; Reject performs a
true `git rm` of the tracked file). It also satisfies AC30c by relying on
the child's own gate code path — `/scope`'s orchestration layer (writing the
rejection-sub-shape Decision Record per AC12a/AC12b) observes the discard
commit SHA via read-only `git log` (the same pattern `/charter` uses for
`/strategy` Phase 5 Reject in its rejection sub-shape) without changing the
child's behavior. Option A is the lowest-blast-radius implementation that
honors all three drivers, matches the `/strategy` Phase 5.2 precedent, and
sidesteps the Q1 directory-move concern correctly (the move is a separate
lifecycle transition, not a Phase 6 concern).

## Implementation Sketch

The contract surface lands in three places per child, with no changes to
`docs/designs/current/` directory-move logic (out of scope for Phase 6).

**`/prd` Phase 4** (`skills/prd/references/phases/phase-4-validate.md`):

- Step 4.5 ("Present to User") — replace the 2-option AskUserQuestion
  (Approve / Request changes) with a 3-option gate:
  - **Approve** — current behavior (proceed to step 4.6's approved branch).
  - **Reject** — NEW branch: confirm rejection one more time, run
    `git rm docs/prds/PRD-<topic>.md`, run cleanup of `wip/prd_<topic>_*.md`
    (the same cleanup currently scoped to step 4.7), commit
    `docs(prd): discard PRD draft for <topic>`, exit.
  - **Continue revising** — renamed from "Request changes"; loops back to
    Phase 3 step 3.5 unchanged.
- Step 4.6 ("Handle Approval") — renumber or annotate to read "Handle
  Approve" since Reject and Continue-revising now have their own branches.
- Cleanup at step 4.7 — note that the Reject branch already ran cleanup
  inline (skip on Reject path).

**`/design` Phase 6** (`skills/design/references/phases/phase-6-final-review.md`):

- Step 6.7 ("Present for Approval") — replace the 2-option AskUserQuestion
  (Approved / Needs iteration) with a 3-option gate:
  - **Approve** — current step 6.8 If-approved branch.
  - **Reject** — NEW branch: confirm rejection, run
    `git rm docs/designs/DESIGN-<topic>.md`, run cleanup of
    `wip/design_<topic>_*.md` and `wip/research/design_<topic>_*.md` (the
    same cleanup currently scoped to step 6.9), commit
    `docs(design): discard DESIGN draft for <topic>`, exit. The discard
    commit lands on the same PR branch as the initial design commit (step
    6.6), producing a PR with two commits: the design and its discard.
  - **Continue revising** — renamed from "Needs iteration"; loops back to
    the relevant earlier phase unchanged.
- Step 6.8 ("Handle Approval") — annotate as the Approve branch only.
- Step 6.9 ("Clean Up wip/ Artifacts") — note that the Reject branch
  already ran cleanup inline (skip on Reject path).
- Step 6.6 ("Commit and PR") — UNCHANGED; the initial design commit still
  fires before the gate, so the Reject path's `git rm` operates on a
  tracked file (matching AC30b's `git rm` framing).
- NO interaction with the directory move (`docs/designs/` →
  `docs/designs/current/`); that's the Planned → Current transition,
  out of Phase 6's scope entirely.

**Verdict file convention** (referenced by `/scope`'s orchestration per
AC12a/AC12b, not authored by the children themselves):

- The children produce no verdict file. The durable signal is the discard
  commit SHA, captured by `/scope` via read-only `git log` after the child
  returns control (analogous to `/charter`'s `git log -1 --pretty=%H --
  docs/strategies/STRATEGY-<topic>.md` pattern for the rejection sub-shape).
- `/scope`'s state file at `wip/scope_<topic>_state.md` records the SHA
  in its `child_snapshots` block and writes the rejection-sub-shape
  Decision Record at
  `docs/decisions/DECISION-{prd,design}-<topic>-rejection-<YYYY-MM-DD>.md`.

**Sub-bullets per child for the SKILL.md contract documentation** — both
children's SKILL.md "Phase Execution" tables get a one-line annotation
naming the Reject branch as a recognized exit at the named phase (Phase 4
for `/prd`, Phase 6 for `/design`), with the commit-message format and the
fact that this contract surface is observable from outside (i.e., callable
by `/scope` per R23).

## Open Questions for Cross-Validation

- **D8 pattern-doc gate-type entry**: this decision assumes the Phase-N
  Reject contract is a child-level gate type (alongside the existing Phase
  4 / Phase 6 approval gates), not a new pattern-level gate. If D8 elevates
  the Reject contract to a pattern-doc gate type, this decision's
  implementation sketch may need to cite the pattern doc's gate-type entry
  for the contract surface vocabulary.
- **D9 (or related) on `/scope`'s `child_snapshots` post-rejection
  semantics**: this decision says the discard commit SHA is captured by
  `/scope` via read-only `git log` after the child returns. Whether
  `child_snapshots` records the discard commit SHA (the rejection) or
  stays frozen on the last successful artifact pointer is a separate
  question (Questions Deferred Q5 mentions this nuance). This decision
  assumes the SHA is captured into a Decision Record reference; the
  `child_snapshots` record shape is decoupled.
- **For `/design` specifically**: confirm whether the design PR (created
  at step 6.6 before the gate) should be closed on Reject or left open
  with the discard commit. Current Option A assumes the PR is left open
  with the design + discard commits visible, matching `/strategy`'s "PR
  shows the history" pattern. Closing the PR on Reject is a finer-grained
  question that the implementer can resolve when writing the SKILL.md
  delta; the contract surface (gate + discard commit) is settled by this
  decision.
