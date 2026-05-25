# Lead: adversarial-demand

## Findings

### Q1: Is demand real?

**Evidence:**

- A roadmap entry exists (`ROADMAP-shirabe-evolution.md`, lines 210-227)
  authored by the maintainer (`dangazineu`) that names SE7 as "second new
  shirabe parent skill" and ties it to a Strategy Block 3 (second
  progression) commitment.
- A maintainer-filed planning issue exists: `tsukumogami/vision#495`
  ("docs(design): /scope tactical progression") with labels `needs-design`,
  `validation:simple`, milestone `shirabe-evolution`. Authored 2026-05-23 by
  dangazineu.
- The strategy doc `STRATEGY-shirabe-evolution.md` lines 244-247 explicitly
  commits the project to a `/scope` tactical parent skill driving
  `brief → PRD → design → plan` as the second progression in Block 3.
- The precedent parent skill `/charter` shipped (shirabe#96, merged
  2026-05-25). The PRD for `/charter` (`PRD-shirabe-charter-skill.md` Goals
  section) explicitly names `/scope` as the next consumer that will inherit
  the parent-skill pattern that `/charter` validates: "`/charter` ships as
  the validation point for the parent-skill pattern that `/scope` and the
  `/work-on` migration will inherit." This makes SE7 a load-bearing follower
  in a multi-feature commitment, not a freestanding idea.
- The pattern-level design doc `DESIGN-shirabe-progression-authoring.md`
  (Status: Current, accepted 2026-05-25) explicitly carries `/scope` as a
  named consumer alongside `/charter` ("The design is shared across the
  parent-skill pattern's three features: `/charter` ... `/scope` (a
  parallel parent sibling, separate PRD), and the future `/work-on`
  migration").
- Tactical-chain children have all shipped as standalone skills, validating
  the chain exists today as separate invocations: `/brief` (SE6, shirabe#95
  merged), `/prd` (existing), `/design` (existing), `/plan` (existing). SE7
  is the wrapper over a real, in-use chain — not an aspirational construct
  over hypothetical children.
- The current worktree itself (`vision-ce182769` on branch
  `docs/scope-tactical-progression`) is an in-flight `/explore` run targeting
  SE7 explicitly, with a scope file and two completed research outputs
  (`pattern-inheritance-audit`, `tactical-chain-gates`) — a sixth signal that
  the work is being actively pursued.

**Confidence: High** — multiple independent sources (maintainer-filed issue
in a Milestone, maintainer-authored ROADMAP entry, maintainer-authored
STRATEGY commitment, downstream PRD/DESIGN naming SE7 as a consumer,
sibling parent skill already shipped as precedent) all confirm.

### Q2: What do users do today instead?

**Evidence:**

- The tactical chain children (`/brief`, `/prd`, `/design`, `/plan`) ship
  as separate `/shirabe:*` invocations. Users currently invoke them by hand
  in sequence.
- The `PRD-shirabe-charter-skill.md` Problem Statement section enumerates
  the cost of having no parent skill (in the strategic chain context, but
  the costs apply symmetrically to the tactical chain): (1) re-derive
  sequencing decisions per run, (2) carry context between children
  manually, (3) no resume contract if the session breaks between children,
  (4) no enforcement that the conversation produces a durable terminal
  artifact.
- `skills/explore/references/phases/phase-5-produce.md` documents an ad-hoc
  workaround: `/explore` auto-continues into `/prd` or `/design` after a
  crystallize decision, but stops before `/plan` ("Auto-continues into /prd"
  / "Auto-continues into /design" / "Stops — user runs /plan"). This is a
  partial in-skill stitching of the chain in place of a true parent.
- Closed issue `tsukumogami/shirabe#22`
  ("ux(explore): workflow should continue into /design automatically after
  user confirms crystallize decision") — maintainer-authored bug report
  citing the manual hand-off as a "UX failure: the user already expressed
  their intent. Asking them to re-invoke a separate command to confirm what
  they just confirmed is friction that shouldn't exist." This is direct
  evidence of pain from the manual-chaining state of affairs.
- The SE4 (`/charter`) implementation was itself driven by dog-fooding the
  tactical chain manually — see the scope file note: "SE4's PR was authored
  by dog-fooding the same `/brief → /prd → /design → /plan` chain that SE7
  will codify. The friction the SE4 session surfaced IS the validation
  evidence for what SE7 needs." Issue #514 (SE12) captures that friction
  empirically: "11 operating-pattern friction modes captured in
  `wip/team-pattern-observations.md`" during the SE4 dog-food.

**Confidence: High** — three concrete workarounds (manual sequential
invocation, partial `/explore` auto-continue stitching, dog-fooding the
chain by hand for SE4) are documented in committed artifacts plus a closed
bug filed against the workaround friction.

### Q3: Who specifically asked?

**Evidence:**

- `dangazineu` (sole maintainer, project lead) authored issue #495 on
  2026-05-23.
- `dangazineu` authored `ROADMAP-shirabe-evolution.md` (commit
  `c357586` on this branch references the broader roadmap, sequence of
  feature commits from the same author).
- `dangazineu` authored `STRATEGY-shirabe-evolution.md` and its
  commitment to the three progressions.
- `dangazineu` authored the shirabe#22 closed bug about chain friction.
- `dangazineu` authored issue #514 (SE12, parent-skill pattern v1
  ergonomics, blocking SE7 inherited improvements).

