---
status: Proposed
upstream: docs/prds/PRD-shirabe-scope-skill.md
---

# DESIGN: shirabe-scope-skill

## Status

Proposed

## Context and Problem Statement

`/scope` is the second parent skill landing in shirabe. The first
parent, `/charter`, shipped against the strategic chain
(`/vision → /strategy → /roadmap`) under the shared design
`docs/designs/current/DESIGN-shirabe-progression-authoring.md`,
which lifts the parent-skill pattern v1 into a contract surface
that future parents bind to without re-deriving. The technical
problem this design solves is binding the same pattern surface to
the tactical chain (`/brief → /prd → /design → /plan`) — a chain
whose shape diverges from the strategic chain at three load-
bearing points the pattern doc has no v1 language for.

The asymmetries the design must absorb without breaking the v1
pattern contract:

- **Two settled-upstream boundaries instead of one.** `/charter`'s
  re-evaluation exit fires at one point (an existing Accepted
  STRATEGY). `/scope` fires at two — an Accepted PRD and an
  Accepted DESIGN, with separate Decision Record sub-shapes and a
  resume-ladder ordering rule (DESIGN above PRD when both exist).
  The pattern's `re-evaluation` exit must gain a `boundary:`
  discriminator without changing the three-exit count.
- **No Phase-N Reject finalization on `/prd` or `/design` today.**
  `/charter`'s rejection sub-shape rides on `/strategy`'s Phase 5
  Reject. The tactical-chain children have no analogous reject
  contract. Either the rejection sub-shape silently disappears in
  `/scope` (an asymmetry inside the pattern contract that has
  nothing to do with the strategic/tactical distinction), or
  `/prd` and `/design` grow Phase-N Reject contracts as `/scope`
  prerequisites. SE7 takes the latter path; this design enumerates
  the contract extensions to both children.
