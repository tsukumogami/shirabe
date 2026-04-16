---
review: issue2-plan-completion-cascade
files:
  - skills/work-on/koto-templates/work-on-plan.md (plan_completion section)
  - skills/work-on/SKILL.md (Completion Cascade section)
---

## Pragmatic Review

### No blocking findings.

**Advisory 1** — SKILL.md:131–135 prose is a partial duplicate of the template directive.
`work-on-plan.md` lines 214–229 already contain the full directive with the exact command
and status enum. SKILL.md lines 131–135 restate the same content in prose form. This is
acceptable documentation layering (SKILL.md is read by humans orienting to the skill;
the template is executed by the agent), but the SKILL.md prose closely mirrors the
template rather than adding context. Not blocking — it doesn't create dead code or a
contract hazard. Advisory only.

---

## Architect Review

### No blocking findings.

**Advisory 2** — `--push` is hardcoded in the template directive but not explained in the
directive text.
`work-on-plan.md` line 219 calls `run-cascade.sh --push {{PLAN_DOC}}`. The directive adds
a comment "(see `skills/work-on/scripts/run-cascade.sh`)" but does not explain why `--push`
is required here (as opposed to a dry-run). SKILL.md line 131 also omits the rationale.
An agent reading only the directive will execute `--push` correctly, but if it ever needs
to deviate (e.g., dry-run before commit), it has no signal to guide that choice. Advisory.

**No missing output handling.** The directive correctly captures both `cascade_status` and
the full JSON result; all three enum values (`completed | partial | skipped`) are covered by
the template's `accepts` block and all route to `done` — no orphaned output path.

**No delegation gap.** The script's contract (JSON to stdout, exit 0 always on cascade
attempt, exit 1 on path-level failure) is correctly consumed: the directive reads
`cascade_status` from `$RESULT` and submits it. The `cascade_detail` is left to the agent
to summarise — appropriate, since the steps array is available in `$RESULT` and only a
human-readable summary is needed.

---

## Maintainer Review

### Advisory 3 — `cascade_detail` is under-specified.

`plan_completion` in the koto template accepts `cascade_detail: type: string` with the
description "Summary of what the cascade did or why steps were skipped." The directive
(line 223) says to submit "a brief `cascade_detail` summarising what ran" but gives no
guidance on what level of detail to use or where to source it (full `steps` array? first
failed step? count only?). A future developer reading the directive and SKILL.md alone
cannot determine what constitutes an acceptable `cascade_detail`. Advisory — no runtime
breakage, but ambiguous for anyone maintaining or extending this state.

**`run-cascade.sh` is sufficiently explained.** The template's directive (lines 214–223)
names the script, describes what it does (walks upstream frontmatter chain, applies
lifecycle transitions, emits JSON), shows the exact invocation, and references the script
path for deeper reading. SKILL.md lines 132–134 give a one-paragraph description of the
same behaviour. Together they give a future developer a complete mental model without
reading the script itself. No finding.

---

## Summary

| # | Perspective  | Level    | Finding |
|---|-------------|----------|---------|
| 1 | Pragmatic   | Advisory | SKILL.md prose duplicates template directive without adding context |
| 2 | Architect   | Advisory | `--push` flag hardcoded with no rationale in directive or SKILL.md |
| 3 | Maintainer  | Advisory | `cascade_detail` field content is under-specified for future maintainers |

Blocking: 0. Advisory: 3.
