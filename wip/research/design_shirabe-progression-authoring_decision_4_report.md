# Decision 4: Pattern-surface PRD requirement ratification (R12, R13, R14, R17a, R18)

Walked `/decision` inline (no nested team). Fast path Tier 3: Phases 0, 1, 2, 6.

## Phase 0: Context

### Question

For each of the five `/charter` PRD requirements tagged `[pattern-level]` on the
small-surface "pattern surface" — R12 visibility detection, R13 manual-fallback,
R14 child-internals isolation, R17a CLAUDE.md surfacing, R18 eval shipping — does
the design ratify the tagging verbatim, ratify with parent-specific bindings, or
return it to PRD-altitude rework? Plus a sub-decision: does R18 ship a shared
pattern-level eval scenario baseline that every parent inherits, or does each
parent author its evals independently?

### Constraints

- The PRD already tags all five as `[pattern-level]`. The design's job is to
  confirm or amend; not to re-derive.
- `/scope` and `/work-on` are reasonable inferences, not bounded specs.
  `/scope` is a tactical progression parent (doc-emitting like `/charter`).
  `/work-on` migrates from current substrate; its "children" are issues / PRs,
  not docs with frontmatter.
- The design's deeper job: any "ratify verbatim" claim must hold across all
  three parents. The tricky one is R14 — `/work-on`'s children have no
  `status:` frontmatter on a doc; they have GitHub issue / PR state.
- Eval-shared-set (R18 sub-decision) is the genuine reuse-versus-independence
  call. The cost of "shared" is coupling; the cost of "independent" is
  drift on the four invariant behaviors (slug rejection per R3,
  malformed state file per R11, child-internals isolation per R14,
  visibility default per R12).

### Background

