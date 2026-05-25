# Decision 6 — Resume-ladder body-slot fills (Slots 5/6/7) for /scope

**Tier**: Critical
**Author**: decision-researcher-6
**PRD source**: R11 resume ladder; AC15-AC18b; AC25
**Pattern source**: `references/parent-skill-resume-ladder-template.md`
**Precedent**: `skills/charter/references/phases/phase-resume.md`

## Question

For `/scope`'s resume ladder, fill the three parent-specific body slots of
the universal 9-row template:

- **Slot 5 (status-aware re-entry)**: Row ordering and prompt vocabulary
  for re-entry against settled or in-progress child docs across the PRD-
  boundary, DESIGN-boundary, and PLAN's three statuses, with AC17b's
  rule that DESIGN-above-PRD when both Accepted artifacts exist
  (most-downstream-first first-match-wins ordering).
- **Slot 6 (partial-child-run detection)**: One row per child
  (`/brief`, `/prd`, `/design`, `/plan`) with the exact `wip/`
  artifact filename pattern each row matches.
- **Slot 7 (feeder-doc-detected)**: Vacuous in v1 per Out-of-Scope #7
  (no feeder skill analogous to `/charter`'s `/comp`). Document
  explicitly as a future-proofing position.

## Recommended option

**Adopt the row ordering and prompt vocabulary the PRD's R11 already
inscribes verbatim (lines 658-670)**, refined here into per-slot row
tables with the prompt-vocabulary contract from AC17a-c and the
negative-vocabulary rule inherited from `/charter`'s US-2.

The PRD authored the ladder body at the requirement level; the design's
job is to **ratify the row ordering as the canonical body-slot fill,
fix the literal prompt substrings against AC17a-c, and document the
slot-7 vacuum so future-proofing reads correctly.**

### Slot 5 — Status-aware re-entry (8 rows)

The slot's row ordering follows the **most-downstream-first
first-match-wins** discipline: PLAN > DESIGN > PRD > BRIEF. This is the
natural reading direction for "the rightmost child that has produced an
artifact" and is the ordering AC17b ratifies for the DESIGN/PRD pair
("the resume ladder's ordering puts DESIGN above PRD; the
DESIGN-boundary fires first").

The slot fans across the four children's lifecycles, with PLAN's three
statuses splitting its row group into three sub-rows (Active, Done,
Draft):

| Row | Match condition | Action | Prompt vocabulary contract |
|-----|-----------------|--------|----------------------------|
| 5.1 | `docs/plans/PLAN-<topic>.md` frontmatter `status: Active` (multi-pr mode: also check GH issues tied to topic) | Refuse re-entry; redirect to `/work-on` | Literal substring "redirect to `/work-on`" with message identifying `/work-on` as the active-plan owner. MUST NOT contain "Re-evaluate / Revise / Bail". (AC17c) |
| 5.2 | `docs/plans/PLAN-<topic>.md` frontmatter `status: Done` | Refuse re-entry; redirect to `/release` | Literal substring "redirect to `/release`". MUST NOT contain "Re-evaluate / Revise / Bail". (AC17c) |
| 5.3 | `docs/plans/PLAN-<topic>.md` frontmatter `status: Draft` | Two-option prompt: continue PLAN draft into `/plan` OR start fresh (re-enter chain authoring from the PRD-or-DESIGN boundary) | "Continue draft" / "Start fresh". MUST NOT contain "Re-evaluate / Revise / Bail" (PLAN-Draft is not a re-evaluation boundary). |
| 5.4 | `docs/designs/current/DESIGN-<topic>.md` frontmatter `status: Accepted` AND no PLAN at any status | Three-option entry prompt against DESIGN-boundary; "Revise" path re-runs `/plan` against the DESIGN | **MUST** contain literal substring "Re-evaluate / Revise / Bail" (case-insensitive). MUST identify the boundary as the **DESIGN-boundary**. (AC17b) |
| 5.5 | `docs/designs/DESIGN-<topic>.md` frontmatter `status: Proposed` AND no PLAN | Two-option prompt: continue DESIGN draft into `/design` OR start fresh | "Continue draft" / "Start fresh". MUST NOT contain "Re-evaluate / Revise / Bail" (Proposed is not Accepted). |
| 5.6 | `docs/prds/PRD-<topic>.md` frontmatter `status: Accepted` AND no DESIGN at any status AND no PLAN | Three-option entry prompt against PRD-boundary; "Revise" path re-runs `/design` and `/plan` against the PRD | **MUST** contain literal substring "Re-evaluate / Revise / Bail" (case-insensitive). MUST identify the boundary as the **PRD-boundary**. MUST NOT contain "Continue / Start fresh". (AC17a) |
| 5.7 | `docs/prds/PRD-<topic>.md` frontmatter `status: Draft` AND no DESIGN AND no PLAN | Two-option prompt: continue PRD draft into `/prd` OR start fresh | "Continue draft" / "Start fresh". MUST NOT contain "Re-evaluate / Revise / Bail" (Draft is not Accepted). |
| 5.8 | `docs/briefs/BRIEF-<topic>.md` frontmatter `status: Accepted` or `Done` AND no PRD AND no DESIGN AND no PLAN | Auto-skip `/brief` in chain proposal (BRIEF is upstream input); proceed to Phase 1 with chain seeded from BRIEF | No "Re-evaluate / Revise / Bail" prompt — BRIEF is not a re-evaluation boundary. Implicit chain-proposal entry only. |
| 5.9 | `docs/briefs/BRIEF-<topic>.md` frontmatter `status: Draft` AND no PRD AND no DESIGN AND no PLAN | Two-option prompt: continue BRIEF draft into `/brief` OR start fresh | "Continue draft" / "Start fresh". |

**Note on the row count.** The slot expands into nine rows because PLAN
splits across three statuses (5.1-5.3) and the three remaining children
each have Accepted-or-Draft pairs (5.4-5.9). The PRD's R11 ladder lists
the rows in the same order; I've labeled them 5.1-5.9 within slot 5 for
implementation clarity. The literal flat-ladder row numbers (5-13) are
authored in the PRD verbatim; the per-slot labels here serve the design
doc's role of explaining the ordering rationale.

**The DESIGN-above-PRD ordering (AC17b) is load-bearing.** When both an
Accepted PRD and an Accepted DESIGN exist for the topic, the ladder
fires the DESIGN-boundary prompt (5.4), not the PRD-boundary prompt
(5.6). The reasoning: the DESIGN is downstream of the PRD; an author
re-entering with both present has already consumed the PRD into the
DESIGN, so the natural re-evaluation question is about the DESIGN, not
the PRD. The first-match-wins discipline encodes this without needing
to ask the author.

### Slot 5 — Vocabulary contract (load-bearing literal substrings)

The vocabulary contract inherits the negative-vocabulary rule from
`/charter`'s PRD US-2 (which `/scope`'s AC17a re-asserts):

- **The literal substring "Re-evaluate / Revise / Bail"** (case-
  insensitive) MUST appear on Accepted-boundary rows (5.4 DESIGN and
  5.6 PRD). The three options are co-equal; there is no recommended
  default.
- **The literal substring "Continue / Start fresh"** is explicitly
  **prohibited** on the Accepted-boundary rows (5.4 and 5.6).
  AC17a calls this out for PRD; AC17b extends the same prohibition
  to DESIGN by parity. Reason: "Continue / Start fresh" biases every
  chain toward revision and destroys the discipline-vs-artifact
  decoupling that motivates `/scope`.
- **Draft-status rows** (5.3 PLAN-Draft, 5.5 DESIGN-Proposed, 5.7
  PRD-Draft, 5.9 BRIEF-Draft) use **"Continue draft / Start fresh"**.
  This is the appropriate vocabulary for not-yet-settled artifacts
  (parallel to `/charter`'s row 6 vocabulary for Draft STRATEGY).
- **PLAN refuse-and-redirect rows** (5.1 Active, 5.2 Done) use the
  refuse-and-redirect vocabulary identifying the owning skill
  (`/work-on` for Active, `/release` for Done) per AC17c. These rows
  do NOT fire any Re-evaluate / Revise / Bail prompt — `/scope` is a
  chain-authoring skill, and active/done plans belong to the
  execution and release skills respectively.

### Slot 6 — Partial-child-run detection (4 rows)

The slot fires when a child's own `wip/` artifact exists on disk but
the child's durable doc has not been produced. **Row ordering follows
the same most-downstream-first discipline** so that a partial `/plan`
run takes precedence over a partial `/design` run (which itself takes
precedence over a partial `/prd` run, and so on).

| Row | Match condition | Action |
|-----|-----------------|--------|
| 6.1 | `wip/plan_<topic>_*.md` exists on disk AND no `docs/plans/PLAN-<topic>.md` at any status | Resume into `/plan` (re-invoke against its own resume ladder) |
| 6.2 | `wip/design_<topic>_*.md` exists on disk AND no `docs/designs/{,current/}DESIGN-<topic>.md` at any status AND no partial `/plan` | Resume into `/design` |
| 6.3 | `wip/prd_<topic>_*.md` exists on disk AND no `docs/prds/PRD-<topic>.md` at any status AND no partial `/design` AND no partial `/plan` | Resume into `/prd` |
| 6.4 | `wip/brief_<topic>_*.md` exists on disk AND no `docs/briefs/BRIEF-<topic>.md` at any status AND no partial `/prd` AND no partial `/design` AND no partial `/plan` | Resume into `/brief` |

**Match-pattern shape.** The glob `wip/<child>_<topic>_*.md` is used
because each child writes multiple phase-specific filenames during its
own multi-phase execution. `/scope`'s ladder does not need to know each
specific phase filename — the existence of ANY matching wip artifact is
sufficient signal that a partial run is in flight. The child's own
resume logic handles routing to the correct phase once `/scope`
re-invokes it. (Pattern matches `/charter`'s phase-resume.md row-7/row-8
filename-asymmetry-accommodation discipline: read what exists on disk,
not what documentation claims should exist.)

**R14 child-internals isolation holds.** The slot reads only the
existence of files matching the glob, not their contents. The two
filenames per child constitute the **minimum surface needed for
partial-run detection** and are the only `/scope`-side knowledge of
child `wip/` paths (matching `/charter`'s documented exception per the
R14-widened isolation rule).

**Action on resume into child** — `/scope` re-invokes the child with
the `--parent-orchestrated` flag (per Decision 3's signaling
mechanism), suppressing the child's own status-aware re-entry prompt
and letting the child's own resume ladder route to the appropriate
continuation phase.

### Slot 7 — Feeder-doc-detected (vacuous in v1)

**State: Vacuous.** The tactical chain has no feeder skill analogous
to `/charter`'s `/comp`. The slot is present at the pattern level
because the universal template names it (lines 28, 140-154 of
`references/parent-skill-resume-ladder-template.md`); `/scope` v1 fills
it with **zero rows**.

**Documentation requirement.** `/scope`'s `phase-resume.md` (and this
design doc's body-slot exposition) MUST explicitly state that slot 7
is intentionally empty in v1. The reason is documented in PRD's
Out-of-Scope section: "A feeder slot in the tactical chain v1. The
tactical chain has no feeder skill analogous to `/charter`'s `/comp`.
Pattern-level future-proofing keeps the feeder slot named in the
pattern doc; `/scope` ships without a populated feeder position. If a
future feeder lands (e.g., `/spike-feasibility`), the three-condition
gate template at the pattern level accommodates it without re-deriving
the contract."

**Future-proofing reference points.** Two candidate feeders surfaced
during exploration (`wip/research/explore_scope-tactical-progression_r1_lead-input-modes-resume-ladder.md`
findings + Open Question 5):

- **A `/spike-feasibility` feeder** that produces a SPIKE doc at
  `docs/spikes/SPIKE-<topic>.md` carrying a "decision crystallized"
  closure. If this ships post-v1, slot 7 row 7.1 would fire on detection
  of the SPIKE and seed Phase 1's chain proposal from its closure body.
- **A `/decision` feeder** invoked when the tactical chain surfaces a
  contested architectural choice that `/design`'s Phase 1 decomposition
  would otherwise consume. If this ships, slot 7 row 7.2 (or row 7.1
  in the SPIKE absence case) would fire on detection of an applicable
  Decision Record.

**Neither feeder is in `/scope` v1's scope.** The slot's presence in
the ladder body is documented as a placeholder so the future addition
is mechanical (add row 7.1; no re-derivation of the slot's contract).
The pattern template's authoring at lines 140-154 already specifies the
slot's behavior contract; `/scope` does not need to extend it.

### Full flat ladder (with all three slots labeled)

Combining the universal meta-ladder (rows 1-4, 8-9 of the template) with
slot 5 (rows 5.1-5.9), slot 6 (rows 6.1-6.4), and slot 7 (vacuous), the
flat literal ladder is:

```
 1. state file malformed                                  -> Hard error + offer Discard          [Meta-1]
 2. state file has exit field set                         -> Exit-value-specific re-entry prompt [Meta-2]
 3. state file exists, last_updated < 7d                  -> Resume at recorded phase            [Meta-3]
 4. state file exists, last_updated >= 7d                 -> Resume / Force-materialize / Discard[Meta-4]
 5. PLAN status: Active                                   -> Refuse, redirect to /work-on        [Slot 5.1]
 6. PLAN status: Done                                     -> Refuse, redirect to /release        [Slot 5.2]
 7. PLAN status: Draft                                    -> Continue draft / Start fresh        [Slot 5.3]
 8. DESIGN at current/, Accepted                          -> Re-evaluate / Revise / Bail (DESIGN)[Slot 5.4]
 9. DESIGN Proposed                                       -> Continue draft / Start fresh        [Slot 5.5]
10. PRD Accepted                                          -> Re-evaluate / Revise / Bail (PRD)   [Slot 5.6]
11. PRD Draft                                             -> Continue draft / Start fresh        [Slot 5.7]
12. BRIEF Accepted/Done                                   -> Auto-skip /brief in chain proposal  [Slot 5.8]
13. BRIEF Draft                                           -> Continue draft / Start fresh        [Slot 5.9]
14. wip/plan_<topic>_*.md exists                          -> Resume into /plan                   [Slot 6.1]
15. wip/design_<topic>_*.md exists                        -> Resume into /design                 [Slot 6.2]
16. wip/prd_<topic>_*.md exists                           -> Resume into /prd                    [Slot 6.3]
17. wip/brief_<topic>_*.md exists                         -> Resume into /brief                  [Slot 6.4]
                                                                                                 [Slot 7: vacuous]
18. On branch related to topic                            -> Resume at Phase 1                   [Meta-8]
19. On main or unrelated branch                           -> Start at Phase 0                    [Meta-9]
```

**19 rows total**: 6 meta (template rows 1-4 + 8-9), 9 slot-5, 4 slot-6,
0 slot-7. The earlier exploration estimate (15-20 rows) lands on this
ladder at 19 — consistent with the chain-position-collapse mechanic
analyzed in `wip/research/explore_scope-tactical-progression_r1_lead-input-modes-resume-ladder.md`
lines 91-95.

## Why this approach

### 1. The PRD authored the row ordering verbatim; design ratifies and adds the vocabulary contract.

The PRD's R11 (lines 651-673) lays out the 19-row literal ladder in
plain text. The design decision is not "what is the ordering" — the
PRD decided that — but "how do the body slots map to the row groups,
and what is the prompt vocabulary contract for each row."

The decision-record value-add here is:

- **Slot mapping**: which PRD rows belong to slot 5 vs slot 6 vs slot
  7 vs the meta-ladder. The PRD doesn't draw this boundary; the design
  doc must, so the pattern-doc edits (Decision 8) know which rows are
  pattern-level fixed vs parent-specific.
- **Prompt vocabulary contract**: AC17a/AC17b/AC17c specify literal
  substring requirements at the PRD level; this decision binds those
  substrings to specific rows, with the negative-vocabulary rule
  (prohibition on "Continue / Start fresh" at Accepted-boundary rows)
  applied to both DESIGN (5.4) and PRD (5.6) by parity.
- **Slot 7 future-proofing**: the PRD's Out-of-Scope item names the
  vacuum; the design ratifies the slot's presence in the pattern
  template and documents the placeholder reading.

### 2. Most-downstream-first first-match-wins is the natural ordering and AC17b ratifies it.

The exploration's chain-position-collapse mechanic
(`wip/research/explore_scope-tactical-progression_r1_lead-input-modes-resume-ladder.md`
lines 91-95, 124-127) ran the numbers: a naive 4×3 = 12-row table per
child×state is wrong because first-match-wins walks the chain from
terminal-most to earliest. A PLAN match short-circuits checking earlier
children. The PRD's R11 already encodes this; AC17b's "DESIGN above
PRD" is the smallest concrete instance.

The discipline holds across all three rows of structured analogy:

- Slot 5 fires on the rightmost durable artifact at any status; the
  ordering walks PLAN-statuses (5.1-5.3) → DESIGN-statuses (5.4-5.5)
  → PRD-statuses (5.6-5.7) → BRIEF-statuses (5.8-5.9).
- Slot 6 fires on the rightmost partial-child-run intermediate; the
  ordering walks `/plan` (6.1) → `/design` (6.2) → `/prd` (6.3) →
  `/brief` (6.4).
- Slot 7 is vacuous, so no ordering question arises.

### 3. PLAN's three-status split is the only place row count exceeds two-per-child.

PLAN is the only child whose three lifecycle statuses each warrant a
distinct ladder behavior (Active → `/work-on`, Done → `/release`,
Draft → continue/start-fresh). DESIGN, PRD, and BRIEF each collapse to
two rows (Accepted-or-equivalent / Draft-or-equivalent). The exploration
lead (lines 60-72) considered collapsing each Accepted/Draft pair to a
single row with branching action prose; the recommendation here keeps
two rows per child per `/charter`'s precedent for grep-checkability
(`/charter`'s phase-resume.md splits Accepted vs Draft STRATEGY into
rows 5 and 6 explicitly). AC eval scenarios for AC17a/AC17b/AC17c rely
on the row-level granularity for assertions.

### 4. Slot 7 vacuum is documented, not silent.

Leaving slot 7 unfilled in the design doc without explanation would
read as "the design author forgot." The PRD's Out-of-Scope item makes
the absence intentional; the design must mirror that. The future-
proofing reference points (SPIKE feeder, `/decision` feeder) are
named here so a future PRD-rev can add a row 7.1 mechanically.

## Considered options

### Option A (recommended): Adopt PRD's R11 ordering verbatim with slot labels + vocabulary contract

**Description**: Ratify the PRD's 19-row literal ladder as the design's
canonical resume-ladder body. Map rows 5-13 to slot 5 (sub-labeled
5.1-5.9 by lifecycle position), rows 14-17 to slot 6, leave slot 7
explicitly vacuous. Bind the literal prompt substrings ("Re-evaluate /
Revise / Bail", "Continue draft / Start fresh", "redirect to
`/work-on`", "redirect to `/release`") to specific rows.

**Pros**:
- Zero divergence from the PRD's authored intent.
- The slot labels make the pattern-doc edits in Decision 8
  mechanically clear (rows 5-13 fill slot 5, rows 14-17 fill slot 6).
- AC17a/AC17b/AC17c's literal-substring requirements bind cleanly to
  individual rows.
- The 19-row literal count matches the exploration estimate (lines
  91-95: "1.5× to 2× larger than `/charter`'s 10-row ladder," landing
  at 19 = 1.9× `/charter`'s 10).

**Cons**:
- Slot 5 has nine sub-rows, which is denser than `/charter`'s
  four-row slot-5 fill. Reviewers reading the design doc cold may need
  the slot-label scaffolding to track the structure.

### Option B: Collapse same-child Accepted/Draft pairs to a single row with branching action prose

**Description**: Reduce slot 5 from nine rows to five rows by merging
each child's settled/draft pair into one row whose action prose
branches on the live status. PLAN keeps three rows (Active, Done, Draft
each have category-distinct actions). DESIGN, PRD, BRIEF each collapse
to one row. Total slot-5 row count: 3 + 1 + 1 + 1 = 6. Slot 6 stays at
4. Total flat ladder: 16 rows.

**Pros**:
- More compact ladder; easier to read at a glance.
- Some readers find branching action prose more honest about the
  decision tree than separate rows.

**Cons**:
- Breaks AC17a/AC17b/AC17c's literal-substring grep-checkability. The
  ACs specify "the entry prompt MUST contain the literal substring
  'Re-evaluate / Revise / Bail'" — splitting between settled and draft
  rows lets the eval assertion be row-scoped; merging requires the
  assertion to be "the prompt fires when status == Accepted, and when
  it fires it contains the substring," which is more brittle.
- Breaks `/charter`'s precedent. `/charter`'s phase-resume.md (rows 5
  and 6) splits Accepted/Active vs Draft into separate rows. Following
  the same expansion granularity in `/scope` lets reviewers compare the
  two ladders side-by-side without mental translation.
- The compact form hides the chain-position-collapse mechanic that
  motivates the most-downstream-first ordering. The expanded form
  surfaces it.

**Why rejected**: AC17a/AC17b/AC17c are written as row-scoped
literal-substring contracts. Collapsing rows requires re-authoring the
ACs to status-scoped contracts, which is broader work than this
decision's scope.

### Option C: Add a populated slot-7 feeder row for SPIKE detection in v1

**Description**: Fill slot 7 with one row that detects
`docs/spikes/SPIKE-<topic>.md` and routes to Phase 1 with chain proposal
seeded from the SPIKE's "decision crystallized" closure. Total flat
ladder: 20 rows.

**Pros**:
- Closes the slot-7 vacuum with concrete v1 behavior.
- The `/explore` skill's "decision crystallized" closure surface
  exists today (per the exploration lead's findings at line 137:
  "`/explore` produces a SPIKE doc when an exploration crystallizes a
  decision"); a slot-7 row could consume it without new substrate.

**Cons**:
- The PRD's Out-of-Scope section explicitly defers the feeder slot to
  a future feature. Implementing it in v1 would re-scope the PRD,
  which is out of the design's authority.
- The exploration's Open Question 3 (lines 144-145) flagged the
  feeder-row count as undecided; resolving it inside the design doc
  bypasses the PRD-rev path the question intended.
- The pattern-level future-proofing already accommodates the slot
  without `/scope` populating it. Adding a v1 row creates a precedent
  that other parents must justify if they also leave slot 7 empty.

**Why rejected**: Out-of-scope per the PRD's explicit deferral. The
slot-7 vacuum is intentional, not accidental.

## Risks

### R1: AC17b's "DESIGN above PRD" ordering surprises authors who expect PRD-first.

**Surface**: An author with both an Accepted PRD and an Accepted DESIGN
invokes `/scope` expecting a PRD-boundary re-evaluation conversation and
instead gets a DESIGN-boundary prompt.

**Mitigation**: The DESIGN-boundary prompt's body MUST identify the
boundary explicitly (AC17b: "MUST identify the boundary as the
DESIGN-boundary") so the author understands which artifact is the
re-evaluation target. The "Revise" path on the DESIGN-boundary (5.4)
re-runs `/design` and `/plan`; if the author wants to re-evaluate
against the PRD instead, they can Bail and explicitly invoke `/prd`
manually (R13 first-class manual fallback).

**Residual risk**: Low. The boundary identification in the prompt body
plus the manual-fallback escape hatch covers the surprise case.

### R2: Slot 6 partial-child detection races slot 5 status-aware re-entry.

**Surface**: A child's durable doc exists at Accepted (triggering slot
5) AND the same child has a leftover `wip/` intermediate from a prior
run (triggering slot 6). First-match-wins means slot 5 fires first; the
`wip/` intermediate is ignored.

**Mitigation**: This is the intended behavior. Once a child has a
durable Accepted doc, the partial-run intermediate is stale by
definition — the child finished its run and emitted the durable
artifact; the leftover `wip/` files are scratch that should have been
cleaned up. The R14 child-internals isolation rule means `/scope`
doesn't need to clean up child `wip/` files; the child's own
cleanup is the child's responsibility.

**Residual risk**: Cosmetic. Stale `wip/` files accumulating in the
branch is a hygiene issue but doesn't affect `/scope`'s correctness.
The pre-existing wip-hygiene rule (CLAUDE.md) covers cleanup at PR
time.

### R3: The DESIGN directory-move (Proposed → Accepted) breaks the slot-5 row glob.

**Surface**: Row 5.4 looks at `docs/designs/current/DESIGN-<topic>.md`
for Accepted; row 5.5 looks at `docs/designs/DESIGN-<topic>.md` for
Proposed. The ladder needs to check both paths because the path itself
is part of the status surface.

**Mitigation**: Documented explicitly in the row table above (5.4 vs
5.5 differ in the path glob). The state-file `child_snapshots.design`
block (per Decision 5's resolution) records `path:` per snapshot and
gets updated on the directory move.

**Residual risk**: Low. The path-as-status-surface complication is
called out in the exploration lead's lines 131-133. Decision 5
(cross-boundary state-snapshot semantics) resolves the snapshot's path
tracking. This decision documents the row-level surface.

### R4: PLAN-Active row's multi-pr-mode GH-issue check expands `/scope`'s read surface beyond filesystem.

**Surface**: Row 5.1 checks PLAN-Active. In multi-pr mode, PLAN's
"Active" state may be reflected in a set of open GH issues tied to the
topic (per R5/R7 of the PRD and the exploration lead's lines 108-109).
This means `/scope` reads GH state, not just filesystem state, on
resume.

**Mitigation**: The state-file `plan_execution_mode` field (R10)
records single-pr vs multi-pr at `/plan`'s exit. Row 5.1's match
condition consults the state file first to determine which surface to
check. In single-pr mode, only the PLAN.md frontmatter matters; in
multi-pr mode, both the PLAN.md AND the GH issue surface matter.

**Residual risk**: Medium. The GH read surface is not local-only; CI
or offline contexts could misbehave. This is the R14-widened
"non-doc children" surface anticipated by Decision 4 of the design
parent skill pattern (per the exploration lead's lines 108-109). The
design doc must cite this widening in the pattern-doc edits
(Decision 8 territory).

## Implications for other decisions

- **Decision 3 (parent-to-child signaling)**: Slot 6 rows re-invoke
  the child with the suppression flag. The flag's name (per Decision
  3's resolution) appears in slot-6 action prose.
- **Decision 5 (child_snapshots semantics on Decision Record write)**:
  Slot 5's "Revise" path triggers a re-run of the downstream child; the
  child_snapshots block advances per Decision 5's rule. Slot 5's
  "Re-evaluate" path writes a Decision Record without invoking the
  child; the snapshot policy on that path is Decision 5's territory.
- **Decision 8 (pattern-doc edit surface)**: The slot-5 + slot-6 row
  count and the "refuse-and-redirect" meta-ladder shape for PLAN-Active
  / PLAN-Done extends the universal template's slot-5 contract. Decision
  8 must extend `references/parent-skill-resume-ladder-template.md`
  with a "refuse-and-redirect" sub-shape for slot-5 rows whose action
  is a redirect rather than a re-entry prompt.

## Implications for the SKILL.md and phase-resume.md

- **SKILL.md `## Resume Logic` ladder citation**: cite the 19-row flat
  ladder verbatim from the PRD's R11. The slot-label scaffolding lives
  in `phase-resume.md`, not in the SKILL.md (matching `/charter`'s
  precedent where SKILL.md cites the ladder shape and phase-resume.md
  carries the detailed body).
- **`skills/scope/references/phases/phase-resume.md`**: full row-by-row
  prose with the slot labels, the prompt-vocabulary contracts, the
  R3 (directory-move) and R4 (GH-issue surface) widenings, and the
  R14 child-internals isolation citation. Mirrors `/charter`'s
  phase-resume.md in shape.

## Evidence cited

- PRD R11 (lines 627-690), R10 schema (lines 576-625), AC15-AC18b
  (lines 1142-1202), AC25 (lines 1253-1257), Out-of-Scope feeder item
  (lines 1384-1391): `docs/prds/PRD-shirabe-scope-skill.md`
- Universal template slot definitions (lines 99-154):
  `references/parent-skill-resume-ladder-template.md`
- `/charter` precedent ladder (10-row body, slot-5 expanded into rows
  5-6, slot-6 expanded into rows 7-8, slot-7 vacuous, status-aware
  re-entry suppression contract): `skills/charter/references/phases/phase-resume.md`
- Exploration lead's chain-position-collapse mechanic (lines 56-95):
  `wip/research/explore_scope-tactical-progression_r1_lead-input-modes-resume-ladder.md`
- Exploration lead's surprises and open questions (lines 124-152):
  same file
