---
complexity: simple
complexity_rationale: Verification task — run the existing eval suite, fix any assertion that regressed against the env-var change. No new code.
---

## Goal

Confirm that the `CLAUDE_SKILL_DIR` → `CLAUDE_PLUGIN_ROOT/skills/work-on`
standardization that landed with this PLAN's parent PR doesn't regress
any work-on eval assertion.

## Context

Commit `5db8575` ("chore(work-on): standardize on CLAUDE_PLUGIN_ROOT
env var") replaced `${CLAUDE_SKILL_DIR}` with
`${CLAUDE_PLUGIN_ROOT}/skills/work-on` in three locations
(`SKILL.md` × 2, `phase-0-context-injection.md` × 1). The committed
state is clean (verified via `grep` against `.gitignore`-respecting
paths), but `scripts/run-evals.sh` spawns a `claude -p` subprocess
that can produce evaluation outputs containing the old name if any
assertion is keyed on `CLAUDE_SKILL_DIR`.

A post-merge eval run is the cheapest way to confirm. If failures
surface, they are either: (a) assertions that check for the old
literal string and need updating, or (b) skill behavior that still
emits the old name (which would be an actual regression to fix).

## Acceptance Criteria

- [ ] `scripts/run-evals.sh work-on` runs end-to-end against the
  merged main branch
- [ ] All current work-on eval assertions pass, OR
- [ ] Any failures are root-caused: assertion stale (update assertion)
  vs. real regression (fix skill in a follow-up PR)
- [ ] Tests pass (run project's test command)
- [ ] CI green

## Dependencies

None — this is a verification task; the env-var fix it verifies has
already landed.

## Downstream Dependencies

None
