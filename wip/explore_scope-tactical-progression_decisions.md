# Exploration Decisions: scope-tactical-progression

## Round 1

- **Orientation: extend pattern to preserve full symmetry with `/charter`.** SE7
  scope includes pattern-doc edits and upstream contract extensions to `/prd`
  and `/design`. Reason: full contract symmetry across both parent skills is
  load-bearing for the parent-skill pattern v1; asymmetries left unaddressed
  in `/scope` v1 would compound across SE8 (`/work-on`), SE9 (review-time
  redirect), and SE12 (pattern ergonomics).

- **Pattern reference `parent-skill-pattern.md` will gain a fourth gate type:
  Mandatory-with-auto-skip.** Reason: `/prd`'s "ALWAYS invoke unless an Accepted
  PRD already exists" semantics don't fit cleanly into EITHER-signal / ALWAYS /
  shape-dependent. Unifying with EITHER-signal forces a contrived "requirements-
  shift" signal that doesn't match `/prd`'s actual resume semantics. Adding the
  fourth gate type is the more honest framing.

- **Rejection sub-shape is preserved in `/scope`. Phase-N Reject finalization
  contracts will be added to `/prd` and `/design` as SE7 prerequisites.**
  Reason: dropping rejection in `/scope` would create a per-parent asymmetry
  inside the pattern contract that has nothing to do with the strategic/tactical
  distinction — it would just be that one parent has fewer exit sub-shapes than
  another. Preserving symmetry forces the upstream contract work but produces
  a cleaner pattern.

- **A new top-level reference will land:
  `references/parent-skill-worktree-discipline.md`.** Reason: worktree staleness
  affects every long-running parent skill, not just `/scope`. Top-level
  placement lets `/charter` cite the same reference in a follow-up; deferring
  to SE12 leaves a known-good fold sitting outside the pattern's contract
  surface.

- **BRIEF is treated as a chain member, not a feeder.** Reason: rejection
  sub-shape symmetry requires that every chain child has a Phase-N Reject
  finalization verdict. If BRIEF were a feeder, the chain proposal logic would
  treat it asymmetrically from the other three children. Chain-member status
  also lets "brief-only" be expressed as `full-run` with `chain_ran: [/brief]`,
  consistent with `/charter`'s short-chain-run pattern.

- **`DESIGN-shirabe-explore-split.md` will be renamed to
  `DESIGN-shirabe-scope-skill.md` for parallelism with the other per-parent
  skill designs.** Roadmap text will be updated to reflect that the discover/
  converge engine consumption is via cross-skill pointing, not extraction.
  Reason: the "explore-split" name describes an engine refactor that was
  deliberately rejected in SE4; the actual work is authoring `/scope`'s skill
  body.

- **L9 (PRD pattern-level requirement tagging) is reclassified from "untapped
  learning" to "established convention `/scope` MUST follow".** Reason: it is
  the only mechanical way for reviewers to verify that pattern-doc edits cover
  all pattern-level requirements; without it, pattern-doc edits become opaque
  to grep-based review.

- **Observation #11's worktree runbook fold articulates an explicit trigger
  condition.** Reason: pure documentation rots fast; a trigger condition makes
  the discipline load-bearing and reviewer-checkable. Candidate trigger: "before
  each Phase 2 child invocation, run `git fetch && git status` against the
  worktree's tracking branch; halt and surface staleness if upstream has new
  commits on the target branch."

- **`/scope` $ARGUMENTS surface stays narrow (2 slots: empty / non-empty slug).**
  Reason: `/charter`'s narrow stance is a deliberate UX/governance choice; tactical
  chain's richer upstream-artifact diversity is handled in Phase 1 discovery prose,
  not $ARGUMENTS dispatch. Consistency with `/charter` matters more than
  ergonomic path-acceptance.

- **`/scope`'s validator pass-through validates each intermediate as the chain
  crosses boundaries** (PRD before invoking `/design`, DESIGN before invoking
  `/plan`, PLAN before declaring full-run). Reason: strict pass-through matches
  the inheritance pattern's discipline; simpler PLAN-only validation would leave
  intermediate artifacts unverified at chain-completion-time. The chain-level
  validation gate is `/scope`'s, not the children's.

- **`/scope` against PLAN-Active or PLAN-Done refuses and redirects.** Reason:
  re-entering chain authoring against an actively-implementing or completed
  feature is a category error — `/work-on` owns Active, `/release` owns Done.
  `/scope`'s row 5a fires the "redirect to next skill" prompt rather than the
  Re-evaluate / Revise / Bail triad.

- **`--max-rounds=N` default for `/scope` is 5** (vs `/charter`'s 3). Reason:
  tactical chains have more re-evaluation opportunities (2 boundaries vs 1)
  AND requirements/design churn faster than strategic thesis; a higher default
  accommodates the larger natural surface without forcing user override.

## Implied Deferrals (cascade from orientation)

- L1 (single-pr value-gated heuristic) — defer to SE12 (`/plan` polish; not SE7 surface)
- L5 (`/work-on` plan-outline mode) — defer to SE8
- L6 (`ci_outcome` semantics) — already in pattern doc; no fold
- L10 (reviewer coverage categories) — defer to SE12 (`/plan` surface)
- Track B observations (#1, #2, #4, #5, #6, #8) — defer to amplifier-layer
- L2, L14 — pattern-level documentation observations; no per-parent fold
