# Architecture Review: Completion Cascade — Solution Architecture and Implementation Approach

## Scope

Review of the Solution Architecture and Implementation Approach sections of
`docs/designs/DESIGN-completion-cascade.md`, cross-referenced against:

- `skills/work-on/SKILL.md` and `skills/work-on/koto-templates/work-on-plan.md` (current plan_completion directive)
- `skills/design/scripts/transition-status.sh`, `skills/prd/scripts/transition-status.sh`,
  `skills/roadmap/scripts/transition-status.sh` (the per-skill scripts the cascade calls)
- `skills/work-on/evals/evals.json` (eval #26 and related plan-mode evals)
- `docs/roadmaps/ROADMAP-strategic-pipeline.md` (real upstream structure for validation)
- `wip/research/design_completion-cascade_phase5_security.md` (prior security review)

---

## Q1: Is the architecture clear enough to implement without ambiguity?

**Mostly yes, with two specific gaps.**

The main loop, data flow diagram, and per-handler interface definitions are
precise enough to implement directly. The component tree, the CLI contract
(`--push` flag, exit codes, JSON output shape), and the idempotency guarantee
are all well-specified.

**Gap 1 — `validate_upstream_path` is missing from the Components tree.**

The Components block lists five functions inside `run-cascade.sh`:

```
├── get_frontmatter_field()
├── validate_upstream_path()     ← present here
├── check_issue_closed()
├── handle_design()
├── handle_prd()
├── handle_roadmap()
```

Wait — `validate_upstream_path` IS listed in the Components tree shown in the
design doc body (line 184-ish), but the version provided for review in the
prompt omits it. The body also documents its interface under "Key Interfaces".
The inconsistency is between the review prompt's excerpt and the committed
doc — not an internal inconsistency in the committed design. The committed doc
is internally consistent on this point.

**Gap 2 — `strip_implementation_issues` is not in the Components tree.**

The Components tree says `handle_design()` strips Implementation Issues and
then transitions to Current, and the body documents it as:

> 1. Call `strip_implementation_issues` — idempotent awk strip of `## Implementation Issues` section.

But `strip_implementation_issues` is not named in the component tree alongside
the other inline functions. An implementer reading only the component diagram
would not know a fifth utility function needs to be written. The omission
creates ambiguity about whether this is a named function or inline logic inside
`handle_design`. The design doc should either add it to the component tree or
make explicit that the strip is anonymous inline logic.

**Gap 3 — Commit granularity.**

The design specifies a single final commit ("all staged changes in a single
commit: `chore(cascade): post-implementation artifact transitions`"), which
differs from the current `work-on-plan.md` template's approach of one commit
per step with individual push calls. The design is clear about the chosen
approach, but the change from multi-commit to single-commit has a consequence
that is not flagged: if `git push` fails after staging six files, recovery
requires the operator to understand what the script staged and why. A
checkpoint or log of what was staged before the push would close this
observability gap.

---

## Q2: Are there missing components or interfaces?

**Two missing pieces; one underspecified interface.**

**Missing: Eval fixture docs for the new cascade scenarios.**

Phase 3 calls for two new Tier 2 execute-mode scenarios:
`e2e-cascade-design-roadmap` and `e2e-cascade-design-prd-roadmap`. The
existing Tier 2 scenarios all rely on fixture files under
`skills/work-on/evals/fixtures/scenarios/<name>/`. The new scenarios require
fixture PLAN, DESIGN, (PRD), and ROADMAP docs with correct frontmatter
`upstream` chains for the script to traverse. These fixtures are not mentioned
in Phase 3's deliverables list. Without them, the eval harness has nowhere to
call `run-cascade.sh` against real files.

The fixture PLAN doc at `skills/work-on/evals/fixtures/plans/PLAN-diamond-test.md`
currently has no `upstream` field. The new scenarios need their own fixture PLAN
doc (or an extended version) that chains through the full upstream topology.

**Missing: `check_issue_closed` is listed in Components but not used by any handler.**

The component tree includes `check_issue_closed()` as an inline function, and
the Key Interfaces section documents its signature. But none of the three
handler descriptions (`handle_design`, `handle_prd`, `handle_roadmap`) mention
calling it. The Data Flow diagram also does not show `check_issue_closed` in
any path. Either the function should be called somewhere (its likely intent is
to guard the ROADMAP Done transition — only transition if all tracked issues
are closed), or the component tree and Key Interfaces section should remove it
to avoid confusing implementers.

**Underspecified: ROADMAP feature entry lookup.**

`handle_roadmap` locates the relevant feature entry by plan slug using
`grep -F`. The design gives the algorithm in prose but doesn't specify what
the "plan slug" looks like relative to typical ROADMAP content. Inspecting
real ROADMAP docs (e.g., `ROADMAP-strategic-pipeline.md`), features reference
PLAN docs indirectly through the `**Downstream:**` field, not directly by PLAN
slug. A feature entry contains lines like `DESIGN-work-on-koto-unification.md
(Current)` — not the plan slug. The design should specify which field or
phrase the grep targets, and what the script does when the plan slug doesn't
appear literally in the ROADMAP.

---

## Q3: Are the implementation phases correctly sequenced?

**Yes, with one dependency clarification needed.**

The phase order (script + tests → template update → evals) is correct:

- Phase 1 creates the invocable script. Phase 2 can't reference the script
  until Phase 1 exists.
- Phase 3 evals exercise the real script, so they depend on Phase 1.
- Phase 2's template update depends on Phase 1 being stable enough to invoke.

The only sequencing note: `work-on-plan.md` currently has its own
`plan_completion` prose that works (albeit with the topology bug). Phase 2
should not land until Phase 1 passes its own test harness — otherwise the
cascade regresses. The design implies this but does not state it explicitly as
a merge gate.

The phase split is also slightly asymmetric: Phase 1 includes the test script
but Phase 3 includes the eval scenarios. An implementer might ask why the
`run-cascade_test.sh` (shell-level unit tests) ships in Phase 1 but the eval
scenarios (execute-mode integration tests) wait until Phase 3. This is
appropriate because the eval framework requires the script to be integrated
into the template first (Phase 2) to be meaningful as an e2e test. The
ordering holds.

---

## Q4: Are there simpler alternatives overlooked?

**One worth noting; one previously considered and correctly rejected.**

**Worth noting: deferred push via `git stash`.**

The `--push` flag is the chosen mechanism for separating staging from pushing.
An alternative that preserves the single-commit structure and avoids the
flag-passing surface: run all file mutations and `git add` calls, then print a
diff summary and exit 0 without committing unless `--commit` is passed. This
is slightly simpler than `--push` because it leaves no staged state on failure
(no partial commit for the agent to clean up). The design's chosen approach
works and has clear precedent (the `plan_completion` directive passes `--push`
explicitly), so this is not a blocking concern — just an alternative worth
knowing about.

**Previously rejected but reconsidered: multi-commit approach.**

The current `work-on-plan.md` uses one commit + push per step. The design
collapses this to a single commit. The tradeoff: single commit is a cleaner
history entry but has a larger atomic blast radius on push failure. Given that
the script already has idempotency as a design goal (each transition script
skips if already at target), a multi-commit approach would actually be simpler
to recover from after partial failures, because the operator can inspect git
log to see which steps ran. The design's choice of single commit is not wrong,
but the recovery story for a mid-run push failure deserves one sentence in
Consequences.

---

## Summary Findings

1. **`strip_implementation_issues` is absent from the Components tree.** Add it as a named entry alongside the other inline functions, or explicitly say it is anonymous inline logic in `handle_design`. Either is fine; leaving it implicit creates implementer ambiguity.

2. **`check_issue_closed` has no call site in any handler.** The function is listed in Components and has a documented interface, but nothing calls it. Either assign it a concrete call site (most logical: guard the `handle_roadmap` Done transition) or remove it from the architecture to avoid dead code.

3. **Phase 3 fixture docs are not listed as Phase 3 deliverables.** The two new Tier 2 execute-mode scenarios require fixture PLAN, DESIGN, PRD, and ROADMAP docs with correct `upstream` chains. These need to be explicit deliverables, or the eval scenarios cannot run. The existing `PLAN-diamond-test.md` fixture has no `upstream` field and cannot serve this purpose.

4. **ROADMAP feature-entry lookup needs a concrete field target.** Real ROADMAP documents (verified in `ROADMAP-strategic-pipeline.md`) reference downstream artifacts through `**Downstream:**` fields, not direct plan slug mentions. The design's "grep -F by plan slug" approach may not find anything in practice. The interface spec should name the exact field the script searches and define the fallback.

5. **Eval #26 update is underspecified.** Phase 3 says "update Tier 1 assertions for eval #26 to reference `run-cascade.sh`." The current eval #26 expectations enumerate individual prose steps (git rm, transition DESIGN, transition PRD, update ROADMAP, etc.). The updated assertions should verify the agent invokes `run-cascade.sh --push {{PLAN_DOC}}` as a single command, not the individual steps. The design should say this explicitly so the eval update matches the new contract rather than just rewording the old expectations.