No distinct external reporters. This is a single-maintainer project where
the maintainer is the user. Triangulation is via maintainer-authored
artifacts across the project tree (roadmap, strategy, milestone issues,
PRD, design doc, sibling implementation PRs) rather than across distinct
human reporters.

**Confidence: High** for the maintainer-driven origin; **Medium** if the
question requires diverse human authorship. The repo's social model is
single-maintainer; the multiple artifact types and the existence of a
shipped sibling parent skill (`/charter`) provide the corroboration that
distinct reporters would provide in a larger project.

### Q4: What behavior change counts as success?

**Evidence:**

- Acceptance criteria from issue #495:
  - `docs/designs/DESIGN-shirabe-explore-split.md` exists
  - Design doc status is "Proposed" (ready for review)
  - Design doc follows the design-doc skill schema
  - Design doc references this issue as `spawned_from`
- This is acceptance for the design issue only, not for the eventual
  `/scope` skill ship. The skill-ship acceptance is downstream.
- The ROADMAP-shirabe-evolution.md SE7 entry names the deliverable as a
  "plain-English SKILL.md that orchestrates child phases for brief / PRD /
  design / plan" using "current shirabe patterns" with content flow
  "through `wip/` and explicit input" and an artifact-decision living "in
  phase prose."
- The STRATEGY doc's Block 3 names the success criterion as "Each
  progression must produce at least its durable terminal artifact;
  intermediate skills may produce earlier artifacts when the agent judges
  the work review-worthy" — i.e., the terminal PLAN MUST be produced for a
  full-run exit.
- The /charter PRD's Goals section provides a model contract that /scope
  will inherit verbatim: "An author invokes `/charter` and is walked
  through the strategic chain without remembering the order, the
  artifact-decision heuristics, or the visibility gating. The chain ends
  at exactly one of three named exit paths (full-run, re-evaluation,
  abandonment-forced). ... The chain is resumable mid-flight across child
  boundaries." Substituting strategic → tactical and STRATEGY → PLAN, this
  is the expected success contract for SE7.
- The `DESIGN-shirabe-progression-authoring.md` (Current status) declares
  the substitution surfaces and invariants (I-1..I-7, three exits) that
  `/scope` must bind. Success at the pattern-conformance layer = `/scope`
  binds the same surfaces.

