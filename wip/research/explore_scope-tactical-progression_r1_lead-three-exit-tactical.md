# Lead: three-exit-tactical

## Findings

### Source-of-truth grounding

`/charter`'s three-exit contract is codified in two places: the pattern-level
"Three Exit Paths" section of
`public/shirabe/references/parent-skill-pattern.md` (lines 79-111) names the
exits at the pattern surface; `public/shirabe/skills/charter/references/
phases/phase-finalization.md` (746 lines) owns the parent-specific binding
including the R8 tie-break, the Reject-vs-Bail distinction, and the
clean-cancel fallthrough. The three exit-artifact templates live at
`public/shirabe/skills/charter/references/templates/
{decision-record-re-evaluation,decision-record-rejection,
abandonment-forced-marker}.md`.

The pattern-level framing (parent-skill-pattern.md lines 100-111) is
unambiguous on the underlying principle: "The three-exit contract
operationalizes the discipline-vs-artifact decoupling thesis as its
underlying principle: strategic conversation can be *disciplined* without
being forced to *produce*." Each exit demonstrates a specific decoupling
property — full-run produces, re-evaluation disciplines without producing,
abandonment-forced ends at a review surface rather than silently losing.

The tactical-chain question collapses to: **does the
discipline-vs-artifact decoupling apply at all when PLAN's "product" is a
set of GitHub issues that immediately materialize as work?** The
finding is yes, partially — at the PRD and DESIGN boundaries — and no at
the PLAN boundary. The asymmetry concentrates at PLAN.

### Tactical-chain artifact lifecycle states (load-bearing for re-entry semantics)

| Artifact | States | Source-of-truth |
|---|---|---|
| BRIEF | (entry preamble; ephemeral in /scope sense) | SE6 (shirabe#95) |
| PRD | Draft → Accepted → In Progress → Done | `skills/prd/references/prd-format.md` line 96 |
| DESIGN | Proposed → Accepted → Planned → Current → Superseded | `skills/design/references/lifecycle.md` lines 9-20 |
| PLAN | Draft → Active → Done | `skills/plan/references/quality/plan-doc-structure.md` lines 45-49 |

PRD's Accepted/In-Progress and DESIGN's Accepted/Planned states are
load-bearing for re-evaluation: an existing artifact at these states is a
**settled durable claim** the chain can choose not to re-author. This is
the exact shape of `/charter`'s row 5 trigger (Accepted/Active STRATEGY,
`phase-resume.md` line 144).

### Per-exit mapping: /charter → /scope analog

#### Exit 1 — full-run

**Direct analog. Inherits verbatim with slot-fill.** A tactical full-run
completes the chain through its terminal artifact (PLAN), which in
multi-pr mode also materializes GitHub issues. The `exit_artifacts`
listing in state simply becomes a longer ordered list — BRIEF (optional),
PRD, DESIGN (optional, see gate research lead), PLAN — instead of
STRATEGY+ROADMAP.

`phase-finalization.md` lines 73-96's AC11a/AC11b pattern (STRATEGY-only
vs STRATEGY+ROADMAP shapes) transfers directly: `/scope` has its own
shape variants (PRD-only-when-no-DESIGN-needed, PRD+DESIGN, PRD+DESIGN+PLAN,
etc.). The R9 conditional-field absence machinery transfers verbatim.

The AC24 validator pass-through pattern (lines 109-178) transfers
literally — `/scope` invokes `shirabe validate` against the terminal PLAN
(and likely against intermediate PRD/DESIGN at chain boundaries) before
declaring full-run.

#### Exit 2 — re-evaluation, re-evaluation sub-shape

**Inherits with multiplication.** The re-evaluation sub-shape applies at
each settled-upstream boundary in the tactical chain. Where `/charter`
has ONE boundary (existing Accepted/Active STRATEGY → Re-evaluate /
Revise / Bail triad at phase-resume.md row 5), `/scope` has TWO:

1. **PRD-boundary re-evaluation.** `/scope <topic>` invoked against an
   existing PRD at status Accepted (or In Progress). The Re-evaluate
   option produces `DECISION-prd-<topic>-re-evaluation-<date>.md`
   recording "requirements still hold; no revision warranted; the chain
   does not re-author the PRD or proceed to DESIGN/PLAN."

