# Architecture Review: shirabe-progression-authoring

**Reviewer:** architecture-reviewer (Phase 6)
**Date:** 2026-05-24
**Verdict:** PASS with SHOULD-FIX items
**Design:** `docs/designs/DESIGN-shirabe-progression-authoring.md`

## Path verification (done first per coordinator brief)

| Referenced path | Exists? | Notes |
|---|---|---|
| `docs/prds/PRD-shirabe-charter-skill.md` | YES | Frontmatter upstream target verified |
| `skills/explore/references/phases/phase-2-discover.md` | YES | Decision 1 leaves it in place |
| `skills/explore/references/phases/phase-3-converge.md` | YES | Decision 1 leaves it in place |
| `references/cross-repo-references.md` | YES | Cited as precedent for top-level location |
| `references/decision-protocol.md` | YES | Cited as precedent |
| `references/pipeline-model.md` | YES | Cited as precedent |
| `references/wip-hygiene.md` | YES | Cited as precedent |
| `${CLAUDE_PLUGIN_ROOT}/references/...` resolution | CONFIRMED | `skills/explore/SKILL.md:251` uses this idiom — Decision 7 assumption holds |
| `## Repo Visibility:` header in shirabe CLAUDE.md | YES (line 6: `## Repo Visibility: Public`) | R12 mechanism is real |
| `skills/charter/` | DOES NOT EXIST | Expected — Stage 2 deliverable |
| `skills/scope/` | DOES NOT EXIST | Expected — Stage 4, separate PRD |
| `skills/work-on/` | EXISTS (current implementation) | Migration target named in design |
| `skills/decision/` | YES | Cited for inline-walk pattern (Decision 5) |
| `skills/design/references/phases/phase-6-final-review.md` | YES | Cited in coordinator brief; review protocol is real |
| `scripts/run-evals.sh` | YES | R18 substrate is real |
| `references/parent-skill-*.md` (4 new files) | DOES NOT EXIST | Expected — Stage 1 deliverables |
| `wip/research/design_shirabe-progression-authoring_decision_{1..4}_report.md` | YES (all 4) | Background context per coordinator brief |
| `wip/research/design_shirabe-progression-authoring_decision_5_report.md` | NO — file is at `wip/design_shirabe-progression-authoring_decision_5_report.md` (no `research/`) | Coordinator brief had this path right; my initial confusion was wrong path in brief footer. Same for decision 6. Minor brief-vs-actual inconsistency, not a design defect. |

**Zero fabricated paths in the design body itself.** Every committed-artifact path the design references either exists today or is an explicit Stage-1-through-Stage-3 deliverable. Brief-team reviewer-structural's gap (missing fabricated-path checks) is not repeated here.

## Question 1: Clear enough to implement?

**Verdict: PASS.** A `/charter` SKILL.md author could begin authoring from this design without re-deriving the contract.

Evidence:

- Component 2 (Parent-skill SKILL.md template) names seven concrete structural elements in order, each citing the specific pattern-level reference or PRD requirement that defines its content. An author opens SKILL.md and fills sections 1-7 by walking the list.
- Component 3 (Two-layer contract surface) names six invariants (I-1 through I-6) explicitly. I-1 through I-5 are described inline in Decision 2's Chosen subsection; I-6 is named as the unsatisfied invariant. Layer 2's reference implementation is concrete: 5-field schema, `wip/<parent>_<topic>_state.md` path, YAML-in-md serialization.
- Component 4 (Resume-ladder template) gives the universal 9-row ladder verbatim in Decision 3, naming which rows are pattern-level (1-4, 8-9) versus body-slot (5-7). Charter's author fills 5-7 with charter-specific prose; the rest port verbatim.
- Data Flow section gives an executable mental model: Phase 0 sets up state, per-phase loop writes phase_pointer, Phase N finalizes with R9 hard-check, resume reads state + child snapshots.

**SHOULD-FIX 1:** The design names the four new reference files (Component 1) and their content scope but does NOT name the section structure each file SHALL have. An author of `parent-skill-pattern.md` knows what to cover (contract surface, invariants, exit paths, integration shapes, substitution surfaces) but not how to organize it. Recommendation: add a one-line section-skeleton per file to Stage 1's deliverable description (e.g., `parent-skill-pattern.md` → §Contract §Invariants §Exit Paths §Substitution Surfaces §Feeder Shape).