**Confidence: High** for the design-issue acceptance (explicit in #495);
**High** for the skill-ship contract (inheritable from /charter PRD + the
shared pattern design); **Medium** for the runtime success measurement
(no metrics like "X% of authors prefer /scope to manual chaining" are
defined anywhere I found).

### Q5: Is it already built?

**Evidence:**

- `skills/` directory at `public/shirabe @ origin/main` does NOT contain a
  `scope/` directory (verified: skills are `decision/`, `design/`,
  `explore/`, `plan/`, `prd/`, `private-content/`, `public-content/`,
  `release/`, `review-plan/`, `roadmap/`, `vision/`, `work-on/`,
  `writing-style/`, plus `charter/` and `brief/` shipped via #96 and #95).
- No `DESIGN-shirabe-explore-split.md` exists in the repo (the design doc
  named by issue #495 — confirmed by recursive find on the worktree and
  inspection of `docs/designs/` and `docs/designs/current/`).
- The shipped `/charter` parent skill IS the precedent infrastructure
  /scope will inherit — but it is not /scope itself.
- The `DESIGN-shirabe-progression-authoring.md` (shared pattern design)
  IS shipped and Current — this is the upstream of `/scope`'s eventual
  design, not `/scope` itself.
- Partial /explore auto-continue (the `/prd` and `/design` handoffs)
  exists in `skills/explore/references/phases/phase-5-produce*.md` but
  it's a degenerate partial stitch from `/explore`'s exit, not a wrapping
  tactical-chain parent.
- The current branch (`docs/scope-tactical-progression`) is an `/explore`
  run staging the design work — `wip/explore_scope-tactical-progression_*`
  files exist, but no durable scope-skill artifacts have landed.

**Confidence: High — not built.** Two layers of build status (the design
doc and the skill itself) both confirmed absent via direct filesystem
inspection.

### Q6: Is it already planned?

**Evidence:**

- Issue `tsukumogami/vision#495` is open with `needs-design` label, in the
  `shirabe-evolution` milestone (#25).
- Milestone status from `ROADMAP-shirabe-evolution.md` table line 538:
  "SE7 (`/scope` tactical progression) | #495 | Not started".
- Dependency graph in the same roadmap places SE7 in Phase 1 (Core layer)
  with soft dependency on SE4 (`/charter`) — and SE4 shipped, so SE7 is
  unblocked.
- The roadmap explicitly names the design doc to be produced
  (`DESIGN-shirabe-explore-split.md`) and a second related doc
  (`DESIGN-shirabe-progression-authoring.md`) which already shipped.
- The strategy doc commits to the three progressions
  (`/charter`, `/scope`, `/work-on`-migration) as a coherent Block 3
  deliverable.
- The exploration is in flight as of this worktree
  (`docs/scope-tactical-progression` branch, two research outputs landed,
  this very call adds a third).
- SE12 (#514, `parent-skill pattern v1 ergonomics improvements`) is also
  planned and queued, and is described as a feeder of "inside-pattern
  improvements" that "SE7 (`/scope`) and SE8 (`/work-on` migration) inherit
  the inside-pattern improvements when they ship." So SE7 is planned AND
  scheduled to absorb related learnings.

**Confidence: High** — open milestone issue, named in roadmap dependency
graph as Not started but unblocked, predecessor shipped, downstream PRD
naming SE7 as a consumer of its improvements.

## Calibration

**Demand validated.**

This is not a "no evidence found" outcome. Multiple positive evidence
sources confirm:

- A maintainer-filed milestone issue (#495) with `needs-design` triage
  label.
- A maintainer-authored ROADMAP entry explicitly naming SE7 and locating
  it on a dependency graph as unblocked.
- A maintainer-authored STRATEGY commitment naming `/scope` as one of
  three load-bearing parent skills the strategy hinges on.
- A shipped precedent (`/charter`, shirabe#96) whose own PRD names
  `/scope` as the second-consumer the precedent was built to validate.
- A shipped shared pattern design (`DESIGN-shirabe-progression-authoring`)
  whose Status section names `/scope` as a co-target of the design.
- A closed bug (`shirabe#22`) capturing user pain from the manual-chaining
  workaround that `/scope` would resolve.
- An in-flight explore run (this very worktree) generating the design
  inputs.

No rejection evidence exists. There is no closed PR with maintainer
"don't do this" reasoning, no design doc that de-scoped `/scope`, no
ADR rejecting the tactical-chain parent. The strategy's Non-Goals section
rejects a *hard* split between `/charter` and `/scope` crystallize menus
(`STRATEGY-shirabe-evolution.md`) — but that is a scope-narrowing on how
`/scope` ships, not a rejection of `/scope` itself.

The validation pattern is unusual for a public open-source project because
the repo is single-maintainer and reporters do not multiply. But the
artifact-graph corroboration (roadmap → strategy → milestone issue →
sibling-PRD-naming-/scope → shared-pattern-design-naming-/scope → in-flight
explore) substitutes for distinct-reporter multiplication: each artifact
is an independent commitment surface that would have to be retracted if
demand evaporated.

The only gap worth flagging is **Q4 runtime success measurement** — no
quantitative criterion (e.g., "X% of tactical-chain runs use `/scope`
within Y months") is defined anywhere I found. The success criterion is
behavioral and pattern-conformance-based: `/scope` works the way
`/charter` works, just for the tactical chain. Whether that is *enough*
of a success measurement depends on the project's own metrics discipline,
which I can't assess from the artifacts.

## Summary

Demand is validated: a maintainer-filed milestone issue (#495), a roadmap
entry naming SE7 as load-bearing follower of the shipped `/charter`
precedent, a strategy commitment to three parent progressions, and an
in-flight `/explore` run all confirm. The strongest evidence is the
multi-artifact triangulation — `/charter`'s shipped PRD names `/scope`
as the next inheritor, the shared pattern design has SE7 as a named
co-target, and a closed bug (`shirabe#22`) captures pain from the
manual-chaining workaround the parent skill resolves. The biggest gap is
the absence of any defined runtime success metric beyond
pattern-conformance with `/charter`; the project's social model
(single-maintainer) substitutes artifact-graph corroboration for
multi-reporter triangulation, which is sufficient here but worth naming.
