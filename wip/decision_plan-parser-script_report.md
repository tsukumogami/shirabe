<!-- decision:start id="plan-parser-script" status="assumed" -->
### Decision: How should /work-on obtain koto tasks evidence from a PLAN doc?

**Context**

The approved `DESIGN-work-on-koto-unification.md` specifies that the plan
orchestrator template (`work-on-plan.md`) accepts a `tasks`-typed evidence
field that koto's scheduler materializes into child workflows. The question
is how `/work-on` produces that evidence payload from a PLAN doc at the
`parse_plan` state.

Three constraints bound the answer:

1. **No main-branch pollution.** Only `PLAN-*.md` files in `docs/plans/`
   are canonical. Machine-readable derivatives must not commit to main.
   Multi-pr plans routinely merge to main; any JSON sidecar committed
   alongside PLAN.md would accumulate in main's history.
2. **No `wip/` for workflow state.** The current `/work-on` skill uses
   koto's context store (`koto context add` / `koto context get`) as the
   primary state path; `wip/` is only a degradation fallback when koto is
   unreachable. The `work-on.md` template has no `wip/` references, and
   Phase 5 finalization explicitly notes "No manual `rm -rf wip/` needed."
   Any new design must preserve this koto-native invariant.
3. **Format authority.** `/plan` is the PLAN.md format authority. It
   writes `schema: plan/v1` and owns the Implementation Issues table,
   Dependency Graph, and Issue Outlines sections. Parsing logic should
   co-locate with the authority that controls format evolution so that
   schema changes ripple in one PR, not across skills.

The prior decision round proposed a sidecar in `docs/plans/` (rejected
for pollution), then a sidecar in `wip/` (rejected for violating the
koto-native principle). The question was taken back to the /decision
framework for a rigorous re-evaluation against the full constraint set.

**Assumptions**

- Koto accepts evidence via stdin (`--with-data @-`) or, failing that, a
  tempfile path. If neither works, a `mktemp` + `rm` sandwich in
  `$TMPDIR` is always available. The tempfile never reaches the repo tree.
- PLAN.md structured sections (Implementation Issues table, Dependency
  Graph, Issue Outlines) are stable enough that a parser script has
  bounded maintenance cost. Schema evolution (`plan/v1` -> `v2`) would
  update the parser alongside /plan's writer in one PR.
- /plan skill changes are in scope for the work-on-koto-unification
  rollout. Both skills live in the same repo; a cross-skill contract is
  reviewable together.

**Chosen: Parser script owned by /plan, piped to koto by /work-on (Option B)**

Add `skills/plan/scripts/plan-to-tasks.sh` (bash + jq, following the
existing `build-dependency-graph.sh` pattern):
- Input: PLAN.md path as argument
- Output: tasks JSON on stdout, matching koto's task-entry schema
  (array of `{name, vars, waits_on}` with `template` omitted so the
  `default_template` on the hook applies)
- Exit codes: 0 success, 1 malformed input, 2 PLAN schema mismatch
- Unit-tested via `plan-to-tasks_test.sh` with fixture PLANs covering:
  multi-pr mode (Implementation Issues table), single-pr mode (Issue
  Outlines), struck-through rows, child reference rows, empty
  dependencies, diamond dependency patterns

The `/work-on` plan-orchestrator template's `parse_plan` state directive
invokes the script and pipes directly into koto:

```bash
bash "${SHIRABE_ROOT}/skills/plan/scripts/plan-to-tasks.sh" "$PLAN_DOC" \
  | koto next "$WF" --with-data @-
```

If koto rejects stdin, the fallback is a `mktemp` sandwich cleaned in the
same shell expression:

```bash
TMP=$(mktemp) && trap "rm -f $TMP" EXIT \
  && bash "${SHIRABE_ROOT}/skills/plan/scripts/plan-to-tasks.sh" \
       "$PLAN_DOC" > "$TMP" \
  && koto next "$WF" --with-data "@$TMP"
```

The tempfile (if used) lives in `$TMPDIR`, exists for microseconds, and
is never under the repo tree. No commit-able artifact is produced at any
point. After submission, koto's context is the source of truth:
`koto context get <WF> tasks` retrieves the submitted payload on resume,
and re-submission is a no-op under koto's union-by-name rules.

Rerunning from a merged PLAN (e.g., a fresh branch that only has the
committed `docs/plans/PLAN-foo.md`) requires nothing new -- the script
regenerates tasks JSON deterministically from the markdown. No "rebuild
mode" or special command; the script is always the source of truth for
PLAN-to-JSON transformation.

**Rationale**

Option B is the only alternative that satisfies all three constraints:
format authority (script lives with /plan), koto-native persistence (no
`wip/`, no repo-tree artifacts), and no main pollution (nothing committed
beyond PLAN.md itself).