**SHOULD-FIX 2:** Component 5 (team-shape declarator mechanism) describes WHAT a declaration must contain (fixed roles, variable-cardinality role types with upper bound) and partly demonstrates HOW (a `/charter` prose example). Decision 8 confirms prose is the v1 form. But there is no example declaration for a team-emitting parent — only for `/charter` which explicitly says "single-agent skill in the v1 core layer — no team." A reader trying to author `/design`'s team-shape declaration has no concrete model. Recommendation: add a worked example of a team-emitting parent's prose declaration (e.g., a sketch of how `/design`'s team shape would read: fixed roles `coordinator`, `architecture-reviewer`, `security-reviewer`; variable-cardinality `decision-researcher` with upper bound 9).

## Question 2: Missing components or interfaces?

**Verdict: PASS with NIT.** The five components and four interfaces cover the architectural surface.

Coverage check against the parent-skill pattern's load-bearing axes:
- Skill loading surface (R1): Component 2.
- State (R9, R10, R11): Components 3, 4.
- Child inspection (R14): Component 1's child-inspection file + Parent⇄child interface.
- Visibility (R12): Parent⇄workspace interface.
- CLAUDE.md surfacing (R17a): Stage 3 deliverable. Not a runtime component, correctly stays in implementation approach rather than architecture.
- Eval shipping (R18): Decision 4 specifies copy-paste-with-canonical-source; this is a delivery discipline not an architectural component, correctly framed in Decision 4 rather than Component-N.
- Team primitive substitution surface (Decision 5): Component 5.
- Storage substitution surface (Decision 2): Component 3.
- Conditional-feeder pattern (Decision 6): Parent⇄feeder-skill interface.

**NIT 1:** No explicit component for the manual-fallback mechanism (R13). The PRD's R13 specifies that the parent skill's `--auto` execution-mode flag MUST permit a manual fallback path. The design ratifies R13 verbatim (Decision 4) but does not surface manual-fallback as either a component or a named interface. It's implicit in Component 2 element 2 ("Execution-mode flag parsing"), but a future author writing a parent for a non-doc-emitting child may miss it. Recommendation: add one line to Component 2's element 2 spelling out that the flag-parsing requirement carries the R13 non-interference rule as a behavioral commitment.

**NIT 2:** No explicit named interface for **parent ⇄ git** (commit SHA lookups, blob hashes for fingerprinting, branch-name detection for the resume-ladder rows 8 and 9). Component 3 mentions git blob hash inside the dual-check drift detection invariant; Data Flow mentions `git log` for discard commit SHA; the Parent⇄workspace interface section mentions branch-related state in passing. But none names git as an interface boundary the parent depends on, which matters because (a) the v1 substrate is git-coupled, and (b) the amplifier-layer substitution may not be. Recommendation: name a "Parent ⇄ git" interface in the Key Interfaces section, listing the three git surfaces the v1 implementation uses (blob hash for fingerprint, log for discard SHA, branch name for ladder rows 8/9). This makes the git coupling explicit and frames it as another seam between core and amplifier layers.

## Question 3: Sequencing correctness?

**Verdict: PASS.** Stage 1 → Stage 2 → Stage 3 → (deferred) Stage 4 ordering is correct.

Stage 1 produces the four reference files; Stage 2's `/charter` SKILL.md cites them; Stage 3's CLAUDE.md surfacing only requires `/charter` to exist as a slash command. No hidden dependency between stages is missed.

**SHOULD-FIX 3:** Stage 2's `/charter` deliverable list includes `skills/charter/evals/evals.json` with "the shared eval baseline (slug rejection, malformed state file, child-internals isolation, visibility default) copy-and-adapted plus `/charter`-specific scenarios (US-1 through US-4)." Decision 4 says `/charter`'s eval file IS the canonical source from which `/scope` and `/work-on` copy. But there is no separate Stage 1 deliverable producing the canonical baseline — Stage 2 is both producing the canonical and adapting it. This is fine in isolation but the staging is muddled: the canonical baseline is a pattern-level artifact even though it physically lives inside `/charter`. Recommendation: either (a) split the baseline scenarios into a separate Stage 1 deliverable (e.g., `references/parent-skill-eval-baseline.md` describing the four scenarios in prose, even though the runnable file lives in `/charter`), or (b) explicitly note in Stage 2 that the baseline scenarios authored there are pattern-level and any future change requires updating all downstream parents.

**NIT 3:** Stage 3 mentions workspace `CLAUDE.md` and `shirabe/CLAUDE.md` updates without naming who owns the workspace `CLAUDE.md` (it lives in `tsukumogami/dot-niwa` for the public-half view, possibly elsewhere in the overlay). For a public design, this is fine; the design author can interpret "workspace CLAUDE.md" correctly. But a follow-on author for `/scope` or `/work-on` may need to know which file to edit. Optional polish: add a one-line note that the workspace CLAUDE.md surfacing edits happen in `tsukumogami/dot-niwa` (or wherever the canonical source lives).

## Question 4: Simpler alternatives?

**Verdict: PASS.** The strawman test on Decision 2's two-layer contract and Decision 3's 5-field minimum holds. The rejection rationales are substantive, not strawmen.

**Decision 2 strawman test.** Three alternatives are rejected:

1. **"Lock R10 schema; cross-branch as wip/-specific."** Rejected reason: "over-commits to whole-document YAML serialization, foreclosing structured-update or field-level-update substrates the amplifier layer may need." This is substantive — the design has thought about plausible amplifier-layer primitives and identified that whole-document YAML is the wrong granularity if the substrate offers structured updates. Not a strawman.
2. **"Cross-branch as expected but not invariant."** Rejected reason: weakens the forcing function on the amplifier layer; creates inconsistency with Decision 5's team_primitive framing. Substantive.
3. **"Pure invariant contract (no reference schema)."** Rejected reason: fragments the pattern across three parents with the same domain; convergence-by-default is the right prior. Substantive.

I tested a fourth alternative the design does NOT name: **"One-layer contract, invariants only, with PRD R10 cited as a recommended-but-not-required example serialization."** The argument for this: it preserves invariant-portability without privileging YAML-in-md as Layer 2. Counter-argument I worked through: this is functionally the "Pure invariant contract" alternative the design rejects in (3) above, with a recommendation footnote. The rejection logic holds — convergence-by-default for three parents in the same domain doesn't get materially better by demoting Layer 2 to a recommendation. So no genuine simpler alternative was overlooked.

**Decision 3 strawman test.** The 5-field minimum (`topic`, `last_updated`, `phase_pointer`, `exit`, `exit_artifacts`) is challenged. Two alternatives rejected:

1. **Verbatim ratification of full R10 schema.** Rejected because R9's null-prohibition conflicts with carrying `/charter`-specific conditional fields across parents. Substantive and correct — I verified this against `/charter`'s PRD requirements; R9 does prohibit null on conditional fields, so verbatim R10 inheritance for `/scope`/`/work-on` would force schema contortion.
2. **Pure invariant abstraction (no shared field names).** Rejected because it kills portability of acceptance criteria and provides rename flexibility no consumer asks for. Substantive.

I tested a third alternative: **"Three-field minimum (`topic`, `phase_pointer`, `exit`); drop `last_updated` and `exit_artifacts`."** The argument: `last_updated` is metadata; `exit_artifacts` is recoverable by re-reading `docs/`. Counter-argument: `last_updated` drives ladder row 4 (stale-session threshold), which is a pattern-level commitment in Decision 3's Chosen — so dropping it would force the ladder to invent a substitute. `exit_artifacts` is the only durable enumeration of what the chain produced; recovering by re-reading `docs/` requires the parent to remember which docs to look at, which is what `exit_artifacts` is for. So the 5-field minimum is not over-specified — each field is load-bearing.

**Is the prose form well-specified enough that a parent-of-the-parent agent can read it and translate to a TeamCreate call?** (Coordinator brief explicit question.) Verdict: PARTIALLY. The design describes the declaration content (fixed roles, variable-cardinality role types with upper bound) but gives a worked example only for the no-team case (`/charter`). See SHOULD-FIX 2 above. Without a worked example for a team-emitting parent, an agent doing the prose→TeamCreate translation has to infer the shape from the abstract description. A single sketch (e.g., a few lines showing how `/design`'s shape would read) closes the gap.

## Severity per finding

| Finding | Severity |
|---|---|
| SHOULD-FIX 1: Add section-skeleton per pattern-level reference file in Stage 1 | SHOULD-FIX |
| SHOULD-FIX 2: Add worked example of team-emitting parent's prose team-shape declaration | SHOULD-FIX |
| SHOULD-FIX 3: Clarify staging of shared eval baseline (canonical-source-but-physically-in-charter) | SHOULD-FIX |
| NIT 1: Name R13 manual-fallback non-interference rule explicitly in Component 2 element 2 | NIT |
| NIT 2: Name Parent ⇄ git as an explicit interface in Key Interfaces | NIT |
| NIT 3: Note which CLAUDE.md (workspace overlay source) Stage 3 edits | NIT |

No MUST-FIX findings.

## Summary

**PASS.** The design is clear enough to implement, the components and interfaces cover the load-bearing surface, the staging is correctly ordered, and the rejection rationales survive the strawman test. The two-layer contract surface (Decision 2), 5-field minimum schema (Decision 3), and named substitution variables (Decisions 2 and 5) form a coherent architectural seam — substrate-agnostic semantics above, substrate-bound implementation below — that earns its indirection cost by serving three parent skills. The three SHOULD-FIX items (reference-file section skeletons, team-shape worked example, eval-baseline staging clarity) are authoring-quality improvements rather than architectural defects, and can be addressed in the same edit pass that lands Stage 1's deliverables. No fabricated paths in the design body; every committed-artifact reference resolves or is a named future-Stage deliverable.