R12-R18 prose at PRD lines 545-648:
- R12 reads CLAUDE.md `## Repo Visibility:`, defaults Private with warning.
  Precedent: `/strategy` SKILL.md lines 51-65 (visibility detection from
  CLAUDE.md, default Private if unknown, warning "restricting is easier to
  undo than oversharing"). `/explore` follows the same pattern.
- R13 treats manual fallback (direct child invocation outside parent) as
  first-class steady-state. Parent does not prevent or warn against it.
  Sibling-edit detection on next resume surfaces staleness via
  `child_snapshots` comparison (R10).
- R14 reads only child doc frontmatter `status:` and topic slug. Parent
  MUST NOT inspect child's `wip/research/<child>_<topic>_phase<N>_*.md` or
  any other child internals.
- R17a ships CLAUDE.md updates surfacing entry triggers. R17b's specific
  trigger phrases are charter-specific; R17a's requirement-to-ship is the
  pattern-level commitment.
- R18 ships evals at `skills/<name>/evals/evals.json`, runnable via
  `scripts/run-evals.sh <name>`. `/charter`'s scenarios cover US-1
  through US-4 (charter-specific); the requirement-to-ship is the
  pattern-level commitment.
- Existing eval format (`skills/strategy/evals/evals.json`): JSON with
  `skill_name`, `evals[]`. Each eval has `id`, `name`, `prompt`,
  `expected_output`, `files`, `expectations[]`. Expectations are
  asserted via a grader; assertion language is concrete behavior
  ("Plan validates the topic slug 'X' matches [a-z0-9-]+ at Phase 0").

## Phase 1: Research findings

### Critical unknowns and resolutions

1. **Does `/scope` have a children-emit-docs surface like `/charter`?** Yes,
   inferred. `/charter`'s PRD lines 76-79 names `/scope` as a parallel
   parent sibling. `/scope` operates at tactical altitude over `/prd`,
   `/design`, `/plan` (the PRD's "tactical-altitude children"). These all
   produce docs (`docs/prds/PRD-*.md`, `docs/designs/DESIGN-*.md`,
   `docs/plans/PLAN-*.md`) with frontmatter `status:`. So `/scope`'s
   children have the same inspection surface as `/charter`'s.

2. **Does `/work-on` emit docs?** No. PRD line 14 and Out of Scope item 2
   (line 938) name `/work-on` as a substrate migration: the parent
   manipulates issues, PRs, and branches. Children are GitHub issues
   (state: open, closed, status labels) and PRs (state: open, merged,
   draft, plus CI check states). There is no `docs/<type>/<TYPE>-*.md`
   file with `status:` frontmatter at the child level.

3. **Does the `/strategy` precedent for visibility detection generalize?**
   Yes. `/strategy` SKILL.md lines 51-65 and `/explore` both read the
   `## Repo Visibility:` header. The CLAUDE.md surface is repo-level
   (workspace-wide convention), not skill-level. Every parent runs in a
   repo; every repo has (or should have) the header. The pattern is
   already cross-skill; promoting it to pattern-level requirement is
   ratifying status quo.

4. **What evals scenarios are invariant across parents?** Four:
   (a) slug rejection per R3 — every parent enforces `^[a-z0-9-]+$`;
   (b) malformed state file per R11 — every parent surfaces error and
   offers Discard rather than silent fall-through;
   (c) child-internals isolation per R14 — every doc-emitting parent
   reads only child frontmatter (qualifier applies to /work-on
   per finding 2);
   (d) visibility default per R12 — every parent defaults Private with
   warning when header absent.

5. **What's the cost of "shared eval scenario baseline" versus "each
   parent independent"?** Shared baseline: one canonical scenario per
   invariant lives somewhere pattern-level (e.g., a `references/`
   file referenced by each parent's evals.json) and each parent's
   `evals.json` can either include a `$ref` shape (current format does
   not support this — it's flat JSON with `evals[]`) OR each parent
   copy-pastes the canonical text with a comment indicating the source.
   Independent: each parent's `evals.json` is self-contained, drift
   risk is real. The current eval-runner contract
   (`scripts/run-evals.sh <name>`) reads only `skills/<name>/evals/evals.json`
   — there is no `$ref` mechanism today.

### Assumptions (--auto mode)

- **Assumed:** `/scope`'s children all emit `docs/<type>/<TYPE>-<slug>.md`
  with frontmatter `status:`. If wrong: `/scope` may need its own R14
  binding distinct from `/charter`. Mitigating signal: shirabe's existing
  child skills (`/prd`, `/design`, `/plan`) all already produce such docs
  today.
- **Assumed:** the workspace CLAUDE.md surfacing requirement applies
  equally to all three parents. If wrong: `/work-on` might surface only
  in repo-level CLAUDE.md (not workspace). Mitigating signal: discovery
  of new skills goes through the same author surface today; no reason
  `/work-on` would be different.
- **Assumed:** evals format remains JSON-flat (`evals[]`) for v1; no
  `$ref` mechanism added. If wrong: the shared-baseline alternative
  could use a reference rather than copy-paste. Mitigating signal: PRD
  treats evals as v1-ship-as-is; format changes are out of scope.

## Phase 2: Alternatives per requirement

For each of R12, R13, R14, R17a, R18, three alternatives:

- **(a) ratify-verbatim** — design adopts the requirement as pattern-level
  with no parent-specific binding.
- **(b) ratify-with-parent-specific-binding** — design adopts the
  requirement as pattern-level but names where parents differ on the
  surface (e.g., R14's "child internals" means different things for
  doc-emitting vs non-doc-emitting parents).
- **(c) needs-rework** — return the requirement to PRD-altitude
  rework; not ratifiable as written.

### R12 (visibility detection)

- **(a) ratify-verbatim.** Every parent reads CLAUDE.md `## Repo
  Visibility:`, defaults Private with the same warning text.
  Mechanism is repo-level (not child-level); identical across parents.
  `/strategy` and `/explore` already demonstrate this.
- (b) per-parent binding. `/work-on` might claim it doesn't need
  visibility detection (no `/comp` to surface, no visibility-gated
  content). But `/work-on` operates on issues whose titles, descriptions,
  and PR bodies can leak across visibility boundaries. Visibility is a
  workspace-wide concern, not a feature-specific one.
- (c) rework. Not warranted — `/strategy`'s precedent is clean.

### R13 (manual-fallback)

- **(a) ratify-verbatim.** Every parent treats direct child invocation
  outside the parent as first-class steady-state. Parent never blocks
  or warns against it. On next resume, sibling-edit detection surfaces
  staleness via `child_snapshots`.
- (b) per-parent binding. `/work-on`'s "children" (issues, PRs) can be
  manipulated directly outside `/work-on` (e.g., user edits an issue's
  body, comments on a PR, force-pushes a branch). The manual-fallback
  contract still applies: `/work-on` MUST NOT interfere with direct
  manipulation. The behavior is the same; only the surface differs
  (issue/PR state vs doc state). This is identity, not a binding.
- (c) rework. Not warranted.

### R14 (child-internals isolation)

- (a) ratify-verbatim. Holds for `/charter` and `/scope` (doc-emitting
  parents). Breaks for `/work-on` — its children have no `wip/research/`
  internals because they are GitHub issues / PRs, not skill invocations
  with phase files.
- **(b) ratify-with-parent-specific-binding.** This is the structurally
  honest answer. The pattern-level commitment is: **a parent reads only
  its child's durable, externally-visible status surface; never the
  child's internal evidence or working materials.** For doc-emitting
  parents (`/charter`, `/scope`), the durable surface is the child doc's
  frontmatter `status:` plus the topic slug; the internal surface is
  `wip/research/<child>_<topic>_phase<N>_*.md` and any other intermediate
  wip artifacts the child writes. For `/work-on`-style parents, the
  durable surface is the GitHub issue's state + labels and the PR's
  state + CI check rollup; the internal surface is comment threads,
  CI log bodies, draft-stage diffs, and reviewer-thread internals. Same
  rule, different surface.
- (c) rework. Not needed if (b) is taken — the pattern-level rule
  generalizes cleanly; only the concrete surface varies per parent.

### R17a (CLAUDE.md surfacing)

- **(a) ratify-verbatim.** Every parent ships CLAUDE.md updates that
  surface its entry triggers and discovery surface. The requirement is
  about *that* CLAUDE.md updates happen; the *content* (trigger phrases
  themselves, e.g., R17b for `/charter`) is parent-specific. R17a's
  pattern-level scope is the ship-CLAUDE.md-updates commitment, full
  stop.
- (b) per-parent binding. Not necessary — R17a is already minimally
  scoped; R17b is the bindings.
- (c) rework. Not warranted.

### R18 (eval shipping)

- **(a) ratify-verbatim.** Every parent ships
  `skills/<name>/evals/evals.json`, runnable via
  `scripts/run-evals.sh <name>`. The scenarios chosen are parent-specific
  (e.g., `/charter`'s cover US-1 through US-4). The pattern-level
  commitment is the ship-evals + run-via-script commitment.
- (b) per-parent binding. Trivially the case for scenario *content*, but
  R18 already scopes itself this way. No additional binding needed.
- (c) rework. Not warranted.

### Sub-decision: shared eval scenario baseline?

Three alternatives for the four invariant scenarios (slug rejection,
malformed state file, child-internals isolation, visibility default):

- **(s1) Each parent authors independently.** No shared baseline. Each
  parent's evals.json covers its own user stories plus the four invariants.
  Cost: drift risk — `/scope` and `/work-on` may diverge on assertion
  wording or scenario design as they're authored. Benefit: no infra
  changes; current eval format works as-is.
- **(s2) Shared baseline via copy-paste with a canonical source.** The
  pattern-level design names a canonical source for the four invariant
  scenarios (e.g., `skills/charter/evals/evals.json` becomes the
  reference implementation, or a new `references/parent-skill-eval-baseline.md`
  in shirabe-core documents the canonical assertion wording). Each
  parent's evals.json copies the four scenarios in, adapted to the
  parent's slug and state-file path. Drift is detectable at PR review:
  reviewers compare against the canonical source. No eval-format
  changes required.
- (s3) Shared baseline via `$ref` mechanism in the eval runner.
  `scripts/run-evals.sh` learns to resolve `"$ref":
  "../../references/baseline-evals.json#/scenarios/slug-rejection"`
  inclusion. Each parent's evals.json references the baseline by path.
  Cost: eval-runner script change, eval-format extension. Benefit: no
  drift mechanically possible. Out of scope per the assumption that
  eval format is v1-frozen.

**Chosen for sub-decision: (s2) shared baseline via copy-paste with a
canonical source.** Authors the four invariant scenarios in
`/charter`'s evals.json with a header comment noting "these four
scenarios are the pattern-level baseline; `/scope` and `/work-on` copy
them adapted to their parent name." The design's pattern-level
references section names this baseline explicitly. Drift caught at
review.

## Phase 6: Synthesis and Final Decision

### Summary table

| Req  | Verdict                                         | One-line rationale                                                                                                                                                       |
|------|-------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| R12  | (a) ratify-verbatim                             | CLAUDE.md `## Repo Visibility:` is workspace-wide; `/strategy` and `/explore` already use it identically. Every parent inherits without modification.                    |
| R13  | (a) ratify-verbatim                             | Manual-fallback non-interference is identical across parents — direct child invocation never warns or blocks. Surface (doc vs issue/PR) differs but rule is identical.   |
| R14  | (b) ratify-with-parent-specific-binding         | Pattern-level rule: parent reads only the child's durable externally-visible status surface; never internals. Surface = frontmatter `status:` for docs; issue/PR state + CI rollup for `/work-on`. |
| R17a | (a) ratify-verbatim                             | Ship CLAUDE.md updates that surface entry triggers. Trigger-phrase content is parent-specific (e.g., R17b for `/charter`) — but the ship-the-updates rule is identical.  |
| R18  | (a) ratify-verbatim                             | Ship `skills/<name>/evals/evals.json` runnable via `scripts/run-evals.sh <name>`. Scenario content is parent-specific; the ship-and-runnable commitment is identical.   |
| R18 sub | shared baseline via copy-paste                | Four invariant scenarios (slug rejection, malformed state file, child-internals isolation, visibility default) authored once in `/charter` evals.json as the canonical baseline; `/scope` and `/work-on` copy adapted to their slug. Pattern-level references doc names the canonical source. |

### Chosen

Ratify R12, R13, R17a, R18 verbatim as pattern-level. Ratify R14 with
parent-specific binding (the rule generalizes; the surface differs for
non-doc-emitting parents like `/work-on`). R18 sub-decision: ship a
shared scenario baseline via copy-paste with a canonical source.

### Rationale

The PRD's pattern-level tagging holds for four of the five requirements
without amendment. Each is small-surface and identical across parents:
visibility detection reads a workspace-level header; manual-fallback
non-interference is a behavior rule that doesn't depend on the child's
shape; CLAUDE.md surfacing and eval-shipping commitments scope themselves
correctly (the *content* is parent-specific, the *commitment* is not).

R14 is the only requirement that needs the design to do real work. The
PRD's literal phrasing reads `frontmatter status: and topic slug` — that
phrasing assumes children are doc-emitting. `/work-on`'s children are
issues and PRs, which have no doc and no frontmatter. The honest
pattern-level rule is broader: **a parent reads only its child's durable,
externally-visible status surface; never the child's internals or working
materials.** For doc-emitting parents (`/charter`, `/scope`), that surface
is frontmatter `status:` plus topic slug. For `/work-on`, that surface
is issue/PR state + labels + CI rollup. The pattern-level commitment
holds; the binding names the per-parent surface. The design should
write the rule at the broader altitude and provide a small table mapping
each parent's "durable status surface" and "internals/forbidden surface."

The R18 shared-baseline sub-decision: the four invariant scenarios
(slug rejection, malformed state file, child-internals isolation,
visibility default) test pattern-level behavior that every parent must
exhibit identically. Copy-paste with a canonical source — pointing the
`/scope` and `/work-on` authors at `/charter`'s evals.json or a
`references/parent-skill-eval-baseline.md` — gets the reuse benefit
without modifying the v1-frozen eval format. The drift risk is bounded
because reviewers compare against the canonical source at PR review.
A future `$ref` mechanism (s3) is a cleaner end-state but is
infrastructure work out of scope for v1.

### Confidence

**High** on R12, R13, R17a, R18 (verbatim ratification). The PRD's
phrasing already scopes these as workspace- and skill-level commitments
without per-parent variation.

**Medium-high** on R14 (parent-specific binding). The "broader rule, named
surface per parent" structure is structurally honest and accommodates
`/work-on` without forcing it into a doc-frontmatter shape that doesn't
fit. The remaining risk: when `/work-on`'s migration PRD lands, the
"issue/PR state + CI rollup" surface enumeration may need refinement
(e.g., are reviewer-thread internals always off-limits, or only when the
parent's decision logic doesn't need them?). The design should flag this
as a follow-up bounded by the `/work-on` migration's PRD scope.

**Medium** on R18 sub-decision (shared baseline via copy-paste). The
copy-paste mechanism is conventional and drift-bounded by review
discipline, but it depends on humans (or eval CI) noticing divergence.
If shirabe ships a `$ref` mechanism later, this answer mechanically
upgrades.

### Assumptions

- `/scope`'s children all emit docs with frontmatter `status:`. (Mitigating
  signal: shirabe's existing child skills already do.)
- `/work-on`'s children are issues and PRs, not docs. (Confirmed in PRD
  text.)
- Eval format remains JSON-flat in v1. (Confirmed: PRD treats evals as
  ship-as-is.)
- The R14 broader rule ("durable externally-visible status surface, never
  internals") generalizes for any future parent. If a parent's children
  are neither docs nor GitHub issues/PRs (e.g., a `/koto`-driven parent),
  the rule still holds with a new surface enumeration.

### Rejected alternatives

- **R12 (b) per-parent binding.** Rejected: visibility is a workspace
  concern, not a feature-specific one. Even `/work-on` operates on issues
  whose content can leak across visibility boundaries.
- **R13 (b) per-parent binding.** Rejected: the rule (parent never
  interferes with direct child invocation) is identical across parents;
  the surface differing (issue/PR vs doc) is not a binding, it's
  identity.
- **R14 (a) ratify-verbatim.** Rejected: the PRD's literal `frontmatter
  status:` phrasing assumes doc-emitting children. `/work-on`'s children
  have no frontmatter. Ratifying verbatim would force a tortured
  interpretation or leave `/work-on` outside the pattern.
- **R14 (c) rework.** Rejected: the underlying rule generalizes cleanly;
  the per-parent surface enumeration is a binding, not a defect in the
  PRD. The PRD's tagging is correct; the design's job is to widen the
  rule's phrasing without changing the commitment.
- **R18 sub (s1) independent.** Rejected: drift on the four invariants
  defeats the purpose of pattern-level scope. The pattern exists so
  every parent exhibits the same baseline behavior; independent
  authoring undermines that.
- **R18 sub (s3) `$ref` mechanism.** Rejected for v1: eval-format
  changes are out of scope. Re-evaluate when shirabe-eval infrastructure
  is bounded.

### Consequences

- The design's pattern-level scope acquires R12, R13, R17a, R18 verbatim
  from `/charter`'s PRD, plus R14 in a widened form. `/scope` inherits
  these without further analysis when its PRD lands.
- The design must include a small table (likely in Solution Architecture
  or a `references/parent-skill-pattern.md`) mapping each parent's
  R14 surface: `/charter` and `/scope` use frontmatter `status:`;
  `/work-on` uses issue/PR state + labels + CI rollup.
- The design's pattern-level references include a "shared eval scenario
  baseline" reference (either `/charter`'s evals.json as the canonical
  source, or a new `references/parent-skill-eval-baseline.md` with the
  canonical assertion wording). `/scope` and `/work-on` evals.json files
  copy adapted versions.
- A follow-up question is flagged for `/work-on`'s PRD: enumerate
  exactly which issue/PR-state surfaces are durable (state + labels +
  CI rollup) versus internals (comment-thread internals, draft-stage
  diffs, reviewer-thread internals). This is `/work-on`'s scope, not
  `/charter`'s.
- An optional substrate-layer follow-up: when shirabe ships a `$ref`
  mechanism for evals, the R18 sub-decision upgrades from copy-paste
  to mechanical reuse. Not a v1 blocker.
