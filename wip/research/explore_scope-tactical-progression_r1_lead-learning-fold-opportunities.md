# Lead: learning-fold-opportunities

## Findings

This audit walks the ten non-folded observations and ten non-folded
learnings against SE7's surface area. Surface-area context comes from
the two prior round-1 findings docs in this exploration
(`...lead-pattern-inheritance-audit.md`,
`...lead-tactical-chain-gates.md`), which establish that:

- All four parent-skill pattern reference files transfer verbatim to
  `/scope`. SE7 authors a `/scope` SKILL.md following `/charter`'s
  seven-element template plus four phase reference files (chain
  orchestration, resume, finalization, state management).
- `/scope`'s tactical chain has four children (`/brief`, `/prd`,
  `/design`, `/plan`) and four child-invocation gates (Feeder-EITHER
  for `/brief`, Mandatory-with-auto-skip for `/prd`, Shape-dependent
  for `/design`, ALWAYS for `/plan`).
- SE7 ships motivating BRIEF + PRD + DESIGN + PLAN docs alongside the
  skill (mirroring SE4's `docs/briefs/BRIEF-shirabe-charter-skill.md`,
  `docs/prds/PRD-shirabe-charter-skill.md`, etc.). These docs ARE the
  primary fold landing sites for L4 / L9 / L11 / observation #11.

The "fold" question for each item is: does folding into the SE7
deliverable cost less than 2 hours of authoring discipline, AND can
SE7's surface area legitimately host the fold without substrate work?

### Disposition Table — Observations

| Item | Disposition | Target artifact | One-line justification |
|---|---|---|---|
| **#1 Message-loss / durable-state-as-source-of-truth** | Defer to SE12 (Track B) | — | Track B amplifier-layer item; folding requires substrate (durable message bus or context store). SE7 inherits the wip-yaml-md substrate verbatim and cannot fix this in v1. |
| **#2 Idle-notification noise** | Defer to SE12 (Track B) | — | Track B amplifier-layer item; idle-pings-vs-inbox-verdicts discipline already folded into pattern doc (parent-skill-pattern.md "Idle-Pings-Are-Not-Inbox-Messages Rule"). `/scope` inherits the rule verbatim. No additional fold opportunity. |
| **#3 File-existence checks in reviewer prompts** | **Fold into SE7 v1** | `skills/scope/references/phases/phase-2-chain-orchestration.md` (child-invocation-verification subsection) | Cheap (~30 min): when `/scope` dispatches a child invocation, the Team-Lead Operating Discipline already requires filesystem-evidence check (priority 1). Add a one-paragraph "structural file-existence check before consulting child verdicts" note specifically for `/design` and `/plan` outputs at `docs/designs/DESIGN-<topic>.md` / `docs/plans/PLAN-<topic>.md`. No pattern-doc edit; per-parent reference file extension. |
| **#4 Long coordinator prompts** | Already covered by SE7's natural shape | — | The SE7 SKILL.md follows the seven-element template with phase reference files for per-phase prose (R1's "progressive disclosure" discipline). The pattern itself solved this; SE7 inherits the solution. |
| **#5 Variable-cardinality discovery requires team-lead round-trip** | Defer to SE12 (Track B) | — | Track B amplifier-layer item; requires substrate (live-team-query primitive, lazy spawn). The pattern's team-shape declarator already names "variable-cardinality role types with an upper bound" as a contract (folded as L12); `/scope` is single-agent at the parent-itself layer so the round-trip doesn't apply within `/scope`. |
| **#6 Race conditions in message ordering** | Defer to SE12 (Track B) | — | Track B amplifier-layer item; requires substrate (message-ordering guarantees). `/scope`'s wip-yaml-md substrate has no race surface (state is single-writer per topic). |
| **#8 Task-list context switching** | Defer to SE12 (Track B) | — | Track B amplifier-layer item; requires substrate (separate parent vs team task lists). No fold opportunity in `/scope` v1 — `/scope` is single-agent. |
| **#9 Reviewer findings vs file-existence** | **Fold into SE7 v1** | `skills/scope/evals/evals.json` (one new eval scenario) AND `skills/scope/references/phases/phase-2-chain-orchestration.md` (review interpretation rule) | Cheap (~45 min): add a scope-eval scenario that distinguishes "reviewer says PASS but artifact missing" from "reviewer says PASS and artifact present". The pattern doc's Team-Lead Discipline already names filesystem evidence as priority 1; the fold is the explicit `/scope`-side reviewer-PASS-without-artifact treatment (treat as STALE not PASS). Inside-pattern Track A item; no substrate dependency. |
| **#10 Cross-skill resume = file handoff only** | Already covered by SE7's natural shape | — | `/scope`'s resume ladder inspects published-path artifacts (per R14 widened rule and `parent-skill-child-inspection.md` per-parent surface table). File handoff IS the v1 contract (codified in `single-team-per-leader-no-nested.team_primitive` consequence 2: "File-handoff between parents"). `/scope` is the consumer of this rule, not a candidate for changing it. |
| **#11 Worktree staleness mid-execution** | **Fold into SE7 v1** | `references/parent-skill-worktree-discipline.md` (NEW top-level reference) OR `skills/scope/references/operational-runbook.md` (parent-specific runbook) | Cheap (~1 hour): observation #11 IS named in the SE12 roadmap entry as a Track A inside-pattern item ("operational rebase discipline for long tactical-chain runs"). Tactical chains span longer than strategic chains (per `/plan`'s multi-pr mode creating issues for downstream `/work-on` runs), so worktree staleness bites `/scope` harder than `/charter`. Author as a runbook reference inside `skills/scope/references/` (avoids touching the four pattern references). Inside-pattern Track A; no substrate dependency. |

