# Exploration Findings: work-on-readiness

## Round 1 Synthesis

### Finding 1: run-cascade_test.sh has no CI job

The test harness exists (5 scenarios, all passing) but no `.github/workflows/*.yml` triggers it. The only work-on-specific CI coverage is:
- Template compilation (`validate-templates.yml`) — structural check only
- Template freshness (`check-templates.yml`) — Mermaid regeneration check
- Eval existence (`check-evals.yml`) — checks the file exists, doesn't run it

`run-cascade_test.sh` is never executed on PRs. A regression in the cascade script would pass CI.

**Severity:** High. The cascade is the most complex script in work-on and the most likely to break on edge cases.

---

### Finding 2: orchestrator_setup is already idempotent — friction #1 is lower priority than assumed

Research showed the directive already handles both cases:
```bash
git checkout impl/$PLAN_SLUG 2>/dev/null || git checkout -b impl/$PLAN_SLUG
gh pr list --head impl/$PLAN_SLUG ... | grep -q . || gh pr create ...
```
Branch and PR collisions are handled silently. Friction #1 is real (no explicit override flag) but the failure mode is graceful, not destructive. It should stay on the list but is not blocking.

---

### Finding 3: plan-to-tasks.sh has three concrete parsing gaps

1. **No name truncation** (friction #2/#8): The slug can be arbitrarily long. koto's name length limit is not enforced. Long issue titles silently produce names that exceed the limit; the koto init fails with an opaque error.

2. **Section-header dependency format unsupported** (friction #4): Single-pr mode extracts deps from `**Dependencies**: Issue N` inline format only. If the PLAN uses a `### Dependencies` section header (which `/plan` produces in some modes), `waits_on` is silently empty.

3. **`<<ISSUE:N>>` placeholders not parsed** (friction #5): The script has no handling for this format. Only `Issue N` natural language is recognized. Since `/plan` uses `<<ISSUE:N>>` in Issue Outlines, dependencies are silently dropped for any PLAN produced by the current `/plan` skill.

Gap #3 is the most serious: it means every PLAN produced by `/plan` in single-pr mode will spawn all children with no dependency ordering, potentially running them in parallel when they need to be serial.

---

### Finding 4: no pre-flight document validation

Validation is distributed and discovery-based. The cascade finds problems mid-run (partial results), and plan-to-tasks finds problems at parse time (exit code 2). Neither checks the full document before starting work.

What's missing:
- No lint script that validates PLAN frontmatter before plan-to-tasks runs
- No CI check that validates PLAN docs have required fields (`schema: plan/v1`, `execution_mode`, `issue_count`)
- No check that `upstream` chains are valid (file exists, is tracked, has correct status)
- DESIGN/PRD/ROADMAP format requirements for the cascade are not validated anywhere

The cascade handles missing/malformed fields gracefully (partial cascade with detail), but a broken upstream chain produces partial output that may not be obvious to the agent reading JSON results.

---

### Finding 5: wip/ directory is not enforced in CI

Tools repo has a CI check that fails PRs if `wip/` contains files. Shirabe's CI has no equivalent. During work-on orchestration, wip/ files accumulate and must be cleaned before merge — but nothing enforces this. A PR with leftover state files would merge silently.

(CLAUDE.md says "CI enforces this check" but no workflow implements it.)

---

### Finding 6: tools repo patterns worth porting

Three specific patterns stand out:

**a. Blocking label pre-flight check** — before any implementation work starts, the skill reads the issue's labels and stops if a blocking label is present (needs-design, needs-prd, etc.). Work-on SKILL.md has language about this but no deterministic enforcement script. An agent could misread labels under context pressure.

**b. AWK-based golden file tests** — tools uses bash+awk tests with expected output files. 80+ tests catch regressions on parsing scripts. plan-to-tasks_test.sh has coverage for the happy path but not edge cases (long names, circular deps, malformed bodies). Adding golden file tests would make the test harness more systematic.

**c. Introspection / staleness phase** — before analysis, tools checks whether the issue's context artifacts are stale (PR merged, issue closed, upstream artifacts changed). Prevents agents from doing implementation work on a stale context. Work-on's `staleness_check` state handles some of this but the directive relies entirely on the agent's judgment rather than a deterministic check.

---

## Open Questions

- Should `<<ISSUE:N>>` be parsed in plan-to-tasks.sh, or should /plan be changed to emit `Issue N` in single-pr mode? (Either works; the question is which is more stable.)
- What is koto's actual name length limit? (Needed to set the truncation threshold in plan-to-tasks.sh.)
- Should the wip/ CI check be added to shirabe now or deferred until the skill is closer to release?

## Decision: Crystallize