- **A terminal child with two output modes.** `/plan`'s `single-
  pr` mode produces a self-contained PLAN doc; `multi-pr` mode
  produces a PLAN doc plus a GitHub milestone with issues. The
  pattern's `planned_chain`/`chain_ran`/`chain_skipped` triad
  doesn't capture output-mode selection; `/scope`'s state file
  needs a new `plan_execution_mode:` field so re-entry against an
  Active PLAN reads the correct surface.

`/prd`'s invocation gate sits on top of those three. `/charter`'s
three gate vocabularies (EITHER-signal, ALWAYS, shape-dependent)
don't fit `/prd` cleanly. `/prd` is mandatory unless an Accepted
PRD already exists; that auto-skip is real and load-bearing. The
pattern's gate vocabulary needs a fourth entry
(Mandatory-with-auto-skip) so the gate is named honestly inside
the pattern doc, not jammed into a misnamed third gate.

System boundaries touched by this design:

- `skills/scope/SKILL.md` (new) — the loadable skill body, with
  the seven pattern-level structural elements R1 names and a body
  prose section per `/scope`-specific requirement (R2, R4-R8,
  R15-R23).
- `references/parent-skill-pattern.md` (edit) — add the fourth
  gate type (Mandatory-with-auto-skip) to the gate vocabulary,
  with `/prd`'s gate as the canonical example.
- `references/parent-skill-state-schema.md` (edit) — add the
  `boundary:` and `plan_execution_mode:` conditional-field
  semantics (with I-5 absent-when-ungated bindings).
- `references/parent-skill-resume-ladder-template.md` (edit) —
  document the two-boundary re-evaluation ordering rule (DESIGN
  above PRD) and the PLAN-status-aware refuse-and-redirect rows
  (Active → `/work-on`, Done → `/release`).
- `references/parent-skill-child-inspection.md` (no edit needed)
  — the per-parent surface table already covers doc-emitting
  children; `/scope`'s four children are all doc-emitting and
  fall under the existing row.
- `references/parent-skill-worktree-discipline.md` (new) — a
  top-level reference that captures R21's worktree-staleness
  trigger condition as shared infrastructure both `/charter` and
  `/scope` cite. `/charter`'s SKILL.md gains a follow-up reference-
  table citation in a back-edit.
- `skills/prd/SKILL.md` + phase references (edit) — ship the
  Phase-N Reject finalization contract at `/prd`'s Phase 4 (per
  R23 and AC30a).
- `skills/design/SKILL.md` + phase references (edit) — ship the
  Phase-N Reject finalization contract at `/design`'s Phase 6
  (per R23 and AC30b).
- `skills/scope/evals/evals.json` (new) — eval scenarios covering
  US-1 through US-6 (per R18 and AC24b).
- Workspace and shirabe `CLAUDE.md` — surface `/scope` entry
  triggers (R17a, R17b); shirabe's CLAUDE.md gains a "Tactical
  Chain Entry: /scope" section paralleling the existing
  "Strategic Chain Entry: /charter" section.

Existing architecture this design inherits without alteration:

- The two-layer contract (Layer 1 semantic invariants I-1 through
  I-7; Layer 2 reference implementation under the v1 substrate
  identifiers `wip-yaml-md` and `single-team-per-leader-no-
  nested`) carries verbatim from
  `DESIGN-shirabe-progression-authoring.md`. `/scope` v1 binds
  the same substrates.
- The pattern's seven semantic invariants stand as `/charter`
  ratified them; `/scope` adds gate vocabulary and one new
  top-level reference but does not edit the invariants. I-6
  (cross-branch resume) remains the named-but-unsatisfied
  invariant the amplifier-layer migration closes; `/scope`'s
  state file is branch-coupled in v1.
- The team-lead operating discipline (the 5-step sleep-check-
  nudge loop encoded as I-7) binds `/scope` at the child-
  dispatch layer; `/scope` v1 is single-agent at its own layer
  (no peers dispatched at the `/scope`-itself layer), so the
  binding is vacuous at the parent-itself layer and concrete at
  the child-skill dispatch layer (each `/brief`, `/prd`,
  `/design`, `/plan` invocation is a dispatch in the discipline
  sense).

## Decision Drivers

The drivers below combine PRD-derived constraints (from
`PRD-shirabe-scope-skill.md` Requirements and Acceptance
Criteria) with implementation-specific constraints the PRD does
not surface explicitly. Drivers are ordered from most-binding to
least.

1. **Pattern contract symmetry across both parent skills.** The
   parent-skill pattern v1 has only one ground-truth example
   (`/charter`). `/scope` shipping is what ratifies the pattern
   for the next two parents (`/work-on` migration, future
   tactical parents). Any asymmetry left unaddressed in `/scope`
   compounds across SE8/SE9/SE12. Per PRD Decision 1, the design
   chooses full symmetry over narrow shipping: the rejection
   sub-shape, the Mandatory-with-auto-skip gate, the worktree-
   discipline reference all land at the pattern level.

2. **L9 pattern-level requirement-tagging traceability.** The PRD
   tags every requirement `[pattern-level]` or `[/scope-
   specific]` so reviewers can grep-verify pattern-doc edits.
   The design MUST mirror this distinction in its Solution
   Architecture: components labeled as pattern-doc edits cover
   the eleven pattern-level requirements (R1, R3, R9, R10, R11,
   R12, R13, R14, R17a, R18, R19); components labeled as
   `/scope` body slots cover the fifteen `/scope`-specific
   requirements (R2, R4, R5, R6, R7, R7.5, R8, R15, R16, R16.5,
   R17b, R20, R21, R22, R23). 1:1 traceability is the design's
   reviewer-checkability surface.

3. **Two-substrate respect for the v1 core layer.** `/scope`
   ships against the existing core-layer substrates:
   `storage_substrate: wip-yaml-md` (state at
   `wip/scope_<topic>_state.md` as YAML-in-.md), `team_primitive:
   single-team-per-leader-no-nested` (no nested teams; inline
   decision walks; upfront upper-bound roster). Implementation
   choices that would require amplifier-layer substrates are
   out of scope for v1.

4. **Six user stories as the eval surface.** Per R18 and AC24b,
   `skills/scope/evals/evals.json` MUST cover US-1 through US-6.
   The design's architecture must make each story
   eval-reachable: the chain-proposal output (R7.5) must contain
   literal-grep-checkable substrings, the state file's
   `exit:`/`boundary:`/`decision_record_sub_shape:` fields must
   be observable post-run, the abandonment-forced HTML-comment
   marker must be schema-compliant.

5. **Cross-boundary resume across four child positions plus three
   PLAN statuses plus DESIGN's directory-move lifecycle.** The
   resume ladder (R11) is the most complex pattern component
   `/scope` ships against. The ladder must consult the state
   file, four child snapshots (status + content-hash dual-check
   per R10), four `wip/{child}_<topic>_*` partial-run signals,
   and emit refuse-and-redirect rows for PLAN-Active (→
   `/work-on`) and PLAN-Done (→ `/release`). The ladder is the
   surface where most contract-violation bugs would surface; the
   design must keep the row ordering reviewable.

6. **Manual fallback as first-class steady-state behavior.** R13
   binds: a child invoked directly outside `/scope` MUST leave
   identical externally-visible surfaces. The design must NOT
   add hooks, marker files, or coupling that would distinguish
   in-chain from out-of-chain invocations on the durable
   artifact. Child-snapshot drift detection (status OR
   content-hash differs) is the only allowed signal the parent
   reads on resume.

7. **PRD-defined design-altitude open questions land in this
   doc.** Five questions in the PRD's "Questions Deferred to
   Design" section (Phase-N Reject placement; R6 shape-predicate
   evaluation mechanism; PLAN-status-aware signaling to `/plan`;
   the worktree-discipline reference's exact prose; cross-
   boundary state-snapshot semantics) are explicit design-team
   territory. Each must be resolved here, not punted.

8. **Tactical chain spans longer than strategic.** Four children
   per full run vs three; requirements/design churn faster than
   thesis. Two implementation-specific consequences: (a)
   `--max-rounds=N` default of 5 instead of `/charter`'s 3 (per
   R16.5), and (b) the worktree-staleness check trigger fires
   before each Phase 2 child invocation (per R21) rather than
   once per parent invocation.

9. **Public-visibility content governance.** shirabe is a public
   repo. The design MUST NOT reference private resources, pre-
   announcement features, or competitive material. The upstream
   PRD is public; this design is public; both follow the
   public-content discipline shipped at `skills/public-
   content/SKILL.md`.

10. **wip-hygiene rule.** wip/ files are non-durable and cleaned
    before merge. The design MUST NOT reference any wip/... path
    from frontmatter, prose, or code comments that survives the
    cleanup commit. Phase 6's reference-hygiene grep enforces
    this; the design itself must self-comply.