2. **DESIGN-boundary re-evaluation.** `/scope <topic>` invoked against an
   existing DESIGN at status Accepted (or Planned). The Re-evaluate
   option produces `DECISION-design-<topic>-re-evaluation-<date>.md`
   recording "architecture still holds; no revision warranted; the chain
   does not re-author the DESIGN or proceed to PLAN."

The `referenced_strategy` state field generalizes to
`referenced_upstream` or splits into `referenced_prd` and
`referenced_design`. The Decision Record template body (Context,
Decision, Options Considered, Consequences) transfers verbatim with
"STRATEGY" globally substituted to "PRD" or "DESIGN".

**Key asymmetry surface.** PRD's "Bet-Specific Falsifiability" claims (the
re-evaluation walk-through in `phase-finalization.md` lines 188-191) have no
direct PRD/DESIGN analog. PRDs have Acceptance Criteria; DESIGNs have
Decision Drivers and Considered Options. The pattern still holds (walk the
named commitments; ask whether they still hold), but the specific
falsifiability machinery doesn't transfer literally — it generalizes to
"walk the artifact's load-bearing claims".

#### Exit 2 — re-evaluation, rejection sub-shape

**Does NOT cleanly transfer. Largest asymmetry surface.** `/strategy`'s
Phase 5 Reject is a deliberate finalization judgment specific to
strategic bets — the author worked through `/strategy` to its terminal
phase and consciously chose to reject the Draft STRATEGY as "the bet is
wrong or unwarranted" (phase-finalization.md lines 226-229).

The tactical children's analogs are weaker:

- **`/prd` Reject** — Does /prd have a Phase 4 "reject the requirements"
  finalization? Inspection of `skills/prd/SKILL.md` Phase 4 (Validate, jury
  review) shows no explicit Reject sub-state; the jury either passes the
  PRD or surfaces revision requests. The "PRD doesn't merit existing"
  judgment isn't a /prd Phase 4 output today.
- **`/design` Reject** — Same shape. `/design` Phase 6 final review
  validates and either accepts or loops back to revision. No "design
  rejected; no design warranted" terminal verdict.
- **`/plan` Reject** — Phase 6 review either passes or loops back. No
  "implementation rejected; this work shouldn't ship" terminal verdict.

This is the asymmetry the lead question anticipated. **Tactical artifacts
are products of work-decomposition, not strategic-bet judgments.** A
rejected PRD means "we shouldn't build this thing"; a rejected DESIGN
means "this approach is wrong"; a rejected PLAN means... the issues
themselves are wrong, but at that point work usually proceeds anyway.

Two paths forward, both worth surfacing as open questions:

- **(A) Drop rejection sub-shape in /scope.** Tactical children don't
  have Phase-N Reject finalization verdicts, so the rejection sub-shape
  has no trigger. /scope's Exit 2 only takes the re-evaluation sub-shape.
- **(B) Add Phase-N Reject finalization to /prd and /design as a
  prerequisite for /scope.** This is a substantial extension of the
  tactical children's contracts — it gives them an explicit "reject this
  artifact as unwarranted" terminal verdict that /scope can capture as a
  rejection Decision Record. This would extend the discipline-vs-artifact
  decoupling into the tactical chain.

Option (A) is the smaller change; option (B) preserves contract symmetry
with /charter at the cost of new work in /prd and /design.

#### Exit 3 — abandonment-forced

**Direct analog with bigger host-artifact set.** The R8 tie-break
(phase-finalization.md lines 417-491) transfers verbatim: most-recently-
running child resolution via (1) last entry in `chain_ran`, (2) first
`planned_chain` entry with non-empty wip/ on disk, (3) clean-cancel
fallthrough.

The host-artifact-types section of `abandonment-forced-marker.md` (lines
85-109) lists STRATEGY/VISION/ROADMAP for /charter; for /scope it
becomes:

- **BRIEF** at `docs/briefs/BRIEF-<topic>.md` — force-materialized when
  `/brief` is the most-recently-running child at bail.
- **PRD** at `docs/prds/PRD-<topic>.md` — force-materialized when `/prd`
  is the most-recently-running child at bail.
