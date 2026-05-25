# /prd Scope: shirabe-scope-skill

## Problem Statement

shirabe ships `/brief`, `/prd`, `/design`, and `/plan` at the tactical
chain's altitude as four direct-invocation child skills, but no parent
skill walks an author through the chain as a sequence, enforces the
three-exit contract across BRIEF/PRD/DESIGN/PLAN boundaries, or proves
the parent-skill pattern v1 against the tactical chain's asymmetries
(extra re-evaluation boundary at the DESIGN level, no Phase-N Reject
finalization on `/prd` or `/design` today, a terminal child with two
output modes). Authors today sequence the chain by hand; the pattern
stays unratified for the parent skills that follow (`/work-on`
migration, future tactical parents). The work `/scope` does is
twofold: it ships the tactical-chain parent skill, and it ratifies
the parent-skill pattern v1 by standing it against a chain with
materially different shape than `/charter`'s strategic chain.

## Initial Scope

### In Scope

- The `/scope` SKILL.md following the parent-skill template `/charter`
  established (input modes, execution-mode flag parsing, topic-slug
  constraint, workflow phases diagram, resume logic ladder, phase
  execution list, reference files table).
- Four delegation contracts at the `/scope` → child interfaces
  (`/brief`, `/prd`, `/design`, `/plan`) covering inputs, outputs,
  conditionality rules, and review-halt behavior. Gate vocabulary
  per child: Feeder-EITHER signal for `/brief`, Mandatory-with-auto-
  skip for `/prd`, shape-dependent for `/design`, ALWAYS-with-
  terminal-semantics for `/plan`.
- Three exit paths (full-run at PLAN, re-evaluation Decision Record
  at PRD- or DESIGN-boundary, abandonment-forced materialization)
  as first-class skill behavior. Two re-evaluation Decision Record
  sub-shapes; both inherit from the pattern's re-evaluation template
  with PRD- and DESIGN-specific load-bearing-claim walks.
- Resume ladder across four child boundaries with status-aware
  re-entry against PLAN at three statuses (Draft, Active, Done),
  DESIGN's directory-move lifecycle (`docs/designs/` vs
  `docs/designs/current/`), and partial-child-run detection for each
  of the four children's `wip/` artifacts.
- Pattern-level edits the tactical chain's asymmetries motivate:
  fourth gate type (Mandatory-with-auto-skip) added to
  `references/parent-skill-pattern.md`; new top-level reference
  `references/parent-skill-worktree-discipline.md`; L9 PRD
  pattern-level requirement tagging reclassified from "untapped
  learning" to required convention.
- Phase-N Reject finalization contracts added to `/prd` and `/design`
  as `/scope` prerequisites (preserving rejection sub-shape symmetry
  across both parents).
- Shared design doc renamed from `DESIGN-shirabe-explore-split.md`
  to `DESIGN-shirabe-scope-skill.md`; roadmap entry updated to
  reflect cross-skill pointing reality (not engine extraction).
- Workspace and shirabe CLAUDE.md updates documenting `/scope`'s
  entry triggers and tactical-chain entry section.
- Manual-redirect workflow as first-class steady-state surface; R13
  manual-fallback non-interference applies to all four child
  boundaries.
- Eval suite at `skills/scope/evals/evals.json` with scenarios
  covering each gate, each exit path, both resume re-entry surfaces,
  and the manual-fallback case.

### Out of Scope

- The `/work-on` migration into the parent-skill pattern (SE8).
- Review-time redirect mechanism (SE9).
- Pattern-ergonomics tightening (SE12).
- Re-litigating pattern invariants I-1 through I-7.
- Amplifier-layer workflow substrate.
- niwa workspace context surface changes.
- Migration of existing tactical-progression artifacts.
- Authoring `/brief`, `/prd`, `/design`, or `/plan` skill bodies
  (only the Phase-N Reject contract extensions to `/prd` and
  `/design` are in scope as `/scope` prerequisites).

## Research Leads

1. **L9 fold disposition** (pattern-level requirement tagging):
   confirm reuse of /charter's exact R-numbers for pattern-level
   requirements (R1, R3, R9, R10, R11, R12, R13, R14, R17a, R18, R19)
   and identify where `/scope`-specific R-numbers begin (R20+).
   *Answered:* exploration Lead 1 and Decisions doc both confirm
   reuse of /charter's exact R-numbers; new tactical-chain
   requirements start at R20+.
2. **Observation #3 + #9 paired fold**: structural file-existence +
   reviewer-PASS-with-artifact-presence check at child-invocation
   review boundary — produces a new `/scope`-specific requirement.
3. **Observation #11 fold**: worktree-staleness runbook trigger
   condition (when does `/scope` halt for upstream commit drift?) —
   produces a new `/scope`-specific requirement.
4. **L11 fold**: `<<ISSUE:N>>` placeholder discipline in `/scope`'s
   own PLAN doc and chain-orchestration interpretation rule —
   produces a new `/scope`-specific requirement.
5. **Pattern-level gate vocabulary fourth entry**: confirm the
   "Mandatory-with-auto-skip" semantics line up with `/prd`'s
   actual resume behavior and pattern doc framing.
   *Answered:* exploration Decisions doc confirms the fourth gate
   type lands in `references/parent-skill-pattern.md` to capture
   `/prd`'s ALWAYS-unless-Accepted-PRD-exists semantics.
6. **Phase-N Reject contract extensions on `/prd` and `/design`**:
   what minimal contract surface needs to exist on each child so
   `/scope` can route rejection to the re-evaluation exit's
   rejection sub-shape symmetrically across both new tactical
   boundaries (PRD-rejection vs DESIGN-rejection sub-shapes)?

## Coverage Notes

The BRIEF (Accepted at commit 5207ee2) already answers the six
coverage dimensions (who/current/missing/why-now/scope/success).
Exploration (decisions doc + findings doc + 7 research files at
`wip/research/explore_scope-tactical-progression_r1_*.md`) settles
the 12 cascading decisions that frame the PRD's contract surface.

Phase 2 (Discover) is therefore narrow: leads 1 and 5 are already
answered by exploration files; leads 2, 3, 4, and 6 may need
targeted investigation but most likely fold directly into PRD
requirement enumeration without additional research.
