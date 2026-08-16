# Decision 3 — How each parent detects the `/explore` handoff

Topic: `scope-chain-mandatory-steps`. Governing requirements: R20, R22,
R23, R26. Repo root:
`/home/dgazineu/dev/niwaw/tsuku/tsuku+shirabe_inconsistencies-03b57366/public/shirabe/.claude/worktrees/scope-chain`.
All line numbers refer to files as they exist in that worktree.

## Question

`/explore` stops routing into leaf children and routes into `/scope` and
`/charter` instead. Each parent must recognize that a router handoff exists
for the topic and enter its own Phase 1 with that handoff's content in hand —
without skipping Phase 1, without invoking a child directly, and without
overriding a settled artifact already on disk.

The two parents present the clause with different furniture. `/scope`'s resume
ladder has an explicitly reserved, explicitly vacuous Slot 7
(`skills/scope/references/phases/phase-resume.md:80-84`). `/charter` numbers
its rows 1-10 rather than naming slots, its row 7 is already occupied by
`/strategy`'s partial-run check, and its own file explains why a new numbered
row was rejected once before: rows 9-10 are the shared meta-ladder tail and
"renumbering would disturb for `/scope` as well as `/charter`"
(`skills/charter/references/phases/phase-resume.md:264-269`).

## Decision Drivers

**D1 — One dispatch surface per parent.** The PRD's own framing of the
`/explore` Phase 0 defect (R16) is that "what SHALL NOT survive is two routing
surfaces in one skill reaching different conclusions." Any placement that
creates a second entry-decision authority alongside the resume ladder
reintroduces the defect class the PRD is removing.

**D2 — Re-entry protection is the stronger claim.** Every settled-artifact row
in both parents exists to stop a chain from overwriting accepted work. A
handoff carries conversation (R21) and cannot know what is on disk; it must
never outrank a durable artifact.

**D3 — Ordering should be computed, not restated.** `/charter` row 8's match
condition is already a hand-maintained conjunction of four negatives
(`phase-resume.md:295-298`). Every additional place that restates the ladder's
precedence by hand is a place that drifts.

**D4 — The child-internals isolation surface must not widen.** Both parents
bound their reads to three permitted sources plus a short, named list of child
`wip/` filenames (`skills/charter/references/phases/phase-resume.md:479-523`;
`skills/scope/references/phases/phase-resume.md:152-158`). The handoff is read
for content, not just existence — the first ladder match in either parent that
does so. A parent-namespaced handoff path keeps that read inside the parent's
own declared surface; a child-namespaced one would widen the isolation rule and
the closed write-target set at the same time
(`references/parent-skill-security.md:56-60` already covers "ancillary scratch
under the same `wip/<parent>_<topic>_*` prefix").

**D5 — Phase 0 is not optional setup.** Neither parent's Phase 0 creates or
switches a branch. `/scope`'s Phase 0 does slug validation, visibility
detection, `--upstream` validation, the stale `parent_orchestration:`
self-heal, and state-file creation
(`skills/scope/references/phases/phase-0-setup.md:272-284`); `/charter`'s does
slug validation, `--upstream` validation, and state-file creation
(`skills/charter/references/phases/phase-0-setup.md:32-39`). Any clause whose
action is "enter Phase 1" without qualification produces a chain with no state
file. This drives both the handoff clause's action text and the R26 answer.

**D6 — Renumbering cost is real and buys nothing.** The tail row numbers are
cited in the shared template (`references/parent-skill-resume-ladder-template.md:21-34`),
in both parents' SKILL.md (`skills/scope/SKILL.md:338`,
`skills/charter/SKILL.md:217`), in the row-6 rationale paragraph, in
`/charter`'s table of contents, and in both eval suites (`skills/scope/evals/evals.json`
eval 2 asserts no fall-through "to row 9"; `skills/charter/evals/evals.json`
eval 2 asserts the same "to row 10").

## Considered Options

### A. Fill Slot 7 in both, renumbering `/charter` and the template in lockstep

`/scope` gets its clause in the reserved Slot 7. `/charter` gets a new row 9,
its branch and main rows become 10 and 11, and the shared template's "9-row
ordering" block is rewritten to match.