### Disposition Table — Untapped Learnings

| Item | Disposition | Target artifact | One-line justification |
|---|---|---|---|
| **L1 Single-pr value-gated heuristic** | Defer to SE12 (/plan polish) | — | This is `/plan`-side discipline (when to choose single-pr vs multi-pr based on value-gate analysis). Out of `/scope`'s surface area — `/scope` invokes `/plan` and passes through `/plan`'s existing input modes per "Parents do not extend children's input surfaces" rule. SE7 records `execution_mode` in state but doesn't decide it. |
| **L2 Substitution surfaces are orthogonal** | Already covered by SE7's natural shape | — | Pattern doc names two substitution surfaces (`storage_substrate`, `team_primitive`). `/scope` inherits both verbatim. The orthogonality property is a documentation observation about the pattern itself, not a per-parent fold. |
| **L4 Brief Mermaid diagrams as Phase 2/3 step** | **Fold into SE7 v1** | `docs/briefs/BRIEF-shirabe-scope-skill.md` (the BRIEF FOR `/scope`) | Already validated cheap: SE4's `BRIEF-shirabe-charter-skill.md` shipped with two Mermaid diagrams (flowchart LR for chain phases, flowchart TD for exit shapes). SE7's BRIEF for `/scope` should ship with analogous diagrams from the start. Authoring overhead ~30 min; no pattern surface change. This is a writing-style precedent fold, not a contract fold. |
| **L5 /work-on plan-outline mode** | Defer to SE8 (prerequisite) | — | This is `/work-on` surface area; SE7 explicitly does not modify `/work-on`. The lead's context names L5 as an SE8 prerequisite, not an SE7 fold candidate. |
| **L6 ci_outcome semantics** | Already covered by SE7's natural shape | — | The pattern doc's `ci_outcome` Semantics section names `passing` vs `failing_fixed` explicitly. `/scope` inherits verbatim. The lead's context says L6 was deferred to koto docs; it's not an SE7 fold target. |
| **L9 Pattern-level requirement tagging in PRDs** | **Fold into SE7 v1** | `docs/prds/PRD-shirabe-scope-skill.md` (the PRD FOR `/scope`) | Already validated cheap: SE4's `PRD-shirabe-charter-skill.md` tags every requirement `[pattern-level]` or `[/charter-specific]`. SE7's PRD for `/scope` does the same with `[pattern-level]` or `[/scope-specific]` tags. Authoring overhead ~15 min; no pattern surface change. This is a PRD authoring-discipline precedent fold — and arguably it MUST happen for SE7 since the pattern-level requirements have to stay identical across both `/charter` and `/scope`. SE7 should reuse `/charter`'s exact pattern-level R-numbers (R1, R3, R9, R10, R11, R12, R13, R14, R17a, R18, R19) and only add `/scope`-specific requirements with new numbers. |
| **L10 Reviewer coverage categories** | Defer to SE12 (/plan polish) | — | This is `/plan`'s 4-vs-5 reviewer category discipline. Roadmap SE12 entry explicitly names it as Track A item 3 ("reference-hygiene as a 5th /plan reviewer category"). Out of `/scope`'s surface area; SE7 doesn't author `/plan`. |
| **L11 Outline-number reference brittleness** | **Fold into SE7 v1** | `docs/plans/PLAN-shirabe-scope-skill.md` (the PLAN FOR `/scope`) AND `skills/scope/references/phases/phase-2-chain-orchestration.md` (invocation discipline against `/plan`) | Cheap (~45 min) with two landing sites. (a) SE7's own PLAN doc should use the `<<ISSUE:N>>` placeholder convention with explicit explanatory prose (mirroring `/plan` SKILL.md's "Placeholder Conventions" section) so cross-references survive issue-number assignment. (b) `/scope`'s Phase 2 chain-orchestration reference adds a note: when `/scope` re-enters mid-chain against an Active PLAN doc with unresolved `<<ISSUE:N>>` placeholders, it must not interpret outline-number references as stale. This protects re-entry from outline-number brittleness in `/plan`'s single-pr mode artifacts. |
| **L12 Team-shape declarator IS the substitution surface** | Already covered by SE7's natural shape | — | The pattern doc's "Team-Shape Declarator" section (folded in SE4) names this verbatim. `/scope` declares its team shape in its own SKILL.md following the prose form (v1 substrate). No per-parent fold work. |
| **L14 Single-team-per-leader produced positive properties** | Already covered by SE7's natural shape | — | This is an amplifier-layer note about why v1's team_primitive value works. The pattern doc's `team_primitive` section names the three consequences (inline-decision walks, file-handoff, upfront upper-bound roster) — that IS the encoding of L14. `/scope` inherits as a consumer. |

