# Phase 2 Research: Maintainer perspective

## Lead 1: Resume-ladder precedents

### Findings

Per-skill ladder structures (read top-to-bottom, resume at first match):

**`/explore`** (`skills/explore/SKILL.md:186-199`) — multi-source, 7 conditions:
```
wip/explore_<topic>_crystallize.md exists                          -> Phase 5
wip/explore_<topic>_findings.md has "## Decision: Crystallize"     -> Phase 4
wip/explore_<topic>_findings.md exists (no crystallize marker)     -> Phase 3
wip/research/explore_<topic>_r*_lead-*.md exist, no findings       -> Phase 3
wip/explore_<topic>_scope.md exists                                -> Phase 2
On topic branch, no explore artifacts                              -> Phase 1
Not on topic branch                                                -> Phase 0
```
Multi-source: consults `_crystallize.md`, `_findings.md`, `_scope.md`, AND
the research fan-out files. Status-aware re-entry is **not** present — there
is no durable `docs/` artifact for `/explore`, so no Accepted-status case.
Carries a content-level marker check inside the findings file (`## Decision:
Crystallize`), making it the most "stateful" of the ladders.

**`/strategy`** (`skills/strategy/SKILL.md:158-169`) — multi-source, 8 conditions:
```
STRATEGY exists with status "Accepted" or "Active"      -> Offer revise/fresh
STRATEGY exists with status "Draft"                      -> Continue Phase 2 or 3
wip/research/strategy_<topic>_phase4_*.md files exist    -> Phase 4
STRATEGY has Building Blocks section                     -> Phase 4
STRATEGY has Defensibility Thesis section                -> Phase 3
wip/strategy_<topic>_scope.md exists                     -> Phase 2
On a branch related to the topic                         -> Phase 1
On main or unrelated branch                              -> Phase 0
```
Multi-source: consults the durable STRATEGY doc AND its section content AND
multiple wip files. Status-aware re-entry IS present (Accepted/Active vs.
Draft branching). Note: the SKILL.md ladder names `wip/strategy_<topic>_scope.md`
but `phase-0-setup.md:142` and `phase-1-discover.md:35` actually create and
read `wip/strategy_<topic>_context.md` as the canonical entry-mode + phase-pointer
file (`scope.md` is the conversational-scope output). The on-disk shape is
both files, with `context.md` carrying the phase pointer; the SKILL.md ladder
omits this. **Concrete divergence between SKILL.md ladder and phase-file
behavior — note for `/charter` as evidence that ladders can drift from
phase scripts and must be specified canonically in one place.**

**`/prd`** (`skills/prd/SKILL.md:97-106`) — multi-source, 6 conditions:
```
PRD status "Accepted"                              -> Offer revise/fresh
PRD status "Draft"                                 -> Continue Phase 3
wip/research/prd_<topic>_phase2_*.md files exist   -> Phase 3
wip/prd_<topic>_scope.md exists                    -> Phase 2
On a branch related to the topic                   -> Phase 1
On main or unrelated branch                        -> Phase 0
```
Same shape as `/strategy` minus the section-content checks. Status-aware
re-entry IS present.

**`/vision`** (`skills/vision/SKILL.md:128-137`) — multi-source, 6 conditions,
structurally identical to `/prd` modulo artifact name.

**`/roadmap`** (`skills/roadmap/SKILL.md:137-146`) — multi-source, 6 conditions,
structurally identical to `/prd`/`/vision` modulo artifact name.

**`/design`** (`skills/design/SKILL.md:167-179`) — multi-source, 8 conditions,
including content-section checks (`Solution Architecture`, `Considered
Options`) and a JSON-file completeness check (`coordination.json` all complete
vs. some pending). Status-aware re-entry IS present.

**`/plan`** (`skills/plan/SKILL.md:213-229`) — multi-source, 8 conditions,
checks both `wip/` and external state (existing GitHub issues for this
design). The roadmap-input case checks the populated Implementation Issues
table inside the durable ROADMAP doc — a content-section check.
Status-aware re-entry is NOT explicit (no "PLAN exists Accepted/Draft" line),
but the GitHub-issues check serves the analogous function.