Match condition, `/scope`: no state file, no Slot 5 match, no Slot 6 match, and
a handoff at the canonical path. `/charter`: the same shape spelled as the
file's four explicit negatives plus the handoff test.

Evaluation order: correct and free — the slot sits below the partial-child-run
slot and above the branch row in both parents, which is exactly where the
template puts slot 7 (`parent-skill-resume-ladder-template.md:28-30`).

Action: run Phase 0's setup obligations, then Phase 1 with the handoff
pre-loaded.

Template change: the numbered ladder block, the "rows 1-4 and 8-9 are the
meta-ladder" sentence, and the slot-7 body all move.

Blast radius: everything A′ touches (below) plus `/charter`'s TOC, the row-6
rationale paragraph, `/charter` SKILL.md:217, `/scope` SKILL.md:338, the
template's row block, and the two eval expectations that name the fall-through
row by number. The renumber is mechanical but wide, and the parents end up
numbered differently from each other anyway (9 rows versus 11), which is the
outcome the "same shape for every reader" claim was meant to prevent.

Rejected for cost without behavioral gain, not for being wrong. It is the
option a green-field implementation would pick.

### B. Slot 7 in `/scope`, inside row 8 in `/charter`

`/charter` puts the handoff test inside row 8's body and disambiguates there,
mirroring the mid-roadmap check row 6 already carries.

Match condition: row 8 matches when either `wip/vision_<topic>_scope.md` or the
handoff exists, then branches on which.

Evaluation order: identical to A′ in practice — row 8 sits above the branch
row, so the R26 interaction is resolved the same way.

Action: two different actions behind one row — resume into `/vision` for one
branch, enter `/charter` Phase 1 for the other.

Template change: none, which is its main attraction.

Blast radius: smallest of the three, and it repairs the row-8 collision in the
same edit.

Rejected on two grounds. First, the row-6 precedent does not transfer. Row 6's
disambiguation picks *which child to resume into* — one action class, two
targets, and the row's stated action ("Continue draft") stays true either way.
A handoff branch inside row 8 puts two different actions at two different
phases behind one row: resume into a child, or run the parent's own Phase 0 and
Phase 1. That is the shape that made row 8 misroute in the first place, applied
again deliberately. Second, it makes `/charter` SKILL.md:222-224 — "slot 7
(feeder-doc-detected) is unfilled because `/charter` has no feeder-doc case" —
false while the feeder behavior ships, and the correction has nowhere natural
to land. Documentation drift by construction is a poor trade for one saved
section.

### C. A pre-ladder check in both parents

The handoff test runs at parent entry, ahead of the resume ladder, on the
argument that a handoff is an entry condition rather than a resume condition.

Match condition: a handoff exists at the canonical path — plus, to be safe,
no state file, no settled child artifact in any status the parent's Slot 5
enumerates, and no child partial-run artifact. That conjunction is the point of
failure: it is exactly what rows 1-6 already compute, restated by hand outside
the ladder (D3), and it is the same conjunction-of-negatives shape that is
already wrong in `/charter` row 8.

Evaluation order: whatever the hand-written conjunction says. Get one negative
wrong and a handoff overrides an Accepted PRD, which is the worst available
failure (D2).

Action: same as A′, and C reaches it more naturally — the pre-ladder position
makes "this is a first invocation, so run Phase 0" the obvious reading rather
than something the clause has to assert.

Template change: the largest. It adds a pattern-level concept — a dispatch
surface that precedes the resume ladder — that every future parent inherits,
and it falsifies `/charter` phase-resume.md:3-8, which states the ladder is the
entry-point decision logic for any invocation that finds prior state on the
topic.

Rejected on D1. The genuine insight behind C — that a handoff run is a first
invocation, not a resume — is worth keeping, and A′ keeps it by making Phase 0's
obligations explicit in the slot's action rather than by building a second
router to express it.

## Recommendation

**A′ — fill Slot 7 in both parents, and place `/charter`'s slot-7 body as row
8.5 rather than renumbering the tail.**

`/scope` fills the position already reserved for it. `/charter` gains one row
between row 8 (`/vision` partial run) and row 9 (topic-related branch), which
is the slot-7 position the template defines, numbered 8.5 so rows 9 and 10 keep
their ordinals and every existing citation of them stays true. The fractional
number is not a sub-row of row 8 — `/charter` has no decimal rows today, and
the row carries a one-line note saying what the number means.