- **DESIGN** at `docs/designs/DESIGN-<topic>.md` — force-materialized when
  `/design` is most-recently-running.
- **PLAN** at `docs/plans/PLAN-<topic>.md` — force-materialized when
  `/plan` is most-recently-running.

The HTML-comment marker shape (`<!-- charter-status-block: ... -->`)
needs a rename — likely `<!-- scope-status-block: abandonment-forced; ... -->`.
The placement rule (inside the artifact's existing Status section,
HTML-comment syntax so the host validator ignores it) transfers verbatim
across all four host types because all four have a Status section per
their own schema. Greppability invariant is preserved.

**One PLAN-specific consideration.** A force-materialized PLAN with the
abandonment marker is a Draft PLAN that did NOT reach Phase 7 (Creation)
and therefore did NOT create GitHub issues. This is *good* — the
abandonment is captured as a partial artifact without the action
consequence firing. The PLAN status `Draft` per
`plan-doc-structure.md` lines 45-49 maps cleanly here.

#### Clean-cancel fallthrough

**Inherits verbatim.** R8 step 3 (phase-finalization.md lines 450-474):
no `chain_ran` history AND no `planned_chain` entry has wip/ intermediate
on disk → no state file written, no terminal artifact, no `exit:` value.
A `/scope` Bail at the chain-proposal prompt with no prior progress ends
the same way `/charter`'s does.

### New exits the tactical chain may need

#### Candidate: "Issue-only" exit (existing PRD + DESIGN, only PLAN needed)

NOT a new exit shape — this is the **full-run case where /scope's
chain-proposal selects [PLAN] as the only child to run.** The
chain-proposal logic (analogous to /charter's R7.5) detects that the
PRD and DESIGN exist at Accepted/Planned and that the only outstanding
child is /plan; it proposes a single-child chain. The exit fires as
`exit: full-run` with `chain_ran: [/plan]` and `exit_artifacts: [PLAN]`.

This is **not** an Exit 2 re-evaluation — the chain *did* re-author
(by producing PLAN; PLAN didn't exist before). The re-evaluation
sub-shape requires no new artifact was produced. The PRD-and-DESIGN-
already-exist case produces a new artifact (PLAN) and uses the
existing PRD/DESIGN as upstream.

So no new exit; this is a full-run sub-shape with chain_ran shorter
than the full sequence. /charter has an analog: full-run with just
`/strategy` and not `/roadmap` when R7 gates don't hold.

#### Candidate: "Brief-only" exit (preamble landed, defer remainder)

`/charter` has no analog because its entry is a Phase 1 discovery, not a
separate artifact. `/scope`'s BRIEF is a separate artifact that may
exist independently (it's authored by /brief, a separately invocable
skill).

Two sub-questions:

1. **Is BRIEF a chain member or a feeder?** Per the parent-skill-pattern
   Conditional Feeder Invocation Shape (lines 114-147), feeders are
   side-channel children not strictly required. If BRIEF is a feeder,
   then "brief-only" is a clean-cancel with the feeder having already
   landed — no new exit shape needed. If BRIEF is a chain member, then
   landing only BRIEF and exiting is either abandonment-forced (if the
   chain was planned to go further and bailed) or a deliberate "scope
   discovery, defer build" judgment requiring new Exit 2 sub-shape.

2. **Does "produce BRIEF and stop" mean re-evaluation-equivalent
   discipline?** The scope-tactical-progression scope file
   (`wip/explore_scope-tactical-progression_scope.md` lines 36-42)
   notes /brief may have a "brief-just-landed" auto-skip we observed
   during SE4. If the canonical flow is "/scope produces BRIEF and asks
   whether to continue", then "Bail after BRIEF" with BRIEF as the
   terminal artifact is conceptually a re-evaluation: the BRIEF
   disciplined the scoping conversation, the author chose not to
   produce further artifacts.

This is a substantive open question that the tactical chain raises and
/charter does not.

### Where Decision Record re-evaluation fires MORE often in tactical chains

In `/charter`, Decision Records fire at one boundary (existing STRATEGY).
In `/scope`, they fire at **two boundaries** (existing PRD, existing
DESIGN) — and arguably a third (existing BRIEF if BRIEF is treated as
chain member). The intermediate artifacts are more granular than
STRATEGY, so the re-evaluation opportunity surface is larger.

Empirically this should mean: tactical chains produce MORE Decision
Records over time than strategic chains do. The discipline-vs-artifact
decoupling fires more often because there are more settled-upstream
hold-points where the decoupling is meaningful.

The phase-finalization.md row 5 "Re-evaluate / Revise / Bail" prompt
generalizes to row 5 (PRD-boundary) + row 5b (DESIGN-boundary), each
with its own Decision Record sub-shape. Row 5 vocabulary transfers
verbatim — the "default-option wording is part of the contract surface"
rule (parent-skill-pattern.md lines 269-273) holds.

### Existing artifacts at intermediate states — hold-points vs revision triggers

The lead's instruction 4 asks whether Draft PRD or Active DESIGN
constitute legitimate hold-points or always require revision.

**Draft PRD.** Per /charter's row 6 (Draft STRATEGY exists,
phase-resume.md lines 184-207), the prompt is two-option: "Continue
draft" vs "Start fresh". This is NOT a re-evaluation prompt; the Draft
state means the prior chain didn't complete, not that the artifact is
settled. The same shape transfers to /scope: Draft PRD → "Continue PRD
draft" vs "Start fresh chain". Exit is full-run (when continue
completes), abandonment-forced (when bail), or clean-cancel (when bail
with no progress).