### Folds Already Captured in SE4 (Cross-Reference)

For audit completeness, these were folded in SE4 and inherit verbatim
to `/scope` via the pattern references — they do NOT need re-folding:

- **L3 Reviewer-vs-worker role distinction** — folded into the pattern
  doc's "Reviewer-shaped roles vs variable-cardinality worker role
  types" paragraph at the bottom of the Team-Shape Declarator section.
  `/scope`'s team-shape declaration (prose in SKILL.md per v1) names
  the two cardinality shapes separately.
- **L7 Discipline-vs-artifact decoupling thesis named** — folded into
  the pattern doc's Three Exit Paths section ("The three-exit contract
  operationalizes the discipline-vs-artifact decoupling thesis...").
  `/scope` inherits this framing for its three exit paths.
- **L8 Default-option wording as contract surface** — folded into the
  pattern doc's Required SKILL.md Structural Elements section ("The
  default-option wording at status-aware re-entry prompts is part of
  the contract surface, not a UX detail..."). `/scope`'s SKILL.md must
  include the literal-substring "Re-evaluate / Revise / Bail" against
  its PLAN surface (with status noun substituted — Active/Done instead
  of Accepted, per `/plan` lifecycle).
- **L13 Parents don't extend children's input surfaces** — folded
  into the pattern doc's Conditional Feeder Invocation Shape section.
  `/scope`'s chain-orchestration reference inherits this discipline:
  `/scope` invokes `/brief <topic>`, `/prd <topic>`, etc., never
  `/prd --thesis-shift` or `/design --from-scope-context`.
- **Observation #7 (Long coordinator silences without timeouts)** —
  subsumed by I-7 (Active Orchestration). `/scope`'s child invocations
  bind the 120s implementation-pass task class with 10-cycle patience.
- **Observation #12 (Team-lead never-go-idle)** — promoted to I-7.
  `/scope` inherits.

## Implications

### Count of Fold Items: Four

The audit recommends folding FOUR items into SE7 v1:

1. **Observation #3** — file-existence checks in child invocation
   verification (chain-orchestration reference file).