The shared template gets one amendment, in the "Ladder Shape" section: parents
may expand a body slot into more than one numbered row, and the meta-ladder
tail is identified by role (on-topic branch, then main or unrelated branch) and
by being last, not by ordinal. `/charter` already ships ten rows against the
template's nine, so this amendment describes what is true today as much as it
licenses row 8.5.

**Question 1 — a handoff and a settled PRD at the canonical path.** The settled
artifact wins. Slot 5 fires; Slot 7 is never reached, because first-match-wins
and slot ordering put the status-aware re-entry slot above the feeder slot.
The reason is D2 plus a property of the handoff itself: R21 forbids it from
carrying artifact existence, status, or hashes, so it has nothing to say about
the PRD on disk and cannot be the more current evidence. Two behaviors attach
to that verdict. The handoff is **not silently dropped**: the row that fires
states that a router handoff exists at the path and was not consumed, and
offers its problem statement as context for the Re-evaluate / Revise / Bail
choice. And the handoff file is **left on disk**, so a later Revise — which
starts a fresh chain — reaches Slot 7 on its own terms. The same rule applies
to every higher row, including `/charter` row 8 when a genuine `/vision`
partial run and a handoff both exist: the partial run is further along, it
wins, and the handoff is announced rather than consumed.

**Question 2 — what "pre-loaded" means.** The action is: run Phase 0's setup
obligations against the current worktree, then enter Phase 1 with the handoff's
content available to the discovery prompts. Concretely, for `/scope` Phase 1
(`skills/scope/references/phases/phase-1-discovery.md`):

| Phase 1 step | With a handoff |
|---|---|
| Framing-shift question (`:45-53`) | The handoff supplies the answer and its evidence. The question is still surfaced, as a confirmation — "the exploration concluded X; confirm or correct" — and the author's response is what gets recorded. Under `--auto`, the pre-supplied answer is taken and announced, matching the recorded-upstream `--auto` rule at `phase-resume.md:119-123`. |
| Topic-related child-doc globs (`:56-62`) | Unchanged. Filesystem read, every run. |
| Cold-start projected-PRD evaluation (`:70-88`) | Suppressed. A handoff run is not a cold start; the handoff's problem statement replaces the slug-keyword projection, and the `phase-1: empty-cold-start` short-circuit cannot fire because signal exists. |
| R6 predicate walk (`:148-248`) | P1 and P3 accept the handoff's estimate with its stated reasons. P2 is recomputed against the repo tree (`:200-202`). All three are re-evaluated against the real PRD by the post-`/prd` gate (`:90-106`) regardless. |
| Re-entry protection verdicts (`:107-131`) | Unchanged. Live frontmatter `status:` reads. |
| `planned_chain:` population (`:399-437`) | Unchanged. The whole chain, always; the handoff cannot shorten it. |
| Initial `child_snapshots:` capture (`:439-454`) | Unchanged. Live `git hash-object`. |
| Chain proposal and `Proceed / Adjust / Bail` (`:290-330`) | Unchanged and mandatory. |

For `/charter` Phase 1 (`skills/charter/references/phases/phase-1-discovery.md`):
the thesis-shift question at `:144` is pre-answered and still surfaced — the file
already says it is asked "for the framing it gives the conversation" even when
the outcome cannot change (`:154-155`) — while repo visibility (`:29-46`), the
existing VISION's status (`:151-153`), and the chain-proposal confirmation
(`:217-255`) all run unchanged. An identified upstream VISION arrives through
`--upstream`, not through the handoff (R25).

Both clauses carry the R21 sentence explicitly: artifact existence, frontmatter
status, content hashes, visibility, and upstream validation are re-read on
every run and are never taken from the handoff.

**Question 5 — R26.** Resolved, in two parts. The load-bearing part is
placement: Slot 7 sits above the branch row in both parents, so a router handoff
on a `docs/<topic>` branch fires the handoff clause and the branch row is never
consulted. That takes the interaction out of the router's path, which is what
R26 asks for.

