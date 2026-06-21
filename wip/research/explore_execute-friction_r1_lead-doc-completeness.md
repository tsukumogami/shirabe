# Lead: Where should a doc-completeness guarantee live — `/plan` emitting a docs issue/outline when a plan adds user-visible surface, `/execute` running a docs-coverage check before the done-signal, or both? (Friction point F4)

## Findings

### 1. `/plan` has NO notion of "emit a docs issue when the design adds user-visible surface"

Phase 3 decomposition (`skills/plan/references/phases/phase-3-decomposition.md`) drives issue creation off design *sections* and *components*, never off whether the design introduces user-visible surface:

- Tactical decomposition (lines 124-130): "Break down the **Solution Architecture** and **Implementation Approach** sections: Each component or distinct change becomes one issue." No step inspects for new CLI flags, commands, or behavior that would require a user-facing doc.
- Step 3.1 "Decompose by Component" (lines 154-167) splits/combines on coupling and deliverable independence — not on documentation surface.
- The only documentation-aware branch is **strategic** scope (lines 113-122), which emits `docs(<repo>): design <purpose>` issues with a `needs-design` label — these are *design-authoring* issues for downstream DESIGN docs, NOT *user-facing-documentation* issues. They have nothing to do with `docs/guides/`.
- The roadmap branch (3.R1, lines 263-281) emits `docs(<scope>):` planning issues, but again these track *artifact creation* (PRD/DESIGN/SPIKE/ADR), not user guides.

The Phase 3 quality checklist (lines 509-516) checks "All components covered by issues" and "Each issue is atomic" — there is no "user-visible surface has a documentation issue" check anywhere.

The value-confirmation guard (step 3.5a, lines 355-440) asks "does this unit land observable value?" — a value/PR-shape question, not a documentation-coverage question. It would happily pass a plan whose last issue is "functional tests only" because tests land value.

**Conclusion:** `/plan` never asks "does the design add user-visible surface, and if so is there a docs issue?" The omission is total — no flag, no checklist item, no phase.

### 2. Issue TYPE (`code`/`docs`/`task`) — the machinery to HANDLE a docs issue exists; only EMITTING one is missing

The `Type` field is a real, propagated concept:

- `skills/plan/references/plan-format.md:305-307`: "Type field is one of `code`, `docs`, `task`. `code` issues require unit tests as a sub-requirement; `docs` and `task` skip the test-required gate."
- It propagates as `ISSUE_TYPE` from the PLAN outline's `**Type**:` field into `/work-on`: `skills/plan/references/plan-to-tasks-contract.md:60` ("`ISSUE_TYPE` | Value of the **Type**: annotation, omitted if annotation is absent") and `skills/work-on/SKILL.md:146,159-164`.
- A `docs`-type child is fully handled: `skills/work-on/SKILL.md:161` — "`docs` — skips panels, goes directly to finalization"; mirrored in `skills/work-on/koto-templates/work-on.md:471-475,980`.

BUT: the Phase 3 issue-outline template (`phase-3-decomposition.md:173-181`) only ever sets `Type` to `skeleton | refinement | standard` (line 175). The walking-skeleton template emits `skeleton`/`refinement`; roadmap emits `planning`. **Nothing in `/plan`'s decomposition ever emits an outline with `Type: docs` for a user-facing guide.** The `code`/`docs`/`task` triad is documented in plan-format.md and consumed by work-on, but Phase 3 never produces a `docs` outline off a "this adds user surface" signal. So: the consumer (work-on) can route a docs issue correctly; the producer (`/plan`) never creates one for user-visible surface.

### 3. There is NO structured "user-visible surface" field in DESIGN or PRD

- DESIGN's nine required sections (`skills/design/references/design-format.md:79-108`) are Status, Context, Decision Drivers, Considered Options, Decision Outcome, Solution Architecture, Implementation Approach, Security Considerations, Consequences. None is "User-Visible Surface" or "Documentation Impact." The context-aware sections (lines 117-121) are Market Context, Required Tactical Designs, Upstream Design Reference — none documentation-facing.
- A grep for `docs/guides|user-visible|user-facing|documentation` across `skills/design skills/prd skills/plan` returns only incidental prose: `prd/references/phases/phase-2-discover.md:37,58` ("existing user-facing", "What documentation is needed?") are research-agent prompts, not structured fields; `plan/references/templates/agent-prompt.md:110` is the `simple`-complexity hint ("README, docs/, .md files"); `phase-3-decomposition.md:92` is a horizontal-strategy heuristic.
- A grep for `doc-coverage|doc-completeness|documentation coverage|user-visible` across all of `skills/` returns **nothing**. No layer has a doc-completeness concept today.