The format authority principle decides between B and C. Both produce
identical runtime behavior, but B places the parser with the writer:
when /plan changes PLAN schema, the script updates in the same PR, CI
validates both sides. If the parser lived in /work-on (Option C), schema
changes would require coordinated updates across skills and risk silent
drift. Shirabe's existing pattern already places PLAN utilities
(`build-dependency-graph.sh`, `create-issues-batch.sh`) in /plan; B
extends that pattern.

The koto-native principle decides against A and I. Option A pays 10-15k
tokens per parse with no CI safety net, compounded across resume cycles.
Option I is a hybrid that keeps A's token costs while adding B's
maintenance burden -- the worst of both.

The no-pollution principle decides against F. Embedding task data inline
in PLAN.md eliminates external files but duplicates the Implementation
Issues table content, risks editor drift, and forces a schema migration.
The sidecar-free piping in B achieves the same "no external file" goal
without in-doc duplication.

Cross-skill contract scope is narrow and stable: one script (`plan-to-tasks.sh`),
one argument (PLAN path), one stdout format (koto task-entry JSON). The
contract is a CLI shape, not shared code. Either skill can evolve
independently as long as the CLI shape holds.

**Alternatives Considered**

- **Option A: Inline prose parsing in /work-on.** Rejected because
  10-15k tokens per parse and LLM reliability on edge cases (struck-through
  rows, child reference rows, multi-line descriptions, Mermaid graph
  edges) make this the least defensible path. No CI testability. The
  "no scripts" framing from the prior Decision 2 was about orchestration
  (scheduling, dispatch), not input translation -- a distinction that
  matters here.

- **Option C: Parser script owned by /work-on.** Rejected on format
  authority grounds. Script produces identical runtime results to B, but
  places the parser in the reader rather than the writer. PLAN schema
  evolution becomes a cross-skill coordination problem with no CI
  bridge. Shirabe's existing pattern puts PLAN utilities in /plan;
  deviating here would fragment the convention.

- **Option F: Machine-readable block embedded in PLAN.md.** Rejected
  because it duplicates Implementation Issues content inline and forces
  a `plan/v1` -> `v2` schema migration. Two views of the same data in
  one file, with no generator/generated relationship, risks editor
  drift. Frontmatter grows unwieldy for 30+ issue plans.

- **Option I: Hybrid (prose + targeted script calls).** Rejected as
  worst-of-both: still pays Option A's token costs, still needs Option
  B's CI test surface, with ambiguous responsibility boundaries.

- **Options D, E, G, H, J rejected up-front:** sidecar in `docs/plans/`
  (main pollution), sidecar in `wip/` (violates koto-native principle),
  dedicated CLI binary (over-scoped), koto-side parser (out of shirabe's
  control), /plan inits koto workflow directly (conflates roles and
  breaks merged-PLAN-resume).

**Consequences**

What becomes easier:
- Deterministic, CI-testable PLAN parsing via a fixture-driven test
  suite. Regressions in table parsing, strikethrough handling, or
  dependency extraction surface in CI, not in a failed koto submission.
- Zero runtime tokens for PLAN parsing. Resume cycles stay cheap.
- Koto-native flow preserved: submission goes directly to koto's context
  store, subsequent reads via `koto context get`, no repo-tree
  intermediaries.
- Format authority maintained: /plan owns both writing and reading
  PLAN.md; schema changes ripple in one PR.
- Rerunning from a merged PLAN requires no special ceremony -- the
  script is the transformation, invoked identically on fresh branches.

What becomes harder:
- New script to author and maintain. Bash + jq markdown parsing has
  edge cases (embedded pipe characters in titles, nested quotes,
  strikethrough `~~...~~` markers, child reference row prefix `^`);
  fixture coverage must address these.
- Cross-skill contract to document. The /work-on skill references a
  script path inside /plan. The contract (CLI signature, stdout format)
  needs a short design note in the work-on skill's references so future
  contributors don't break the dependency accidentally.
- /plan's test suite gains a new harness (`plan-to-tasks_test.sh`) and
  associated fixture PLANs.

Follow-up items for the implementation plan:
- Add a prerequisite issue: "feat(plan): add `plan-to-tasks.sh` script
  with CI tests". Must land before the work-on-plan template can
  reference it.
- Update `DESIGN-work-on-koto-unification.md` Decision 2 and Implementation
  Approach Phase 5 to reflect the script-and-pipe flow. Remove any
  remaining prose-parses-PLAN language.
- Document the script's CLI contract in `skills/plan/references/` with a
  schema example of the tasks JSON output, so /work-on's template
  directive is grounded in a canonical reference.
- Verify at implementation time: does `koto next --with-data @-` accept
  stdin? If yes, use the single-pipe form; if not, use the tempfile
  sandwich. The decision holds either way.
<!-- decision:end -->