**Active DESIGN.** Active DESIGN is `docs/designs/current/DESIGN-<topic>.md`
— it's a "current implementation reference" state, post-Planned. This is
analogous to /charter's "Active STRATEGY" (row 5). The Re-evaluate /
Revise / Bail triad fires.

**In Progress PRD.** PRD's "In Progress" status is the analog of /charter's
"Active STRATEGY" for PRD (the requirements are settled and the chain
moved on). Treat as Re-evaluate / Revise / Bail triad.

So the answer: **Draft states are continue-or-restart binary prompts;
Accepted/Active/Planned/In-Progress states are Re-evaluate/Revise/Bail
triads.** This matches /charter's row 5 vs row 6 distinction.

## Implications

### For /scope's phase-finalization.md

The phase-finalization.md outline becomes longer than /charter's 746
lines because the re-evaluation sub-shape multiplies by boundary count
(2-3x). Concrete additions over /charter:

1. **Exit 2 — re-evaluation, PRD sub-shape** — analogous to /charter's
   "Exit 2 — re-evaluation, re-evaluation Sub-Shape (US-2)" section
   (lines 179-217). Trigger: row-5-PRD prompt fires with Re-evaluate
   selected. State fields: `referenced_prd`, `decision_record_sub_shape:
   re-evaluation-prd`.

2. **Exit 2 — re-evaluation, DESIGN sub-shape** — analogous shape.
   Trigger: row-5-DESIGN prompt fires with Re-evaluate selected. State
   fields: `referenced_design`, `decision_record_sub_shape:
   re-evaluation-design`.

3. **Possible Exit 2 — BRIEF sub-shape** — open question (see Open
   Questions below).

4. **Possible Exit 2 — rejection sub-shape, /prd Phase N Reject** —
   requires /prd Phase N Reject contract to exist (option B above).

5. **Possible Exit 2 — rejection sub-shape, /design Phase N Reject** —
   requires /design Phase N Reject contract to exist.

6. **Exit 3 — abandonment-forced** transfers verbatim with extended
   host-artifact set (4 children instead of 3). The R8 tie-break
   procedure transfers verbatim.

7. **AC24 validator pass-through** generalizes — /scope invokes
   `shirabe validate` against PRD AND DESIGN AND PLAN as each completes.
   This is the chain-level validation gate /scope owns.

The Reject-vs-Bail distinction (phase-finalization.md lines 493-555) is
load-bearing AND has weaker tactical-chain triggers — see option (A) vs
(B) above. The principle (deliberate finalization judgment ≠ mid-chain
interruption) carries; whether tactical children expose deliberate
finalization rejection verdicts is the open question.

### For /scope's exit-artifact templates

Templates needed:

- `decision-record-re-evaluation-prd.md` — analog to
  `decision-record-re-evaluation.md`, "STRATEGY" → "PRD", "Bet-Specific
  Falsifiability" → "Acceptance Criteria" (or "requirements") in the
  Options Considered prose.