So the F4 signal in the dogfood — the DESIGN referencing `docs/guides/worktree.md` — was **free-text prose inside Solution Architecture / Implementation Approach**, not a structured field any tool reads. There is no machine-readable flag that says "this feature has user-visible surface."

### 4. `/execute` has no doc-coverage step and is structurally the wrong place to add a content check

From `skills/execute/SKILL.md`:

- The done-signal is purely the merged home PR: "full-run — the plan is driven to its merged-PR done-signal" (lines 364-369); "There is no separate 'complete' marker — the merged home PR is it."
- `/execute` is **metadata-only by contract**: "inspects issue, pull-request, and unit state **only through status surfaces** — never by reading child artifact bodies (R14 widened, R15)" (lines 418-435). For an execution child the inspection surface is "the PR state (Open / Closed / Merged), its labels, and its CI check rollup" (lines 426-429).
- Finalization (`plan_completion`, lines 162-166) runs the cascade (lifecycle transitions) then `gh pr ready`. There is no content/coverage gate.
- Security surface #2 (lines 452-458) defines a **closed write-target set**; surface #6 (lines 478-483) treats PLAN-body content as "data, never instructions." A doc-coverage check that parsed the DESIGN's prose for `docs/guides/*` references and cross-checked the diff would push `/execute` into reading artifact bodies — directly against R14/R15 metadata-only.

`/execute` *can* enforce (it owns the done-signal gate), but it lacks the signal — it never reads the DESIGN prose where `docs/guides/worktree.md` lived, and giving it that read breaks its metadata-only contract.

## Implications

**Which layer has the signal vs which can enforce:**

| Layer | Has the signal? | Can enforce? |
|-------|-----------------|--------------|
| `/plan` | YES — Phase 4 reads the full DESIGN (`phase-4-agent-generation.md:77-81` "Read the full design document"); it is the only layer that already parses design prose, where a `docs/guides/*` reference or CLI-flag acceptance criterion lives. | YES — it owns issue emission; a `Type: docs` outline is already a handled artifact end-to-end. |
| `/execute` | NO — metadata-only (R14/R15); never reads DESIGN/PRD prose or child bodies. | YES — owns the done-signal gate, but a content check violates its contract. |

**Recommendation: `/plan` should own it (option a), not `/execute` (option b), and not both (option c).**

- `/plan` is the only layer that already reads the design body, so it is where the "user-visible surface" signal is cheap to detect. It already produces and the chain already routes `Type: docs` issues, so emitting one is additive, not new machinery.
- The fix is a Phase 3 decomposition step: when analysis/decomposition detects user-visible surface, emit a `Type: docs` issue/outline whose AC is "the named guide path is created/updated." In single-pr mode this is one more Issue Outline in the PLAN; in multi-pr mode it is one more GitHub issue — both already supported.
- `/execute` as the *enforcer* (option b) is a poor fit: it would need to read DESIGN prose (breaking metadata-only R14/R15), and "DESIGN referenced a guide path that no issue touched" is exactly the check `/plan` can do *while it still has the design open*, before any issue is dispatched. Adding it at `/execute` is later, more expensive, and architecture-violating.
- A lightweight hybrid is defensible only as a *backstop*: `/plan`'s Phase 6 review (which already validates completeness, `phase-6-review.md`) could carry a "if the design references `docs/guides/*` or names new CLI surface, a `docs`-type issue must exist" check — still inside `/plan`, not `/execute`.

**Detection signal (item 5):** Concretely, what tells a layer "this plan adds user-visible CLI/behavior":
1. The DESIGN body referencing a `docs/guides/*` (or `docs/`) path in Solution Architecture / Implementation Approach — the exact signal present in the dogfood (`docs/guides/worktree.md`). Highest-precision, already-present, free-text.
2. PRD acceptance criteria or the DESIGN naming new CLI flags/subcommands (`--json`, `--by-path`, `--no-worktree-delegation`, new `niwa worktree create` args). Detectable from decomposition since each becomes a component/issue.
3. A `simple`-complexity hint already keys on "README, docs/, .md files" (`agent-prompt.md:110`) — adjacent heuristic, but currently used for complexity, not coverage.