2. **Observation #9** — reviewer-PASS-without-artifact treatment (one
   eval scenario + chain-orchestration reference note).
3. **Observation #11** — worktree staleness runbook (new reference
   file; choice between top-level pattern reference and parent-specific
   reference — see Open Questions).
4. **L4 + L9 + L11** — three authoring-discipline folds in the SE7
   motivating docs (BRIEF Mermaid diagrams, PRD requirement tagging,
   PLAN placeholder discipline). Counted as one fold cluster because
   they share a target (SE7's own brief/prd/plan docs) and the
   authoring cost is small per-item.

### What This Means for SE7's PRD Requirement Count

SE4's PRD had ~21 requirements (R1, R2, R3, R4, R5, R6, R7, R7.5, R8,
R9, R10, R11, R12, R13, R14, R15, R16, R17a, R17b, R18, R19). Of
those, 11 are `[pattern-level]` and 10 are `[/charter-specific]`.

For `/scope`:

- **Pattern-level requirements inherit verbatim** — R1, R3, R9, R10,
  R11, R12, R13, R14, R17a, R18, R19. Eleven requirements reused by
  number to preserve cross-PRD comparability (per L9 fold).
- **`/scope`-specific requirements replace `/charter`-specific ones** —
  ten new requirements at the same R-numbers (R2, R4, R5, R6, R7, R7.5,
  R8, R15, R16, R17b) but with `/scope`-flavored content. Or `/scope`
  may need fewer (e.g., no `/comp`-equivalent R5; the four-child gate
  inventory may collapse to two requirements instead of `/charter`'s
  four R4/R5/R6/R7).
- **Fold-driven new requirements** — observation #3 fold may add a
  new `[/scope-specific]` requirement enforcing structural file-existence
  checks during child-invocation review. Observation #9 fold may add a
  new requirement requiring reviewer findings to gate against artifact
  presence. Net add: ~2 requirements (NOT 12).

**Net PRD requirement count for `/scope`: ~21-23 requirements.** Same
order of magnitude as `/charter`'s PRD. The folds are small additions
on top of the inherited pattern-level set, not a doubling.

### What This Means for SE7's DESIGN Component Count

`/charter`'s ship vehicle in shirabe#96 organized the design around
the SKILL.md's seven structural elements plus phase reference files.
The PR description mentions "Component 5" (reviewer-vs-worker), so
SE4's DESIGN doc structured around ~6-8 components. For `/scope`:

- **Pattern inheritance components** — 4 components covering the four
  parent-skill reference files (identical structure, parent-specific
  body fill).
- **`/scope`-specific components** — 4 components covering the chain
  orchestration (per-child gates), resume ladder body fill (4 children
  partial-run rows + 3 PLAN statuses), finalization (3 exit paths bound
  to `/scope` artifacts), state management (parent-specific fields
  including `execution_mode`).
- **Fold-driven new components / sub-sections** — observation #3 + #9
  fold goes into the chain-orchestration component as a sub-section
  ("Reviewer Verdict Discipline"); observation #11 fold goes into
  EITHER a new pattern-level component (if reference-file fold) or a
  new `/scope`-only component (if parent-specific runbook fold).

**Net DESIGN component count for `/scope`: ~8-10 components.** Same
order of magnitude as `/charter`'s DESIGN.

### Cumulative Authoring Overhead

Folding all four candidates adds roughly **3-4 hours of authoring
overhead** to SE7's BRIEF + PRD + DESIGN + PLAN + SKILL.md + phase
reference files. The baseline SE7 authoring cost (assuming SE4's
shape applies) is at least 1-2 weeks for the docs + skill body + 11
eval scenarios. Folding represents <5% authoring overhead for
demonstrably v1-shippable value.

### What Stays Deferred to SE12

Six observations (#1, #2, #5, #6, #8, #10) and four learnings (L1,
L5, L6, L10) stay deferred. All six observations are Track B
amplifier-layer items requiring SE2 substrate work; the four
deferred learnings are out of `/scope`'s surface area (`/plan` polish,
`/work-on` mode, koto docs). The deferral is correct under the
discipline-vs-artifact decoupling thesis: SE7 v1 ships the discipline
without forcing the production of the amplifier substrate.