The second part closes the residual defect cheaply. The branch row's stated
justification — "the branch context provides enough signal to skip Phase 0
setup" (`parent-skill-resume-ladder-template.md:87-89`) — does not survive
inspection: neither parent's Phase 0 touches branches (D5), and neither accepts
a bare invocation that could derive a slug from the branch name
(`skills/charter/references/phases/phase-0-setup.md:83-101`). So the row's
"skip" saves the author nothing and costs the chain its state file, its
visibility value, and its `--upstream` re-validation. Recommend restating the
branch row's action in the shared template as: run Phase 0's setup obligations,
which are idempotent, then continue into Phase 1 without pausing. No
renumbering, no eval change — only the action prose moves.

The honest consequence: with that restatement, the branch row and the main-branch
row take the same action in v1 and differ only in what they tell the author.
Keeping both is still right — collapsing them means renumbering (D6), the match
conditions carry different diagnostics, and the template holds the position for
a parent whose Phase 0 does branch work — but the convergence should be stated
in the template rather than discovered by the next reader.

## Proposed Ladder Rows

The handoff path is written below as `wip/scope_<topic>_handoff.md` and
`wip/charter_<topic>_handoff.md`. Decision 2 owns the literal string and the
schema; this decision needs only that the path is parent-namespaced, is one
canonical path per parent, and collides with no Slot 6 / row 7-8 pattern. If
Decision 2 lands a different name, only the literal changes here.

### `/scope` — replacing `phase-resume.md:80-84`

```markdown
## Slot 7 — Feeder-Doc-Detected (`/explore` router handoff)

**Match condition.** No Slot 5 row matched and no Slot 6 row
matched, AND a router handoff exists at
`wip/scope_<topic>_handoff.md`. The handoff is `/scope`'s own
parent-namespaced artifact, written by `/explore`'s router arm; it
is never one of the child-prefixed `wip/{brief,prd,design,plan}_*`
names Slot 6 reads.

**Action.** Run Phase 0's setup obligations against the worktree as
it is now — slug validation, visibility detection, `--upstream`
validation when the flag was supplied, the stale
`parent_orchestration:` self-heal, state-file creation — then enter
**Phase 1** with the handoff pre-loaded as discovery input. Record
`consumed_handoff: wip/scope_<topic>_handoff.md` in the state file.

The slot is a feeder, not a partial-child-run: it MUST NOT invoke
`/brief`, `/prd`, `/design`, or `/plan` directly, and it MUST NOT
skip Phase 1. The framing-shift question, the chain proposal, and
the `Proceed / Adjust / Bail` prompt all still run.

**What the handoff supplies, and what Phase 1 still computes.** The
handoff supplies the framing-shift answer with its evidence, the
problem statement and scope boundary, the decisions the exploration
settled, and an R6 predicate estimate for P1 and P3. Phase 1 still
runs the topic-related child-doc globs, the P2 new-component
cross-reference, every re-entry protection verdict, the initial
`child_snapshots:` capture, and `planned_chain:` population. Artifact
existence, frontmatter `status:`, content hashes, visibility, and
`--upstream` validation are re-read on every run and are NEVER taken
from the handoff — a handoff written last week describes a worktree
that no longer exists.

**Slug re-validation.** A slug recovered from the handoff's on-disk
path follows the same rule Slot 5 and Slot 6 matches follow (see
below): re-validate against `^[a-z0-9-]+$` before interpolation. The
handoff's *body* is untrusted input: it is read as conversation and
is never interpolated into an emitted command, and any path it names
is not a read target.

**When a higher row wins.** A settled artifact or a partial child run
outranks a handoff — re-entry protection is the stronger claim, and
the handoff carries no filesystem state that could contradict what is
on disk. When a higher row fires while a handoff exists, `/scope`
states that the handoff was found and not consumed, names its path,
and leaves the file on disk. It is not silently discarded.
```

### `/scope` — narrowed Slot 6 (R22), replacing `phase-resume.md:68-72`

