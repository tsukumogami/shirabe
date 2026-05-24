# /prd Scope: shirabe-charter-skill

## Problem Statement

shirabe ships `/vision`, `/strategy`, and `/roadmap` as loadable child
skills that authors invoke directly, plus the still-unshipped `/comp`
artifact category. What is missing is a parent skill — `/charter` —
that walks an author through the strategic conversation as a
*sequence*: deciding which children to invoke, carrying scope between
them, enforcing a resume contract across child boundaries, and
guaranteeing the conversation always lands at one of three durable
exits (full-run, re-evaluation Decision Record, abandonment-forced
materialization). Without `/charter`, the strategic chain's
invariants are unenforceable, the discipline-vs-artifact decoupling
collapses into ad-hoc artifact churn, and the parent-skill pattern
that `/scope` and the future `/work-on` migration depend on has no
validation point.

## Initial Scope

### In Scope

- `/charter` as a loadable plain-English SKILL.md following the
  existing parent-skill template (input modes, execution-mode flag
  parsing, topic-slug constraint, workflow phases diagram, resume
  logic ladder, phase execution list, reference files table).
- The four `/charter` → child delegation contracts (`/vision`,
  `/comp`, `/strategy`, `/roadmap`), each with inputs, outputs,
  conditionality rules, and review-halt behavior.
  - The `/strategy` contract verifies against the shipped
    `skills/strategy/SKILL.md`: `/charter` passes whatever upstream
    its own discovery surfaced (VISION path, PRD path, or freeform
    topic) — never a STRATEGY path as `/strategy`'s input.
  - The `/comp` contract is documented load-bearing but gated
    behind a skill-existence check; `/charter` silently skips
    `/comp` while the skill is unshipped. When `/comp` lands, the
    contract becomes live with no additional `/charter` change
    needed.
- The three first-class exit paths under hard enforcement:
  - **Full-run** — a Draft STRATEGY (and optional ROADMAP) lands;
    chain halts at durable artifact for human review.
  - **Re-evaluation** — Decision Record at
    `docs/decisions/DECISION-strategy-<scope>-re-evaluation.md`
    references the existing STRATEGY; no STRATEGY revision.
  - **Abandonment-forced** — most-recent intermediate is
    force-materialized; Status block records the exit was
    abandonment-forced. There is no "true bail" path — the
    abandonment-forced exit IS what fires on user bail.
- A hybrid resume ladder: `wip/charter_<topic>_state.md` holds the
  phase pointer (which child the chain last completed and which
  exit, if any, fired); child-status checks happen against the
  durable child docs. Robust to manual edits outside `/charter`.
- The visibility model that gates `/comp` to private repos by reading
  CLAUDE.md's `## Repo Visibility:` header. Public repos skip `/comp`
  silently and never surface it as a question.
- The discover/converge engine reference `/charter` consumes for its
  Phase 1 discovery (the brief's Open Question 3 — engine extraction
  location — is treated as a design-team question, not requirements).
- Workspace and shirabe CLAUDE.md updates documenting `/charter`'s
  entry triggers and discovery surface.
- Manual fallback workflow as first-class steady-state surface:
  authors invoking a child directly outside `/charter` is supported,
  and `/charter`'s resume ladder detects child-doc edits made outside
  the chain (Journey 4).
- The `/charter`-scoped portions of
  `DESIGN-shirabe-progression-authoring.md` — the PRD surfaces which
  requirements are `/charter`-specific versus pattern-level so the
  designer can lift the pattern-level ones into the shared design.

### Out of Scope

- The `/scope` tactical progression skill (separate feature, separate
  brief; shares the design doc).
- The `/work-on` migration into the parent-skill pattern (separate
  feature; depends on the koto-amplifier-layer workflow substrate).
- The `/comp` skill body itself — `/charter`'s contract for consuming
  `/comp` is in scope; authoring `/comp` SKILL.md is the
  responsibility of the `/comp` feature.
- Revisions to the shipped `/strategy` SKILL.md (consumed as-is).
- The amplifier-layer workflow substrate.
- Automatic review-time redirect mechanism (manual fallback is
  first-class; the automatic-redirect substrate is amplifier work).
- Migration of existing strategic-progression artifacts — `/charter`
  adds a parent layer without renaming or restructuring child
  artifacts.
- Tone rubric, writing-style discipline, and other shirabe substrate
  work.

## Research Leads

1. **`/strategy` contract verification (detailed).** Read
   `skills/strategy/SKILL.md` and all of
   `skills/strategy/references/phases/` carefully. Map exactly what
   `/strategy` accepts at the four input modes, what its Phase 1
   discovery does with each mode, and what `wip/` and `docs/`
   artifacts it writes at every phase. `/charter`'s `/strategy`
   delegation contract must bind precisely against this surface.
   Specifically capture: input modes 1-4 behavior, the
   `wip/strategy_<topic>_context.md` vs `wip/strategy_<topic>_scope.md`
   filenames (phase-1-discover.md references the former; verify
   actual on-disk shape), and the Resume Logic ladder's six
   conditions so `/charter`'s resume can compose with `/strategy`'s.