## Surprises

### 1. L9 Fold Is Almost Mandatory, Not Optional

The pattern-level requirement tagging convention is a stronger
discipline than the original retrospective framed it. SE4 introduced
it in `PRD-shirabe-charter-skill.md` so reviewers can grep for
`[pattern-level]` and verify the pattern-doc edits cover all of them.
For SE7, if the PRD does NOT preserve the tagging convention, then a
reviewer cannot mechanically verify whether `/scope`'s pattern-level
requirements match `/charter`'s pattern-level requirements. The fold
is essentially required by the pattern itself; calling it an "untapped
learning" understates the gravity. Worth re-classifying L9 from
"untapped" to "established convention `/scope` MUST follow".

### 2. Observation #11 Has a Hidden Cost-of-Deferral Multiplier

Worktree staleness gets worse as chain length increases. `/charter`'s
strategic chain is 3 children (VISION + STRATEGY + ROADMAP).
`/scope`'s tactical chain is 4 children (BRIEF + PRD + DESIGN + PLAN).
Each child invocation involves a child's full Phase 0..N execution
(typically minutes to hours), so the worktree window grows from
`/charter`'s ~3-hour typical run to `/scope`'s ~6-hour typical run.
The probability of upstream changes during a `/scope` run is roughly
double; the cost of NOT folding observation #11 doubles
correspondingly. This makes #11 a higher-priority fold for SE7 than
the SE12 roadmap entry implies.

### 3. Observation #3 and #9 Are the Same Fold, Different Phases

Both observations are about reviewer-prompt discipline: #3 is the
upstream side (reviewer SHOULD check files exist), #9 is the
downstream consequence (when reviewer didn't, the PASS verdict is
unsafe). Folding them together as a single "filesystem-evidence-as-
priority-1" reinforcement in `/scope`'s chain-orchestration reference
captures both at once. The pattern doc already established the
priority ordering; `/scope`'s fold is a per-parent enforcement note,
not a pattern-doc edit.

### 4. L4 Already Happened in SE4 Practice

The SE4 retrospective named L4 (brief Mermaid diagrams) as "untapped",
but `BRIEF-shirabe-charter-skill.md` shipped with TWO Mermaid diagrams.
The "untapped" framing reflects the absence of a written convention,
not the absence of the practice. The fold for SE7 is therefore
trivially cheap (just author the same way) — and if SE12 ships a
`/brief` polish that codifies "diagrams welcomed in Phase 2/3 prose",
the fold landing site shifts from the SE7 doc to the `/brief`
references. This is the kind of fold where doing it once in SE7 v1
is faster than waiting for the polish PR.

### 5. The Real Defer-to-SE12 Set Is Smaller Than the Lead Implied

The lead's candidates-already-identified list included L4 / L9 / L11
plus observation #11. The audit confirms all four are good fold
candidates AND adds observation #3 + #9 (paired as a single fold)
making the total six fold items in three landing-site clusters. The
deferred set shrinks from "~14 untapped + 7 Track A" to "10 items
deferred for substrate or out-of-surface reasons" — the inside-pattern
Track A items folding-into-SE7-v1 is a cheap acceleration of SE12's
Track A work specifically.

## Open Questions

1. **Where does observation #11 land — pattern-level reference or
   `/scope`-only runbook?** Two valid placements:
   (a) New top-level `references/parent-skill-worktree-discipline.md`
   that all future parents inherit (and `/charter`'s SKILL.md gets
   amended in a follow-up to cite it).
   (b) `skills/scope/references/operational-runbook.md` that's
   `/scope`-only and SE12 generalizes later.
   Placement (a) is the right pattern-promotion arc but couples SE7 to
   a back-edit of `/charter`'s reference table. Placement (b) ships
   faster but creates a known re-home in SE12. Recommend (b) for SE7
   v1 — the worktree-staleness empirical evidence is tactical-chain-
   biased; generalizing to a top-level reference should wait for
   evidence from `/work-on` SE8 too.