```markdown
- **6.1 `/plan` partial run.** A `/plan`-authored artifact exists
  under `wip/plan_<topic>_*` (`_analysis.md`, `_decomposition.md`,
  `_dependencies.md`, `_manifest.json`, `_mapping.json`,
  `_milestones.md`, `_review.md`, `_decisions.md`,
  `_issue_<id>_body.md`). Re-invoke `/plan` against its own resume
  logic; do not re-run from scratch.
- **6.2 `/design` partial run.** `wip/design_<topic>_summary.md`,
  `wip/design_<topic>_coordination.json`,
  `wip/design_<topic>_decisions.md`, or
  `wip/design_<topic>_decision_<N>_report.md` exists. Re-invoke
  `/design`.
- **6.3 `/prd` partial run.** `wip/prd_<topic>_scope.md` or
  `wip/prd_<topic>_decisions.md` exists — the two artifacts `/prd`
  writes for itself. Re-invoke `/prd`.
- **6.4 `/brief` partial run.** `wip/brief_<topic>_discover.md` or
  `wip/brief_<topic>_context.md` exists. Re-invoke `/brief`.

Slot 6 reads a closed enumeration of the filenames these children
write, not an open glob over their `wip/` prefixes. A router handoff
is never a Slot 6 match: it lives at `wip/scope_<topic>_handoff.md`
and matches Slot 7.
```

Coverage check. `/prd` writes `wip/prd_<topic>_scope.md` at its own Phase 1
(`skills/prd/references/phases/phase-1-scope.md:74`) and
`wip/prd_<topic>_decisions.md` under `--auto`
(`skills/prd/SKILL.md:82`), and cleans `wip/prd_<topic>_*.md` at Phase 4
(`phase-4-validate.md:301`). A genuinely interrupted `/prd` run still matches
6.3 on both paths. Research files live under `wip/research/prd_<topic>_*` and
never matched the old glob either, so no coverage is lost. `/design`'s
`_summary.md` was the second exact-filename collision — `/explore`'s
`phase-5-produce-design.md` writes the same name — and the closed enumeration
plus the router's move to a parent-namespaced path removes it for new runs.

### `/charter` — ladder block, replacing `phase-resume.md:50-61`

```
1.   state file malformed                                  -> Hard error naming malformation + offer Discard
2.   state file has exit field set                         -> Exit-value-specific re-entry prompt
3.   state file exists, last_updated < 7d                  -> Resume at recorded phase_pointer (no prompt)
4.   state file exists, last_updated >= 7d                 -> Resume / Force-materialize / Discard prompt
5.   STRATEGY-<topic>.md Accepted/Active                   -> Re-evaluate / Revise / Bail prompt
6.   STRATEGY-<topic>.md Draft                             -> continue-or-start-fresh prompt
7.   wip/strategy_<topic>_discover.md exists               -> Resume into /strategy
8.   /vision's own partial-run artifact exists             -> Resume into /vision
8.5  wip/charter_<topic>_handoff.md exists                 -> Phase 0 setup, then Phase 1 with the handoff pre-loaded
9.   On branch related to topic                            -> Phase 0 setup, then Phase 1
10.  On main or unrelated branch                           -> Start at Phase 0
```

Row 8.5 is `/charter`'s slot-7 body, inserted between the partial-child-run
slot (rows 7-8) and the meta-ladder tail (rows 9-10). It is numbered
fractionally, not as row 9, so rows 9 and 10 keep the ordinals the shared
template, `/charter` SKILL.md, and both eval suites already cite. It is not a
sub-row of row 8.

### `/charter` — new row body, after row 8