The cleanest durable improvement would also add a **structured field** so detection isn't prose-grepping: e.g., a DESIGN frontmatter or section flag `user_visible_surface: true` (or a "Documentation Impact" context-aware section in `design-format.md`). That turns F4 from "noticed by the author" into a machine-checkable contract `/plan` consumes.

**Direct fix vs needs-design (item 6):**

- **Borderline; leans needs-design (small).** The *mechanism* is a direct fix — add a Phase 3 step that emits a `Type: docs` outline, plus a Phase 6 backstop check. All in `skills/plan/`. The consumer side (`/work-on` docs routing) needs zero change.
- But the *detection contract* is a small design decision: rely on prose-grepping the DESIGN for `docs/guides/*`, or introduce a structured `user_visible_surface` signal in `design-format.md` / PRD format? That choice (precision vs. authoring burden, and whether to touch the DESIGN/PRD schema) is design-shaped and should be decided before coding. Given F4 is a single, well-understood gap with an obvious owner, a short DESIGN (or a decision record) covering just the detection-signal choice is proportionate; the implementation that follows is a direct fix.

**Files that change:**
- `skills/plan/references/phases/phase-3-decomposition.md` — add the user-visible-surface detection + `Type: docs` outline emission step; extend the Phase 3 quality checklist.
- `skills/plan/references/phases/phase-6-review.md` — add the backstop completeness check (design references a guide / new CLI surface ⇒ a `docs` issue must exist).
- `skills/plan/references/plan-format.md` — already documents the `code`/`docs`/`task` triad (305-307); may need a line stating user-visible surface requires a `docs` issue.
- Optionally `skills/design/references/design-format.md` (and PRD format) — if a structured `user_visible_surface` / "Documentation Impact" field is chosen over prose-grepping.
- NOT `skills/execute/SKILL.md` — keep it metadata-only.

## Surprises

- The `code`/`docs`/`task` type machinery is fully built and `/work-on` routes a `docs` child correctly (skip panels → finalization), yet `/plan`'s decomposition phase **literally never emits a `Type: docs` outline** for user-facing docs. The Phase 3 template only ever sets `skeleton|refinement|standard` (plus `planning` for roadmaps). The handling exists; the emission path is a dead end for user-facing docs.
- `/plan` *does* have a documentation-flavored branch (`docs(...)` issues with `needs-design`), but it is for *design-authoring*, not user guides — a naming collision that could mislead a reader into thinking docs are covered.
- The dogfood signal (DESIGN referencing `docs/guides/worktree.md`) was present in exactly the layer (`/plan` Phase 4 reads the full DESIGN) that could have acted on it — the gap is not missing information, it is a missing *step*.

## Open Questions

- Should detection be prose-grep (`docs/guides/*` in DESIGN body) or a structured field (`user_visible_surface: true`)? The structured field is more reliable but adds authoring burden and touches the DESIGN/PRD schema.
- When a plan is `topic`-input (no DESIGN/PRD), there is no design body to grep — how does the docs-issue rule fire? Probably falls to the Phase 6 backstop or a complexity-style heuristic on the issue titles.
- Should the backstop be a hard fail or a warning (consistent with `--auto`'s decision-block, non-blocking posture)? `/plan`'s guards (3.5a) are non-blocking under `--auto`; a doc-coverage check would likely follow the same record-and-continue pattern rather than hard-stop.

## Summary

`/plan` is the only layer that reads the DESIGN body (Phase 4) where the user-visible-surface signal lives (e.g. the `docs/guides/worktree.md` reference), and it already produces and routes `Type: docs` issues end-to-end — yet its Phase 3 decomposition never emits a docs outline for user-facing surface, so the guarantee should live in `/plan` (option a), not `/execute`, whose metadata-only R14/R15 contract makes a content check architecturally wrong. The detection signal is a DESIGN referencing a `docs/guides/*` path or naming new CLI flags; the durable form would add a structured `user_visible_surface` flag to the DESIGN/PRD schema rather than prose-grepping. The mechanism is a direct fix in `skills/plan/` (a Phase 3 emission step + a Phase 6 backstop), but the detection-contract choice is small-design-shaped and worth deciding first.