2. **`/vision` and `/roadmap` contracts.** Read
   `skills/vision/SKILL.md` and `skills/roadmap/SKILL.md` and their
   phase references. Map input modes, output paths, status
   lifecycles, and any conditional logic that affects how `/charter`
   decides to invoke them. Particularly: when does `/charter` invoke
   `/vision` (the brief says "if the long-term thesis is shifting")
   versus skip — what signal does `/charter` use, and is that signal
   derivable from upstream content `/charter`'s Phase 1 already
   gathers? Same for `/roadmap` (the brief says "if the strategy
   decomposes into coordinated multi-block work").

3. **Existing parent-skill resume-ladder precedent.** `/explore` and
   `/strategy` both use status-first resume ladders against `wip/`
   and `docs/` artifacts. Map their exact patterns (six-condition
   ladder in `/strategy`; phase-pointer + wip-file detection in
   `/explore`). Then identify the gaps `/charter` needs to fill:
   detecting partial child runs across multiple skills, deciding
   which child to resume into, handling the case where a child's
   doc was edited outside `/charter` since the last `/charter`
   run.

4. **Decision Record format for the re-evaluation exit.** The
   re-evaluation exit writes
   `docs/decisions/DECISION-strategy-<scope>-re-evaluation.md`.
   Check whether this path matches an existing artifact type in
   shirabe (the workspace has a `/decision` skill and a
   `decision-record` skill in tsukumogami; need to confirm which
   one's format `/charter` writes against). If neither exists in
   `skills/decision/` at the appropriate format, the PRD needs a
   requirement that `/charter` writes the Decision Record in a
   compatible shape. Read `skills/decision/SKILL.md` to map this.

## Coverage Notes

- **Who is affected**: skill authors invoking strategic-chain work;
  reviewers reading the produced artifacts. Both covered by the
  brief's User Journeys 1-4.
- **Current situation**: authors manually invoke three (or four)
  child skills in sequence with no resume contract and no
  terminal-artifact guarantee. The brief's Problem Statement
  documents this fully.
- **What's missing**: the parent skill itself, the codified
  delegation graph, the resume ladder across child boundaries,
  terminal-artifact enforcement, and the parent-skill pattern's
  validation point. All four are in the PRD's Requirements scope.
- **Why now**: the parent-skill pattern is load-bearing for
  `/charter`, `/scope`, and the future `/work-on` migration; without
  `/charter` shipping first, the pattern has no validation point and
  the two follow-on features inherit nothing.
- **Scope boundaries**: enumerated in In Scope / Out of Scope
  above. Brief's Scope Boundary section is the source.
- **Success criteria**: the three exit paths fire correctly under
  hard enforcement; resume ladder picks up mid-chain after a
  session break; visibility gating skips `/comp` in public repos
  silently; the `/strategy` contract binds against the shipped
  skill exactly; the parent-skill pattern is documented well enough
  that `/scope` and `/work-on` can inherit it.

### Resolved scoping decisions (pre-Phase-2)

- **PRD audience**: mixed — author-reader for the user-facing
  surface; designer-reader for the four delegation contracts and
  three exit paths. Pattern-level vs `/charter`-specific
  requirements are tagged so the designer can lift the
  pattern-level ones into the shared `DESIGN-shirabe-progression-authoring.md`.
- **`/comp` treatment**: documented-but-disabled via skill-existence
  check; load-bearing contract in requirements.
- **Three-exits enforcement**: hard. State-tracking field in
  `wip/charter_<topic>_state.md` records which exit fired;
  finalization check fails if none did. No "true bail" path.
- **Resume-ladder source of truth**: hybrid. State file holds the
  phase pointer; child-status checks happen against child docs.

### Open Questions to surface in the PRD

- **Engine extraction location** (brief's Open Question 3). Whether
  the discover/converge engine moves from
  `skills/explore/references/phases/` to a top-level `references/`
  directory is a design-team question; the PRD lists it as Open and
  defers to `/design`.
- **`/charter` auto-handoff from `/explore`** (brief's Open Question
  5). Whether `/explore`'s Phase 5 crystallize routes to `/charter`
  is a follow-on integration question; the PRD lists it as Open and
  defers — out of scope for `/charter` v1.
- **Dual-implementation contract** (brief's Open Question 4). The
  freeze line between `/charter`'s `wip/`-based implementation and
  the eventual amplifier-layer implementation is an architectural
  question; the PRD lists it as Open and defers to `/design`.
- **Team persistence across the parent-skill chain.** TeamCreate's
  single-team-per-leader constraint prevents downstream teams
  (`/prd`, `/design`, `/plan`) from holding upstream teams (`/brief`)
  alive for interactive query. File-handoff is the current contract;
  likely resolution is the koto-amplifier-layer workflow substrate
  when it lands. Design-team territory.