```markdown
## Row 8.5 — `/explore` Router Handoff

**Match condition.** No state file exists at
`wip/charter_<topic>_state.md`, no STRATEGY exists at
`docs/strategies/STRATEGY-<topic>.md` in any status, no `/strategy`
partial-run artifact exists, no `/vision` partial-run artifact
exists, AND `wip/charter_<topic>_handoff.md` exists on disk. The
handoff is `/charter`'s own parent-namespaced artifact, written by
`/explore`'s router arm; it is never one of the child-prefixed
filenames rows 7-8 read.

**Action.** Run Phase 0's setup obligations against the worktree as
it is now — slug validation, `--upstream` validation when the flag
was supplied, state-file creation — then enter **Phase 1
(Discovery)** with the handoff pre-loaded. Record
`consumed_handoff: wip/charter_<topic>_handoff.md` in the state file.

The row MUST NOT resume into `/vision`, `/strategy`, or `/roadmap`.
Routing a handoff straight into a child is the defect row 8 carried
before the router change: it bypasses the thesis-shift question and
the chain proposal, leaves no state file, and means `/strategy` and
`/roadmap` are never scheduled. Phase 1 runs in full — the
thesis-shift question is surfaced with the handoff's answer offered
for confirmation, and the chain-proposal confirmation prompt still
fires.

**What the handoff supplies, and what Phase 1 still computes.** The
handoff supplies the thesis-shift answer with its evidence and
classification, the problem framing, and the decisions the
exploration settled. Phase 1 still reads repo visibility from
CLAUDE.md, still reads the existing VISION's frontmatter `status:`
at the published path, and still surfaces the chain proposal.
Artifact existence, frontmatter status, content hashes, visibility,
and `--upstream` validation are re-read on every run and are NEVER
taken from the handoff. An upstream VISION identified during
exploration arrives through `--upstream <path>` with the `VISION-`
basename enforced at Phase 0, not embedded in the handoff.

**Read-surface note.** The handoff sits under `/charter`'s own
`wip/charter_<topic>_*` prefix, so reading it does not widen the R14
child-internals isolation surface and does not add a child `wip/`
path to the two named in rows 7-8. Its body is untrusted input: read
as conversation, never interpolated into an emitted command, and any
path it names is not a read target. A slug recovered from its
on-disk path is re-validated against `^[a-z0-9-]+$` before
interpolation.

**When a higher row wins.** Rows 5-8 outrank this row. When one of
them fires while a handoff exists, `/charter` states that the handoff
was found and not consumed, names its path, and leaves the file on
disk — a later Revise starts a fresh chain and reaches row 8.5 on its
own terms.
```

### `/charter` — narrowed row 8 (R22), replacing `phase-resume.md:295-302`

```markdown
**Match condition.** No state file exists at
`wip/charter_<topic>_state.md`, no STRATEGY exists at the published
path, no `/strategy` partial-run artifact exists, AND `/vision`'s own
partial-run artifact exists on disk: `wip/vision_<topic>_scope.md`,
which `/vision` writes at its Phase 1
(`skills/vision/references/phases/phase-1-scope.md:79`), or
`wip/vision_<topic>_decisions.md`, which `/vision` writes under
`--auto` (`skills/vision/SKILL.md:109`).

A router handoff never matches this row. It lives at
`wip/charter_<topic>_handoff.md` and matches row 8.5. Before the
router change, `/explore` Phase 5 wrote its VISION handoff at
`wip/vision_<topic>_scope.md` — byte-compatible with `/vision`'s own
scoping artifact — and this row could not tell the two apart, so a
handoff resumed into `/vision` and bypassed `/charter` Phase 0 and
Phase 1 entirely. With the handoff parent-namespaced, `/vision` is
this row's only producer.
```

## Consequences

**Files that change, `/scope`.** `phase-resume.md` — Slot 7 body replaced, Slot
6 rows narrowed, the Slot 6 slug-re-validation paragraph at `:74-78` extended
to name Slot 7. `SKILL.md:358` ("Slot 7 is vacuous in v1") and `SKILL.md:415`
(reference table, "Slot 7 (vacuous)"). `SKILL.md:278-283`, the slug
cross-reference reading "Slot 5 or Slot 6". `phase-0-setup.md:233-244`, the
same rule restated locally. `phase-1-discovery.md`, a new subsection under
Discovery Prompt Structure recording which prompt inputs the handoff
pre-supplies. `references/state-schema.md`, the `consumed_handoff:` field.

**Files that change, `/charter`.** `phase-resume.md` — ladder block, TOC, new
row 8.5 body, row 8 match condition, the R14 isolation list at `:502-511` and
the Bounded Read Surface note at `:592-602` (both gain the handoff as a
parent-namespaced read, explicitly not a child internal), and the row-6
rationale at `:264-269`, whose "rows 9-10 are pattern-level rows renumbering
would disturb" sentence stays true and gains a clause saying row 8.5 is how
slot 7 was filled without disturbing them. `SKILL.md:222-224`, the sentence
asserting slot 7 is unfilled. `phase-state-management.md`, the
`consumed_handoff:` field.

**Shared template.** `references/parent-skill-resume-ladder-template.md` — two
edits. The Ladder Shape section gains a sentence licensing multi-row slot
expansion and identifying the tail by role rather than ordinal. Entry 8's
behavior text changes from "resume at the parent's Phase 1; the branch context
provides enough signal to skip Phase 0 setup" to running Phase 0's idempotent
setup obligations first. The slot-7 description at `:154-168` needs no change —
the router handoff is exactly the feeder-doc case it already describes.