### Common ladder pattern across all seven

Every shipped ladder is **multi-source by default**: every ladder consults
at least two artifact types, and the more mature skills (`/strategy`,
`/design`, `/plan`) consult three or four. The scope-doc framing of `/charter`'s
ladder as "hybrid" (state file holds phase pointer; child status checked
against child docs) is therefore **not novel as a category** — it
matches the existing shape. What IS novel is the **boundary**: every shipped
ladder reasons over artifacts produced by THAT skill (its own wip files, its
own durable doc, its own research fan-out, optionally external state like
GitHub issues). No shipped ladder reasons over artifacts produced by
SIBLING SKILLS.

The common condition order is:
1. Durable-doc status checks (highest priority, Accepted/Active offer
   revise/fresh; Draft offer to continue) — present in all six skills with
   durable docs.
2. Late-phase research fan-out check (`wip/research/<skill>_<topic>_phase<N>_*.md`).
3. Mid-phase content-section checks (`/strategy`, `/design`).
4. Early-phase scope/context wip file check.
5. Branch-name match.
6. Main/unrelated branch → Phase 0.

### Hybrid composition validation for `/charter`

When `/charter` re-enters a partially-run child (e.g., user bailed during
`/strategy`'s Phase 3), the child's OWN resume ladder runs on entry: the
child sees its own STRATEGY-with-Defensibility-Thesis-section and resumes
at Phase 3. **This composes cleanly in isolation.** The risk surfaces in
three specific cases:

1. **Status-aware re-entry collision.** `/strategy` Resume condition 1
   (STRATEGY Accepted → "offer to revise or start fresh") prompts the user.
   If `/charter` invoked `/strategy` expecting a full-run exit, the child's
   own offer-to-revise UI hijacks `/charter`'s flow. `/charter` needs an
   invocation discipline: when invoking a child whose durable doc is already
   Accepted, `/charter` must DECIDE upfront (per its own phase logic) whether
   this is a re-evaluation exit (write Decision Record, don't invoke child)
   or a fresh run (signal the child to skip its own status check). Without
   that discipline, the child's ladder will surface options that contradict
   `/charter`'s phase state.

2. **Sibling-edit detection.** No shipped ladder detects edits to a
   sibling's doc. If a user edits `docs/visions/VISION-foo.md` outside
   `/charter` between two `/charter` runs, `/charter` has no native signal
   that the upstream changed. The hybrid design (state file holds phase
   pointer; child-status check against child doc) handles this only if
   `/charter` ALSO records the child doc's status/hash at the time of last
   exit and re-reads it on resume. The scope doc commits to child-status
   checks against child docs — this works if "status" includes durable
   markers like file mtime or a status-block timestamp; it does not work
   if "status" only means the Status: line.

3. **Multi-child phase ambiguity.** Six of the seven shipped ladders walk
   conditions in a strictly linear order. `/charter` walks a multi-child
   chain where the order is conditional on phase-1 discovery (does the
   chain need `/vision`? `/comp`? `/strategy`? `/roadmap`?). The ladder
   needs to encode "which children were in scope for this run" — the state
   file must record the planned chain, not just the current phase pointer.

### Implications for Requirements

- Specify the resume ladder's source-of-truth file canonically in ONE
  place (the PRD or design — not split across SKILL.md and phase files).
  The `/strategy` SKILL.md/`context.md` divergence is the existing
  cautionary example.
- The state file (`wip/charter_<topic>_state.md`) must record at minimum:
  (a) current phase pointer, (b) planned child chain (which of `/vision`,
  `/comp`, `/strategy`, `/roadmap` are in-scope for this run), (c) exit
  pointer (which exit fired, if any), (d) per-child status-snapshot at last
  exit (status line + an additional marker like mtime or content-hash) so
  sibling-edit detection works.
- The ladder must specify behavior when a child's own status-aware re-entry
  would prompt the user — `/charter` either suppresses the child's prompt
  (by signaling skip-status-check) or pre-empts it (by writing a Decision
  Record and never invoking the child).
- The ladder must specify cross-child phase-pointer transitions: when
  `/strategy` exits Draft → Accepted, `/charter`'s state file's phase pointer
  must advance. Either (a) `/charter` re-runs the ladder on every resume to
  recompute the phase, or (b) the state file is updated by the child or by
  `/charter` post-child-completion. The hybrid model implies (a) but it
  needs a requirement.

### Open Questions

- Does `/charter`'s state file get committed as wip/ (resumable across
  sessions and visible during review) or held in koto context (cloud-backed,
  not in git)? See Lead 3.
- When sibling-edit detection fires, what does `/charter` do? Re-prompt the
  user to choose chain branch, or re-run discovery? The scope doc commits
  to "robust to manual edits outside `/charter`" but doesn't specify
  behavior.

---

## Lead 2: Parent-skill pattern commitments

### Findings

For each candidate, verdict + justification:

**Three-exits-or-fail enforcement model** — **pattern-level**.
Every parent skill (`/charter`, future `/scope`, future `/work-on` migration)
needs to commit to terminal-artifact exits, because the parent-skill pattern's
core value-add is exactly this guarantee. The mapping from parent to specific
exit set differs (`/scope` chains `/prd`, `/design`, `/plan` so its exits look
different), but the meta-rule "the parent must commit to a finite set of
terminal-artifact exits, and finalization must verify one of them fired"
applies identically. Lift into shared design.

**Hard finalization check on exit-tracking field in state file** —
**pattern-level**. Direct corollary of the previous. Implementation detail —
where the field lives (wip file, koto context, koto decisions) is
storage-dependent — but the contract "no orphan parent-skill run; finalization
fails if no exit was recorded" applies to all three. Lift.

**Skill-existence gating for unshipped children** — **pattern-level**. `/scope`
will face the same situation as features mature unevenly; `/work-on`-as-parent
will face it once it loads conditional sub-skills. The mechanism (read SKILL.md
existence at the child's expected path) is identical across parents. Lift.

**Visibility-gated child invocation (e.g., `/comp` private-only)** —
**pattern-level**. The visibility detection mechanism (read CLAUDE.md `## Repo
Visibility:` header) is workspace-wide and parent-agnostic. `/scope` likely
has no visibility-gated child today, but `/work-on`-as-parent might (e.g., if
private-only sub-skills are added). The reading-the-header part is
pattern-level; the specific `/comp` mapping is `/charter`-specific. Lift the
mechanism, document the binding in `/charter`'s PRD.

**State file holding phase pointer + exit pointer** — **pattern-level**.
Same shape needed by every parent skill — phase pointer plus exit pointer is
the parent-skill state contract. Storage location is storage-dependent
(wip/ vs. koto) but the shape doesn't change. Lift.

**Manual fallback as first-class (any child invokable directly outside
parent)** — **pattern-level**. This is the steady-state surface for the
whole parent-skill pattern: parents amplify, they do not gate. `/scope`
needs this exact property (PRD/design/plan invokable directly today and that
must remain true after `/scope` ships). Lift.

**Cross-child resume ladder** — **pattern-level** (mechanism)
**+ /charter-specific** (concrete child set). The fact that a parent walks
a multi-source ladder over multiple child docs and its own state file is the
pattern. Which children (`/vision`, `/comp`, `/strategy`, `/roadmap` vs.
`/prd`, `/design`, `/plan`) is the specific binding. Lift the mechanism;
keep the binding in `/charter`'s PRD.

Additional candidate surfaced from reading: **status-snapshot-at-last-exit
for sibling-edit detection** — **pattern-level**. From Lead 1, this is
required for any parent that wants robustness against out-of-band child
edits. All three parent skills will face this. Lift.

**The discover/converge engine reference** — **uncertain**. The scope doc
treats engine extraction location as a design-team question. The need for
a phase-1 discovery dialogue is plausibly pattern-level (every parent skill
will have a phase-1 conversation to decide which children to invoke), but
the engine's reusability is unproven until `/scope` actually consumes it.
Mark as pattern-candidate; the designer can promote if `/scope`'s discovery
turns out structurally compatible.

### Implications for Requirements

The PRD's pattern-level vs `/charter`-specific tagging should mark:

**Pattern-level (lift to shared design):**
- Terminal-exits-or-fail enforcement model.
- Hard finalization check on exit-tracking state-file field.
- Skill-existence gating for unshipped children.
- Visibility-detection mechanism (read CLAUDE.md header).
- State file shape: phase pointer + planned chain + exit pointer +
  per-child status snapshot.
- Manual-fallback-as-first-class for children.
- Cross-child resume-ladder mechanism (status-snapshot diff against child
  docs).

**`/charter`-specific (stay in `/charter`'s PRD):**
- The specific four children and their delegation contracts.
- The specific three exits (full-run, re-evaluation Decision Record,
  abandonment-forced) and their artifacts.
- The specific `/comp`-private-only binding (mechanism is pattern-level;
  this binding is `/charter`'s).
- The specific discovery questions used to decide which children to invoke.

**Uncertain (designer's call):**
- Whether the discover/converge engine extraction is pattern-level enough
  to lift to the shared design or stays scoped to `/charter`.

### Open Questions

- Should the shared design doc be authored alongside `/charter`'s PRD or
  deferred until at least one other parent skill (`/scope` or `/work-on`
  migration) is in scope to validate "pattern-level" claims? The scope doc
  says `DESIGN-shirabe-progression-authoring.md` is shared — needs the PRD
  to make this commitment explicit.

---

## Lead 3: wip/-vs-koto-context tension

### Findings

shirabe `CLAUDE.md:54-73` documents the storage model precisely:

- **Non-koto workflows** use `wip/`. Committed to git. Visible during PR
  review. Cleaned before merge.
- **koto-driven workflows** use `koto context add`. Cloud-backed. Same
  review and traceability properties (per the CLAUDE.md framing). `wip/`
  is NOT a koto-driven-workflow location.
- Agent-side scratch when assembling content for koto context can use any
  on-disk location PROVIDED it's deleted post-`koto context add` or lives
  in auto-wiped paths. **Invariant: no persistent on-disk shadow of
  koto-managed content.**

Of the shipped skills, `/work-on` is the only koto-driven one
(`skills/work-on/SKILL.md:224-228`: resume is via `koto workflows` + `koto
next <WF>`, not file-based). `/explore`, `/strategy`, `/prd`, `/vision`,
`/roadmap`, `/design`, `/plan` are all wip/-based.

The brief frames `/charter`'s `wip/`-based intermediates as "against current
shirabe patterns" — that is **incorrect framing** as stated; `/charter` joining
the wip/-based group is exactly current shirabe pattern. The accurate
framing is: "against the long-term direction of koto-driven workflows
(which the future amplifier-layer-driven `/work-on` migration will live in),
but in-line with every shipped non-koto skill."

**Storage-agnostic aspects of `/charter`'s resume contract:**

- The resume LADDER itself (the ordered conditions and what they evaluate to)
  is pure logic over named state fields and child-doc inspection. Whether
  "state file phase pointer" lives in `wip/charter_<topic>_state.md` or in
  `koto context get charter_state` is a substitution at the storage layer.
- The CONTRACT shape (phase pointer + planned chain + exit pointer +
  per-child status snapshot) is identical across storage models.
- The child-doc inspection part is storage-agnostic — `docs/strategies/STRATEGY-*.md`
  lives at the same path under both models.
- The visibility-gating mechanism is storage-agnostic (reads CLAUDE.md, not
  state file).
- The skill-existence gating is storage-agnostic (reads `skills/<name>/SKILL.md`).

**`wip/`-specific aspects that don't translate:**

- **Git-visibility of state file.** Under `wip/`, the state file is committed
  to the feature branch and visible to reviewers and to the user. Under koto
  context, the state file is only visible via `koto context get` (and the
  user must run that command to see it). The audit-trail surface differs.
- **Cleanup-before-merge.** `wip/` artifacts MUST be cleaned before PR
  merge (per `references/wip-hygiene.md`); koto-context artifacts don't
  need cleanup (they're not in git). For `/charter`, this affects whether
  the state file outlives the chain or is destroyed at finalization.
- **No-orphan-references invariant.** `wip/` paths must not appear in any
  durable reference (frontmatter, prose, etc.). The state file's path is
  itself a wip/ path, so any cross-reference to it from durable docs is
  forbidden. Koto-context has no analogous restriction.
- **Branch coupling.** wip/ files are per-branch (live on the feature
  branch and travel with it). Koto context is per-workflow (lives in
  cloud storage keyed by workflow ID, independent of git branch). For
  `/charter`'s resume across sessions, the wip/ model requires the same
  branch; the koto model decouples.

For the resume contract specifically, **the contract IS storage-agnostic**.
The dual-implementation contract is achievable: specify the resume ladder
in terms of named state fields and child-doc inspections, with a storage-layer
mapping table that gives the wip/ and koto-context bindings.

### Implications for Requirements

- The PRD frames `/charter`'s resume-ladder requirements **storage-agnostically**:
  named state fields with abstract operations (get phase pointer, get
  planned chain, etc.) plus child-doc inspections. The wip/-based bindings
  appear as a concrete storage mapping, not as the contract itself.
- The PRD explicitly tags the wip/-specific commitments (cleanup-before-merge,
  no-orphan-references invariant) as orthogonal to the resume contract.
  They are `wip/`-implementation discipline, not contract terms.
- The brief's framing of `wip/` as "against current shirabe patterns" should
  be corrected in the PRD: wip/ is the current pattern for all six
  non-koto skills; koto-context is the future direction for amplifier-layer
  workflows.
- The dual-implementation contract bounding (brief Open Question 4) gets
  the concrete shape: the contract is the named-fields-plus-doc-inspections
  layer; the mapping to wip/ vs koto-context is the storage-layer detail.
- One concrete risk to flag for the designer: the state file's
  branch-coupling under wip/ means `/charter` resume requires the same
  branch as the original run. Under koto-context, branch-decoupling allows
  resume across branches. If `/charter`'s exit-tracking ever needs to
  cross branches (e.g., merge of one child's PR followed by `/charter`
  resume on main to invoke the next child), wip/ model breaks.

### Open Questions

- Does `/charter` v1 require the state-file path to be reachable from
  multiple branches? The wip/-based model effectively answers no (the chain
  runs on one feature branch from invocation to exit). If yes, wip/ is
  insufficient and the amplifier-layer freeze line has to bound that
  capability.
- Does the cleanup-before-merge invariant apply to `/charter`'s state file
  the same as other wip/ artifacts, or is it a special case (e.g., kept
  alive across merges)? The scope doc commits to "robust to manual edits
  outside `/charter`" — does that imply the state file survives across
  PR merges, contradicting wip/ hygiene?

---

## Lead 4: shirabe validate / CI enforcement

### Findings

CI workflows in `.github/workflows/`:

- `validate-docs.yml`: callable workflow. Builds `shirabe` binary, runs
  `shirabe validate --visibility=${{ github.repository_visibility }}` on
  changed `docs/**` files. This is the only workflow that touches
  produced-artifact content.
- `check-evals.yml`, `check-plan-docs.yml`, `check-plan-scripts.yml`,
  `check-sentinel.yml`, `check-template-consistency.yml`,
  `check-templates.yml`, `check-work-on-scripts.yml`: structural integrity
  checks on skill templates, eval files, plan/work-on scripts. None touch
  `wip/` content.

`shirabe validate` checks (from `internal/validate/checks.go`):

- **R6**: PLAN doc `upstream:` field exists on disk and is git-tracked.
- **R7**: VISION docs in public repos must not contain forbidden sections
  (Competitive Considerations).
- **R8**: STRATEGY docs in public repos must not contain forbidden sections
  (Competitive Considerations).
- Visibility detection: `--visibility=<public|private>` flag, supplied from
  `github.repository_visibility` in CI. Empty visibility fails closed (R7/R8
  treat it as "must not contain prohibited sections," matching public repo
  behavior).
- Frontmatter validation: status values per artifact-type schema, custom
  statuses supported via `--custom-statuses` flag.

There is **no validator check** for:
- `wip/` cleanup state — not enforced by the binary, only by skill-phase
  scripts (per `references/wip-hygiene.md:64-73`) and by the verification
  commands an author runs before opening a PR.
- Produced-artifact-path existence after a skill run — no post-run check
  binds skill output paths to filesystem state.
- Visibility-gated child invocation — no check verifies that a private-only
  artifact never lands in a public repo (R7/R8 catch the section-content
  side; nothing catches a `docs/competitive/COMP-*.md` file existing in a
  public repo).

The wip-hygiene enforcement is "skill-phase scripts hard-stop on violations"
(`references/wip-hygiene.md:65-66`) — meaning each consuming skill is
responsible for grep-ing for `wip/` references in its own output before
landing the durable artifact. There is no centralized CI check.

### Implications for Requirements

- `/charter`'s produced artifacts (Draft STRATEGY, optional ROADMAP, Decision
  Record, abandonment-forced materializations) must pass `shirabe validate`
  on commit. Specifically:
  - STRATEGY draft: must not contain Competitive Considerations sections
    when committed to a public repo. R8 catches violations. `/charter`'s
    `/strategy` delegation already inherits this from `/strategy` itself.
  - Decision Record (`docs/decisions/DECISION-strategy-<scope>-re-evaluation.md`):
    must pass whatever schema validator applies. The scope doc references
    a `skills/decision/` directory — that needs separate verification that
    the schema is in place (research lead 4 from the scope doc, not in
    this lead's brief).
- `/charter` must run the wip-hygiene grep on its own outputs before
  finalization. The state file path is itself `wip/charter_<topic>_state.md`;
  if `/charter` writes any durable artifact that references this path,
  the grep step catches it before commit.
- No CI check exists for the abandonment-forced exit's materialized
  intermediate. `/charter` is responsible for ensuring that the
  force-materialized artifact passes whatever validators apply to its
  artifact type (e.g., if a partial STRATEGY draft is materialized, it
  must pass STRATEGY schema + R8). Requirement: abandonment-forced
  materialization writes an artifact in the same schema-compliant shape
  as a full-run artifact.
- `/charter` does not need to add a new CI check. The existing
  `validate-docs.yml` workflow covers everything `/charter` produces under
  `docs/`. `/charter` only needs to ensure its outputs comply.

---

## Summary

`/charter`'s "hybrid resume ladder" matches the multi-source shape of every
shipped shirabe ladder — the novel part is reasoning across CHILD-SKILL
boundaries, which no shipped skill does, and the discipline this requires
(status-snapshot per child to detect out-of-band edits; pre-emption of
child status-aware re-entry to prevent UI hijack of `/charter`'s flow;
planned-chain state-file field to disambiguate multi-child phase pointers).
The pattern-level commitments — three-exits-or-fail, exit-pointer
finalization check, skill-existence gating, visibility-detection mechanism,
state-file shape (phase pointer + planned chain + exit pointer +
per-child status snapshot), manual-fallback-first-class, and the
cross-child resume mechanism — should be lifted into the shared design;
the specific four-child chain, the three named exits, and the `/comp`
private-only binding stay in `/charter`'s PRD. The `wip/`-vs-koto-context
tension dissolves at the contract layer: the resume ladder's contract is
storage-agnostic (named state fields plus child-doc inspections), and the
wip/-implementation discipline (cleanup-before-merge, no-orphan-references)
is orthogonal to it — the brief's framing of wip/ as "against current
patterns" should be corrected in the PRD since wip/ IS the current pattern
for all six non-koto skills. CI enforcement is limited: `shirabe validate`
checks R6/R7/R8 on committed `docs/**` files, no wip/-cleanup CI exists, and
`/charter`'s only CI obligation is producing schema-compliant durable
artifacts (a constraint that applies equally to the abandonment-forced
materialization, which must be schema-compliant as a full run).