2. **Should fold-driven new requirements get fresh R-numbers or be
   appended to existing ones?** If observation #3 fold adds a
   `[/scope-specific]` requirement enforcing structural file-existence
   checks, does it become R20 (new number after `/charter`'s R19) or
   does it append to an existing requirement like R8 (chain
   orchestration)? Fresh R-numbers preserve cross-PRD comparability
   per L9; appending shortens the requirement list. Recommend fresh
   R-numbers — preserves the L9 grep-friendly contract.

3. **Does folding observation #9's reviewer-PASS-without-artifact
   eval scenario require adding a new baseline-* scenario or a
   `/scope`-specific us-* scenario?** SE4's eval baseline (scenarios
   1-6) is designed for verbatim copy into future parents'
   `evals.json`. If observation #9's fold adds a baseline-* eval,
   SE7 should ALSO back-edit `/charter`'s evals.json to add the same
   scenario; if it adds a us-* scenario, SE7 owns it alone. Recommend
   us-* scenario for SE7 v1 — the back-edit to `/charter` is
   additional work that may not be worth coupling.

4. **Cost-of-fold for L11 — does `/scope`'s PLAN need explicit
   placeholder discipline, or does `/plan`'s own discipline cover
   it?** `/plan`'s SKILL.md already documents `<<ISSUE:N>>`
   placeholder conventions. If `/scope`'s PLAN doc consumes `/plan`'s
   convention verbatim, the fold is trivial (just use it). The
   chain-orchestration note in `/scope`'s Phase 2 reference about
   not-misreading-stale-placeholders is the load-bearing half of
   L11 — it's about re-entry behavior, not authoring. The fold is
   small either way.

5. **Should the cluster (L4, L9, L11) be three folds or one fold?**
   The audit counts them as one cluster because they share a
   landing site (SE7's own motivating BRIEF + PRD + PLAN docs) and
   share an authoring rationale (precedent following from SE4).
   Counted as one cluster, the total fold list is four items.
   Counted as three, total is six. Recommend "one cluster" framing
   for SE7's PRD's "Out of Scope" / "Decisions and Trade-offs"
   section so the discussion stays compact.

6. **Does the worktree-discipline fold need to articulate when it
   fires?** Pure operational documentation is cheap to author but
   easy to ignore. If observation #11's runbook entry includes a
   trigger condition (e.g., "after every child Phase N
   finalization", "before every child invocation"), the discipline
   becomes load-bearing and reviewer-checkable. If it doesn't, it's
   a footnote. Recommend articulating the trigger condition: "before
   each `/scope` Phase 2 child invocation, run `git fetch && git
   status` against the worktree; if upstream has new commits on the
   target branch, halt and surface the staleness". This makes the
   fold actionable.

## Summary

Six of twenty audited items (observations #3, #9, #11, and learnings
L4 + L9 + L11) fold cheaply into SE7 v1 with ~3-4 hours of authoring
overhead spread across SE7's own BRIEF/PRD/PLAN docs and `/scope`'s
chain-orchestration phase reference; the other fourteen items defer
correctly (six Track B items need amplifier-layer substrate, four
items sit outside `/scope`'s surface area, four already inherit
verbatim from SE4's pattern references). Folding adds roughly two
new requirements to SE7's PRD (~21-23 total, same magnitude as
`/charter`'s ~21) and one new sub-section to the chain-orchestration
design component; it does NOT double SE7's authoring effort. The
biggest open question is where observation #11's worktree runbook
lands — as a new top-level pattern reference (coupling SE7 to a
back-edit of `/charter`) or as a `/scope`-only runbook that SE12
generalizes later — and the recommendation is the latter, since
worktree-staleness empirical evidence is tactical-chain-biased and
should accumulate across `/scope` AND `/work-on` (SE8) before being
promoted to pattern-level.

---

**Visibility flag for downstream BRIEF (Public-repo handoff):** This
findings document cites only public-repo paths (`public/shirabe`) and
public artifacts (roadmap entry in vision is referenced by
SE-identifier and roadmap-line context only). The Track A vs Track B
taxonomy and the I-7 / I-6 named substitution surfaces are all
publicly committed in `references/parent-skill-pattern.md`. Safe to
inherit into a Public-shirabe BRIEF without redaction. The vision
roadmap's specific issue numbers (#492, #495, #514) are private and
SHALL be omitted from public-bound prose.