**Evals, `/scope`.** Eval 3 (`baseline-child-internals-isolation`) enumerates
the Slot 6 patterns as the exhaustive child `wip/` read surface; the expectation
gains the handoff as a parent-namespaced read that is not a child internal, and
the Slot 6 enumeration in the expectation text moves from globs to the closed
filename list. Eval 2's "row 9" citation is unaffected. New cases needed: a
handoff alone fires Slot 7, runs Phase 0, runs Phase 1 in full, and invokes no
child directly; a handoff plus an Accepted PRD fires Slot 5 and announces the
unconsumed handoff; a handoff on a `docs/<topic>` branch fires Slot 7 rather
than the branch row.

**Evals, `/charter`.** Eval 3 names `wip/vision_<topic>_scope.md` and
`wip/strategy_<topic>_discover.md` as the only permitted child `wip/` reads
"beyond rows 7-8"; the expectation gains `wip/vision_<topic>_decisions.md` and
the parent-namespaced handoff. Eval 2's "row 10" citation is unaffected. New
cases mirror `/scope`'s three, plus one for a handoff coexisting with a genuine
`/vision` partial run, where row 8 wins and the handoff is announced.

**A migration edge that the narrowing does not close.** A worktree carrying a
pre-migration `wip/prd_<topic>_scope.md` or `wip/vision_<topic>_scope.md`
written by the old `/explore` is indistinguishable from the child's own
scoping artifact by path alone, and telling them apart would require reading
a child-namespaced file's body — a widening of the isolation surface that costs
more than the case is worth. Those orphans keep matching Slot 6.3 / row 8 and
resume into the child, which is what the old `/explore` did with them anyway.
The blast radius is bounded to worktrees that ran `/explore` before this change
and have not cleaned `wip/`. Record as a Known Limitation with that bound
stated.

**What gets better beyond the requirement.** `/charter` row 8's collision is
repaired rather than worked around, `/scope`'s Slot 6 stops being an open glob
over four `wip/` prefixes, and both parents stop having a ladder row that can
produce a running chain with no state file.

## Open Sub-Questions

1. **The handoff's literal path and schema** belong to Decision 2. This
   decision needs three properties: parent-namespaced under
   `wip/<parent>_<topic>_*`, one canonical path per parent, and no overlap with
   any Slot 6 / row 7-8 filename. The parent-namespaced prefix is also what
   keeps the handoff inside each parent's already-declared write-and-remove set
   (`references/parent-skill-security.md:56-60`), so Phase 4 cleanup needs no
   carve-out.

2. **`consumed_handoff:` needs a schema home.** Both parents' state schemas and
   the pattern-level `parent-skill-state-schema.md` need the field, its type,
   and whether it is conditional-gated. Left unspecified it becomes the next
   `chain_revised:` — written by a phase file, absent from the schema, read by
   nothing (R30).

3. **Whether the handoff is deleted on consumption or at Phase 4 cleanup.**
   Leaving it until cleanup is what makes the "announced but not consumed"
   behavior work across invocations; deleting on consumption prevents a second
   chain from re-consuming a stale handoff. Recommend leaving it and letting
   Phase 4 remove it, with `consumed_handoff:` in state as the guard against
   double consumption, but the interaction with the abandonment-forced cleanup
   carve-out is unexamined.

4. **Whether row 8.5's number should be 8.5 or a letter suffix.** Purely
   editorial, but `/scope` uses decimals for sub-rows *within* a slot, so a
   reader coming from `/scope` may read 8.5 as part of row 8. The one-line note
   in the ladder block is the mitigation; a different literal would need the
   same note.

5. **`/vision`'s and `/prd`'s own detection clauses** still name `/explore` as
   the producer of `wip/<child>_<topic>_scope.md` (`skills/vision/SKILL.md:96-101`;
   `skills/prd/references/phases/phase-1-scope.md:14`). R24 owns re-grounding
   them on the parent. The narrowed Slot 6 / row 8 conditions above assume that
   work lands; if it does not, the child skills keep telling a story about a
   producer that no longer exists, and row 8's "only producer is `/vision`"
   claim reads as contradicted by the child's own documentation.
