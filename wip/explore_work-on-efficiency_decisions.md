# Exploration Decisions: work-on-efficiency

## Round 1

- **Proceed directly to crystallize**: All 6 leads fully investigated. Coverage is
  sufficient for artifact type selection and design. No meaningful gaps warrant another
  research round.

- **Docs fast path — single template, Option A**: Two-field discrimination at
  `implementation` (`issue_type: docs/code`) preferred over routing state (Option B)
  and separate template (Option C). Why: minimal graph disruption, existing precedent
  in `plan_context_injection`, avoids fork maintenance cost. Cost accepted: agent must
  re-submit `issue_type` at every `implementation` visit (verbosity, not structural
  burden).

- **Plan-backed PR model — Approach a**: Add `pr_status: shared` enum value over
  Approach b (fork to `work-on-plan-backed.md`). Why: ships now, no maintenance burden,
  Approach b's structural enforcement isn't worth duplicating 17 states when all
  plan-backed children share the same mode. Approach c (`is_set` operator) ruled out:
  koto `when` conditions have no existence checks, and the command-gate workaround is
  blocked by empty-string allowlist restriction.

- **Files annotation — optional, auto-add edges**: `**Files**:` annotation in Issue
  Outline is optional (not required for all plans). `plan-to-tasks.sh` auto-adds
  `waits_on` edges (not just warns) when two outlines share a file. Why: required
  would add friction for clean plans; auto-add is safer than an ignorable warning.
  Trade-off accepted: annotation doesn't prevent section-level conflicts.

- **Template consistency CI — all three checks in one script**: Mermaid state-set diff,
  `default_template` existence, workflow name in prose — all as `validate-template-mermaid.sh`.
  Context key directive check (Check 2) deferred: coverage limited by reference-file
  delegation pattern. Why: three high-value, near-zero-maintenance checks add clear
  enforcement; Check 2's false-negative rate makes it not worth adding now.

- **Artifact type — Design Doc**: Requirements were given as input (7 friction points
  from direct execution); the "what to build" is clear. Technical approaches need
  comparison: Option A vs. B vs. C for docs path, Approach a vs. b for PR model,
  where classification happens in the orchestrator. Multiple viable implementation
  paths surfaced. A design doc records these decisions so future contributors don't
  re-litigate them.