- `decision-record-re-evaluation-design.md` — analog, "STRATEGY" →
  "DESIGN", "Bet-Specific Falsifiability" → "Decision Drivers" or
  "Considered Options".
- `decision-record-rejection-prd.md` — only if option (B) is chosen.
- `decision-record-rejection-design.md` — only if option (B) is chosen.
- `abandonment-forced-marker.md` — analog with marker prefix
  `scope-status-block:` and host-artifact-types section extended to 4
  artifact types (BRIEF, PRD, DESIGN, PLAN).

The frontmatter and body structure of the re-evaluation Decision Record
template (status: Accepted; Status/Context/Decision/Options
Considered/Consequences sections) transfers verbatim with terminology
substitution; the prose-walkthrough convention transfers verbatim.

### For /scope's state-schema

`/charter`'s state schema (sketched in `phase-finalization.md` line 65
and detailed in `phase-state-management.md`) has fields like
`referenced_strategy`, `decision_record_sub_shape: re-evaluation |
rejection`. /scope's state schema needs:

- `referenced_prd` (gated by `decision_record_sub_shape:
  re-evaluation-prd`)
- `referenced_design` (gated by `decision_record_sub_shape:
  re-evaluation-design`)
- Possible `referenced_brief` (if BRIEF re-evaluation is a thing)
- Expanded `triggering_child` enum: `/brief | /prd | /design | /plan`
  (vs /charter's `/vision | /strategy | /roadmap`)
- R9 conditional-field gating transfers verbatim — each
  decision_record_sub_shape value gates a different conditional field
  combination.

## Surprises

### S1 — The rejection sub-shape has no clean tactical analog

The largest finding. /strategy Phase 5 Reject is a deliberate
finalization judgment ("the bet is wrong"). Tactical children's Phase N
review phases (PRD Phase 4 validate, DESIGN Phase 6 final review, PLAN
Phase 6 review) don't expose a "reject this artifact as unwarranted"
terminal verdict — they pass or loop back to revision.

This means option (A) — drop the rejection sub-shape in /scope — is
the path-of-least-resistance choice. It costs symmetry with /charter
but preserves the discipline-vs-artifact decoupling at the
re-evaluation boundary (which is where it concretely shows up in the
tactical chain anyway).

Option (B) — add Phase N Reject to /prd and /design — is a substantial
contract extension that may be premature for v1 /scope.

### S2 — Re-evaluation fires MORE often in tactical chains

/charter has one boundary; /scope has 2 (PRD, DESIGN) and possibly 3
(BRIEF). The re-evaluation Decision Record is a MORE common artifact in
the tactical chain than in the strategic chain. This inverts the lead's
opening framing ("strategic/tactical asymmetry concentrates" at one
spot) — the asymmetry actually concentrates at BOTH the rejection
sub-shape (which weakens or disappears) AND the re-evaluation sub-shape
(which multiplies). The two pull in opposite directions.

### S3 — Abandonment-forced is the SAFEST tactical exit

Counter to the lead's framing that PLAN is "action-binding" and
therefore tactical chains might lean full-run, the action-bindingness
of PLAN makes abandonment-forced *more* valuable: a force-materialized
Draft PLAN does NOT trigger Phase 7 issue creation, so the action
consequence is correctly suppressed when the chain bails. The
HTML-comment marker preserves the abandonment audit trail without
firing GitHub side effects. This is exactly what the
discipline-vs-artifact decoupling produces in the tactical case.

### S4 — "Issue-only" turns out not to be a new exit

The lead asked about an "Issue-only" exit (existing PRD + DESIGN, only
PLAN needed). It's not a new exit — it's full-run with a short
`chain_ran`. /charter has the analog: full-run with `chain_ran:
[/strategy]` and not `/roadmap` when R7 gates don't hold. The
chain-proposal step (the analog of /charter's R7.5) handles the
length-selection upstream of finalization.

### S5 — "Brief-only" is the genuinely new exit candidate

If /brief is a chain member (not a feeder), then a chain that produces
only BRIEF and stops is conceptually a re-evaluation of
"should-we-author-PRD-and-beyond" — but the BRIEF didn't exist before,
so it's also not a pure re-evaluation. This shape doesn't exist in
/charter. Whether /scope needs to name it as a distinct exit shape, or
whether it falls under full-run-with-chain_ran=[/brief], is an open
question (Open Questions below).

## Open Questions

### Q1 — Drop or build the rejection sub-shape?

**Decision required.** Two paths:

- **(A) Drop rejection sub-shape in /scope.** Tactical children don't
  expose Phase N Reject finalization verdicts. /scope's Exit 2 only
  takes re-evaluation sub-shapes (per-boundary). Smaller v1 surface.
- **(B) Add Phase N Reject to /prd and /design as a prerequisite for
  /scope.** Preserves contract symmetry with /charter. Substantial
  extension of /prd and /design contracts. Requires PRD-Reject and
  DESIGN-Reject Decision Record templates inside /scope.

The lead suggests this is where the asymmetry concentrates; the
finding is the asymmetry is **larger than expected** (the rejection
sub-shape doesn't transfer cleanly). User needs to choose A or B.

### Q2 — Is BRIEF a chain member or a feeder?

**Decision required.** If chain member: BRIEF-only-exit needs naming
(either as a full-run-with-chain_ran=[/brief] or as a distinct
"brief-only" exit). If feeder: BRIEF presence is part of Phase 1
discovery, not a chain boundary, and "brief-only" reduces to clean-cancel
with the feeder having landed independently.

The scope research file's "brief-just-landed" auto-skip observation
suggests BRIEF is treated as part of the chain (with an auto-skip rule
when it just landed), but the formal status (member vs feeder) is what
determines exit semantics.

### Q3 — Does /scope need a row 5 prompt PER boundary (PRD + DESIGN), or one consolidated prompt?

**Decision required.** Per-boundary (two prompts: row-5-PRD against
existing PRD, row-5-DESIGN against existing DESIGN) is structurally
cleaner and produces sub-shape-specific Decision Records. Consolidated
(one row-5 prompt that detects which boundary is settled and prompts
accordingly) reduces the ladder row count but couples sub-shape
selection into ladder logic.

/charter has one boundary so the question doesn't arise. /scope is
where the answer needs to be decided.

### Q4 — Do PLAN's "Active" and "Done" states deserve a re-evaluation prompt?

PLAN at status Active means GitHub issues exist and `/work-on` is
actively implementing. PLAN at status Done means implementation
completed. Re-invoking /scope against either state is unusual but
possible (e.g., "re-evaluate whether this completed work was
worthwhile"). /charter doesn't have an analog because STRATEGY's
"Active" is the operational state, not the post-implementation state.

User decision: does Active/Done PLAN trigger a Re-evaluate / Revise /
Bail prompt, or does /scope refuse to engage with these states and
direct the user to a different skill (/work-on, /release, etc.)?

### Q5 — Validator pass-through scope

`/charter`'s AC24 pass-through validates the Draft STRATEGY before
declaring full-run. `/scope` has multiple intermediate artifacts (PRD,
DESIGN) plus PLAN. Decision: does /scope validate ONLY the terminal
artifact (PLAN), or does it validate each intermediate as the chain
crosses boundaries (PRD before invoking /design, DESIGN before invoking
/plan, PLAN before declaring full-run)? The latter is stricter and
matches the inheritance pattern. The former is simpler.

## Summary

The three-exit contract transfers from /charter to /scope with the
re-evaluation sub-shape **multiplying by boundary count** (two
boundaries — PRD and DESIGN — instead of one) and the rejection sub-shape
**weakening or disappearing** because tactical children don't expose
Phase-N Reject finalization verdicts the way /strategy does. The main
implication is /scope's phase-finalization.md grows longer than
/charter's via per-boundary re-evaluation templates and Decision Record
sub-shapes, while the abandonment-forced exit transfers verbatim with
the host-artifact set extended to four. The biggest open question is
whether to drop the rejection sub-shape entirely (option A — smaller
surface, breaks /charter symmetry) or build Phase-N Reject contracts
into /prd and /design as a /scope prerequisite (option B — preserves
discipline-vs-artifact decoupling at full symmetry, substantial
upstream contract work).
